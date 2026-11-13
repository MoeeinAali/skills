# Next.js 16.x: what's new, what bites, where the docs are

Distilled from the docs bundled with Next.js **16.4.1** (`node_modules/next/dist/docs/`). Once the project is
scaffolded, the installed docs win over this file: run `scripts/find-next-docs.sh` and open the guide named in the
doc map below before you write code in that area. If the installed version is newer, check its upgrade guide for
anything that changed since 16.4.

## Contents
1. The mental model in one screen
2. What changed (15 → 16.4), as API facts
3. Gotchas that fail builds or reviews
4. Scaffolding
5. Doc map: which file to read for which task

---

## 1. The mental model in one screen

- **Static and dynamic are decided per component, not per route.** With **Cache Components**
  (`cacheComponents: true`, the default for new apps), each route prerenders a **static shell**: the static
  markup, the cached (`'use cache'`) output, and the `<Suspense>` fallbacks. The request-time parts stream into
  their Suspense holes. That is **Partial Prerendering (PPR)**, and it is now simply how the App Router renders.
- **Anything request-dependent must be either cached or suspended.** `cookies()`, `headers()`, `searchParams`,
  unknown `params`, uncached fetches and `Date.now()`/`Math.random()` must be wrapped in `<Suspense>`, made
  cacheable (`'use cache'`, with the runtime value passed as an argument), or deferred (`await connection()` /
  `await io()`). Otherwise dev shows a **blocking-route** insight and the build fails.
- **Three cache directives:**
  - `'use cache'`: shared, in-memory by default (or `cacheHandlers.default`), part of the static shell when its
    lifetime allows.
  - `'use cache: private'`: may read cookies and headers. It is never stored on the server, only in the browser
    for the `stale` window, and it can join prefetches.
  - `'use cache: remote'`: a shared durable store through `cacheHandlers.remote` (Redis and the like). Worth its
    network hop only at a high hit rate.

  Every cache entry is scoped to the deployment (the build id / `deploymentId` is in the key).
- **Lifetimes and tags:**
  - `cacheLife(profile)`. The built-in profiles (stale / revalidate / expire): `seconds` 30s/1s/1m, `minutes`
    5m/1m/1h, `hours` 5m/1h/1d, `days` 5m/1d/1w, `weeks` 5m/1w/30d, `max` 5m/30d/1y, `default` 5m/15m/never.
    Custom profiles go in `next.config.ts` → `cacheLife`.
  - `cacheTag(...)` names an entry for invalidation.
  - Pair every `'use cache'` with a `cacheLife`. A very short lifetime (for example `seconds`) keeps the result
    out of the static shell.
- **Three invalidation tools:**
  - `updateTag(tag)`: Server Actions only. Read-your-own-writes: the next request waits for fresh data.
  - `revalidateTag(tag, 'max')`: Actions or Route Handlers. Stale-while-revalidate. The single-argument form is
    deprecated.
  - `refresh()`: Server Actions only. Refreshes the client router without touching the tags.

  `revalidatePath` still exists.
- **Navigation is prefetch-driven.** With **Partial Prefetching** (`partialPrefetching: true`, 16.3+), a `<Link>`
  prefetches one reusable **App Shell** per route. `<Link prefetch={true}>` also resolves that link's
  `params`/`searchParams` and the cached content behind them, at the cost of one server render per link.
- **Route controls** (Server Components only, Cache Components only):
  - `export const instant = true | false | {level}`: dev validation that navigations into the segment produce UI
    immediately.
  - `export const ensureStatic = 'shell' | 'prefetch' | 'navigation' | false`: enforces that a navigation stage
    stays static. `'navigation'` is validated at build.
  - `export const prefetch = 'partial' | 'force-disabled'`: the segment's prefetch ceiling.
- **Deferral primitives:**
  - `await connection()`: wait for a real request. It also blocks prefetch.
  - `await io()` (`next/cache`): mark sync I/O like time, random or sync DB reads. Prefer it over `connection()`.
  - `await prefetch()` / `await navigation()` (`next/cache`): push a subtree into a later navigation stage.
