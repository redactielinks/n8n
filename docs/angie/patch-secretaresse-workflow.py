#!/usr/bin/env python3
"""
Patch: voeg Obsidian-nodes toe aan de Secretaresse workflow.
Gebruik: python3 patch-secretaresse-workflow.py
Input:  /tmp/sec.json  (geexporteerd via: docker cp n8n:/tmp/sec.json /tmp/sec.json)
Output: /tmp/sec-modified.json
"""

import json
import sys

INPUT  = "/tmp/sec.json"
OUTPUT = "/tmp/sec-modified.json"

with open(INPUT, encoding="utf-8") as f:
    data = json.load(f)

wf = data[0] if isinstance(data, list) else data

# ── JavaScript voor de Obsidian handler ───────────────────────────────────────
OBSIDIAN_JS = r"""
const msg = $('Listen for incoming events').first().json.message;
const text = ($json.text || '').trim();
const chatId = String(msg?.from?.id || $json.chat_id || '');
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
  replyText = 'Onbekend Obsidian-commando: /' + cmd + '. Beschikbaar: /notitie, /dagboek, /zoek';
}

return [{ json: { replyText, chatId, text } }];
""".strip()

# ── Nieuwe nodes ───────────────────────────────────────────────────────────────
new_nodes = [
    {
        "parameters": {
            "conditions": {
                "options": {"caseSensitive": False, "leftValue": "", "typeValidation": "loose"},
                "conditions": [
                    {"id": "obs-notitie", "leftValue": "={{ ($json.text || '').toLowerCase() }}", "rightValue": "/notitie", "operator": {"type": "string", "operation": "startsWith"}},
                    {"id": "obs-note",    "leftValue": "={{ ($json.text || '').toLowerCase() }}", "rightValue": "/note",    "operator": {"type": "string", "operation": "startsWith"}},
                    {"id": "obs-dagboek", "leftValue": "={{ ($json.text || '').toLowerCase() }}", "rightValue": "/dagboek", "operator": {"type": "string", "operation": "startsWith"}},
                    {"id": "obs-journal", "leftValue": "={{ ($json.text || '').toLowerCase() }}", "rightValue": "/journal", "operator": {"type": "string", "operation": "startsWith"}},
                    {"id": "obs-zoek",    "leftValue": "={{ ($json.text || '').toLowerCase() }}", "rightValue": "/zoek",    "operator": {"type": "string", "operation": "startsWith"}},
                    {"id": "obs-find",    "leftValue": "={{ ($json.text || '').toLowerCase() }}", "rightValue": "/find",    "operator": {"type": "string", "operation": "startsWith"}},
                ],
                "combinator": "or"
            },
            "options": {}
        },
        "id": "obsidian-router-v1",
        "name": "Is Obsidian Cmd?",
        "type": "n8n-nodes-base.if",
        "typeVersion": 2,
        "position": [2316, 700]
    },
    {
        "parameters": {
            "jsCode": OBSIDIAN_JS
        },
        "id": "obsidian-handler-v1",
        "name": "Handle Obsidian",
        "type": "n8n-nodes-base.code",
        "typeVersion": 2,
        "position": [2536, 700]
    },
    {
        "parameters": {
            "chatId": "={{ $json.chatId }}",
            "text": "={{ $json.replyText }}",
            "additionalFields": {"appendAttribution": False}
        },
        "id": "obsidian-telegram-v1",
        "name": "Telegram: Obsidian Reply",
        "type": "n8n-nodes-base.telegram",
        "typeVersion": 1.2,
        "position": [2756, 700],
        "credentials": {
            "telegramApi": {"id": "zk613MPgh3b3pkBZ", "name": "jaouiyes_n8n_bot"}
        }
    }
]

# ── Voeg nodes toe ────────────────────────────────────────────────────────────
existing_ids = {n["id"] for n in wf["nodes"]}
for node in new_nodes:
    if node["id"] not in existing_ids:
        wf["nodes"].append(node)
        print(f"  + Node toegevoegd: {node['name']}")
    else:
        print(f"  ~ Node bestaat al: {node['name']} (overgeslagen)")

# ── Verbindingen aanpassen ────────────────────────────────────────────────────
connections = wf.setdefault("connections", {})

# "Is commando?" TRUE → was "Verwerk commando", wordt "Is Obsidian Cmd?"
if "Is commando?" in connections:
    true_outputs = connections["Is commando?"]["main"][0]
    for conn in true_outputs:
        if conn["node"] == "Verwerk commando":
            conn["node"] = "Is Obsidian Cmd?"
            print("  ~ Verbinding: 'Is commando?' TRUE → 'Is Obsidian Cmd?'")

# Nieuwe verbindingen
connections["Is Obsidian Cmd?"] = {
    "main": [
        [{"node": "Handle Obsidian",  "type": "main", "index": 0}],  # TRUE
        [{"node": "Verwerk commando", "type": "main", "index": 0}]   # FALSE
    ]
}
connections["Handle Obsidian"] = {
    "main": [[{"node": "Telegram: Obsidian Reply", "type": "main", "index": 0}]]
}
print("  + Verbindingen voor Obsidian-branch toegevoegd")

# ── Help-tekst uitbreiden in Verwerk commando ─────────────────────────────────
OBSIDIAN_HELP = (
    "\\n/notitie [tekst] \\u2014 opslaan in Obsidian"
    "\\n/dagboek [tekst] \\u2014 dagboek bijwerken"
    "\\n/zoek [query]   \\u2014 zoeken in Obsidian"
)
for node in wf["nodes"]:
    if node["name"] == "Verwerk commando" and "jsCode" in node.get("parameters", {}):
        old = node["parameters"]["jsCode"]
        marker = "stuur /help voor hulp."
        if marker in old and "/notitie" not in old:
            new_help_line = (
                "\\n/notitie [tekst] \\u2014 opslaan in Obsidian"
                "\\n/dagboek [tekst] \\u2014 dagboek bijwerken"
                "\\n/zoek [query] \\u2014 zoeken in Obsidian"
            )
            node["parameters"]["jsCode"] = old.replace(
                "/idee [tekst] \\u2014 sla idee op in Notion'",
                "/idee [tekst] \\u2014 sla idee op in Notion" + new_help_line + "'"
            )
            print("  ~ Help-tekst uitgebreid met Obsidian-commando's")

# ── Opslaan ───────────────────────────────────────────────────────────────────
output = data if isinstance(data, list) else [wf]
with open(OUTPUT, "w", encoding="utf-8") as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

print(f"\nKlaar! Opgeslagen als {OUTPUT}")
print("Importeer met:")
print("  docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all")
