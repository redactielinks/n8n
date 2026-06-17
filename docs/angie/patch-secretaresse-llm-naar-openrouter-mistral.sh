#!/bin/bash
# Zet de Secretaresse-agent over van de lokale LM Studio (Mac Mini) naar
# OpenRouter, met Mistral als model (Europese LLM-aanbieder, en
# betrouwbaarder/stabieler/sneller dan het kleine lokale model).
#
# Vervangt de "Lokale LLM (Mac Mini)" node (type lmChatOpenAi) door een
# "OpenRouter Chat Model"-node (type lmChatOpenRouter) die de al
# bestaande OpenRouter-credential gebruikt (oITPdZPojDOLJaCJ). Er wordt
# GEEN nieuwe credential aangemaakt en er wordt geen API-key gevraagd of
# getoond.
#
# Modelkeuze: mistralai/mistral-large-2512 (Mistral Large 3) — het
# meest capabele Mistral-model op OpenRouter, gekozen omdat de vorige
# crashes vooral kwamen door een klein model dat tool-aanroepen niet
# correct kon formatteren. Een kleiner/goedkoper Mistral-model
# (bijv. mistralai/mistral-medium-3.5) kan later via dit zelfde script
# als argument gekozen worden, bv.:
#   bash patch-secretaresse-llm-naar-openrouter-mistral.sh "mistralai/mistral-medium-3.5"
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
OLD_NODE="Lokale LLM (Mac Mini)"
NEW_NODE="OpenRouter Chat Model"
CRED_ID="oITPdZPojDOLJaCJ"
CRED_NAME="OpenRouter account"
MODEL_NAME="${1:-mistralai/mistral-large-2512}"

echo "============================================================"
echo "  Secretaresse-agent overzetten naar OpenRouter (Mistral)"
echo "============================================================"
echo "  Model: ${MODEL_NAME}"
echo ""

echo "==> Workflow exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec7.json 2>/dev/null
docker cp n8n:/tmp/sec7.json /tmp/sec7.json

python3 - "$WF_ID" "$OLD_NODE" "$NEW_NODE" "$CRED_ID" "$CRED_NAME" "$MODEL_NAME" <<'PYEOF'
import json, sys

OLD_TYPE = '@n8n/n8n-nodes-langchain.lmChatOpenAi'
NEW_TYPE = '@n8n/n8n-nodes-langchain.lmChatOpenRouter'

wf_id, old_node, new_node, cred_id, cred_name, model_name = sys.argv[1:7]

with open('/tmp/sec7.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == wf_id)

target = None
for n in wf['nodes']:
    if n['name'] == old_node or n.get('type') == OLD_TYPE:
        target = n
        break

already_migrated = any(
    n.get('type') == NEW_TYPE and n['name'] == new_node for n in wf['nodes']
)

if target is None:
    if already_migrated:
        print(f"Node was al eerder vervangen door '{new_node}' (al OpenRouter, niets te doen).")
        with open('/tmp/sec7-modified.json', 'w', encoding='utf-8') as f:
            json.dump([wf], f, ensure_ascii=False, indent=2)
        print("Klaar: /tmp/sec7-modified.json (ongewijzigd)")
        sys.exit(0)
    print(f"FOUT: geen node gevonden met naam {old_node!r} of type {OLD_TYPE!r}.")
    print("Beschikbare nodes in deze workflow:")
    for n in wf['nodes']:
        print(f"  - {n['name']!r} (type: {n.get('type')!r})")
    sys.exit(1)

orig_name = target['name']
target['name'] = new_node
target['type'] = NEW_TYPE
target['typeVersion'] = 1
target['parameters'] = {
    'model': model_name,
    'options': {},
}
target['credentials'] = {'openRouterApi': {'id': cred_id, 'name': cred_name}}
print(f"Node vervangen: True (was {orig_name!r})")

conns = wf['connections']
if orig_name in conns and orig_name != new_node:
    conns[new_node] = conns.pop(orig_name)
    print(f"Verbinding-key hernoemd: {orig_name!r} -> {new_node!r}")

with open('/tmp/sec7-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec7-modified.json")
PYEOF

echo ""
echo "==> Importeren en activeren..."
docker cp /tmp/sec7-modified.json n8n:/tmp/sec7-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec7-modified.json --overwrite-all

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
echo "  De Mac Mini / LM Studio is niet meer nodig voor de Secretaresse."
echo "============================================================"
