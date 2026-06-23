#!/bin/bash
# ============================================================
# Project Angie — LLM-hallucinatie fixen bij niet-factuur-tekst
#                 + foutieve "Bakkerij De Gouden Brood"-pagina opruimen
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Bug (gemeld door gebruiker, met screenshots): het Telegram-bericht
# "koppel mijn brouwer.gert@gmail.com account aan n8n" (een instructie,
# geen document) werd door de vrije-tekst-intentclassificatie ten onrechte
# als 'administratie' geclassificeerd. Vervolgens kreeg verwerkFinancieel-
# Document() die tekst, en omdat die functie altijd JSON-factuurvelden
# MOET teruggeven, verzon het LLM een complete nepfactuur ("Bakkerij De
# Gouden Brood", FB-2024-0315-001, 105,93 euro) -- een leverancier die niet
# bestaat en niets met het verzoek te maken heeft. Die nepfactuur werd
# vervolgens echt op de wiki opgeslagen.
#
# Deze patch pakt de oorzaak op twee niveaus aan:
#  1. verwerkFinancieelDocument() krijgt een nieuw veld "is_document" in
#     de JSON die het LLM moet teruggeven, met een expliciete instructie om
#     dat op false te zetten (en niets te verzinnen) als de tekst duidelijk
#     geen factuur/bon/ticket/document is maar bv. een vraag, verzoek of
#     instructie. slaFinancieelDocumentOp() respecteert dat: bij
#     is_document=false wordt er geen nepdocument opgeslagen, maar de
#     tekst als gewone notitie bewaard (niets gaat verloren), met een
#     duidelijke melding terug.
#  2. De vrije-tekst-intentclassificatie krijgt een verduidelijking dat
#     administratie/declaratie/tickets/kopen/garantie/verzekeringen alleen
#     gekozen mogen worden voor tekst die zelf een document met concrete
#     gegevens is -- nooit voor een vraag/verzoek/instructie. Dit voorkomt
#     dat dit soort berichten überhaupt in de factuur-tak terechtkomen.
#
# Daarnaast ruimt dit script de al opgeslagen foutieve pagina over
# "Bakkerij De Gouden Brood" (factuurnummer FB-2024-0315-001) op: het
# bestand zelf en de koppeling op de Persoonlijk-categoriepagina.
#
# Dit lost niet het oorspronkelijke verzoek van de gebruiker op (Gmail-
# account koppelen aan n8n) -- dat kan niet via een script, alleen via de
# n8n-webinterface (OAuth2-credential), zie docs/angie/TODO.md.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude
# lokale kopie en download daarna vers:
#   rm -f patch-fix-llm-hallucinatie-niet-document.sh
#   curl -fsSL -o patch-fix-llm-hallucinatie-niet-document.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-fix-llm-hallucinatie-niet-document.sh?t=$(date +%s)"
#   bash patch-fix-llm-hallucinatie-niet-document.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-23-fix-hallucinatie-niet-document-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
KENNISBANK_DIR="/home/redactielinks/kennisbank"
KENNISBANK_WIKI="${KENNISBANK_DIR}/wiki"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen van de Code-node..."
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

if 'is_document' in js:
    raise SystemExit("'is_document' staat er al in -- deze patch lijkt al uitgevoerd te zijn, niet opnieuw uitvoeren.")
if 'verwerkFinancieelDocument' not in js:
    raise SystemExit("Verwachte 'verwerkFinancieelDocument' niet gevonden -- patch-facturen-bijlagen-en-fiscale-tips.sh moet eerst uitgevoerd zijn, patch afgebroken zonder iets te wijzigen.")

# --- 1. defaults: is_document standaard true (alleen false als het LLM dat expliciet aangeeft) ---
OLD_DEFAULTS = (
    "  const defaults = {\n"
    "    leverancier: '', factuurdatum: '', factuurnummer: '', factuurperiode: '',\n"
    "    bedrag_excl_btw: '', btw_percentage: '', btw_bedrag: '', bedrag_incl_btw: '',\n"
    "    categorie_fiscaal: '', aftrekbaar: 'onbekend', titel_kort: '',\n"
    "    tip: 'Geen tip gegenereerd -- controleer zelf het bedrag en de btw.',\n"
    "  };"
)
NEW_DEFAULTS = (
    "  const defaults = {\n"
    "    is_document: true,\n"
    "    leverancier: '', factuurdatum: '', factuurnummer: '', factuurperiode: '',\n"
    "    bedrag_excl_btw: '', btw_percentage: '', btw_bedrag: '', bedrag_incl_btw: '',\n"
    "    categorie_fiscaal: '', aftrekbaar: 'onbekend', titel_kort: '',\n"
    "    tip: 'Geen tip gegenereerd -- controleer zelf het bedrag en de btw.',\n"
    "  };"
)
if js.count(OLD_DEFAULTS) != 1:
    raise SystemExit("Verwachte 'defaults'-blok niet exact 1x gevonden -- niet veilig om te patchen, afgebroken zonder iets te wijzigen.")
