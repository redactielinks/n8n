#!/bin/bash
# Patch: /idee schrijft direct naar Obsidian (geen OpenRouter tussenstap)
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF'
import json

EXTRAHEER_JS = r"""
const text = $input.first().json.text || '';
const ideeTekst = text.replace(/^\/?idee[,\s]+/i, '').trim();
const chatId = String($('Listen for incoming events').first().json?.message?.from?.id || 7319477310);

const fs = require('fs');
const path = require('path');
const VAULT = '/home/node/obsidian-share';
const LLM_URL = 'http://100.68.46.126:27124/v1/chat/completions';

const now = new Date();
const pad = n => String(n).padStart(2, '0');
const dateStr = now.getFullYear() + '-' + pad(now.getMonth()+1) + '-' + pad(now.getDate());
const timestamp = dateStr + ' ' + pad(now.getHours()) + ':' + pad(now.getMinutes());
const fileTs = String(now.getFullYear()) + pad(now.getMonth()+1) + pad(now.getDate()) + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());

// Lokale LLM aanroepen voor metadata
let titel = ideeTekst.substring(0, 60);
let samenvatting = '';
let categorie = 'Projecten';
let prioriteit = 'Normaal';
let tags = ['idee', 'telegram'];

try {
  const llmRes = await fetch(LLM_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      model: 'local-model',
      messages: [{
        role: 'system',
        content: 'Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel":"max 60 tekens","samenvatting":"2-3 zinnen","categorie":"Projecten|Zakelijk|Uitvinding|Levensstijl|Kopen|Reizen|Lezen|Gezondheid|Financien","prioriteit":"Laag|Normaal|Hoog","tags":["3-5 trefwoorden"]}'
      }, {
        role: 'user',
        content: 'Brainstormidee: ' + ideeTekst
      }],
      stream: false,
      temperature: 0.3
    })
  });
  const llmData = await llmRes.json();
  const content = llmData?.choices?.[0]?.message?.content || '{}';
  const meta = JSON.parse(content.replace(/```json\n?|\n?```/g, '').trim());
  if (meta.titel)       titel       = String(meta.titel).substring(0, 60);
  if (meta.samenvatting) samenvatting = String(meta.samenvatting);
  if (meta.categorie)   categorie   = String(meta.categorie);
  if (meta.prioriteit)  prioriteit  = String(meta.prioriteit);
  if (Array.isArray(meta.tags)) tags = meta.tags.concat(['idee', 'telegram']);
} catch(e) {
  // LLM niet beschikbaar: sla op zonder verrijking
}

const dir = path.join(VAULT, 'Inbox');
if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

const tagLines = tags.map(t => '  - ' + t).join('\n');
const lines = [
  '---', 'tags:', tagLines,
  'titel: ' + titel,
  'categorie: ' + categorie,
  'prioriteit: ' + prioriteit,
  'datum: ' + timestamp, 'bron: telegram', '---', '',
  '# ' + titel, '',
  samenvatting || ideeTekst, '',
  samenvatting ? ('\n## Origineel\n\n' + ideeTekst) : '',
].join('\n');

fs.writeFileSync(path.join(dir, fileTs + '-idee.md'), lines, 'utf8');

const preview = titel.length > 60 ? titel.substring(0, 60) + '...' : titel;
const replyText = '✅ Idee opgeslagen in Obsidian:\n*' + preview + '*' +
  (samenvatting ? '\n\n' + samenvatting.substring(0, 120) : '');

return [{ json: { chatId, replyText } }];
""".strip()

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

for node in wf['nodes']:
    if node['name'] == 'Extraheer idee':
        node['parameters']['jsCode'] = EXTRAHEER_JS
        print("  ~ Extraheer idee: schrijft direct naar Obsidian")
    elif node['name'] == 'Bevestig opslaan':
        node['parameters']['chatId'] = "={{ $json.chatId }}"
        node['parameters']['text']   = "={{ $json.replyText }}"
        print("  ~ Bevestig opslaan: leest uit $json")

conn = wf.setdefault('connections', {})
if 'Extraheer idee' in conn:
    conn['Extraheer idee'] = {
        'main': [[{'node': 'Bevestig opslaan', 'type': 'main', 'index': 0}]]
    }
    print("  ~ Verbinding: Extraheer idee → Bevestig opslaan (OpenRouter geskipt)")

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF

echo "==> Importeren..."
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all

echo "==> Activeren..."
ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
docker stop n8n 2>/dev/null
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1, activeVersionId='${ACTIVE_VID}' WHERE id='${WF_ID}';"
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker rm n8n 2>/dev/null || true
docker run -d --name n8n --restart always -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path \
    n8nio/n8n:latest
sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 4
echo ""
echo "Stuur nu /idee test via Telegram."
