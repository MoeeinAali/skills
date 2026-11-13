# Decision catalogue

Every question the skill asks in Phase 3, in dependency order. Each decision has:

- **Ask:** the question as worded to the user.
- **Options:** at most 4, because the question tool caps it and "Other" is always available. The recommended one
  comes first in the ask; the "Default" line says which it is.
- **Compare:** the trade-offs. Show the table in Full mode, or when the user asks "compare".
- **Recommend when:** the rule that picks the default from the brief. State the reason to the user.
- **Scaffold impact:** what changes in the repo, so the user sees the cost.

Library versions move. Install `@latest` and check the major. If a library named here has been deprecated or
renamed, say so and offer its successor.

## Contents
- Express preset
- F. Optional features checklist (multi-select, ask first)
- P. Project shape: P01–P04
- R. Rendering: R01–R03
- C. Data and caching: C01–C07
- S. State and forms: S01–S03
- U. UI: U01–U06
- A. Auth: A01
- I. i18n / RTL: I01–I02
- T. Testing: T01–T05
- Q. Code quality: Q01–Q04
- D. Delivery: D01–D03
- O. Observability: O01–O04
- X. Security: X01–X02
- W. PWA / TWA / offline: W01–W02
- G. Flags and analytics: G01–G02

---

## Express preset

This is the neutral baseline. **`preferences.md` overrides it** row by row: the user's preferences replace these
defaults, are marked "Preferred", and its "ask per project" rows become questions. Show the merged table,
adjusted by the brief and the domain pack, with a "why" column filled in for this project. Then
ask: "Change anything? Name the rows; everything else is accepted."

| Area | Default | One-line why |
|---|---|---|
| P01 Repo | Single Next app, workspace-ready (pnpm) | No second app in the brief. It splits into a monorepo when an admin app or shared UI appears. |
| P02 PM | pnpm | Strict node_modules, fast, workspace support |
| P03 TS | `strict` + `noUncheckedIndexedAccess` + typed routes | Catches the index and route bugs that reviewers find |
| P04 Architecture | Feature modules + shared kernel, boundaries linted | Scales with team and feature count; enforced seams |
| R01 Rendering | Cache Components (PPR) | Static shell + cached + streamed, per component |
| R02 Prefetch | Partial Prefetching on | One App Shell per route; opt-in deep prefetch |
| R03 React Compiler | On | Auto-memoization; delete most `useMemo`/`useCallback` |
| C01 Server cache | In-memory `use cache`; Redis handler only if multi-pod consistency is required | No infra until it pays |
| C02 Client data | TanStack Query (for islands, realtime, infinite lists) | Cache and invalidation for client-owned data |
| C03 API contract | OpenAPI → generated types + typed fetch; otherwise Zod contracts | One source of truth for wire types |
| C04 Mutations | Server Actions (via DAL), Route Handlers for webhooks/public API | Progressive enhancement, `updateTag` |
| C05 Validation | Zod | Ecosystem default (forms, env, actions) |
| C06 Realtime | Per brief: none / SSE / WebSocket | — |
| C07 No backend | Contract-first + backend adapter with an in-process seeded mock | Works in prerender and build; swap to the real API by env |
| S01 Client state | Zustand (small, per-feature stores) | Minimal, no providers, selector-based |
| S02 URL state | nuqs | Typed, shareable filters, server-readable |
| S03 Forms | React Hook Form + Zod (complex), `useActionState` (simple) | Right tool per form size |
| U01 Styling | Tailwind CSS v4 + CSS variables (tokens) | Fast, tokenized, RTL logical utilities |
| U02 Components | shadcn/ui (owned code) on Radix or Base UI | Accessible primitives, no lock-in |
| U03 Icons / motion | lucide-react + `motion`; `<ViewTransition>` for route transitions | — |
| A01 Auth | Per backend: BFF session cookie against the existing API | Tokens never touch JS |
| I01 i18n | Per brief (next-intl if multi-locale) | — |
| T* Testing | Vitest + Testing Library + MSW; Playwright + `@next/playwright` | Fast unit, real-browser e2e, instant-nav tests |
| Q* Quality | ESLint (next) + Prettier + boundaries + knip, lefthook, commitlint | Enforced, not hoped |
| D* Delivery | GitHub Actions; Docker standalone (or Vercel per brief); Renovate | — |
| O* Observability | Web vitals → `/api/vitals` → Prometheus; prom-client `/metrics`; OTel; Sentry | RUM + server metrics + traces + errors |
| X* Security | Security headers + CSP (no nonce unless required); Zod env | Keeps the static shell |
| W* PWA | Per brief | — |

