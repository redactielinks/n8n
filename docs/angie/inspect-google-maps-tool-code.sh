#!/bin/bash
# Alleen-lezen: toont de volledige code/parameters van de node "Google
# Maps" in de Secretaresse-workflow. Nodig om de exacte oorzaak van de
# fout "ReferenceError: fetch is not defined [line 7]" te vinden
# (gezien tijdens uitvoering 58, bij de vraag over hoog water bij
# Holwerd) voordat we een gerichte patch schrijven.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"

echo "==> Workflow exporteren (alleen-lezen)..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect_gmaps.json 2>/dev/null
docker cp n8n:/tmp/inspect_gmaps.json /tmp/inspect_gmaps.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect_gmaps.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')

found = False
for n in wf['nodes']:
    if n['name'] == 'Google Maps':
        found = True
        print(f"=== Node 'Google Maps' (type: {n.get('type')}, typeVersion: {n.get('typeVersion')}) ===")
        print(json.dumps(n.get('parameters', {}), ensure_ascii=False, indent=2))

if not found:
    print("Node 'Google Maps' niet gevonden. Beschikbare nodes:")
    for n in wf['nodes']:
        print(f"  - {n['name']!r} (type: {n.get('type')!r})")

print("\n=== Welke andere nodes zijn als ai_tool verbonden aan Secretaresse? ===")
for src, outputs in wf.get('connections', {}).items():
    for conn_type, branches in outputs.items():
        if conn_type != 'ai_tool':
            continue
        for branch in branches:
            for conn in branch:
                if conn['node'] == 'Secretaresse':
                    node = next((nn for nn in wf['nodes'] if nn['name'] == src), None)
                    print(f"  - {src} (type: {node.get('type') if node else '?'})")
PYEOF
