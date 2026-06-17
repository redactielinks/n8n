#!/bin/bash
# Alleen-lezen: volledige configuratie van de "OpenRouter Chat Model" node
# en alle verbindingen waar die node in voorkomt (elk verbindingstype,
# niet alleen "main"), zodat we 'm veilig kunnen vervangen door een node
# die naar de lokale LM Studio op de Mac Mini wijst.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"

echo "==> Exporteren (alleen-lezen)..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect2.json 2>/dev/null
docker cp n8n:/tmp/inspect2.json /tmp/inspect2.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect2.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')

print("=== OpenRouter Chat Model: volledige node-definitie ===")
for n in wf['nodes']:
    if n['name'] == 'OpenRouter Chat Model':
        print(json.dumps(n, indent=2, ensure_ascii=False))

print("\n=== Alle verbindingen waar 'OpenRouter Chat Model' in voorkomt (elk type) ===")
for src, outputs in wf.get('connections', {}).items():
    for conn_type, branches in outputs.items():
        for branch_idx, branch in enumerate(branches):
            for conn in branch:
                if src == 'OpenRouter Chat Model' or conn['node'] == 'OpenRouter Chat Model':
                    print(f"  {src} --[{conn_type}, output {branch_idx}]--> {conn['node']} (input index {conn.get('index')})")

print("\n=== Secretaresse node: volledige definitie ===")
for n in wf['nodes']:
    if n['name'] == 'Secretaresse':
        print(json.dumps(n, indent=2, ensure_ascii=False))
PYEOF
