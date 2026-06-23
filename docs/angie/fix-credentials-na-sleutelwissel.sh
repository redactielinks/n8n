#!/bin/bash
# Herstelt ALLE credentials die niet meer ontsleuteld kunnen worden nadat de
# encryptiesleutel in ~/.n8n/config opnieuw is overschreven (zelfde
# terugkerende probleem als op 17 en 19 juni 2026: een docker-herstart die
# N8N_ENCRYPTION_KEY niet expliciet meegaf, waarna n8n een nieuwe sleutel
# genereerde -- alle credentials die onder de OUDE sleutel versleuteld waren
# zijn daardoor blijvend onleesbaar onder de nieuwe).
#
# Gevolg deze keer: niet alleen de Telegram-credential is onleesbaar, maar
# ook de OpenRouter-credential -- en die is nodig voor vrijwel alles
# (wiki-chat, CLI-webhook, documentverwerking). De hele assistent staat dus
# stil totdat dit hersteld is.
#
# Je voert hier twee geheimen lokaal-op-de-Pi in (verborgen invoer, komt
# nergens anders terecht dan in de n8n-credential zelf):
#  - je OpenRouter API-key (sk-or-...)
#  - het Telegram-bottoken (van @BotFather, of uit de configuratie die je
#    al voor Hermes Agent's eigen gateway op de Mac Mini hebt staan -- dat
#    is hetzelfde token, dus je hoeft het niet uit n8n te halen)
# Beide zijn optioneel: leeg laten + Enter slaat die credential over.
set -euo pipefail

SCRIPT_VERSIE="2026-06-23-fix-credentials-na-sleutelwissel-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

CONFIG="/home/redactielinks/.n8n/config"
KENNISBANK_DIR="/home/redactielinks/kennisbank"

OPENROUTER_CRED_ID="oITPdZPojDOLJaCJ"
OPENROUTER_CRED_NAME="OpenRouter account"
TELEGRAM_CRED_ID="zk613MPgh3b3pkBZ"
TELEGRAM_CRED_NAME="jaouiyes_n8n_bot"

echo "============================================================"
echo "  Herstel credentials na sleutelwissel"
echo "============================================================"
echo ""

CURRENT_KEY=$(python3 -c "import json; print(json.load(open('${CONFIG}'))['encryptionKey'])")
echo "Huidige encryptiesleutel gevonden in ${CONFIG} (wordt niet getoond)."
echo ""

read -r -s -p "Plak je OpenRouter API-key (sk-or-...), of laat leeg om over te slaan, en druk op Enter: " OPENROUTER_API_KEY
echo ""
read -r -s -p "Plak het Telegram-bottoken, of laat leeg om over te slaan, en druk op Enter: " TELEGRAM_BOT_TOKEN
echo ""

if [ -z "$OPENROUTER_API_KEY" ] && [ -z "$TELEGRAM_BOT_TOKEN" ]; then
  echo "Geen van beide ingevoerd, niets te herstellen, gestopt."
  exit 1
fi

TMP_JSON="/tmp/creds-herstel-$$.json"
OPENROUTER_API_KEY="$OPENROUTER_API_KEY" TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" python3 - \
    "$OPENROUTER_CRED_ID" "$OPENROUTER_CRED_NAME" "$TELEGRAM_CRED_ID" "$TELEGRAM_CRED_NAME" "$TMP_JSON" <<'PYEOF'
import json, os, sys

or_id, or_name, tg_id, tg_name, out_path = sys.argv[1:6]
or_key = os.environ.get('OPENROUTER_API_KEY', '')
tg_token = os.environ.get('TELEGRAM_BOT_TOKEN', '')

creds = []
if or_key:
    creds.append({"id": or_id, "name": or_name, "type": "openRouterApi", "data": {"apiKey": or_key}})
if tg_token:
    creds.append({"id": tg_id, "name": tg_name, "type": "telegramApi", "data": {"accessToken": tg_token}})

with open(out_path, 'w', encoding='utf-8') as f:
    json.dump(creds, f)
print(f"  {len(creds)} credential(s) klaargezet om opnieuw op te slaan.")
PYEOF
unset OPENROUTER_API_KEY TELEGRAM_BOT_TOKEN

echo "==> Importeren in n8n..."
docker cp "$TMP_JSON" n8n:/tmp/creds-herstel.json
docker exec n8n n8n import:credentials --input=/tmp/creds-herstel.json
docker exec n8n rm -f /tmp/creds-herstel.json
rm -f "$TMP_JSON"
echo "Credential(s) opnieuw opgeslagen onder de huidige sleutel."

echo ""
echo "==> Encryptiesleutel vastzetten zodat dit niet meer kan gebeuren..."
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker stop n8n 2>/dev/null || true
docker rm n8n 2>/dev/null || true
docker run -d --name n8n --restart always -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -v "${KENNISBANK_DIR}:${KENNISBANK_DIR}" \
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
echo "  Klaar. Test nu:"
echo "  curl -s -X POST http://localhost:5678/webhook/angie-cli -H \"Content-Type: application/json\" -d '{\"text\":\"/taken\"}'"
echo ""
echo "  Geeft dat weer een normaal antwoord (geen credential-foutmelding)?"
echo "  Dan kun je daarna inspect-telegram-trigger-status.sh, en vervolgens"
echo "  patch-telegram-trigger-uit.sh, opnieuw draaien."
echo "============================================================"
