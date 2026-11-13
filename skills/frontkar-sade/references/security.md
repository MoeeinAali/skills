# Security

Read this in Phase 3 (decisions X01–X03), Phase 6 step 8, every Phase 7 slice that adds an action, a Route
Handler, a redirect or user-rendered HTML, and Phase 8. Docs: `02-guides/content-security-policy.md`,
`02-guides/data-security.md`, `02-guides/server-actions.md` → Security, `02-guides/authentication.md`,
`05-config/01-next-config-js/{headers,serverActions,taint,images}.md`.

## Contents
1. The threat model for a Next.js frontend
2. CSP: three tiers, and the one rule that breaks apps
3. The other security headers
4. Server Actions are public endpoints
5. Route Handlers: CSRF, CORS, webhooks
6. What reaches the client
7. XSS sinks
8. Sessions and auth flows
9. Redirects, images and SSRF
10. Supply chain and secrets
11. Checks and tests

---

## 1. The threat model for a Next.js frontend

| Threat | Where it enters | Main control |
|---|---|---|
| XSS | `dangerouslySetInnerHTML`, user URLs in `href`, JSON-LD, markdown, third-party scripts | React escaping, sanitising, CSP (§2, §7) |
| Broken access control | Server Actions and Route Handlers that trust the UI | Auth + authorization **inside** every action and DAL call (§4) |
| Data leaking to the client | Props of Client Components, action return values, `use cache` entries | DTOs, `server-only`, taint (§6) |
| CSRF | Cookie-authenticated Route Handlers | Origin checks, `SameSite` cookies (§5). Actions have a built-in check. |
| Clickjacking | Framing the app | `frame-ancestors 'none'` (§2) |
| Open redirect | `?next=` after login | Same-origin path check (§9) |
| SSRF / cost abuse | The image optimizer with broad `remotePatterns` | Narrow patterns (§9) |
| Session theft | Tokens in `localStorage`, missing cookie flags | `httpOnly` `Secure` `SameSite` cookies (§8) |
| Supply chain | npm packages, third-party scripts | Lockfile, audit, few vendors, CSP `connect-src` (§10) |
| Brute force / abuse | OTP, login, search, public APIs | Rate limits at the edge and in the action (§4, §8) |

Say this table in an interview, then show where each control lives in the code.

## 2. CSP: three tiers, and the one rule that breaks apps

**The rule:** Next.js puts inline `<script>` tags in every page (the RSC payload). If `script-src` has no
`'unsafe-inline'`, no nonce and no working hash/SRI setup, hydration breaks in production. And **adding any hash
or nonce to `script-src` makes browsers ignore `'unsafe-inline'`**. So "unsafe-inline plus the hash of my theme
script" silently becomes "hash only", and the app breaks. Pick exactly one tier.

| Tier | `script-src` | Rendering cost | Choose it when |
|---|---|---|---|
| **A. Static-friendly (default with Cache Components)** | `'self' 'unsafe-inline'` + vendor origins | None: the static shell and CDN caching stay | Most apps. The other directives still do real work: no plugins, no `<base>` hijack, no framing, form and `connect-src` allowlists that limit exfiltration. |
| B. SRI (experimental, `experimental.sri`) | `'self'` + vendor origins, integrity hashes on Next's script files | None | You want no `'unsafe-inline'` and can accept an experimental flag. **Verify in a production build** that no inline script is blocked (§11) before relying on it; fall back to A if it is. |
| C. Nonce via `proxy.ts` + `'strict-dynamic'` | `'self' 'nonce-…' 'strict-dynamic'` | **Every page renders per request.** PPR's static shell is incompatible, ISR and CDN caching of HTML are gone. | Compliance demands it, or a wallet/admin app that is fully dynamic anyway. Say the trade-off out loud. |

In every tier:

- `style-src 'self' 'unsafe-inline'`. Radix (shadcn) positioning and `motion` write `style="…"` attributes, and
  nonces don't cover attributes. Style injection is a much smaller risk than script injection.
- `'unsafe-eval'` only in development (React uses it for error stacks).
- `connect-src` lists the API, the WebSocket/SSE origins, and every analytics and Sentry endpoint.
  `worker-src 'self'` and `manifest-src 'self'` with a PWA.
