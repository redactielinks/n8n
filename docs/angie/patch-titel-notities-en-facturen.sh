#!/bin/bash
# ============================================================
# Project Angie — Duidelijke titels voor notities/facturen in "Recent
# toegevoegd" (vervolg-fix op patch-facturen-bijlagen-en-fiscale-tips.sh)
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Bugreport: in "Recent toegevoegd" op de wiki-homepage stond bij een
# notitie alleen het bestandspad/tijdstempel te zien (bv.
# "persoonlijk/notities/20260619174057-notitie"), geen idee waar de notitie
# over ging. Hetzelfde gold voor administratie/declaratie/tickets/kopen/
# garantie/verzekeringen: zonder herkende leverancier was de titel alleen
# het kale rubrieklabel (bv. "Administratie"), niet onderscheidend als er
# meerdere pagina's in dezelfde rubriek staan.
#
# Oorzaak: notitiepagina's kregen nooit een eigen "# titel"-kop, en de wiki
# (extract_title in app.py) valt zonder kop terug op het bestandspad. Bij de
# facturen/etc.-pagina's was er wel een kop, maar zonder herkende leverancier
# bleef die kop het kale label.
#
# Fix (alleen de n8n-kant; dit is een gerichte patch boven op
# patch-facturen-bijlagen-en-fiscale-tips.sh, dat moet dus al gedraaid zijn):
# - Notitiepagina's krijgen nu een "# "-kop op basis van een preview van de
#   inhoud.
# - De titel van facturen/etc.-pagina's valt bij een onbekende leverancier
#   terug op een preview van de inhoud, in plaats van het kale label.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers:
#   rm -f patch-titel-notities-en-facturen.sh
#   curl -fsSL -o patch-titel-notities-en-facturen.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-titel-notities-en-facturen.sh?t=$(date +%s)"
#   bash patch-titel-notities-en-facturen.sh
#
# Let op: dit fixt alleen NIEUWE pagina's vanaf nu. Bestaande notitiepagina's
# zonder kop tonen na deze patch alsnog een betere titel in "Recent
# toegevoegd", omdat app.py daar inmiddels ook een vangnet voor heeft (eerste
# tekstregel als fallback) -- maar daarvoor moet je ook update-wiki-site.sh
# opnieuw draaien:
#   rm -f update-wiki-site.sh
#   curl -fsSL -o update-wiki-site.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/update-wiki-site.sh?t=$(date +%s)"
#   bash update-wiki-site.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-19-titel-notities-en-facturen-1"
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
if 'verwerkFinancieelDocument' not in js:
    raise SystemExit("Verwachte 'verwerkFinancieelDocument' niet gevonden -- patch-facturen-bijlagen-en-fiscale-tips.sh moet eerst uitgevoerd zijn, patch afgebroken.")


