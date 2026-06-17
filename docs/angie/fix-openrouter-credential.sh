#!/bin/bash
# Herstelt de OpenRouter-credential die niet meer ontsleuteld kan worden
# (de encryptiesleutel in ~/.n8n/config is na het aanmaken van de
# credential overschreven, waarschijnlijk tijdens de HTTPS-tunnel setup).
#
# Je OpenRouter API-key wordt hier alleen lokaal op de Pi ingetypt
# (verborgen invoer) en gaat nooit ergens anders naartoe.
set -euo pipefail

CRED_ID="oITPdZPojDOLJaCJ"
CRED_NAME="OpenRouter account"
CONFIG="/home/redactielinks/.n8n/config"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "============================================================"
echo "  Herstel OpenRouter-credential"
echo "============================================================"
echo ""

CURRENT_KEY=$(python3 -c "import json; print(json.load(open('${CONFIG}'))['encryptionKey'])")
echo "Huidige encryptiesleutel gevonden in ${CONFIG} (wordt niet getoond)."

echo ""
read -r -s -p "Plak je OpenRouter API-key (sk-or-...) en druk op Enter: " API_KEY
echo ""
if [ -z "$API_KEY" ]; then
  echo "Geen key ingevoerd, gestopt."
  exit 1
fi

TMP_JSON="/tmp/openrouter-cred-$$.json"
OPENROUTER_API_KEY="$API_KEY" python3 - "$CRED_ID" "$CRED_NAME" "$TMP_JSON" <<'PYEOF'
import json, os, sys
cred_id, name, out_path = sys.argv[1:4]
api_key = os.environ['OPENROUTER_API_KEY']
data = [{"id": cred_id, "name": name, "type": "openRouterApi", "data": {"apiKey": api_key}}]
with open(out_path, 'w') as f:
    json.dump(data, f)
PYEOF
unset API_KEY

echo "==> Importeren in n8n..."
docker cp "$TMP_JSON" n8n:/tmp/openrouter-cred.json
docker exec n8n n8n import:credentials --input=/tmp/openrouter-cred.json
docker exec n8n rm -f /tmp/openrouter-cred.json
rm -f "$TMP_JSON"
echo "Credential opnieuw opgeslagen onder de huidige sleutel."

echo ""
echo "==> Encryptiesleutel vastzetten zodat dit niet meer kan gebeuren..."
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker stop n8n
docker rm n8n
docker run -d --name n8n --restart always -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e N8N_ENCRYPTION_KEY="${CURRENT_KEY}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path,http,https,url \
    n8nio/n8n:latest
unset CURRENT_KEY
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 5

echo ""
echo "============================================================"
echo "  Klaar. Test nu in Telegram een gewoon zinnetje zonder /."
echo "============================================================"
