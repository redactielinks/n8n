#!/bin/bash
# ============================================================
# Project Angie — Periode tonen bij herhalende/periodieke facturen
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# "ik wil bij herhaling facturen ook graag in de beschrijving zien voor
# welke periode de factuur is": de fiscale/boekhoudkundige analyse
# (verwerkFinancieelDocument) haalde nog geen factureringsperiode uit de
# tekst. Voor herhalende facturen (abonnement, verzekeringspremie, energie,
# huur e.d.) staat die periode er vaak wel in (bv. "januari 2026" of
# "01-01-2026 t/m 31-01-2026") -- nu wordt die meegenomen in:
#  - de frontmatter van de wiki-pagina (factuurperiode: ...)
#  - de "Samenvatting"-sectie op de pagina (- Periode: ...)
#  - het directe antwoord na opslaan ("... Periode: januari 2026.")
# Voor eenmalige/niet-periodieke documenten blijft het veld leeg en
# verandert er niets aan de tekst.
#
# Vereist dat patch-fiscaal-particulier-en-llm-retry.sh al is uitgevoerd
# (anders bestaat de PARTICULIER-zonder-bedrijf-prompt nog niet om uit te
# breiden).
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers:
#   rm -f patch-factuurperiode.sh
#   curl -fsSL -o patch-factuurperiode.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-factuurperiode.sh?t=$(date +%s)"
#   bash patch-factuurperiode.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-19-factuurperiode-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
KENNISBANK_DIR="/home/redactielinks/kennisbank"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF_INNER'
import json