- Roll out with `Content-Security-Policy-Report-Only` first, collect reports, then enforce.

```ts
// src/platform/security/csp.ts (tier A; imported by next.config.ts)
const isDev = process.env.NODE_ENV === 'development'

export function buildCsp({ connect = [], scripts = [], images = [], frames = [] }: {
  connect?: string[]; scripts?: string[]; images?: string[]; frames?: string[]
}) {
  return [
    "default-src 'self'",
    `script-src 'self' 'unsafe-inline'${isDev ? " 'unsafe-eval'" : ''} ${scripts.join(' ')}`,
    "style-src 'self' 'unsafe-inline'",
    `img-src 'self' data: blob: ${images.join(' ')}`,
    "font-src 'self'",
    `connect-src 'self' ${connect.join(' ')}`,
    `frame-src ${frames.length ? frames.join(' ') : "'none'"}`,
    "worker-src 'self'",
    "manifest-src 'self'",
    "object-src 'none'",
    "base-uri 'self'",
    "form-action 'self'",
    "frame-ancestors 'none'",
    'report-uri /api/csp-report',
    'report-to csp',
    ...(isDev ? [] : ['upgrade-insecure-requests']),
  ].join('; ')
}
```

Tier C (only if chosen):

```ts
// src/proxy.ts: a nonce per request. Every page becomes dynamic.
import { NextResponse, type NextRequest } from 'next/server'

export function proxy(request: NextRequest) {
  const nonce = Buffer.from(crypto.randomUUID()).toString('base64')
  const isDev = process.env.NODE_ENV === 'development'
  const csp = [
    "default-src 'self'",
    `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'${isDev ? " 'unsafe-eval'" : ''}`,
    "style-src 'self' 'unsafe-inline'",
    "object-src 'none'", "base-uri 'self'", "form-action 'self'", "frame-ancestors 'none'",
  ].join('; ')
  const requestHeaders = new Headers(request.headers)
  requestHeaders.set('x-nonce', nonce)
  requestHeaders.set('Content-Security-Policy', csp) // Next reads it and stamps its own scripts
  const response = NextResponse.next({ request: { headers: requestHeaders } })
  response.headers.set('Content-Security-Policy', csp)
  return response
}
```
Read the nonce with `(await headers()).get('x-nonce')` and pass it to `next/script`, `<GoogleTagManager nonce>`
and the theme boot script.

The report endpoint:

```ts
// src/app/api/csp-report/route.ts
import { logger } from '@/platform/observability/logger'

export async function POST(request: Request) {
  const body = await request.text()
  if (body.length > 16_384) return new Response(null, { status: 413 })
  logger.warn({ csp: safeJson(body), ua: request.headers.get('user-agent') }, 'csp violation')
  return new Response(null, { status: 204 })
}

function safeJson(text: string) {
  try { return JSON.parse(text) } catch { return { raw: text.slice(0, 500) } }
}
```
Add `Reporting-Endpoints: csp="/api/csp-report"` to the headers. Rate-limit the route at the edge, and sample the
logs, because extensions generate noise.

## 3. The other security headers

```ts
// src/platform/security/headers.ts
import { buildCsp } from './csp'

export const securityHeaders = [
  { key: 'Content-Security-Policy', value: buildCsp({ /* origins from env */ }) },
  { key: 'Reporting-Endpoints', value: 'csp="/api/csp-report"' },
  { key: 'Strict-Transport-Security', value: 'max-age=63072000; includeSubDomains; preload' },
  { key: 'X-Content-Type-Options', value: 'nosniff' },
  { key: 'X-Frame-Options', value: 'DENY' }, // legacy browsers; frame-ancestors is the real control
  { key: 'Referrer-Policy', value: 'strict-origin-when-cross-origin' },
  { key: 'Permissions-Policy', value: 'camera=(), microphone=(), geolocation=(), payment=()' },
  { key: 'Cross-Origin-Opener-Policy', value: 'same-origin' }, // relax to same-origin-allow-popups for OAuth popups
]
```

Plus `poweredByHeader: false`. Only send HSTS `preload` when every subdomain is HTTPS. `COEP: require-corp` is
not a default, because it breaks third-party images and scripts. Add it only if you need cross-origin isolation.

## 4. Server Actions are public endpoints

An action is a POST that anyone can send without your UI. Next gives you: an Origin/Host **CSRF check**, a **1 MB
body limit**, **encrypted, unguessable action IDs**, dead-code elimination of unused actions, and **encrypted
closures**. That is not authorization. Inside every action:

```ts
// src/features/watchlist/server/actions.ts
'use server'
import { z } from 'zod'
import { updateTag } from 'next/cache'
import { requireUser } from '@/platform/auth/session'
import { rateLimit } from '@/platform/security/rate-limit'
import { watchlistRepo } from './repo'
import { tags } from './tags'
import type { Result } from '@/shared/lib/result'

