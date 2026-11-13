# UI and data techniques

The patterns a senior frontend reviewer expects to see used deliberately: chosen per feature, implemented with
the project's stack, and tested. Use this in Phase 1 (build the technique map from the brief), Phase 4 (write it
into ARCHITECTURE.md) and Phase 7 (each slice implements and tests its techniques).

Library APIs move between majors. Check the installed version's docs for TanStack Query/Virtual, nuqs and RHF
before copying a snippet.

## Contents
1. Technique map: feature signals → techniques
2. Loading UX: skeletons, streaming, pending, optimistic
3. Lists: pagination, infinite scroll, virtualization
4. Search, filter, sort: server vs client
5. Debounce, throttle, rAF
6. Validation: client and server
7. Freshness and races
8. Performance techniques
9. Resilience: errors, retries, empty and offline states
10. Accessibility for these patterns
11. Testing these patterns

---

## 1. Technique map

In Phase 1, read each feature in the brief and tick its techniques. Put the result in ARCHITECTURE.md as a table
(feature → techniques → where), and refer to it in every slice.

| Signal in the brief | Techniques |
|---|---|
| "list", "feed", "history", "all X" | pagination type (§3), skeleton rows (§2), empty state (§9) |
| unbounded list, "scroll", mobile feed | infinite scroll (§3.2) + `maxPages` cap; virtualization if rows > ~100 in DOM (§3.3) |
| table with many rows, live rows | virtualization (§3.3), row-level subscriptions (§7), sticky header |
| "search", "find" | debounced input (§5), server or client search by data size (§4), Persian text normalization (§4.4), highlighted matches, results count in a live region (§10) |
| "filter", "sort", "tabs" | URL state (§4.2), `keepPreviousData` (§4.3), shareable links |
| "live", "real-time", "prices" | throttled/rAF-batched rendering (§5), stale indicator on disconnect (§9) |
| "form", "create", "edit", "settings" | shared Zod schema client and server (§6), pending and double-submit guard (§2.3), field errors from the server (§6.2) |
| "like", "star", "follow", "add to" | optimistic update with rollback (§2.4) |
| "dashboard", "detail page" | Suspense per section with matching skeletons (§2.1), section error boundaries (§9) |
| "autosave", "draft" | debounced save (§5), save status indicator, `beforeunload` guard |
| heavy widget (chart, editor, map, player) | lazy loading with `next/dynamic` (§8), skeleton of the same size |
| images, gallery | `next/image` with `sizes`, priority only for the LCP image, blur placeholder (§8) |

## 2. Loading UX

### 2.1 Skeletons
- Use **skeletons for content and spinners only for actions.** A skeleton has the same box size as the final
  content (fixed heights, avatar circles, line widths), so CLS stays ~0.
- Where they go:
  - `loading.tsx` covers the whole segment on navigation.
  - An inline `<Suspense fallback={<XSkeleton/>}>` covers each independently slow section, which is the better
    default under PPR because the fallback ships in the static shell.
  - TanStack `isPending` handles client islands.
- Keep one `Skeleton` primitive in `shared/ui` (shadcn has one), plus a `<FeatureSkeleton>` per feature component,
  colocated with it so they change together.
- Don't flash: if data usually arrives in under ~150 ms on client transitions, wrap the update in
  `startTransition`/`useTransition` so React keeps the old UI instead of flashing a skeleton.
- A11y: put `aria-busy="true"` on the region, and a visually hidden "Loading…" text, once rather than per row.

### 2.2 Streaming
Order the Suspense boundaries by importance: the above-the-fold content resolves first. Don't nest boundaries so
that a fast child waits on a slow parent. Push awaits down (see `rendering-and-caching.md`).

### 2.3 Pending states
- Use `useFormStatus` in submit buttons, or RHF `formState.isSubmitting`: disable the button and show an inline
  spinner. This is also the **double-submit guard**.
- Use `useLinkStatus` (`next/link`) for a per-link pending hint on slow navigations, and `useTransition` for
  non-navigation updates.
- Keep the user's input on error. Never reset a form that failed.

### 2.4 Optimistic updates
- **Server Actions:** `useOptimistic(state, reducer)`. Apply on submit; the action's result (or `updateTag`)
  reconciles. On failure, roll back and toast.
