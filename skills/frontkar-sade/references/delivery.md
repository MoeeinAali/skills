# Delivery: requests, prefetching, HTTP caching, offline and error pages

Read this in Phase 3 (decisions C08, R02, D04, W03), Phase 4 (the route map's request, prefetch and header
columns), Phase 6 steps 2, 4 and 8, and in every slice that adds a read, a mutation, a link list or a Route
Handler. Docs: `02-guides/{server-actions,backend-for-frontend,prefetching,optimizing-prefetching,cdn-caching,
self-hosting,offline-support,progressive-web-apps}.md`, `03-file-conventions/{error,not-found,forbidden}.md`,
`04-functions/catchError.md`.

## Contents
1. Which request path: Server Component, Server Action, Route Handler or client fetch
2. Prerendering and prefetching
3. HTTP cache headers
4. Error pages
5. Offline support
6. Checks and tests

---

## 1. Which request path

| Need | Path | Why |
|---|---|---|
| Page data, SEO content, anything in the first HTML | **Server Component → DAL** (`'use cache'` where shared) | No client JS, cached and tagged, streams |
| A mutation from your own UI (form, toggle, button) | **Server Action** (via the DAL), called directly or as a TanStack `mutationFn` | CSRF check, progressive enhancement, `updateTag`/`refresh` re-renders in the same round trip |
| A read from a client island: infinite pages, search-as-you-type, polling, data after an interaction | **Route Handler `GET`** (`app/api/...`, the BFF) through TanStack Query | GET is cacheable (browser, CDN), parallel, abortable, prefetchable |
| A live stream | **SSE Route Handler** or a WebSocket to the backend | — |
| Public data with CORS on the backend, no secrets (a public market WS, a public CDN JSON) | Client → backend directly | Saves a hop. Only if the API is designed for browsers. |
| Webhooks, a public API for third parties, mobile clients | **Route Handler** (POST) | An explicit HTTP contract (security §5) |

Rules:

- **Don't read through Server Actions.** Next dispatches actions **one at a time per client**, so a search box or
  infinite list on actions queues behind every other action. Actions are POSTs, so nothing caches them and they
  can't be prefetched. Use them for writes.
- `Promise.all` over actions on the client doesn't parallelise. Parallel work goes inside one action, or in a
  Server Component.
- The first page of a client-owned list is read on the server and handed to the island (`initialData` or
  `prefetchQuery` + `HydrationBoundary`). The client only fetches what comes after.
- Both the Route Handler and the Server Component call **the same DAL function**, so validation, auth and caching
  live in one place. The Route Handler is a thin HTTP adapter.
- A same-origin request sends the session cookie by itself. Never copy a token into client JS to call the backend.
- Choosing between an action and a client `fetch` to a Route Handler for a mutation: the action, unless the caller
  isn't your React UI or you need upload progress (actions don't report it).

```ts
// src/app/api/markets/route.ts: a thin GET adapter over the DAL for client islands
import { listMarkets, MarketsQuery } from '@/features/markets/server'

export async function GET(request: Request) {
  const parsed = MarketsQuery.safeParse(Object.fromEntries(new URL(request.url).searchParams))
  if (!parsed.success) return Response.json({ code: 'invalid' }, { status: 400 })
  const page = await listMarkets(parsed.data) // cached + tagged inside the DAL
  return Response.json(page, {
    headers: { 'Cache-Control': 'public, max-age=0, s-maxage=5, stale-while-revalidate=25' },
  })
}
```

## 2. Prerendering and prefetching

**What prerenders.** With Cache Components, `next build` prerenders every route's static shell plus its cached
content, and each param in `generateStaticParams`. Other params render on the first request, and the result is
cached like ISR. `export const instant = true` asserts that navigating to a route is instant, and
`ensureStatic` fails the build if a stage you expected to be static isn't.

- `generateStaticParams` returns the **top N** (popular markets, best-selling products), not everything. Build
  time grows with N, and the tail fills on demand.