- **Errors and state:**
  - `catchError(Fallback)` (`next/error`) builds component-level error boundaries that understand
    `redirect()`/`notFound()` and offer `retry()`. `error.tsx`/`global-error.tsx` remain the route-level
    boundaries.
  - Cache Components keeps recently visited routes mounted but hidden with React `<Activity>`, so client state
    survives back/forward. Design effects to clean up on hide (`guides/preserving-ui-state.md`).

## 2. What changed (15 → 16.4), as API facts

| Area | Fact |
|---|---|
| Runtime | Node ≥ 20.9, TS ≥ 5.1. Browsers: Chrome/Edge/Firefox 111+, Safari 16.4+. |
| Bundler | **Turbopack is the default** for `dev` and `build`. A custom `webpack()` config **fails the build** unless you pass `--webpack`. `turbopack` is a top-level config key. The filesystem cache is on by default. |
| Request APIs | `params`, `searchParams`, `cookies()`, `headers()` and `draftMode()` are **async only** (sync access was removed). So are the `params`/`id` props of the OG/icon/sitemap generators. |
| Types | `next typegen` (and dev/build) generate the global `PageProps<'/route'>`, `LayoutProps<'/route'>` and `RouteContext<'/route'>` types. `typedRoutes: true` is stable (typed `href`s). |
| Middleware | `middleware.ts` is **deprecated → `proxy.ts`** (`export default function proxy(req)` or a named `proxy`). Proxy runs on the **Node.js runtime**, and setting `runtime` in it throws. Without a `matcher` it runs on every request, static files included. Server Functions are POSTs to their page route, so a matcher change can silently drop Proxy coverage: always authorize inside the action or the data access layer. |
| Caching | `cacheComponents` is top level (`experimental.dynamicIO` and `experimental.useCache` were removed). With it on, the segment configs `dynamic`, `dynamicParams`, `revalidate` and `fetchCache` **are removed**: use `use cache` plus `cacheLife` instead. `experimental.ppr` and `experimental_ppr` were removed (PPR is the default under Cache Components). `unstable_cacheLife`/`unstable_cacheTag` became `cacheLife`/`cacheTag`. |
| Prefetching | `partialPrefetching` (16.3). Leaving it unset with Cache Components logs a warning. The `prefetch` segment export was stabilized in 16.3. Both flags are planned to become always-on in the next major. |
| Root params | `next/root-params`: `import { lang } from 'next/root-params'`, readable from any Server Component (not Client, not Actions, not Route Handlers). With Cache Components, each root param needs ≥ 1 `generateStaticParams` value. `unstable_rootParams` was removed. |
| Lint | `next lint` was **removed**, and `next build` no longer lints. Use the ESLint CLI (`eslint-config-next@16` needs ESLint 9, flat config) or Biome. The `eslint` key in next.config was removed. |
| Build output | The `size` and `First Load JS` columns are gone. Use `next analyze` (the Turbopack bundle analyzer, an interactive UI, can export) for bundle work. |
| React | React 19.2 (canary channel in the App Router): `<ViewTransition>`, `useEffectEvent`, `<Activity>`. **React Compiler** support is stable (`reactCompiler: true`, needs `babel-plugin-react-compiler`), off by default because it costs build time. |
| Config removals | `serverRuntimeConfig`/`publicRuntimeConfig` (use env), AMP, `devIndicators` sub-options. `images.imageSizes` no longer includes 16. |
| Offline | `experimental.useOffline` plus `useOffline()` from `next/offline`: detects connectivity, retries navigations, prefetches and Server Actions after reconnect. |
| Testing | `@next/playwright` `instant()` asserts on what is visible *immediately* on a load or navigation. For production-build CI, build with `experimental.exposeTestingApiInProductionBuild` (env-gated). |
| Ops | `deploymentId` / `NEXT_DEPLOYMENT_ID` give version-skew protection (a hard reload on mismatch). Multi-instance needs the same `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` on every instance and a shared cache handler for consistent caching. `supportsImmutableAssets`. Adapters API (`adapterPath`) for platforms. |
| Agents | `create-next-app` writes `AGENTS.md` with a managed block, which `next dev` keeps current (`agentRules: false` turns it off). `/_next/mcp` is a dev MCP endpoint (routes, errors, logs). The official skills are `next-dev-loop`, `next-cache-components-adoption`/`-optimizer` and `next-partial-prefetching-adoption`/`-optimizer`. |

