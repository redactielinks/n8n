#!/bin/bash
# Fix: voeg /idee toe aan de werkende Obsidian-route (zelfde pad als /notitie)
# De oorspronkelijke /idee-route gaat door een AI-keten die hangt.
# Oplossing: /idee toevoegen aan "Is Obsidian Cmd?" + "Handle Obsidian".
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF'
import json

HANDLE_OBSIDIAN_JS = r"""
const inp = $input.first().json;
const text = (inp.text || inp.message?.text || '').trim();
const chatId = String(inp.message?.from?.id || inp.chatId || '7319477310');
const fs = require('fs');
const path = require('path');

const VAULT = '/home/node/obsidian-share';
const now = new Date();
const pad = n => String(n).padStart(2, '0');
const dateStr = now.getFullYear() + '-' + pad(now.getMonth()+1) + '-' + pad(now.getDate());
const timeStr = pad(now.getHours()) + ':' + pad(now.getMinutes());
const timestamp = dateStr + ' ' + timeStr;
const fileTs = String(now.getFullYear()) + pad(now.getMonth()+1) + pad(now.getDate()) + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());

const cmdMatch = text.match(/^\/(\w+)\s*([\s\S]*)/);
const cmd = (cmdMatch?.[1] || '').toLowerCase();
const content = (cmdMatch?.[2] || '').trim();

let replyText = '';

if (cmd === 'notitie' || cmd === 'notities' || cmd === 'note') {
  const dir = path.join(VAULT, 'Inbox');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const filepath = path.join(dir, fileTs + '-notitie.md');
  const lines = ['---', 'tags:', '  - notitie', '  - telegram', 'datum: ' + timestamp, 'bron: telegram', '---', '', content];
  fs.writeFileSync(filepath, lines.join('\n'), 'utf8');
  const preview = content.length > 60 ? content.substring(0, 60) + '...' : content;
  replyText = 'Notitie opgeslagen: "' + preview + '"';

} else if (cmd === 'dagboek' || cmd === 'journal') {
  const dir = path.join(VAULT, 'Dagboek');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const filepath = path.join(dir, dateStr + '.md');
  const entry = '\n## ' + timestamp + '\n\n' + content + '\n';
  if (fs.existsSync(filepath)) {
    fs.appendFileSync(filepath, entry, 'utf8');
  } else {
    const header = ['---', 'tags:', '  - dagboek', '  - telegram', 'datum: ' + dateStr, 'bron: telegram', '---', '', '# Dagboek ' + dateStr, ''].join('\n');
    fs.writeFileSync(filepath, header + entry, 'utf8');
  }
  replyText = 'Dagboek bijgewerkt voor ' + dateStr + '.';

} else if (cmd === 'idee') {
  const dir = path.join(VAULT, 'Inbox');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const filepath = path.join(dir, fileTs + '-idee.md');
  const tags = ['---', 'tags:', '  - idee', '  - telegram', 'datum: ' + timestamp, 'bron: telegram', '---', '', '# ' + content, '', content, ''].join('\n');
  fs.writeFileSync(filepath, tags, 'utf8');
  const preview = content.length > 60 ? content.substring(0, 60) + '...' : content;
  replyText = 'Idee opgeslagen: "' + preview + '"';

} else if (cmd === 'zoek' || cmd === 'search' || cmd === 'find') {
  if (!content || content.length < 2) {
    replyText = 'Geef een zoekterm op. Voorbeeld: /zoek project aanpak';
  } else {
    const results = [];
    function searchVault(dir, q) {
      if (results.length >= 5) return;
      let entries;
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch(e) { return; }
      for (const e of entries) {
        if (results.length >= 5) break;
        if (e.name.startsWith('.')) continue;
        const fp = path.join(dir, e.name);
        if (e.isDirectory()) { searchVault(fp, q); }
        else if (e.name.endsWith('.md')) {
          try {
            const txt = fs.readFileSync(fp, 'utf8');
            if (txt.toLowerCase().includes(q.toLowerCase())) {
              const lines = txt.split('\n');
              const hit = lines.find(l => l.toLowerCase().includes(q.toLowerCase()) && l.trim() && !l.startsWith('---') && !l.startsWith('tags:')) || '';
              const clean = hit.trim().replace(/^#+\s*/, '').replace(/[*_`\[\]]/g, '').substring(0, 80);
              results.push({ name: e.name.replace('.md', ''), preview: clean });
            }
          } catch(e2) {}
        }
      }
    }
    searchVault(VAULT, content);
    if (results.length === 0) {
      replyText = 'Geen notities gevonden voor "' + content + '".';
    } else {
      const list = results.map((r, i) =>
        (i + 1) + '. ' + r.name + (r.preview ? '\n   ' + r.preview : '')
      ).join('\n\n');
      replyText = 'Gevonden (' + results.length + ') voor "' + content + '":\n\n' + list;
    }
  }
} else {
  replyText = 'Onbekend commando: /' + cmd + '. Beschikbaar: /notitie, /dagboek, /idee, /zoek';
}

return [{ json: { replyText, chatId, text } }];
""".strip()

IDEE_CONDITION = {
    "id": "obs-idee",
    "leftValue": "={{ ($json.text || '').toLowerCase() }}",
    "rightValue": "/idee",
    "operator": {"type": "string", "operation": "startsWith"}
}

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

for node in wf['nodes']:
    nm = node['name']

    if nm == 'Handle Obsidian':
        node['parameters']['jsCode'] = HANDLE_OBSIDIAN_JS
        print("  ~ Handle Obsidian: bijgewerkt met /idee ondersteuning")

    elif nm == 'Is Obsidian Cmd?':
        conds = node['parameters']['conditions']['conditions']
        if not any(c.get('rightValue') == '/idee' for c in conds):
            conds.append(IDEE_CONDITION)
            print("  ~ Is Obsidian Cmd?: /idee conditie toegevoegd")
        else:
            print("  ~ Is Obsidian Cmd?: /idee was al aanwezig")

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF

echo "==> Importeren..."
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all

echo "==> Activeren..."
ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
docker stop n8n 2>/dev/null || true
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
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 3
echo ""
echo "Stuur nu /idee test via Telegram."
echo "Werkt dit: /notitie test  → dan werkt /idee nu ook."