- Unknown params: `notFound()` from the DAL result. Don't render an empty page.
- `next build` output is a review artefact: it marks each route static, partial or dynamic. A route that should be
  partial but shows as dynamic means a request API is awaited above a Suspense boundary.

**Prefetch levels (`<Link prefetch>`)**, with Partial Prefetching on:

| Value | Prefetches | Use for |
|---|---|---|
| default / `'auto'` | The route's App Shell, once, shared by every link to it | Most links |
| `true` | Shell + this URL's cached content | High-intent links: the next step of a flow, the top results, primary nav |
| `false` | Nothing until click | Very long link lists (virtualised tables, infinite feeds), links to heavy private routes |
| Hover-to-upgrade (`prefetch={hovered ? true : 'auto'}`) | Shell first, the content on intent | Cards and rows where `true` everywhere would be too much |

- `router.prefetch(href)` for programmatic intent: the first search result, the item under the keyboard cursor,
  the next step after a successful action.
- Segment export `prefetch = 'force-disabled'` for private, expensive routes. Rendering must have no side effects,
  because prefetches render: never count a page view or mark something as read while rendering. Do it in a client
  effect or an action.
- **Client data prefetch:** `queryClient.prefetchQuery` on hover for an island's detail data, and the next page of
  an infinite list when the sentinel gets close (`techniques.md` §3).
- **Resource hints:** `preconnect` (from `react-dom`) to the API and WS origins in the root layout.
  `next/font` preloads fonts, and the LCP image gets `preload` on `next/image`.

## 3. HTTP cache headers

What Next sets, and you can't (or shouldn't) override:

| Response | `Cache-Control` | Notes |
|---|---|---|
| `/_next/static/*` (hashed JS, CSS, fonts, static image imports) | `public, max-age=31536000, immutable` | **Not overridable** in `headers()`. With skew protection the URLs carry `?dpl=`; adapters can serve `/_next/static/immutable/...` instead (16.3, `supportsImmutableAssets`). |
| Fully static page | `s-maxage=31536000` | |
| ISR / cached with revalidation | `s-maxage={revalidate}, stale-while-revalidate={expire - revalidate}` | Driven by `cacheLife` |
| Dynamic page (reads request data) | `private, no-cache, no-store, max-age=0, must-revalidate` | Personal pages stay out of shared caches |
| `/_next/image` | From the source and `images.minimumCacheTTL` | Raise `minimumCacheTTL` for remote images that never change |

What you set:

```ts
// next.config.ts → headers(), alongside the security headers
async headers() {
  return [
    { source: '/:path*', headers: securityHeaders },
    // The service worker must never be cached, or updates stall.
    { source: '/sw.js', headers: [{ key: 'Cache-Control', value: 'no-cache, no-store, must-revalidate' }] },
    // public/ files aren't hashed: cache for a day, then revalidate in the background.
    { source: '/images/:path*', headers: [{ key: 'Cache-Control', value: 'public, max-age=86400, stale-while-revalidate=604800' }] },
    // Only for files whose names change with their content (e.g. /brand/logo.3f2a.svg).
    { source: '/brand/:file*', headers: [{ key: 'Cache-Control', value: 'public, max-age=31536000, immutable' }] },
    ...(process.env.DEPLOY_ENV !== 'production'
      ? [{ source: '/:path*', headers: [{ key: 'X-Robots-Tag', value: 'noindex, nofollow' }] }]
      : []),
  ]
}
```

- Metadata routes (`robots.ts`, `sitemap.ts`, `manifest.ts`, `icon`, `opengraph-image`) get their headers from
  Next. Don't add rules for them.
- Prefer `next/font` and static imports (`import logo from './logo.svg'`), so assets land in `/_next/static` and
  are immutable for free. Put things in `public/` only when they need a stable URL.
