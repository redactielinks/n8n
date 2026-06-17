#!/bin/bash
# Voeg /onderzoek toe: Gemma zoekt via SearXNG op internet, beoordeelt
# betrouwbaarheid en geeft een antwoord met bronnen via Telegram.
# Vereist: setup-searxng.sh is al uitgevoerd.
# Slaat niets automatisch op in de wiki; jij beslist of je het in raw/ zet.
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
const http = require('http');
const https = require('https');
const { URL } = require('url');

function httpRequest(opts) {
  return new Promise((resolve, reject) => {
    const u = new URL(opts.url);
    const lib = u.protocol === 'https:' ? https : http;
    const bodyStr = opts.body !== undefined ? JSON.stringify(opts.body) : undefined;
    const headers = Object.assign({}, opts.headers || {});
    if (bodyStr) {
      headers['Content-Type'] = headers['Content-Type'] || 'application/json';
    }
    const req = lib.request({
      hostname: u.hostname,
      port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: u.pathname + (u.search || ''),
      method: opts.method || 'GET',
      headers,
    }, (res) => {
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode >= 400) {
          reject(new Error('HTTP ' + res.statusCode + ': ' + data.slice(0, 200)));
          return;
        }
        if (opts.json) {
          try { resolve(JSON.parse(data)); }
          catch (e) { reject(new Error('Geen geldige JSON: ' + data.slice(0, 200))); }
        } else {
          resolve(data);
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(opts.timeout || 30000, () => req.destroy(new Error('Timeout na ' + (opts.timeout || 30000) + 'ms')));
    if (bodyStr) req.write(bodyStr);
    req.end();
  });
}

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
  const LLM_URL = 'http://100.68.46.126:27124/v1/chat/completions';
  let titel = content.substring(0, 60);
  let samenvatting = '';
  let categorie = 'Projecten';
  let prioriteit = 'Normaal';
  let tags = ['idee', 'telegram'];

  try {
    const llmData = await httpRequest({
      method: 'POST',
      url: LLM_URL,
      headers: { 'Content-Type': 'application/json' },
      body: {
        model: 'google/gemma-3-4b',
        messages: [{
          role: 'system',
          content: 'Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel":"max 60 tekens","samenvatting":"2-3 zinnen","categorie":"Projecten|Zakelijk|Uitvinding|Levensstijl|Kopen|Reizen|Lezen|Gezondheid|Financien","prioriteit":"Laag|Normaal|Hoog","tags":["3-5 trefwoorden"]}'
        }, {
          role: 'user',
          content: 'Brainstormidee: ' + content
        }],
        stream: false,
        temperature: 0.3
      },
      json: true,
      timeout: 45000,
    });
    const llmContent = llmData?.choices?.[0]?.message?.content || '{}';
    const meta = JSON.parse(llmContent.replace(/```json\n?|\n?```/g, '').trim());
    if (meta.titel)        titel        = String(meta.titel).substring(0, 60);
    if (meta.samenvatting) samenvatting = String(meta.samenvatting);
    if (meta.categorie)    categorie    = String(meta.categorie);
    if (meta.prioriteit)   prioriteit   = String(meta.prioriteit);
    if (Array.isArray(meta.tags)) tags  = meta.tags.concat(['idee', 'telegram']);
  } catch(e) {
    // LLM niet beschikbaar of timeout: sla op zonder verrijking
  }

  const dir = path.join(VAULT, 'Inbox');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const tagLines = tags.map(t => '  - ' + t).join('\n');
  const fileContent = [
    '---', 'tags:', tagLines,
    'titel: ' + titel,
    'categorie: ' + categorie,
    'prioriteit: ' + prioriteit,
    'datum: ' + timestamp, 'bron: telegram', '---', '',
    '# ' + titel, '',
    samenvatting || content, '',
    samenvatting ? ('\n## Origineel\n\n' + content) : '',
  ].join('\n');
  fs.writeFileSync(path.join(dir, fileTs + '-idee.md'), fileContent, 'utf8');
  const preview = titel.length > 60 ? titel.substring(0, 60) + '...' : titel;
  replyText = 'Idee opgeslagen: "' + preview + '"' +
    (samenvatting ? '\n\n' + samenvatting.substring(0, 120) : '');

} else if (cmd === 'taak') {
  if (!content) {
    replyText = 'Geef een taaknaam op. Voorbeeld: /taak rapport afmaken';
  } else {
    const dir = path.join(VAULT, 'Inbox');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const filepath = path.join(dir, fileTs + '-taak.md');
    const lines = [
      '---', 'tags:', '  - taak', '  - telegram',
      'datum: ' + timestamp, 'bron: telegram', '---', '',
      '- [ ] ' + content, '',
    ].join('\n');
    fs.writeFileSync(filepath, lines, 'utf8');
    replyText = 'Taak aangemaakt: "' + content + '"';
  }

} else if (cmd === 'taken') {
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
        txt.split('\n').filter(l => l.includes('- [ ]')).forEach(t => openTaken.push(t.trim()));
      } catch(e2) {}
    }
  }
  scanDir(VAULT);
  if (openTaken.length === 0) {
    replyText = 'Geen openstaande taken gevonden.';
  } else {
    const lijst = openTaken.slice(0, 20).join('\n');
    replyText = 'Openstaande taken (' + openTaken.length + '):\n\n' + lijst;
  }

} else if (cmd === 'wiki') {
  if (!content) {
    replyText = 'Stel een vraag. Voorbeeld: /wiki wat staat er over de schrijfstijl?';
  } else {
    const BRANCH = 'claude/angie-https-tunnel-foss-hfqqzl';
    const KENNISBANK_API = 'https://api.github.com/repos/redactielinks/n8n/contents/kennisbank?ref=' + BRANCH;
    const LLM_URL = 'http://100.68.46.126:27124/v1/chat/completions';
    try {
      // Dit repo is de hele n8n-broncode; een recursieve tree-call op de
      // hele branch zou tienduizenden bestanden teruggeven. Daarom eerst
      // de tree-sha van enkel de wiki-map opzoeken, en alleen die subtree
      // recursief uitlezen.
      const kennisbankListing = await httpRequest({
        method: 'GET',
        url: KENNISBANK_API,
        headers: { 'User-Agent': 'angie-bot' },
        json: true,
        timeout: 15000,
      });
      const wikiEntry = (Array.isArray(kennisbankListing) ? kennisbankListing : [])
        .find(e => e.name === 'wiki' && e.type === 'dir');

      let files = [];
      if (wikiEntry) {
        const TREE_API = 'https://api.github.com/repos/redactielinks/n8n/git/trees/' + wikiEntry.sha + '?recursive=1';
        const tree = await httpRequest({
          method: 'GET',
          url: TREE_API,
          headers: { 'User-Agent': 'angie-bot' },
          json: true,
          timeout: 15000,
        });
        files = (tree.tree || []).filter(f => f.type === 'blob' && f.path.endsWith('.md'));
      }

      let wikiText = '';
      for (const f of files) {
        const rawUrl = 'https://raw.githubusercontent.com/redactielinks/n8n/' + BRANCH + '/kennisbank/wiki/' + f.path;
        const fileTxt = await httpRequest({ method: 'GET', url: rawUrl, timeout: 15000 });
        wikiText += '\n\n## ' + f.path + '\n\n' + fileTxt;
      }

      if (!wikiText.trim()) {
        replyText = 'De wiki is nog leeg.';
      } else {
        const llmData = await httpRequest({
          method: 'POST',
          url: LLM_URL,
          headers: { 'Content-Type': 'application/json' },
          body: {
            model: 'google/gemma-3-4b',
            messages: [{
              role: 'system',
              content: 'Je beantwoordt vragen uitsluitend op basis van de meegegeven wiki-inhoud. Schrijf in duidelijk, spreektaalachtig Nederlands, informeel met "je", direct ter zake, korte alinea\'s van max 3-4 regels, geen lange gedachtenstreep, geen emoji, geen clichés. Staat het antwoord niet in de wiki-inhoud, zeg dat dan expliciet in plaats van te gokken.'
            }, {
              role: 'user',
              content: 'WIKI-INHOUD:\n' + wikiText + '\n\nVRAAG: ' + content
            }],
            stream: false,
            temperature: 0.3
          },
          json: true,
          timeout: 45000,
        });
        replyText = llmData?.choices?.[0]?.message?.content || 'Geen antwoord ontvangen van het model.';
      }
    } catch(e) {
      replyText = 'Wiki niet doorzoekbaar nu (' + e.message + '). Controleer of LM Studio draait op de Mac Mini, of dat GitHub bereikbaar is.';
    }
  }

} else if (cmd === 'onderzoek') {
  if (!content) {
    replyText = 'Stel een onderzoeksvraag. Voorbeeld: /onderzoek nieuwste inzichten over twice exceptional';
  } else {
    const SEARX_URL = 'http://100.77.5.104:8081/search?format=json&q=' + encodeURIComponent(content);
    const LLM_URL = 'http://100.68.46.126:27124/v1/chat/completions';
    try {
      const searchData = await httpRequest({
        method: 'GET',
        url: SEARX_URL,
        json: true,
        timeout: 15000,
      });
      const results = (searchData.results || []).slice(0, 8).map(r => ({
        titel: r.title || '', url: r.url || '', samenvatting: r.content || ''
      }));

      if (results.length === 0) {
        replyText = 'Geen zoekresultaten gevonden voor "' + content + '".';
      } else {
        const bronnenTekst = results.map((r, i) =>
          (i + 1) + '. ' + r.titel + ' (' + r.url + ')\n' + r.samenvatting
        ).join('\n\n');

        const llmData = await httpRequest({
          method: 'POST',
          url: LLM_URL,
          headers: { 'Content-Type': 'application/json' },
          body: {
            model: 'google/gemma-3-4b',
            messages: [{
              role: 'system',
              content: 'Je krijgt een onderzoeksvraag en zoekresultaten van het internet. Beoordeel welke bronnen betrouwbaar lijken: officiele organisaties, vakliteratuur en bekende media wegen zwaarder dan onbekende sites of forums. Geef een kort, feitelijk antwoord gebaseerd op de betrouwbaarste bronnen, en sluit af met een genummerde lijst van de gebruikte bronnen (titel en link). Schrijf in duidelijk, spreektaalachtig Nederlands, informeel met "je", korte alinea\'s van max 3-4 regels, geen lange gedachtenstreep, geen emoji, geen clichés.'
            }, {
              role: 'user',
              content: 'ONDERZOEKSVRAAG: ' + content + '\n\nZOEKRESULTATEN:\n' + bronnenTekst
            }],
            stream: false,
            temperature: 0.3
          },
          json: true,
          timeout: 120000,
        });
        replyText = (llmData?.choices?.[0]?.message?.content || 'Geen antwoord ontvangen van het model.') +
          '\n\n(Niet automatisch opgeslagen. Plaats dit zelf in raw/ als je het wilt bewaren.)';
      }
    } catch(e) {
      replyText = 'Onderzoek niet mogelijk nu (' + e.message + '). Controleer of SearXNG (poort 8081) en LM Studio draaien.';
    }
  }

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
  replyText = 'Beschikbare commando\'s:\n/notitie /dagboek /idee /taak /taken /wiki /onderzoek /zoek';
}

return [{ json: { replyText, chatId, text } }];
""".strip()

NEW_CONDITIONS = [
    {"id": "obs-onderzoek", "leftValue": "={{ ($json.text || '').toLowerCase() }}", "rightValue": "/onderzoek", "operator": {"type": "string", "operation": "startsWith"}},
]

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

for node in wf['nodes']:
    nm = node['name']
    if nm == 'Handle Obsidian':
        node['parameters']['jsCode'] = HANDLE_OBSIDIAN_JS
        print("  ~ Handle Obsidian: /onderzoek toegevoegd")
    elif nm == 'Is Obsidian Cmd?':
        conds = node['parameters']['conditions']['conditions']
        existing = {c.get('rightValue') for c in conds}
        for nc in NEW_CONDITIONS:
            if nc['rightValue'] not in existing:
                conds.append(nc)
                print(f"  ~ Is Obsidian Cmd?: {nc['rightValue']} toegevoegd")
            else:
                print(f"  ~ Is Obsidian Cmd?: {nc['rightValue']} al aanwezig")

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
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path,http,https,url \
    n8nio/n8n:latest
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 3
echo ""
echo "Test:"
echo "  /onderzoek nieuwste inzichten over twice exceptional"
