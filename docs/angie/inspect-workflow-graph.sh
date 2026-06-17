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

print("\n=== Configuratie van routerende nodes ===")
for naam in ['Is commando?', 'If', 'If1', 'Voice or Text', 'Detecteer pad',
             'AllowList', 'Is bijlage?', 'Is /content?', 'Is /idee?']:
    for n in wf['nodes']:
        if n['name'] == naam:
            print(f"\n--- {naam} (type={n['type']}) ---")
            print(json.dumps(n.get('parameters', {}), indent=2, ensure_ascii=False))

print("\n=== Secretaresse node (alleen type + systeemprompt-veldnamen, geen credentials) ===")
for n in wf['nodes']:
    if n['name'] == 'Secretaresse':
        params = n.get('parameters', {})
        print(f"type={n['type']}")
        print(f"parameter-keys: {list(params.keys())}")
        if 'text' in params:
            print(f"text (eerste 300 tekens): {str(params['text'])[:300]}")
        if 'options' in params:
            print(f"options-keys: {list(params['options'].keys())}")
PYEOF
