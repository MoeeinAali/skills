# <Project> architecture

## 1. Product in one paragraph
<Who it is for, the core journeys, what "done" means for this iteration.>

## 2. Stack at a glance
| Area | Choice | ADR |
|---|---|---|
| Rendering | Cache Components + Partial Prefetching | [0001](adr/0001-rendering.md) |
| … | … | … |

## 3. Route map
| Route | Audience | Strategy | Cached parts (profile · tags) | Dynamic holes | Prefetch | Guards | Notes |
|---|---|---|---|---|---|---|---|

## 4. Data flow
<The diagram from references/architecture.md §3, adapted. Where validation, caching, auth and error handling
happen.>

## 5. Cache invalidation
| Mutation / event | Where | Invalidates | Tool |
|---|---|---|---|

## 6. Folder layout and import rules
<Tree + the rules table, and the lint config that enforces it.>

## 7. Cross-cutting
- Errors: <the model>
- Auth: <session, proxy vs DAL responsibilities>
- i18n/RTL: <…>
- Observability: <vitals, metrics, traces, errors: where each goes>
- Security: <headers, CSP choice, secrets>

## 8. NFR budgets
| Metric | Budget | Measured by |
|---|---|---|
| LCP (p75, mobile) | ≤ 2.5 s | RUM `/api/vitals` + Lighthouse CI |
| INP (p75) | ≤ 200 ms | RUM |
| CLS (p75) | ≤ 0.1 | RUM |
| JS per route (gz) | ≤ <n> KB | `next analyze` / size budget job |
| Error rate | < <n>% | Sentry / metrics |

## 9. Deliberately out of scope
<Each skipped capability and why: time box, not in the brief, follow-up.>

## 10. Risks and follow-ups
