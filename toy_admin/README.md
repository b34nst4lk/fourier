# toy_admin

The daily-puzzle backend for the fourier toys — the umbrella's one
Erlang-native piece. The host box has no Erlang, so **every** build/test/run
here happens inside Docker.

Shipped and serving. Design history lives in `docs/archive/`; `docs/PROGRESS.md`
is the rolling ledger.

## Gates

The Dockerfile's `test` stage is the gate: `gleam format --check` then
`gleam test --target erlang`. The release stage copies that stage's marker
file, so a plain image build cannot skip the tests — a red test fails the
build.

```sh
# whole image, gates included (context is the umbrella root: the math core
# arrives as a path dependency on ../fourier_sketch)
docker build -f toy_admin/Dockerfile -t toy_admin .
```

For a faster edit/test loop, reuse the builder stage and bind-mount the tree:

```sh
docker build --target base -f toy_admin/Dockerfile -t toy-builder .
docker run --rm -u $(id -u):$(id -g) \
  -e HOME=/tmp/h -e HEX_HOME=/tmp/h/.hex -e REBAR_CACHE_DIR=/tmp/h/.cache/rebar3 \
  -v "$PWD":/work -w /work/toy_admin toy-builder \
  sh -c 'gleam format --check src test && gleam test --target erlang'
```

## Run

```sh
cd toy_admin && docker compose up -d --build   # container_name: toy_admin
```

The wisp app listens on `$PORT` (default 8080) bound to `0.0.0.0` and joins the
external `home_server-network`, so the cloudflared tunnel reaches it as
`http://toy_admin:8080`. No host ports are published — the tunnel is the only
ingress, and authentication is Cloudflare Access at that edge, not here.

```sh
# state lives in a named volume (toy_admin-data) at DB_PATH; the app creates the
# schema at boot, so a fresh volume is a working empty store
docker compose exec toy_admin ls -l /app/data
```

```sh
GET  /api/health            -> 200 {"status":"ok"}
GET  /api/puzzle/today?tz=<minutes>
                            -> 200 {"status":"ok","puzzle":{...}}   a puzzle to serve
                            -> 200 {"status":"none","fallback":true} nothing published yet
POST /api/solve             -> 200 {"status":"ok"} | 404 UnknownPuzzle | 400 <problems>
POST /api/attempts/abandon  -> 200 {"status":"ok"} | 404 UnknownPuzzle | 400 <problems>
```

Every answer carries `status` (`ok`/`none`/`error`); failures also carry
`errors: ["BadUuid", "BadPuzzleDate", "TooManyMoves", "BadSlot", "BadDirection",
"UnknownPuzzle", "BadTimezone", "BadRequest", "RateLimited", "StoreError"]` —
those names are the client's vocabulary and a contract with the toys.

`tz` is the offset **to add to UTC** in minutes (the negation of JavaScript's
`getTimezoneOffset()`), clamped to ±14h; absent means UTC. It is a query
parameter rather than a header so the answer is reproducible from a URL and
visible in logs.

## Configuration

| variable | default | meaning |
| --- | --- | --- |
| `PORT` | `8080` | listen port (bound to `0.0.0.0`) |
| `DB_PATH` | `data/toy_admin.sqlite3` | SQLite file; compose sets `/app/data/toy_admin.sqlite3` on the volume |
| `THROTTLE_UUID_LIMIT` / `THROTTLE_UUID_WINDOW_SECONDS` | `20` / `300` | per-player fence on the write routes |
| `THROTTLE_IP_LIMIT` / `THROTTLE_IP_WINDOW_SECONDS` | `60` / `300` | per-address fence, checked before the body is read |
| `SECRET_KEY_BASE` | dev placeholder | reserved for sessions; unused today |

Unparsable or non-positive throttle values fall back to the default rather than
switching a fence off. The counters are in-memory (an ETS table), reset by a
restart, and not shared between replicas — deliberately no persistence.

## Layout

| module | role |
| --- | --- |
| `toy_admin.gleam` | route table + mist boot (`handle_request`) |
| `toy_admin/derivation.gleam` | dots → 512-sample DFT → centroid, top-4 dial truth, fixed extras, target trace |
| `toy_admin/dates.gleam` | visitor-local date (clamped ±14h), never-past serving rule, date validation |
| `toy_admin/ingest.gleam` | solve-record validation: uuid v4, ≤500 moves, slot 0..3, dir ±1 |
| `toy_admin/store.gleam` | SQLite (sqlight): schema, puzzle CRUD reads, solve/abandon upserts, per-day stats |
| `toy_admin/fixture_json.gleam` | the stored-fixture / served-puzzle JSON contract (dots added on serve) |
| `toy_admin/throttle.gleam` | fixed-window request fences (ETS), pure window math + env config |
| `toy_admin/dates.gleam` / `clock.gleam` | civil dates; the one wall-clock read |
| `toy_admin/env.gleam` | binary-safe `os:getenv`/`os:putenv` (Erlang speaks charlists) |
