#!/usr/bin/env bash
# Build the static bundle: dist/ holds index.html + compiled Gleam JS.
# Serve dist/ with any static file server, e.g.
#   cd dist && node ../scripts/dev-server.mjs
# The module import is rewritten to a relative path so dist/ works at any
# mount depth (/, /toys/fourier-sketch/...).
set -euo pipefail
cd "$(dirname "$0")/.."

gleam build --target javascript
rm -rf dist
mkdir -p dist
cp index.html dist/
mkdir -p dist/build/dev
cp -r build/dev/javascript dist/build/dev/
sed -i 's|"/build/|"build/|g' dist/index.html
echo "dist/ ready ($(du -sh dist | cut -f1)) — serve it statically"