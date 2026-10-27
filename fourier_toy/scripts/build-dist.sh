#!/usr/bin/env bash
# Build a SINGLE self-contained HTML file: dist/index.html inlines the whole
# Lustre app (gleam runtime + fixtures + ffi) as one module script, bundled
# by esbuild — the house single-file pattern.
set -euo pipefail
cd "$(dirname "$0")/.."

gleam build --target javascript

cat > .esbuild-entry.mjs <<'EJS'
import { main } from "./build/dev/javascript/fourier_toy/fourier_toy.mjs";
main();
EJS

npx --yes esbuild .esbuild-entry.mjs \
  --bundle \
  --format=esm \
  --platform=browser \
  --minify \
  --charset=utf8 \
  --outfile=.esbuild-bundle.js

python3 - <<'PYEOF'
import re
from pathlib import Path

html = Path("index.html").read_text()
bundle = Path(".esbuild-bundle.js").read_text()

if "</script" in bundle.lower():
    raise SystemExit("build: bundle contains '</script' — cannot inline safely")
pattern = re.compile(r'<script type="module">.*?</script>', re.S)
if not pattern.search(html):
    raise SystemExit("build: module script placeholder not found in index.html")
html = pattern.sub(lambda m: '<script type="module">\n' + bundle + "\n</script>", html, count=1)

dist = Path("dist")
if dist.exists():
    import shutil
    shutil.rmtree(dist)
dist.mkdir()
Path("dist/index.html").write_text(html)
PYEOF

rm -f .esbuild-entry.mjs .esbuild-bundle.js
echo "dist/index.html ready ($(du -sh dist | cut -f1)) — ONE file, deploy by copying it"
