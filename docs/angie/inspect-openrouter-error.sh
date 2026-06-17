#!/bin/bash
# Alleen-lezen: haalt meer context op rond de OpenRouter-foutmelding uit de
# laatste mislukte uitvoering, rechtstreeks uit sqlite.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

LAST_ID=$(sqlite3 "$DB" "SELECT id FROM execution_entity WHERE workflowId='${WF_ID}' AND status='error' ORDER BY id DESC LIMIT 1;")
echo "==> Mislukte uitvoering: ID ${LAST_ID}"

sqlite3 "$DB" "SELECT data FROM execution_data WHERE executionId='${LAST_ID}';" > /tmp/exec_data_full.txt

python3 - <<'PYEOF'
import re
with open('/tmp/exec_data_full.txt', encoding='utf-8', errors='replace') as f:
    text = f.read()

print(f"(lengte: {len(text)} tekens)\n")

idxs = [m.start() for m in re.finditer(r'OpenRouter|openrouter|status code|statusCode|401|403|429|insufficient|credit|quota|API key|Unauthorized', text)]
seen = set()
for i in idxs:
    start = max(0, i - 150)
    end = min(len(text), i + 350)
    snippet = text[start:end]
    if snippet not in seen:
        seen.add(snippet)
        print('=== context ===')
        print(snippet)
        print()
PYEOF
