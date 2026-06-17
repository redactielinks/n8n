#!/bin/bash
# Zet de Secretaresse-agent over van OpenRouter (cloud) naar de lokale
# LM Studio op de Mac Mini, zodat de agent voorlopig geen externe
# LLM-provider nodig heeft. Vervangt de "OpenRouter Chat Model" node door
# een "OpenAI Chat Model"-node met een eigen Base URL naar LM Studio
# (LM Studio praat het OpenAI-protocol, dus dat werkt zonder eigen node).
#
# Zet ook N8N_ENCRYPTION_KEY vast als env var, zodat een toekomstige
# container-herstart de nieuwe credential niet opnieuw onleesbaar maakt
# (zie inspect-encryption-key.sh: dit was de oorzaak van de OpenRouter-
# storing).
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
OLD_NODE="OpenRouter Chat Model"
NEW_NODE="Lokale LLM (Mac Mini)"
CRED_ID="localLmStudioCred01"
CRED_NAME="LM Studio (Mac Mini, lokaal)"
LM_STUDIO_BASE_URL="http://100.68.46.126:27124/v1"
MODEL_NAME="google/gemma-3-4b"

echo "============================================================"
echo "  Secretaresse-agent overzetten naar lokale LLM (Mac Mini)"
echo "============================================================"
echo ""

echo "==> Stap 1: dummy OpenAI-credential aanmaken (LM Studio valideert de key niet)..."
TMP_CRED="/tmp/lmstudio-cred-$$.json"
python3 - "$CRED_ID" "$CRED_NAME" "$LM_STUDIO_BASE_URL" "$TMP_CRED" <<'PYEOF'
import json, sys
cred_id, name, base_url, out_path = sys.argv[1:5]
data = [{
    "id": cred_id,
    "name": name,
    "type": "openAiApi",
    "data": {"apiKey": "lm-studio-niet-gevalideerd", "url": base_url},
}]
with open(out_path, 'w') as f:
    json.dump(data, f)
PYEOF
docker cp "$TMP_CRED" n8n:/tmp/lmstudio-cred.json
docker exec n8n n8n import:credentials --input=/tmp/lmstudio-cred.json
docker exec n8n rm -f /tmp/lmstudio-cred.json
rm -f "$TMP_CRED"
ok_cred=1
echo "Credential '${CRED_NAME}' aangemaakt."

echo ""
echo "==> Stap 2: workflow exporteren en LLM-node vervangen..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec3.json 2>/dev/null
docker cp n8n:/tmp/sec3.json /tmp/sec3.json

python3 - "$WF_ID" "$OLD_NODE" "$NEW_NODE" "$CRED_ID" "$CRED_NAME" "$LM_STUDIO_BASE_URL" "$MODEL_NAME" <<'PYEOF'
import json, sys

OLD_TYPE = '@n8n/n8n-nodes-langchain.lmChatOpenRouter'
NEW_TYPE = '@n8n/n8n-nodes-langchain.lmChatOpenAi'

wf_id, old_node, new_node, cred_id, cred_name, base_url, model_name = sys.argv[1:8]

with open('/tmp/sec3.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == wf_id)

# Zoek de te vervangen node op naam OF op type (naam kan handmatig
# gewijzigd zijn zonder dat we dat weten; type van een OpenRouter-LLM-node
# verandert niet zomaar).
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
        print(f"Node was al eerder vervangen door '{new_node}' (al lokale LLM, niets te doen).")
        with open('/tmp/sec3-modified.json', 'w', encoding='utf-8') as f:
            json.dump([wf], f, ensure_ascii=False, indent=2)
        print("Klaar: /tmp/sec3-modified.json (ongewijzigd)")
        sys.exit(0)
    print(f"FOUT: geen node gevonden met naam {old_node!r} of type {OLD_TYPE!r}.")
    print("Beschikbare nodes in deze workflow:")
    for n in wf['nodes']:
        print(f"  - {n['name']!r} (type: {n.get('type')!r})")
    sys.exit(1)

orig_name = target['name']
target['name'] = new_node
target['type'] = NEW_TYPE
target['parameters'] = {
    'model': model_name,
    'options': {'baseURL': base_url},
}
target['credentials'] = {'openAiApi': {'id': cred_id, 'name': cred_name}}
print(f"Node vervangen: True (was {orig_name!r})")

conns = wf['connections']
if orig_name in conns and orig_name != new_node:
    conns[new_node] = conns.pop(orig_name)
    print(f"Verbinding-key hernoemd: {orig_name!r} -> {new_node!r}")

with open('/tmp/sec3-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec3-modified.json")
PYEOF

echo ""
echo "==> Stap 3: importeren en activeren..."
docker cp /tmp/sec3-modified.json n8n:/tmp/sec3-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec3-modified.json --overwrite-all

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
echo "  Klaar. Zorg dat LM Studio draait op de Mac Mini (poort 27124)"
echo "  met het model '${MODEL_NAME}' geladen, en test daarna in"
echo "  Telegram een gewoon zinnetje zonder /."
echo "============================================================"
