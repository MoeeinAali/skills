# Recipes: starting code for the foundation (Phase 6)

These are starting points, written against Next 16.4 and current library APIs. Before pasting one, open the doc
named in its header from the installed `node_modules/next/dist/docs/`, and adapt it to the decisions. Each recipe
says which decision enables it. Skip what wasn't chosen.

## Contents
1. next.config.ts
2. Env (X02)
3. Result type and HTTP client
4. Feature data access: cached query, action, tags
5. QueryClient provider (C02)
6. Realtime store (C06)
7. proxy.ts (A01)
8. Health endpoints (D02)
9. Metrics: prom-client on a private port (O02)
10. Web vitals → Prometheus (O01)
11. Security headers and CSP (X01)
12. Vitest (T01/T02)
13. Playwright + instant() (T03)
14. ESLint boundaries (Q02)
15. lefthook (Q03)
16. GitHub Actions (D01)
17. Dockerfile (D02)
18. Theme: light/dark, the Comeback way (U04)
19. Analytics fan-out (G02)
20. Backend adapter with an in-process mock (C07)

---

## 1. next.config.ts
Docs: `03-api-reference/05-config/01-next-config-js/*`
```ts
import type { NextConfig } from 'next'
import { securityHeaders } from './src/platform/security/headers' // security.md §3

const nextConfig: NextConfig = {
  cacheComponents: true,
  partialPrefetching: true,
  reactCompiler: true,
  typedRoutes: true,
  output: 'standalone',
  poweredByHeader: false,
  deploymentId: process.env.DEPLOYMENT_ID,
  serverExternalPackages: ['prom-client'],
  cacheLife: {
    ticker: { stale: 5, revalidate: 5, expire: 60 },
  },
  experimental: {
    // Only for the e2e build that runs @next/playwright instant() against `next start`.
    exposeTestingApiInProductionBuild: process.env.EXPOSE_TESTING_API === '1',
  },
  async headers() {
    // Security headers on everything, plus the cache rules for sw.js and unhashed public/ files (delivery.md §3).
    return [{ source: '/:path*', headers: securityHeaders }]
  },
}

export default nextConfig
```

