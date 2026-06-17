#!/bin/bash
# Repareert en verstrengt de "Google Maps" (plaatsen_zoeken) tool van de
# Secretaresse-agent.
#
# Probleem 1 (crash): de tool gebruikte het globale `fetch()`, dat niet
# bestaat in de sandbox waarin Code-tools draaien (vandaar "fetch is not
# defined"). Dit liet de hele Secretaresse-node vastlopen, waardoor er
# soms HELEMAAL GEEN Telegram-antwoord kwam (zoals bij de hoogwater-
# vraag over Holwerd). Fix: gebruik n8n's eigen `helpers.httpRequest`,
# de manier waarop n8n Code-tools altijd HTTP-verzoeken horen te doen.
#
# Probleem 2 (verkeerd gebruikt): het kleine lokale model greep naar
# deze tool zodra een vraag een plaatsnaam bevatte (bv. "hoog water bij
# Holwerd"), ook al gaat de vraag niet over een adres. Fix: de
# tool-beschrijving (wat de agent ziet) expliciet beperken tot het
# opzoeken van een SPECIFIEKE zaak/winkel op naam, en expliciet
# uitsluiten: routes, getijden, weer, algemene vragen (-> web_zoeken).
#
# Repareert daarnaast een tweede, los probleem in dezelfde agent: de
# agent gaf 21 minuten na elkaar tweemaal exact "Het is 16:00 uur.",
# ook al was de echte tijd inmiddels 16:21. De systeem-instructie zelf
# berekent de tijd wel vers bij elke aanroep, maar het kleine lokale
# model "leunde" op het eigen antwoord van de vorige beurt dat nog in
# het gespreksgeheugen (Window Buffer Memory) stond. Fix: een
# expliciete regel toevoegen die zegt dat een eerder tijdantwoord in
# de geschiedenis nooit hergebruikt mag worden.
#
# Optioneel: geef een nieuwe API-sleutel als argument om de oude
# (blootgestelde) Google Maps-sleutel te vervangen, bv.:
#   bash patch-maps-en-tijd-geheugen-fix.sh "NIEUWE_SLEUTEL_HIER"
# Zonder argument blijft de bestaande sleutel ongewijzigd.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
NEW_API_KEY="${1:-}"

echo "============================================================"
echo "  Google Maps tool repareren en aanscherpen"
echo "============================================================"
echo ""

echo "==> Workflow exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec6.json 2>/dev/null
docker cp n8n:/tmp/sec6.json /tmp/sec6.json

python3 - "$WF_ID" "$NEW_API_KEY" <<'PYEOF'
import json, sys

wf_id, new_api_key = sys.argv[1], sys.argv[2]

EXPECTED_DESCRIPTION = "Zoek plaatsen, restaurants of winkels op een locatie. Alleen voor het vinden van adressen en locaties, NIET voor routes, reistijden of navigatie."

EXPECTED_CODE = """
const query = $input.first().json.query || $input.first().json.input || "";
const apiKey = "AIzaSyAVq4QNuliXGU-iqCuetPZXMbCqiW5SVrI";

// Zoek plaatsen via Places Text Search
const url = `https://maps.googleapis.com/maps/api/place/textsearch/json?query=${encodeURIComponent(query)}&language=nl&key=${apiKey}`;
const resp = await fetch(url);
const data = await resp.json();

if (data.status !== "OK") {
 return JSON.stringify({ error: data.status, message: "Geen resultaten gevonden voor: " + query });
}

const places = data.results.slice(0, 5).map(p => ({
 naam: p.name,
 adres: p.formatted_address,
 beoordeling: p.rating || "onbekend",
 open: p.opening_hours?.open_now !== undefined ? (p.opening_hours.open_now ? "Nu open" : "Nu gesloten") : "onbekend",
 types: p.types?.slice(0,3).join(", ") || ""
}));

return JSON.stringify(places);
"""

