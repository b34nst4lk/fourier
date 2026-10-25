# toy_admin — the daily-puzzle backend (toy_admin/docs/PLAN-daily-puzzles.md §3).
#
# Build context is the UMBRELLA ROOT (fourier/), not toy_admin/, because the
# math core arrives as a path dependency on ../fourier_sketch (plan Q15):
#
#   docker build -f toy_admin/Dockerfile -t toy_admin <fourier-root>
#
# In practice compose does it (toy_admin/compose.yml sets `context: ..`).
# The root .dockerignore keeps that wider context slim.
#
# Stages:
#   base    — pinned toolchain (gleam 1.19.2 / OTP 29.1.2 on alpine) plus the
#             C toolchain the esqlite NIF (sqlight, plan Q14) needs, with
#             dependencies pre-fetched so source edits do not re-resolve.
#   test    — the gate stage: `gleam format --check` then `gleam test` on the
#             ERLANG target (this server is the umbrella's one Erlang-native
#             piece; the house --target javascript rule governs the toys' UI).
#             A failing gate fails the image build — the line stops here.
#   build   — the release shipment (`gleam export erlang-shipment`).
#   runtime — slim OTP runtime running the wisp app on $PORT (default 8080).

FROM ghcr.io/gleam-lang/gleam:v1.19.2-erlang-alpine AS base

# sqlight -> esqlite -> rebar3 -> cc on the bundled SQLite amalgamation.
RUN apk add --no-cache build-base

WORKDIR /app/toy_admin
COPY fourier_sketch/gleam.toml fourier_sketch/manifest.toml /app/fourier_sketch/
COPY toy_admin/gleam.toml toy_admin/manifest.toml /app/toy_admin/
RUN gleam deps download

# ---- gates ---------------------------------------------------------------
FROM base AS test
COPY fourier_sketch/src /app/fourier_sketch/src
COPY toy_admin/src /app/toy_admin/src
COPY toy_admin/test /app/toy_admin/test
RUN gleam format --check src test
RUN gleam test --target erlang
# Gate marker: the release stage copies this file, which forces the gate stage
# to run as part of EVERY image build (a plain `docker build` must not be able
# to skip the tests by not depending on them).
RUN touch /app/gates-passed

# ---- release -------------------------------------------------------------
FROM base AS build
COPY --from=test /app/gates-passed /app/gates-passed
COPY fourier_sketch/src /app/fourier_sketch/src
COPY toy_admin/src /app/toy_admin/src
RUN gleam export erlang-shipment

# ---- runtime -------------------------------------------------------------
FROM erlang:29.1.2-alpine AS runtime
WORKDIR /app
COPY --from=build /app/toy_admin/build/erlang-shipment/ /app/
# The wisp app reads PORT (default 8080) and binds 0.0.0.0 so the tunnel's
# ingress can resolve http://toy_admin:8080 across home_server-network.
ENV PORT=8080
EXPOSE 8080
CMD ["./entrypoint.sh", "run"]
