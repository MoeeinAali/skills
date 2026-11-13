---
name: frontkar-sade
description: Design and build a large-scale, production-grade Next.js (App Router, 16.x) frontend from zero, the way a senior frontend engineer would. It first interviews the user about the product and every tech choice (rendering, caching, data layer, state, UI, auth, i18n/RTL, testing, CI, PWA/TWA, web vitals, Prometheus metrics, security, deployment), comparing the options and recommending one, then writes ADRs and a rendering/caching map, scaffolds the repo, and builds it in reviewed, tested vertical slices. Use it whenever someone wants to start, bootstrap, scaffold or architect a new Next.js / React frontend, gets a project brief for a take-home or live coding interview, says "build this app with Next.js", "set up a senior-level frontend", "choose a stack for this project", or asks for SSR/CSR/PPR, caching or architecture decisions on a greenfield app, even if they never say "architect".
---

# Frontkar Sade

Build a new Next.js frontend from a project brief, at the level a senior engineer is judged on: every choice is
deliberate, written down with its trade-off, enforced by tooling, and verified by tests and builds. The user
picks; you lay out the options, compare them and recommend one.

The work runs in phases. Don't skip ahead. A decision made after the code exists costs a rewrite, and a decision
nobody wrote down can't be defended in a review or an interview.

```
0 Preflight → 1 Brief → 2 Mode → 3 Decisions → 4 Architecture docs + review
→ 5 Scaffold → 6 Foundation → 7 Feature slices (loop) → 8 Hardening → 9 Handoff
```

## Reference files: read them when the phase needs them

| File | Read it |
|---|---|
| `references/preferences.md` | Phase 0, and again for every Phase 3 question. **The user's own defaults.** They pre-select options and override the neutral catalogue. |
| `references/decisions.md` | Phase 3. The catalogue: every question, its options, the comparison and the recommendation rule. |
| `references/nextjs-16.md` | Before Phase 3, then again before writing any routing, rendering, caching or config code. What changed in Next 15/16, and a map of the bundled docs. |
| `references/rendering-and-caching.md` | Phase 3 (rendering and caching rounds) and Phase 4 (the route map). |
| `references/architecture.md` | Phases 4 to 6. Folder layout, layer and import rules, naming, error model, env. |
| `references/recipes.md` | Phase 6. Starting code for the HTTP client, env, providers, metrics, vitals, CSP, Docker and CI. |
| `references/quality-gates.md` | Phases 4 and 6 to 8. Test strategy, gate commands, and the review checklist. |
| `references/packs/<domain>.md` | When the brief matches a domain: `fintech-exchange`, `ecommerce`, `dashboard-saas`, `content-media`. |
| `assets/templates/*` | Phase 4. ADR, ARCHITECTURE.md, the project's AGENTS.md, and the `decisions.yaml` schema. |
| `scripts/find-next-docs.sh` | Locates `node_modules/next/dist/docs` and prints the Next version. |
| `scripts/gates.sh` | Runs the project's quality gates in order and stops at the first failure. |

## How to ask questions

If an `AskUserQuestion`-style tool is available, use it. It takes 1–4 questions per call and 2–4 options per
question, and the user can always type "Other". Put the recommended option first and add "(Recommended)" to its
label. Use `multiSelect` for the optional-features checklist. Use the option `preview` field for side-by-side
comparisons of code or folder trees. Without such a tool, ask in plain text with numbered options, mark the
recommended one, and accept answers like `3b, 4a`.

The user is often under time pressure, for example in a live interview. So:

- Never ask what you can infer from the brief. Write the inference down as an assumption the user can reject.
- Batch related questions: up to four per round.
- Every option carries a one-line consequence, so the user knows what they are buying.
- A recommendation is tied to this brief ("Recommended because the order book updates 10×/s"), not to taste.

## Phase 0: Preflight (no questions)

1. Check the tools: `node -v` (Next 16 needs ≥ 20.9; prefer the current LTS), `pnpm -v`/`bun -v`/`npm -v`, `git`,
   and `gh auth status` if GitHub CI is likely. Note anything missing; don't install global tools without asking.
2. Find the target directory. If it already holds a project, stop and ask whether to work inside it.
3. Check for the user's review skills: `paranoia` (any agent's skills dir, e.g. `~/.claude/skills/paranoia`). It is
   optional. Without it, Phase 4 and 8 reviews use `references/quality-gates.md` alone.
4. Read `references/preferences.md`. These are the user's defaults for most decisions.
5. Read `references/nextjs-16.md`. Your training data predates parts of Next 16. That file lists what changed and
   where the bundled docs live, and Phase 5 makes the installed docs the source of truth.

## Phase 1: Brief

Ask the user to paste the project definition, or point to a file. Extract the following and play it back as a
short **Product Brief** for confirmation:

- product and users (roles, who is anonymous and who is logged in)
- the feature list as user journeys, each tagged MVP or Later
- the entities and their source (an existing REST/GraphQL backend with or without OpenAPI, a BaaS, or none, so we
  mock it)
