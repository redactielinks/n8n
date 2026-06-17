#!/bin/bash
# Alleen-lezen: toont het type, de credential-koppeling en de node-code van
# de "Weer"-tool, om te bepalen hoe de credential opnieuw versleuteld moet
# worden (zelfde aanpak als eerder bij de OpenRouter-credential).
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Workflow exporteren (alleen-lezen)..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect-weer-node.json 2>/dev/null
docker cp n8n:/tmp/inspect-weer-node.json /tmp/inspect-weer-node.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect-weer-node.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')

for n in wf['nodes']:
    if n['name'] == 'Weer':
        print("=== Node 'Weer' ===")
        print("type:", n.get('type'))
        print("typeVersion:", n.get('typeVersion'))
        print("credentials:", json.dumps(n.get('credentials', {}), indent=2))
        params = n.get('parameters', {})
        # Toon parameters zonder eventuele lange jsCode-blokken integraal af te drukken op te lang
        for k, v in params.items():
            if k == 'jsCode':
                print(f"parameters.jsCode (eerste 1500 tekens):")
                print(v[:1500])
            else:
                print(f"parameters.{k}:", json.dumps(v, ensure_ascii=False)[:300])
        break
else:
    print("Node 'Weer' niet gevonden.")
PYEOF

echo ""
echo "==> Credential-tabel (alleen metadata, geen geheime data)..."
sqlite3 -header -column "$DB" "SELECT id, name, type, datetime(createdAt) as gemaakt, datetime(updatedAt) as bijgewerkt FROM credentials_entity;"