## 3. Gotchas that fail builds or reviews

1. A cookie or header read in a **layout**, outside Suspense, turns every child route into a blocking route. Read
   it in the leaf that needs it, inside `<Suspense>`, or pass the promise down (`params.then(...)` inside a
   Suspense).
2. `await params` at the top of a dynamic layout without `generateStaticParams` makes the whole layout dynamic.
   Push the await down.
3. `'use cache'` arguments and return values must be serializable. Closures over request data become part of the
   key. Don't read `cookies()` inside plain `'use cache'`: pass the value in, or use `'use cache: private'`.
4. `Date.now()`, `Math.random()` and `crypto.randomUUID()` during prerender raise **blocking-prerender-*** insights.
   Either `'use cache'` them (one value for everyone) or put `await io()` before them inside Suspense.
5. `updateTag` and `refresh` **throw outside Server Actions**. From Route Handlers or webhooks, use
   `revalidateTag(tag, 'max')`.
6. A CSP **nonce** forces dynamic rendering for every page that needs it (the nonce is per request). That cancels
   the static shell. Without a nonce, Next's inline scripts need `'unsafe-inline'` (or SRI, experimental), and
   adding any hash next to `'unsafe-inline'` disables it (`security.md` §2, `guides/content-security-policy.md`).
7. Self-hosted multi-instance setups break three ways if you skip the setup: "Failed to find Server Action" (the
   encryption key differs), stale caches differ per pod (no shared handler or tag coordination), and version skew
   during a rolling deploy (no `deploymentId`).
8. Libraries bundled into several server entries get several module instances. Pin singletons (a prom-client
   `Registry`, DB pools) on `globalThis`, or mark the package `serverExternalPackages`.
9. Bots that can't handle streamed metadata get the page rendered fully at request time. The data sources used in
   prerender must therefore also be reachable at runtime, or bots get 500s.
10. `instant`, `ensureStatic` and `prefetch` exports in a `'use client'` file throw. Keep route files as Server
    Components and push interactivity into children.
11. A barrel `index.ts` that re-exports server and client code drags server-only code toward client bundles. Use
    `import 'server-only'` in the data access layer and separate entry points (see `architecture.md`).
12. `next build` doesn't typecheck everything you think it does, and doesn't lint at all. CI must run
    `tsc --noEmit` and `eslint` as their own steps.

## 4. Scaffolding

`create-next-app` flags (16.4):

- `--ts`, `--tailwind`, `--eslint` | `--biome` | `--no-linter`, `--app`, `--src-dir`, `--import-alias "@/*"`
- `--react-compiler`, `--cache-components` (the default for the App Router), `--turbopack` (default) | `--webpack`
- `--use-pnpm` | `--use-bun` | `--use-npm` | `--use-yarn`, `--empty`, `--skip-install`, `--disable-git`
- `--agents-md` (default) | `--no-agents-md`, `--agent-feedback` | `--no-agent-feedback`, `--yes`

Example for the default senior stack:

```bash
pnpm create next-app@latest web --ts --tailwind --eslint --app --src-dir --import-alias "@/*" \
  --react-compiler --use-pnpm --agents-md --no-agent-feedback --empty
```

Then set in `next.config.ts`: `cacheComponents: true`, `partialPrefetching: true` (set it explicitly),
`typedRoutes: true`, `reactCompiler` per the decision, `output: 'standalone'` if Docker, `deploymentId` from env,
and `poweredByHeader: false`. Run `next typegen` so `PageProps` and `LayoutProps` exist before you write routes.

## 5. Doc map

The paths are relative to `node_modules/next/dist/docs/01-app/`. Read the file before you code the area.