- the shape of the data: how fresh it must be (static, minutes, seconds, live push), how personal (public,
  per-segment, per-user), how big (list sizes, update rate)
- the non-functional needs: SEO, traffic and scale, locales/RTL, devices (mobile-first? installable?),
  accessibility level, security and compliance, the browsers that must work
- the constraints: the time box, team size, must-use or must-avoid tech, the hosting target
- the deliverable: what "done" means for this session (demo-able MVP? architecture plus two slices?)

If the brief matches a domain pack, read it now. Its defaults change several recommendations.

Then ask the scoping questions you could not infer, in **one** round: the time box, the backend situation, the
hosting target, the must-have deliverable.

## Phase 2: Mode

Ask once:

- **Express (Recommended when time-boxed):** you show the full recommended stack for this brief as one table
  (area → choice → why), with the user's preferences filled in and marked "Preferred", plus the optional-features
  checklist. The "ask per project" decisions are asked as separate questions. The user changes only what they disagree with.
  It takes 2–3 rounds.
- **Full:** walk every area in `references/decisions.md` round by round, each option with its comparison table.
  It takes about 10–12 rounds. Use it when the user wants to learn or defend every choice.

In both modes the user may ask "compare X vs Y" on any line. Answer with that decision's comparison table, then
re-ask.

## Phase 3: Decisions

Read `references/decisions.md` and `references/rendering-and-caching.md`. Work through the areas in the order the
catalogue gives, because later areas depend on earlier ones (for example, the rendering model constrains caching,
auth and CSP). For each area:

1. Start from `references/preferences.md`. A preferred option is listed first and labelled **(Preferred)**, and
   the alternatives are still compared. Then check it against the brief and the earlier answers. If the brief
   argues for something else, say why and recommend that instead, while keeping the preferred option visible. If
   an option conflicts with an earlier answer, say so and name the dependency. Decisions marked "ask per
   project" have no default: always ask them.
2. Ask, with the options, the comparison and the recommendation.
3. Record the answer in a running `decisions.yaml` (schema: `assets/templates/decisions.yaml`).

The **optional-features checklist** (decision `F01`) is a multi-select. Ask it early in Express mode, because it
adds rounds: PWA → offline strategy, Prometheus → metrics port, and so on. It covers unit tests, component tests,
e2e tests, visual regression, Storybook, GitHub/GitLab CI, a preview deploy per PR, PWA, a TWA (Android), web push,
web vitals reporting, Prometheus `/metrics`, OpenTelemetry, Sentry, i18n, RTL, dark mode, feature flags, analytics,
an a11y CI check, a bundle-size budget, Lighthouse CI, Renovate/Dependabot, Docker, conventional commits and
changesets.

When the rounds are done, print the final decision table and ask for one explicit approval. Nothing is scaffolded
before it.

## Phase 4: Architecture docs and plan review

Write these into the new repo's `docs/` (from `assets/templates/`):

- `docs/decisions.yaml`: the machine-readable record of every choice.
- `docs/adr/NNNN-<slug>.md`: one ADR per decision that has a real alternative (rendering model, data layer,
  state, auth, styling, testing, deployment and so on). Each says context → options considered → decision →
  consequences → how it is enforced. "How it is enforced" is what separates a senior ADR from a wish: name the
  lint rule, the test or the CI job.
- `docs/ARCHITECTURE.md` holds:
  - **The route map:** every route, with its rendering strategy, cache scope and lifetime, tags, prefetch level,
    and the auth it needs (`references/rendering-and-caching.md` shows the format). It is the most persuasive
    artefact in a review, so it must be complete.
  - **Data flow:** a diagram of the layers (`references/architecture.md`), and where validation, caching and
    errors happen.
  - **Folder layout** and **import rules**.
  - **Cache invalidation:** which mutation calls `updateTag`, `revalidateTag` or `refresh` on what.
  - **NFR budgets:** LCP, INP, CLS, the JS budget per route, and the targets for the error rate and availability.
- `AGENTS.md` (plus a `CLAUDE.md` that only says `@AGENTS.md`), from `assets/templates/AGENTS.md`. It holds the
  project's rules for any agent working here later. Keep the Next.js managed block that `create-next-app` and
  `next dev` write.
- `docs/PLAN.md`: the phased build plan, with the feature slices in priority order, each with an acceptance
  criterion and the tests that prove it.

**Plan review.** If `paranoia` is available, run it on `docs/` (`--effort medium`, or `high` if there is time). If
not, review the docs yourself against the "Plan" section of `references/quality-gates.md`. Fix the findings, then
show the user a 10-line summary and the review result.

## Phase 5: Scaffold

1. Run `create-next-app` with flags that match the decisions (see `references/nextjs-16.md` → "Scaffolding").
   Prefer explicit flags over `--yes`, so the result doesn't depend on saved preferences.