- **TanStack:** `onMutate` → `cancelQueries` → snapshot → `setQueryData` → return the snapshot; `onError` →
  restore the snapshot; `onSettled` → `invalidateQueries`.
- Only optimistically update what's almost certain to succeed and cheap to undo (likes, stars, toggles, list
  reordering). Not payments or orders.

## 3. Lists

### 3.1 Choose a pagination type
| Type | Use when | Notes |
|---|---|---|
| Page numbers (offset) | SEO listing pages, jump-to-page, a stable dataset | `?page=` in the URL; server-rendered; `<Link prefetch>` on the next page |
| Cursor ("load more" / infinite) | Feeds, histories, live-inserting data | No duplicates or skips when items are inserted; can't jump to page N |
| Infinite scroll | Mobile feeds, discovery | A "load more" button fallback; `maxPages`; restore scroll position on back |
| Virtualized "all rows" | Data already in memory (≤ ~10k rows) | No paging requests at all, just DOM virtualization |

### 3.2 Infinite scroll
- Render the **first page on the server** (fast LCP, SEO), then hand it to `useInfiniteQuery` as `initialData` (or
  prefetch + `HydrationBoundary`), and let the client load the following pages.
- `useInfiniteQuery({ queryKey, queryFn: ({ pageParam, signal }) => …, initialPageParam, getNextPageParam,
  maxPages })`. Pass `signal` to fetch so that stale requests abort.
- Trigger with an **IntersectionObserver sentinel** (`rootMargin: '600px'` to prefetch early), not scroll
  listeners. Guard against duplicate calls: `if (hasNextPage && !isFetchingNextPage) fetchNextPage()`.
- Keep a visible **"Load more" button** too, for keyboard users and when the observer isn't supported.
- Cap memory with `maxPages` (plus virtualization for long sessions). Show the end-of-list state, and on error an
  inline retry at the bottom.
- Back navigation: with Cache Components, hidden routes stay mounted through `<Activity>`, so the scroll and query
  state usually survive. Test it.

### 3.3 Virtualization (TanStack Virtual, preferred)
- Virtualize when a list can hold more than ~100 complex rows (or ~1000 simple ones) in the DOM. Below that,
  `content-visibility: auto` with `contain-intrinsic-size` is a zero-JS alternative.
- `useVirtualizer({ count, getScrollElement, estimateSize, overscan: 8 })` for a scroll container, or
  `useWindowVirtualizer` for page scroll. Render `getVirtualItems()` absolutely positioned inside a
  `getTotalSize()` spacer. Use `measureElement` for dynamic heights.
- **Infinite + virtual:** `count = hasNextPage ? rows.length + 1 : rows.length`. When the last virtual item index
  ≥ `rows.length - 1`, fetch the next page.