| Task | Read |
|---|---|
| Folder conventions, private `_folders`, route groups, colocation | `01-getting-started/02-project-structure.md` |
| Server vs Client Components, the boundary, passing props | `01-getting-started/05-server-and-client-components.md`, `02-guides/server-and-client-boundary.md` |
| Fetching, streaming, `React.cache`, preloading | `01-getting-started/06-fetching-data.md`, `02-guides/streaming.md` |
| Mutations, Server Actions, forms | `01-getting-started/07-mutating-data.md`, `02-guides/server-actions.md`, `02-guides/forms.md` |
| Caching model | `01-getting-started/08-caching.md`, `03-api-reference/01-directives/use-cache*.md`, `04-functions/cacheLife.md`, `cacheTag.md` |
| Revalidation | `01-getting-started/09-revalidating.md`, `02-guides/how-revalidation-works.md`, `04-functions/updateTag.md`, `revalidateTag.md`, `refresh.md` |
| No Cache Components (previous model) | `02-guides/caching-without-cache-components.md`, `02-guides/incremental-static-regeneration.md` |
| ISR with Cache Components, unknown params, App Shell | `02-guides/incremental-static-regeneration-cache-components.md` |
| Static shell, instant navigation, prefetch tuning | `02-guides/optimizing-the-static-shell.md`, `instant-navigation.md`, `prefetching.md`, `optimizing-prefetching.md`, `keeping-pages-static.md`, `adopting-partial-prefetching.md` |
| Errors | `01-getting-started/10-error-handling.md`, `04-functions/catchError.md`, `03-file-conventions/error.md` |
| Auth | `02-guides/authentication.md`, `02-guides/authentication-with-cache-components.md`, `02-guides/data-security.md` |
| Proxy (middleware) | `01-getting-started/16-proxy.md`, `03-file-conventions/proxy.md` |
| Route Handlers / BFF | `01-getting-started/15-route-handlers.md`, `02-guides/backend-for-frontend.md` |
| Client data fetching | `02-guides/client-side-data-fetching/tanstack-query.md`, `.../swr.md` |
| Interactive UX (optimistic, transitions, pending) | `02-guides/interactive-apps.md`, `02-guides/preserving-ui-state.md`, `02-guides/view-transitions.md` |
| SPA-like apps, static export | `02-guides/single-page-applications.md`, `02-guides/static-exports.md` |
| Metadata, OG, sitemap, robots, JSON-LD | `01-getting-started/14-metadata-and-og-images.md`, `03-file-conventions/01-metadata/*`, `02-guides/json-ld.md` |
| i18n, root params | `02-guides/internationalization.md`, `04-functions/next-root-params.md` |
| CSS, Tailwind, fonts, images | `01-getting-started/11-css.md`, `13-fonts.md`, `12-images.md` |
| Env vars | `02-guides/environment-variables.md` |
| Instrumentation, OTel, analytics, web vitals | `02-guides/instrumentation.md`, `open-telemetry.md`, `analytics.md`, `04-functions/use-report-web-vitals.md`, `05-config/01-next-config-js/webVitalsAttribution.md` |
| PWA, offline | `02-guides/progressive-web-apps.md`, `02-guides/offline-support.md`, `04-functions/use-offline.md`, `03-file-conventions/01-metadata/manifest.md` |
| CSP and security headers | `02-guides/content-security-policy.md`, `05-config/01-next-config-js/headers.md` |
| Testing | `02-guides/testing/{vitest,jest,playwright,cypress}.md`, plus `instant-navigation.md` → "Prevent regressions" |
| Self-hosting, Docker, multi-instance, CDN | `02-guides/self-hosting.md`, `cdn-caching.md`, `deploying-to-platforms.md`, `05-config/01-next-config-js/{output,deploymentId,cacheHandlers}.md` |
| CI build cache, build debugging | `02-guides/ci-build-caching.md`, `02-guides/building.md` (`next build --debug-prerender`) |
| Bundles and memory | `02-guides/package-bundling.md`, `02-guides/memory-usage.md`, `05-config/01-next-config-js/optimizePackageImports.md` |
| Production readiness | `02-guides/production-checklist.md` |
| Agents and MCP | `02-guides/ai-agents.md`, `02-guides/mcp.md` |
| Typed routes, TS plugin | `03-api-reference/05-config/02-typescript.md`, `05-config/01-next-config-js/typedRoutes.md` |

If an exact filename differs in the installed version, run `find node_modules/next/dist/docs -name '<slug>.md'`.