js = js.replace(OLD_DEFAULTS, NEW_DEFAULTS)
print("  ~ defaults: is_document toegevoegd")

# --- 2. systeemprompt van verwerkFinancieelDocument: vraag om is_document, verbied verzinnen ---
OLD_JSON_LINE = (
    "          content: 'Je bent een Nederlandse administratief en fiscaal assistent voor een PARTICULIER ZONDER eigen bedrijf of onderneming -- geen zzp\\'er, geen btw-aangifte, geen ondernemersaftrek. Je krijgt de tekst van een factuur, bon, ticket of ander document. Antwoord uitsluitend als JSON (geen markdown). Velden: {\"titel_kort\":"
)
if js.count(OLD_JSON_LINE) != 1:
    raise SystemExit("Verwachte systeemprompt-aanhef van verwerkFinancieelDocument niet exact 1x gevonden -- afgebroken zonder iets te wijzigen.")
NEW_JSON_LINE = (
    "          content: 'Je bent een Nederlandse administratief en fiscaal assistent voor een PARTICULIER ZONDER eigen bedrijf of onderneming -- geen zzp\\'er, geen btw-aangifte, geen ondernemersaftrek. Je krijgt een stuk tekst dat MEESTAL de inhoud is van een factuur, bon, ticket of ander document, maar soms per ongeluk iets anders is (bv. een vraag, verzoek of instructie zoals \"koppel mijn account aan X\") -- controleer dit eerst. Antwoord uitsluitend als JSON (geen markdown). Velden: {\"is_document\":\"true als de tekst daadwerkelijk de inhoud van een factuur/bon/ticket/document is, false als het duidelijk iets anders is zoals een vraag, verzoek of instructie -- bij false NOOIT de overige velden invullen met verzonnen waarden, laat ze dan allemaal leeg/onbekend\",\"titel_kort\":"
)
js = js.replace(OLD_JSON_LINE, NEW_JSON_LINE)
print("  ~ verwerkFinancieelDocument: 'is_document'-veld + anti-hallucinatie-instructie toegevoegd aan systeemprompt")

# --- 3. vrije-tekst-intentclassificatie: verduidelijk dat administratie e.d. een document vereist ---
OLD_CLASSIFIER = (
    "administratie = officiele documenten, formulieren, brieven, contracten of belastingzaken. declaratie = onkostendeclaraties of bonnetjes die je later wilt terugvragen."
)
if js.count(OLD_CLASSIFIER) != 1:
    raise SystemExit("Verwachte classificatie-tekst niet exact 1x gevonden -- afgebroken zonder iets te wijzigen.")
NEW_CLASSIFIER = (
    "administratie = officiele documenten, formulieren, brieven, contracten of belastingzaken -- kies dit (en declaratie/tickets/kopen/garantie/verzekeringen) alleen als de tekst zelf zo\\'n document is met concrete gegevens (bedrag, datum, nummer, leverancier e.d.); een vraag, verzoek of instructie (bv. \"koppel mijn account aan X\") is altijd notitie of taak, nooit administratie. declaratie = onkostendeclaraties of bonnetjes die je later wilt terugvragen."
)
js = js.replace(OLD_CLASSIFIER, NEW_CLASSIFIER)
print("  ~ intentclassificatie: verduidelijkt dat administratie e.d. een echt document vereist")

# --- 4. slaFinancieelDocumentOp: bij is_document=false geen nepdocument opslaan, wel als notitie bewaren ---
OLD_GUARD = (
    "  const analyse = await verwerkFinancieelDocument(content);\n"
    "  const bijlageLink = linkBijlage(dir, bijlagePad);"
)
if js.count(OLD_GUARD) != 1:
    raise SystemExit("Verwachte regels in slaFinancieelDocumentOp niet exact 1x gevonden -- afgebroken zonder iets te wijzigen.")
