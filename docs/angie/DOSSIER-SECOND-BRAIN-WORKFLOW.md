# Technisch Dossier — Project Angie: Second Brain Workflow

**Status:** Gereed voor import  
**Datum:** 2026-06-15  
**Workflow-bestand:** `docs/angie/workflow-second-brain.json`

---

## Wat doet deze workflow?

Elke keer dat je een bericht stuurt naar je Telegram-bot op je iPhone, verwerkt de workflow dit automatisch:

1. Detecteert of je een commando-prefix gebruikt of vrije tekst stuurt
2. Geeft vrije tekst door aan je lokale LLM op de Mac Mini ter classificatie
3. Bouwt een gestructureerde Obsidian-notitie met YAML frontmatter
4. Schrijft het bestand weg naar de gedeelde map op de Pi 5
5. Stuurt je een bevestiging terug in Telegram

---

## Beschikbare Commando's (vanuit iPhone)

| Commando | Alias | Gedrag |
|---|---|---|
| `/notitie [tekst]` | `/note` | Slaat op als losse notitie |
| `/taak [tekst]` | `/todo`, `/task` | Slaat op als checkbox-taak (`- [ ]`) |
| `/idee [tekst]` | `/idea` | Slaat op als idee-notitie |
| `/dagboek [tekst]` | `/journal` | Slaat op als dagboek-entry |
| `/help` | `/commando`, `/start` | Stuurt commandolijst terug |
| *(vrije tekst zonder prefix)* | — | LLM classificeert en structureert automatisch |

---

## Workflow-architectuur

```
iPhone (Telegram)
        |
        | HTTPS via Tailscale Funnel
        v
Telegram Trigger (Pi 5, n8n)
        |
        v
Code: Parse Command
├─ Detecteert prefix (/notitie, /taak, /idee, /dagboek)
├─ Bouwt YAML frontmatter + Obsidian markdown voor bekende commando's
└─ Extraheert content voor vrije tekst
        |
        v
If: Is Help Command?
├─ JA → Telegram: stuur helpbericht (flow eindigt hier)
└─ NEE → If: Has Command Prefix?
              |
    ┌─────────┴──────────┐
    │ JA (direct)        │ NEE (vrije tekst)
    ↓                    ↓
    (obsidianContent     HTTP POST →
     al klaar)          Mac Mini LLM
                        (100.99.111.39:27124)
                             |
                             ↓
                        Code: Parse LLM Response
                        (bouwt Obsidian markdown uit JSON)
    │                        │
    └──────────┬─────────────┘
               ↓
    Code: Prepare Binary (tekst → binary buffer)
               |
               ↓
    Write File to Disk
    /home/node/obsidian-share/inbox/[timestamp]-[categorie].md
               |
               ↓
    Telegram: Bevestigingsbericht
```

---

## Bestandsstructuur in Obsidian

Alle notities komen terecht in de `inbox/` map:

```
n8n-obsidian-share/
└── inbox/
    ├── 20240615143022-notitie.md
    ├── 20240615143501-taak.md
    ├── 20240615150000-idee.md
    └── 20240615160000-dagboek.md
```

**YAML frontmatter voorbeeld (directe notitie):**
```yaml
---
tags:
  - notitie
  - telegram
datum: 2024-06-15 14:30
bron: telegram
---

De inhoud van je bericht staat hier.
```

**YAML frontmatter voorbeeld (LLM-verwerkt):**
```yaml
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

[gestructureerde inhoud door LLM geschreven]
```

---

## Importeren in n8n

### Stap 1: Maak de inbox-map aan op de Pi 5

```bash
ssh redactielinks@100.77.5.104
mkdir -p /home/redactielinks/n8n-obsidian-share/inbox
```

### Stap 2: Importeer de workflow

1. Open n8n: **http://100.77.5.104:5678**
2. Klik linksbovenin op het hamburger-menu → **Import from file**
3. Selecteer `docs/angie/workflow-second-brain.json`
4. Workflow verschijnt nu als concept

### Stap 3: Koppel de Telegram credential

Elke node met een Telegram-icoon heeft een credential nodig:

1. Klik op de **Telegram Trigger** node
2. Klik op het credential-veld → **Create New**
3. Vul in:
   - **Credential Name:** `Angie Telegram Bot`
   - **Access Token:** `8622180504:AAF-WK0seg3n8I4VGUS5xo_dQgw9PXGVyUU`
4. Sla op → n8n genereert automatisch een credential-ID
5. Herhaal dit voor de **Telegram: Help Message** en **Telegram: Bevestiging** nodes, selecteer dezelfde credential

> **Tip:** Na het aanmaken van de credential kun je in de andere Telegram-nodes dezelfde credential selecteren uit het dropdown-menu — je hoeft het token maar één keer in te vullen.

### Stap 4: Controleer het LLM-endpoint

In de node **LLM: Classificeer & Structureer**:

- **Huidige instelling:** `http://100.99.111.39:27124/v1/chat/completions`
- Pas het pad aan op basis van wat er op je Mac Mini draait:

| Software | Juist pad |
|---|---|
| LM Studio | `/v1/chat/completions` (standaard) |
| Ollama (chat) | `/api/chat` |
| Ollama (generate) | `/api/generate` |
| Aangepaste server | Test eerst: `curl -X POST http://100.99.111.39:27124/...` |

