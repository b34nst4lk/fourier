#!/usr/bin/env bash
# Assemble prototypes/dist/index.html: bundle src/app.js (which imports
# proto.js + puzzle.js) with esbuild, inline it into template.html.
# ONE self-contained file — no external module tree can break on a static host.
# Runs inside the hermetic clone; esbuild resolves via npx (cached on the box).
set -euo pipefail
cd "$(dirname "$0")"

npx --yes esbuild src/app.js \
  --bundle \
  --format=esm \
  --platform=browser \
  --minify \
  --charset=utf8 \
  --outfile=.bundle.js

python3 - <<'PYEOF'
from pathlib import Path

tpl = Path('template.html').read_text()
bundle = Path('.bundle.js').read_text()

if '</script' in bundle.lower():
    raise SystemExit("build: bundle contains '</script' — cannot inline safely")
if tpl.count('{{APP_JS}}') != 1:
    raise SystemExit('build: template must hold exactly one {{APP_JS}} placeholder')
# links are rendered at runtime from the PUZZLES map — check its ids;
# the actual card rendering is verified by the jsdom artifact checks
for i in range(1, 10):
    if ('p%d' % i) not in bundle:
        raise SystemExit('build: missing experiment id p%d' % i)

out = tpl.replace('{{APP_JS}}', bundle)
dist = Path('dist')
if dist.exists():
    import shutil
    shutil.rmtree(dist)
dist.mkdir()
Path('dist/index.html').write_text(out)
PYEOF

rm -f .bundle.js
echo "dist/index.html ready ($(wc -c < dist/index.html) bytes) — one file, deploy by copy"