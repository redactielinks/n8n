#!/bin/bash
# ============================================================
# Project Angie — Fiscaal advies corrigeren (geen eigen bedrijf) + LLM-retry
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Twee bugs in een:
#
# 1. Het fiscale prompt in "Verwerk Wiki Commando" ging ten onrechte uit van
#    een "zelfstandig ondernemer/particulier" en beoordeelde aftrekbaarheid
#    "vanuit het perspectief van een zelfstandig ondernemer met gemengd
#    zakelijk/prive gebruik". Resultaat: een gewone particuliere
#    verzekeringspolis kreeg het advies "vermoedelijk aftrekbaar: ja...
#    waarschijnlijk aftrekbaar als zakelijke verzekering" -- maar er is
#    helemaal geen bedrijf, dus zakelijke kostenaftrek bestaat niet voor
#    deze persoon. Het prompt gaat nu uit van een PARTICULIER zonder eigen
#    bedrijf/onderneming en mag alleen nog wijzen op de specifieke
#    wettelijke persoonlijke aftrekposten (giften aan een ANBI,
#    hypotheekrente, niet-vergoede zorgkosten boven de drempel) -- nooit
#    meer zakelijke/btw-aftrek voorstellen.
#
# 2. Bij "het werkt nog steeds niet" (twee van de drie documenten kregen nog
#    de generieke tip "LLM niet bereikbaar of timeout") kon de echte oorzaak
#    niet gezien worden: de catch-blokken verborgen de werkelijke
#    foutmelding (bv. een tijdelijke HTTP 429 rate limit van OpenRouter bij
#    meerdere documenten kort na elkaar). Nu: (a) één keer automatisch
#    opnieuw proberen na 2 seconden bij een mislukte aanroep, en (b) als het
#    dan nog mislukt, staat de echte foutmelding (bv. "HTTP 429: ...") in de
#    tip, zodat een volgende melding wel te diagnosticeren is zonder
#    Pi-toegang.
#
# Vereist dat patch-llm-calls-naar-openrouter.sh al is uitgevoerd.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers:
#   rm -f patch-fiscaal-particulier-en-llm-retry.sh
#   curl -fsSL -o patch-fiscaal-particulier-en-llm-retry.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-fiscaal-particulier-en-llm-retry.sh?t=$(date +%s)"
#   bash patch-fiscaal-particulier-en-llm-retry.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-19-fiscaal-particulier-en-llm-retry-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"

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
if 'openrouter.ai' not in js:
    raise SystemExit("'openrouter.ai' niet gevonden -- patch-llm-calls-naar-openrouter.sh moet eerst uitgevoerd zijn, patch afgebroken.")
if 'async function metRetry' in js:
    raise SystemExit("Deze patch lijkt al uitgevoerd te zijn ('metRetry' staat er al in) -- niet opnieuw uitvoeren.")

OLD_GENEREER = '// De eerste tekstregel van een document (aanhef van een brief, kopregel van\n// een bon) beschrijft zelden waar het document over gaat -- vandaar een\n// echte LLM-samenvatting in plaats van kaal afkappen. Kort en met een eigen\n// (kleinere) timeout, want dit mag niet de hele opslag laten mislukken.\nasync function genereerKorteTitel(content) {\n  const fallback = cleanPreview(content).substring(0, 60);\n  try {\n    const llmData = await httpRequest({\n      method: \'POST\', url: LLM_URL,\n      headers: { \'Content-Type\': \'application/json\', \'Authorization\': \'Bearer \' + LLM_API_KEY },\n      body: {\n        model: LLM_MODEL,\n        messages: [{\n          role: \'system\',\n          content: \'Geef een korte titel (max 8 woorden) die samenvat waar de tekst van de gebruiker over gaat. Antwoord met alleen de titel zelf, in het Nederlands, zonder aanhalingstekens, zonder opmaak, zonder uitleg.\'\n        }, { role: \'user\', content: content.substring(0, 2000) }],\n        stream: false, temperature: 0.2,\n      },\n      json: true, timeout: 20000,\n    });\n    const titel = (llmData?.choices?.[0]?.message?.content || \'\').replace(/^["\'`]+|["\'`]+$/g, \'\').trim();\n    return titel ? cleanPreview(titel).substring(0, 70) : fallback;\n  } catch (e) {\n    return fallback;\n  }\n}\n\n'
if js.count(OLD_GENEREER) != 1:
    raise SystemExit(f"Verwachte genereerKorteTitel-functie {js.count(OLD_GENEREER)}x gevonden in plaats van 1x -- niet veilig om automatisch te patchen. Patch afgebroken zonder iets te wijzigen.")