---

## F. Optional features checklist (ask first, multi-select)

Ask as **four multi-select questions in one round**. Pre-tick (and list first) what the brief implies.

1. **Testing:** Unit tests (Vitest) · Component tests · E2E (Playwright) · Visual regression / Storybook
2. **Delivery:** GitHub Actions CI · Preview deploy per PR · Docker image · Renovate/Dependabot
3. **Ops:** Web vitals reporting · Prometheus `/metrics` (prom-client) · OpenTelemetry tracing · Sentry errors
4. **Product:** PWA (installable/offline) · TWA (Android) · i18n (multi-locale) · RTL (+ Persian/Jalali)

Then a second round if relevant: dark mode · feature flags · product analytics · web push · a11y CI (axe) ·
bundle budget · Lighthouse CI · conventional commits + changesets · Storybook.

Each tick enables the matching decision below. An unticked area is skipped and listed as "deliberately out of
scope" in ARCHITECTURE.md, which shows judgement too.

---

## P. Project shape

### P01. Repo shape
**Ask:** Single app or monorepo?
| Option | Compare | Recommend when |
|---|---|---|
| **Single Next app** | Simplest CI, one lockfile. Can split later. | One deployable, no shared packages yet (most interview briefs) |
| pnpm workspaces + Turborepo | `apps/web`, `apps/admin`, `packages/ui`, `packages/config`. Remote cache, task graph. | ≥ 2 apps or a design system shared across apps |
| Nx | Generators, project graph, module-boundary lint built in | A large org that already uses Nx |
**Scaffold impact:** a monorepo adds `turbo.json`, `pnpm-workspace.yaml`, shared `tsconfig`/`eslint` packages,
and `outputFileTracingRoot` for standalone builds.

### P02. Package manager
| Option | Compare |
|---|---|
| **pnpm** | Strict and content-addressed, best workspaces, CI caching well known |
| bun | Fastest installs, also a test runner. Ecosystem edge cases remain. |
| npm | Zero setup, slower, flat node_modules hides phantom deps |
**Default:** pnpm, unless the team or the brief says otherwise.

### P03. TypeScript strictness
| Option | Compare |
|---|---|
| **strict + `noUncheckedIndexedAccess` + `typedRoutes`** (+ `verbatimModuleSyntax`) | Catches undefined index access and broken links at compile time. Small friction. |
| strict only | The Next default; misses index bugs |
| strict + `exactOptionalPropertyTypes` too | The maximum rigour. Friction with some libraries' types. |
**Scaffold impact:** `tsconfig.json` flags, and `next typegen` in `postinstall`/CI so `PageProps` exists.

### P04. Folder architecture
**Ask:** How should code be organized as the app grows? (Show the trees from `architecture.md` in `preview`.)
| Option | Compare | Recommend when |
|---|---|---|
| **Feature modules + shared kernel** | `src/features/<x>/{server,client,components,model}` with a public `index.ts` per feature, plus `shared/` and `platform/`. Boundaries linted. Ownership maps to features. | Default for large scale. Many features, many devs. |
| Layered by technical type (`api/ queries/ stores/ components/ ui/ lib/`) | Familiar, easy to start. Features smear across folders, and ownership and deletion are harder. (This is the Comeback layout.) | Small-to-medium apps, or a team already used to it |
| Feature-Sliced Design (app/pages/widgets/features/entities/shared) | A formal methodology with strict layer rules, steep for newcomers. Overlaps with the App Router's `app/`. | The team already practises FSD |
**Scaffold impact:** the folder skeleton, path aliases, and the boundary lint config (Q02).