OLD_DEFAULTS = "  const defaults = {\n    leverancier: '', factuurdatum: '', factuurnummer: '',\n    bedrag_excl_btw: '', btw_percentage: '', btw_bedrag: '', bedrag_incl_btw: '',\n    categorie_fiscaal: '', aftrekbaar: 'onbekend', titel_kort: '',\n    tip: 'Geen tip gegenereerd -- controleer zelf het bedrag en de btw.',\n  };"
NEW_DEFAULTS = "  const defaults = {\n    leverancier: '', factuurdatum: '', factuurnummer: '', factuurperiode: '',\n    bedrag_excl_btw: '', btw_percentage: '', btw_bedrag: '', bedrag_incl_btw: '',\n    categorie_fiscaal: '', aftrekbaar: 'onbekend', titel_kort: '',\n    tip: 'Geen tip gegenereerd -- controleer zelf het bedrag en de btw.',\n  };"
OLD_JSON_LINE = '          content: \'Je bent een Nederlandse administratief en fiscaal assistent voor een PARTICULIER ZONDER eigen bedrijf of onderneming -- geen zzp\\\'er, geen btw-aangifte, geen ondernemersaftrek. Je krijgt de tekst van een factuur, bon, ticket of ander document. Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel_kort":"korte titel van max 8 woorden die samenvat waar dit document over gaat, bv. \\\'Vliegticket KLM Amsterdam-Londen\\\' of \\\'Garantiebewijs wasmachine Bosch\\\', in het Nederlands","leverancier":"naam leverancier/winkel/maatschappij, of leeg","factuurdatum":"YYYY-MM-DD indien herkenbaar, anders de datum zoals vermeld, of leeg","factuurnummer":"factuur-, bon- of ticketnummer, of leeg","bedrag_excl_btw":"bedrag exclusief btw als getal met punt, of leeg","btw_percentage":"21|9|0|onbekend","btw_bedrag":"btw-bedrag als getal met punt, of leeg","bedrag_incl_btw":"totaalbedrag inclusief btw als getal met punt, of leeg","categorie_fiscaal":"korte categorie voor de persoonlijke administratie, bv. Zorg, Wonen, Vervoer, Verzekering, Aankoop, Abonnement, Overig -- GEEN zakelijke/ondernemerscategorieen zoals Kantoorkosten of Representatiekosten, deze persoon heeft geen bedrijf","aftrekbaar":"ja|nee|deels|onbekend -- vanuit het Nederlandse inkomstenbelasting-perspectief van een PARTICULIER zonder bedrijf: bijna altijd \\\'nee\\\', want gewone uitgaven/verzekeringen/aankopen zijn voor particulieren niet aftrekbaar; gebruik \\\'ja\\\'/\\\'deels\\\' alleen bij een van de specifieke wettelijke persoonlijke aftrekposten (giften aan een ANBI, hypotheekrente eigen woning, specifieke zorgkosten boven de drempel die niet vergoed worden, e.d.) -- stel nooit zakelijke kostenaftrek voor, want deze persoon heeft geen onderneming","tip":"1-2 zinnen praktisch en proactief advies specifiek voor dit document vanuit het perspectief van een particulier zonder bedrijf (bv. bewaartermijn, garantietermijn, een eventuele persoonlijke aftrekpost zoals een gift of zorgkosten) -- stel nooit een zakelijke/btw-aftrek voor, en herhaal geen algemeen advies dat al vaststaat in de pagina"}\''
NEW_JSON_LINE = '          content: \'Je bent een Nederlandse administratief en fiscaal assistent voor een PARTICULIER ZONDER eigen bedrijf of onderneming -- geen zzp\\\'er, geen btw-aangifte, geen ondernemersaftrek. Je krijgt de tekst van een factuur, bon, ticket of ander document. Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel_kort":"korte titel van max 8 woorden die samenvat waar dit document over gaat, bv. \\\'Vliegticket KLM Amsterdam-Londen\\\' of \\\'Garantiebewijs wasmachine Bosch\\\', in het Nederlands","leverancier":"naam leverancier/winkel/maatschappij, of leeg","factuurdatum":"YYYY-MM-DD indien herkenbaar, anders de datum zoals vermeld, of leeg","factuurnummer":"factuur-, bon- of ticketnummer, of leeg","factuurperiode":"alleen invullen bij een HERHALENDE/PERIODIEKE factuur (abonnement, verzekeringspremie, energie, huur e.d.): de periode die deze factuur dekt, bv. \\\'januari 2026\\\' of \\\'01-01-2026 t/m 31-01-2026\\\' -- anders leeg","bedrag_excl_btw":"bedrag exclusief btw als getal met punt, of leeg","btw_percentage":"21|9|0|onbekend","btw_bedrag":"btw-bedrag als getal met punt, of leeg","bedrag_incl_btw":"totaalbedrag inclusief btw als getal met punt, of leeg","categorie_fiscaal":"korte categorie voor de persoonlijke administratie, bv. Zorg, Wonen, Vervoer, Verzekering, Aankoop, Abonnement, Overig -- GEEN zakelijke/ondernemerscategorieen zoals Kantoorkosten of Representatiekosten, deze persoon heeft geen bedrijf","aftrekbaar":"ja|nee|deels|onbekend -- vanuit het Nederlandse inkomstenbelasting-perspectief van een PARTICULIER zonder bedrijf: bijna altijd \\\'nee\\\', want gewone uitgaven/verzekeringen/aankopen zijn voor particulieren niet aftrekbaar; gebruik \\\'ja\\\'/\\\'deels\\\' alleen bij een van de specifieke wettelijke persoonlijke aftrekposten (giften aan een ANBI, hypotheekrente eigen woning, specifieke zorgkosten boven de drempel die niet vergoed worden, e.d.) -- stel nooit zakelijke kostenaftrek voor, want deze persoon heeft geen onderneming","tip":"1-2 zinnen praktisch en proactief advies specifiek voor dit document vanuit het perspectief van een particulier zonder bedrijf (bv. bewaartermijn, garantietermijn, een eventuele persoonlijke aftrekpost zoals een gift of zorgkosten) -- stel nooit een zakelijke/btw-aftrek voor, en herhaal geen algemeen advies dat al vaststaat in de pagina"}\''
OLD_FM = "  if (analyse.factuurdatum) fmLines.push('factuurdatum: ' + analyse.factuurdatum);\n  if (analyse.factuurnummer) fmLines.push('factuurnummer: ' + analyse.factuurnummer);"
NEW_FM = "  if (analyse.factuurdatum) fmLines.push('factuurdatum: ' + analyse.factuurdatum);\n  if (analyse.factuurnummer) fmLines.push('factuurnummer: ' + analyse.factuurnummer);\n  if (analyse.factuurperiode) fmLines.push('factuurperiode: ' + analyse.factuurperiode);"
OLD_SAMENVATTING = "    analyse.factuurdatum ? '- Datum: ' + analyse.factuurdatum : '',\n    analyse.factuurnummer ? '- Nummer: ' + analyse.factuurnummer : '',"
NEW_SAMENVATTING = "    analyse.factuurdatum ? '- Datum: ' + analyse.factuurdatum : '',\n    analyse.factuurnummer ? '- Nummer: ' + analyse.factuurnummer : '',\n    analyse.factuurperiode ? '- Periode: ' + analyse.factuurperiode : '',"
OLD_REPLY = "  if (analyse.bedrag_incl_btw) reply += ' (' + analyse.bedrag_incl_btw + ')';\n  reply += '.';\n  if (analyse.aftrekbaar && analyse.aftrekbaar !== 'onbekend') reply += ' Vermoedelijk aftrekbaar: ' + analyse.aftrekbaar + '.';"
NEW_REPLY = "  if (analyse.bedrag_incl_btw) reply += ' (' + analyse.bedrag_incl_btw + ')';\n  reply += '.';\n  if (analyse.factuurperiode) reply += ' Periode: ' + analyse.factuurperiode + '.';\n  if (analyse.aftrekbaar && analyse.aftrekbaar !== 'onbekend') reply += ' Vermoedelijk aftrekbaar: ' + analyse.aftrekbaar + '.';"

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
if 'PARTICULIER ZONDER eigen bedrijf' not in js:
    raise SystemExit("Verwachte 'PARTICULIER ZONDER eigen bedrijf'-prompt niet gevonden -- patch-fiscaal-particulier-en-llm-retry.sh moet eerst uitgevoerd zijn, patch afgebroken.")
if 'factuurperiode' in js:
    raise SystemExit("Deze patch lijkt al uitgevoerd te zijn ('factuurperiode' staat er al in) -- niet opnieuw uitvoeren.")

vervangingen = [
    ("defaults-object", OLD_DEFAULTS, NEW_DEFAULTS),
    ("JSON-schema (LLM-prompt)", OLD_JSON_LINE, NEW_JSON_LINE),
    ("frontmatter", OLD_FM, NEW_FM),
    ("samenvatting-regels", OLD_SAMENVATTING, NEW_SAMENVATTING),
    ("antwoordtekst", OLD_REPLY, NEW_REPLY),
]
for naam, oud, nieuw in vervangingen:
    aantal = js.count(oud)
    if aantal != 1:
        raise SystemExit(f"Verwachte {naam}-regel(s) {aantal}x gevonden in plaats van 1x -- niet veilig om automatisch te patchen. Patch afgebroken zonder iets te wijzigen.")
    js = js.replace(oud, nieuw)
    print(f"  ~ {naam}: factuurperiode toegevoegd")

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
echo "Test (factuur met een herkenbare periode):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"Factuur van Energiedirect\nFactuurnummer: E2026-998\nPeriode: januari 2026\nBTW 21%: 8.68\nTotaalbedrag: 50.00"}'"'"''
echo "Verwacht: '... Periode: januari 2026.' in het antwoord, en een regel"
echo "'- Periode: januari 2026' onder Samenvatting op de wiki-pagina."
