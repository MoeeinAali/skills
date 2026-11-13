# Domain pack: content / media / news / sports

Read in Phase 1 for news feeds, blogs, video/clips, sports scores and similar content-heavy, SEO-driven apps.

## Default overrides

| Area | Override | Why |
|---|---|---|
| R01 | PPR; articles = ISR with Cache Components; lists `use cache` + `cacheLife('minutes')` | Freshness without SSR cost |
| Invalidation | CMS webhook → `revalidateTag('article:{id}','max')`, `revalidateTag('feed:{topic}','max')` | Editors publish, readers see it in seconds |
| Live scores | Cached snapshot (`seconds`/custom profile) + SSE/WS island; push notifications per followed match (W01 web push) | Live without per-request SSR |
| SEO | `generateMetadata`, NewsArticle/VideoObject JSON-LD, news sitemap, OG images via `opengraph-image.tsx` | Discovery, social shares |
| Media | HLS via `hls.js` (dynamic import, client-only), poster images through `next/image`, lazy players | LCP and bundle size |
| PWA | Often installable + offline reading list + TWA on Android | Re-engagement |
| Infinite feeds | TanStack `useInfiniteQuery` after an SSR first page; virtualized long lists | Scroll performance |
| Ads/analytics | Third-party scripts with `next/script` `lazyOnload`, reserve ad slot sizes | CLS |

## Tests

Feed pagination, article rendering (sanitized HTML via DOMPurify or a trusted renderer), e2e feed → article
(instant), OG image route responds.
