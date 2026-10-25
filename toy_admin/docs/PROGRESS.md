# toy_admin — Progress

Daily-puzzle backend + admin: per-feature plans, this rolling ledger.

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Plan of record | ✅ done | `PLAN-daily-puzzles.md` — grilled + settled 2026-10-24 |
| 1 | Scaffold | ✅ done (2026-10-24, coder subagent deepseek-v4.1-flash:cloud, reviewed) | gleam project, mist/wisp, Dockerfile, compose on the bridge network; /api/health live; 46 tests |
| 2 | Puzzle store + derivation | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, reviewed 2026-10-24: gates re-run (build green — 108 tests inside), wire probes verified from the network (health/none/BadTimezone 400/BadUuid 400), store+throttle+fixture-json code read line-by-line) | derivation (star gold 27.57/6.59/2.93/0.54, lossless split) + dates (clamp ±14h, Hinnant civil-from-days, never-past) + ingest (uuid v4, 500-cap, adversarial) + SQLite store (sqlight): `puzzles` / `attempts`, solve/abandon upsert, per-day stats |
| 3 | Public API | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, reviewed 2026-10-24: gates re-run (build green — 108 tests inside), wire probes verified from the network (health/none/BadTimezone 400/BadUuid 400), store+throttle+fixture-json code read line-by-line) | puzzle/today (Wordle-style clamp, `?tz=`), solve + abandon ingest with stable error names, per-uuid + per-IP fixed-window fences (ETS, env-tuned); DB_PATH on the `toy_admin-data` volume |
| 4a | Admin API | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, **reviewed 2026-10-25**) | fence (`Cf-Access-Jwt-Assertion`, audience `ADMIN_ACCESS_AUD`, expiry; NO signature check — documented) + CRUD `/api/admin/puzzles[/<id>]` (create re-derives, edit re-derives on dots change, delete keeps telemetry) + Q23 menu stats (solvePct one decimal, medianMoves of all attempts incl. abandons, nulls on no data) + `envelope.gleam`; 192 tests green in the Docker gate; live wire probes with a hand-crafted JWT |
| 4b | Admin UI | ✅ done + 4 browser fixes (2026-10-25, coder subagent, reviewed) | Lustre bundle (admin_ui/, JS target), draw authoring + preview test-play, menu with Q23 stats, delete confirm; embedded at /api/admin behind the fence; 41 UI tests + 201 backend tests |
| 5 | Deploy | ⬜ (code done: ui stage in Dockerfile, build-admin-ui.sh, ADMIN_ACCESS_AUD env) | tunnel ingress rule, user's CF dashboard steps (Access, rate limit, bot fight), compose up; set `ADMIN_ACCESS_AUD` |
| 5 | Deploy | ⬜ (code done: ui stage in Dockerfile, build-admin-ui.sh, ADMIN_ACCESS_AUD env) | tunnel ingress rule, user's CF dashboard steps (Access, rate limit, bot fight), compose up |

## Notes

