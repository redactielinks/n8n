#!/bin/bash
# Alleen-lezen: onderzoekt twee dingen na de overstap naar de lokale LLM
# (Mac Mini):
#   1) Hoe de Secretaresse-agent aan "de huidige tijd" komt (staat dat
#      expliciet in de systeem-instructie, of moet het model dat zelf
#      verzinnen?), en welke tools er beschikbaar zijn.
#   2) Hoe lang de laatste succesvolle uitvoering duurde en welke tools
#      daarbij daadwerkelijk zijn aangeroepen (bv. onnodig de agenda
#      raadplegen voor een simpele tijd-vraag kost extra seconden).
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Workflow exporteren (alleen-lezen)..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect3.json 2>/dev/null
docker cp n8n:/tmp/inspect3.json /tmp/inspect3.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect3.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')

print("=== Secretaresse: volledige systeem-instructie(s) ===")
for n in wf['nodes']:
    if n['name'] == 'Secretaresse':
        params = n.get('parameters', {})
        sysmsg_top = params.get('systemMessage')
        sysmsg_opt = params.get('options', {}).get('systemMessage')
        if sysmsg_top:
            print("--- parameters.systemMessage ---")
            print(sysmsg_top)
        if sysmsg_opt:
            print("--- parameters.options.systemMessage ---")
            print(sysmsg_opt)
        if not sysmsg_top and not sysmsg_opt:
            print("(geen systemMessage gevonden in parameters)")

print("\n=== Tools verbonden aan Secretaresse (ai_tool connectie) ===")
for src, outputs in wf.get('connections', {}).items():
    for conn_type, branches in outputs.items():
        if conn_type != 'ai_tool':
            continue
        for branch in branches:
            for conn in branch:
                if conn['node'] == 'Secretaresse':
                    print(f"  - {src}")

print("\n=== Zoek naar tijd/datum-gerelateerde nodes of expressies ===")
for n in wf['nodes']:
    blob = json.dumps(n.get('parameters', {}), ensure_ascii=False)
    if any(kw in blob for kw in ['$now', 'currentDate', 'DateTime', 'huidige tijd', 'huidige datum']) or \
       any(kw in n['name'].lower() for kw in ['tijd', 'datum', 'time', 'date']):
        print(f"  - node {n['name']!r} (type {n.get('type')}) bevat tijd/datum-referentie")
PYEOF

echo ""
echo "==> Laatste succesvolle uitvoering: duur en aangeroepen tools..."
LAST_OK=$(sqlite3 "$DB" "SELECT id FROM execution_entity WHERE workflowId='${WF_ID}' AND status='success' ORDER BY id DESC LIMIT 1;")
if [ -z "$LAST_OK" ]; then
  echo "Geen succesvolle uitvoering gevonden."
  exit 0
fi
echo "Execution ID: ${LAST_OK}"
sqlite3 -header -column "$DB" \
  "SELECT id, status, datetime(startedAt) as gestart, datetime(stoppedAt) as gestopt,
          (julianday(stoppedAt) - julianday(startedAt)) * 86400.0 as duur_seconden
   FROM execution_entity WHERE id=${LAST_OK};"

sqlite3 "$DB" "SELECT data FROM execution_data WHERE executionId='${LAST_OK}';" > /tmp/last_ok_data.txt

echo ""
echo "==> Tool-namen die voorkomen in de ruwe executiedata (regex, geen volledige parse)..."
python3 - <<'PYEOF'
import re
with open('/tmp/last_ok_data.txt', encoding='utf-8', errors='replace') as f:
    text = f.read()

candidates = [
    'google_calendar', 'Google Calendar', 'content_hub_opslaan', 'taak_aanmaken',
    'taken_ophalen', 'web_zoeken', 'weer', 'get_email', 'google_docs', 'google_sheets',
    'google_drive', 'google_workspace', 'google_maps', 'logboek',
]
for c in candidates:
    count = text.count(c)
    if count:
        print(f"  - {c!r}: {count}x gevonden in de executiedata")
PYEOF
