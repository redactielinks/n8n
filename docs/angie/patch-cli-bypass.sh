#!/bin/bash
# ============================================================
# Project Angie — CLI-bypass: commando's direct vanaf de Pi, zonder Telegram
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Telegram heen-en-weer (telefoon -> Telegram-servers -> Tailscale Funnel ->
# n8n) kost altijd een paar seconden. Vanaf de Pi zelf (via Termius/SSH) is
# dat overbodig: dit voegt een eigen, lokale webhook-ingang toe die exact
# dezelfde commandoherkenning (/notitie, /dagboek, /taken, vrije tekst, etc.)
# gebruikt, maar het antwoord direct als HTTP-respons teruggeeft in plaats
# van via Telegram.
#
# Nieuwe nodes:
#   CLI Trigger        - webhook, pad "angie-cli", wacht op een Respond-node
#   Verwerk CLI Input   - zet de POST-body om naar { text, source: 'cli' }
#   Is CLI Bron?        - na de bestaande commandoverwerking: CLI of Telegram?
#   Beantwoord CLI      - stuurt { "reply": "..." } terug als HTTP-respons
#
# Bestaande nodes/logica blijven ongewijzigd, behalve een kleine toevoeging
# aan "Verwerk Wiki Commando": die geeft nu ook een "source"-veld door
# (telegram/cli), zodat "Is CLI Bron?" weet waar het antwoord naartoe moet.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers (anders kun je per ongeluk een verlopen
# gecachete versie uitvoeren zonder dat je het ziet):
#   rm -f patch-cli-bypass.sh
#   curl -fsSL -o patch-cli-bypass.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-cli-bypass.sh?t=$(date +%s)"
#   grep -q "Verwerk CLI Input" patch-cli-bypass.sh && echo "OK: juiste versie gedownload" || echo "FOUT: oude/verkeerde versie"
#   bash patch-cli-bypass.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-18-cli-bypass-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
KENNISBANK_DIR="/home/redactielinks/kennisbank"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF'
import json

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

by_name = {n['name']: n for n in wf['nodes']}

# --- 1. "source"-veld toevoegen aan Verwerk Wiki Commando -----------------
handler = by_name.get('Verwerk Wiki Commando')
if handler is None:
    raise SystemExit("Node 'Verwerk Wiki Commando' niet gevonden — is de routeringspatch al uitgevoerd?")

js = handler['parameters']['jsCode']

OLD_HEAD = (
    "const chatId = String(inp.message?.from?.id || inp.chatId || '7319477310');\n"
    "const voice = inp.message?.voice || inp.message?.audio;"
)
NEW_HEAD = (
    "const chatId = String(inp.message?.from?.id || inp.chatId || '7319477310');\n"
    "const source = inp.source || 'telegram';\n"
    "const voice = inp.message?.voice || inp.message?.audio;"
)
if js.count(OLD_HEAD) != 1:
    raise SystemExit("Verwachte head-regels niet (precies 1x) gevonden in Verwerk Wiki Commando — code is anders dan verwacht, patch afgebroken.")
js = js.replace(OLD_HEAD, NEW_HEAD)

RETURNS_OLD = [
    "return [{ json: { replyText: 'Spraakbericht kon niet worden verwerkt (' + e.message + '). Controleer of de Whisper-server draait op de Mac Mini, of typ je bericht.', chatId, text: '' } }];",
    "return [{ json: { replyText: 'Ik heb niets kunnen verstaan in dat spraakbericht. Probeer het opnieuw of typ je bericht.', chatId, text: '' } }];",
    "return [{ json: { replyText, chatId, text } }];",
]
for old in RETURNS_OLD:
    if js.count(old) != 1:
        raise SystemExit(f"Verwachte return-regel niet (precies 1x) gevonden: {old!r}")
    new = old.replace(", text: '' } }];", ", text: '', source } }];").replace(", text } }];", ", text, source } }];")
    js = js.replace(old, new)

handler['parameters']['jsCode'] = js
print("  ~ 'Verwerk Wiki Commando' geeft nu ook een 'source'-veld door (telegram/cli)")

# --- 2. Nieuwe nodes toevoegen ---------------------------------------------
nieuwe_nodes = [
    {
        "id": "cli-trigger",
        "name": "CLI Trigger",
        "type": "n8n-nodes-base.webhook",
        "typeVersion": 2,
        "position": [1200, 900],
        "webhookId": "angie-cli",
        "parameters": {
            "path": "angie-cli",
            "httpMethod": "POST",
            "responseMode": "responseNode",
            "options": {}
        }
    },
    {
        "id": "cli-verwerk-input",
        "name": "Verwerk CLI Input",
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": [1424, 900],
        "parameters": {
            "jsCode": (
                "const body = $input.first().json.body || $input.first().json;\n"
                "const text = (body.text || body.command || '').toString();\n"
                "return [{ json: { text, source: 'cli' } }];"
            )
        }
    },
    {
        "id": "cli-is-bron",
        "name": "Is CLI Bron?",
        "type": "n8n-nodes-base.if",
        "typeVersion": 2,
        "position": [2756, 900],
        "parameters": {
            "conditions": {
                "options": {
                    "caseSensitive": True,
                    "leftValue": "",
                    "typeValidation": "loose"
                },
                "conditions": [
                    {
                        "id": "cli-bron-check",
                        "leftValue": "={{ $json.source }}",
                        "rightValue": "cli",
                        "operator": {"type": "string", "operation": "equals"}
                    }
                ],
                "combinator": "and"
            },
            "options": {}
        }
    },
    {
        "id": "cli-beantwoord",
        "name": "Beantwoord CLI",
        "type": "n8n-nodes-base.respondToWebhook",
        "typeVersion": 1.1,
        "position": [2976, 800],
        "parameters": {
            "respondWith": "json",
            "responseBody": "={ \"reply\": {{ JSON.stringify($json.replyText) }} }"
        }
    },
]
bestaande_namen = {n['name'] for n in wf['nodes']}
for node in nieuwe_nodes:
    if node['name'] in bestaande_namen:
        raise SystemExit(f"Node '{node['name']}' bestaat al — patch niet opnieuw uitvoeren zonder eerst te controleren.")
    wf['nodes'].append(node)
    print(f"  + node toegevoegd: {node['name']}")

# --- 3. Connections aansluiten ---------------------------------------------
conns = wf['connections']

if 'Verwerk Wiki Commando' not in conns or conns['Verwerk Wiki Commando'] != {
    'main': [[{'node': 'Telegram: Wiki Antwoord', 'type': 'main', 'index': 0}]]
}:
    raise SystemExit(
        "Onverwachte bestaande connectie vanaf 'Verwerk Wiki Commando': "
        f"{conns.get('Verwerk Wiki Commando')!r} — patch afgebroken, structuur is anders dan verwacht."
    )

conns['CLI Trigger'] = {'main': [[{'node': 'Verwerk CLI Input', 'type': 'main', 'index': 0}]]}
conns['Verwerk CLI Input'] = {'main': [[{'node': 'Is Wiki Commando?', 'type': 'main', 'index': 0}]]}
conns['Verwerk Wiki Commando'] = {'main': [[{'node': 'Is CLI Bron?', 'type': 'main', 'index': 0}]]}
conns['Is CLI Bron?'] = {
    'main': [
        [{'node': 'Beantwoord CLI', 'type': 'main', 'index': 0}],
        [{'node': 'Telegram: Wiki Antwoord', 'type': 'main', 'index': 0}],
    ]
}
print("  ~ 'CLI Trigger' -> 'Verwerk CLI Input' -> 'Is Wiki Commando?' aangesloten")
print("  ~ 'Verwerk Wiki Commando' -> 'Is CLI Bron?' -> [Beantwoord CLI | Telegram: Wiki Antwoord]")

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF

echo "==> Importeren..."
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all

echo "==> Activeren en n8n herstarten met toegang tot de kennisbank..."
ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
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
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path,http,https,url \
    n8nio/n8n:latest
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 3
echo ""
echo "Test rechtstreeks vanaf de Pi (snel, blijft binnen het tailnet):"
echo "  curl -s -X POST http://localhost:5678/webhook/angie-cli -H 'Content-Type: application/json' -d '{\"text\":\"/taken\"}'"
echo "  curl -s -X POST http://localhost:5678/webhook/angie-cli -H 'Content-Type: application/json' -d '{\"text\":\"even een testje zonder commando\"}'"
echo ""
echo "Test vanaf een ander tailnet-apparaat (bv. iPhone via Termius/Tailscale-app):"
echo "  curl -s -X POST http://100.77.5.104:5678/webhook/angie-cli -H 'Content-Type: application/json' -d '{\"text\":\"/notitie test via CLI\"}'"
echo ""
echo "Verwacht antwoord: {\"reply\":\"...\"} direct terug, zonder dat er iets naar Telegram gaat."
echo "Controleer daarna op de Pi of het bestand is aangemaakt:"
echo "  find ~/kennisbank/wiki/persoonlijk -type f -newer ~/kennisbank/wiki/index.md"