NEW_GENEREER = '// OpenRouter (gedeelde/gratis modellen) geeft onder belasting soms een\n// tijdelijke 429/5xx terug -- vooral bij meerdere documenten kort na elkaar\n// (titel + classificatie + analyse per document). Eén keer opnieuw proberen\n// na een korte pauze voorkomt dat zo\'n kortstondige hapering een hele\n// analyse laat mislukken.\nasync function metRetry(fn, pogingen = 2, wachtMs = 2000) {\n  let laatsteFout;\n  for (let i = 0; i < pogingen; i++) {\n    try { return await fn(); }\n    catch (e) {\n      laatsteFout = e;\n      if (i < pogingen - 1) await new Promise(r => setTimeout(r, wachtMs));\n    }\n  }\n  throw laatsteFout;\n}\n\n// De eerste tekstregel van een document (aanhef van een brief, kopregel van\n// een bon) beschrijft zelden waar het document over gaat -- vandaar een\n// echte LLM-samenvatting in plaats van kaal afkappen. Kort en met een eigen\n// (kleinere) timeout, want dit mag niet de hele opslag laten mislukken.\nasync function genereerKorteTitel(content) {\n  const fallback = cleanPreview(content).substring(0, 60);\n  try {\n    const llmData = await metRetry(() => httpRequest({\n      method: \'POST\', url: LLM_URL,\n      headers: { \'Content-Type\': \'application/json\', \'Authorization\': \'Bearer \' + LLM_API_KEY },\n      body: {\n        model: LLM_MODEL,\n        messages: [{\n          role: \'system\',\n          content: \'Geef een korte titel (max 8 woorden) die samenvat waar de tekst van de gebruiker over gaat. Antwoord met alleen de titel zelf, in het Nederlands, zonder aanhalingstekens, zonder opmaak, zonder uitleg.\'\n        }, { role: \'user\', content: content.substring(0, 2000) }],\n        stream: false, temperature: 0.2,\n      },\n      json: true, timeout: 20000,\n    }));\n    const titel = (llmData?.choices?.[0]?.message?.content || \'\').replace(/^["\'`]+|["\'`]+$/g, \'\').trim();\n    return titel ? cleanPreview(titel).substring(0, 70) : fallback;\n  } catch (e) {\n    return fallback;\n  }\n}\n\n'
js = js.replace(OLD_GENEREER, NEW_GENEREER)
print("  ~ genereerKorteTitel: metRetry toegevoegd (1x opnieuw proberen bij tijdelijke 429/5xx)")

