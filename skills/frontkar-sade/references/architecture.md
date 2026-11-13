# Architecture: layout, layers, rules

Use this in Phases 4–6. It describes the default **feature modules + shared kernel** layout (decision P04). If the
user picked the layered layout, the "Layered alternative" section at the end maps the same rules onto it.

## Contents
1. Folder layout
2. Layers and import rules (enforced)
3. Data flow
4. Server/client split inside a feature
5. Naming
6. Error model
7. Env and config
8. Route files
9. Layered alternative

---

## 1. Folder layout

```
src/
  app/                          # ROUTING ONLY: thin layouts, pages, route handlers, metadata files
    (public)/                   # route groups by audience or shell
    (app)/                      # authenticated shell
    api/                        # route handlers: webhooks, vitals, health, public BFF endpoints
    layout.tsx  not-found.tsx  error.tsx  global-error.tsx  manifest.ts  robots.ts  sitemap.ts
  features/
    <feature>/                  # e.g. markets, orders, wallet, auth, profile
      index.ts                  # PUBLIC client-safe API (components, hooks, types)
      server.ts                 # PUBLIC server-only API (queries, actions), starts with import 'server-only'
      server/                   # data access: queries.ts ('use cache'), actions.ts ('use server'), tags.ts, mappers.ts
      client/                   # api.ts (client fetchers), queries.ts (TanStack hooks + key factory), store.ts (Zustand)
      components/               # feature UI (server and client components)
      model/                    # types, zod schemas, pure domain logic: the most unit-tested folder
      __tests__/ or *.test.ts   # colocated tests
  shared/
    ui/                         # design-system primitives (shadcn-owned components live here)
    lib/                        # pure helpers: format, money/decimal, dates, cn, assert
    hooks/                      # generic hooks (useMediaQuery, useInterval)
    config/                     # constants, route builders, cacheLife profile names
  platform/                     # infrastructure, one implementation each
    http/                       # the ONE http client, HttpError, retries, auth header injection
    auth/                       # session read/verify (server-only), proxy helpers
    realtime/                   # socket/SSE connection manager
    observability/              # metrics registry, vitals reporter, logger, tracing helpers
    env/                        # env.server.ts, env.client.ts (zod)
    i18n/                       # locale config, dictionaries loader
    query/                      # QueryClient factory + provider
  styles/                       # globals.css with tokens (@theme), fonts
  instrumentation.ts            # OTel + node-only metrics server (dynamic import of instrumentation.node.ts)
  instrumentation-client.ts     # client RUM/error init
  proxy.ts                      # optimistic auth redirects, locale negotiation, headers. Nothing heavy.
tests/e2e/                      # Playwright specs, fixtures, MSW/route mocks
docs/                           # ARCHITECTURE.md, adr/, decisions.yaml, PLAN.md, NOTES.md
```

Why this shape: a feature can be found, owned, tested and deleted as one folder. `app/` stays a routing table a
reviewer can read in a minute. Infrastructure has exactly one implementation, so there's no second HTTP client.

## 2. Layers and import rules (enforced in Q02)

```
app  →  features  →  shared
  ↘        ↓        ↗
      platform
```

| From \ To | app | features/x (public `index`/`server`) | features/x internals | features/y internals | shared | platform |
|---|---|---|---|---|---|---|
| app | – | ✅ | ❌ | ❌ | ✅ | ✅ |
| features/x | ❌ | ✅ (other features' public API only) | ✅ own | ❌ | ✅ | ✅ |
| shared | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ |
| platform | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ |

More rules:

- Anything under `features/*/server/**` and `platform/auth/**` starts with `import 'server-only'`. Client stores and
  hooks live in `client/` and start with `'use client'` where needed.
- Feature-to-feature imports go only through the public API, and are a smell when there are many. Lift shared
  domain into `shared/` or compose in `app/`.
- No cycles (dependency-cruiser `no-circular`).
- `index.ts` exports **client-safe** things only. Server things come from `@/features/x/server`. Mixing them in one
  barrel is how server code leaks into client bundles.

## 3. Data flow

```
Browser ──<Link>/nav──▶ app/route (Server Component, thin)
                          │ awaits inside <Suspense>
                          ▼
                features/x/server/queries.ts   ('use cache' + cacheLife + cacheTag; or uncached in Suspense)
                          │
                          ▼
                platform/http  ──▶ Backend API     (server side: internal URL, auth header from session)

Client island ('use client') ──▶ features/x/client/queries.ts (TanStack) ──▶ platform/http (public URL)
Form / button ──▶ Server Action features/x/server/actions.ts
                    ├─ zod-parse input
                    ├─ authorize (platform/auth, DAL)
                    ├─ call backend via platform/http
                    └─ updateTag / revalidateTag / refresh  → return typed result
Realtime ──▶ platform/realtime ──▶ external store / queryClient.setQueryData ──▶ subscribed components
```

Validation happens at three edges: user input (in the action), backend responses you don't control (Zod in the
mapper, or generated types), and env (at boot).

