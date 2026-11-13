# SEO and sharing

Read this in Phase 3 (decisions E01–E02), Phase 4 (the SEO column of the route map) and Phase 6 step 4 (metadata
defaults, robots, sitemap, OG). Docs: `01-getting-started/14-metadata-and-og-images.md`,
`03-api-reference/03-file-conventions/01-metadata/*`, `04-functions/generate-metadata.md`, `02-guides/json-ld.md`.

## Contents
1. Decide per route: indexable or not
2. Metadata defaults and per-route metadata
3. Canonicals, filters, pagination and locales
4. robots and sitemap
5. Structured data (JSON-LD)
6. Open Graph images
7. What rendering does to SEO
8. Checks and tests

---

## 1. Decide per route: indexable or not

Every row of the route map gets an **SEO** column with one of these values:

| Value | Routes | What it means |
|---|---|---|
| `index` | Landing, catalogue/list, detail pages (`/markets/[symbol]`, `/products/[slug]`), articles | Content in the first HTML, its own title, description and canonical, in the sitemap, JSON-LD, an OG image |
| `index, canonical → X` | Filtered/sorted variants of a list that are worth sharing | Rendered, but the canonical points to the clean URL |
| `noindex, follow` | Search results, arbitrary filter combinations, paginated pages past the useful ones | `robots: { index: false, follow: true }` |
| `noindex` | Auth, account, wallet, checkout, admin, every personal page | `robots: { index: false }` and not in the sitemap. Disallowing it in robots.txt doesn't remove it from the index, and it isn't access control |

Staging and preview builds are `noindex` everywhere: an `X-Robots-Tag: noindex, nofollow` header plus a robots.txt
that disallows all, both keyed on a deploy-environment variable, never on `NODE_ENV`.

## 2. Metadata defaults and per-route metadata

Never hand-write `<head>`. Use the static `metadata` export or `generateMetadata`. Metadata merges **shallowly
down the tree**, and a child that doesn't set a field inherits it. So the root layout must not set a `canonical`
(every page would claim to be `/`), and a nested `openGraph` object replaces the parent's whole `openGraph`.

```ts
// src/app/layout.tsx
import type { Metadata, Viewport } from 'next'
import { clientEnv } from '@/platform/env/env.client'

export const metadata: Metadata = {
  metadataBase: new URL(clientEnv.NEXT_PUBLIC_SITE_URL), // makes OG/canonical URLs absolute
  title: { default: 'Saraf', template: '%s | Saraf' },
  description: '…',
  applicationName: 'Saraf',
  openGraph: { type: 'website', siteName: 'Saraf', locale: 'fa_IR' },
  twitter: { card: 'summary_large_image' },
  formatDetection: { telephone: false },
}

export const viewport: Viewport = {
  // themeColor lives in viewport, not metadata. Keep it in step with the theme recipe (recipes §18).
  themeColor: [
    { media: '(prefers-color-scheme: light)', color: '#ffffff' },
    { media: '(prefers-color-scheme: dark)', color: '#111517' },
  ],
}
```

```ts
// src/app/markets/[symbol]/page.tsx
export async function generateMetadata({ params }: PageProps<'/markets/[symbol]'>): Promise<Metadata> {
  const { symbol } = await params
  const market = await getMarket(symbol) // the same cached DAL call the page makes, so it's fetched once
  if (!market) notFound()
  return {
    title: `${market.nameFa} (${market.symbol})`,
    description: `قیمت لحظه‌ای ${market.nameFa}، نمودار و معاملات اخیر`,
    alternates: { canonical: `/markets/${market.symbol}` },
  }
}
```

- `generateMetadata` and the page share one cached DAL function (`'use cache'` + `cacheTag`), so the data is read
  once and invalidated by the same tag.
- Metadata is **streamed** to browsers, while the bots in the `htmlLimitedBots` list (Googlebot, Bingbot,
  Twitterbot and others by default) get blocking metadata. So the data source must be reachable at request time,
  not only at build (gotcha 9 in `nextjs-16.md`).
