# Domain pack: fintech / crypto exchange / trading

Read this in Phase 1 when the brief involves markets, prices, order books, trading, wallets, payments or balances.
It overrides some Express defaults and adds required decisions.

## What changes in the defaults

| Area | Override | Why |
|---|---|---|
| C06 Realtime | **WebSocket** (the exchange's own protocol or a pub/sub client), with an SSE/polling fallback | Order books and tickers change many times per second |
| Money | **No JS floats for prices or amounts.** Use a decimal library (`decimal.js`/`big.js`) or integer minor units (bigint) end to end; strings on the wire | `0.1 + 0.2` and rounding bugs in money are what reviewers check first |
| U05 Tables | TanStack Table + **Virtual** for order books, trade history, market lists | Hundreds of rows updating live |
| U06 Charts | TradingView `lightweight-charts` (client-only, `dynamic(() => import(...))`) | Candles, depth, small canvas |
| A01 Auth | BFF httpOnly session + **2FA (TOTP/SMS) step-up** for withdrawals and API keys; device/session list | Sensitive actions need re-auth |
| X01 Security | Strict CSP, no third-party scripts on trade/wallet routes, `frame-ancestors 'none'` (clickjacking on order buttons) | High-value target |
| I01/I02 | Often fa-IR RTL + Jalali dates + **Latin digits for prices** (configurable), IRT/USDT quote formatting | Local exchanges |
| R01 Rendering | Market pages: **static shell + cached snapshot (`ticker` profile, a few seconds) + live WS island**. Wallet/orders: dynamic, `prefetch='force-disabled'` or `ensureStatic='shell'` | SEO for market pages; freshness and privacy for money |

## Required design items (add to ARCHITECTURE.md)

1. **Market data pipeline:** one socket per tab (the leader tab through `BroadcastChannel` if multi-tab matters),
   channel subscription refcounting (subscribe when the first component mounts, unsubscribe on the last unmount),
   reconnect with jittered exponential backoff, heartbeat/ping, resubscribe and **snapshot resync** after a
   reconnect or a sequence gap, and pause or slow down when `document.hidden`.
2. **Order book model:** a snapshot plus incremental deltas keyed by price level, with sequence numbers. Drop
   out-of-order deltas and resync on a gap. Aggregate by tick size on the client. Render top N levels.
   Throttle renders to ≤ 1 per frame (`createStreamStore`, `recipes.md` §6). Keep it in an external store, not
   React state or TanStack Query.
3. **Ticker and price list:** a normalized map `symbol → {last, change24h, volume}`. Components subscribe by
   symbol with selectors, so one ticker update re-renders one row. Flash up/down with CSS classes, not
   re-mounting.
4. **Order entry:** the form schema is shared between client (RHF + Zod) and the Server Action. Validate tick
   size, lot size, min notional and available balance on the client for UX, and **re-validate on the server**
   (authoritative). Make it idempotent with a client-generated `clientOrderId`. Use `useOptimistic` to show the
   pending order in "open orders", reconciled by the WS order update. Disable double submit.
5. **Balances and wallet:** never cached in shared caches. Use an uncached DAL read in Suspense, or
   `use cache: private` with a short `stale`. Invalidate with `updateTag('user:{id}:balances')` after
   trade, deposit or withdraw actions, and from the WS user channel through `router.refresh()`/query invalidation.
6. **Precision and formatting:** one `shared/lib/money.ts` with `formatPrice(symbol, value)` and
   `formatAmount(asset, value)`, using per-market precision from market metadata. Never `toFixed` on floats.
   Test it heavily (rounding mode, trailing zeros, huge and tiny values, RTL with Latin digits).
7. **Rate limits and errors:** map backend rate-limit codes to user-facing messages, back off on 429, and show
   stale-data banners when the stream is disconnected (with `useOffline` or the socket state).
8. **Security UX:** auto-logout on idle for money routes, confirm dialogs for withdrawals with an address
   whitelist, mask sensitive values, and no secrets or tokens in `localStorage`.

## Route sketch

| Route | Strategy |
|---|---|
| `/` | static shell, cached top markets (`ticker`/`minutes`), live ticker island |
| `/markets` | shell + cached list, live prices island, nuqs filters (quote asset, favourites, sort) |
| `/markets/[symbol]` | ISR (top symbols in `generateStaticParams`) + cached snapshot + WS order book, trades, chart islands; `instant=true` |
| `/trade/[symbol]` (pro view) | app shell + mostly client islands (book, chart, order form, open orders), `prefetch='force-disabled'` for anonymous users |
| `/wallet`, `/orders`, `/settings/security` | authenticated, dynamic, private, `force-disabled` prefetch |

## Tests that matter here

- money formatting and precision (property-based tests with `fast-check` are a strong signal)
- an order-book reducer: snapshot + deltas, out-of-order, gap → resync
- the order form: client validation mirrors the server schema; double-submit prevented
- e2e: browse market → open market page (instant) → place a limit order (mocked backend) → it appears in open orders
- WS resilience: drop the connection in e2e (`page.route`/`context.setOffline`) and assert the stale banner and
  the resync

## Interview talking points

- Why WS data lives in an external store and not in React state or Query (render pressure, selector granularity).
- Why money is strings or decimals end to end.
- Why market pages are PPR (SEO + instant shell) while trading UI is client islands.
- Why the server re-validates everything the client validated.
