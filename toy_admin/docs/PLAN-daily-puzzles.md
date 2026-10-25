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
  median moves in the menu row (one endpoint, four numbers).
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

## 9. Implementation decisions (phase 4a — admin API, recorded 2026-10-25)

The fence, CRUD and stats layer. Same discipline as §8: the decisions the
worker had to make, with the reasoning, so the plan stays the one place they
live. The admin UI half of phase 4 (draw canvas, menu, test-play) is still
open; this section governs the backend it will talk to.

- **Fence semantics (Q12)**: `Cf-Access-Jwt-Assertion` presence is required
  (missing/blank → **401 `Unauthorized`**). With `ADMIN_ACCESS_AUD` set, the
  payload must be a JSON object whose `aud` contains that value (string or
  array, RFC 7519) and whose `exp >= now`; refusal is **403 `Forbidden`** for
  every claim failure (the UI's reaction to all of them is "log in again", so
  they share one name; `access.Failure` keeps the diagnostic).
  **No signature verification** — documented loudly in `access.gleam`: the
  tunnel is the only ingress (no host ports, Q13), Access minted the token for
  an admitted request, and full JWKS verification stays on the shelf (§7).
  Expiry is checked before audience: a stale certificate is stale whoever it
  names.
- **`ADMIN_ACCESS_AUD` unset/blank = presence-only**, and it *logs once at
  boot* (`logging.log(Warning, ...)` from `main`, text pinned by a test). It
  fails toward "still needs a Cloudflare token", never toward "wide open": an
  unauthenticated caller who never passed Access has no header and gets 401.
  A value of spaces is treated as unset, not as "the empty audience matches
  everything".
- **base64url**: no new dependency and no hand-written codec — gleam_stdlib
  1.x already ships `bit_array.base64_url_encode/decode` on both targets. The
  brief's "implement it pure IF the stdlib lacks it" condition is not met, so
  the tests instead PIN the RFC 4648 vectors, the URL-safe alphabet swap
  (`+/` ↔ `-_`), and unpadded decode (JWT segments are unpadded, RFC 7515) —
  a stdlib bump that changes any of them goes RED next to the explanation.
- **Drawing wire format**: `dots` is a JSON array of `[x, y]` NUMBER pairs, in
  and out (`fixture_json.dots_decoder` / `dots_to_json`). It accepts **ints**
  as well as floats: JavaScript's `JSON.stringify` emits `10`, not `10.0`, and
  the canvas sends whole-number coordinates all day. Both spellings normalise
  to the sketch's `#(Float, Float)`. Stored `dots` keeps the same encoding, so
  stored = served = authored.
- **Create/update validation** (`admin.gleam`): `name` non-empty after
  **trimming** (`BadName`; a body with no `name` is a blank name, not a broken
  request), `showDate` valid (`BadPuzzleDate`), `dots` non-empty array of pairs
  **and** deriving to a non-degenerate fixture (`BadDrawing`, decided by
  `derivation.is_degenerate`, i.e. by the empty fixture that the core's 3-dot
  gate produces — one gate, not two). All present-and-bad fields are reported
  in ONE envelope, in field order, so the editor underlines both at once.
  Only an undecodable body is `BadRequest`.
- **Update is partial** (`name?`, `showDate?`, `dots?`): absent fields are
  left alone, and `{}` is a coherent no-op (the store writes nothing and does
  not bump `updated_at`). A **dots change re-derives** the fixture from the
  new drawing with the effective name/date (Q2/Q3); a name/date change rewrites
  the fixture's embedded copy without re-running the DFT (the numbers do not
  depend on the labels — the served document takes identity from the row).
  A collision with ANOTHER puzzle's show_date is **409 `DuplicateShowDate`**;
  keeping its own date is fine. Unknown id → **404 `UnknownPuzzle`** for GET,
  PUT and DELETE; a non-numeric id is 404 whatever the method.
- **Delete is 204 with an EMPTY body**, and the puzzle's attempt rows are
  KEPT (no FK, no cascade): deleting a calendar entry must not rewrite history.
