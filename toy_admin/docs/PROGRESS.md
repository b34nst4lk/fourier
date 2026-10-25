# toy_admin — Progress

Daily-puzzle backend + admin: per-feature plans, this rolling ledger.

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Plan of record | ✅ done | `PLAN-daily-puzzles.md` — grilled + settled 2026-10-24 |
| 1 | Scaffold | ✅ done (2026-10-24, coder subagent deepseek-v4.1-flash:cloud, reviewed) | gleam project, mist/wisp, Dockerfile, compose on the bridge network; /api/health live; 46 tests |
| 2 | Puzzle store + derivation | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, reviewed 2026-10-24: gates re-run (build green — 108 tests inside), wire probes verified from the network (health/none/BadTimezone 400/BadUuid 400), store+throttle+fixture-json code read line-by-line) | derivation (star gold 27.57/6.59/2.93/0.54, lossless split) + dates (clamp ±14h, Hinnant civil-from-days, never-past) + ingest (uuid v4, 500-cap, adversarial) + SQLite store (sqlight): `puzzles` / `attempts`, solve/abandon upsert, per-day stats |
| 3 | Public API | ✅ done (2026-10-25, coder subagent deepseek-v4.1-flash:cloud, reviewed 2026-10-24: gates re-run (build green — 108 tests inside), wire probes verified from the network (health/none/BadTimezone 400/BadUuid 400), store+throttle+fixture-json code read line-by-line) | puzzle/today (Wordle-style clamp, `?tz=`), solve + abandon ingest with stable error names, per-uuid + per-IP fixed-window fences (ETS, env-tuned); DB_PATH on the `toy_admin-data` volume |
| 4 | Admin API + UI | ⬜ | CRUD + menu stats + draw authoring + test-play, Access JWT sanity check |
| 5 | Deploy | ⬜ | tunnel ingress rule, user's CF dashboard steps (Access, rate limit, bot fight), compose up |

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
- Reviewer notes (2026-10-24): plan §8 records the implementation decisions
  the worker left unfolded. The API-layer RED was captured by route-table
  reversion, not natural order (the worker disclosed this; the store/
  fixture/throttle suites ran natural RED-to-GREEN). Fence defaults-on and
  the solved-never-overwritten guard verified in SQL.
