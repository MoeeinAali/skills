# Quality gates, tests and review

Use this in Phase 4 (plan review), Phases 6–7 (each commit) and Phase 8 (hardening). If the `paranoia` skill is
installed, run it at the checkpoints below as well. This file is the fallback when it isn't, and the
Next.js-specific layer either way.

## Contents
1. Gate commands (what `scripts/gates.sh` runs)
2. Test strategy
3. Plan review checklist (Phase 4)
4. Code review checklist (every slice)
5. Next.js-specific review
6. Hardening checklist (Phase 8)
7. Using paranoia

---

## 1. Gate commands

Expected `package.json` scripts (create them in Phase 5; `gates.sh` runs the ones that exist, in this order):

| Script | Command | Fails on |
|---|---|---|
| `format:check` | `prettier --check .` (or `biome format`) | unformatted files |
| `typecheck` | `next typegen && tsc --noEmit` | any type error (`next build` is not a typecheck gate) |
| `lint` | `eslint . --max-warnings=0` | lint, boundaries, a11y, hooks |
| `knip` | `knip` | unused files, exports or deps |
| `test` | `vitest run` | unit and component failures, coverage below threshold |
| `build` | `next build` | prerender errors, blocking routes, `ensureStatic` violations |
| `test:e2e` | `playwright test` | e2e and `instant()` failures (run against `next start` in CI) |

`scripts/gates.sh` with `--quick` skips build and e2e (use it between edits), and with `--full` runs everything.
Never report a slice done on `--quick` alone.

## 2. Test strategy

| Layer | What | Tool | Rule |
|---|---|---|---|
| Unit | `model/`, `shared/lib/`, mappers, reducers, formatters (money, dates, RTL) | Vitest | TDD. Edge cases: empty, boundary, invalid, locale. About 80% lines. |
| Server logic | actions (parse → authorize → mutate → invalidate), DAL functions | Vitest with mocked `platform/http` + `server-only` mock | Assert on the `Result` and the invalidation calls |
| Component | Client Components' behaviour: forms, toggles, error and empty states | Testing Library (+ MSW) | Query by role and label, not test ids, where possible. No snapshot-only tests. |
| E2E | Each MVP journey happy path + one failure path; instant navigations | Playwright + `@next/playwright` | Against a production build in CI. Mobile and desktop projects. |
| A11y | Key pages | axe in Playwright | Zero serious or critical violations |
| Contract | Generated API types are current | codegen in CI + `git diff --exit-code` | The spec changed and types didn't, so CI fails |

Async Server Components aren't unit-testable with current runners. Test their logic as functions and their
output in e2e.

## 3. Plan review checklist (Phase 4)

- [ ] Every MVP journey in the brief maps to ≥ 1 route in the route map and ≥ 1 slice in PLAN.md.
- [ ] Every route-map row states the static shell, the cached parts (with profile and tags), the dynamic holes,
      the prefetch level and the guard.
- [ ] Every cache tag has a named invalidator (action or webhook). Every mutation names what it invalidates.
- [ ] Nothing user-specific is in a shared `use cache` without the user id in its key, or it uses
      `use cache: private`.
- [ ] Each ADR has real alternatives, a consequence (the cost, not only the benefits) and "how enforced".
- [ ] Decisions don't contradict each other (e.g. a nonce CSP with "static shell everywhere", or static export
      with Server Actions, or Biome with the boundaries plugin).
- [ ] The NFR budgets are numbers, and something measures each one (a CI job, RUM, Lighthouse).
- [ ] "Deliberately out of scope" lists what was skipped and why.
- [ ] The docs read plainly: no padding, no marketing adjectives, no statements that will go stale.

## 4. Code review checklist (every slice)

