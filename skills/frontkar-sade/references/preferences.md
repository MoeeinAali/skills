# The user's preferences

These are the user's own defaults. **How they apply:** a preference is pre-selected and labelled **(Preferred)**
in the question, and listed first. The alternatives are still shown and compared. If the brief argues against a
preference (for example, the backend has an OpenAPI spec, or there's no Node runtime), say so plainly and
recommend the better fit. The user decides. In the Express table, preferred rows show "Preferred" in the why
column.

Rows marked **ask per project** have no default. Always ask them, with the comparison.

To change a preference, edit this file. `decisions.md` stays the neutral catalogue.

## UI

| Decision | Preferred | Notes |
|---|---|---|
| U01 Styling | **Tailwind CSS v4 + CSS-variable tokens** (`@theme inline` in `globals.css`) | Colours only from tokens, never hex in components |
| U02 Components | **shadcn/ui on Radix** | Owned components in `shared/ui` (or `ui/`). Generated with the shadcn CLI, then adapted. |
| U03 Animation | **motion + GSAP** | `motion` for UI state (sheets, lists, layout, presence). **GSAP** (`gsap` + `@gsap/react` `useGSAP`) for timelines, scroll-driven (ScrollTrigger) and hero sequences. Both are client-only. Respect `prefers-reduced-motion`. Load GSAP plugins with dynamic imports on the routes that use them. |
| U03 Icons | **lucide-react** | One icon library only |
| Toasts | **sonner** | Re-exported from one module (`shared/lib/toast.ts`). Mutation errors are toasted globally (TanStack `MutationCache`), not per hook. |
| U04 Theme | **Light/dark like Comeback** (see below) | Not next-themes |
| U05 Virtualization | **TanStack Virtual** | For any list or table that can exceed about 100 rows. Use TanStack Table with it when it's tabular. |
| U06 Charts | **ask per project** | Recommend from the brief (lightweight-charts for finance, Recharts for dashboards, ECharts for huge data) |

### Dark/light mode, the Comeback way

- Themes are `light | dark | system`. The default is **system**: with no saved choice, CSS follows
  `prefers-color-scheme`.
- The saved choice lives in a Zustand store persisted to `localStorage` (through the project's storage helper and
  key registry, never a raw key string).
- A tiny inline **boot script** in the root layout reads the saved choice and sets `<html data-theme>` before
  first paint, so there's no flash. The theme isn't read on the server, so the root layout stays static and the
  PPR shell isn't broken by a cookie read.
- `globals.css`:
  - `:root` holds the light tokens.
  - `@media (prefers-color-scheme: dark) { :root:not([data-theme='light']) {…dark tokens…} }` covers system dark.
  - `[data-theme='dark'] {…dark tokens…}` covers an explicit choice, **and any subtree can pin itself dark** with
    `data-theme="dark"` (heroes, campaign pages).
  - Page-level-only tokens (accent, brand) go under `:root[data-theme='dark']`.
  - `@theme inline` maps the tokens to Tailwind colours.
  - `color-scheme: dark` sits in the dark blocks.
- The setter updates the store and the `data-theme` attribute together. A `useTheme()` hook returns `undefined`
  until hydrated, so the server and the first client render agree.
- A `ThemeColor` client component syncs `<meta name="theme-color">` (PWA status bar) with the active theme.

## State, data, forms

| Decision | Preferred | Notes |
|---|---|---|
| S01 Client state | **Zustand** | Small stores per feature, selectors, `persist` through the storage helper. Server data never goes in a store. |
| C02 Client data | **TanStack Query** | A key factory registry (one place), explicit `staleTime`, global mutation error toast, `setQueryData` from sockets |
| S03 Forms | **React Hook Form + Zod** | `zodResolver`; the same schema re-validates in the Server Action |
| C05 Validation | **Zod** | Also env and API boundaries |
| HTTP | **Native `fetch` wrapper** | One module (`platform/http` or `services/http.ts`), `HttpError {status, code}`, timeouts, auth header injection. No axios or ky. Even with an OpenAPI spec, use generated **types** with this wrapper (or `openapi-fetch`, which is fetch-based) and keep the same error mapping. |
| S02 URL state / typed params | **ask per project** | Ask whether to use `nuqs` for search params and `typedRoutes` + `PageProps<'/route'>` for typed links and params. Compare with hand-rolled `useSearchParams`. |
| P04 Architecture | **ask per project** | Show feature modules vs layered (Comeback style) with `preview` trees, and recommend from the brief's size |

## Rendering

| Decision | Preferred | Notes |
|---|---|---|
| R01 | **Cache Components (PPR)** | Still check the brief: no Node runtime, or a blocking dependency, changes it |
| R02 | **Partial Prefetching on** | — |
| R03 | **React Compiler on** | Mention the build-time cost. Check it per project. |
| P03 | `strict` + `noUncheckedIndexedAccess` | `typedRoutes` follows the S02 answer |

## Analytics and observability

| Decision | Preferred | Notes |
|---|---|---|
| G02 Analytics | **Google (GA4 via GTM), Microsoft Clarity, PostHog, Yektanet/local pixels**, offered as a multi-select with all four pre-ticked | All are loaded through one `platform/analytics` module: a typed `track(event, props)` that fans out to the enabled providers. Scripts go through `next/script` (`afterInteractive`/`lazyOnload`), or `@next/third-parties` for GTM. Load no analytics script on sensitive routes (auth, wallet, checkout). Add each provider's origins to the CSP. Gate on consent where required. Clarity masks inputs by default; keep it that way. |
| O04 Errors | **Sentry** (`@sentry/nextjs`) | Release = `deploymentId`. Upload source maps in CI, never serve them publicly. |
| O02 Metrics | **prom-client `/metrics`** on a private port from `instrumentation.ts` (registry on `globalThis`, `serverExternalPackages`) | `recipes.md` §9 |
| O01 RUM | **Web vitals → `/api/vitals` → Prometheus** histogram labelled by route template | `recipes.md` §10 |
| O03 Tracing | **OpenTelemetry** (`@vercel/otel`, OTLP exporter) | — |
| Logs | **pino** JSON with a request id | No `console.log` in committed code |

## Testing and quality

| Decision | Preferred | Notes |
|---|---|---|
| T01/T02 | **Vitest browser mode** (Playwright provider) for component tests, Vitest node env for pure logic | Use two Vitest projects: `unit` (node, `model/` and `lib/`) and `browser` (components in real Chromium). MSW for network in both. |
| T03 | **Playwright + `@next/playwright`** (`instant()`), `@axe-core/playwright` | Against a production build in CI |
| Q01 | **ESLint (flat) + Prettier** | eslint-config-next, typescript-eslint, jsx-a11y, boundaries, `prettier-plugin-tailwindcss` |
| Q03/Q04 | **lefthook + commitlint** (Conventional Commits) | — |

## Tooling and delivery

| Decision | Preferred | Notes |
|---|---|---|
| P01/P02 | **pnpm, single app** | Split into a Turborepo monorepo only when a second app or shared package appears |
| D01/D02 | **GitHub Actions + Docker standalone (self-hosted)** | So the multi-instance items apply: encryption key, `deploymentId`, health endpoints, shared cache decision |
| D03 | Renovate | Not chosen explicitly; offer it, don't assume it |
| I01/I02 Locale | **ask per project** | If Persian: RTL, Vazirmatn via `next/font/local`, logical properties, Jalali via `Intl` |
| Dates | **`Intl` only** | Add `date-fns-jalali` only when real date math is needed |
