#!/bin/bash
# ============================================================
# Project Angie — Shortcuts (iOS-deelmenu) aansluiten op de wiki-pad
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Hetzelfde probleem als bij vrije tekst via Telegram: "Shortcuts Trigger"
# (de webhook achter het iOS-deelmenu, "angie-shortcuts") leidde via
# "Verwerk shortcuts" naar "Is /content?", een oude, losstaande keten die
# voor de meeste gevallen uiteindelijk bij de kapotte/rate-limited
# "Secretaresse"-tak uitkomt. Daardoor kwam gedeelde content niet in de
# wiki terecht.
#
# Fix: "Verwerk shortcuts" koppelt nu rechtstreeks aan "Is Wiki Commando?",
# dezelfde commandoherkenning die Telegram en de CLI-bypass al gebruiken.
# De oude "Is /content?"-keten blijft bestaan maar krijgt geen verkeer meer
# (niets verwijderd, dus reversibel).
#
# Daarnaast: "Is CLI Bron?" (toegevoegd in de CLI-bypass-patch) checkte
# alleen op source == 'cli'. Nu Shortcuts ook via dit pad loopt (source ==
# 'shortcuts'), wordt de check generieker: alles wat NIET van Telegram komt
# krijgt een directe HTTP-respons (via "Beantwoord CLI", die voor elke
# wachtende webhook-aanroep werkt, niet alleen voor de CLI-trigger); alleen
# Telegram-berichten gaan nog via de Telegram-node.
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers:
#   rm -f patch-shortcuts-naar-wiki-pad.sh
#   curl -fsSL -o patch-shortcuts-naar-wiki-pad.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-shortcuts-naar-wiki-pad.sh?t=$(date +%s)"
#   grep -q "notEquals" patch-shortcuts-naar-wiki-pad.sh && echo "OK: juiste versie gedownload" || echo "FOUT"
#   bash patch-shortcuts-naar-wiki-pad.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-18-shortcuts-naar-wiki-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
KENNISBANK_DIR="/home/redactielinks/kennisbank"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF'
import json

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

conns = wf['connections']

# --- 1. "Verwerk shortcuts" rechtstreeks naar "Is Wiki Commando?" ---------
verwacht = {'main': [[{'node': 'Is /content?', 'type': 'main', 'index': 0}]]}
if conns.get('Verwerk shortcuts') != verwacht:
    raise SystemExit(
        "Onverwachte bestaande connectie vanaf 'Verwerk shortcuts': "
        f"{conns.get('Verwerk shortcuts')!r} — patch afgebroken, structuur is anders dan verwacht."
    )
conns['Verwerk shortcuts'] = {'main': [[{'node': 'Is Wiki Commando?', 'type': 'main', 'index': 0}]]}
print("  ~ 'Verwerk shortcuts' koppelt nu direct aan 'Is Wiki Commando?' (oude 'Is /content?'-keten omzeild)")

# --- 2. "Is CLI Bron?" generieker maken: alles behalve Telegram -----------
by_name = {n['name']: n for n in wf['nodes']}
node = by_name.get('Is CLI Bron?')
if node is None:
    raise SystemExit("Node 'Is CLI Bron?' niet gevonden — is de CLI-bypass-patch al uitgevoerd?")

cond = node['parameters']['conditions']['conditions']
if len(cond) != 1 or cond[0].get('rightValue') != 'cli' or cond[0]['operator'].get('operation') != 'equals':
    raise SystemExit(f"Onverwachte conditie in 'Is CLI Bron?': {cond!r} — patch afgebroken.")
cond[0]['rightValue'] = 'telegram'
cond[0]['operator']['operation'] = 'notEquals'
print("  ~ 'Is CLI Bron?' checkt nu op 'source != telegram' (CLI + Shortcuts + toekomstige bronnen)")

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
echo "Test via het iOS-deelmenu: deel een stukje tekst of een link naar je 'Angie'-snelkoppeling."
echo "Verwacht: het komt nu in de wiki terecht (net als /notitie), niet meer in de oude content-hub-keten."
echo "Controleer op de Pi:"
echo "  find ~/kennisbank/wiki/persoonlijk -type f -newer ~/kennisbank/wiki/index.md"
