#!/bin/bash
# Alleen-lezen: haalt de foutmelding van de laatste workflow-uitvoering
# rechtstreeks uit de sqlite-database, zonder de (crashende) n8n-webUI
# nodig te hebben.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Laatste uitvoeringen voor deze workflow..."
sqlite3 -header -column "$DB" \
  "SELECT id, status, mode, datetime(startedAt) as gestart, datetime(stoppedAt) as gestopt
   FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 8;"

LAST_ID=$(sqlite3 "$DB" "SELECT id FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 1;")
echo ""
echo "==> Meest recente uitvoering: ID ${LAST_ID}"

echo "==> Ophalen ruwe executiedata..."
sqlite3 "$DB" "SELECT data FROM execution_data WHERE executionId='${LAST_ID}';" > /tmp/exec_data.txt 2>/dev/null || true

if [ ! -s /tmp/exec_data.txt ]; then
  echo "(geen rij in execution_data, val terug op execution_entity.data)"
  sqlite3 "$DB" "SELECT data FROM execution_entity WHERE id='${LAST_ID}';" > /tmp/exec_data.txt 2>/dev/null || true
fi

python3 - <<'PYEOF'
import re
with open('/tmp/exec_data.txt', encoding='utf-8', errors='replace') as f:
    text = f.read()

print(f"(ruwe data lengte: {len(text)} tekens)\n")

seen = set()
for m in re.finditer(r'.{0,60}[Ee]rror.{0,200}', text):
    snippet = m.group(0)
    if snippet not in seen:
        seen.add(snippet)
        print('---')
        print(snippet)

if not seen:
    print("Geen 'error'-tekst gevonden. Eerste 500 tekens van de ruwe data:")
    print(text[:500])
PYEOF
