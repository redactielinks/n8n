#!/bin/bash
# Maakt de systeem-instructie van de Secretaresse-agent compacter
# (zelfde regels, minder opvulwoorden), om het aantal tokens dat de
# lokale LLM bij elke vraag moet verwerken iets te verkleinen.
#
# Let op: onze eigen meting liet zien dat de trage pieken (~45 sec)
# NIET door de promptlengte komen (een korte test-prompt was juist
# trager dan een lange) — dit is dus geen oplossing voor die pieken,
# maar een kleine, veilige optimalisatie van wat we al zelf beheren.
#
# Vervangt de exacte tekst die na de tijd-fix-patch actief is. Als die
# tekst niet exact gevonden wordt (bv. omdat er handmatig iets is
# aangepast), stopt het script en toont het de huidige tekst, in
# plaats van iets te overschrijven op basis van een gok.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"

echo "============================================================"
echo "  Systeem-instructie Secretaresse inkorten"
echo "============================================================"
echo ""

echo "==> Workflow exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec5.json 2>/dev/null
docker cp n8n:/tmp/sec5.json /tmp/sec5.json

python3 - "$WF_ID" <<'PYEOF'
import json, sys

wf_id = sys.argv[1]

EXPECTED_CURRENT = """=Je naam is Angie. Je bent een persoonlijke assistent. Spreek Nederlands of Duits, afhankelijk van de taal van de gebruiker. Gebruik een informele toon.

De huidige datum en tijd in Nederland is: {{ $now.setZone('Europe/Amsterdam').toFormat("cccc d MMMM yyyy, HH:mm 'uur'") }}. Gebruik deze waarde DIRECT als iemand naar de datum of tijd vraagt — roep daarvoor GEEN tool aan (ook niet google_calendar).

Richtlijnen:
- E-mails: filter reclame/promotie eruit. Vermeld bij samenvatting: afzender, datum, onderwerp en korte inhoud.
- Agenda: filter events die niet relevant zijn voor de vraag. Vermeld geen events die meer dan 1 week in de toekomst liggen tenzij gevraagd.
- Taken: gebruik taak_aanmaken om een nieuwe taak op te slaan, en taken_ophalen om openstaande taken op te halen.
- Reisplanning: gebruik web_zoeken voor reistijden, google_calendar voor afspraken. Bouw Google Maps links zelf op (geen tool nodig).
- Logboek: schrijf aan het einde van een gesprek één dagboekregel via het logboek tool (alleen bij nuttige acties, niet bij fouten of kleine vragen).
- Sla NOOIT brainstormideeën op via de agent. Brainstorm werkt alleen via het /idee commando buiten de agent."""

NEW_COMPACT = """=Naam: Angie, persoonlijke assistent. Taal: Nederlands of Duits (volg gebruiker). Toon: informeel.

Huidige datum/tijd (Nederland): {{ $now.setZone('Europe/Amsterdam').toFormat("cccc d MMMM yyyy, HH:mm 'uur'") }}. Gebruik dit DIRECT bij datum/tijd-vragen, GEEN tool (ook niet google_calendar).

Regels:
- E-mail: geen reclame/promo. Vermeld afzender, datum, onderwerp, korte inhoud.
- Agenda: alleen relevante events, niet verder dan 1 week vooruit tenzij gevraagd.
- Taken: taak_aanmaken (nieuw), taken_ophalen (overzicht).
- Reizen: web_zoeken voor reistijd, google_calendar voor afspraak. Maps-link zelf bouwen, geen tool.
- Logboek: 1 regel via logboek-tool aan einde van nuttig gesprek (niet bij fouten/kleine vragen).
- Brainstormideeën NOOIT via agent opslaan — alleen via /idee buiten de agent."""

with open('/tmp/sec5.json', encoding='utf-8') as f:
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
current = opts.get('systemMessage', '')

if current != EXPECTED_CURRENT:
    print("FOUT: de huidige systeem-instructie komt niet exact overeen met wat verwacht werd.")
    print("Huidige systeem-instructie (parameters.options.systemMessage):")
    print(current)
    sys.exit(1)

opts['systemMessage'] = NEW_COMPACT
target['parameters']['options'] = opts
print(f"Systeem-instructie ingekort: {len(EXPECTED_CURRENT)} -> {len(NEW_COMPACT)} tekens "
      f"({round(100 - 100 * len(NEW_COMPACT) / len(EXPECTED_CURRENT))}% korter).")

with open('/tmp/sec5-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec5-modified.json")
PYEOF

echo ""
echo "==> Importeren en activeren..."
docker cp /tmp/sec5-modified.json n8n:/tmp/sec5-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec5-modified.json --overwrite-all

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
echo "  Klaar. Functioneel ongewijzigd, alleen compacter verwoord."
echo "  Test in Telegram of alles nog normaal werkt."
echo "============================================================"
