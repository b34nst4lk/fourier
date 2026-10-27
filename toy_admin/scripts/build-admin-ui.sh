#!/usr/bin/env bash
# Build the admin UI into ONE self-contained file: toy_admin/priv/admin.html
# inlines the whole Lustre app (gleam runtime + admin_ui + ffi) as one module
# script, bundled by esbuild — the same single-file pattern as the toys
# (fourier_toy/scripts/build-dist.sh), with the backend's priv/ as its target
# instead of dist/.
#
# Runs on the HOST (no Erlang needed: everything here is --target javascript).
# The Dockerfile's `ui` stage runs the same steps against a pinned node image;
# keep the two in step if either changes.
set -euo pipefail
cd "$(dirname "$0")/../admin_ui"

gleam build --target javascript

cat > .esbuild-entry.mjs <<'EJS'
import { main } from "./build/dev/javascript/admin_ui/admin_ui.mjs";
main();
EJS

# esbuild, pinned: the version is part of the build, not whatever the registry
# serves today. A global/local install wins (the Dockerfile's `ui` stage
# installs exactly this version); on a bare host npx fetches it.
ESBUILD_VERSION=0.28.2
if command -v esbuild >/dev/null 2>&1; then
  ESBUILD=(esbuild)
else
  ESBUILD=(npx --yes "esbuild@${ESBUILD_VERSION}")
fi

"${ESBUILD[@]}" .esbuild-entry.mjs \
  --bundle \
  --format=esm \
  --platform=browser \
  --minify \
  --charset=utf8 \
  --outfile=.esbuild-bundle.js

python3 - <<'PYEOF'
import re
from pathlib import Path

html = Path("template.html").read_text()
bundle = Path(".esbuild-bundle.js").read_text()

if "</script" in bundle.lower():
    raise SystemExit("build: bundle contains '</script' — cannot inline safely")
pattern = re.compile(r'<script type="module">.*?</script>', re.S)
if not pattern.search(html):
    raise SystemExit("build: module script placeholder not found in template.html")
html = pattern.sub(lambda m: '<script type="module">\n' + bundle + "\n</script>", html, count=1)

out = Path("../priv")
out.mkdir(parents=True, exist_ok=True)
Path("../priv/admin.html").write_text(html)
PYEOF

rm -f .esbuild-entry.mjs .esbuild-bundle.js
echo "priv/admin.html ready ($(du -h ../priv/admin.html | cut -f1)) — served verbatim at GET /api/admin"