2. Run `scripts/find-next-docs.sh` from the new project. **From here on, the installed docs at
   `node_modules/next/dist/docs/` are the source of truth.** Before writing code in an area (caching, proxy,
   metadata, route handlers, instrumentation, PWA and so on), open the matching guide from the doc map in
   `references/nextjs-16.md`. If the installed docs contradict this skill, follow the docs and tell the user.
3. Install the chosen libraries at their **current** majors (`pnpm add x@latest`). Don't pin a version from memory.
   Check the major you got against its migration notes if it is newer than this skill expects.
4. Apply the tooling config: TypeScript strictness, lint and format, boundaries, git hooks, env validation and the
   `next.config.ts` flags.
5. Create the folder skeleton from `references/architecture.md`.
6. Run the gates (`scripts/gates.sh`). Commit: `chore: scaffold <name> with <key choices>`.

## Phase 6: Foundation (cross-cutting, before any feature)

Build the platform layer every feature will lean on, using `references/recipes.md` as the starting point, and
adapt it to the decisions. The usual order, skipping what wasn't chosen:

1. env schema and config, the error model, logging
2. the HTTP client / API layer (generated OpenAPI types if a spec exists, otherwise hand-written Zod-validated
   contracts) and the mock layer (MSW) when the backend isn't ready
3. the providers (query client, theme, i18n), the root layout, fonts, metadata defaults, `not-found`, `error`,
   `global-error`, `loading` and the shared shell (header, nav, footer)
4. design tokens, the UI primitives and the dark-mode/RTL plumbing
5. auth: `proxy.ts` for optimistic redirects, a server-only session read in the data access layer, the login flow
6. observability: web vitals, `/metrics`, tracing, error reporting, health endpoints
7. security headers and CSP, PWA/manifest/service worker
8. the test harness (unit, component, e2e configs, a sample test of each kind) and CI

Each item ends green on `scripts/gates.sh` and gets its own commit. Use TDD where there's logic, such as mappers,
formatters and reducers. Infra wiring is proven by a test or a manual check you actually ran, not by assuming it
works.

## Phase 7: Feature slices (the loop)

Take the slices from `docs/PLAN.md` one at a time, MVP first. Each slice is vertical: contract and types → server
data access (cached or not, as the route map says) → mutations and their invalidation → UI with loading, empty,
error and success states → tests → docs.

For each slice:

1. Re-read the route map rows it touches. If the slice needs a rendering or caching choice that isn't in the map,
   stop and update the map (and the ADR if the change is material) before coding.
2. Write the failing tests first for the logic and for the user-visible behaviour (component test or e2e).
3. Implement. Keep route files thin. Respect the import boundaries.
4. Run `scripts/gates.sh`. For routes on Cache Components, also check the dev overlay or the build output for
   blocking-route and instant-navigation insights, because they are real defects, not noise.
5. Review the diff against `references/quality-gates.md` → "Code review", and with `paranoia` if available. Fix
   the findings.
6. Commit with a conventional message. Tell the user in one or two lines what landed and what's next.

If the user is in an interview, keep a running `docs/NOTES.md` of trade-offs made under time pressure ("chose
polling over WS for slice 3 because…; follow-up: …"). It gives the user something concrete to discuss.

## Phase 8: Hardening

Run the whole gate set, including e2e against a production build (`next build && next start`). Then:

- the bundle check (`next analyze` or the chosen budget tool) against the budgets in ARCHITECTURE.md
- a Lighthouse or web-vitals spot check on the key routes
- an a11y pass (axe in e2e, keyboard-only walk of the main journey)
- a security pass: headers, CSP, no secrets in client bundles (search the build output for env values), validated
  Server Action input, authorization in the data access layer (not only in `proxy.ts`)
- a final `paranoia` at the effort the user picks, or the full checklist yourself

## Phase 9: Handoff

Update `README.md` (setup, scripts, architecture links, decisions summary) and print for the user:

- what was built, what was deferred, and the known risks
- the five decisions most worth defending, each with its one-sentence trade-off (useful for an interviewer's
  "why did you…?")
- the exact commands to run, test and build

## Principles that hold in every phase

- **Docs over memory.** Next.js 16 changed rendering, caching, middleware (now `proxy.ts`), the request APIs and
  linting. When unsure, open the installed doc; don't guess.
- **Server-first, client by need.** A component gets `'use client'` only for state, effects, browser APIs or
  interactive libraries. Keep client islands small and pass them serializable props.
- **Every cache has an owner.** Each `use cache` gets a `cacheLife` and a tag, and each tag has a mutation that
  invalidates it. If you can't name the invalidation, don't cache.
- **One source of truth** for each concern: one HTTP client, one query-key factory per feature, one env schema,
  one token set, one error model.
- **Enforce, don't hope.** A rule that matters becomes a lint rule, a type, a test or a CI job.
- **The smallest design that covers the brief.** Large scale means clear seams and enforced boundaries, not
  speculative abstraction. Don't add a library, layer or flag the brief doesn't need, and say what you
  deliberately left out.
- **Honest status.** Report failing gates with their output. Never say "done" without having run the gates.
