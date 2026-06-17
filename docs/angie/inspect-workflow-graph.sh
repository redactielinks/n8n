#!/bin/bash
# Alleen-lezen inspectie van de live workflow-graaf. Wijzigt niets.
# Toont alle nodes, hun type, en hoe ze met elkaar verbonden zijn, plus
# de volledige conditions + combinator van "Is Obsidian Cmd?".
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"

echo "==> Exporteren (alleen-lezen, schrijft niets terug)..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect.json 2>/dev/null
docker cp n8n:/tmp/inspect.json /tmp/inspect.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Workflow: {wf['name']}  (actief: {wf.get('active')})\n")

print("=== Nodes ===")
for n in wf['nodes']:
    print(f"  - {n['name']!r:35s} type={n['type']}")

print("\n=== Verbindingen (van -> naar) ===")
for src, outputs in wf.get('connections', {}).items():
    for branch_idx, branch in enumerate(outputs.get('main', [])):
        for conn in branch:
            print(f"  {src} [output {branch_idx}] -> {conn['node']}")

print("\n=== Is Obsidian Cmd? volledige config ===")
for n in wf['nodes']:
    if n['name'] == 'Is Obsidian Cmd?':
        print(json.dumps(n['parameters'], indent=2, ensure_ascii=False))

print("\n=== Telegram Trigger config (indien aanwezig) ===")
for n in wf['nodes']:
    if 'trigger' in n['type'].lower() and 'telegram' in n['type'].lower():
        print(f"Node: {n['name']}")
        print(json.dumps(n['parameters'], indent=2, ensure_ascii=False))
PYEOF
