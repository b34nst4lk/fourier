# PLAN — daily puzzle system (toy_admin + fourier_toy + jacks.im)

> Per-feature plan document (first of the new convention — one plan per
> doc, completed plans move to `docs/archive/`). Design settled by grilling,
> 2026-10-24; decisions carry their grill numbers (Q#).

A daily-scheduleable Fourier-tuning puzzle: an OTP-free admin (Cloudflare
Access-gated) where puzzles are drawn, saved, dated, and test-played; a
public toy page that loads the day's puzzle from a same-origin API; and an
anonymous uuid-keyed telemetry loop — run by a Gleam backend in a Docker
container on the home box, exposed through the existing cloudflared tunnel.

Settled decisions are numbered by their grill question (Q#, session of
2026-10-24). Anything not settled here is not silently assumed — it gets
grilled before building.

## 1. The toy page (public, fourier_toy)

- **Q1 — Same URL, dynamic load**:`/toys/fourier-toy` stays put; on load it
  `fetch`es the day's puzzle from the API and renders the puzzle exactly as
  any fixture today (dashed target, comet, dials, counter). The **built-in
  quaver is the fallback** for: no scheduled puzzle, backend unreachable —
  the page must never be broken by the backend (Q5).
- **Q21 — Wordle-style attempt persistence**: dial state, counter,
  solved-flag, and the move list persist client-side (localStorage, keyed
  uuid+date). Reopening the tab resumes exactly where the player left off.
  Attempt = one uuid+date; **abandon triggers are exactly two**: reset, and
  new-day overwrite (an unsolved stored attempt from a previous date
  reports as abandoned when today's page loads over it).
- **Q16 — Site-wide uuid**: one `crypto.randomUUID()` in localStorage
  (`j-uid`, key name TBD at implementation), shared by all jacksim toys;
  clearing cache mints a fresh anonymous identity by design.
- **Q24 — Client-side scoring is a stated design property**: the API
  payload contains the dial truths (as the quaver bundle already does);
  scoring stays local and trust-based. Revisit only if public visibility
  ever appears (leaderboard is parked, Q8).
- Puzzle labeled by **date, not running number** (explicit default).
- The move list is recorded client-side until the first solve
  (counter-freeze boundary); cap at 500 entries (ingest caps below).

## 2. The API (same-origin `jacks.im/api`)

- **Q9 — Same origin, no CORS**: the toy and the API share jacks.im, so
  there is no CORS surface and one TLS/DNS story. "The admin is not
  mentioned or accessible" is realized as: no links, robots disallow, and
  Access walling everything that isn't `/api` public routes — obscurity is
  not load-bearing (TOTP was the plan; Access IS the wall now, Q12).
- Routes (v1):
  - `GET /api/puzzle/today` (+ `tz` offset param) → the visitor-local
    date's puzzle fixture JSON, or `none` (client falls back to quaver).
  - `POST /api/solve` → `{uuid, puzzleDate, moves: [(slot, dir), …]}` on
    first solve. Reproducible record: start state + move list ⇒ final
    state; server derives summaries.
  - `POST /api/attempts/abandon` → `{uuid, puzzleDate, moves: N}` on reset
    or new-day overwrite.
- **Q11 — Visitor-local midnight clamped**: client `getTimezoneOffset()`,
  server clamps to ±14h and **never serves a puzzle past the newest
  published show-date**.
- **Q17 — Duplicate show-dates refused** at save.
- **Ingest integrity (Q22)**: uuid format-validated, moves ≤ 500, per-uuid
  + per-IP backend throttles; **edge** rate-limit rule + **Bot Fight Mode**
  in the CF dashboard (user's side, expressions provided at deploy);
  **Turnstile** is the standing upgrade lever if the data ever matters —
  not in v1. Fake-solve noise is accepted for private stats.
- **Access JWT sanity check**: the backend reads `Cf-Access-Jwt-Assertion`
  on admin routes for presence + audience (full signature verification is
  unnecessary while the tunnel is the only ingress — stated, revisitable).

## 3. The backend (`toy_admin/` in the umbrella)

- **Q15 — In the umbrella**, path dep on `fourier_sketch`'s core;
  **Erlang target** inside Docker (the one Erlang-native piece; the house
  `--target javascript` rule applies to toys' UI code, not this server).
- **Q18 — Stack**: mist + wisp; the admin UI is a Lustre single-file bundle
  embedded in the binary (house single-file rule), served at
  `/api/admin`. Escape hatch noted: if embedding chafes, move the bundle
  to a static `/admin` served by the blog engine + a shifted Access path
  rule — no API contract change. Design family: parchment.
- **Q14 — SQLite** via `sqlight` (NIF build in the Dockerfile): puzzles,
  solve/abandon rows, one file in a volume.
- **Q13 — Own compose project** (compose file in the fourier repo,
  attaching to the external `home_server-network`; the tunnel's ingress
  rule points at it; **no host ports published** — tunnel-only ingress).
  Deploy = ssh + `docker compose up -d --build`; pinned base images.
- **Schema**: `puzzles(id, name, show_date UNIQUE, dots, fixture_json,
  created_at, updated_at)`; `attempts(uuid, puzzle_date, puzzle_id,
  solved, moves nullable, created_at)` (solve rows carry the move list;
  abandon rows carry only the count — uniform stats treatment).
- **Fixture derivation (Q2)**: dots → 512-pt resample → DFT → top-4 by
  amplitude = dial truth; k=0 = centroid; rest = fixed extras. Runs ONCE
  at save; both dots and derived fixture stored (dots = source of truth).
- **Q19 — Dial arrangement is per-puzzle data**: the fixture carries an
  explicit `dials` list; **v1 always emits the standard pattern**
  (phase/radius/k/fixed in amplitude order) — variation machinery exists
  day one, unused, so future experiments need no format migration.

## 4. The admin UI (Cloudflare Access-gated)

- **Q12 — Auth is Cloudflare Access** (path-scoped policy on
  `jacks.im/api/admin*`, user's dashboard, one click-task): login UX = the
  same gate as hermes.jacks.im; no self-built auth in v1.
- **Q2/Q3 — Authoring**: the sketch's draw canvas UI minus the term
  panel; save/edit/delete with name + show-date; the derived truths are
  shown before save; edit re-derives.
- **Q4 — Test-play**: the toy's actual board with a menu of **all** saved
  puzzles regardless of date, plus **test-current-drawing** before save.
- **Q23 — Minimal stats**: per-puzzle attempts / solves / solve % /
  median moves in the menu row (one SQL aggregate endpoint).
- **Q8 — No public score display**; leaderboard parked on the shelf (the
  uuid schema supports it later).

## 5. Deployment split

- **Mine**: backend code + Dockerfile + compose; the tunnel `config.yaml`
  ingress rule (path `^/api(/.*)?$` → `toy_admin:8080`, added ABOVE the
  blog catch-all — first match wins) prepared + verified;
  `toy_admin` joins `home_server-network`; the toy's new bundle through
  the existing blog hermetic pipeline (its manifest entry pins the ref).
- **User's**: Access application on `jacks.im/api/admin*`; CF edge
  rate-limit rule + Bot Fight Mode enablement (exact rule expressions
  provided at deploy); the final `ssh` + `docker compose up -d --build`.

## 6. Gates

- Backend: `gleam test` (Erlang target inside Docker; TDD where logic
  lives — fixture derivation, date logic, ingest validation), docker
  image builds, compose contract (container reachable as `toy_admin:8080`
  on the bridge, no published ports).
- Toy: the existing gates extend — artifact smoke grows the fetch/fallback
  and persistence/resume contracts (jsdom drives the API stub + localStorage).
- The house rule that a failed gate stops the line applies to deploys:
  edge rules and Access go live only after the backend contract is green.

## 7. Shelf (parked, not v1)

- Public leaderboard (needs naming/anti-abuse design; Q8).
- per-move event stream (Q6/Q20 lineage) if a question emerges that
  attempt rows can't answer.
- Turnstile binding on ingest (Q22) — the documented hardening turn.
- Access JWT full signature verification (Q12) — if the ingress surface
  ever grows beyond the tunnel.
- fourier-sketch telemetry on the site-wide uuid (Q16) — free when wanted.
## 8. Implementation decisions (phases 2–3, recorded 2026-10-24)

Decisions made during phase 2/3 (store + public API), folded from the
coder subagent's work post-review — the plan of record is the one place
these live:

- **Attempts rows**: one per `(uuid, puzzle_date)`; columns `solved` + a
  SPLIT storage — `moves` (JSON list, solve rows only) and `move_count`
  (always an integer: solve = the list's length; abandon = the client's
  count). Every row's count stays queryable as a number. `created_at`
  preserved on upsert; re-sent solves REPLACE (idempotent).
- **Solve/abandon require a published puzzle** for that exact show_date
  (`UnknownPuzzle`); a solved row is never overwritten by a later abandon
  (silently `Ok` — a non-event).
- **Envelope + error names are contract**: `{"status":"ok"|"none"|"error",
  "errors":[names]}`; names: `BadUuid`, `BadPuzzleDate`, `TooManyMoves`,
  `BadSlot`, `BadDirection`, `UnknownPuzzle`, `BadTimezone`, `BadRequest`
  (undecodable body), `StoreError` (500), `RateLimited` (429 + Retry-After).
- **tz as `?tz=<minutes>`** — offset to ADD to UTC (the negation of JS
  `getTimezoneOffset`); absent = UTC; unparsable = 400, never a silent
  UTC guess. A calendar gap or a puzzle deleted between store reads
  serves `{"status":"none"}` (the client's quaver fallback), not an error.
- **Fences**: in-memory ETS fixed-window counters (not persisted, forgotten
  on restart — accepted); uuid 20/300s + IP 60/300s defaults,
  env-configurable (`THROTTLE_*`), unparsable/non-positive values fall
  back to defaults (a compose typo must not disable a fence). Request
  order on writes: method → IP fence (headers only) → body → validation →
  uuid fence → store.
- **DB**: `DB_PATH` env (default `data/toy_admin.sqlite3`); compose mounts
  named volume `toy_admin-data` at `/app/data`.
