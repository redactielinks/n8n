# Technisch Dossier — Project Angie: Obsidian-koppeling

**Status:** Gereed voor installatie  
**Datum:** 2026-06-15  
**Milestone:** Obsidian als database voor Second Brain

---

## Architectuur: Obsidian als Single Source of Truth

```
iPhone (Telegram)
        │
        ▼ HTTPS via Tailscale Funnel
n8n op Pi 5 (100.77.5.104)
        │
        ├── /notitie /taak /idee → Inbox/[ts]-[type].md
        ├── /dagboek             → Dagboek/YYYY-MM-DD.md (append)
        ├── /zoek                → grep vault → Telegram reply
        └── vrije tekst         → LLM (Mac Mini) → Inbox/[ts]-[cat].md
        │
        ▼ schrijft naar
/home/redactielinks/n8n-obsidian-share/  ← Obsidian vault op Pi 5
        │
        ▼ Syncthing via Tailscale (100.77.5.104 ↔ 100.111.45.105)
~/ObsidianVault/  ← Obsidian vault op MacBook Pro
        │
        ▼
Obsidian (MacBook) — realtime zichtbaar in de app
```

---

## Vault-mapstructuur

```
n8n-obsidian-share/
├── .obsidian/              ← Obsidian configuratie
├── Inbox/                  ← ALLE nieuwe Telegram-notities
│   ├── 20240615143022-notitie.md
│   ├── 20240615143501-taak.md
│   └── 20240615150000-idee.md
├── Dagboek/                ← één .md-bestand per dag
│   ├── 2024-06-15.md
│   └── 2024-06-16.md
└── Archief/                ← handmatig beheerd door gebruiker
```

**Werkwijze (GTD-filosofie):**  
Alles komt binnen in `Inbox/`. Regelmatig verwerk je de Inbox in Obsidian op MacBook: verplaatsen naar thematische mappen, linken, uitwerken. Angie vult de Inbox aan vanuit je iPhone.

---

## Bestandsformaat (YAML frontmatter)

### Directe commando's (notitie/taak/idee):
```markdown
---
tags:
  - taak
  - telegram
datum: 2024-06-15 14:30
bron: telegram
---

- [ ] rapport afmaken voor vrijdag
```

### LLM-verwerkte vrije tekst:
```markdown
---
titel: Aanpak voor project X
tags:
  - project
  - planning
  - telegram
datum: 2024-06-15 14:30
bron: telegram
categorie: notitie
---

# Aanpak voor project X

[inhoud gestructureerd door LLM]
```

### Dagboek (dagelijks bijgehouden, append-mode):
```markdown
---
tags:
  - dagboek
  - telegram
datum: 2024-06-15
bron: telegram
---

# Dagboek 2024-06-15

## 2024-06-15 09:15

Eerste entry van de dag...

## 2024-06-15 14:30

Volgende entry...
```

---

## Installatie: Stap voor stap

### Fase 1: Vault initialiseren op Pi 5

```bash
ssh redactielinks@100.77.5.104
bash ~/n8n/docs/angie/init-obsidian-vault.sh
```

Maakt aan:
- `/home/redactielinks/n8n-obsidian-share/Inbox/`
- `/home/redactielinks/n8n-obsidian-share/Dagboek/`
- `/home/redactielinks/n8n-obsidian-share/Archief/`
- `/home/redactielinks/n8n-obsidian-share/.obsidian/`
- Welkomstnotitie in Inbox/

### Fase 2: n8n container herstarten met fs-module toegang

De workflow gebruikt `require('fs')` in Code nodes voor dagboek-append en zoekfunctie. Dit vereist de `NODE_FUNCTION_ALLOW_BUILTIN` omgevingsvariabele.

```bash
ssh redactielinks@100.77.5.104

# Ophalen van bestaande WEBHOOK_URL
WEBHOOK_URL=$(docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' 2>/dev/null | grep WEBHOOK_URL | cut -d= -f2)

# Als WEBHOOK_URL leeg is: ophalen via Tailscale
[ -z "$WEBHOOK_URL" ] && WEBHOOK_URL=$(tailscale status --json \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")

# Container stoppen en herstart met NODE_FUNCTION_ALLOW_BUILTIN
docker stop n8n && docker rm n8n

docker run -d \
    --name n8n \
    --restart always \
    -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path \
    n8nio/n8n:latest

echo "n8n herstart met fs-module toegang."
```

