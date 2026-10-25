#!/usr/bin/env bash
# Insert the 18 DRAFT puzzles into the store through the admin API
# (POST /api/admin/puzzles): the server derives + validates each drawing, so a
# degenerate draft fails HERE with BadDrawing instead of polluting the table.
# Bodies are POSTed from FILES inside the container (busybox wget has no
# stdin-posting we can trust with JSON quoting).
set -euo pipefail
cd "$(dirname "$0")/.."

AUD=$(grep '^ADMIN_ACCESS_AUD=' .env | cut -d= -f2)
b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }
HEADER=$(printf '{"alg":"RS256","typ":"JWT","kid":"d0"}' | b64url)
NEXT=$(( $(date +%s) + 1800 ))
PAYLOAD=$(printf '{"aud":"%s","exp":%s}' "$AUD" "$NEXT" | b64url)
TOKEN="$HEADER.$PAYLOAD.x"
HDR="Cf-Access-Jwt-Assertion: $TOKEN"

# one body file per draft: drafts.json preserves release order (easy -> hard)
node - << 'NODEEOF'
const drafts = JSON.parse(require("fs").readFileSync("/tmp/drafts.json", "utf8"));
const start = new Date("2026-10-31T00:00:00Z");
const names = Object.keys(drafts);
names.forEach((name, i) => {
  const d = new Date(start.getTime() + i * 86400000);
  const showDate = d.toISOString().slice(0, 10);
  require("fs").writeFileSync(
    `/tmp/draft-body-${i}.json`,
    JSON.stringify({ name, showDate, dots: drafts[name] }),
  );
});
console.log(names.length + " drafts, show dates " +
  "2026-10-31 .. " + names[names.length - 1] && "");
for (let i = 0; i < names.length; i++) {
  const d = new Date(start.getTime() + i * 86400000);
  console.log(i, names[i], d.toISOString().slice(0, 10));
}
NODEEOF

for i in $(seq 0 17); do
  docker cp /tmp/draft-body-$i.json toy_admin:/tmp/body.json
  STATUS=$(docker exec toy_admin sh -c \
    "wget -q -O /tmp/resp.json --header '$HDR' --post-file /tmp/body.json \
     http://127.0.0.1:8080/api/admin/puzzles; echo \$?" )
  # busybox wget exits 1 on 4xx/5xx; read the status from the body instead
  BODY=$(docker cp toy_admin:/tmp/resp.json /tmp/resp-$i.json >/dev/null 2>&1 && \
    node -e 'const b=JSON.parse(require("fs").readFileSync(process.argv[1]));console.log(JSON.stringify(b).slice(0,80))' /tmp/resp-$i.json)
  echo "draft $i -> wget-exit $STATUS body $BODY"
done

echo "=== the schedule now ==="
curl -s https://jacks.im/api/puzzle/today -o /dev/null -w "today: %{http_code}\n"
docker exec toy_admin wget -q -O - \
  --header "$HDR" http://127.0.0.1:8080/api/admin/puzzles | \
  node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{const j=JSON.parse(s);for(const r of j.rows)console.log(r.id, r.name, r.showDate)})'