# toy_admin — Progress

Daily-puzzle backend + admin: per-feature plans, this rolling ledger.

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Plan of record | ✅ done | `PLAN-daily-puzzles.md` — grilled + settled 2026-10-24 |
| 1 | Scaffold | ✅ done (2026-10-24, coder subagent deepseek-v4.1-flash:cloud, reviewed) | gleam project, mist/wisp, Dockerfile, compose on the bridge network; /api/health live; 46 tests |
| 2 | Puzzle store + derivation | 🟡 core TDD'd, store pending | derivation (star gold 27.57/6.59/2.93/0.54, lossless split) + dates (clamp ±14h, Hinnant civil-from-days, never-past) + ingest (uuid v4, 500-cap, adversarial) — the SQLite store itself is the open half |
| 3 | Public API | ⬜ | puzzle/today (Wordle-style clamp), solve + abandon ingest, throttles/caps |
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
