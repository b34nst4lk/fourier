#!/usr/bin/env bash
# One-time setup for the SVG->dots pipeline. System python has no pip (PEP 668),
# so deps live in a cache venv; svg_pipeline.py re-execs into it automatically.
# Kept OUT of the skill dir so the skill stays portable.
set -euo pipefail
VENV="${FOURIER_VENV:-/opt/data/cache/fourier-puzzle}"
mkdir -p "$(dirname "$VENV")"
if [ ! -x "$VENV/bin/python" ]; then
  command -v uv >/dev/null || { echo "uv not found: install with curl -LsSf https://astral.sh/uv/install.sh | sh" >&2; exit 1; }
  uv venv --python 3.13 "$VENV"
fi
uv pip install --python "$VENV/bin/python" numpy shapely svgpathtools matplotlib
"$VENV/bin/python" -c "import numpy, shapely, svgpathtools, matplotlib; print('deps ok:', numpy.__version__, shapely.__version__, 'venv:', '$VENV')"
