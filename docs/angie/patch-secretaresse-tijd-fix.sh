#!/bin/bash
# Fix voor twee problemen die ontstonden na de overstap naar de lokale
# LLM (Mac Mini): de agent gaf een verkeerde kloktijd, en reageerde traag
# op simpele vragen.
#
# Oorzaak: de systeem-instructie van de Secretaresse-node injecteerde
# alleen een ruwe ISO-tijdstempel ({{ $now }}, zonder tijdzone-context).
# Het kleine lokale model (4B) interpreteerde die stempel verkeerd en
# verzon een afwijkende tijd. Bovendien riep de agent voor een simpele
# tijd-vraag onnodig de Google Agenda-tool aan (elke tool-aanroep is een
# extra, trage lokale-LLM-stap).
#
# Fix: vervang de ruwe tijdstempel door een leesbare datum/tijd in de
# juiste tijdzone (Europe/Amsterdam), en voeg een expliciete regel toe
# dat er voor datum/tijd-vragen geen tool nodig is.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"

OLD_SNIPPET="De datum van vandaag is {{ \$now }}."
NEW_SNIPPET="De huidige datum en tijd in Nederland is: {{ \$now.setZone('Europe/Amsterdam').toFormat(\"cccc d MMMM yyyy, HH:mm 'uur'\") }}. Gebruik deze waarde DIRECT als iemand naar de datum of tijd vraagt — roep daarvoor GEEN tool aan (ook niet google_calendar)."

echo "============================================================"
echo "  Tijd-fix voor Secretaresse-agent"
echo "============================================================"
echo ""

echo "==> Workflow exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec4.json 2>/dev/null
docker cp n8n:/tmp/sec4.json /tmp/sec4.json

python3 - "$WF_ID" "$OLD_SNIPPET" "$NEW_SNIPPET" <<'PYEOF'
import json, sys

wf_id, old_snippet, new_snippet = sys.argv[1:4]

with open('/tmp/sec4.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == wf_id)

target = None
for n in wf['nodes']:
    if n['name'] == 'Secretaresse':
        target = n
        break

if target is None:
    print("FOUT: node 'Secretaresse' niet gevonden.")
    sys.exit(1)

opts = target.get('parameters', {}).get('options', {})
sysmsg = opts.get('systemMessage', '')

if old_snippet not in sysmsg:
    print("FOUT: verwachte tekst niet gevonden in de systeem-instructie.")
    print("Huidige systeem-instructie (parameters.options.systemMessage):")
    print(sysmsg)
    sys.exit(1)

opts['systemMessage'] = sysmsg.replace(old_snippet, new_snippet)
target['parameters']['options'] = opts
print("Systeem-instructie aangepast: tijdstempel vervangen door leesbare NL-tijd + 'geen tool nodig' regel.")

with open('/tmp/sec4-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec4-modified.json")
PYEOF

echo ""
echo "==> Importeren en activeren..."
docker cp /tmp/sec4-modified.json n8n:/tmp/sec4-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec4-modified.json --overwrite-all

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
echo "  Klaar. Test in Telegram nogmaals: 'hoe laat is het'."
echo "  Dit zou nu sneller moeten gaan (geen agenda-tool meer) en"
echo "  de juiste tijd moeten geven."
echo "============================================================"
