#!/bin/bash
# Vervangt ALLEEN de Google Maps API-sleutel in de (al eerder gerepareerde)
# "Google Maps"-tool, omdat de oude sleutel per ongeluk is blootgesteld
# (zichtbaar geweest in een workflow-export/terminal/chat).
#
# Vereist de nieuwe sleutel als argument, getypt direct in Termius:
#   bash rotate-google-maps-key.sh "NIEUWE_SLEUTEL_HIER"
# De sleutel komt nooit in een commit, log-bestand of ergens anders terecht.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
OLD_KEY_LINE='const apiKey = "AIzaSyAVq4QNuliXGU-iqCuetPZXMbCqiW5SVrI";'
NEW_API_KEY="${1:?Gebruik: bash rotate-google-maps-key.sh \"NIEUWE_SLEUTEL\"}"

echo "============================================================"
echo "  Google Maps API-sleutel roteren"
echo "============================================================"
echo ""

echo "==> Workflow exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/maps-rotate.json 2>/dev/null
docker cp n8n:/tmp/maps-rotate.json /tmp/maps-rotate.json

OLD_KEY_LINE="$OLD_KEY_LINE" NEW_API_KEY="$NEW_API_KEY" python3 - "$WF_ID" <<'PYEOF'
import json, os, sys

wf_id = sys.argv[1]
old_key_line = os.environ['OLD_KEY_LINE']
new_api_key = os.environ['NEW_API_KEY']

with open('/tmp/maps-rotate.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == wf_id)

target = None
for n in wf['nodes']:
    if n['name'] == 'Google Maps':
        target = n
        break

if target is None:
    print("FOUT: node 'Google Maps' niet gevonden.")
    sys.exit(1)

current_code = target.get('parameters', {}).get('jsCode', '')

if old_key_line not in current_code:
    print("FOUT: de verwachte oude sleutel-regel is niet (meer) exact aanwezig in de code.")
    print("Huidige jsCode:")
    print(current_code)
    sys.exit(1)

new_key_line = f'const apiKey = "{new_api_key}";'
target['parameters']['jsCode'] = current_code.replace(old_key_line, new_key_line)
print("Sleutel vervangen in de Google Maps-tool.")

with open('/tmp/maps-rotate-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/maps-rotate-modified.json")
PYEOF

echo ""
echo "==> Importeren en activeren..."
docker cp /tmp/maps-rotate-modified.json n8n:/tmp/maps-rotate-modified.json
docker exec n8n n8n import:workflow --input=/tmp/maps-rotate-modified.json --overwrite-all

ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
ENC_KEY=$(python3 -c "import json; print(json.load(open('${CONFIG}'))['encryptionKey'])")
docker stop n8n 2>/dev/null || true
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1, activeVersionId='${ACTIVE_VID}' WHERE id='${WF_ID}';"
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker rm n8n 2>/dev/null || true
docker run -d --name n8n --restart always -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e N8N_ENCRYPTION_KEY="${ENC_KEY}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path,http,https,url \
    n8nio/n8n:latest
unset ENC_KEY NEW_API_KEY
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 5

echo ""
echo "============================================================"
echo "  Klaar. De oude sleutel is niet meer in gebruik door n8n."
echo "  Verwijder 'm ook in Google Cloud Console als je dat nog niet"
echo "  had gedaan."
echo "============================================================"
