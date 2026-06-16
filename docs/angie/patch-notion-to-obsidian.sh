#!/bin/bash
# ============================================================
# Project Angie — Vervang Notion door Obsidian in Secretaresse workflow
# Voer uit OP de Raspberry Pi 5:
#   bash <(curl -fsSL https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-notion-to-obsidian.sh)
# ============================================================

set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }
err()  { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
VAULT="/home/redactielinks/n8n-obsidian-share"

echo ""
echo "============================================================"
echo "  Project Angie — Notion → Obsidian migratie"
echo "============================================================"
echo ""

# ── 1. Vault-map uitbreiden ────────────────────────────────
mkdir -p "${VAULT}/Inbox" "${VAULT}/Dagboek" "${VAULT}/Archief" "${VAULT}/ContentHub"
chmod -R 777 "${VAULT}"
ok "Vault-mappen aanwezig (incl. ContentHub)"

# ── 2. Workflow exporteren ────────────────────────────────
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json
ok "Workflow geëxporteerd naar /tmp/sec.json"

# ── 3. Python-patch uitvoeren ─────────────────────────────
python3 - <<'PYEOF'
import json, sys

INPUT  = "/tmp/sec.json"
OUTPUT = "/tmp/sec-modified.json"

# ── JavaScript: idee opslaan in Obsidian ──────────────────
IDEE_JS = r"""
const meta = $('Verwerk metadata').first().json;
const fs = require('fs');
const path = require('path');
const VAULT = '/home/node/obsidian-share';
const now = new Date();
const pad = n => String(n).padStart(2, '0');
const dateStr = now.getFullYear() + '-' + pad(now.getMonth()+1) + '-' + pad(now.getDate());
const timestamp = dateStr + ' ' + pad(now.getHours()) + ':' + pad(now.getMinutes());
const fileTs = String(now.getFullYear()) + pad(now.getMonth()+1) + pad(now.getDate()) + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());

const dir = path.join(VAULT, 'Inbox');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

const tags = (meta.tags || []).concat(['idee', 'telegram']);
const tagLines = tags.map(t => '  - ' + t).join('\n');
const frontmatter = [
  '---', 'tags:', tagLines,
  'titel: ' + (meta.titel || 'Idee'),
  'categorie: ' + (meta.categorie || 'Projecten'),
  'prioriteit: ' + (meta.prioriteit || 'Normaal'),
  'datum: ' + timestamp, 'bron: telegram', '---', '',
  '# ' + (meta.titel || 'Idee'), '',
  meta.samenvatting || '', '',
].join('\n');

const content = frontmatter + (meta.origineleTekst ? '\n## Origineel\n\n' + meta.origineleTekst + '\n' : '');
const filepath = path.join(dir, fileTs + '-idee.md');
fs.writeFileSync(filepath, content, 'utf8');

return [{ json: { ...meta, filepath } }];
""".strip()

# ── JavaScript: content opslaan in Obsidian ───────────────
CONTENT_JS = r"""
const item = $input.first().json;
const titel = item.titel || item.title || ('Content ' + new Date().toISOString().substring(0,10));
const tekst = item.content || item.tekst || item.text || item.origineleTekst || '';
const fs = require('fs');
const path = require('path');
const VAULT = '/home/node/obsidian-share';
const now = new Date();
const pad = n => String(n).padStart(2, '0');
const dateStr = now.getFullYear() + '-' + pad(now.getMonth()+1) + '-' + pad(now.getDate());
const timestamp = dateStr + ' ' + pad(now.getHours()) + ':' + pad(now.getMinutes());
const fileTs = String(now.getFullYear()) + pad(now.getMonth()+1) + pad(now.getDate()) + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());

const dir = path.join(VAULT, 'ContentHub');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

const lines = [
  '---', 'tags:', '  - content', '  - telegram',
  'datum: ' + timestamp, 'bron: telegram', '---', '',
  '# ' + titel, '', tekst, '',
].join('\n');

const filepath = path.join(dir, fileTs + '-content.md');
fs.writeFileSync(filepath, lines, 'utf8');
return [{ json: { ...item, filepath } }];
""".strip()

# ── Tool: taak aanmaken in Obsidian ───────────────────────
TAAK_TOOL_JS = r"""
const naam      = $fromAI('naam', 'Naam van de taak');
const prioriteit = $fromAI('prioriteit', 'Hoog, Middel of Laag') || 'Middel';
const deadline  = $fromAI('deadline', 'Deadline YYYY-MM-DD of leeg') || '';
const fs = require('fs');
const path = require('path');
const VAULT = '/home/node/obsidian-share';
const now = new Date();
const pad = n => String(n).padStart(2, '0');
const dateStr = now.getFullYear() + '-' + pad(now.getMonth()+1) + '-' + pad(now.getDate());
const timestamp = dateStr + ' ' + pad(now.getHours()) + ':' + pad(now.getMinutes());
const fileTs = String(now.getFullYear()) + pad(now.getMonth()+1) + pad(now.getDate()) + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());

const dir = path.join(VAULT, 'Inbox');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

const lines = [
  '---', 'tags:', '  - taak', '  - telegram',
  'prioriteit: ' + prioriteit,
  deadline ? 'deadline: ' + deadline : null,
  'datum: ' + timestamp, 'bron: telegram', '---', '',
  '- [ ] ' + naam, '',
].filter(l => l !== null).join('\n');

const filepath = path.join(dir, fileTs + '-taak.md');
fs.writeFileSync(filepath, lines, 'utf8');
return 'Taak aangemaakt in Obsidian: "' + naam + '" (' + prioriteit + (deadline ? ', deadline: ' + deadline : '') + ')';
""".strip()

# ── Tool: taken ophalen uit Obsidian ──────────────────────
TAKEN_TOOL_JS = r"""
const zoekterm = $fromAI('zoekterm', 'Zoekterm voor taken, of leeg voor alle open taken') || '';
const fs = require('fs');
const path = require('path');
const VAULT = '/home/node/obsidian-share';

const openTaken = [];
function scanDir(dir) {
  let entries;
  try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch(e) { return; }
  for (const e of entries) {
    if (e.name.startsWith('.')) continue;
    const fp = path.join(dir, e.name);
    if (e.isDirectory()) { scanDir(fp); continue; }
    if (!e.name.endsWith('.md')) continue;
    try {
      const txt = fs.readFileSync(fp, 'utf8');
      const taken = txt.split('\n').filter(l => l.includes('- [ ]'));
      if (taken.length === 0) continue;
      if (zoekterm && !txt.toLowerCase().includes(zoekterm.toLowerCase())) continue;
      taken.forEach(t => openTaken.push(t.trim()));
    } catch(e2) {}
  }
}
scanDir(VAULT);

if (openTaken.length === 0) return 'Geen openstaande taken gevonden' + (zoekterm ? ' voor "' + zoekterm + '"' : '') + '.';
return 'Openstaande taken (' + openTaken.length + '):\n' + openTaken.join('\n');
""".strip()

# ── Laden ─────────────────────────────────────────────────
with open(INPUT, encoding='utf-8') as f:
    data = json.load(f)

wf = next((w for w in (data if isinstance(data, list) else [data])
           if w.get('id') == 'YdNGeswnhhzFdTFy'), None)
if not wf:
    print("ERROR: Secretaresse workflow niet gevonden!"); sys.exit(1)
print(f"Gevonden: {wf['name']}")

# ── Nodes patchen ─────────────────────────────────────────
for node in wf['nodes']:
    nm = node['name']

    if nm == 'Sla op Notion':
        node['type'] = 'n8n-nodes-base.code'
        node['typeVersion'] = 2
        node['parameters'] = {'jsCode': IDEE_JS}
        node.pop('credentials', None)
        print("  ~ Sla op Notion          → Obsidian (idee)")

    elif nm == 'Sla op Content Hub':
        node['type'] = 'n8n-nodes-base.code'
        node['typeVersion'] = 2
        node['parameters'] = {'jsCode': CONTENT_JS}
        node.pop('credentials', None)
        print("  ~ Sla op Content Hub     → Obsidian (ContentHub)")

    elif nm == 'Taak aanmaken':
        node['type'] = '@n8n/n8n-nodes-langchain.toolCode'
        node['typeVersion'] = 1
        node['parameters'] = {
            'name': 'taak_aanmaken',
            'description': 'Maak een nieuwe taak aan in Obsidian.',
            'jsCode': TAAK_TOOL_JS
        }
        node.pop('credentials', None)
        print("  ~ Taak aanmaken          → Obsidian toolCode")

    elif nm == 'Taken ophalen':
        node['type'] = '@n8n/n8n-nodes-langchain.toolCode'
        node['typeVersion'] = 1
        node['parameters'] = {
            'name': 'taken_ophalen',
            'description': 'Haal openstaande taken op uit Obsidian. Geeft een lijst van - [ ] items terug.',
            'jsCode': TAKEN_TOOL_JS
        }
        node.pop('credentials', None)
        print("  ~ Taken ophalen          → Obsidian toolCode")

    elif nm == 'Bevestig opslaan':
        txt = node.get('parameters', {}).get('text', '')
        node['parameters']['text'] = txt.replace('Notion', 'Obsidian').replace('notion', 'obsidian')
        print("  ~ Bevestig opslaan       → tekst bijgewerkt")

    elif nm == 'Bevestig content':
        txt = node.get('parameters', {}).get('text', '')
        node['parameters']['text'] = txt.replace('Content Hub', 'Obsidian').replace('content hub', 'Obsidian').replace('Notion', 'Obsidian')
        print("  ~ Bevestig content       → tekst bijgewerkt")

# ── Opslaan ───────────────────────────────────────────────
with open(OUTPUT, 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print(f"\nKlaar: {OUTPUT}")
PYEOF

ok "Patch uitgevoerd"

# ── 4. Importeren ─────────────────────────────────────────
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all
ok "Workflow geïmporteerd"

# ── 5. Activeren (activeVersionId instellen) ──────────────
ACTIVE_VID=$(sqlite3 "${DB}" \
  "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
docker stop n8n 2>/dev/null || true
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1, activeVersionId='${ACTIVE_VID}' WHERE id='${WF_ID}';"
ok "Workflow geactiveerd (activeVersionId=${ACTIVE_VID})"

# ── 6. n8n herstarten ─────────────────────────────────────
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker rm n8n 2>/dev/null || true
docker run -d \
    --name n8n \
    --restart always \
    -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v "${VAULT}:/home/node/obsidian-share" \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path \
    n8nio/n8n:latest
ok "n8n herstart"

# ── 7. Funnel activeren ───────────────────────────────────
sudo tailscale funnel --bg 5678 2>/dev/null && ok "Tailscale Funnel actief" || true

sleep 10
docker logs n8n --tail 6

echo ""
echo "============================================================"
echo -e "${GREEN}  KLAAR — Notion verwijderd, Obsidian actief${NC}"
echo "============================================================"
echo ""
echo "  Test: stuur '/idee vliegende auto' via Telegram"
echo "  Resultaat: bevestiging + bestand in ${VAULT}/Inbox/"
echo ""