- **Stats (Q23)**: `attempts` = attempt rows (solves + abandons), `solves` =
  solved rows, `solvePct` = one decimal computed in integer tenths, half-up
  (`"97.3"`), **null** when `attempts = 0`; `medianMoves` = median of ALL
  attempts' `move_count` — **an abandon counts with its own reported count**
  (the question is "how many moves does this puzzle take", not "how many did
  the winners need") — as a Float (even counts average the middle two),
  **null** when `attempts = 0`. Null, never `0`/`"0.0"`: "no data" is not "0%".
  The list route reads stats per puzzle (2 small queries each, N+1 by design);
  if the calendar ever grows to thousands this is the one place to fold into
  a `GROUP BY`.
- **Admin responses**: `GET /api/admin/puzzles` → `{"status":"ok","puzzles":
  [{id,name,showDate,attempts,solves,solvePct,medianMoves}, ...]}`, newest
  `show_date` first (then id). `POST` → **201** `{"status":"ok","puzzle":
  <full row>}`; `GET <id>` and `PUT <id>` → **200** with the same full-row
  document: `{id,name,showDate,dots,fixture,createdAt,updatedAt}` where
  `dots` and `fixture` are PARSED back out for the editor and the timestamps
  are **epoch seconds** (the store's unit; no ISO strings, no timezone in a
  number). New error names `BadName` and `BadDrawing` join the §8 vocabulary.
- **Envelope**: `ok_empty` / `ok_with` / `created_with` / `error_response` /
  `rate_limited` / `none_response` moved into `src/toy_admin/envelope.gleam`
  (public routes and admin routes answer in the same vocabulary — one module,
  checked once). 405s come from wisp (`method_not_allowed` with an accurate
  `allow` header, plain text exactly as on the public routes).
- **Order of operations, every admin route**: fence → path id → method →
  body → validation → derivation → store. The fence runs BEFORE the method
  check, so an unfenced caller learns nothing — not even which methods a path
  takes.
- **Config**: `ADMIN_ACCESS_AUD` (new; the Access application's audience tag),
  alongside `DB_PATH` and `THROTTLE_*`. Header name: `Cf-Access-Jwt-Assertion`
  (lowercase in code, HTTP headers being case-insensitive). `compose.yml`
  carries the variable as a commented line — set it from the Access dashboard
  at deploy; leaving it out is the presence-only mode described above.


## 10. Implementation decisions (phase 4b — the admin UI, recorded 2026-10-25)

- **The UI is a separate Gleam package** (`toy_admin/admin_ui/`, JS target,
  deps: lustre + gleam_json only — no math packages on the client) built to
  ONE self-contained `priv/admin.html` (esbuild pinned in its node stage;
  house single-file rule), **boot-cached** by the backend (read once at
  boot: the bundle cannot change while the process runs; a missing bundle
  is a broken BUILD — the route answers a plain 500 and the boot log says
  so). Served verbatim at `GET /api/admin`, behind the same fence.
- **Preview endpoint** (`POST /api/admin/preview`, fenced): derive a
  fixture from UNsubmitted dots with no store write — the mechanism behind
  "test the current drawing before saving" (Q4); previewing over a taken
  date is legal (a preview is not a create) and writes nothing. A blank
  name borrows the previewed date.
- **Client-side scoring lives in the UI** (`admin_ui/score.gleam`, ported
  from fourier_toy/shapes: position_at / synth_trace / rms_pointwise /
  rms_polar / match_pct, extras chained as rotating epicycles) — the one
  duplicated piece of math, documented; `fourier_core` extraction remains
  the plan-parked way to dissolve it.
- **The draw-canvas/test-play driver** ports the toy's loop with its latest
  constants verbatim (receded scaffold alphas, 40–85% comet ramp, DPR ≤ 2,
  30fps cap) — plus a deliberate improvement: the loop STOPS when its
  canvas leaves the DOM (view swaps no longer keep the CPU awake; the
  sibling's noted wart, fixed at the port).
- **jsdom is not a project gate here** (review ruling with the worker):
  the in-image gleam suites + wire probes cover the UI contract at this
  scale; adding node_modules to the image for jsdom is a separate decision
  if the UI grows complex enough to warrant render contracts.
- `priv/` is a build artifact (never committed) — same rule as the toys'
  `dist/`; `admin_ui/manifest.toml` IS committed (it pins the dep set).

## 11. Implementation decisions (toy-side integration + patches, recorded 2026-10-25)

- **The fixture carries `patches`** (the puzzle's starting dial states) —
  derived at save by the STANDARD vocabulary, constants in
  `derivation.gleam`: `start_radius_pct = 73.0` (of dial_max_r),
  `start_k_shift = -2` (the umbrella's recorded "k −2 on the kind-3 slot"
  vocabulary — the review brief's −5 was a slip; the quaver gold test
  KSet(−5) keeps the generalisation honest), phase = truth + 90° then
  **snapped to the 5° dial grid** (a patch phase must be reachable by
  steps!), fixed slot = Keep. Wire encoding: one object per slot,
  `{"kind":"phase","deg":355} | {"kind":"radius","pct":73} | {"kind":"k",
  "k":-5} | {"kind":"keep"}` — named kinds, nothing positional.
- **Toy wire decode** (`fourier_toy/src/fourier_toy/wire.gleam`): the whole
  envelope decodes; `dials` (arrangement) is DATA (Q19); numbers accept
  int-or-float (browser JSON.stringify emits ints); the board contract is
  4/4/4 — anything else falls back rather than crash.
- **Identity + attempts in the toy (Q16/Q21)**: identity `j-uid`
  (crypto.randomUUID, created on first visit); attempt state `j-att`
  (one JSON object: v, date (the SHOW DATE it belongs to), state (dial
  array), moves ([slot,dir] pairs until the freeze), count, solved,
  reported). Resume restores dials/counter/solved badge exactly; a solve
  POSTs `/api/solve` once and marks `reported`; a solve that never
  confirmed re-POSTs on the next boot (the store's upsert makes the
  duplicate free); abandon fires on reset (unsolved, count > 0) and on
  new-day overwrite, carrying the OLD attempt's data before it is
  replaced. Post-solve steps are neither counted nor recorded.
- **Fallback = no telemetry**: the built-in quaver is not a published
  puzzle (`UnknownPuzzle` would reject its solve reports by design), so
  the fallback mode writes nothing — documented, deliberate.
- **The toy's match for dailies**: client-side (Q24), the normalizer
  (`rms_polar`) recomputed from the served target — `shapes.from_parts`
  is the fetched-puzzle seam; the built-in quaver path is untouched.
- **The date is presented subordinate to the name**: `<name> · <date>` in
  a `.when` span; the fallback shows just `quaver`.

## 12. Remaining deployment steps (as of 2026-10-25, post go-live)

LIVE behind Access: the tunnel path rule `^/api(/.*)?$ → http://toy_admin:8080` sits ABOVE the blog catch-all (applied + cloudflared RESTARTED — `up -d` is a no-op for bind-mounted config changes — and verified through Cloudflare: /api/health 200 ok, /api/puzzle/today serves the day's puzzle, /api/admin 302 to the Access login, site intact elsewhere; AUD provenance kid==AUD against the gitignored .env tag). The toy's daily integration is published (blog pipeline 9bd2663) and the cross-repo seam verified live end-to-end. Remaining:
(1) the USER'S dashboard items (agent cannot touch): the edge rate-limit rule (solve/abandon paths, >30/min per IP) + Bot Fight Mode;
(2) the toy page's last blog publish (9bd2663) predates the theme revamp (2eefd90) — re-publish through the blog pipeline (`make deploy`) so the live page carries the B/W palette;
(3) the authoring live-preview panel (§13 below) deploys as a container rebuild with its commit.

## 13. Implementation decisions (the authoring live-preview panel, recorded 2026-10-25)

The grill's settled answers (one at a time, user):
- **State (Q1)**: TRUTH by default — judge the shape you drew (the comet traces the target); a small-caps toggle peeks at the PLAYER'S START (the fixture's own patches applied — judge the challenge). Labels: "solved view" / "player start".
- **Read-only (Q2)**: the panel renders; steppers stay in the full board — the panel's job is seeing, not playing.
- **Live (Q3)**: debounced ~300ms on EVERY drawing change (DotsTapped / Undo / Clear / DotsLoaded). The panel NEVER blanks: a refused preview keeps the last fixture rendering and shows a "preview stale" hint; the next good answer clears it.
- **Layout (Q4)**: two equal columns ≥ 900px (`.studio`: drawing left, panel right), stacked below (drawing first). The full-screen test-play REMAINS — its ONLY entry is the panel's "open full board" link; the form's own "test play" button was RETIRED in review (one affordance per Q4c; smoke reworded accordingly).
- **No score line (Q5)**: the panel is a shape-preview; Match % stays in the full board (at the start-state the same number measures the perturbation and invites misreading).

Implementation decisions (worker, verified in review):
- **Debounce seam = an FFI timer slot** (`fetch.mjs` `preview_after`): one module-local handle, every call clears the previous timer — a burst leaves exactly one timer. The TEST seam is the message: arming dispatches `PreviewFire(generation)` when the window expires; tests dispatch that message by hand (same message, same guard).
- **The clock = `PreviewClock(generation, scheduled, inflight)`**: every drawing change bumps the generation and names the armed timer; a fire whose generation isn't `scheduled` is a no-op; an answer whose generation isn't `inflight` is DISCARDED — a superseded answer leaves the newer request pending (not None). Two independent layers (timer-cancel + generation guards), deliberate redundancy, mutation-proven: dropping either leaves exactly one request standing.
- **`invalidate_preview` kills the clock** on Preview (full board), BackToMenu, StartNew, StartEdit and Saved(Ok) — opening the full board voids the panel's timer, so a late panel fire can never post into the play view.
- **One canvas driver, two board ids** (`play-board` full board, `preview-board` panel): every `play_*` call names its canvas first; the boot retry re-reads the FRESHEST requested id (`want_id`) rather than the id its own chain started with, so a remount can never attach the loop to a canvas about to leave the DOM; `play_stop` also cancels a still-pending boot retry (stop-then-panel ordering). The two boards are never mounted at once.
- **Start = `dial.initial` over the fixture's OWN patches** (the standard set when the fixture carries none) — the same derivation the full board boots with; the toggle is a repaint, never a request.
- **Read-only rows reuse the full board's formatters** (same words and numbers, steppers omitted; non-dial slots skipped by KIND — the arrangement is data).
- **Mutation-tested**: both generation guards bite (failures under mutation, source restored; suites green after).

## 14. Implementation decisions (the authoring canvas's pointer vocabulary, recorded 2026-10-25)

- **The admin page is DESKTOP-ONLY (user, 2026-10-25)** — only the toy itself
  must be mobile-friendly. The authoring canvas's delete affordance is the
  right pointer button (no right-click on touch); touch-delete is PARKED, not
  designed.
- **The vocabulary is fourier_sketch's, ported verbatim**: press within
  `hit_radius = 3.0` units (the family's constant, pinned by a parity test in
  the same 0..100 space) on the LEFT button grabs the nearest dot — the dot
  follows the pointer (`set`, no history) — and the release closes the drag:
  a real move = exactly ONE undo step and ONE preview schedule; a press that
  never moves (or drags back to the exact start) pops its own snapshot — a
  click costs nothing, adds nothing. Press on empty space with the LEFT
  button adds a dot (unchanged). The RIGHT button deletes the nearest dot in
  reach, deletes NOTHING when none is in reach. Other buttons are ignored.
  `nearest` uses squared distances with ties to the earliest index (the
  sketch's rule). Up AND pointerleave close the drag (a drag released off
  the panel cannot stay open); the browser contextmenu is prevented and
  ignored. Mid-drag moves repaint ONLY — the drop schedules the preview (the
  debounce cannot fire once per pointermove sample).
- **The editor deliberately keeps the polygon path** (no sketch smoothing):
  it shows what the derivation will actually resample.

## 15. Implementation decisions (agent drafts — the local agent's door, recorded 2026-10-25)

- **Two agent routes, one shared key**: GET /api/agent/schedule (the calendar
  with the Q23 stats, published AND drafts, read-only) and POST
  /api/agent/puzzle (an UNDATED draft: name + dots, nothing else). Fenced by
  a once-at-boot bearer key: AGENT_API_KEY / AGENT_ID in the gitignored .env,
  compose-interpolated with empty-safe defaults; unset = both answer 401
  AgentAuth plus ONE boot warning (the AUD fence's fail-safe direction). The
  comparison is plain ==: declared acceptable — a local bridge network, an
  undated draft is the worst outcome, and the shelf notes constant-time
  compare next to the JWT-signature item.
- **Agents never schedule**: a non-empty showDate in an agent POST is 400
  AgentNoScheduling — refuse, never silently drop. A silent date would lie
  to the agent and the human would never see the attempt.
- **The store's two-state model**: puzzles.status (draft|published) and
  .creator (the agent's id; 'human' by default) via a rename-and-copy
  migration in ONE transaction (the presence of `status` is the version
  marker; a mid-failure must roll back or the next boot would strand the
  data in puzzles_phase_4a while believing migration done). The show-date
  UNIQUE became a PARTIAL index over published rows only (drafts share '').
  show_date == '' ⟺ status == draft, derived together on every write.
- **Publish is the human's act**: the admin PUT accepts an OPTIONAL showDate
  — absent = no change; '' = draftify (re-pull from the calendar); a date =
  approve (the duplicate-date rule, published-only). The row-level approve
  flow sends the ONE-field PUT so approving cannot change what it approves.
- **`/api/puzzle/today` serves published rows only** — a draft can never
  serve; attempts stay keyed by (uuid, puzzle_date) and unpublishing never
  deletes them.
- **The next free day is a browser rule**: both date fields (new puzzle,
  approve) prefill "the first day on or after today no row occupies"
  (admin_ui schedule.gleam: Hinnant civil-from-days/days-from-civil, exact
  for the proleptic Gregorian calendar; drafts hold no day; the server has
  no opinion — it validates and refuses duplicates as ever).
- **Reach**: toy_admin joins the agent's docker network (br-pi, external,
  name-pinned) so hermes-jacksim calls http://toy_admin:8080/api/agent/*
  by container name. Nothing host-published for this; the admin routes stay
  Cloudflare-Access-gated exactly as they were.