OLD_VERWERK = 'async function verwerkFinancieelDocument(content) {\n  const defaults = {\n    leverancier: \'\', factuurdatum: \'\', factuurnummer: \'\',\n    bedrag_excl_btw: \'\', btw_percentage: \'\', btw_bedrag: \'\', bedrag_incl_btw: \'\',\n    categorie_fiscaal: \'\', aftrekbaar: \'onbekend\', titel_kort: \'\',\n    tip: \'Kon niet automatisch geanalyseerd worden (LLM niet bereikbaar of timeout) -- controleer zelf het bedrag en de btw.\',\n  };\n  try {\n    const llmData = await httpRequest({\n      method: \'POST\', url: LLM_URL,\n      headers: { \'Content-Type\': \'application/json\', \'Authorization\': \'Bearer \' + LLM_API_KEY },\n      body: {\n        model: LLM_MODEL,\n        messages: [{\n          role: \'system\',\n          // "titel_kort" is bewust apart van "leverancier": zonder herkende\n          // leverancier (bv. bij tickets/garantiebewijzen) was de titel\n          // voorheen alleen het kale rubrieklabel of een afgekapte ruwe\n          // tekstregel -- geen van beide beschrijft waar het document\n          // werkelijk over gaat.\n          content: \'Je bent een Nederlandse boekhoudkundig en fiscaal assistent voor een zelfstandig ondernemer/particulier. Je krijgt de tekst van een factuur, bon, ticket of ander document. Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel_kort":"korte titel van max 8 woorden die samenvat waar dit document over gaat, bv. \\\'Vliegticket KLM Amsterdam-Londen\\\' of \\\'Garantiebewijs wasmachine Bosch\\\', in het Nederlands","leverancier":"naam leverancier/winkel/maatschappij, of leeg","factuurdatum":"YYYY-MM-DD indien herkenbaar, anders de datum zoals vermeld, of leeg","factuurnummer":"factuur-, bon- of ticketnummer, of leeg","bedrag_excl_btw":"bedrag exclusief btw als getal met punt, of leeg","btw_percentage":"21|9|0|onbekend","btw_bedrag":"btw-bedrag als getal met punt, of leeg","bedrag_incl_btw":"totaalbedrag inclusief btw als getal met punt, of leeg","categorie_fiscaal":"korte kostencategorie, bv. Kantoorkosten, Reiskosten, Representatiekosten, ICT, Vakliteratuur, Verzekering, Aankoop, Overig","aftrekbaar":"ja|nee|deels|onbekend, vanuit het perspectief van een zelfstandig ondernemer met gemengd zakelijk/prive gebruik","tip":"1-2 zinnen praktisch en proactief advies specifiek voor dit document (bv. btw-aftrek, zakelijk vs prive gebruik, garantietermijn, bewaartermijn) -- geen algemeen fiscaal advies herhalen, dat staat al vast in de pagina"}\'\n        }, { role: \'user\', content }],\n        stream: false, temperature: 0.2,\n      },\n      json: true, timeout: 60000,\n    });\n    const raw = llmData?.choices?.[0]?.message?.content || \'{}\';\n    const parsed = JSON.parse(raw.replace(/```json\\n?|\\n?```/g, \'\').trim());\n    return Object.assign({}, defaults, parsed);\n  } catch (e) {\n    return defaults;\n  }\n}\n'
if js.count(OLD_VERWERK) != 1:
    raise SystemExit(f"Verwachte verwerkFinancieelDocument-functie {js.count(OLD_VERWERK)}x gevonden in plaats van 1x -- niet veilig om automatisch te patchen. Patch afgebroken zonder iets te wijzigen.")
