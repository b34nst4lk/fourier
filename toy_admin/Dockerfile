# toy_admin — the daily-puzzle backend (toy_admin/docs/).
#
# Build context is the UMBRELLA ROOT (fourier/), not toy_admin/, because the
# math core arrives as a path dependency on ../fourier_sketch:
#
#   docker build -f toy_admin/Dockerfile -t toy_admin <fourier-root>
#
# In practice compose does it (toy_admin/compose.yml sets `context: ..`).
# The root .dockerignore keeps that wider context slim.
#
# Stages:
#   base    — pinned toolchain (gleam 1.19.2 / OTP 29.1.2 on alpine) plus the
#             C toolchain the esqlite NIF (sqlight) needs, with
#             dependencies pre-fetched so source edits do not re-resolve.
#   test    — the gate stage: `gleam format --check` then `gleam test` on the
#             ERLANG target (this server is the umbrella's one Erlang-native
#             piece; the house --target javascript rule governs the toys' UI).
#             A failing gate fails the image build — the line stops here.
#   ui      — the admin browser UI:
#             admin_ui/ is a separate --target javascript package, bundled by
#             esbuild into ONE self-contained priv/admin.html. Its own stage,
#             because the backend's test stage must never need node, and its
#             own gate (`gleam test` on the JS target) so a broken UI fails the
#             build here. The bundle is built from source, never checked in.
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
# ---- admin UI bundle -----------------------------------------------------
# node 26-alpine pinned by tag: the npm/esbuild toolchain the bundle needs and
# the Erlang image deliberately does not carry. gleam comes from the SAME
# pinned image as the backend (a musl build, so it runs here), and only the
# javascript target is used — no OTP in this stage at all.
FROM node:26-alpine AS ui
COPY --from=ghcr.io/gleam-lang/gleam:v1.19.2-erlang-alpine /bin/gleam /usr/local/bin/gleam
# bash: the build script is a bash script (set -euo pipefail), like the toys';
# node:alpine ships only /bin/sh.
# python3: the inlining step is the toys' own (build-dist.sh) — same script
# shape, same behaviour.
# esbuild pinned to the version scripts/build-admin-ui.sh names, so the image
# and a host build produce the same bundle.
RUN apk add --no-cache bash python3 \
 && npm install --global --no-fund --no-audit esbuild@0.28.2
WORKDIR /app/toy_admin/admin_ui
COPY toy_admin/admin_ui/gleam.toml toy_admin/admin_ui/manifest.toml ./
RUN gleam deps download
COPY toy_admin/admin_ui/src ./src
COPY toy_admin/admin_ui/test ./test
# The UI's own gates (host-runnable too: `gleam test --target javascript`).
RUN gleam format --check src test
RUN gleam test --target javascript
COPY toy_admin/admin_ui/template.html ./
COPY toy_admin/scripts/build-admin-ui.sh /app/toy_admin/scripts/build-admin-ui.sh
RUN /app/toy_admin/scripts/build-admin-ui.sh

# ---- runtime -------------------------------------------------------------
FROM erlang:29.1.2-alpine AS runtime
WORKDIR /app
COPY --from=build /app/toy_admin/build/erlang-shipment/ /app/
# The SQLite directory. compose mounts the named volume `toy_admin-data` here
# (DB_PATH=/app/data/toy_admin.sqlite3); creating it in the image keeps the app
# working when the volume is absent (a bare `docker run`), because SQLite will
# not create a missing directory for you.
RUN mkdir -p /app/data
# The admin page the backend serves at GET /api/admin, read ONCE at boot
# (admin_ui.load — a missing file is a broken build, not a missing feature, so
# it is baked in here rather than mounted). The path is relative to CWD=/app,
# where entrypoint.sh runs.
COPY --from=ui /app/toy_admin/priv/admin.html /app/priv/admin.html
# The wisp app reads PORT (default 8080) and binds 0.0.0.0 so the tunnel's
# ingress can resolve http://toy_admin:8080 across home_server-network.
ENV PORT=8080
ENV DB_PATH=/app/data/toy_admin.sqlite3
EXPOSE 8080
CMD ["./entrypoint.sh", "run"]