---

## R. Rendering

### R01. App-wide rendering model
Full comparison: `rendering-and-caching.md` §1.
Options: **Cache Components (PPR)** · previous model (route-level, ISR) · SPA mode / static export.
**Recommend:** Cache Components, unless the hosting can't run Node (then static export with CSR), or a hard
dependency breaks under it (then the previous model, written up as a risk).

### R02. Partial Prefetching
| Option | Compare |
|---|---|
| **On (`partialPrefetching: true`)** | One App Shell per route, shared by all links. `prefetch={true}` on high-intent links for URL-specific cached content. Less prefetch traffic. |
| Off | The legacy per-link prefetch. Only for apps that adopted Cache Components before 16.3. |
| Per route (`export const prefetch = 'partial'`) | Incremental adoption. Not needed on a greenfield app. |

### R03. React Compiler
| Option | Compare |
|---|---|
| **On** | Automatic memoization, simpler components, no `useMemo`/`useCallback` noise. Slower builds, measured per app. |
| Off | Faster builds; memoize by hand where profiling shows a need |
**Recommend:** on for greenfield. Mention that build time is the known cost, and check that `babel-plugin-react-compiler`
installs cleanly.

---

## C. Data and caching

### C01. Server cache store
| Option | Compare | Recommend when |
|---|---|---|
| **Default in-memory (per instance)** | Zero infra. Entries per pod, lost on restart. Still drives the static shell and prefetch. | Single instance, or eventual consistency across pods is acceptable |
| Redis via `cacheHandlers` (+ `use cache: remote` where it pays) | Shared across pods, survives restarts. A network hop per lookup. Needs tag coordination. | Multi-pod with rate-limited or slow upstreams, or consistency needs |
| Platform-provided (Vercel, adapter) | Managed, nothing to configure | Deploying to that platform |

### C02. Client data fetching
| Option | Compare | Recommend when |
|---|---|---|
| **TanStack Query** | Query keys, dedupe, retries, infinite queries, optimistic updates, devtools, `setQueryData` from sockets | Any client islands with server data, realtime, infinite scroll |
| SWR | Smaller, simpler API, fewer mutation tools | Light client fetching only |
| None (RSC + Server Actions only) | The least JS. Every refetch is a server round trip, so no live or optimistic client cache. | Content sites, simple CRUD |
**Scaffold impact:** a QueryClient provider with defaults (`staleTime`), a global error handling policy, key
factories per feature, and devtools in dev only.

### C03. API contract and types
| Option | Compare | Recommend when |
|---|---|---|
| **OpenAPI → generated types** (`openapi-typescript` + `openapi-fetch`, or `orval`/`@hey-api/openapi-ts` to generate hooks) | The backend spec is the source of truth. Drift breaks the build. | The backend publishes OpenAPI |
| Hand-written Zod contracts at the edge | Runtime validation of every response, types inferred. Duplicates the backend's knowledge. | No spec, or an untrusted or third-party API |
| tRPC | End-to-end types, no schema files. Needs a TS backend you own. | Next.js is the backend (BFF with a DB) |
| GraphQL (codegen + client) | Flexible queries, fragments colocated. Needs a GraphQL server. | The backend is GraphQL |
Combine: generated types plus Zod parsing at boundaries you don't trust.

### C04. Mutation path
| Option | Compare |
|---|---|
| **Server Actions through the data access layer** | Progressive enhancement, `useActionState`/`useOptimistic`, `updateTag`/`refresh`, no hand-written endpoints. Authorize inside each action. |
| Route Handlers as BFF (`app/api/*`) | An explicit HTTP API (webhooks, mobile clients, third parties). Manual CSRF and validation. |
| The client calls the backend directly (CORS) | Simplest when the backend is the real API. No server hop, but tokens must be handled in the browser. |
**Default:** actions for UI mutations, Route Handlers for webhooks and public endpoints, and direct calls only for
realtime or high-frequency client paths.