NEW_VERWERK = 'async function verwerkFinancieelDocument(content) {\n  const defaults = {\n    leverancier: \'\', factuurdatum: \'\', factuurnummer: \'\',\n    bedrag_excl_btw: \'\', btw_percentage: \'\', btw_bedrag: \'\', bedrag_incl_btw: \'\',\n    categorie_fiscaal: \'\', aftrekbaar: \'onbekend\', titel_kort: \'\',\n    tip: \'Geen tip gegenereerd -- controleer zelf het bedrag en de btw.\',\n  };\n  try {\n    const llmData = await metRetry(() => httpRequest({\n      method: \'POST\', url: LLM_URL,\n      headers: { \'Content-Type\': \'application/json\', \'Authorization\': \'Bearer \' + LLM_API_KEY },\n      body: {\n        model: LLM_MODEL,\n        messages: [{\n          role: \'system\',\n          // "titel_kort" is bewust apart van "leverancier": zonder herkende\n          // leverancier (bv. bij tickets/garantiebewijzen) was de titel\n          // voorheen alleen het kale rubrieklabel of een afgekapte ruwe\n          // tekstregel -- geen van beide beschrijft waar het document\n          // werkelijk over gaat.\n          // Deze persoon heeft GEEN eigen bedrijf/onderneming -- het\n          // fiscale advies mag dus nooit uitgaan van zakelijke kostenaftrek\n          // (dat leverde eerder ten onrechte "vermoedelijk zakelijk\n          // aftrekbaar" op voor een gewone particuliere verzekeringspolis).\n          content: \'Je bent een Nederlandse administratief en fiscaal assistent voor een PARTICULIER ZONDER eigen bedrijf of onderneming -- geen zzp\\\'er, geen btw-aangifte, geen ondernemersaftrek. Je krijgt de tekst van een factuur, bon, ticket of ander document. Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel_kort":"korte titel van max 8 woorden die samenvat waar dit document over gaat, bv. \\\'Vliegticket KLM Amsterdam-Londen\\\' of \\\'Garantiebewijs wasmachine Bosch\\\', in het Nederlands","leverancier":"naam leverancier/winkel/maatschappij, of leeg","factuurdatum":"YYYY-MM-DD indien herkenbaar, anders de datum zoals vermeld, of leeg","factuurnummer":"factuur-, bon- of ticketnummer, of leeg","bedrag_excl_btw":"bedrag exclusief btw als getal met punt, of leeg","btw_percentage":"21|9|0|onbekend","btw_bedrag":"btw-bedrag als getal met punt, of leeg","bedrag_incl_btw":"totaalbedrag inclusief btw als getal met punt, of leeg","categorie_fiscaal":"korte categorie voor de persoonlijke administratie, bv. Zorg, Wonen, Vervoer, Verzekering, Aankoop, Abonnement, Overig -- GEEN zakelijke/ondernemerscategorieen zoals Kantoorkosten of Representatiekosten, deze persoon heeft geen bedrijf","aftrekbaar":"ja|nee|deels|onbekend -- vanuit het Nederlandse inkomstenbelasting-perspectief van een PARTICULIER zonder bedrijf: bijna altijd \\\'nee\\\', want gewone uitgaven/verzekeringen/aankopen zijn voor particulieren niet aftrekbaar; gebruik \\\'ja\\\'/\\\'deels\\\' alleen bij een van de specifieke wettelijke persoonlijke aftrekposten (giften aan een ANBI, hypotheekrente eigen woning, specifieke zorgkosten boven de drempel die niet vergoed worden, e.d.) -- stel nooit zakelijke kostenaftrek voor, want deze persoon heeft geen onderneming","tip":"1-2 zinnen praktisch en proactief advies specifiek voor dit document vanuit het perspectief van een particulier zonder bedrijf (bv. bewaartermijn, garantietermijn, een eventuele persoonlijke aftrekpost zoals een gift of zorgkosten) -- stel nooit een zakelijke/btw-aftrek voor, en herhaal geen algemeen advies dat al vaststaat in de pagina"}\'\n        }, { role: \'user\', content }],\n        stream: false, temperature: 0.2,\n      },\n      json: true, timeout: 60000,\n    }));\n    const raw = llmData?.choices?.[0]?.message?.content || \'{}\';\n    const parsed = JSON.parse(raw.replace(/```json\\n?|\\n?```/g, \'\').trim());\n    return Object.assign({}, defaults, parsed);\n  } catch (e) {\n    return Object.assign({}, defaults, {\n      tip: \'Kon niet automatisch geanalyseerd worden (\' + String(e && e.message || e).slice(0, 150) + \') -- controleer zelf het bedrag en de btw.\',\n    });\n  }\n}\n'
js = js.replace(OLD_VERWERK, NEW_VERWERK)
print("  ~ verwerkFinancieelDocument: fiscaal advies nu vanuit particulier-zonder-bedrijf-perspectief (was ten onrechte 'zelfstandig ondernemer'), metRetry toegevoegd, echte foutoorzaak nu zichtbaar in de tip bij mislukking")

handler['parameters']['jsCode'] = js

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF_INNER

echo "==> Importeren..."
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all

echo "==> Activeren en n8n herstarten..."
ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
ENC_KEY=$(python3 -c "import json; print(json.load(open('${CONFIG}'))['encryptionKey'])")
docker stop n8n 2>/dev/null || true
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1, activeVersionId='${ACTIVE_VID}' WHERE id='${WF_ID}';"
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker rm n8n 2>/dev/null || true
docker run -d --name n8n --restart always -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -v /home/redactielinks/kennisbank:/home/redactielinks/kennisbank \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e N8N_ENCRYPTION_KEY="${ENC_KEY}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path,http,https,url \
    n8nio/n8n:latest
unset ENC_KEY
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 3
echo ""
echo "Test (een particuliere verzekeringspolis mag NOOIT meer \"zakelijk"
echo "aftrekbaar\" als advies krijgen):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"Polis Univé Stad en Land, premie 26,05 per maand, dekking inboedel."}'"'"''
echo "Verwacht: 'aftrekbaar: nee' (of een tip die wijst op een eventuele"
echo "persoonlijke aftrekpost), NIET 'waarschijnlijk aftrekbaar als"
echo "zakelijke verzekering'."
