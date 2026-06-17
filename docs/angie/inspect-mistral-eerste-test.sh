#!/bin/bash
# Alleen-lezen: onderzoekt waarom de eerste test na de overstap naar
# OpenRouter/Mistral geen Telegram-antwoord opleverde. Toont de laatste
# uitvoeringen (ook of er OVERHAUPT een uitvoering is gestart voor de
# vraag over Holwerd), en als er een uitvoering is, de foutmelding +
# context rond OpenRouter/credential/model.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Laatste 8 uitvoeringen van deze workflow..."
sqlite3 -header -column "$DB" \
  "SELECT id, status, mode, datetime(startedAt) as gestart, datetime(stoppedAt) as gestopt
   FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 8;"

LAST_ID=$(sqlite3 "$DB" "SELECT id FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 1;")
echo ""
echo "==> Meest recente uitvoering: ID ${LAST_ID}"

sqlite3 "$DB" "SELECT data FROM execution_data WHERE executionId='${LAST_ID}';" > /tmp/exec_mistral.txt 2>/dev/null || true
if [ ! -s /tmp/exec_mistral.txt ]; then
  sqlite3 "$DB" "SELECT data FROM execution_entity WHERE id='${LAST_ID}';" > /tmp/exec_mistral.txt 2>/dev/null || true
fi

echo ""
echo "==> Recente n8n-logregels (laatste 80, voor webhook/trigger-fouten)..."
docker logs n8n --tail 80 2>&1 | grep -iE "error|telegram|webhook|fail" || echo "(geen relevante regels)"

python3 - <<'PYEOF'
import re
with open('/tmp/exec_mistral.txt', encoding='utf-8', errors='replace') as f:
    text = f.read()

print(f"\n(ruwe executiedata lengte: {len(text)} tekens)\n")

idxs = [m.start() for m in re.finditer(
    r'OpenRouter|openrouter|Mistral|mistral|status code|statusCode|401|403|404|429|500|'
    r'insufficient|credit|quota|API key|Unauthorized|decrypt|Credentials for|error', text)]
seen = set()
count = 0
for i in idxs:
    start = max(0, i - 150)
    end = min(len(text), i + 350)
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
