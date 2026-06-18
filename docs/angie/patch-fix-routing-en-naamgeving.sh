#!/bin/bash
# ============================================================
# Project Angie — Routeringsbug fixen + Obsidian-namen weghalen
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Twee problemen in één patch:
#
# 1. Routeringsbug: de node "Is commando?" liet alleen berichten door
#    die met "/" beginnen naar het wiki-pad. Vrije tekst (zonder "/")
#    werd daardoor voor die controle al afgevangen en viel in de oude,
#    losstaande Secretaresse/OpenRouter-tak (die nu vastloopt op een
#    rate-limit). Daardoor kwam niets in de wiki terecht.
#    Fix: "Voice or Text" koppelt nu rechtstreeks aan de wiki-
#    commandoherkenning, die zelf via een vangnet-voorwaarde al
#    vrije tekst, spraak ÉN alle slash-commando's afvangt. De oude
#    "Is commando?"-node en de tak erachter blijven bestaan maar
#    krijgen geen verkeer meer (niets verwijderd, dus reversibel).
#
# 2. Naamgeving: "Is Obsidian Cmd?", "Handle Obsidian" en
#    "Telegram: Obsidian Reply" zijn alleen interne node-namen uit de
#    tijd dat dit systeem nog naar Obsidian schreef. Functioneel
#    schrijft niets meer naar Obsidian (zie patch-stop-obsidian-
#    gebruik-wiki.sh), maar de namen zijn verwarrend. Hernoemd naar:
#      Is Obsidian Cmd?        -> Is Wiki Commando?
#      Handle Obsidian         -> Verwerk Wiki Commando
#      Telegram: Obsidian Reply -> Telegram: Wiki Antwoord
#
# Voer dit uit OP de Raspberry Pi:
#   curl -fsSL -o patch-fix-routing-en-naamgeving.sh https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-fix-routing-en-naamgeving.sh
#   bash patch-fix-routing-en-naamgeving.sh
# ============================================================
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
KENNISBANK_DIR="/home/redactielinks/kennisbank"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF'
import json

RENAME = {
    'Is Obsidian Cmd?': 'Is Wiki Commando?',
    'Handle Obsidian': 'Verwerk Wiki Commando',
    'Telegram: Obsidian Reply': 'Telegram: Wiki Antwoord',
}

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

for node in wf['nodes']:
    if node['name'] in RENAME:
        old = node['name']
        node['name'] = RENAME[old]
        print(f"  ~ hernoemd: {old} -> {RENAME[old]}")

def rename_in_connections(conns):
    # Echte n8n-structuur: connections[bron] = {"main": [[{node,type,index}, ...], [...]]}
    new_conns = {}
    for src, conn_types in conns.items():
        new_src = RENAME.get(src, src)
        new_conn_types = {}
        for conn_type, outputs in conn_types.items():
            new_outputs = []
            for output in outputs:
                new_output = []
                for conn in output:
                    conn = dict(conn)
                    if conn.get('node') in RENAME:
                        conn['node'] = RENAME[conn['node']]
                    new_output.append(conn)
                new_outputs.append(new_output)
            new_conn_types[conn_type] = new_outputs
        new_conns[new_src] = new_conn_types
    return new_conns

wf['connections'] = rename_in_connections(wf['connections'])

# Bypass de oude "Is commando?"-poort: alles van "Voice or Text" gaat
# direct naar de wiki-commandoherkenning (die zelf al vrije tekst, spraak
# en alle slash-commando's afvangt), zodat vrije tekst niet meer in de
# oude, kapotte Secretaresse/OpenRouter-tak verdwijnt.
wf['connections']['Voice or Text'] = {'main': [[{'node': 'Is Wiki Commando?', 'type': 'main', 'index': 0}]]}
print("  ~ 'Voice or Text' koppelt nu direct aan 'Is Wiki Commando?' (oude 'Is commando?'-poort omzeild)")

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF

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
echo "Test in Telegram:"
echo "  - Vrije tekst zonder slash, bijv: even een testje zonder commando"
echo "  - /notitie test van de gefixte routering"
echo "  - /taken"
echo ""
echo "Controleer daarna op de Pi of het bestand is aangemaakt:"
echo "  find ~/kennisbank/wiki/persoonlijk -type f -newer ~/kennisbank/wiki/index.md"
