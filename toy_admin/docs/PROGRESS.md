# toy_admin — Progress

Daily-puzzle backend + admin: per-feature plans, this rolling ledger.

| Phase | Scope | Status | Notes |
|-------|-------|--------|-------|
| 0 | Plan of record | ✅ done | `PLAN-daily-puzzles.md` — grilled + settled 2026-10-24 |
| 1 | Scaffold | ⬜ | gleam project, mist/wisp deps, Dockerfile, compose on the bridge network |
| 2 | Puzzle store + derivation | ⬜ | SQLite, dots→fixture at save, duplicate-date refusal |
| 3 | Public API | ⬜ | puzzle/today (Wordle-style clamp), solve + abandon ingest, throttles/caps |
| 4 | Admin API + UI | ⬜ | CRUD + menu stats + draw authoring + test-play, Access JWT sanity check |
| 5 | Deploy | ⬜ | tunnel ingress rule, user's CF dashboard steps (Access, rate limit, bot fight), compose up |

## Notes

- Erlang target inside Docker — the one Erlang-native project in the
  umbrella (house --target javascript rule applies to toys' UI code).
- No host ports published: tunnel-only ingress (backend resolves as
  `toy_admin:8080` on `home_server-network`).
- Auth is delegated to Cloudflare Access (path policy on jacks.im/api/admin*).
