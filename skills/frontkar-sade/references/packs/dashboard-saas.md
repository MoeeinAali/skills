# Domain pack: dashboard / SaaS / admin

Read in Phase 1 when the app sits mostly behind login: admin panels, analytics dashboards, B2B tools, CRMs.

## Default overrides

| Area | Override | Why |
|---|---|---|
| R01 | Cache Components still on: a static **app shell** (nav, layout chrome) + per-user streamed sections | Instant navigation inside the app |
| Caching | Per-tenant data: pass `tenantId`/`userId` into `use cache` (shared key per tenant) or `use cache: private`; never a tenant-agnostic cache of tenant data | Isolation |
| C02 | TanStack Query for tables, filters, polling, optimistic edits | Heavy client interaction |
| U05 | TanStack Table + Virtual; server-side pagination, sorting and filtering via nuqs URL state | Large datasets, shareable views |
| U06 | Recharts/ECharts, dynamically imported per route | Bundle per route |
| Auth | RBAC/ABAC checks in the DAL per resource; UI hides what policy forbids, but the server enforces | — |
| SEO | `robots: noindex` on app routes | — |
| G01 | Feature flags per tenant/plan | Gradual rollouts |

## Required design items

- A permission model in `platform/auth/policy.ts` (`can(user, action, resource)`), used by both the DAL and the UI.
- Multi-tenant routing: subdomain or `/[tenant]` (root param via `next/root-params`), with tenant resolution in
  `proxy.ts` (optimistic) and the DAL (authoritative).
- Audit-friendly mutations: every action returns a typed result, and destructive ones confirm.
- Bulk operations with progress (SSE or polling) and cancel.

## Tests

The policy table (unit, exhaustive), the table URL-state round-trip, and e2e for each role seeing and doing only
what it's allowed to.