const Input = z.object({ symbol: z.string().regex(/^[A-Z0-9]{2,12}$/) })

export async function addToWatchlist(raw: unknown): Promise<Result<null>> {
  const user = await requireUser()                              // 1. authenticate (throws/redirects)
  await rateLimit(`watchlist:${user.id}`, { limit: 30, windowS: 60 })
  const parsed = Input.safeParse(raw)                           // 2. validate the shape
  if (!parsed.success) {
    return { ok: false, error: { code: 'invalid', message: 'Invalid symbol', fieldErrors: z.flattenError(parsed.error).fieldErrors } }
  }
  await watchlistRepo.add(user.id, parsed.data.symbol)          // 3. authorize by scoping to user.id
  updateTag(tags.userWatchlist(user.id))
  return { ok: true, data: null }                               // 4. return only what the UI renders
}
```

- Take **ids plus the change**, never whole objects. Re-read ownership from the session (`where: { id, ownerId }`).
  Zod checks shape, not ownership.
- Return a DTO, never a raw row: the return value is serialised to the browser.
- Destructive or money-moving actions re-check a recent authentication (step-up, OTP) and fail loudly.
- `serverActions.allowedOrigins` only when a proxy forwards its own host instead of `x-forwarded-host`. List the
  public host, never `*`. Raise `bodySizeLimit` only on the action that uploads.
- Multi-instance: the same `NEXT_SERVER_ACTIONS_ENCRYPTION_KEY` on every instance (`rendering-and-caching.md` §7).
- `unauthorized()`/`forbidden()` with `forbidden.tsx`/`unauthorized.tsx` need `experimental.authInterrupts`.
  Without the flag, redirect or return an error result.

## 5. Route Handlers: CSRF, CORS, webhooks

Route Handlers get **no** built-in CSRF check. For any cookie-authenticated non-GET handler:

```ts
// src/platform/security/same-origin.ts
import 'server-only'
import { HttpError } from '@/platform/http/http-error'