- Keys: use stable ids, never the index, when rows update live.
- RTL: horizontal virtualization needs the direction handled (check the installed version's RTL support).
  Vertical lists are unaffected.
- SSR: the server renders the first page of rows (not virtualized), and the virtualizer takes over on the client.
  Make sure the initial rows match to avoid hydration mismatch, or render a skeleton until mounted.
- A11y: `role="list"`/`role="grid"` with `aria-rowcount`/`aria-rowindex` for tables, and keep focus on a row when
  it scrolls out of view (or move focus to the container).

## 4. Search, filter, sort

### 4.1 Server or client?
| Data | Do it | How |
|---|---|---|
| Fully loaded and small (≲ 2k rows, already needed on screen) | **Client** | `useDeferredValue(query)` + `useMemo` filter. No debounce needed: deferring keeps typing responsive. |
| Large, paginated, or needs ranking or fuzzy search | **Server** | Debounced input → URL → server query (RSC re-render or a TanStack key change) |
| SEO-relevant filters (category, brand) | **Server, in the URL path or params** | Indexable, prerenderable with `generateStaticParams` for the common ones |
| Live data plus filtering | **Client over the live store** | Filter the external store with selectors |

### 4.2 URL as state
- Filters, sort, tab and page live in the URL (shareable, back button works, server-readable). Use **nuqs** if
  chosen (`useQueryState`/`useQueryStates` with typed parsers), otherwise `useSearchParams` + `router.replace`.
- `shallow: true` (the nuqs default) updates the URL without a server round trip. Use it for client-side filters.
  Set `shallow: false` when a Server Component reads `searchParams` and must re-render.
- Rate-limit URL writes while typing: debounce the input (§5), and use nuqs's built-in URL update
  throttling/debouncing if the installed version has it.
- Reset the page or cursor when a filter changes.

### 4.3 Smooth result updates
- TanStack: `placeholderData: keepPreviousData`, so old results stay (dimmed with `isPlaceholderData`) while new
  ones load, instead of a skeleton flash.
- RSC: `startTransition` around the URL update keeps the current UI until the new segment streams in.
- Abort stale requests: TanStack passes `signal` to `queryFn`, and the query key change cancels. Hand-rolled
  fetches use `AbortController` per request and ignore late responses (§7).

### 4.4 Persian text normalization
Normalize both the query and the indexed text before comparing, in `shared/lib/text.ts`, with unit tests:
- Arabic `ي`/`ك` → Persian `ی`/`ک`, `ة` → `ه`, strip diacritics (harakat) and tatweel `ـ`
- Persian and Arabic digits → Latin (or the reverse, consistently)
- ZWNJ (U+200C) and extra whitespace → single space; lower-case Latin; trim

## 5. Debounce, throttle, rAF

| Technique | Fires | Use for | Typical wait |
|---|---|---|---|
| **Debounce** (trailing) | once after input stops | search box, autosave, async field validation, resize-end | 250–400 ms (search), 800–1500 ms (autosave) |
| **Throttle** | at most once per interval | scroll/resize handlers, analytics events, pointer move, URL writes | 100–250 ms |
| **rAF batching** | at most once per frame | live data → render (prices, order book), drag positions | 16 ms (per frame) |
| **`useDeferredValue`** | when React has idle time | expensive client-side filtering or rendering from input | – |

Implement small hooks in `shared/hooks/`. Don't import all of lodash (if you use it, use `lodash-es/debounce`):

```ts
// shared/hooks/use-debounced-value.ts
import { useEffect, useState } from 'react'

export function useDebouncedValue<T>(value: T, delayMs = 300): T {
  const [debounced, setDebounced] = useState(value)
  useEffect(() => {
    const id = setTimeout(() => setDebounced(value), delayMs)
    return () => clearTimeout(id)
  }, [value, delayMs])
  return debounced
}
```
```ts
// shared/hooks/use-throttled-callback.ts
import { useEffect, useLayoutEffect, useRef } from 'react'

export function useThrottledCallback<A extends unknown[]>(fn: (...args: A) => void, waitMs = 200) {
  const fnRef = useRef(fn)
  const last = useRef(0)
  const timer = useRef<ReturnType<typeof setTimeout>>(undefined)
  // Always call the latest fn without re-creating the throttled function.
  useLayoutEffect(() => {
    fnRef.current = fn
  })
  useEffect(() => () => clearTimeout(timer.current), [])
  return (...args: A) => {
    const remaining = waitMs - (Date.now() - last.current)
    clearTimeout(timer.current)
    if (remaining <= 0) {
      last.current = Date.now()
      fnRef.current(...args)
    } else {
      // Trailing call so the final value is never lost.
      timer.current = setTimeout(() => {
        last.current = Date.now()
        fnRef.current(...args)
      }, remaining)
    }
  }
}
```

Rules: debounce the **value** you send (search term), not the input's own state (the input stays controlled and
instant). Clean up timers on unmount. For scroll position use IntersectionObserver, or a passive listener plus
rAF, instead of throttled scroll math where possible.

## 6. Validation

### 6.1 One schema, two places
- A Zod schema in `features/x/model/schemas.ts`, used by RHF (`zodResolver(schema)`) on the client **and**
  `schema.safeParse` in the Server Action (or the Route Handler). The client is for UX and the server is the
  authority.
- Normalize before validating: trim, Persian → Latin digits for phone/OTP/amounts (`z.preprocess` or a
  transform), and coerce `FormData` strings (`z.coerce.number()`).
