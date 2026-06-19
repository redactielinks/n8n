#!/bin/bash
# ============================================================
# Project Angie — Factuurherkenning miste "Factuurnummer" (vervolg-fix op
# patch-facturen-bijlagen-en-fiscale-tips.sh)
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Bugreport: geuploade facturen kwamen nog steeds als notitie onder
# Persoonlijk terecht in plaats van onder Administratie/Declaratie/etc.,
# ook na de eerdere factuurherkenning-fix.
#
# Oorzaak: de heuristiek gebruikte /\bfactuur\b/ -- een woordgrens direct
# na "factuur". Maar "Factuurnummer" heeft geen woordgrens tussen "factuur"
# en "nummer" (allebei letters), dus \bfactuur\b matchte "Factuurnummer:
# 87410" helemaal niet, terwijl dat juist de meest voorkomende tekst op een
# factuur is. Dezelfde regel werd ook nog ALTIJD voorafgegaan door "Bestand
# ontvangen (bestandsnaam):" vanuit de wiki-site, wat titels onduidelijk
# maakte (zie ook app.py -- die fix komt mee via update-wiki-site.sh).
#
# Fix: "factuur"/"invoice" zonder woordgrens erna (matcht dus ook
# "factuurnummer", "facturatie", "invoiced", etc.), plus een paar extra
# synoniemen (nota, kwitantie, kassabon).
#
# Vereist dat patch-facturen-bijlagen-en-fiscale-tips.sh al is uitgevoerd.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers:
#   rm -f patch-factuurherkenning-regex-fix.sh
#   curl -fsSL -o patch-factuurherkenning-regex-fix.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-factuurherkenning-regex-fix.sh?t=$(date +%s)"
#   bash patch-factuurherkenning-regex-fix.sh
#
# Draai ook update-wiki-site.sh opnieuw (voor de "Bestand ontvangen"-fix in
# app.py, die titels nog verder verduidelijkt):
#   rm -f update-wiki-site.sh
#   curl -fsSL -o update-wiki-site.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/update-wiki-site.sh?t=$(date +%s)"
#   bash update-wiki-site.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-19-factuurherkenning-regex-fix-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
KENNISBANK_DIR="/home/redactielinks/kennisbank"

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

by_name = {n['name']: n for n in wf['nodes']}
handler = by_name.get('Verwerk Wiki Commando')
if handler is None:
    raise SystemExit("Node 'Verwerk Wiki Commando' niet gevonden -- naam/structuur is anders dan verwacht, patch afgebroken.")

js = handler['parameters']['jsCode']
if 'lijktOpFactuur' not in js:
    raise SystemExit("Verwachte 'lijktOpFactuur' niet gevonden -- patch-facturen-bijlagen-en-fiscale-tips.sh moet eerst uitgevoerd zijn, patch afgebroken.")

OUD = 'const lijktOpFactuur = /\\bfactuur\\b|\\binvoice\\b|\\bbon(nummer)?\\b/i.test(text)\n  && /btw|vat|totaalbedrag|total amount|factuurnummer|invoice number|te betalen|bedrag/i.test(text);'

NIEUW = '// "factuur" zonder \\b erna, want "factuurnummer" heeft geen woordgrens\n// tussen "factuur" en "nummer" -- \\bfactuur\\b miste daardoor juist de\n// meest voorkomende factuurtekst.\nconst lijktOpFactuur = /factuur|invoice|\\bbon(nummer)?\\b|\\bnota\\b|kwitantie|kassabon/i.test(text)\n  && /btw|vat|totaalbedrag|total amount|factuurnummer|invoice number|te betalen|bedrag/i.test(text);'

aantal = js.count(OUD)
if aantal == 0:
    raise SystemExit("Verwachte oude regex-code niet gevonden -- deze fix lijkt al toegepast, of de structuur is gewijzigd. Patch afgebroken zonder iets te wijzigen.")
if aantal > 1:
    raise SystemExit(f"Oude regex-code komt {aantal}x voor in plaats van 1x -- niet veilig om automatisch te patchen. Patch afgebroken zonder iets te wijzigen.")
js = js.replace(OUD, NIEUW)
print("  ~ lijktOpFactuur: 'factuur'/'invoice' zonder woordgrens erna, matcht nu ook 'factuurnummer'")

handler['parameters']['jsCode'] = js

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF_INNER

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
echo "Test (zonder /commando, 'Factuurnummer' zonder los woord 'factuur' moet"
echo "nu toch herkend worden):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"Factuurnummer: 87410\nBedrag: 50.00\nBTW: 8.68"}'"'"''
echo "Verwacht: 'Administratie opgeslagen: ...' NIET als losse notitie."
