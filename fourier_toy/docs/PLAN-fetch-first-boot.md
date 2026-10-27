# PLAN — Fetch-first boot with a last-loaded cache

> Plan of record for `fourier_toy`. Product decisions are **user-ruled**
> (2026-10-27 session); §4 is the TDD spec the coding subagent works against.
> Companion: `PLAN-legibility-pass.md` (lands after this one on the same
> branch), and `../toy_admin/docs/PLAN-varied-starts.md` (independent).

## 0. What changes

Today the board paints the built-in quaver **first**, synchronously, before
any network answer — then swaps to the daily when `GET /api/puzzle/today`
settles. Returning players see a wrong-puzzle flash on every good-network
visit, and the quaver appears even when yesterday's real puzzle is the
honest fallback. New order, user-ruled:

1. **The fetch fires first** — before any canvas sync.
2. If a **last-loaded daily** exists in storage, it paints **optimistically**
   (instant board, no wrong-puzzle flash) while the fetch runs.
3. The fetch **confirms** (same date → nothing to do), **swaps** (new date →
   the existing retire-then-open flow), or **fails / answers "none"** (the
   cached board stands, fully playable, with its own date's semantics).
4. The quaver appears **only on a cold start that finds nothing** — no cache,
   no network — where it keeps today's exact semantics (no storage, no
   telemetry).

The stored attempt (`j-att`), the solve/abandon POSTs, the schema v2, and the
wire decoder are all untouched — this plan only reorders when they fire.

## 1. Decisions (user-ruled, 2026-10-27)

| # | Decision | Ruling |
|---|----------|--------|
| 1 | Fetch first, cache second, quaver last | Approved as proposed (the optimistic variant: the cache paints immediately, the fetch confirms/swaps; not blank-until-fetch). |
| 2 | The cache | A new best-effort localStorage key `j-last` holding the **raw fetched document text** — written on every successful daily load, decoded through the same live `wire.decode` at boot. No version field: the decoder IS the gate (a future format that no longer decodes = cache ignored). |
| 3 | Cached board semantics on fetch failure/"none" | The cached board behaves as a **full daily for its own date**: matching stored attempt resumes (steps persist; an unreported solve re-sends — idempotent, keyed by that date), non-matching opens fresh. When a later fetch names a newer day, the existing retire flow takes it (a spurious fresh attempt from an offline session is abandoned or solved-reported exactly as today's rules do). |
| 4 | Cold start (no cache) | A minimal **loading state**: bar + empty canvas + the three columns with glyphs disabled, no title. It exists only for the fetch's duration on a first-ever visit. |
| 5 | The quaver fallback | Unchanged when reached: paints, plays, stores nothing, tells nothing. |

## 2. Design

`src/fourier_toy.gleam`:

- `init`: theme apply, hold driver, read `j-att` (held, as today) and
  `j-last`; **fetch_effect fires before any canvas sync**. If `j-last`
  decodes, `enter_daily` runs on the cached document immediately (the same
  function the fetch answer takes — resume/retire/fresh logic included, so
  offline play is coherent by construction). Otherwise the model enters
  `Loading` (below) until the fetch settles.
- `PuzzleFetched`: `Ok` → `enter_daily` (same date ⇒ its date-compare paths
  converge to no-ops or the ordinary resume bookkeeping; new date ⇒ the
  existing retire-then-open). `Error`/none → keep whatever is on screen
  (the cached daily, or the loading state if cold — cold failure falls
  through to the quaver).
- `Loading`: a model variant (or flag) rendering bar + canvas + disabled
  glyph columns, no `h2`, no score text. Stepping is impossible (buttons
  disabled), so no attempt bookkeeping can fire against a nonexistent board.
- Storage: `ffi.ls_set("j-last", <raw body>)` inside the existing
  fetch-success path; best-effort like every storage write.
- The FFI is untouched (payload-stash/late-boot already covers any sync
  timing); `ffi.gleam` gains nothing.

## 3. Contracts

- `j-att`, `attempt` v2, the two POST bodies, `reported` re-send: unchanged.
- `wire.decode` reused verbatim for the cache — a cached document that no
  longer decodes is silently ignored (cold boot path).
- The quaver's no-storage/no-telemetry rule is preserved for the cold
  fallback only; a cached daily is real (it has a date and an attempt), so
  it records and reports like any daily.
- Boot contract: no new pins (the FFI payload mechanics are unchanged).

## 4. TDD spec — required tests and expected outcomes

Working agreement: RED first (the artifact smoke's boot sections), seen
failing for the intended reason; then GREEN; all gates green before the
commit. The smoke's jsdom harness already stubs `fetch` with deferred
resolution — it gains latency control for the in-flight states.

### `scripts/artifact_smoke.mjs` — new boot sections (RED first)

- `optimistic cached boot paints before the fetch resolves`: seed `j-last`
  with a served old-format document and `j-att` with a matching-date v2
  attempt; the fetch stub never resolves; after the init flush the board
  shows the cached puzzle's title + date tag, three columns painted (canvas
  stub ops > 0), the resumed counter/solved badge — and **zero POSTs**.
- `same-day confirm is a no-op`: resolve the fetch with the same document —
  no repaint churn (canvas op delta below a frame's paint), no new storage
  writes, an unreported-solve replay fires exactly once (when the seeded
  attempt has `solved:true, reported:false`).
- `new-day swap retires properly`: resolve with a newer date — the held
  attempt is abandoned (or solve-reported) per today's rules, a fresh
  attempt opens, the canvas repaints the new puzzle.
- `offline with cache is a full daily`: fetch rejects; the cached board
  accepts steps (persisted to `j-att` under the cached date), a solve on the
  cached board POSTs once (the same-day idempotent path).
- `cold offline → quaver`: no `j-last`, fetch rejects — the quaver paints,
  zero POSTs, zero storage writes (the existing S8 pins, now reachable via
  the loading state).
- `cold success paints the daily`: no `j-last`, fetch resolves Ok — the
  daily paints (existing pin, re-verified through the loading state).
- `a stale cache that no longer decodes is ignored`: seed `j-last` with
  garbage / an old envelope — cold-boot behavior, no crash.
- `j-last is written on every successful load`: after a successful fetch,
  `j-last` holds the raw body (storage assertion).
- All existing S1–S7/S8 pins stay green (score-vs-core, hold driver, theme,
  edge disables, fallbacks).

Gates: `./scripts/build-dist.sh` → smoke green (record the count);
`node scripts/boot_contract.mjs` 123/123; `gleam test --target javascript`
42/42; `gleam format --check`; bench budgets; dist byte-reproducible.

## 5. Parked

- Service-worker / offline-first beyond the one-document cache.
- Prefetching tomorrow's puzzle at midnight.
- A visible "connecting" treatment beyond the blank loading state.