NEW_GUARD = (
    "  const analyse = await verwerkFinancieelDocument(content);\n"
    "  if (analyse.is_document === false) {\n"
    "    const notitieDir = path.join(KENNISBANK_WIKI, 'persoonlijk', 'notities');\n"
    "    if (!fs.existsSync(notitieDir)) fs.mkdirSync(notitieDir, { recursive: true });\n"
    "    const preview = await genereerKorteTitel(content);\n"
    "    const bijlageLink = linkBijlage(notitieDir, bijlagePad);\n"
    "    const fmLines = ['---', 'tags:', '  - notitie', '  - ' + source, 'datum: ' + timestamp, 'bron: ' + source];\n"
    "    if (bijlageLink) fmLines.push('bijlage: ' + bijlageLink);\n"
    "    fmLines.push('---');\n"
    "    const bodyDelen = ['# ' + (preview || 'Notitie'), ''];\n"
    "    if (bijlageLink) bodyDelen.push('[Bekijk origineel](' + bijlageLink + ')', '');\n"
    "    bodyDelen.push(content);\n"
    "    const filename = fileTs + '-notitie.md';\n"
    "    fs.writeFileSync(path.join(notitieDir, filename), fmLines.join('\\n') + '\\n\\n' + bodyDelen.join('\\n') + '\\n', 'utf8');\n"
    "    linkInCategorie('persoonlijk.md', 'Persoonlijk', preview || 'Notitie', 'persoonlijk/notities/' + filename);\n"
    "    return 'Dit herkende ik niet als factuur/bon/document (was als ' + label + ' geclassificeerd) -- ik heb niets verzonnen en het in plaats daarvan als gewone notitie opgeslagen: \"' + (preview || 'Notitie') + '\". Bedoelde je iets anders? Typ het juiste commando, bv. /taken of /notitie.';\n"
    "  }\n"
    "  const bijlageLink = linkBijlage(dir, bijlagePad);"
)
js = js.replace(OLD_GUARD, NEW_GUARD)
print("  ~ slaFinancieelDocumentOp: vangnet toegevoegd voor is_document=false (notitie i.p.v. nepdocument)")

handler['parameters']['jsCode'] = js

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF_INNER

echo "==> Importeren..."
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all

echo "==> Foutieve nepfactuur 'Bakkerij De Gouden Brood' opruimen (als die er nog staat)..."
KENNISBANK_WIKI="${KENNISBANK_WIKI}" python3 - <<'PYEOF_CLEANUP'
import os, re

wiki = os.environ['KENNISBANK_WIKI']
admin_dir = os.path.join(wiki, 'persoonlijk', 'administratie')

treffers = []
if os.path.isdir(admin_dir):
    for naam in os.listdir(admin_dir):
        pad = os.path.join(admin_dir, naam)
        if not naam.endswith('.md'):
            continue
        try:
            inhoud = open(pad, encoding='utf-8').read()
        except OSError:
            continue
        if 'Bakkerij De Gouden Brood' in inhoud and 'FB-2024-0315-001' in inhoud:
            treffers.append((naam, pad))

if len(treffers) == 0:
    print("  Geen bestand met 'Bakkerij De Gouden Brood' / 'FB-2024-0315-001' gevonden -- niets te verwijderen (mogelijk al opgeruimd).")
elif len(treffers) > 1:
    print(f"  WAARSCHUWING: {len(treffers)} bestanden komen overeen, niet automatisch verwijderd uit voorzichtigheid:")
    for naam, _ in treffers:
        print(f"    - {naam}")
else:
    naam, pad = treffers[0]
    os.remove(pad)
    print(f"  Verwijderd: {pad}")

    index_pad = os.path.join(wiki, 'persoonlijk.md')
    rel_pad = 'persoonlijk/administratie/' + naam
    if os.path.exists(index_pad):
        regels = open(index_pad, encoding='utf-8').read().split('\n')
        nieuwe_regels = [r for r in regels if rel_pad not in r]
        if len(nieuwe_regels) != len(regels):
            with open(index_pad, 'w', encoding='utf-8') as f:
                f.write('\n'.join(nieuwe_regels))
            print(f"  Koppeling naar '{rel_pad}' verwijderd uit {index_pad}")
        else:
            print(f"  Geen koppeling naar '{rel_pad}' gevonden in {index_pad} (niets te verwijderen daar)")
PYEOF_CLEANUP

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
echo "Test (stuur dit als gewone tekst, zonder commando, via de wiki-chat of CLI-webhook):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"koppel mijn account aan X"}'"'"''
echo ""
echo "Verwacht: GEEN nepfactuur meer, maar een antwoord dat het als gewone notitie is"
echo "opgeslagen omdat het geen factuur/document is."
echo ""
echo "Let op: dit lost niet de oorspronkelijke Gmail-koppeling op -- dat kan alleen via"
echo "de n8n-webinterface (OAuth2), zie docs/angie/TODO.md."