- RHF `mode: 'onTouched'` (validate after the first blur, then on change), so it doesn't shout while the user is
  still typing.
- Server-only rules (uniqueness, balance, permissions) live only on the server. Surface them as field errors.

### 6.2 Server errors back into the form
The action returns `{ ok: false, error: { fieldErrors } }`. On the client: `Object.entries(fieldErrors).forEach(([name,
msgs]) => setError(name, { message: msgs[0] }))`, plus a form-level error for non-field codes. Focus the first
invalid field.

### 6.3 Async validation
Use a debounced check (e.g. "is this username taken?") through a small Route Handler or action, abort the
previous check, show a pending indicator on the field, and **re-check on the server at submit**.

## 7. Freshness and races
- Choose per data: `staleTime` (how long it's fresh), `refetchOnWindowFocus` (on for dashboards, off for static),
  `refetchInterval` (polling, paused when the tab is hidden), or a push stream.
- **Out-of-order responses:** the query key plus abort handles it in TanStack. In hand-rolled code, track a
  request id or use `AbortController`, and only apply the latest.
- Live lists: subscribe per row (selector by id) so one update re-renders one row. Flash changes with a CSS class
  toggled by key, not a remount.
- Mutation then read: invalidate exactly the affected keys and tags. Avoid blanket `invalidateQueries()`.

## 8. Performance techniques
- **Code splitting:** `next/dynamic(() => import('./Chart'), { loading: () => <ChartSkeleton/> })` for heavy
  client widgets (charts, editors, maps, GSAP plugins, players). `ssr: false` is only allowed inside Client
  Components.
- **Images:** `next/image` with `sizes`, `priority`/`fetchPriority="high"` on the single LCP image only,
  `placeholder="blur"` for large media.
- **Prefetch on intent:** the default `<Link>` prefetches the App Shell; use `prefetch={true}` on high-intent links
  (the first results, next page) for URL-specific cached content.
- **Render cost:** with the React Compiler on, skip manual memo. Without it, memoize list rows and selectors.
  Keep client props small. Profile before optimizing.
- **Layout stability:** reserve space for async content, ads, images and fonts (`next/font` with metric
  fallbacks).
- **Third-party scripts:** `next/script` `lazyOnload`, and never on critical routes.

## 9. Resilience
- Put an **error boundary per independent section** (`catchError` or `error.tsx`) with a retry. One failing
  widget shouldn't blank the page.
- Retries: idempotent GETs only, with exponential backoff (TanStack `retry`, `retryDelay`). Never retry
  mutations automatically.
- Make the **empty state** distinct from "no results for this filter" (offer to clear filters) and from errors.
- Offline or disconnected: a banner (`useOffline` if enabled, or socket state), mark live data as stale, and queue
  or disable mutations.
- Timeouts on every request (`AbortSignal.timeout`), and a user-facing message for slow responses.

## 10. Accessibility for these patterns
- Search results count: `aria-live="polite"` ("۲۴ نتیجه"), updated after the debounce, not on every keystroke.
- Infinite scroll: a "Load more" button, focus stays put, new items announced politely. Don't trap keyboard users
  above an endless list: give the footer a skip link.
- Skeleton regions: `aria-busy`, one hidden "loading" label.
- Optimistic toggles: `aria-pressed`, and revert the announcement on rollback.
- Virtualized grids: `aria-rowcount`/`aria-rowindex`, and keyboard navigation that scrolls the virtualizer.

## 11. Testing these patterns
| Pattern | Test |
|---|---|
| debounce/throttle hooks | Vitest fake timers (`vi.useFakeTimers()`, `advanceTimersByTime`) |
| Persian normalization, filters, sorters | pure unit tests with tables of cases |
| infinite scroll, virtualization | Vitest **browser mode** (real IntersectionObserver and layout) or Playwright: scroll and assert the next page loads, DOM row count stays bounded |
| search | e2e: type → one request after the debounce (assert with route interception), URL updated, back button restores it |
| optimistic update | component test with MSW returning an error → UI rolls back + toast |
| validation | unit (schema), component (client messages), action test (server rejects what the client would allow if bypassed) |
| skeletons/streaming | `instant()` e2e: the skeleton is visible immediately, then the content arrives |
