#!/bin/bash
# ============================================================
# Project Angie — Telegram-trigger uitschakelen in de n8n-workflow
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# "laten we de n8n workflow van angie alleen voor hermes gebruiken": sinds
# Hermes Agent (Mac Mini) op 22 juni 2026 een eigen Telegram-gateway heeft
# gekregen op hetzelfde (nog niet-geroteerde) bottoken, kan de legacy
# Telegram Trigger-node in Angie's n8n-workflow niet langer actief blijven
# -- Telegram staat geen webhook + losse gateway tegelijk toe op één
# bottoken, en de twee zouden elkaars updates wegkapen.
#
# Deze patch:
#  - zet de Telegram Trigger-node in de Secretaresse-workflow op
#    disabled (zo registreert n8n bij een herstart geen webhook meer voor
#    deze node);
#  - roept éénmalig Telegram's deleteWebhook-API aan om een eventueel nog
#    geregistreerd n8n-webhook bij Telegram zelf op te ruimen, zodat
#    Hermes Agent's eigen gateway (long-polling of webhook) het bottoken
#    exclusief kan gebruiken.
# De wiki-site-chat en /webhook/angie-cli (gebruikt door zowel jou als
# Hermes Agent via de MCP-bridge) blijven ongewijzigd werken -- dit raakt
# alleen de Telegram Trigger-node.
#
# Het Telegram-bottoken wordt hier alleen lokaal-op-de-Pi, tijdens het
# draaien van dit script, ontsleuteld uit de bestaande credential
# (zk613MPgh3b3pkBZ, "jaouiyes_n8n_bot") en direct na gebruik verwijderd
# -- het komt nergens in deze broncode of in enige log/print terecht.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude
# lokale kopie en download daarna vers:
#   rm -f patch-telegram-trigger-uit.sh
#   curl -fsSL -o patch-telegram-trigger-uit.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-telegram-trigger-uit.sh?t=$(date +%s)"
#   bash patch-telegram-trigger-uit.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-23-telegram-trigger-uit-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
KENNISBANK_DIR="/home/redactielinks/kennisbank"
TELEGRAM_CRED_ID="zk613MPgh3b3pkBZ"
TELEGRAM_CRED_NAME="jaouiyes_n8n_bot"

echo "==> Telegram-bottoken lokaal ontsleutelen (komt nooit in git of logs terecht)..."
docker exec n8n n8n export:credentials --all --decrypted --output=/tmp/creds-decrypted.json 2>/dev/null
docker cp n8n:/tmp/creds-decrypted.json /tmp/creds-decrypted.json
docker exec n8n rm -f /tmp/creds-decrypted.json
TELEGRAM_BOT_TOKEN=$(python3 -c "
import json
with open('/tmp/creds-decrypted.json', encoding='utf-8') as f:
    creds = json.load(f)
cred = next((c for c in creds if c.get('id') == '${TELEGRAM_CRED_ID}' or c.get('name') == '${TELEGRAM_CRED_NAME}'), None)
if cred is None:
    raise SystemExit('Telegram-credential niet gevonden -- patch afgebroken.')
print(cred['data']['accessToken'])
")
rm -f /tmp/creds-decrypted.json

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF_INNER'
import json

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

trigger_nodes = [n for n in wf['nodes'] if n.get('type') == 'n8n-nodes-base.telegramTrigger']
if not trigger_nodes:
    raise SystemExit("Geen node van type 'n8n-nodes-base.telegramTrigger' gevonden -- patch afgebroken zonder iets te wijzigen.")
if len(trigger_nodes) != 1:
    raise SystemExit(f"Verwachte 1 Telegram Trigger-node, {len(trigger_nodes)} gevonden -- niet veilig om automatisch te patchen. Patch afgebroken zonder iets te wijzigen.")

node = trigger_nodes[0]
if node.get('disabled'):
    raise SystemExit(f"Node '{node['name']}' staat al op disabled -- deze patch lijkt al uitgevoerd te zijn, niet opnieuw uitvoeren.")

node['disabled'] = True
print(f"  ~ node '{node['name']}': disabled = true")

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF_INNER

echo "==> Importeren..."
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all

echo "==> Telegram-webhook bij Telegram zelf opruimen (deleteWebhook)..."
DELETE_RESPONSE=$(curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook")
echo "  Telegram-antwoord: ${DELETE_RESPONSE}"
unset TELEGRAM_BOT_TOKEN

echo "==> Activeren en n8n herstarten met toegang tot de kennisbank..."
ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
ENC_KEY=$(python3 -c "import json; print(json.load(open('${CONFIG}'))['encryptionKey'])")
docker stop n8n 2>/dev/null || true
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1, activeVersionId='${ACTIVE_VID}' WHERE id='${WF_ID}';"
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker rm n8n 2>/dev/null || true
docker run -d --name n8n --restart always -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -v "${KENNISBANK_DIR}:${KENNISBANK_DIR}" \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e N8N_ENCRYPTION_KEY="${ENC_KEY}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path,http,https,url \
    n8nio/n8n:latest
unset ENC_KEY
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 3

echo ""
echo "Test 1 (CLI-webhook moet nog gewoon werken, ongewijzigd):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"/taken"}'"'"''
echo ""
echo "Test 2 (Telegram-trigger moet nu uit staan):"
echo "  Stuur een bericht naar de Telegram-bot. Verwacht: GEEN reactie meer"
echo "  vanuit Angie/n8n -- alleen Hermes Agent's eigen gateway (als die"
echo "  draait) reageert nu nog op dit bottoken."