- Don't set `Cache-Control` on pages in `headers()`. Let `cacheLife` drive it, so the CDN and Next agree.
- **Route Handlers set their own:** shared data `public, max-age=0, s-maxage=N, stale-while-revalidate=M`
  (browsers revalidate, the CDN absorbs load). Personal data `private, no-store`. SSE `no-cache, no-transform`
  plus `X-Accel-Buffering: no` behind nginx.
- **CDN:** cache by path, honour `s-maxage`, and keep the `rsc`, `next-router-*` and `next-url` headers (and the
  `_rsc` param) in the cache key (`guides/cdn-caching.md`). `revalidateTag` doesn't purge the CDN: call its purge
  API in the same place for the affected paths (HTML and RSC variants), or keep `s-maxage` short.
- **Assets on another domain:** `assetPrefix` (`https://cdn.example.com`) plus `crossOrigin: 'anonymous'`, and the
  CDN origin in CSP `script-src`/`style-src`/`font-src`.
- **Version skew:** `deploymentId` makes a stale tab hard-reload on navigation. Keep the previous deployment's
  `/_next/static` available for a while (or use immutable assets) so open tabs can still lazy-load chunks. If a
  `ChunkLoadError` still reaches an error boundary, reload once (guarded with `sessionStorage`).
- Compression: Next gzips by default. Set `compress: false` when nginx or the CDN compresses (with brotli).

## 4. Error pages

Always built in Phase 6, branded, localised, RTL-aware, and with a way forward (retry, home, search):

| File / API | Catches | Notes |
|---|---|---|
| `catchError` (`next/error`) around a section | One section's error | The rest of the page keeps working. `retry()` re-fetches the section. |
| `error.tsx` per segment | Errors in that segment | Client Component. Props: `error` (with `digest`) and **`retry`** (stable in 16.3; re-fetches and re-renders). `reset` clears without re-fetching. |
| `global-error.tsx` | Errors in the root layout | Renders its own `<html>`/`<body>`, imports its own CSS, applies the theme. Keep it dependency-light. |
| `not-found.tsx` (root + per segment) | `notFound()` and unmatched routes | Real `404` only if thrown before streaming (`seo-and-sharing.md` §2). Offer search and popular links. |
| `global-not-found.tsx` (experimental) | Unmatched URLs with several root layouts | Bypasses layouts, so import fonts, CSS and theme. |
| `forbidden.tsx` / `unauthorized.tsx` | `forbidden()` / `unauthorized()` | Need `experimental.authInterrupts`. |
| An `/offline` page | A navigation with no network (§5) | Static, works without JS. |

```tsx
// src/app/(main)/error.tsx
'use client'
import { useEffect } from 'react'
import { reportError } from '@/platform/observability/report-error'
import { SectionError } from '@/shared/ui/section-error'

export default function Error({ error, retry }: { error: Error & { digest?: string }; retry: () => void }) {
  useEffect(() => { reportError(error) }, [error])
  return <SectionError title="مشکلی پیش آمد" onRetry={retry} reference={error.digest} />
}
```

- Show the `digest` as a support reference, never the message (production messages are generic on purpose).
  The server side reaches Sentry through `onRequestError` in `instrumentation.ts`.
- Expected errors (validation, "not found", "insufficient balance") are **results**, not throws (`architecture.md` →
  error model). Boundaries are for the unexpected.
- A maintenance mode is a flag checked in `proxy.ts` that rewrites to a static `/maintenance` page with `503` and
  `Retry-After`.

## 5. Offline support

Pick a level (decision W03). Each level includes the ones above it.

| Level | What it gives | How |
|---|---|---|
| **L1. Honest connectivity (default for any app)** | A banner, live data marked stale, navigations and actions that wait instead of failing | `experimental.useOffline` + `useOffline()` (`next/offline`), TanStack `onlineManager` (queries pause and refetch on reconnect, mutations pause), the socket state |
| L2. An offline page | Navigating offline shows a branded page, not the browser's dinosaur | A service worker: network-first navigations with an `/offline` fallback, cache-first for `/_next/static` |
| L3. Offline reading | Visited pages and data readable offline | Persisted query cache (`persistQueryClient` + IndexedDB) and cached RSC/HTML for chosen public routes. Rarely worth it. |
| L4. Offline writes | Actions queued and replayed | Background Sync or a local queue with conflict rules. Only when the brief demands it. |