- Erlang target inside Docker — the one Erlang-native project in the
  umbrella (house --target javascript rule applies to toys' UI code).
- No host ports published: tunnel-only ingress (backend resolves as
  `toy_admin:8080` on `home_server-network`).
- Auth is delegated to Cloudflare Access (path policy on jacks.im/api/admin*).

- Toolchain note (2026-10-24, review finding): unary `!` compiles on the
  pinned gleam 1.19.2 — the umbrella AGENTS.md "no unary not" note predates
  it. The toys stay on bool.negate (their host gates are older-style);
  toy_admin may use either — the Docker gates are the arbiter.
- Gate mechanism proven adversarially (2026-10-24, reviewer): a sabotaged
  test made `docker compose build` exit 1; restored (checksum-verified),
  exit 0. The marker-forced test stage cannot be skipped.

- Store shape (2026-10-25, phase 2): `attempts` is keyed on
  `(uuid, puzzle_date)` — one row per player per day, so a re-sent solve or an
  abandon after a solve REPLACES/updates rather than appending. `moves` is the
  stored move list (JSON, NULL for an abandon) and `move_count` is always an
  integer, so stats never need to parse JSON. `created_at` is kept while
  `updated_at` moves, which makes "solved at" and "last touched" separable.
  No foreign key to `puzzles`: telemetry outlives a deleted puzzle.
- Fences (2026-10-25, phase 3): fixed windows in one ETS table, not sliding —
  a boundary lets 2x the limit through in the worst case, accepted for a
  nuisance control that is not a security boundary (that is Access at the
  tunnel, Q12). Order on the write routes is IP fence → body read → validation
  → uuid fence → store, so an over-limit caller can never make the server
  parse a junk body.
- Admin API (2026-10-25, phase 4a): decisions with their reasoning live in
  plan §9 — fence semantics + the presence-only fail-safe, the base64url
  finding (stdlib has it; the tests pin RFC 4648 instead), the int-or-float
  drawing wire format from `JSON.stringify`, one-envelope field validation,
  re-derive on dots change, 204-with-no-body delete that keeps telemetry, and
  the Q23 numbers (median of ALL attempts; null, never 0, when there are none).
- Reviewer notes (2026-10-24): plan §8 records the implementation decisions
  the worker left unfolded. The API-layer RED was captured by route-table
  reversion, not natural order (the worker disclosed this; the store/
  fixture/throttle suites ran natural RED-to-GREEN). Fence defaults-on and
  the solved-never-overwritten guard verified in SQL.

- Reviewer notes (4a, 2026-10-25): fence verified on the REAL wire — hand-crafted
  JWTs with a docker-run-set ADMIN_ACCESS_AUD: wrong aud 403, expired 403,
  good aud 200, no token 401 (an earlier 200 came from the probe's env not
  reaching compose-up containers — presence-only fallback, not a code bug;
  the fence also logs presence-only mode once at boot). Full CRUD matrix over
  the wire: save 201, duplicate 409, public solve 200, list stats live
  (attempts/solves/solvePct/medianMoves from a real 2-move solve), PUT 200,
  DELETE 204, unknown id 404. Code read: fence fails safe (presence-only
  without ADMIN_ACCESS_AUD, announced at boot; exp-before-aud justified;
  RFC 7519 aud string-or-array leniency), operation order enforced in one
  fenced() wrapper, stats use exact integer tenths (no float-print drift),
  median includes abandons with the policy documented, no-op restating is a
  true store no-op. Plan §9 folded by the worker itself.

- Reviewer notes (4b, 2026-10-25): all wire claims re-verified from the
  network — UI 401 without a token, 200 text/html (`toy admin — the
  calendar`) with one, preview derives the quad fixture (standard dial
  pattern, centroid, extras, target) and leaves the store untouched
  (puzzles: []), BadDrawing on junk dots. Host gates: admin_ui
  `gleam test --target javascript` 41/41, format clean on both packages.
  Score port is faithful (degrees→radians, extras as rotating epicycles,
  exact integer tenths elsewhere; the star pins the score at truth ≥97%).
  Canvas driver ports the toy's LATEST constants (receded scaffold alphas,
  40–85% comet ramp) and stops its loop when the canvas leaves the DOM —
  the sibling's noted wart, fixed here. Decision notes folded into PLAN
  §10 (boot-cached bundle + 500-on-missing, preview name fallback,
  jsdom-not-a-gate ruling, priv/ ignored).

