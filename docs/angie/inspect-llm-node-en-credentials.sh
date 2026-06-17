#!/bin/bash
# Alleen-lezen: zoekt (via de ai_languageModel-verbinding, niet via een
# gegokte naam) welke node nu het taalmodel aan Secretaresse levert,
# toont zijn volledige configuratie, en toont een lijst van alle
# opgeslagen credentials (naam + type, GEEN geheime waarden) zodat we
# weten of er nog een werkende OpenRouter-credential beschikbaar is
# voor de overstap naar Mistral via OpenRouter.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Exporteren (alleen-lezen)..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect_llm2.json 2>/dev/null
docker cp n8n:/tmp/inspect_llm2.json /tmp/inspect_llm2.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect_llm2.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')

llm_node_name = None
for src, outputs in wf.get('connections', {}).items():
    for conn_type, branches in outputs.items():
        if conn_type != 'ai_languageModel':
            continue
        for branch in branches:
            for conn in branch:
                if conn['node'] == 'Secretaresse':
                    llm_node_name = src

print(f"=== Node die taalmodel levert aan Secretaresse: {llm_node_name!r} ===")
for n in wf['nodes']:
    if n['name'] == llm_node_name:
        print(json.dumps(n, indent=2, ensure_ascii=False))
PYEOF

echo ""
echo "==> Opgeslagen credentials (alleen naam + type, geen geheimen)..."
sqlite3 -header -column "$DB" "SELECT id, name, type FROM credentials_entity ORDER BY type;"