Language-agnostic rules (adapted from the user's gatekeeper review standards):

**Scope and design**
- Does each new file, abstraction, dependency or flag need to exist? Prefer the simplest thing that covers the
  brief. Speculative generality is a finding.
- Reuse before writing: `shared/ui`, `shared/lib`, `platform/*`. A second HTTP client, key factory, formatter or
  toast wrapper is a finding.
- One source of truth: no duplicated enums, schemas or constants. Derive types from the schema (`z.infer`) or the
  generated API types.
- Fix at the source: validate at the boundary (action input, API mapper), not in every component.
- A perf claim needs a measurement (profile, bundle diff, vitals). Otherwise readability wins.
- No unrelated changes in the slice: drive-by renames, reformatting, refactors. They get their own commit.

**Code**
- Names are specific (`orderId`, not `id`, across boundaries; `priceIrt`, not `value`). No abbreviations a
  newcomer can't decode.
- Define helpers close to their use. No pass-through wrappers. Inline single-use trivial locals.
- No `any`, no unjustified `as`, no `@ts-ignore`. `unknown` + narrowing at boundaries.
- Comments explain **why** (a constraint, a trade-off, a non-obvious invariant) in one plain sentence. Delete
  comments that restate code, narrate history ("was X before"), or list values that will go stale.
- No `console.log`, commented-out code, dead exports (knip) or TODOs without an owner and a follow-up.
- Errors: expected failures are values (`Result`), unexpected ones throw to a boundary. Nothing is swallowed.

**Tests**
- New logic has tests written first. A test fails for the right reason before the fix.
- Tests assert behaviour, not implementation details. Each test sets up its own data, with no shared mutable
  fixtures.

**Self-review**
- Read the whole diff before calling the slice done. AI-written code still needs every line understood: if you
  can't explain a line, it doesn't ship.

## 5. Next.js-specific review

- [ ] `'use client'` only where needed, as low in the tree as possible. Client props are serializable and minimal
      (no whole entities when two fields are used).
- [ ] No request APIs (`cookies`, `headers`, `searchParams`, unknown `params`) awaited above a Suspense boundary
      they don't need to block. Layouts don't await what leaves need.
- [ ] Every `use cache` has a `cacheLife` and tags from the feature's `tags.ts`. Arguments are serializable, and
      no secrets end up in cache keys.
- [ ] Every mutation invalidates the right tags with the right tool (`updateTag` in actions for
      read-your-writes, `revalidateTag(tag,'max')` elsewhere).
- [ ] Every Server Action validates its input and authorizes inside itself. `proxy.ts` isn't the only guard.
- [ ] `server-only` on every DAL module. No server env read in client modules. No secrets in `NEXT_PUBLIC_*`.
- [ ] Loading (skeletons matching the layout), empty, error (`catchError`/`error.tsx` with retry) and not-found
      states exist for each data section.
- [ ] `next/image` with `sizes` and dimensions, `next/font`, `next/link`. No layout shift from late content.
- [ ] Metadata through `generateMetadata`/the static `metadata` export, not hand-written `<head>`.
- [ ] Dev overlay: no blocking-route, blocking-prerender-* or instant-navigation insights on the touched routes.
- [ ] The slice implements its row of the technique map (`techniques.md`): skeletons sized like the content,
      debounced search, the right pagination type, virtualization above the row threshold, optimistic updates
      with rollback, and validation in both places. Each is covered by a test.
- [ ] RTL apps: logical properties only. Formatting goes through `shared/lib/format`.
- [ ] A11y: semantic elements, labels, focus management on dialogs and route changes, 44px touch targets on
      mobile.

## 6. Hardening checklist (Phase 8)

- [ ] `scripts/gates.sh --full` is green on a clean checkout (`rm -rf .next node_modules && pnpm i`).
- [ ] `next analyze`: no unexpected large client modules (date libs, lodash, chart libraries on routes that don't
      chart). `optimizePackageImports` for icon and util libraries where it helps.
- [ ] The vitals on the main journeys meet the budgets (Lighthouse, or a `web-vitals` attribution build).
- [ ] Security headers are present (`curl -I`). The CSP blocks nothing legitimate (browser console). No env
      values in `.next/static` (`grep -r` for secrets).
- [ ] Multi-instance readiness if self-hosting: the encryption key, `deploymentId`, the shared cache decision
      documented, and health and readiness endpoints that return per request.
- [ ] README, ARCHITECTURE.md, the ADRs and AGENTS.md match the code as built.

## 7. Using paranoia

If `paranoia` is installed (any agent's skills dir):

- Phase 4: `paranoia docs/` at `--effort medium` (or `high` if there's time). It catches contradictions between
  ADRs, unjustified choices and slop in the docs.
- After each slice: `paranoia` with no argument reviews the local change. Use `--effort low` between slices and
  `medium` before the user demos.
- Phase 8: `paranoia --effort high` (or `max` if the user asks) on the whole change since scaffold.

Merge its findings with section 4 and 5 results. Fix the blockers before moving on, and list the rest in
`docs/NOTES.md` as follow-ups with a reason.