### Fase 3: Nieuwe workflow importeren in n8n

1. Open n8n: **http://100.77.5.104:5678**
2. Hamburger-menu → **Import from file**
3. Selecteer `docs/angie/workflow-second-brain.json`
4. Koppel de Telegram credential in de drie Telegram-nodes (Trigger, Reply)
5. Controleer LLM-endpoint in **"LLM: Classificeer"** node
6. Klik **Activate** (toggle rechtsboven)

### Fase 4: Syncthing installeren voor sync naar MacBook

**Op Pi 5:**
```bash
ssh redactielinks@100.77.5.104
bash ~/n8n/docs/angie/setup-syncthing-pi.sh
```

Het script installeert Syncthing, start het als systemd-service, en print je Pi 5 Device ID.

**Op MacBook:**
```bash
brew install syncthing
brew services start syncthing
# Open UI: http://localhost:8384
```

**Syncthing koppelen (beide kanten):**

1. MacBook Syncthing UI (http://localhost:8384):
   - **Add Remote Device** → Device ID van Pi 5 → Name: `Pi5-n8n`

2. Pi 5 Syncthing UI (http://100.77.5.104:8384):
   - **Add Folder** → `obsidian-vault` → Path: `/home/redactielinks/n8n-obsidian-share`
   - Share with: MacBook (accepteer het verbindingsverzoek)

3. MacBook Syncthing UI:
   - Accepteer de shared folder
   - Stel lokaal pad in: `~/ObsidianVault` (of een bestaand pad)

4. Obsidian op MacBook: **Open folder as vault** → selecteer `~/ObsidianVault`

---

## Workflow: Complete Commandoreferentie

| Commando | Actie | Obsidian-pad |
|---|---|---|
| `/notitie [tekst]` | Nieuwe notitie | `Inbox/[ts]-notitie.md` |
| `/taak [tekst]` | Taak-checkbox | `Inbox/[ts]-taak.md` |
| `/idee [tekst]` | Idee-notitie | `Inbox/[ts]-idee.md` |
| `/dagboek [tekst]` | Append aan dagboek | `Dagboek/YYYY-MM-DD.md` |
| `/zoek [query]` | Grep door vault | — (reply naar Telegram) |
| `/help` | Commandolijst | — (reply naar Telegram) |
| *(vrije tekst)* | LLM classificeert | `Inbox/[ts]-[categorie].md` |

**Bestandsnaam-schema:** `YYYYMMDDHHMMSS-[type].md`  
Voorbeeld: `20240615143022-taak.md`

---

## n8n Workflow: Node-architectuur

```
Telegram Trigger
    │
    ▼
Parse Command (Code)
    ├── Detecteert prefix-commando's
    ├── Bouwt obsidianContent + filepath voor notitie/taak/idee
    ├── Zet replyText voor help/leeg/voice
    └── Geeft dateStr, timestamp, fileTs, VAULT door
    │
    ▼
If: Is Early Exit? (help / leeg / voice)
    ├── TRUE ──────────────────────────────────────────► Telegram: Reply
    └── FALSE
            │
            ▼
        If: Is Zoek?
            ├── TRUE → Zoek in Obsidian (Code, uses fs) ──────────────► Telegram: Reply
            └── FALSE
                    │
                    ▼
                If: Is Dagboek?
                    ├── TRUE → Schrijf naar Dagboek (Code, fs.append) ► Telegram: Reply
                    └── FALSE
                            │
                            ▼
                        If: Has Known Prefix? (notitie/taak/idee)
                            ├── TRUE → Schrijf naar Obsidian ─────────► Telegram: Reply
                            └── FALSE (vrij)
                                    │
                                    ▼
                                LLM: Classificeer (HTTP POST Mac Mini)
                                    │
                                    ▼
                                Parse LLM Response (Code)
                                    │
                                    ▼
                                Schrijf naar Obsidian ──────────────► Telegram: Reply
```

---

## Omgevingsvariabelen: Compleet Overzicht Docker Container

| Variabele | Waarde | Doel |
|---|---|---|
| `N8N_SECURE_COOKIE` | `false` | HTTP-toegang via lokaal netwerk |
| `WEBHOOK_URL` | `https://[pi5].ts.net` | Telegram webhook registratie |
| `NODE_FUNCTION_ALLOW_BUILTIN` | `fs,path` | Toegang tot filesystem in Code nodes |

---

## Troubleshooting

### `require('fs') is not defined` in Code node

**Oorzaak:** `NODE_FUNCTION_ALLOW_BUILTIN` ontbreekt in de Docker container.  
**Fix:**
```bash
docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | grep NODE_FUNCTION
```
Als leeg: herstart container met de variabele (zie Fase 2 hierboven).

---

### Dagboek-bestanden worden aangemaakt maar niet geappend

**Oorzaak:** Code node heeft geen schrijfrechten op de vault-map.  
**Controle op Pi 5:**
```bash
ls -la /home/redactielinks/n8n-obsidian-share/Dagboek/
```
**Fix:**
```bash
chmod -R 777 /home/redactielinks/n8n-obsidian-share/
```

---

### Zoekresultaten zijn leeg terwijl bestanden bestaan

**Oorzaak 1:** Bestanden staan niet in de vault-map die de container ziet.  
**Controle:**
```bash
docker exec n8n ls /home/node/obsidian-share/Inbox/
```

**Oorzaak 2:** Zoekterm te specifiek. De `/zoek` functie is case-insensitive, maar zoekt op exact substrings.  
**Tip:** Zoek op kortere sleutelwoorden.

---

### Syncthing synchroniseert niet

**Controle Pi 5:**
```bash
systemctl --user status syncthing
curl -s http://100.77.5.104:8384/rest/system/status 2>/dev/null | python3 -m json.tool | head -10
```

**Controle MacBook:**
```bash
brew services list | grep syncthing
open http://localhost:8384
```

**Tip:** Syncthing synct via Tailscale IPs. Zorg dat beide apparaten op Tailscale zitten en elkaar kunnen pingen:
```bash
ping 100.111.45.105  # MacBook
ping 100.77.5.104    # Pi 5
```

---

### LLM classificeert slecht of inconsistent

**Diagnose:** Test het LLM-endpoint direct:
```bash
curl -s -X POST http://100.99.111.39:27124/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{
    "model": "local-model",
    "messages": [
      {"role":"system","content":"Geef uitsluitend JSON: {\"category\":\"notitie|taak|idee|dagboek\",\"title\":\"korte titel\",\"content\":\"markdown inhoud\",\"tags\":[]}"},
      {"role":"user","content":"morgen presentatie voorbereiden voor client"}
    ],
    "stream": false
  }' | python3 -m json.tool
```

Als het model geen JSON teruggeeft: verhoog de temperature of pas de system prompt aan in de **"LLM: Classificeer"** node.

---

## Herstel na Calamiteit

```bash
# 1. Vault herstellen vanuit backup
rsync -av backup/n8n-obsidian-share/ /home/redactielinks/n8n-obsidian-share/

# 2. n8n container opnieuw starten
WEBHOOK_URL=$(tailscale status --json \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")

docker stop n8n 2>/dev/null; docker rm n8n 2>/dev/null
docker run -d --name n8n --restart always \
    -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path \
    n8nio/n8n:latest

# 3. Tailscale Funnel herstellen
sudo tailscale funnel --bg 5678

# 4. Syncthing herstellen
systemctl --user start syncthing

# 5. Workflow opnieuw importeren in n8n UI
# → Import from file → workflow-second-brain.json
```

---

## Gerelateerde Bestanden

| Bestand | Doel |
|---|---|
| `docs/angie/init-obsidian-vault.sh` | Vault-structuur aanmaken op Pi 5 |
| `docs/angie/setup-syncthing-pi.sh` | Syncthing installeren op Pi 5 |
| `docs/angie/workflow-second-brain.json` | n8n workflow (importeerbaar) |
| `docs/angie/n8n-docker-start.sh` | n8n container starten met alle variabelen |
| `docs/angie/setup-https-tunnel.sh` | HTTPS tunnel via Tailscale Funnel |
| `docs/angie/DOSSIER-HTTPS-TUNNEL.md` | Dossier HTTPS tunnel |
| `docs/angie/DOSSIER-OBSIDIAN-KOPPELING.md` | Dit dossier |