## 4. Server/client split inside a feature

- `server/queries.ts`: async functions returning **mapped domain types**, never raw wire shapes. Cached ones
  carry `'use cache'`, `cacheLife`, and tags from `tags.ts`. Uncached reads are wrapped in `React.cache` for
  per-request dedupe.
- `server/actions.ts`: `'use server'` at the top. Each action follows parse → authorize → mutate → invalidate →
  return a `Result`. It never throws for an expected failure.
- `client/queries.ts`: a key factory (`marketKeys.all`, `.detail(id)`) and hooks. `staleTime` is set explicitly.
- `components/`: Server Components by default. Client Components are named for their interaction
  (`OrderForm.client.tsx` is optional; the `'use client'` directive is what counts).
- `model/`: zero React, zero IO. Pure functions and schemas, unit-tested to the coverage target.

## 5. Naming

- Components `PascalCase.tsx`, everything else `kebab-case.ts`. Hooks `useX`, stores `useXStore`, actions are
  verbs (`placeOrder`), queries are nouns (`getMarket`, `listOrders`).
- Specific IDs: `marketSymbol`, `orderId`, `userId`, never a bare `id` across boundaries. Units in names when they
  aren't types (`timeoutMs`), but prefer typed values (Decimal, Date).
- No default exports except where Next requires them (page, layout, route files).

## 6. Error model

| Kind | Example | Handling |
|---|---|---|
| Expected, domain | Insufficient balance, validation | Return `{ ok: false, error: { code, message, fieldErrors? } }` from the action. The UI renders it. Not an exception. |
| Expected, not found / unauthorized | Unknown symbol, no session | `notFound()`, `forbidden()`/`unauthorized()` (with `authInterrupts`), or `redirect()` |
| Transport | 5xx, timeout | `HttpError { status, code }` from `platform/http`. Retries for idempotent GETs only (TanStack or the client). The section boundary shows retry. |
| Unexpected | Bugs | Thrown, caught by `catchError` (section) / `error.tsx` (segment) / `global-error.tsx`, reported to Sentry with the route and release |

One `Result<T, E>` type in `shared/lib/result.ts`, used by every action. Never swallow an error silently. Log it
with context once, at the boundary.

## 7. Env and config

- `platform/env/env.server.ts` (`import 'server-only'`) and `env.client.ts` (only `NEXT_PUBLIC_*`), both Zod-parsed
  at import, failing fast with a readable message.
- Server-to-backend traffic uses an internal URL (no `NEXT_PUBLIC_` prefix), and the browser uses the public URL.
  Pick by module (server vs client), not by `typeof window`, where possible.
- Never read `process.env` outside `platform/env`. Lint it (`no-restricted-properties`).

## 8. Route files

- `page.tsx`/`layout.tsx` stay under about 60 lines: they read params as promises, compose feature components inside
  `<Suspense>`, export `generateMetadata`, `generateStaticParams`, and the route config (`instant`,
  `ensureStatic`, `prefetch`).
- Route-only components go in `app/<route>/_components/` (private folder) when no other route uses them.
  Otherwise they belong in a feature.
- Use typed props: `PageProps<'/markets/[symbol]'>` and `LayoutProps<'/(app)'>` (generated by `next typegen`).

## 9. Layered alternative (P04 option 2)

```
src/app  api/  queries/ (+ keys.ts)  stores/  components/<feature>/  ui/  services/ (http, realtime)  lib/  types/  providers/
```

The rules carry over: one HTTP client in `services/`, query keys only in `queries/keys.ts`, `api/` pure functions
with no React, wire types in `types/*.api.type.ts` mapped in `api/`, route-only UI in `app/<route>/_components/`.
Enforce `components → queries → api → services` with the same boundaries lint.