**Test het endpoint via Tailscale vanaf de Pi 5:**
```bash
ssh redactielinks@100.77.5.104
curl -s -X POST http://100.99.111.39:27124/v1/chat/completions \
  -H 'Content-Type: application/json' \
  -d '{"model":"local-model","messages":[{"role":"user","content":"Hallo"}],"stream":false}' \
  | python3 -m json.tool
```

Als je een antwoord krijgt, klopt het pad. Als niet, probeer het pad aan te passen.

### Stap 5: Activeer de workflow

1. Klik de **Activate**-toggle rechtsboven (wordt groen)
2. n8n registreert automatisch de webhook bij Telegram via de WEBHOOK_URL die je in de Docker-container hebt ingesteld

### Stap 6: Test vanuit Telegram

Open je Telegram-app op iPhone en stuur naar de bot:

```
/help
```

Je zou een commandolijst terug moeten ontvangen. Stuur daarna:

```
/taak afspraken plannen voor volgende week
```

Controleer op de Pi 5:
```bash
ls -la /home/redactielinks/n8n-obsidian-share/inbox/
cat /home/redactielinks/n8n-obsidian-share/inbox/*-taak.md
```

---

## LLM Systeem-Prompt (voor Mac Mini)

De workflow stuurt deze instructie mee aan het lokale LLM:

```
Je bent een Second Brain assistent. Classificeer en structureer de 
gebruikersinput als een Obsidian-notitie. Geef je antwoord UITSLUITEND 
als geldig JSON in dit formaat:

{
  "category": "notitie|taak|idee|dagboek",
  "title": "korte beschrijvende titel",
  "content": "gestructureerde markdown inhoud van de notitie",
  "tags": ["relevante", "tags"]
}

Geen uitleg, geen tekst buiten het JSON-object.
```

Het LLM-model krijgt `temperature: 0.3` mee voor consistente, structurele output.

---

## Troubleshooting

### Workflow wordt niet getriggerd na activering

**Oorzaak:** n8n kent de WEBHOOK_URL niet of de Tailscale Funnel staat niet aan.

**Controle:**
```bash
# Op Pi 5:
tailscale funnel status
docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | grep WEBHOOK
```

Als WEBHOOK_URL ontbreekt: zie `DOSSIER-HTTPS-TUNNEL.md` → herstart n8n container met de juiste variabele.

---

### Telegram geeft geen antwoord

**Oorzaak 1:** Credential niet goed gekoppeld in alle drie de Telegram-nodes.  
**Fix:** Controleer alle drie nodes (Trigger, Help, Bevestiging) — ze moeten allemaal dezelfde credential gebruiken.

**Oorzaak 2:** n8n workflow staat op "inactive".  
**Fix:** Klik de Activate-toggle rechtsboven in de workflow-editor.

---

### Bestand wordt niet aangemaakt in Obsidian

**Oorzaak 1:** Pad `/home/node/obsidian-share/inbox/` bestaat niet.  
**Fix op Pi 5:**
```bash
mkdir -p /home/redactielinks/n8n-obsidian-share/inbox
```

**Oorzaak 2:** Volume-mount ontbreekt in de Docker-container.  
**Controle:**
```bash
docker inspect n8n --format '{{json .Mounts}}' | python3 -m json.tool
```
Je moet `/home/redactielinks/n8n-obsidian-share` zien als mount.

---

### LLM-node geeft fout (timeout/connection refused)

**Oorzaak:** Mac Mini LLM staat uit of het endpoint-pad klopt niet.  
**Controle vanaf Pi 5:**
```bash
curl -s http://100.99.111.39:27124/status
```

Als dit faalt: schakel de LLM-server in op de Mac Mini.

Als het endpoint-pad anders is: open de **LLM: Classificeer & Structureer** node in n8n en pas de URL aan.

**Fallback:** De workflow werkt ook zonder LLM — gebruik gewoon altijd een prefix (/notitie, /taak etc.) en de LLM-stap wordt overgeslagen.

---

## Uitbreiding: Obsidian Vault Synchronisatie

Op dit moment schrijft n8n naar de gedeelde map op de Pi 5. Om deze bestanden ook op je MacBook te zien in Obsidian:

**Optie A: Syncthing (FOSS, aanbevolen)**
```bash
# Installeer op Pi 5
sudo apt install syncthing
# Configureer om /home/redactielinks/n8n-obsidian-share te synchroniseren met MacBook
```

**Optie B: Via Tailscale (directe mount)**
Op MacBook:
```bash
sshfs redactielinks@100.77.5.104:/home/redactielinks/n8n-obsidian-share ~/ObsidianInbox
```

**Optie C: NFS mount via Tailscale**
Wordt beschreven in een apart dossier zodra Syncthing- of NFS-integratie wordt opgezet.

---

## Gerelateerde Bestanden

| Bestand | Doel |
|---|---|
| `docs/angie/workflow-second-brain.json` | Importeerbare n8n workflow |
| `docs/angie/setup-https-tunnel.sh` | HTTPS Tunnel setup (vereist voor Telegram) |
| `docs/angie/DOSSIER-HTTPS-TUNNEL.md` | Dossier HTTPS Tunnel |
| `docs/angie/DOSSIER-SECOND-BRAIN-WORKFLOW.md` | Dit dossier |
