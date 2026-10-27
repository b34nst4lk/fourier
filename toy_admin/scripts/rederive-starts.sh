#!/usr/bin/env bash
# Re-derive every NOT-YET-SERVED puzzle's start.
#
# The starting patches are DRAWN per puzzle at save time, so a row saved under
# an older draw keeps that signature until its own dots are saved again. This
# script re-saves each row whose `showDate` is AFTER today by PUTting the row's
# own drawing back through the admin API: `admin.apply_patch` re-derives the
# fixture whenever the body carries `dots`, so the save path does the work (no
# direct SQL, no second derivation).
#
# Because the draw happens SERVER-side, re-saving through a backend that predates
# the current draw redraws with the OLD formula: rebuild (or confirm the running
# image) before running this for real.
#
# Already-served days are never touched — a player may still be playing one.
#
#   scripts/rederive-starts.sh --dry-run   list what WOULD be re-saved, no writes
#   scripts/rederive-starts.sh             re-save them (and print each result)
#
# The fence is the same forged-assertion pattern insert-drafts.sh and
# probe-single-get.sh use: access.gleam verifies aud + exp only (signature
# verification is deliberately not done), so a token shaped like a Cloudflare
# Access JWT carrying the configured audience passes. ADMIN_ACCESS_AUD comes
# from the environment, falling back to the gitignored `.env` beside
# compose.yml — the value never lives in the repo.
#
# Transport: host `curl` against the container's private bridge address. The
# runtime image ships busybox wget (which has `--post-file` only — no PUT) and
# no curl, and the app publishes no host port: the tunnel is the PUBLIC ingress,
# and a maintenance script has no business going through the edge.
set -euo pipefail
cd "$(dirname "$0")/.."

DRY_RUN=0
case "${1:-}" in
  --dry-run) DRY_RUN=1 ;;
  "") ;;
  *)
    echo "usage: $0 [--dry-run]" >&2
    exit 64
    ;;
esac

AUD="${ADMIN_ACCESS_AUD:-}"
if [ -z "$AUD" ] && [ -f .env ]; then
  AUD=$(grep '^ADMIN_ACCESS_AUD=' .env | cut -d= -f2)
fi
if [ -z "$AUD" ]; then
  echo "rederive-starts: ADMIN_ACCESS_AUD is not set (env or .env)" \
    "— the admin fence needs the audience" >&2
  exit 1
fi

CONTAINER="${TOY_ADMIN_CONTAINER:-toy_admin}"
# Which day counts as "already served". The host's UTC date by default; pin it
# (TODAY=2026-10-27) to make a dry run reproducible from a report.
TODAY="${TODAY:-$(date -u +%F)}"

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
HEADER=$(printf '{"alg":"RS256","typ":"JWT","kid":"d0"}' | b64url)
NEXT=$(( $(date +%s) + 1800 ))
PAYLOAD=$(printf '{"aud":"%s","exp":%s}' "$AUD" "$NEXT" | b64url)
HDR="Cf-Access-Jwt-Assertion: $HEADER.$PAYLOAD.x"

# The container may sit on several networks; use the first address that answers
# the health route (only ONE of them is the app).
BASE=""
for ip in $(docker inspect "$CONTAINER" \
  --format '{{range .NetworkSettings.Networks}}{{println .IPAddress}}{{end}}'); do
  if curl -sf --max-time 5 "http://$ip:8080/api/health" >/dev/null 2>&1; then
    BASE="http://$ip:8080"
    break
  fi
done
if [ -z "$BASE" ]; then
  echo "rederive-starts: $CONTAINER is not answering /api/health on any network" >&2
  exit 1
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

curl -sf --max-time 15 -H "$HDR" "$BASE/api/admin/puzzles" -o "$WORK/rows.json"

# id / name / showDate for every row AFTER today, oldest first (the order the
# days will actually be served in). The `puzzles` array is the same calendar
# document the agent door emits (rows.gleam).
node - "$WORK/rows.json" "$TODAY" > "$WORK/targets.tsv" << 'NODEEOF'
const fs = require("fs");
const [path, today] = process.argv.slice(2);
const doc = JSON.parse(fs.readFileSync(path, "utf8"));
if (doc.status !== "ok") {
  console.error("row list failed: " + JSON.stringify(doc).slice(0, 200));
  process.exit(1);
}
const rows = (doc.puzzles || [])
  .filter((row) => row.showDate > today)
  .sort((a, b) => (a.showDate < b.showDate ? -1 : 1));
for (const row of rows) {
  console.log([row.id, row.name, row.showDate].join("\t"));
}
console.error(
  rows.length + " of " + (doc.puzzles || []).length +
  " puzzles are after " + today,
);
NODEEOF

if [ ! -s "$WORK/targets.tsv" ]; then
  echo "nothing to re-derive: no puzzle is scheduled after $TODAY"
  exit 0
fi

if [ "$DRY_RUN" = 1 ]; then
  echo "=== DRY RUN: no writes, these rows WOULD be re-saved ==="
  printf 'id\tname\tshow_date\n'
  cat "$WORK/targets.tsv"
  echo "=== $(wc -l < "$WORK/targets.tsv") rows would be re-saved ==="
  exit 0
fi

while IFS=$'\t' read -r id name show_date; do
  # The row's OWN document: the drawing is the source of truth the fixture is
  # re-derived from, and the identity must come back unchanged.
  curl -sf --max-time 15 -H "$HDR" "$BASE/api/admin/puzzles/$id" \
    -o "$WORK/row-$id.json"
  node - "$WORK/row-$id.json" "$WORK/body-$id.json" << 'NODEEOF'
const fs = require("fs");
const [inPath, outPath] = process.argv.slice(2);
const doc = JSON.parse(fs.readFileSync(inPath, "utf8"));
const puzzle = doc.puzzle;
if (!puzzle) {
  console.error("row read failed: " + JSON.stringify(doc).slice(0, 200));
  process.exit(1);
}
// `dots` PRESENT is what makes the save path re-derive the fixture; the name
// and the date are echoed back so the row keeps its identity.
fs.writeFileSync(
  outPath,
  JSON.stringify({
    name: puzzle.name,
    showDate: puzzle.showDate,
    dots: puzzle.dots,
  }),
);
NODEEOF

  code=$(curl -s -o "$WORK/resp-$id.json" -w '%{http_code}' --max-time 15 \
    -H "$HDR" -H 'content-type: application/json' -X PUT \
    --data-binary "@$WORK/body-$id.json" "$BASE/api/admin/puzzles/$id")
  echo "re-saved $id ($name, $show_date) -> HTTP $code"
  if [ "$code" != "200" ]; then
    echo "  response: $(head -c 200 "$WORK/resp-$id.json")" >&2
    exit 1
  fi
  # What the save actually drew: four patches, in slot order. A row that still
  # shows a fixed start (phase 0°/90°, k truth − 2) did not re-derive.
  node - "$WORK/resp-$id.json" << 'NODEEOF'
const fs = require("fs");
const doc = JSON.parse(fs.readFileSync(process.argv[2], "utf8"));
const patches = (doc.puzzle && doc.puzzle.fixture && doc.puzzle.fixture.patches) || [];
console.log(
  "  patches: " +
  patches.map((patch) => JSON.stringify(patch)).join(" "),
);
NODEEOF
done < "$WORK/targets.tsv"

echo "=== re-derived $(wc -l < "$WORK/targets.tsv") puzzles ==="
