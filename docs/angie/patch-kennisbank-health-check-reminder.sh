#!/bin/bash
# Voegt een NIEUWE, losse workflow toe (raakt de Secretaresse-workflow niet
# aan): elke 1e van de maand om 09:00 stuurt deze een Telegram-herinnering
# om de maandelijkse kennisbank health check te laten draaien (gevraagd in
# een Claude Code-sessie, zoals deze).
#
# Gebruikt de al bestaande Telegram-credential (zk613MPgh3b3pkBZ,
# "jaouiyes_n8n_bot"). Er wordt geen nieuwe credential aangemaakt.
set -euo pipefail

DB="/home/redactielinks/.n8n/database.sqlite"
TELEGRAM_CRED_ID="zk613MPgh3b3pkBZ"
TELEGRAM_CRED_NAME="jaouiyes_n8n_bot"
CHAT_ID="7319477310"
NEW_WF_NAME="Kennisbank — Maandelijkse Health Check Herinnering"

echo "============================================================"
echo "  Maandelijkse health-check-herinnering toevoegen"
echo "============================================================"

echo "==> Alle workflows exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/allwf.json 2>/dev/null
docker cp n8n:/tmp/allwf.json /tmp/allwf.json

NEW_WF_ID=$(python3 -c "import secrets,string; print(''.join(secrets.choice(string.ascii_letters+string.digits) for _ in range(16)))")
echo "  Nieuw workflow-ID: ${NEW_WF_ID}"

NEW_WF_ID="$NEW_WF_ID" NEW_WF_NAME="$NEW_WF_NAME" TELEGRAM_CRED_ID="$TELEGRAM_CRED_ID" \
TELEGRAM_CRED_NAME="$TELEGRAM_CRED_NAME" CHAT_ID="$CHAT_ID" python3 - <<'PYEOF'
import json, os

wf_id = os.environ['NEW_WF_ID']
wf_name = os.environ['NEW_WF_NAME']
cred_id = os.environ['TELEGRAM_CRED_ID']
cred_name = os.environ['TELEGRAM_CRED_NAME']
chat_id = os.environ['CHAT_ID']

with open('/tmp/allwf.json', encoding='utf-8') as f:
    data = json.load(f)
workflows = data if isinstance(data, list) else [data]

if any(w.get('name') == wf_name for w in workflows):
    print(f"Workflow '{wf_name}' bestaat al, niets toegevoegd.")
else:
    reminder_text = (
        "Tijd voor de maandelijkse kennisbank health check.\n\n"
        "Vraag in een Claude Code-sessie: \"doe een health check van de "
        "kennisbank\"."
    )
    new_wf = {
        "id": wf_id,
        "name": wf_name,
        "nodes": [
            {
                "id": "health-check-schedule-v1",
                "name": "Elke 1e van de maand",
                "type": "n8n-nodes-base.scheduleTrigger",
                "typeVersion": 1.2,
                "position": [0, 0],
                "parameters": {
                    "rule": {
                        "interval": [
                            {"field": "cronExpression", "expression": "0 9 1 * *"}
                        ]
                    }
                }
            },
            {
                "id": "health-check-telegram-v1",
                "name": "Telegram: Health Check Herinnering",
                "type": "n8n-nodes-base.telegram",
                "typeVersion": 1.2,
                "position": [260, 0],
                "parameters": {
                    "chatId": chat_id,
                    "text": reminder_text,
                    "additionalFields": {"appendAttribution": False}
                },
                "credentials": {
                    "telegramApi": {"id": cred_id, "name": cred_name}
                }
            }
        ],
        "connections": {
            "Elke 1e van de maand": {
                "main": [[{"node": "Telegram: Health Check Herinnering", "type": "main", "index": 0}]]
            }
        },
        "settings": {}
    }
    workflows.append(new_wf)
    print(f"Workflow '{wf_name}' toegevoegd (id: {wf_id}).")

with open('/tmp/allwf-modified.json', 'w', encoding='utf-8') as f:
    json.dump(workflows, f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/allwf-modified.json")
PYEOF

echo ""
echo "==> Importeren..."
docker cp /tmp/allwf-modified.json n8n:/tmp/allwf-modified.json
docker exec n8n n8n import:workflow --input=/tmp/allwf-modified.json --overwrite-all

echo "==> Activeren..."
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1 WHERE id='${NEW_WF_ID}';"

echo ""
echo "==> Container herstarten..."
ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${NEW_WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
if [ -n "${ACTIVE_VID:-}" ]; then
  sqlite3 "${DB}" "UPDATE workflow_entity SET activeVersionId='${ACTIVE_VID}' WHERE id='${NEW_WF_ID}';"
fi
CONFIG="/home/redactielinks/.n8n/config"
ENC_KEY=$(python3 -c "import json; print(json.load(open('${CONFIG}'))['encryptionKey'])")
docker stop n8n 2>/dev/null || true
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
echo "  Klaar. Workflow-ID: ${NEW_WF_ID}"
echo "  Stuurt elke 1e van de maand om 09:00 een Telegram-herinnering."
echo "============================================================"
