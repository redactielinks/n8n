#!/bin/bash
# Alleen-lezen: controleert of de Secretaresse-node al "Continue On
# Fail" (foutafhandeling) heeft staan, en toont de exacte tekst-
# expressie die de Telegram-node gebruikt om te antwoorden. Nodig om
# een veilige "altijd een antwoord, ook bij een crash"-vangnet te
# kunnen toevoegen zonder te gokken naar de huidige instellingen.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"

echo "==> Workflow exporteren (alleen-lezen)..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect_telegram.json 2>/dev/null
docker cp n8n:/tmp/inspect_telegram.json /tmp/inspect_telegram.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect_telegram.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')

for n in wf['nodes']:
    if n['name'] == 'Secretaresse':
        print("=== Node 'Secretaresse': top-level instellingen ===")
        for key in n:
            if key != 'parameters':
                print(f"  {key}: {n[key]}")
        print("  parameters.options (zonder systemMessage):")
        opts = {k: v for k, v in n.get('parameters', {}).get('options', {}).items() if k != 'systemMessage'}
        print("   ", opts)

print("\n=== Node 'Telegram': volledige parameters ===")
for n in wf['nodes']:
    if n['name'] == 'Telegram':
        print(json.dumps(n.get('parameters', {}), ensure_ascii=False, indent=2))
        print("  top-level instellingen:")
        for key in n:
            if key != 'parameters':
                print(f"    {key}: {n[key]}")
PYEOF
