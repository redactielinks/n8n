#!/bin/bash
# Alleen-lezen/test: meet rechtstreeks bij LM Studio op de Mac Mini hoe
# lang een antwoord duurt, met een KORTE systeem-instructie versus de
# ECHTE (lange) systeem-instructie van de Secretaresse-agent. Dit toont
# of de lange tool-catalogus/instructietekst de oorzaak is van de
# trage reactie (CPU moet die tekst bij elke vraag opnieuw verwerken),
# los van hoeveel redeneerstappen de n8n-agent zelf doet.
#
# Verandert niets aan n8n of LM Studio, stuurt alleen test-aanroepen.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
LM_STUDIO_URL="http://100.68.46.126:27124"
MODEL="google/gemma-3-4b"

echo "==> LM Studio extra modelinfo (indien beschikbaar, bv. quantisatie/context)..."
curl -s "${LM_STUDIO_URL}/api/v0/models" 2>/dev/null | python3 -m json.tool 2>/dev/null \
  || echo "(geen uitgebreide /api/v0/models info beschikbaar, geen probleem)"

echo ""
echo "==> Echte systeem-instructie van Secretaresse ophalen (voor een realistische test)..."
docker exec n8n n8n export:workflow --all --output=/tmp/diag_wf.json 2>/dev/null
docker cp n8n:/tmp/diag_wf.json /tmp/diag_wf.json
python3 - "$WF_ID" <<'PYEOF'
import json, sys
wf_id = sys.argv[1]
with open('/tmp/diag_wf.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == wf_id)
for n in wf['nodes']:
    if n['name'] == 'Secretaresse':
        sysmsg = n.get('parameters', {}).get('options', {}).get('systemMessage', '')
        # Expression-prefix '=' weghalen, dat is geen onderdeel van de tekst zelf
        if sysmsg.startswith('='):
            sysmsg = sysmsg[1:]
        with open('/tmp/sysmsg.json', 'w', encoding='utf-8') as out:
            json.dump(sysmsg, out)
PYEOF
echo "Lengte van de echte systeem-instructie: $(python3 -c "import json; print(len(json.load(open('/tmp/sysmsg.json'))))") tekens."

echo ""
echo "==> Test 1: KORTE systeem-instructie + 'hoe laat is het'..."
TMP1="/tmp/lmtest1.json"
python3 -c "
import json
print(json.dumps({
    'model': '${MODEL}',
    'messages': [
        {'role': 'system', 'content': 'Je bent een korte, behulpzame assistent.'},
        {'role': 'user', 'content': 'hoe laat is het'},
    ],
    'temperature': 0.3,
}))
" > "$TMP1"
time curl -s -w "\nTotale tijd: %{time_total}s\n" \
  -X POST "${LM_STUDIO_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d @"$TMP1" | python3 -c "
import sys, json
raw = sys.stdin.read()
lines = raw.rsplit('\n', 2)
try:
    resp = json.loads(lines[0])
    print('Antwoord:', resp['choices'][0]['message']['content'][:200])
    print('Tokens:', resp.get('usage'))
except Exception as e:
    print('(kon antwoord niet parsen)', e)
print('\n'.join(lines[1:]))
"

echo ""
echo "==> Test 2: ECHTE (lange) systeem-instructie + 'hoe laat is het'..."
TMP2="/tmp/lmtest2.json"
python3 -c "
import json
sysmsg = json.load(open('/tmp/sysmsg.json'))
print(json.dumps({
    'model': '${MODEL}',
    'messages': [
        {'role': 'system', 'content': sysmsg},
        {'role': 'user', 'content': 'hoe laat is het'},
    ],
    'temperature': 0.3,
}))
" > "$TMP2"
time curl -s -w "\nTotale tijd: %{time_total}s\n" \
  -X POST "${LM_STUDIO_URL}/v1/chat/completions" \
  -H "Content-Type: application/json" \
  -d @"$TMP2" | python3 -c "
import sys, json
raw = sys.stdin.read()
lines = raw.rsplit('\n', 2)
try:
    resp = json.loads(lines[0])
    print('Antwoord:', resp['choices'][0]['message']['content'][:200])
    print('Tokens:', resp.get('usage'))
except Exception as e:
    print('(kon antwoord niet parsen)', e)
print('\n'.join(lines[1:]))
"

rm -f "$TMP1" "$TMP2" /tmp/sysmsg.json /tmp/diag_wf.json
echo ""
echo "============================================================"
echo "  Vergelijk de 'Totale tijd' van test 1 en test 2."
echo "  Groot verschil -> de lange instructie is de bottleneck."
echo "  Klein verschil -> iets anders (bv. CPU-only inference,"
echo "  of meerdere redeneerstappen in de n8n-agent) is de oorzaak."
echo "============================================================"
