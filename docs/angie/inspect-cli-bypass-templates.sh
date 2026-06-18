#!/bin/bash
# ============================================================
# Project Angie — Inspectie t.b.v. Telegram-bypass CLI-commando
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Alleen-lezen: exporteert de live workflow en print de exacte
# node-structuur van de bouwstenen die hergebruikt worden om een
# nieuwe lokale webhook-ingang te bouwen (CLI i.p.v. Telegram).
# Past niets aan.
#
# Voer dit uit OP de Raspberry Pi:
#   curl -fsSL -o inspect-cli-bypass-templates.sh https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/inspect-cli-bypass-templates.sh
#   bash inspect-cli-bypass-templates.sh
# ============================================================
set -euo pipefail

docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

python3 - <<'PYEOF'
import json

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)
wf = next(w for w in (data if isinstance(data, list) else [data]) if w.get('id') == 'YdNGeswnhhzFdTFy')

names = ['Shortcuts Trigger', 'Beantwoord shortcuts', 'Is Obsidian Cmd?', 'Handle Obsidian', 'Telegram: Obsidian Reply']
by_name = {n['name']: n for n in wf['nodes']}
for nm in names:
    node = by_name.get(nm)
    print(f"\n===== {nm} =====")
    if not node:
        print("NIET GEVONDEN")
        continue
    # Handle Obsidian's jsCode is al bekend en is te lang om hier nogmaals
    # te printen, dus die wordt overgeslagen.
    slim = {k: v for k, v in node.items() if not (nm == 'Handle Obsidian' and k == 'parameters')}
    print(json.dumps(slim, ensure_ascii=False, indent=2))

print("\n===== connections (relevant) =====")
conns = wf['connections']
for src in ['Shortcuts Trigger', 'Verwerk shortcuts', 'Handle Obsidian', 'Is Obsidian Cmd?']:
    if src in conns:
        print(src, '->', json.dumps(conns[src]))
PYEOF
