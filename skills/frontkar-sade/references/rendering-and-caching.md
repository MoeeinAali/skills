# Rendering and caching playbook

Use this in Phase 3 (decisions R01–R04, C01–C05) and Phase 4 (the route map). Rendering and caching are where
seniority shows: each route gets a strategy that follows from its data, and each cache has a lifetime, a tag and
an invalidation path.

## Contents
1. The app-wide model (decision R01)
2. Classify each piece of data
3. The per-route strategy table
4. The cache layers, from browser to origin
5. Invalidation design
6. Route map format (goes in ARCHITECTURE.md)
7. Multi-instance and CDN
8. Answers to "why not just CSR?" / "why not SSR everything?"

---

## 1. The app-wide model (R01)

| Option | What it is | Choose when | Costs |
|---|---|---|---|
| **A. Cache Components + Partial Prefetching (Recommended)** | Each route = static shell + cached islands + streamed dynamic holes. Prefetch loads the App Shell. | Any new App Router app, especially mixed public/personal content and SEO plus app-like navigation. It's the framework default in 16.x. | You must think about Suspense placement and cache lifetimes up front. The dev overlay enforces it, which is good. Some libraries that read request data at module scope need care. |
| B. Previous model (no Cache Components) | Route-level static/dynamic, `fetch` cache options, segment `revalidate`, ISR | Upgrading an older codebase, or a library you depend on breaks under Cache Components | You lose the static shell for mixed routes, and you're on the path the framework is moving away from (both flags become always-on next major). |
| C. SPA mode (mostly client) | Thin server shell, client data fetching (TanStack Query), maybe `output: 'export'` | Behind-login tools with no SEO, a static host with no Node runtime, an existing SPA team | No streaming SSR of data, a slower first paint for data, larger JS. Static export has no Server Actions, proxy, ISR or image optimization. |

Interview framing: "Static and dynamic are decided per component. I prerender everything that's the same for
everyone, cache what's shared but changes, and stream what's personal or live."

## 2. Classify each piece of data

For each entity or view in the brief, fill this in. The answers pick the strategy.

| Question | Values |
|---|---|
| Who sees the same value? | everyone · a segment (locale, plan, region) · one user |
| How fresh must it be? | build-time · hours · minutes · seconds · live push |
| Does SEO need it in the first HTML? | yes · no |
| How expensive or slow is the source? | cheap/fast · slow · rate-limited |
| Who changes it? | editors/CMS (webhook) · this user (mutation) · the market or other users (stream) |

## 3. The per-route strategy table

| Data profile | Strategy (Cache Components) | Primitives |
|---|---|---|
| Same for everyone, rarely changes (marketing, docs, legal) | **Fully static**, optionally `ensureStatic = 'navigation'` to lock it | Plain Server Components, `use cache` + `cacheLife('max'\|'weeks')` |
| Same for everyone, changes over minutes or hours (catalog, news list, coin info) | **Static shell + cached sections**, revalidated by time and tag | `use cache` + `cacheLife('minutes'\|'hours')` + `cacheTag`, `revalidateTag(tag,'max')` from webhooks |
| Many detail pages keyed by param (product/[slug], market/[symbol]) | **ISR with Cache Components**: `generateStaticParams` for the top N, App Shell for the rest, filled in on first visit | `generateStaticParams`, `use cache` keyed by param, fallbacks inside Suspense |
| Per-user but cacheable briefly (dashboard summary, profile) | **Shell + streamed private section** | Read the session outside the cache and pass the user id into `use cache` (shared key), or `use cache: private` + `cacheLife` so it can join prefetches |
| Per-request, must be fresh (balances, orders, cart totals at checkout) | **Streamed dynamic hole** | `<Suspense>` + an uncached fetch through the data access layer; `await connection()` only when it must wait for a real request |
| Live (prices, order book, chat, notifications) | **Server-rendered snapshot + client subscription**. SSR the last snapshot (cached `seconds` or uncached in Suspense), then a Client Component subscribes over WS/SSE and patches an external store | The snapshot via the data access layer; the client gets `useSyncExternalStore` or TanStack Query `setQueryData`, with rAF/throttle batching |
| Highly interactive, no SEO (builders, editors, complex filters after login) | **Client island inside a static shell** | The page shell on the server, the island `'use client'` with TanStack Query; the URL state in `searchParams` (nuqs) |
| Search/filter results from URL | **Shell + Suspense keyed by searchParams**; `<Link prefetch>` resolves cached results before the click | Pass the `searchParams` promise down, `use cache` the search function, `prefetch={true}` on links with high intent |

Rules of thumb:

- Keep the await as deep as possible. A layout should never await what only one leaf needs.
- One `<Suspense>` per independently slow thing, with a skeleton that matches the final layout so CLS stays ~0.
- Use `loading.tsx` for whole-segment fallbacks and inline `<Suspense>` for sections. Use `catchError` for section
  errors and `error.tsx` per segment.
- Use the `instant = true` export on routes whose navigations must feel instant (main tabs, list → detail), and
  cover them with `@next/playwright` `instant()` e2e tests.

## 4. The cache layers, from browser to origin

The caches you can control, top to bottom. Decision C01 is which of these the project uses and how they're
configured.

