#!/bin/bash
# Zet de Secretaresse-agent over van Mistral naar Hermes 4 70B, beide via
# dezelfde, al bestaande OpenRouter-credential (oITPdZPojDOLJaCJ). Er wordt
# alleen het 'model'-parameter van de bestaande "OpenRouter Chat Model"-node
# aangepast, de node zelf (type lmChatOpenRouter) en de credential blijven
# ongewijzigd. Er wordt GEEN nieuwe credential aangemaakt en geen API-key
# gevraagd of getoond.
#
# Modelkeuze: nousresearch/hermes-4-70b — nieuwste Hermes-generatie, goede
# balans tussen snelheid, kosten en tool-calling-betrouwbaarheid. Een ander
# Hermes-model kan via dit zelfde script als argument gekozen worden, bv.:
#   bash patch-secretaresse-llm-naar-hermes.sh "nousresearch/hermes-4-405b"
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
NODE_NAME="OpenRouter Chat Model"
MODEL_NAME="${1:-nousresearch/hermes-4-70b}"

echo "============================================================"
echo "  Secretaresse-agent overzetten naar Hermes (OpenRouter)"
echo "============================================================"
echo "  Model: ${MODEL_NAME}"
echo ""

echo "==> Workflow exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec8.json 2>/dev/null
docker cp n8n:/tmp/sec8.json /tmp/sec8.json

python3 - "$WF_ID" "$NODE_NAME" "$MODEL_NAME" <<'PYEOF'
import json, sys

NODE_TYPE = '@n8n/n8n-nodes-langchain.lmChatOpenRouter'

wf_id, node_name, model_name = sys.argv[1:4]

with open('/tmp/sec8.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == wf_id)

target = None
for n in wf['nodes']:
    if n['name'] == node_name and n.get('type') == NODE_TYPE:
        target = n
        break

if target is None:
    print(f"FOUT: geen node gevonden met naam {node_name!r} en type {NODE_TYPE!r}.")
    print("Beschikbare nodes in deze workflow:")
    for n in wf['nodes']:
        print(f"  - {n['name']!r} (type: {n.get('type')!r})")
    sys.exit(1)

old_model = target.get('parameters', {}).get('model', '(onbekend)')
target['parameters']['model'] = model_name
print(f"Model gewijzigd: {old_model!r} -> {model_name!r}")

with open('/tmp/sec8-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec8-modified.json")
PYEOF

echo ""
echo "==> Importeren en activeren..."
docker cp /tmp/sec8-modified.json n8n:/tmp/sec8-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec8-modified.json --overwrite-all

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
unset ENC_KEY
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 5

echo ""
echo "============================================================"
echo "  Klaar. Test in Telegram een gewoon zinnetje zonder /."
echo "============================================================"
