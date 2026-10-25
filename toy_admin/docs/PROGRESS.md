# toy_admin — Progress

Daily-puzzle backend + admin: per-feature plans, this rolling ledger.

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Plan of record | ✅ done | `PLAN-daily-puzzles.md` — grilled + settled 2026-10-24 |
| 1 | Scaffold | ✅ done (2026-10-24, coder subagent deepseek-v4.1-flash:cloud, reviewed) | gleam project, mist/wisp, Dockerfile, compose on the bridge network; /api/health live; 46 tests |
| 2 | Puzzle store + derivation | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, reviewed 2026-10-24: gates re-run (build green — 108 tests inside), wire probes verified from the network (health/none/BadTimezone 400/BadUuid 400), store+throttle+fixture-json code read line-by-line) | derivation (star gold 27.57/6.59/2.93/0.54, lossless split) + dates (clamp ±14h, Hinnant civil-from-days, never-past) + ingest (uuid v4, 500-cap, adversarial) + SQLite store (sqlight): `puzzles` / `attempts`, solve/abandon upsert, per-day stats |
| 3 | Public API | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, reviewed 2026-10-24: gates re-run (build green — 108 tests inside), wire probes verified from the network (health/none/BadTimezone 400/BadUuid 400), store+throttle+fixture-json code read line-by-line) | puzzle/today (Wordle-style clamp, `?tz=`), solve + abandon ingest with stable error names, per-uuid + per-IP fixed-window fences (ETS, env-tuned); DB_PATH on the `toy_admin-data` volume |
| 4a | Admin API | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, **reviewed 2026-10-25**) | fence (`Cf-Access-Jwt-Assertion`, audience `ADMIN_ACCESS_AUD`, expiry; NO signature check — documented) + CRUD `/api/admin/puzzles[/<id>]` (create re-derives, edit re-derives on dots change, delete keeps telemetry) + Q23 menu stats (solvePct one decimal, medianMoves of all attempts incl. abandons, nulls on no data) + `envelope.gleam`; 192 tests green in the Docker gate; live wire probes with a hand-crafted JWT |
| 4b | Admin UI | ✅ done (2026-10-25, coder subagent, reviewed) | Lustre bundle (admin_ui/, JS target), draw authoring + preview test-play, menu with Q23 stats, delete confirm; embedded at /api/admin behind the fence; 41 UI tests + 201 backend tests |
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