- `notFound()` must run before anything streams, so the response is a real `404`. Inside a Suspense boundary the
  status stays `200` (Next still injects `noindex`). Check it with `curl -I`.
- A moved slug gets `permanentRedirect()` (308), not a soft "not found".
- Root `<html lang dir>` comes from the locale (`fa`, `rtl`). With several locales, the layout under `[lang]`
  sets it.

## 3. Canonicals, filters, pagination and locales

- **Canonical** = the clean URL of the content. Strip tracking params (`utm_*`, `ref`) and UI-only state (view
  mode, open panel). Sort and arbitrary filter combinations canonicalise to the unfiltered list.
- **SEO-worthy filters** (category, brand, quote currency) become **path segments or a small fixed set of params**
  with their own title and description. They're prerendered with `generateStaticParams` for the common values
  (`techniques.md` §4).
- **Pagination:** each page is its own canonical (`?page=2` canonicalises to itself, not to page 1), linked with
  real `<Link href>` anchors so crawlers can follow them. Infinite scroll needs a crawlable fallback: the
  server-rendered first page plus a "Load more" `<Link href="?page=2">` that the client intercepts.
- **Locales:** `alternates.languages` with every locale plus `x-default`, and the same set in the sitemap.
  Each locale page canonicalises to itself.

## 4. robots and sitemap

```ts
// src/app/robots.ts
import type { MetadataRoute } from 'next'
import { clientEnv } from '@/platform/env/env.client'
import { serverEnv } from '@/platform/env/env.server'

export default function robots(): MetadataRoute.Robots {
  const base = clientEnv.NEXT_PUBLIC_SITE_URL
  if (serverEnv.DEPLOY_ENV !== 'production') return { rules: { userAgent: '*', disallow: '/' } }
  return {
    rules: [{ userAgent: '*', allow: '/', disallow: ['/api/', '/account/', '/wallet/'] }],
    sitemap: `${base}/sitemap.xml`,
  }
}
```

```ts
// src/app/sitemap.ts
import type { MetadataRoute } from 'next'
import { listMarketSlugs } from '@/features/markets/server'
import { clientEnv } from '@/platform/env/env.client'

export default async function sitemap(): Promise<MetadataRoute.Sitemap> {
  const base = clientEnv.NEXT_PUBLIC_SITE_URL
  const markets = await listMarketSlugs() // 'use cache' + cacheLife('hours') + cacheTag('markets')
  return [
    { url: `${base}/`, changeFrequency: 'hourly', priority: 1 },
    { url: `${base}/markets`, changeFrequency: 'hourly', priority: 0.9 },
    ...markets.map((m) => ({ url: `${base}/markets/${m.symbol}`, lastModified: m.updatedAt })),
  ]
}
```

Above 50,000 URLs, split with `generateSitemaps` (each part is `/…/sitemap/[id].xml`, and `id` is a promise in 16)
and list the parts in `robots.ts`. Only `index` routes go in. `lastModified` comes from the data, never `new Date()`
(it's meaningless, and with Cache Components it's a prerender error).

## 5. Structured data (JSON-LD)

Render it in the page's Server Component. It's a data block, so `script-src` doesn't apply to it, but it **is**
an XSS sink: escape `<`.

```tsx
// src/shared/seo/json-ld.tsx
import type { Thing, WithContext } from 'schema-dts' // optional: typed schema.org

export function JsonLd<T extends Thing>({ data }: { data: WithContext<T> }) {
  return (
    <script
      type="application/ld+json"
      dangerouslySetInnerHTML={{ __html: JSON.stringify(data).replace(/</g, '\\u003c') }}
    />
  )
}
```

Use only the types the content really has:

- **Every site:** `Organization` (logo, `sameAs` socials) and `WebSite` (+ `SearchAction` if there's site search) on
  the home page; `BreadcrumbList` on nested pages.
- **Domain:** `Product` + `Offer` (price, currency, availability) for e-commerce; `Article`/`NewsArticle` with
  author and dates for content; `FAQPage` only for a visible FAQ.

Validate with the Rich Results Test and assert it parses in e2e (§8).

## 6. Open Graph images

| Option | Use when |
|---|---|
| A static `opengraph-image.png` (+ `opengraph-image.alt.txt`) per segment | Brand and section pages. Zero runtime. |
| **Generated `opengraph-image.tsx` with `ImageResponse` (`next/og`)** | Detail pages where the title or a number makes the share card (market, product, article) |
| A pre-rendered image from the CMS/backend | The design team owns the cards, or the text needs shaping Satori can't do |

```tsx
// src/app/markets/[symbol]/opengraph-image.tsx
import { readFile } from 'node:fs/promises'
import { join } from 'node:path'
import { ImageResponse } from 'next/og'
import { getMarket } from '@/features/markets/server'

export const alt = 'Saraf market'
export const size = { width: 1200, height: 630 }
export const contentType = 'image/png'

export default async function Image({ params }: { params: Promise<{ symbol: string }> }) {
  const { symbol } = await params
  const [market, font] = await Promise.all([
    getMarket(symbol),
    readFile(join(process.cwd(), 'assets/fonts/Vazirmatn-Bold.ttf')),
  ])
  return new ImageResponse(
    (
      <div style={{ display: 'flex', width: '100%', height: '100%', alignItems: 'center',
        justifyContent: 'center', background: '#111517', color: '#f5f7fa', fontSize: 96 }}>
        {market ? market.symbol : 'Saraf'}
      </div>
    ),
    { ...size, fonts: [{ name: 'Vazirmatn', data: font, weight: 700, style: 'normal' }] },
  )
}
```

- Size 1200×630. `twitter-image` follows the same convention. The `alt` export is static; for a per-item alt, use
  `generateImageMetadata`.
- Limits: flexbox and a subset of CSS only (no grid), a 500 KB bundle including fonts, `ttf`/`otf`/`woff` only.
  Subset the font.
- Generated images are prerendered (for the `generateStaticParams` params) unless they read request data or
  uncached data. Read data through the cached DAL so the image is cached and tagged like the page.
- **Persian/RTL text:** Satori's shaping of Arabic-script text and bidi is limited. Render a test card with
  Persian text on day one. If letters come out disconnected or in the wrong order, keep Persian out of the
  generated image (symbol, Latin-digit numbers, logo) and put the Persian in `og:title`/`og:description`.
- **Don't put live numbers at the centre of a share card.** Social platforms cache the image for days, so a
  price in the card is stale by the time anyone sees it. Use the name, the logo and at most "24h change at share
  time" with a date.
- Check how the card looks with each platform's card validator or an OG preview tool, and in Telegram and
  WhatsApp, which matter more than X in Iran.

## 7. What rendering does to SEO

- Everything indexable is in the **first HTML**: the static shell plus cached content. A client-only island
  (TanStack Query fetching after mount) is invisible to bots that don't run JS and slow for the ones that do. So
  lists render their first page on the server (`techniques.md` §3).
- Core Web Vitals are a ranking signal: `next/image` with `sizes`, the LCP image with `preload` (`priority` is
  deprecated in 16), `next/font` (no layout shift), skeletons with the content's exact size, small client JS.
- One `<h1>` per page, landmarks (`header`, `nav`, `main`, `footer`), descriptive link text, `alt` on content
  images, and real `<a href>` (via `<Link>`) for every navigation, never `onClick` + `router.push`.
- Error and not-found pages return the right status (§2), and unknown params in `generateStaticParams` routes
  `notFound()` instead of rendering an empty page.

## 8. Checks and tests

- **e2e (Playwright, production build):** per `index` route, assert the `<title>`, the meta description, the
  canonical and `og:image`. Assert that `noindex` routes carry `noindex`. Fetch the `og:image` URL and expect
  `200` and `image/png`. Parse every `application/ld+json` block with `JSON.parse`.
- **Unit:** the canonical builder (strips tracking/sort params) and the JSON-LD builders.
- **Request checks:** `curl -I` returns `404` for a missing detail page and `308` for a moved slug.
  `/robots.txt` and `/sitemap.xml` return `200`, and staging returns disallow-all.
- **Lighthouse** SEO category on the key routes in Phase 8 (Lighthouse CI if it was ticked).
