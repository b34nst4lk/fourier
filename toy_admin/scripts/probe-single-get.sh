#!/usr/bin/env bash
# Live probe: the single-puzzle GET the admin menu's TEST button drives.
# Runs on the host; reaches the app INSIDE the running toy_admin container
# (busybox wget, no curl in the runtime image). The fence (aud + exp;
# signature verification is deliberately not done) accepts any RS256-shaped
# token whose aud matches the configured one.
set -euo pipefail
cd "$(dirname "$0")/.."

AUD=$(grep '^ADMIN_ACCESS_AUD=' .env | cut -d= -f2)
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
HEADER=$(printf '{"alg":"RS256","typ":"JWT","kid":"d0"}' | b64url)
NEXT=$(( $(date +%s) + 1800 ))
PAYLOAD=$(printf '{"aud":"%s","exp":%s}' "$AUD" "$NEXT" | b64url)
TOKEN="$HEADER.$PAYLOAD.x"
HDR="Cf-Access-Jwt-Assertion: $TOKEN"

docker exec toy_admin wget -q -O /tmp/probe-rows.json \
  --header "$HDR" http://127.0.0.1:8080/api/admin/puzzles
echo "rows bytes: $(wc -c < /tmp/probe-rows.json)"
docker cp toy_admin:/tmp/probe-rows.json /tmp/probe-rows.json
ID=$(python3 -c 'import json; print(json.load(open("/tmp/probe-rows.json"))["rows"][0]["id"])' 2>/dev/null \
  || grep -o '"id":1*[0-9]*' /tmp/probe-rows.json | head -1 | cut -d: -f2)
echo "first row id: $ID"

docker exec toy_admin sh -c "wget -q -O /tmp/probe-single.json --header '$HDR' http://127.0.0.1:8080/api/admin/puzzles/$ID"
docker cp toy_admin:/tmp/probe-single.json /tmp/probe-single.json
echo "--- the document's SHAPE (what decode_fixture reads) ---"
python3 - << 'PYEOF'
import json
doc = json.load(open('/tmp/probe-single.json'))
print('top-level keys:', sorted(doc.keys()))
print('has TOP-LEVEL fixture key:', 'fixture' in doc)
if 'puzzle' in doc:
    px = doc['puzzle']
    print('inside-puzzle keys:', sorted(px.keys()))
    print('has PUZZLE-NESTED fixture:', 'fixture' in px)
PYEOF