NEW_DESCRIPTION = (
    "Zoek een SPECIFIEKE plek, restaurant of winkel op naam (bijv. 'restaurant "
    "De Kas Amsterdam'). Geeft naam, adres, beoordeling en openingstijden terug. "
    "NIET gebruiken voor: routes, reistijden, navigatie, getijden/waterstanden, "
    "weer, of algemene vragen over een plaats — gebruik daarvoor web_zoeken."
)

with open('/tmp/sec6.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == wf_id)

target = None
for n in wf['nodes']:
    if n['name'] == 'Google Maps':
        target = n
        break

if target is None:
    print("FOUT: node 'Google Maps' niet gevonden.")
    sys.exit(1)

params = target.get('parameters', {})
current_code = params.get('jsCode', '')
current_desc = params.get('description', '')

if current_code != EXPECTED_CODE:
    print("FOUT: de huidige jsCode komt niet exact overeen met wat verwacht werd.")
    print("Huidige jsCode:")
    print(current_code)
    sys.exit(1)

if current_desc != EXPECTED_DESCRIPTION:
    print("FOUT: de huidige description komt niet exact overeen met wat verwacht werd.")
    print("Huidige description:")
    print(current_desc)
    sys.exit(1)

new_code = current_code.replace(
    'const resp = await fetch(url);\nconst data = await resp.json();',
    'const data = await helpers.httpRequest({ method: "GET", url, json: true });',
)

if new_api_key:
    new_code = new_code.replace(
        'const apiKey = "AIzaSyAVq4QNuliXGU-iqCuetPZXMbCqiW5SVrI";',
        f'const apiKey = "{new_api_key}";',
    )
    print("API-sleutel vervangen door de nieuwe sleutel.")
else:
    print("Geen nieuwe API-sleutel opgegeven, bestaande sleutel blijft staan.")

params['jsCode'] = new_code
params['description'] = NEW_DESCRIPTION
target['parameters'] = params

print("Code aangepast: fetch() vervangen door helpers.httpRequest (voorkomt de crash).")
print("Beschrijving aangescherpt: tool wordt nu alleen nog voor specifieke zaak/winkel-zoekopdrachten aangeboden.")

print("")
print("==> Tweede fix: stale tijd-antwoord uit gespreksgeheugen...")

secretaresse = None
for n in wf['nodes']:
    if n['name'] == 'Secretaresse':
        secretaresse = n
        break

if secretaresse is None:
    print("FOUT: node 'Secretaresse' niet gevonden.")
    sys.exit(1)

OLD_TIJD_SNIPPET = (
    "Gebruik dit DIRECT bij datum/tijd-vragen, GEEN tool (ook niet google_calendar)."
)
NEW_TIJD_SNIPPET = (
    "Gebruik dit DIRECT bij datum/tijd-vragen, GEEN tool (ook niet google_calendar). "
    "Gebruik ALTIJD deze waarde vers — kopieer NOOIT een tijdstip uit een eerder "
    "antwoord in dit gesprek, ook niet als de vraag identiek lijkt."
)

opts = secretaresse.get('parameters', {}).get('options', {})
sysmsg = opts.get('systemMessage', '')

if OLD_TIJD_SNIPPET not in sysmsg:
    print("FOUT: verwachte tijd-tekst niet gevonden in de systeem-instructie.")
    print("Huidige systeem-instructie:")
    print(sysmsg)
    sys.exit(1)

opts['systemMessage'] = sysmsg.replace(OLD_TIJD_SNIPPET, NEW_TIJD_SNIPPET)
secretaresse['parameters']['options'] = opts
print("Systeem-instructie aangepast: expliciete regel tegen hergebruik van oude tijd-antwoorden toegevoegd.")

with open('/tmp/sec6-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec6-modified.json")
PYEOF

echo ""
echo "==> Importeren en activeren..."
docker cp /tmp/sec6-modified.json n8n:/tmp/sec6-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec6-modified.json --overwrite-all

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
echo "  Klaar. Test in Telegram: 'hoe laat is het hoog water bij"
echo "  Holwerd' — dit zou nu via web_zoeken moeten gaan, niet meer"
echo "  via Google Maps crashen."
echo "============================================================"
