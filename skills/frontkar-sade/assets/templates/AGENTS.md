<!-- Keep the Next.js managed block (BEGIN/END nextjs-agent-rules) that create-next-app / next dev writes. -->

# <Project>: rules for coding agents

Read `docs/ARCHITECTURE.md` and the ADRs in `docs/adr/` before changing structure, rendering, caching or data
flow. The installed Next.js docs at `node_modules/next/dist/docs/` are the source of truth for framework APIs,
not memory.

## Stack (don't swap; don't add alternatives without an ADR)
<Generated from docs/decisions.yaml: area → library.>

## Layout and boundaries
<The folder tree + import rules. Lint enforces them; don't disable the rule, fix the import.>

## Rules
- Server Components by default. `'use client'` only for state, effects, browser APIs; keep islands small.
- Data access only through `features/*/server` (server-only) and `platform/http`. No raw `fetch` to the backend
  elsewhere.
- Every `'use cache'` has `cacheLife` + tags from the feature's `tags.ts`. Every mutation invalidates what it
  changes (see the ARCHITECTURE.md invalidation table).
- Every Server Action: parse with Zod → authorize → mutate → invalidate → return `Result`.
- Env only through `platform/env`. No secrets in `NEXT_PUBLIC_*`.
- Request APIs (`cookies`, `headers`, `searchParams`, `params`) are awaited as deep as possible, inside
  `<Suspense>`.
- <Domain rules, e.g. money is Decimal end to end; logical CSS properties only (RTL).>
- Comments explain why, in one sentence. No `console.log`, no commented-out code, no `any`.

## Before you commit
`pnpm format:check && pnpm typecheck && pnpm lint && pnpm knip && pnpm test && pnpm build` (whichever exist).
E2E for touched journeys: `pnpm test:e2e`.
Conventional commit messages.