## 2. Env (X02)
Docs: `02-guides/environment-variables.md`
```ts
// src/platform/env/env.server.ts
import 'server-only'
import { z } from 'zod'

const schema = z.object({
  NODE_ENV: z.enum(['development', 'test', 'production']),
  API_INTERNAL_URL: z.url(),
  SESSION_COOKIE_NAME: z.string().default('sid'),
  METRICS_PORT: z.coerce.number().int().default(9464),
  DEPLOY_ENV: z.enum(['local', 'staging', 'production']).default('local'), // drives noindex, not NODE_ENV
})

export const serverEnv = schema.parse(process.env)
```
```ts
// src/platform/env/env.client.ts: only NEXT_PUBLIC_*, referenced literally so the bundler inlines them
import { z } from 'zod'

export const clientEnv = z
  .object({ NEXT_PUBLIC_API_URL: z.url(), NEXT_PUBLIC_SITE_URL: z.url() })
  .parse({
    NEXT_PUBLIC_API_URL: process.env.NEXT_PUBLIC_API_URL,
    NEXT_PUBLIC_SITE_URL: process.env.NEXT_PUBLIC_SITE_URL, // metadataBase, canonicals, sitemap
  })
```
(`z.url()` is Zod 4. On Zod 3 it's `z.string().url()`.)

## 3. Result type and HTTP client
```ts
// src/shared/lib/result.ts
export type Result<T, E = AppError> = { ok: true; data: T } | { ok: false; error: E }
export interface AppError { code: string; message: string; fieldErrors?: Record<string, string[]> }
```
```ts
// src/platform/http/http-error.ts
export class HttpError extends Error {
  constructor(readonly status: number, readonly code: string, message: string) {
    super(message)
    this.name = 'HttpError'
  }
}
```
```ts
// src/platform/http/client.ts: the ONLY way to call the backend
import { HttpError } from './http-error'

interface RequestOptions extends Omit<RequestInit, 'body'> {
  body?: unknown
  token?: string
  timeoutMs?: number
}

export async function http<T>(baseUrl: string, path: string, opts: RequestOptions = {}): Promise<T> {
  const { body, token, timeoutMs = 10_000, headers, ...init } = opts
  const res = await fetch(new URL(path, baseUrl), {
    ...init,
    headers: {
      Accept: 'application/json',
      ...(body !== undefined && { 'Content-Type': 'application/json' }),
      ...(token && { Authorization: `Bearer ${token}` }),
      ...headers,
    },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: init.signal ?? AbortSignal.timeout(timeoutMs),
  })
  if (!res.ok) {
    const payload = (await res.json().catch(() => null)) as { code?: string; message?: string } | null
    throw new HttpError(res.status, payload?.code ?? 'http_error', payload?.message ?? res.statusText)
  }
  return res.status === 204 ? (undefined as T) : ((await res.json()) as T)
}
```
With OpenAPI (C03), wrap `openapi-fetch`'s `createClient<paths>()` in this module instead, keeping the same error
mapping.

## 4. Feature data access: cached query, action, tags
Docs: `01-getting-started/08-caching.md`, `09-revalidating.md`, `07-mutating-data.md`, `02-guides/data-security.md`
```ts
// src/features/markets/server/tags.ts
export const marketTags = {
  all: 'markets',
  one: (symbol: string) => `market:${symbol}`,
} as const
```
```ts
// src/features/markets/server/queries.ts
import 'server-only'
import { cacheLife, cacheTag } from 'next/cache'
import { http } from '@/platform/http/client'
import { serverEnv } from '@/platform/env/env.server'
import { toMarket, type MarketDto } from './mappers'
import { marketTags } from './tags'

export async function getMarket(symbol: string) {
  'use cache'
  cacheLife('ticker')
  cacheTag(marketTags.all, marketTags.one(symbol))
  const dto = await http<MarketDto>(serverEnv.API_INTERNAL_URL, `/markets/${encodeURIComponent(symbol)}`)
  return toMarket(dto)
}
```
```ts
// src/features/orders/server/actions.ts
'use server'
import { updateTag } from 'next/cache'
import { requireUser } from '@/platform/auth/session'
import { placeOrderInput } from '../model/schemas'
import type { Result } from '@/shared/lib/result'

export async function placeOrder(_prev: unknown, formData: FormData): Promise<Result<{ orderId: string }>> {
  const parsed = placeOrderInput.safeParse(Object.fromEntries(formData))
  if (!parsed.success) {
    return { ok: false, error: { code: 'invalid', message: 'Check the form', fieldErrors: parsed.error.flatten().fieldErrors } }
  }
  const user = await requireUser() // authorize HERE, never only in proxy.ts
  const order = await createOrder(user, parsed.data) // calls the backend through platform/http
  updateTag(`user:${user.id}:orders`)
  return { ok: true, data: { orderId: order.id } }
}
```
(`flatten()` is deprecated in Zod 4 in favour of `z.flattenError(err)`. Use whichever the installed major
supports.)

## 5. QueryClient provider (C02)
Docs: `02-guides/client-side-data-fetching/tanstack-query.md`
```tsx
// src/platform/query/providers.tsx
'use client'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import type { ReactNode } from 'react'

let browserQueryClient: QueryClient | undefined

function makeQueryClient() {
  return new QueryClient({ defaultOptions: { queries: { staleTime: 30_000, retry: 2 } } })
}

function getQueryClient() {
  // Keep server requests isolated and preserve the browser cache across renders.
  if (typeof window === 'undefined') return makeQueryClient()
  browserQueryClient ??= makeQueryClient()
  return browserQueryClient
}

export function QueryProvider({ children }: { children: ReactNode }) {
  return <QueryClientProvider client={getQueryClient()}>{children}</QueryClientProvider>
}
```
Mount it in the nearest layout that has client islands, not necessarily the root.

## 6. Realtime store (C06)
```ts
// src/platform/realtime/create-stream-store.ts (import only from Client Components)
import { useSyncExternalStore } from 'react'

export function createStreamStore<T>(initial: T) {
  let state = initial
  let pending: T | null = null
  let frame = 0
  const listeners = new Set<() => void>()

  // Batch bursts (e.g. 50 order-book deltas/s) into one render per animation frame.
  function push(next: T) {
    pending = next
    if (frame) return
    frame = requestAnimationFrame(() => {
      frame = 0
      if (pending === null) return
      state = pending
      pending = null
      listeners.forEach((l) => l())
    })
  }

  function subscribe(l: () => void) {
    listeners.add(l)
    return () => listeners.delete(l)
  }

  function useStore<S>(select: (s: T) => S): S {
    return useSyncExternalStore(subscribe, () => select(state), () => select(initial))
  }

  return { push, useStore, getState: () => state }
}
```
The connection manager (one socket per tab, reconnect with jittered backoff, heartbeat, resubscribe on reconnect,
pause when `document.hidden`) lives beside it and calls `push`. Make selectors return stable values (primitives
or memoized slices), because `useSyncExternalStore` re-renders on every new reference.

## 7. proxy.ts (A01)
Docs: `01-getting-started/16-proxy.md`, `03-file-conventions/proxy.md`
```ts
// src/proxy.ts: optimistic only; real authorization lives in the DAL and each action
import { NextResponse, type NextRequest } from 'next/server'

const PROTECTED = ['/wallet', '/orders', '/settings']

export function proxy(req: NextRequest) {
  const hasSession = req.cookies.has('sid')
  if (!hasSession && PROTECTED.some((p) => req.nextUrl.pathname.startsWith(p))) {
    const url = new URL('/login', req.url)
    url.searchParams.set('next', req.nextUrl.pathname)
    return NextResponse.redirect(url)
  }
  return NextResponse.next()
}

export const config = {
  matcher: ['/((?!api|_next/static|_next/image|favicon.ico|sw.js|manifest.webmanifest|.*\\.(?:png|svg|jpg|webp|ico)$).*)'],
}
```

## 8. Health endpoints (D02)
With Cache Components a `GET` handler is **prerendered** unless it reads request data, and a static health check
lies. `connection()` makes it run per request.
```ts
// src/app/api/healthz/route.ts
import { connection } from 'next/server'

export async function GET() {
  await connection()
  return Response.json({ status: 'ok' })
}
```
`/api/readyz` also checks critical dependencies (backend reachable, cache handler connected) with a short timeout.

## 9. Metrics: prom-client on a private port (O02)
Docs: `02-guides/instrumentation.md`
```ts
// src/instrumentation.ts
export async function register() {
  if (process.env.NEXT_RUNTIME === 'nodejs') {
    await import('./instrumentation.node')
  }
}
```
```ts
// src/instrumentation.node.ts
import { createServer } from 'node:http'
import { getRegistry } from '@/platform/observability/metrics'

const registry = getRegistry()
const port = Number(process.env.METRICS_PORT ?? 9464)

// Separate port: Prometheus scrapes it inside the cluster; it is never routed publicly.
createServer(async (req, res) => {
  if (req.url !== '/metrics') {
    res.writeHead(404).end()
    return
  }
  res.writeHead(200, { 'Content-Type': registry.contentType })
  res.end(await registry.metrics())
}).listen(port)
```
```ts
// src/platform/observability/metrics.ts
import 'server-only'
import { Histogram, Registry, collectDefaultMetrics } from 'prom-client'

interface Metrics {
  registry: Registry
  webVitals: Histogram<'name' | 'route' | 'rating'>
}

// Next can load this module once per server entry, so pin a single registry on globalThis.
const globalForMetrics = globalThis as typeof globalThis & { __metrics?: Metrics }

function create(): Metrics {
  const registry = new Registry()
  collectDefaultMetrics({ register: registry })
  const webVitals = new Histogram({
    name: 'web_vitals',
    help: 'Core Web Vitals from real users (ms; CLS unitless x1000)',
    labelNames: ['name', 'route', 'rating'],
    buckets: [50, 100, 200, 500, 1000, 2000, 2500, 4000, 8000],
    registers: [registry],
  })
  return { registry, webVitals }
}

export const metrics = (globalForMetrics.__metrics ??= create())
export const getRegistry = () => metrics.registry
```

## 10. Web vitals → Prometheus (O01)
Docs: `02-guides/analytics.md`, `04-functions/use-report-web-vitals.md`
```tsx
// src/platform/observability/web-vitals.tsx
'use client'
import { useParams, usePathname } from 'next/navigation'
import { useReportWebVitals } from 'next/web-vitals'

// Collapse /markets/BTCIRT into /markets/[symbol] so label cardinality stays bounded.
function routeTemplate(pathname: string, params: Record<string, string | string[]>) {
  return Object.entries(params).reduce((path, [key, value]) => {
    const v = Array.isArray(value) ? value.join('/') : value
    return path.replace(v, `[${key}]`)
  }, pathname)
}

export function WebVitals() {
  const pathname = usePathname()
  const params = useParams()
  useReportWebVitals((metric) => {
    const body = JSON.stringify({
      name: metric.name,
      value: metric.name === 'CLS' ? metric.value * 1000 : metric.value,
      rating: metric.rating,
      route: routeTemplate(pathname, params),
    })
    navigator.sendBeacon('/api/vitals', body)
  })
  return null
}
```
```ts
// src/app/api/vitals/route.ts
import { z } from 'zod'
import { metrics } from '@/platform/observability/metrics'

const vital = z.object({
  name: z.enum(['TTFB', 'FCP', 'LCP', 'CLS', 'INP']),
  value: z.number().nonnegative().max(60_000),
  rating: z.enum(['good', 'needs-improvement', 'poor']),
  route: z.string().max(200),
})

export async function POST(req: Request) {
  const parsed = vital.safeParse(await req.json().catch(() => null))
  if (!parsed.success) return new Response(null, { status: 400 })
  const { name, value, rating, route } = parsed.data
  metrics.webVitals.labels(name, route, rating).observe(value)
  return new Response(null, { status: 204 })
}
```
Rate-limit this endpoint at the edge or LB, because it's public and unauthenticated.

## 11. Security headers and CSP (X01)
Docs: `02-guides/content-security-policy.md`

The code lives in `security.md`: `buildCsp` (§2), `securityHeaders` (§3), the `/api/csp-report` route and the
nonce `proxy.ts` for tier C. Start in Report-Only (`Content-Security-Policy-Report-Only`) and switch to enforcing
once the main journey logs no violations.

The trap: `script-src 'self'` alone (no `'unsafe-inline'`, nonce or SRI) blocks Next's inline RSC scripts and
breaks hydration in production. And a hash or nonce next to `'unsafe-inline'` makes browsers ignore
`'unsafe-inline'`. Pick one tier from X01 and verify it in a production build with the browser console open.

## 12. Vitest (T01/T02)
Docs: `02-guides/testing/vitest.md`
```ts
// vitest.config.mts
import { defineConfig } from 'vitest/config'
import react from '@vitejs/plugin-react'
import tsconfigPaths from 'vite-tsconfig-paths'

export default defineConfig({
  plugins: [tsconfigPaths(), react()],
  test: {
    environment: 'jsdom',
    setupFiles: ['./tests/setup.ts'], // @testing-library/jest-dom + MSW server.listen()
    include: ['src/**/*.test.{ts,tsx}'],
    coverage: { provider: 'v8', include: ['src/**/model/**', 'src/shared/lib/**'], thresholds: { lines: 80 } },
  },
})
```
For **Vitest browser mode** (the preferred setup for component tests), split this into two `test.projects`:
`unit` (environment `node`, `src/**/model/**`, `src/shared/lib/**`) and `browser` (`browser: { enabled: true,
provider: playwright(), instances: [{ browser: 'chromium' }] }`, `*.browser.test.tsx`), with
`vitest-browser-react` for `render`. Check the installed Vitest major's browser-mode docs for the exact provider
import. It changed between majors.

Mock `server-only` in tests (`vi.mock('server-only', () => ({}))`) when you unit-test server mappers.

## 13. Playwright + instant() (T03)
Docs: `02-guides/testing/playwright.md`, `02-guides/instant-navigation.md`
```ts
// playwright.config.ts
import { defineConfig, devices } from '@playwright/test'

export default defineConfig({
  testDir: 'tests/e2e',
  fullyParallel: true,
  retries: process.env.CI ? 2 : 0,
  use: { baseURL: 'http://localhost:3000', trace: 'on-first-retry' },
  webServer: {
    command: process.env.CI ? 'pnpm start' : 'pnpm dev', // CI builds with EXPOSE_TESTING_API=1 first
    url: 'http://localhost:3000',
    reuseExistingServer: !process.env.CI,
  },
  projects: [
    { name: 'chromium', use: { ...devices['Desktop Chrome'] } },
    { name: 'mobile', use: { ...devices['Pixel 7'] } },
  ],
})
```
```ts
// tests/e2e/market.spec.ts
import { test, expect } from '@playwright/test'
import { instant } from '@next/playwright'

test('market page shell is instant on client navigation', async ({ page }) => {
  await page.goto('/markets')
  await instant(page, async () => {
    await page.click('a[href="/markets/BTCIRT"]')
    await page.waitForURL((url) => url.pathname === '/markets/BTCIRT')
    await expect(page.getByRole('heading', { level: 1 })).toContainText('BTC')
  })
  await expect(page.getByTestId('order-book')).toBeVisible()
})
```
Add `@axe-core/playwright` checks on the key pages if a11y CI was ticked.

## 14. ESLint boundaries (Q02)
```js
// eslint.config.mjs (excerpt): check plugin docs for the installed major's exact config shape
import boundaries from 'eslint-plugin-boundaries'

export default [
  // ...next, typescript-eslint, jsx-a11y configs
  {
    plugins: { boundaries },
    settings: {
      'boundaries/elements': [
        { type: 'app', pattern: 'src/app/**' },
        { type: 'feature', pattern: 'src/features/*', capture: ['feature'] },
        { type: 'shared', pattern: 'src/shared/**' },
        { type: 'platform', pattern: 'src/platform/**' },
      ],
    },
    rules: {
      'boundaries/element-types': ['error', {
        default: 'disallow',
        rules: [
          { from: 'app', allow: ['feature', 'shared', 'platform'] },
          { from: 'feature', allow: ['feature', 'shared', 'platform'] },
          { from: 'platform', allow: ['shared', 'platform'] },
          { from: 'shared', allow: ['shared'] },
        ],
      }],
      'boundaries/entry-point': ['error', {
        default: 'disallow',
        rules: [{ target: 'feature', allow: ['index.ts', 'server.ts'] }],
      }],
      'no-restricted-properties': ['error', { object: 'process', property: 'env', message: 'Use platform/env.' }],
    },
  },
]
```
(Exempt `src/platform/env/**` and the config files from `no-restricted-properties`. Within a feature, allow
relative imports of its own internals.)

## 15. lefthook (Q03)
```yaml
# lefthook.yml
pre-commit:
  parallel: true
  commands:
    format: { glob: '*.{ts,tsx,js,json,md,css}', run: pnpm prettier --write {staged_files}, stage_fixed: true }
    lint: { glob: '*.{ts,tsx}', run: pnpm eslint --max-warnings=0 {staged_files} }
pre-push:
  commands:
    typecheck: { run: pnpm typecheck }
commit-msg:
  commands:
    commitlint: { run: pnpm commitlint --edit {1} }
```

## 16. GitHub Actions (D01)
Docs: `02-guides/ci-build-caching.md`
```yaml
# .github/workflows/ci.yml
name: ci
on: { pull_request: {}, push: { branches: [main] } }
concurrency: { group: ci-${{ github.ref }}, cancel-in-progress: true }
jobs:
  verify:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with: { node-version-file: .nvmrc, cache: pnpm }
      - run: pnpm install --frozen-lockfile
      - run: pnpm next typegen
      - run: pnpm typecheck
      - run: pnpm lint
      - run: pnpm knip
      - run: pnpm test -- --coverage
      - uses: actions/cache@v4
        with:
          path: .next/cache
          key: next-${{ hashFiles('pnpm-lock.yaml') }}-${{ hashFiles('src/**') }}
          restore-keys: next-${{ hashFiles('pnpm-lock.yaml') }}-
      - run: pnpm build
        env: { EXPOSE_TESTING_API: '1', DEPLOYMENT_ID: '${{ github.sha }}' }
      - run: pnpm exec playwright install --with-deps chromium
      - run: pnpm test:e2e --project=chromium
      - uses: actions/upload-artifact@v4
        if: failure()
        with: { name: playwright-report, path: playwright-report }
```
Pin the action majors to the current ones when you write this. Split it into parallel jobs (lint/type/unit vs
build/e2e) once CI time matters.

## 17. Dockerfile (D02)
Docs: `02-guides/self-hosting.md`, `05-config/01-next-config-js/output.md`
```dockerfile
FROM node:24-alpine AS base
RUN corepack enable
WORKDIR /app

FROM base AS deps
COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

FROM base AS build
COPY --from=deps /app/node_modules ./node_modules
COPY . .
ARG DEPLOYMENT_ID
ARG NEXT_SERVER_ACTIONS_ENCRYPTION_KEY
ENV DEPLOYMENT_ID=$DEPLOYMENT_ID NEXT_SERVER_ACTIONS_ENCRYPTION_KEY=$NEXT_SERVER_ACTIONS_ENCRYPTION_KEY
RUN pnpm build

FROM node:24-alpine AS run
WORKDIR /app
ENV NODE_ENV=production PORT=3000 HOSTNAME=0.0.0.0
RUN addgroup -S app && adduser -S app -G app
COPY --from=build --chown=app:app /app/.next/standalone ./
COPY --from=build --chown=app:app /app/.next/static ./.next/static
COPY --from=build --chown=app:app /app/public ./public
USER app
EXPOSE 3000 9464
CMD ["node", "server.js"]
```
Use the Node LTS current at build time. Pass the encryption key as a build secret in real pipelines rather than an
`ARG`.

## 18. Theme: light/dark, the Comeback way (U04)
Docs: `02-guides/preventing-flash-before-hydration.md`
```tsx
// src/app/layout.tsx (excerpt): runs before first paint; the server never reads the theme, so the shell stays static
import { STORAGE_KEYS } from '@/shared/lib/storage'

const THEME_BOOT_SCRIPT = `try{var t=JSON.parse(localStorage.getItem(${JSON.stringify(STORAGE_KEYS.theme)})).state.theme;if(t)document.documentElement.setAttribute('data-theme',t)}catch(e){}`

export default function RootLayout({ children }: LayoutProps<'/'>) {
  return (
    <html lang="fa" dir="rtl" suppressHydrationWarning>
      <head>
        <script dangerouslySetInnerHTML={{ __html: THEME_BOOT_SCRIPT }} />
      </head>
      <body>{children}</body>
    </html>
  )
}
```
```ts
// src/shared/stores/theme.store.ts
'use client'
import { create } from 'zustand'
import { createJSONStorage, persist } from 'zustand/middleware'
import { STORAGE_KEYS } from '@/shared/lib/storage'

export type Theme = 'light' | 'dark'

interface ThemeState {
  /** undefined follows the OS. */
  theme: Theme | undefined
  setTheme: (theme: Theme | undefined) => void
}

export const useThemeStore = create<ThemeState>()(
  persist(
    (set) => ({
      theme: undefined,
      setTheme: (theme) => {
        if (theme) document.documentElement.setAttribute('data-theme', theme)
        else document.documentElement.removeAttribute('data-theme')
        set({ theme })
      },
    }),
    { name: STORAGE_KEYS.theme, storage: createJSONStorage(() => localStorage), partialize: (s) => ({ theme: s.theme }) },
  ),
)
```
```css
/* globals.css: light tokens in :root; dark for the OS (unless pinned light), for an explicit choice, or a pinned subtree */
:root { --background: #fff; --foreground: #111517; /* … */ }
@media (prefers-color-scheme: dark) {
  :root:not([data-theme='light']) { color-scheme: dark; --background: #111517; --foreground: #f5f7fa; }
}
[data-theme='dark'] { color-scheme: dark; --background: #111517; --foreground: #f5f7fa; }
@theme inline { --color-background: var(--background); --color-foreground: var(--foreground); }
```
With a CSP: in tier A (`'unsafe-inline'`) the boot script just runs. **Don't add its hash**, because a hash makes
browsers ignore `'unsafe-inline'` and Next's own inline scripts stop running. In tier C, pass the request nonce
to the `<script>`. In tier B, verify it isn't blocked, and if it is, the tier isn't viable (`security.md` §2).

## 19. Analytics fan-out (G02)
Docs: `02-guides/third-party-libraries.md`, `02-guides/scripts.md`
```ts
// src/platform/analytics/track.ts: one typed entry point; providers never called directly from features
'use client'
type AnalyticsEvent =
  | { name: 'sign_up'; props: { method: 'otp' | 'google' } }
  | { name: 'order_placed'; props: { market: string; side: 'buy' | 'sell' } }

type Provider = (e: AnalyticsEvent) => void

const providers: Provider[] = [
  (e) => window.gtag?.('event', e.name, e.props),        // GA4 via GTM
  (e) => window.clarity?.('event', e.name),              // Microsoft Clarity
  (e) => window.posthog?.capture(e.name, e.props),       // PostHog
  // (e) => window.yektanet?.(...)                       // local pixel, per its docs
]

export function track(event: AnalyticsEvent) {
  for (const send of providers) {
    try { send(event) } catch { /* a failing vendor must never break the UI */ }
  }
}
```
Load the scripts once in a client `<Analytics />` component mounted in the public layouts only (not auth, wallet or
checkout), using `@next/third-parties/google` `<GoogleTagManager>` and `next/script` for the rest. Declare the
`window` globals in `src/types/analytics.d.ts`. Add every vendor origin to the CSP `script-src`/`connect-src`.

## 20. Backend adapter with an in-process mock (C07)
Contract first: the schemas in `features/*/model/schemas.ts` are the API. The mock implements the same contract.
```ts
// src/platform/backend/types.ts
import type { Market, MarketQuery, Page } from '@/features/markets/model/schemas'

export interface Backend {
  listMarkets(q: MarketQuery): Promise<Page<Market>>
  getMarket(symbol: string): Promise<Market | null>
  // one method per endpoint in docs/API.md
}
```
```ts
// src/platform/backend/index.ts: server-only selection; client islands go through Route Handlers
import 'server-only'
import { serverEnv } from '@/platform/env/env.server'
import type { Backend } from './types'

export async function backend(): Promise<Backend> {
  return serverEnv.BACKEND === 'mock'
    ? (await import('./mock')).mockBackend
    : (await import('./http')).httpBackend
}
```
```ts
// src/platform/backend/mock/index.ts
import 'server-only'
import { faker } from '@faker-js/faker'
import { HttpError } from '@/platform/http/http-error'
import type { Backend } from '../types'
import { applyQuery, makeMarket, paginate } from './helpers' // seeded factories + query helpers

faker.seed(42) // deterministic data: the same screenshots and tests every run
const markets = Array.from({ length: 300 }, () => makeMarket())

// Simulated network: latency always, failures only when MOCK_ERROR_RATE > 0.
async function network() {
  await new Promise((r) => setTimeout(r, faker.number.int({ min: 150, max: 600 })))
  if (Math.random() < Number(process.env.MOCK_ERROR_RATE ?? 0)) throw new HttpError(503, 'unavailable', 'Mock outage')
}

export const mockBackend: Backend = {
  async listMarkets({ q, quote, sort, cursor, limit }) {
    await network()
    // Filter, sort and paginate here like a real API, so the UI can't cheat by loading everything.
    const rows = applyQuery(markets, { q, quote, sort })
    return paginate(rows, cursor, limit)
  },
  async getMarket(symbol) {
    await network()
    return markets.find((m) => m.symbol === symbol) ?? null
  },
}
```
Notes:
- Server data access calls `(await backend()).listMarkets(...)`, so it works in prerender, `use cache` and build
  with no server running. Keep `Math.random`/timers out of cached scopes: the latency simulation runs inside the
  mock, which is called inside `use cache` functions. If the dev overlay flags it, gate it behind `await io()` or
  disable latency during build (`process.env.NEXT_PHASE`).
- Client islands (TanStack, infinite scroll, search) call `app/api/<feature>/route.ts` handlers that delegate to
  the same `backend()`. They are the same contract, and later a thin proxy to the real API.
- Realtime: `app/api/stream/route.ts` returns an SSE `ReadableStream` that emits seeded random-walk updates
  every ~1 s. Call `await connection()` first and stop the interval when `request.signal` aborts.
- Mutations in the mock write to module-level arrays (per server process). That's fine for a demo; say so in
  NOTES.md.
- Tests use MSW handlers built from the same factories (`makeMarket`), so fixtures never drift.
