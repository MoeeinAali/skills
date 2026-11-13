# Domain pack: e-commerce / marketplace

Read in Phase 1 when the brief has a catalog, product pages, cart, checkout or orders.

## Default overrides

| Area | Override | Why |
|---|---|---|
| R01 | PPR everywhere public; product detail = **ISR with Cache Components** (`generateStaticParams` for bestsellers) | SEO, LCP, CDN hits |
| Caching | Catalog/product: `use cache` + `cacheLife('hours')` + tags `product:{id}`, `category:{slug}`; **price and stock** in a separate short-lived or uncached hole | Price and stock change faster than content |
| Invalidation | CMS/PIM webhook → Route Handler → `revalidateTag(tag,'max')`; cart actions → `updateTag('cart:{id}')` | Editors vs shoppers |
| S02 | nuqs for facets, sort and pagination; `<Link prefetch>` on high-intent results | Shareable, prefetchable search |
| Cart | Server-owned cart (cookie cart id) + Server Actions + `useOptimistic` | Works without JS, survives devices |
| SEO | `generateMetadata`, Product/Offer/Breadcrumb JSON-LD, `sitemap.ts` with `generateSitemaps` for large catalogs, canonical URLs for facet pages | Organic traffic |
| Images | `next/image` with `sizes`, AVIF/WebP, priority on the LCP image only | LCP |
| G01 | Feature flags for experiments on PDP/checkout, evaluated on the server | No CLS from client flags |

## Required design items

- Checkout is dynamic, never cached, `prefetch='force-disabled'`, and has strict CSP (payment iframes in
  `frame-src`).
- Idempotent order placement (an idempotency key). Show payment redirect and return states.
- Inventory races: show "only N left" from the uncached hole, and re-validate at checkout.

## Tests

The cart reducer and price math (decimal), facet URL ⇄ state round-trip, e2e browse → PDP (instant) → add to
cart → checkout (mocked payment).