- With `useOffline` on, a failed navigation, RSC fetch, prefetch or Server Action **stays pending and retries**
  when the network returns. Suspense fallbacks and pending buttons should say "offline, waiting" instead of
  looking slow (`useOffline()` in the fallback and next to `useTransition`). TanStack Query fetches follow
  TanStack's own retry policy, not this flag.
- **Finance and other live data:** never show cached prices as current. Keep the last value, grey it out, show
  "last updated 12:04", and disable actions that depend on fresh prices until reconnected.
- Don't cache personal HTML or API responses in the service worker. The next user on a shared device would see
  them, and logout wouldn't clear them.

```js
// public/sw.js: L2. Versioned by the query string the registration passes.
const VERSION = new URL(self.location.href).searchParams.get('v') ?? 'dev'
const SHELL = `shell-${VERSION}`
const STATIC = `static-${VERSION}`
const OFFLINE_URL = '/offline'

self.addEventListener('install', (event) => {
  event.waitUntil(caches.open(SHELL).then((cache) => cache.add(OFFLINE_URL)))
})

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys.filter((k) => k !== SHELL && k !== STATIC).map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  )
})

self.addEventListener('fetch', (event) => {
  const { request } = event
  const url = new URL(request.url)
  if (request.method !== 'GET' || url.origin !== self.location.origin) return

  if (request.mode === 'navigate') {
    event.respondWith(fetch(request).catch(async () => (await caches.match(OFFLINE_URL)) ?? Response.error()))
    return
  }
  if (url.pathname.startsWith('/_next/static/')) {
    event.respondWith(
      caches.open(STATIC).then(async (cache) => {
        const hit = await cache.match(request)
        if (hit) return hit
        const response = await fetch(request)
        if (response.ok) cache.put(request, response.clone())
        return response
      }),
    )
  }
})
```

```tsx
// src/platform/pwa/service-worker.tsx: mounted once in the root layout
'use client'
import { useEffect } from 'react'

export function ServiceWorker({ version }: { version: string }) {
  useEffect(() => {
    if (process.env.NODE_ENV !== 'production' || !('serviceWorker' in navigator)) return
    navigator.serviceWorker.register(`/sw.js?v=${version}`, { scope: '/', updateViaCache: 'none' })
  }, [version])
  return null
}
```

- `version` is the `deploymentId`, so every deploy installs a new worker and drops the old caches.
- `/offline` is a static page that reads nothing, says what's happening, and has a retry link. It must look right
  without JS (its CSS may not be cached yet), so keep it simple.
- The worker never touches POSTs, cross-origin requests, `/api/*` or RSC requests (those aren't navigations and
  don't match `/_next/static`).
- CSP needs `worker-src 'self'` and `manifest-src 'self'`. `/sw.js` is served `no-cache` (§3).

## 6. Checks and tests

- **Requests:** a unit test of each Route Handler adapter (`400` on bad params, the right `Cache-Control`). An e2e
  test that typing in search fires debounced GETs, not actions.
- **Prefetch:** `@next/playwright` `instant()` on the key navigations. No blocking-route or instant-navigation
  insights in the dev overlay.
- **Headers:** `curl -I` on `/_next/static/...` (immutable), a static page (`s-maxage`), a dynamic page
  (`private, no-store`), an API route, `/sw.js` (`no-cache`).
- **Errors:** e2e for a missing detail page (`404`, the branded page), a section that throws (the rest of the page
  renders, retry works), and `global-error` (a forced throw in a test-only route).
- **Offline:** Playwright `context.setOffline(true)`: the banner shows, live values are marked stale, a navigation
  shows `/offline` (L2), and an action completes after `setOffline(false)` (with `useOffline`).