export function assertSameOrigin(request: Request) {
  const origin = request.headers.get('origin')
  const host = request.headers.get('x-forwarded-host') ?? request.headers.get('host') // trust x-forwarded-* only behind your proxy
  if (!origin || new URL(origin).host !== host) throw new HttpError(403, 'csrf', 'Cross-origin request rejected')
}
```

- Also require `Content-Type: application/json` (a plain HTML form can't send it) and use `SameSite=Lax` cookies.
- GET handlers never change state (prefetchers, crawlers and link previews call them).
- **CORS:** none by default (same-origin). If a third party needs the endpoint, answer `OPTIONS` and set
  `Access-Control-Allow-Origin` to an allowlist, never `*` together with credentials.
- **Webhooks** (CMS, payments): verify the HMAC signature over the raw body with `crypto.timingSafeEqual`, reject
  old timestamps (replay), then `revalidateTag(tag, 'max')`.
- Validate query params with Zod and return `400` on failure, not `500`.

## 6. What reaches the client

- Every prop passed to a Client Component is serialised into the HTML and the RSC payload. **It is public.** Pass
  the two fields the island uses, not the user object.
- DAL modules start with `import 'server-only'`. Server env lives in `env.server.ts` (also `server-only`). Only
  `NEXT_PUBLIC_*` reaches the browser, and none of it is a secret.
- `taint: true` in `next.config` enables `experimental_taintObjectReference` / `experimental_taintUniqueValue`. Taint
  the session object and tokens in the DAL so an accidental pass to the client throws.
- `use cache` entries are shared across users. Never read cookies or the session inside them, and never cache a
  personal result under a shared key. Per-user data uses `'use cache: private'` or no cache.
- Sentry `beforeSend` and pino `redact` strip `authorization`, `cookie`, tokens, OTPs, phone numbers.

## 7. XSS sinks

- React escapes text. The sinks are: `dangerouslySetInnerHTML`, `href`/`src` from data, `JSON-LD`, markdown/HTML
  from a CMS, `eval`-like libraries, and third-party scripts.
- HTML from users or a CMS goes through DOMPurify (`isomorphic-dompurify` on the server) with an allowlist, or
  through a markdown renderer that doesn't allow raw HTML.
- URLs from data: allow `https:` (and `mailto:`/`tel:` if needed) only, so `javascript:` never reaches an `href`.
- JSON-LD: escape `<` (`seo-and-sharing.md` §5).
- Add a lint rule (`react/no-danger` as an error, with a reviewed disable per use).

## 8. Sessions and auth flows

- The session lives in an `httpOnly; Secure; SameSite=Lax; Path=/` cookie, ideally `__Host-` prefixed. Tokens
  never go to `localStorage` or to client JS (BFF pattern, decision A01).
- Rotate the session id on login and privilege change. Logout clears the cookie and revokes it server-side.
- `proxy.ts` does optimistic redirects only. The real check is in the DAL and in every action.
- **OTP / login:** rate-limit per phone number and per IP, lock out after N failures, give the same message for
  "unknown user" and "wrong code", expire codes quickly, and never log them.
- Personal pages: `Cache-Control: private, no-store` (Next sets it for dynamic pages) and `noindex`.

## 9. Redirects, images and SSRF

```ts
// src/shared/lib/safe-next-path.ts: for ?next= after login
const BASE = 'http://internal.invalid'

export function safeNextPath(raw: string | null | undefined, fallback = '/'): string {
  if (!raw) return fallback
  try {
    const url = new URL(raw, BASE) // '//evil.com', '/\\evil.com' and 'javascript:' all resolve off-origin
    return url.origin === BASE ? `${url.pathname}${url.search}${url.hash}` : fallback
  } catch {
    return fallback
  }
}
```

- `images.remotePatterns`: exact hostnames and path prefixes, never `**`. Keep `dangerouslyAllowSVG` off, or serve
  SVGs with `contentDispositionType: 'attachment'` and a sandbox CSP.
- Never `fetch` a URL that came from the user on the server. If you must, allowlist the host.

## 10. Supply chain and secrets

- `pnpm install --frozen-lockfile` in CI. `pnpm audit --audit-level high` as a CI job that fails on new highs.
  Renovate or Dependabot with grouped updates.
- pnpm 10 blocks dependency install scripts by default. Approve only what needs them (`pnpm approve-builds`).
- Every third-party script is a full-trust dependency: as few vendors as possible, loaded with `next/script`, kept
  off sensitive routes (auth, wallet, checkout), and listed in the CSP.
- Search the build output for secrets in CI: `grep -rE "$SECRET_PATTERNS" .next/static` must find nothing.
- Secrets come from the environment at runtime, never baked into the Docker image. `.env*` stays in `.gitignore`
  and `.dockerignore`.

## 11. Checks and tests

- **e2e:** `response.headers()` on `/` has the CSP, HSTS, `nosniff` and `frame-ancestors`. A Playwright listener on
  `page.on('console')` fails the test on any "Content Security Policy" message during the main journey (this is
  how you verify tier B).
- **Action and handler tests:** call the action without a session → rejected. With another user's id → not
  found or forbidden. With invalid input → field errors. A cross-origin POST to a Route Handler → `403`.
- **Unit:** `safeNextPath` against `//evil.com`, `/\evil.com`, `https://evil.com`, `javascript:alert(1)` and a
  valid path. The sanitiser against a script payload.
- **CI:** audit, a secret search in the build output, and gitleaks (or similar) on the diff.
- **Manual (Phase 8):** `curl -I` on a static page, a dynamic page and an API route. Check the cookie flags in
  devtools, and that the main journey logs no CSP violations.
