#!/bin/bash
# Alleen-lezen: onderzoekt waarom "hoe wordt het weer morgen" een
# verzonnen/generiek antwoord opleverde in plaats van een echt
# zoekresultaat. Toont de laatste uitvoering, of de web_zoeken-tool is
# aangeroepen, en zo ja met welk resultaat/foutmelding.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Laatste 5 uitvoeringen..."
sqlite3 -header -column "$DB" \
  "SELECT id, status, datetime(startedAt) as gestart
   FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 5;"

LAST_ID=$(sqlite3 "$DB" "SELECT id FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 1;")
echo ""
echo "==> Meest recente uitvoering: ID ${LAST_ID}"
sqlite3 "$DB" "SELECT data FROM execution_data WHERE executionId='${LAST_ID}';" > /tmp/exec_weer.txt 2>/dev/null || true

echo ""
echo "==> SearXNG bereikbaar vanaf de Pi zelf?"
curl -s -o /dev/null -w "  HTTP status (poort 8081): %{http_code}\n" "http://100.77.5.104:8081/search?q=test&format=json" --max-time 8 || echo "  (curl mislukt)"

echo ""
echo "==> SearXNG bereikbaar VANUIT de n8n-container?"
docker exec n8n wget -qO- --timeout=8 "http://100.77.5.104:8081/search?q=test&format=json" 2>&1 | head -c 200 || echo "  (mislukt vanuit container)"
echo ""

python3 - <<'PYEOF'
import re
with open('/tmp/exec_weer.txt', encoding='utf-8', errors='replace') as f:
    text = f.read()

print(f"\n(ruwe executiedata lengte: {len(text)} tekens)\n")

idxs = [m.start() for m in re.finditer(
    r'web_zoeken|searx|8081|ECONNREFUSED|ETIMEDOUT|timeout|weer|getElementsByName|'
    r'NodeApiError|statusCode|error|toolHandler', text, re.IGNORECASE)]
seen = set()
count = 0
for i in idxs:
    start = max(0, i - 120)
    end = min(len(text), i + 280)
    snippet = text[start:end]
    if snippet in seen:
        continue
    seen.add(snippet)
    count += 1
    print('=== context', count, '===')
    print(snippet)
    print()
    if count >= 15:
        print("(meer gevonden, afgekapt na 15)")
        break

if count == 0:
    print("Geen relevante tekst gevonden. Eerste 800 tekens van de ruwe data:")
    print(text[:800])
PYEOF