- Compose carries `ADMIN_ACCESS_AUD: ${ADMIN_ACCESS_AUD}` interpolated from
  the gitignored `.env` next to it (2026-10-25): deployment identifiers stay
  off the public repo; blank/absent = presence-only fail-safe (verified in
  `docker compose config` + access.audience_from's trim rule); compose
  recreates on a .env change (up -d — no rebuild needed).

- AUD enforcement live (2026-10-25): ADMIN_ACCESS_AUD set in the box's .env
  (interpolated; recreated, no rebuild). Wire-verified with the REAL aud:
  wrong-aud 403, real-aud 200, expired 403 (exp-before-aud), no-token 401;
  the presence-only boot warning is gone. Real tokens come from Access
  itself (signed; signature verification remains a shelf item backed by
  tunnel-only ingress).

- **GO-LIVE (2026-10-25, phase 5)**: the tunnel path rule
  (`^/api(/.*)?$ -> http://toy_admin:8080`, above the blog catch-all)
  applied to ~/home_server/cloudflared/config.yaml, `ingress validate` OK,
  match test OK (/api* -> toy_admin, else blog). OPERATIONAL LESSON:
  `docker compose up -d cloudflared` is a NO-OP for bind-mounted config
  changes (the service spec didn't change) — it needs `docker compose
  restart cloudflared`; the 404-from-nginx after "apply" was exactly that.
  Outside verification through Cloudflare: /api/health 200 ok,
  /api/puzzle/today serves the live puzzle, /api/admin 302 to the Access
  login (the app exists and covers jacks.im path-admin), site intact
  elsewhere. AUD provenance verified with the redirect-kid==AUD identity
  (kid equals the application's AUD tag): the .env tag matches the app
  minting jacks.im/api/admin logins — the fence's audience check will
  accept exactly those tokens.

- **4 browser fixes live (2026-10-25)**: (1) swallowed-paint bug on
  view-entry (StartNew/BackToAuthoring: effects fire while the old view
  shows — getElementById null → skip, never retried): draw_render now
  stashes the payload and paints through a self-terminating retry chain
  (measured: the return-repaint lands 1 frame after the view flush; the
  pre-fix contract captured it never landing); (2) the test-play score
  dropped the fixed extras (dial-only 91.888% < 95 vs 99.9999…% chained —
  verified against the live served doc): the score now chains extras at
  truth, picture and number share one terms list; (3) the derived readout
  is per-slot bullets from dial's shared formatters; (4) non-dial slots
  never appear (kind-filtered, Q19 data). New COMMITTED GATE:
  scripts/uismoke.mjs (jsdom render contract over the built
  priv/admin.html: mount-and-paint, per-dot op deltas, return-repaint
  without a tap, envelope words) — promoted from once-out-of-tree to a
  project gate by this bug. Baked prod image verified: the running
  container serves ec0d0bf3… (== local build; curl can't verify prod by
  design — the wall answers first).

- **The authoring live-preview panel (2026-10-25)**: the editing view gains
  the toy's own board LIVE beside the drawing (grilled and settled: truth
  default + a "player start" toggle; read-only; debounced ~300ms on every
  drawing change; the panel never blanks — a refused preview keeps the last
  fixture and shows "preview stale"; two equal columns ≥ 900px, stacked
  below; no score line; the full board's only entry is the panel's
  "open full board" link, the form's "test play" button retired). The
  clock contract: PreviewClock(generation/scheduled/inflight) — superseded
  fires and late answers are no-ops (mutation-proven; a late answer leaves
  the newer request pending), opening the full board voids the panel's
  timer; the canvas driver's boot retry now re-reads the freshest board id
  and play_stop cancels a pending retry. Gates: admin_ui 59/59 (8 new
  preview tests), uismoke 65/65 (23 new, incl. the never-blank and
  one-request contracts), format clean both packages, in-image test stage
  green; host priv/admin.html md5 a8a5d00a4a280630b545d699160e54b1 (96K)
  baked with the rebuild.

- **Bug session: the empty live panel + the canvas's missing delete/move
  (2026-10-25)**: the user reported (1) the preview empty even after three
  dots, (2) no deletion/moving of drawn nodes. Fixed in two commits:
  f2db978 (server) the editor ALWAYS sends {name, showDate} even while both
  are empty strings — validated_preview now reads present-but-empty as "not
  picked yet" (the create route stays strict), so previews that drew first
  answered 400 BadPuzzleDate ALL session; the API test that omitted the
  fields and the smoke's unparse-preferring canned answers both hid it, so
  present-but-empty is its own committed test. d6dfeea (admin_ui) a preview
  answer cleared BOTH clock slots, killing the armed fire when a real-network
  answer landed mid-arm — the panel could stop updating entirely; the answer
  now clears ONLY inflight (RED probe committed). 942af36 (admin_ui) the
  canvas moves/deletes nodes via the sketch's vocabulary (grab/set/drop with
  a one-snapshot drag, click-costs-nothing, right-button delete within
  reach, contextmenu prevented; every real change funnels the panel's
  schedule_preview; mid-drag moves never schedule) — admin declared
  desktop-only, touch-delete parked. Gates by hand at each step; mutation
  checks ran at both ends. Bug-1 fix deployed (bundle db2ef03b…, in-image
  md5 verified, endpoints healthy); the vocabulary build deploys with its
  commit's verification.

- **Bug: the menu's test button answered a bad response (2026-10-25)** — the
  user asked first whether the docker logs explain it; they did not, because
  the backend wired NO request logging (the only line was the boot notice).
  Diagnosed instead by live probe (scripts/probe-single-get.sh, now a
  committed tool: mints a fence-acceptable token from .env and wget's the
  app inside the container — the runtime image has no curl). TWO findings,
  both fixed: (b8b5a81) GET /api/admin/puzzles/<id> nests the fixture inside
  "puzzle" while StartTest decoded a TOP-LEVEL fixture — 200s decoded as
  BadResponse; new decode_saved_fixture reads ["puzzle","fixture]; the edit
  flow's dots read already used the nested shape (its sibling). uismoke S8
  added: the stub had NO single-GET handling at all (the button was never
  smoke-driven — the same stub-shape gap class as the preview-body bug);
  S8's canned shape is the server's, and the pre-fix artifact run fails the
  pin. (3ef20ab) request logging: wisp.log_request middleware + the Erlang
  logger level set to INFO at boot (the default NOTICE swallowed every
  line — verified empirically); '<status> METHOD path' lines now appear in
  the container logs through the tunnel.