### C05. Validation library
| Option | Compare |
|---|---|
| **Zod (v4+)** | The standard: RHF resolver, env, actions, OpenAPI tooling |
| Valibot | Tree-shakeable, tiny client bundle, similar API |
| ArkType | The fastest runtime, TS-like syntax, smaller ecosystem |

### C06. Realtime transport (only if the brief has live data)
| Option | Compare | Recommend when |
|---|---|---|
| **WebSocket (native or the backend's protocol client)** | Bidirectional, low latency, needs a reconnect, backoff and heartbeat layer | Order books, trading, chat, collaborative |
| SSE (`EventSource` / Route Handler stream) | One-way, auto-reconnect, works through proxies, simple | Notifications, feeds, progress |
| Polling (TanStack `refetchInterval`) | Trivial, wasteful at scale, latency = interval | Low-frequency or MVP under a time box |
**Pattern:** one connection manager in `platform/realtime` → per-channel subscriptions → an external store
(`useSyncExternalStore`) or `queryClient.setQueryData`, with updates batched per animation frame. See
`packs/fintech-exchange.md`.

### C07. Backend strategy when the brief has none
Most briefs are business-only. **You design the API contract** (`docs/API.md` + Zod schemas in each feature's
`model/`), derived from the features. Then pick how to stand in for the backend:
| Option | Compare | Recommend when |
|---|---|---|
| **Backend adapter: a `Backend` interface with `mock` (in-process, seeded, latency/error simulation) and `http` implementations, selected by env** | Server Components, prerender and build call the in-process mock directly (no server needs to be running). Client islands reach it through thin Route Handlers. Swap in the real API by changing one env var. | Default. Interviews and greenfield work without an API |
| MSW everywhere (browser worker + Node server) | The same handlers in dev, tests and Storybook. Intercepting server-side fetches inside Next's server needs `instrumentation.ts` wiring and is fragile under prerender. | You need network-level realism and the app is mostly client-fetched |
| Next.js as the real backend (Route Handlers/Actions + SQLite/Postgres via Drizzle) | A real persistence layer. More scope, and it's a backend, not a frontend. | The brief explicitly wants a full-stack app |
| json-server / a separate mock server | Simple REST. Another process to run; no realtime. | Quick throwaway prototypes |
Always: the mock is deterministic (a seeded faker), simulates latency (e.g. 150–600 ms) and error rates behind
flags, and paginates, filters and sorts **on the "server" side** like a real API would, so the UI's server/client
choices are realistic. Realtime is mocked with an SSE Route Handler (or a WS stub) that emits updates. Use MSW in
tests in addition to the adapter.

---

## S. State and forms

### S01. Client state
| Option | Compare | Recommend when |
|---|---|---|
| **Zustand** | Tiny, no provider, selectors, middleware (persist, devtools) | Default for UI and session-local state |
| Jotai | Atomic, great for many independent pieces of state and derived state | Editors, complex dashboards |
| Redux Toolkit | Explicit actions, devtools, RTK Query, heavier | Teams standardized on Redux, complex event logs |
| React Context + URL only | No dependency. Re-render cost at scale. | Tiny apps |
Rule: server data never goes in a client store (it belongs to RSC or TanStack Query). Stores hold UI and session
state.

### S02. URL state
**nuqs** (typed parsers, server cache helpers, shallow updates) vs hand-rolled `useSearchParams`. Default: nuqs
when there are filters, tabs or pagination.

### S03. Forms
| Option | Compare |
|---|---|
| **React Hook Form + Zod resolver** | Uncontrolled and fast, big ecosystem, schema shared with the server action |
| TanStack Form | Fully typed, framework-agnostic, newer |
| Conform | Built for Server Actions and progressive enhancement |
| Native `<form action>` + `useActionState` | No dependency. Good for small forms. |

---

## U. UI

### U01. Styling
| Option | Compare |
|---|---|
| **Tailwind CSS v4 + CSS-variable tokens** | Fast, consistent, logical-property utilities for RTL, zero runtime |
| CSS Modules (+ tokens) | Scoped, plain CSS, more files, no utility drift |
| Panda CSS / vanilla-extract | Type-safe tokens and recipes at build time, more setup |

### U02. Component system
| Option | Compare |
|---|---|
| **shadcn/ui (copied, owned components) on Radix or Base UI primitives** | Accessible, themeable, no runtime lock-in. You maintain the code. |
| Mantine | A batteries-included library with hooks and forms. Its own styling system. |
| MUI | Mature, enterprise, Material look, heavier |
| React Aria Components (headless) + your design | The best a11y and i18n (RTL, calendars), more assembly |

### U03. Icons, motion, transitions
lucide-react + `motion` (default). React `<ViewTransition>` for route and shared-element transitions
(`guides/view-transitions.md`). Respect `prefers-reduced-motion`.

### U04. Theming / dark mode (if ticked)
| Option | Compare |
|---|---|
| **localStorage + pre-paint boot script + `data-theme` tokens (the Comeback way, see `preferences.md`)** | No flash, no server read, so the static shell is kept. Subtrees can pin dark. Follows the OS by default. |
| Cookie-driven theme read on the server | No flash, but reading the cookie in the root layout makes it request-time. Read it inside a Suspense leaf, or apply it with a tiny pre-hydration script (`guides/preventing-flash-before-hydration.md`). |
| `next-themes` (class + script) | Easy, client-side, handles system preference |

### U05. Data-heavy UI (if the brief has big tables or lists)
TanStack Table + TanStack Virtual (default, headless) · AG Grid (enterprise features, heavier) · none.

### U06. Charts (if needed)
| Option | Fits |
|---|---|
| **TradingView `lightweight-charts`** | Financial candles and price series, canvas, tiny |
| Recharts | Dashboard charts, SVG, easy |
| ECharts | Huge datasets, many chart types |
| visx | Custom D3-level visuals |

---

## A. Auth

### A01. Authentication approach
| Option | Compare | Recommend when |
|---|---|---|
| **BFF session: the backend issues tokens, Next keeps them in an httpOnly, Secure, SameSite cookie, server calls attach them** | Tokens never touch JS, works with any backend. You write refresh rotation. | An existing backend with its own auth (most company briefs) |
| Better Auth | A full auth library in your app (DB-backed sessions, OAuth, 2FA, passkeys) | Next.js owns users and the DB |
| Auth.js | OAuth-provider focused, mature. Check maintenance status; it is now stewarded alongside Better Auth. | Many OAuth providers, existing Auth.js knowledge |
| Hosted IdP (Clerk / Auth0 / Keycloak OIDC) | Fastest secure path, vendor cost or ops | The org already has an IdP |
**Always:** `proxy.ts` does only the optimistic redirect (does a cookie exist?). The **data access layer**
verifies the session and authorizes per resource, `import 'server-only'`. Every Server Action re-checks auth.
Read `guides/authentication-with-cache-components.md`: read the session in a Suspense leaf, and pass the user id
into cached functions.

---

## I. i18n / RTL (if ticked)

### I01. i18n library
| Option | Compare |
|---|---|
| **next-intl** | App Router native, ICU messages, typed keys, `[locale]` routing, server and client |
| Custom dictionaries + `app/[lang]` + `next/root-params` | No dependency (the official guide's pattern). You build plurals and formatting. |
| Lingui | Message extraction, compile-time catalogs, small runtime |
With Cache Components, the root param needs `generateStaticParams` listing every locale.

### I02. RTL and locale formatting
- `dir`/`lang` on `<html>` from the locale. **Logical properties only** (`ms-*`, `ps-*`, `start-*`; the lint
  rule bans `ml-*`/`pl-*`/`left-*` in RTL apps).
- Numbers, currency and dates through `Intl` (`fa-IR`, `-u-ca-persian` for Jalali, `-u-nu-latn` when Latin digits
  are required, e.g. prices), wrapped in `shared/lib/format.ts`. Use `date-fns-jalali` only if you need date math.
- Fonts: `next/font/local` (e.g. Vazirmatn) with `display: swap` and a fallback metric-matched font.
- Mirror direction-meaning icons only (arrows), never logos or play icons.

---

## T. Testing (if ticked)

### T01. Unit / integration runner
| Option | Compare |
|---|---|
| **Vitest** | Vite-fast, ESM-native, Jest-compatible API, watch UI. The Next docs have a guide. |
| Jest (`next/jest`) | Mature, more config for ESM, slower |
Note: async Server Components aren't supported by these runners. Test their logic as plain functions and their
UI in e2e (`guides/testing/index.md`).

### T02. Component tests
| Option | Compare |
|---|---|
| **Testing Library on jsdom/happy-dom (Vitest)** | Fast, behaviour-focused queries |
| Vitest Browser Mode (Playwright provider) | A real browser: real layout, events and CSS. Slower. |

### T03. E2E
| Option | Compare |
|---|---|
| **Playwright + `@next/playwright` (`instant()`)** | Multi-browser, parallel, traces, instant-navigation assertions, runs against a prod build in CI |
| Cypress | Great interactive runner, single-tab model, no `instant()` helper |

### T04. Network mocking
**MSW** (default): the same handlers in Vitest, Storybook, the browser in dev before the backend exists, and
Playwright through route mocking or an MSW server. Alternative: Playwright `page.route` only.

### T05. Visual and docs
Storybook (+ interaction tests, + Chromatic) · Playwright screenshot tests · none. Recommend Storybook only when
there's a design system or a team.

Coverage target: about 80% lines on `model/` and `lib/` (pure logic), no target on UI. Write the policy in
`quality-gates.md` terms.

---

## Q. Code quality

### Q01. Lint and format
| Option | Compare |
|---|---|
| **ESLint 9 flat (`eslint-config-next`, typescript-eslint, jsx-a11y) + Prettier** | The richest rules (Next, hooks, a11y, boundaries plugins) |
| Biome | One fast tool for lint and format, fewer plugin rules (no boundaries plugin) |
| oxlint (fast pre-pass) + ESLint (deep rules) + Prettier | Speed plus depth. Two configs. |

### Q02. Architecture enforcement
`eslint-plugin-boundaries` (or `import/no-restricted-paths`) for feature/shared/platform rules (default),
`dependency-cruiser` for graph rules and cycle detection in CI. Add `knip` for unused files, exports and deps.

### Q03. Git hooks
**lefthook** (fast, parallel, one YAML) · husky + lint-staged · none. Hooks run format, lint on staged files, and
typecheck on push. CI is still the gate.

### Q04. Commits and release
Conventional Commits + commitlint (default) · + changesets for versioned packages (monorepo) · none.

---

## D. Delivery (if ticked)

### D01. CI
**GitHub Actions** (default) · GitLab CI. The jobs and caching are in `quality-gates.md` and `recipes.md`.

### D02. Hosting / runtime
| Option | Compare |
|---|---|
| **Docker `output: 'standalone'` on k8s/VM (self-host)** | Full control. You own the cache handler, `deploymentId`, the encryption key, CDN, scaling. |
| Vercel | Every feature at full performance fidelity, previews, zero ops. Vendor cost. |
| Static export | Any static host. No server features. |
| Another platform adapter | Check its adapter's functional fidelity (`guides/deploying-to-platforms.md`) |

### D03. Dependency updates
Renovate (grouping, schedules, automerge for patch) · Dependabot (built into GitHub, simpler).

---

## O. Observability (if ticked)

### O01. Web vitals (RUM)
| Option | Compare |
|---|---|
| **`useReportWebVitals` → `navigator.sendBeacon('/api/vitals')` → Prometheus histograms** (labels: metric, route template, rating; **never the raw URL**) | Self-hosted, joins server metrics in Grafana |
| → analytics vendor (GA4, PostHog) | No backend work, vendor-owned |
| Vercel Speed Insights | Only on Vercel |
Enable `experimental.webVitalsAttribution: ['LCP','INP','CLS']` while debugging.

### O02. Server metrics
| Option | Compare |
|---|---|
| **prom-client: default Node metrics + custom histograms, served on a separate port from `instrumentation.ts` (Node runtime only)** | Not publicly exposed, scraped by Prometheus. The registry is pinned on `globalThis`. `prom-client` goes in `serverExternalPackages`. |
| OpenTelemetry metrics → collector | Vendor-neutral, one pipeline for traces and metrics. More moving parts. |
| None | — |

### O03. Tracing
`@vercel/otel` in `instrumentation.ts` (default, works self-hosted with an OTLP exporter) · manual OTel SDK ·
none. Next emits spans for routes, fetches, `generateMetadata` and render.

### O04. Errors and logs
Sentry (`@sentry/nextjs`, source maps, release = `deploymentId`) · GlitchTip (Sentry-compatible, self-hosted) ·
OTel logs only. Logging: **pino** JSON with a request id. No `console.log` in committed code.

---

## X. Security

### X01. Content Security Policy
| Option | Compare |
|---|---|
| **Header CSP without nonce (strict sources, hashes where needed) + full security headers** | Keeps static rendering and the PPR shell |
| Nonce-based CSP via `proxy.ts` | The strongest inline-script control. **Forces dynamic rendering** for the pages that need it, losing the static shell. |
| SRI (experimental) | Hash-based integrity without dynamic rendering. Experimental. |
Always: HSTS, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy`, `frame-ancestors`,
`poweredByHeader: false`, `import 'server-only'`, React taint APIs for secrets, `serverActions.allowedOrigins`
behind proxies.

### X02. Env validation
A Zod `env.ts` split into server and client schemas, parsed at boot (default), or `@t3-oss/env-nextjs`. Only the
`NEXT_PUBLIC_*` keys the client needs. Build fails on a missing var.

---

## W. PWA / TWA / offline (if ticked)

### W01. PWA level
| Option | Compare |
|---|---|
| **Manifest (`app/manifest.ts`) + icons + a hand-written service worker in `public/sw.js`** (precache the shell and offline page, network-first for navigations, cache-first for hashed assets) | No plugin, works with Turbopack. You own the cache versioning. |
| Serwist (`@serwist/next`, the next-pwa successor) | Workbox strategies and precache manifest. Check Turbopack support for the installed version. |
| + Web Push (VAPID, Server Action to subscribe) | Re-engagement. Needs a backend to store subscriptions. |
| + `experimental.useOffline` | Retries navigations and actions on reconnect; `useOffline()` for a banner |

### W02. TWA (Android)
Bubblewrap (or PWABuilder) → `/.well-known/assetlinks.json` served by a Route Handler or `public/`. The PWA
must pass installability. Native-to-web handoff through query params or `postMessage`, never secrets in
`localStorage`.

---

## G. Flags and analytics (if ticked)

### G01. Feature flags / experiments
`flags` SDK (Vercel's, provider-agnostic, evaluates on the server, precompute for static) · GrowthBook
(open-source, A/B stats) · Unleash (self-hosted) · none. Evaluate on the server and pass the result as a prop, so
flags don't cause layout shift.

### G02. Product analytics
PostHog (self-hostable, flags + analytics) · GA4 through `@next/third-parties` · none. Load third-party scripts
with `next/script` `strategy="lazyOnload"` or through the worker, and account for them in the CSP.