OUD_TITEL = "  const titel = label + (analyse.leverancier ? ': ' + analyse.leverancier : '');"
NIEUW_TITEL = '  // Zonder leverancier moet de kop toch beschrijven waar de pagina over\n  // gaat -- anders is de titel alleen het rubrieklabel (bv. "Administratie"),\n  // en laat "Recent toegevoegd" op de wiki-homepage dan voor elk document\n  // dezelfde naam zien zonder enig idee wat erin staat.\n  const titel = analyse.leverancier\n    ? label + \': \' + analyse.leverancier\n    : label + \': \' + cleanPreview(content).substring(0, 50);'
OUD_PREVIEW = "  const previewLabel = analyse.leverancier\n    ? label + ': ' + analyse.leverancier + (analyse.bedrag_incl_btw ? ' (' + analyse.bedrag_incl_btw + ')' : '')\n    : label + ': ' + cleanPreview(content).substring(0, 50);"
NIEUW_PREVIEW = "  const previewLabel = analyse.leverancier && analyse.bedrag_incl_btw\n    ? titel + ' (' + analyse.bedrag_incl_btw + ')'\n    : titel;"
OUD_NOTITIE = 'if (cmd === \'notitie\' || cmd === \'notities\' || cmd === \'note\') {\n  const dir = path.join(KENNISBANK_WIKI, \'persoonlijk\', \'notities\');\n  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });\n  const filename = fileTs + \'-notitie.md\';\n  // Vangnet: als een geuploade bijlage (PDF) hier toch belandt omdat de\n  // classificatie het niet als factuur/document herkende, gaat het\n  // origineel niet stilletjes verloren -- het wordt alsnog gelinkt.\n  const bijlageLink = linkBijlage(dir, bijlage);\n  const lines = [\'---\', \'tags:\', \'  - notitie\', \'  - \' + source, \'datum: \' + timestamp, \'bron: \' + source];\n  if (bijlageLink) lines.push(\'bijlage: \' + bijlageLink);\n  lines.push(\'---\', \'\', (bijlageLink ? \'[Bekijk origineel](\' + bijlageLink + \')\\n\\n\' : \'\') + content);\n  fs.writeFileSync(path.join(dir, filename), lines.join(\'\\n\'), \'utf8\');\n  const cleanContent = cleanPreview(content);\n  const preview = cleanContent.length > 60 ? cleanContent.substring(0, 60) + \'...\' : cleanContent;\n  linkInCategorie(\'persoonlijk.md\', \'Persoonlijk\', preview || \'Notitie\', \'persoonlijk/notities/\' + filename);\n  replyText = \'Notitie opgeslagen: "\' + preview + \'"\';'
NIEUW_NOTITIE = 'if (cmd === \'notitie\' || cmd === \'notities\' || cmd === \'note\') {\n  const dir = path.join(KENNISBANK_WIKI, \'persoonlijk\', \'notities\');\n  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });\n  const filename = fileTs + \'-notitie.md\';\n  const cleanContent = cleanPreview(content);\n  const preview = cleanContent.length > 60 ? cleanContent.substring(0, 60) + \'...\' : cleanContent;\n  // Vangnet: als een geuploade bijlage (PDF) hier toch belandt omdat de\n  // classificatie het niet als factuur/document herkende, gaat het\n  // origineel niet stilletjes verloren -- het wordt alsnog gelinkt.\n  const bijlageLink = linkBijlage(dir, bijlage);\n  const fmLines = [\'---\', \'tags:\', \'  - notitie\', \'  - \' + source, \'datum: \' + timestamp, \'bron: \' + source];\n  if (bijlageLink) fmLines.push(\'bijlage: \' + bijlageLink);\n  fmLines.push(\'---\');\n  // Zonder eigen \'# \'-kop valt de wiki terug op het bestandspad als titel\n  // (zie extract_title in app.py) -- "Recent toegevoegd" liet dan alleen\n  // een tijdstempel zien in plaats van waar de notitie over ging.\n  const bodyDelen = [\'# \' + (preview || \'Notitie\'), \'\'];\n  if (bijlageLink) bodyDelen.push(\'[Bekijk origineel](\' + bijlageLink + \')\', \'\');\n  bodyDelen.push(content);\n  fs.writeFileSync(path.join(dir, filename), fmLines.join(\'\\n\') + \'\\n\\n\' + bodyDelen.join(\'\\n\') + \'\\n\', \'utf8\');\n  linkInCategorie(\'persoonlijk.md\', \'Persoonlijk\', preview || \'Notitie\', \'persoonlijk/notities/\' + filename);\n  replyText = \'Notitie opgeslagen: "\' + preview + \'"\';'

vervangingen = [
    (OUD_TITEL, NIEUW_TITEL, "titel-fallback (administratie/declaratie/tickets/kopen/garantie/verzekeringen)"),
    (OUD_PREVIEW, NIEUW_PREVIEW, "previewLabel op categoriepagina"),
    (OUD_NOTITIE, NIEUW_NOTITIE, "notitiepagina's krijgen een eigen kop"),
]

for oud, nieuw, beschrijving in vervangingen:
    aantal = js.count(oud)
    if aantal == 0:
        raise SystemExit(f"Verwachte code voor '{beschrijving}' niet gevonden -- deze fix lijkt al toegepast, of de structuur is gewijzigd. Patch afgebroken zonder iets te wijzigen.")
    if aantal > 1:
        raise SystemExit(f"Code voor '{beschrijving}' komt {aantal}x voor in plaats van 1x -- niet veilig om automatisch te patchen. Patch afgebroken zonder iets te wijzigen.")
    js = js.replace(oud, nieuw)
    print(f"  ~ {beschrijving}")

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
echo "BELANGRIJK: draai ook update-wiki-site.sh opnieuw (zie commentaar boven"
echo "in dit script) -- anders krijgt extract_title in app.py de fallback-fix"
echo "niet, en blijven bestaande titelloze pagina's hun bestandspad tonen."
echo ""
echo "Test (zonder /commando, moet automatisch op /tickets belanden met een"
echo "beschrijvende titel ipv kaal 'Tickets'):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"/tickets Boarding pass KLM 1234 Amsterdam naar Londen, 14:20 vertrek"}'"'"''
echo "Verwacht in de wiki: titel begint met 'Tickets: Boarding pass KLM 1234...'"
echo "ipv alleen 'Tickets'."
echo "  cat \$(ls -t ~/kennisbank/wiki/persoonlijk/tickets/*.md | head -1) | head -5"
