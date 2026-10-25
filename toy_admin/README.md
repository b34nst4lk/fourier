# toy_admin

The daily-puzzle backend for the fourier toys — the umbrella's one
Erlang-native piece (`docs/PLAN-daily-puzzles.md` §3 Q15). The host box has no
Erlang, so **every** build/test/run here happens inside Docker.

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
ingress, and authentication is Cloudflare Access at that edge (Q12), not here.

```
GET /api/health -> 200 {"status":"ok"}
```

## Layout

| module | role |
| --- | --- |
| `toy_admin.gleam` | route table + mist boot (`handle_request`) |
| `toy_admin/derivation.gleam` | dots → 512-sample DFT → centroid, top-4 dial truth, fixed extras, target trace |
| `toy_admin/dates.gleam` | visitor-local date (clamped ±14h), never-past serving rule, date validation |
| `toy_admin/ingest.gleam` | solve-record validation: uuid v4, ≤500 moves, slot 0..3, dir ±1 |
