#!/bin/bash
# ============================================================
# Project Angie — LLM-aanroepen in de wiki-commando-node naar OpenRouter
# (Mac Mini LM Studio draait niet meer)
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# "we zijn immers gestopt met de lokale llm op de mac mini": alle
# LLM-aanroepen binnen de "Verwerk Wiki Commando"-node (intentclassificatie,
# verwerkFinancieelDocument, genereerKorteTitel, recept-/idee-verwerking,
# etc.) gingen naar http://100.68.46.126:27124 (LM Studio op de Mac Mini).
# Die server draait niet meer, dus elke analyse faalt nu met "LLM niet
# bereikbaar of timeout" -- precies wat je in de screenshots zag.
#
# Fix: alle 8 LLM-aanroepen in deze node gaan voortaan naar OpenRouter,
# via de al bestaande OpenRouter-credential (oITPdZPojDOLJaCJ, dezelfde die
# de hoofdagent gebruikt sinds patch-secretaresse-llm-naar-hermes.sh).
# Model: nousresearch/hermes-4-70b (zelfde als de hoofdagent nu gebruikt --
# pas dit aan met een ander modelnaam als argument, bv.:
#   bash patch-llm-calls-naar-openrouter.sh "mistralai/mistral-large-2512"
#
# De OpenRouter API-key wordt lokaal op de Pi ontsleuteld via
# `n8n export:credentials --decrypted` en alleen in de workflow-jsCode
# gezet -- de key komt nooit in git terecht en wordt nergens geprint.
#
# Vereist dat patch-facturen-bijlagen-en-fiscale-tips.sh (of
# patch-rubrieken-en-llm-titels.sh) al is uitgevoerd.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers:
#   rm -f patch-llm-calls-naar-openrouter.sh
#   curl -fsSL -o patch-llm-calls-naar-openrouter.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-llm-calls-naar-openrouter.sh?t=$(date +%s)"
#   bash patch-llm-calls-naar-openrouter.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-19-llm-calls-naar-openrouter-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
KENNISBANK_DIR="/home/redactielinks/kennisbank"
MODEL_NAME="${1:-nousresearch/hermes-4-70b}"
CRED_ID="oITPdZPojDOLJaCJ"
CRED_NAME="OpenRouter account"

echo "==> OpenRouter API-key lokaal ontsleutelen (komt nooit in git terecht)..."
docker exec n8n n8n export:credentials --all --decrypted --output=/tmp/creds-decrypted.json 2>/dev/null
docker cp n8n:/tmp/creds-decrypted.json /tmp/creds-decrypted.json
docker exec n8n rm -f /tmp/creds-decrypted.json
OPENROUTER_API_KEY=$(python3 -c "
import json
with open('/tmp/creds-decrypted.json', encoding='utf-8') as f:
    creds = json.load(f)
cred = next((c for c in creds if c.get('id') == '${CRED_ID}' or c.get('name') == '${CRED_NAME}'), None)
if cred is None:
    raise SystemExit('OpenRouter-credential niet gevonden -- patch afgebroken.')
print(cred['data']['apiKey'])
")
rm -f /tmp/creds-decrypted.json
if [ -z "$OPENROUTER_API_KEY" ]; then
  echo "FOUT: geen API-key ontsleuteld, patch afgebroken." >&2
  exit 1
fi

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
OPENROUTER_API_KEY="$OPENROUTER_API_KEY" MODEL_NAME="$MODEL_NAME" python3 - <<'PYEOF_INNER'
import json, os

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
if 'openrouter.ai' in js:
    raise SystemExit("Deze patch lijkt al uitgevoerd te zijn ('openrouter.ai' staat er al in) -- niet opnieuw uitvoeren. Gebruik het scriptargument om alleen het model te wijzigen, bv.: bash patch-llm-calls-naar-openrouter.sh \"ander/model\"")

OUD_LLM_URL = "const LLM_URL = 'http://100.68.46.126:27124/v1/chat/completions';"
if js.count(OUD_LLM_URL) != 1:
    raise SystemExit(f"Verwachte LLM_URL-regel {js.count(OUD_LLM_URL)}x gevonden in plaats van 1x -- niet veilig om automatisch te patchen. Patch afgebroken zonder iets te wijzigen.")

api_key = os.environ['OPENROUTER_API_KEY']
model_name = os.environ['MODEL_NAME']
NIEUW_LLM_URL = (
    "const LLM_URL = 'https://openrouter.ai/api/v1/chat/completions';\n"
    f"const LLM_MODEL = {model_name!r};\n"
    f"const LLM_API_KEY = {api_key!r};"
)
js = js.replace(OUD_LLM_URL, NIEUW_LLM_URL)
print("  ~ LLM_URL: Mac Mini (LM Studio) -> OpenRouter")

OUD_HEADERS = "headers: { 'Content-Type': 'application/json' },"
aantal_headers = js.count(OUD_HEADERS)
if aantal_headers == 0:
    raise SystemExit("Verwachte headers-regel niet gevonden -- structuur is gewijzigd, patch afgebroken zonder iets te wijzigen.")
NIEUWE_HEADERS = "headers: { 'Content-Type': 'application/json', 'Authorization': 'Bearer ' + LLM_API_KEY },"
js = js.replace(OUD_HEADERS, NIEUWE_HEADERS)
print(f"  ~ Authorization-header toegevoegd aan {aantal_headers} LLM-aanroep(en)")

OUD_MODEL = "model: 'google/gemma-3-4b',"
aantal_model = js.count(OUD_MODEL)
if aantal_model == 0:
    raise SystemExit("Verwachte model-regel niet gevonden -- structuur is gewijzigd, patch afgebroken zonder iets te wijzigen.")
NIEUW_MODEL = "model: LLM_MODEL,"
js = js.replace(OUD_MODEL, NIEUW_MODEL)
print(f"  ~ model vervangen door LLM_MODEL ({model_name}) in {aantal_model} aanroep(en)")

handler['parameters']['jsCode'] = js

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF_INNER
unset OPENROUTER_API_KEY

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
echo "Test (factuurtekst zonder /commando -- moet nu een ECHTE analyse"
echo "teruggeven, geen 'LLM niet bereikbaar of timeout' meer):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"Factuur van Bol.com\nFactuurnummer: F2026-001234\nBTW 21%: 8.68\nTotaalbedrag: 50.00"}'"'"''
echo "Verwacht: 'Administratie opgeslagen: Bol.com (50.00).' met een"
echo "inhoudelijke tip, NIET de standaardtekst over LLM niet bereikbaar."