| # | Layer | What lives there | Controlled by |
|---|---|---|---|
| 1 | **Client router cache** | RSC payloads of visited and prefetched routes, kept for `cacheLife.stale` | `cacheLife` stale, `<Link prefetch>`, `prefetch` segment config, `router.refresh()` / `refresh()` |
| 2 | **Client data cache** (if a client fetching library is used) | Query results for client islands and realtime | TanStack Query `staleTime`/`gcTime`, query-key factories, `invalidateQueries`, `setQueryData` from WS |
| 3 | **Browser HTTP cache / service worker** | Static assets (immutable hashed), images, offline shell | Next sets immutable headers on `_next/static`. The SW strategy if it's a PWA. |
| 4 | **CDN** | Static shell HTML, static prefetches, assets, images | `Cache-Control` from Next; `headers()` in config for custom paths; see `guides/cdn-caching.md` |
| 5 | **Server function cache** | `use cache` entries (in-memory LRU per instance by default) | `cacheLife`, `cacheTag`, `cacheHandlers.default` |
| 6 | **Shared remote cache** | `use cache: remote` entries shared across pods | `cacheHandlers.remote` (Redis, etc.) |
| 7 | **Request memoization** | Dedupes the same call within one render | `React.cache(fn)` for non-fetch data access functions (session lookup, DB call) |
| 8 | **Upstream** | Backend/API's own caching | Out of scope, but note `ETag`/`Cache-Control` you get back |

Choosing between server cache (5/6) and client cache (2) for the same data: server cache when the data feeds SSR,
SEO or the static shell and is shared across users. Client cache when the data is user-driven, polled or pushed,
and only needed after hydration. Using both is fine (SSR the first page, hand it to TanStack Query through
`initialData` or hydration), but there must be **one owner for invalidation**. Write that owner in the route map.

Custom profiles (put them in `next.config.ts` → `cacheLife`) beat magic numbers:

```ts
cacheLife: {
  ticker: { stale: 5, revalidate: 5, expire: 60 },      // market snapshot under the live stream
  catalog: { stale: 300, revalidate: 900, expire: 86400 },
}
```

## 5. Invalidation design

For each mutation in the brief, decide:

| Mutation origin | Tool | Why |
|---|---|---|
| The user edits their own data in a Server Action and must see it immediately | `updateTag('user:{id}:…')` | Read-your-own-writes, no stale flash |
| The user's action affects shared lists others see | `revalidateTag('list:…', 'max')` | Stale-while-revalidate for everyone else |
| A CMS/admin webhook, cron or backend event | Route Handler → `revalidateTag(tag, 'max')` (verify the signature) | `updateTag` is Server Actions only |
| A client island mutating through the API (not an action) | TanStack `invalidateQueries`/optimistic `setQueryData`, plus a server action or route call to `revalidateTag` if SSR data shows it too | Keep both caches coherent |
| Only the current view needs re-rendering, with no tagged data | `refresh()` in the action / `router.refresh()` | Cheapest |

Tag naming: `entity` for collections, `entity:{id}` for items, `user:{id}:entity` for personal data. Keep
the tag builders in one module per feature (`features/x/server/tags.ts`). Never inline the strings.

## 6. Route map format (goes in ARCHITECTURE.md)

```md
| Route | Audience | Strategy | Cached parts (profile · tags) | Dynamic holes | Client reads | Prefetch | SEO | Guards | Notes |
|---|---|---|---|---|---|---|---|---|---|
| `/` | public | static shell | hero, featured (`hours` · `markets`) | user greeting | – | default | index | – | `instant=true` |
| `/markets` | public | shell + cached list | first page (`minutes` · `markets`) | – | `GET /api/markets` (infinite, `s-maxage=5`) | rows `false`, hover → `true` | index; filters canonical → `/markets` | – | — |
| `/markets/[symbol]` | public | ISR + live | header, stats (`ticker` · `market:{symbol}`) | order book (WS island), my orders | SSE `/api/stream/{symbol}` | `prefetch={true}` from list | index + JSON-LD + generated OG | – | top 50 symbols in `generateStaticParams` |
| `/wallet` | user | shell + private | – | balances (uncached), history (`use cache: private` · `minutes`) | `GET /api/wallet/history` (`private, no-store`) | `force-disabled` | noindex | session (proxy + DAL) | `ensureStatic='shell'` |
```

Every row must answer: what's in the static shell, what streams, who invalidates, what the user sees while
waiting, how the client fetches after the first render, and whether search engines should see it.

## 7. Multi-instance and CDN (self-hosted)

Required when more than one Node instance serves the app:

1. `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY`: the same base64 AES key at build on every instance.
2. `deploymentId` (from git SHA or release id), plus routing by deployment at the LB, for skew protection.
3. A shared `cacheHandlers.default`/`remote` (Redis) if cache consistency across pods matters, and tag
   invalidation that reaches every instance (`guides/how-revalidation-works.md` → Multi-Instance).
4. `output: 'standalone'`, graceful shutdown, `/healthz` (liveness) and `/readyz` (readiness) Route Handlers.
5. CDN: cache `/_next/static/*` immutable. Let Next's `Cache-Control` drive HTML. Don't strip `RSC`, `Next-Router-*`
   or `Next-Url` headers from the cache key (see `guides/cdn-caching.md` → "What you must preserve").

## 8. Answers to "why not just CSR?" / "why not SSR everything?"

- **CSR everywhere:** bigger JS, blank or skeleton first paint, worse LCP and SEO, waterfalls on slow mobile
  networks, and every user pays for work that could have been done once. CSR is right for islands of heavy
  interactivity, not for the page.
- **SSR on every request:** the server pays per request for content that's the same for everyone, TTFB depends on
  the slowest upstream, and there's no CDN hit. PPR gives SSR's freshness only where it's needed and a static
  shell elsewhere.
- **SSG everywhere:** stale data and rebuilds per change. ISR and tags fix it without losing the static shell.
