# Technisch Dossier — Project Angie: Multi-Device Obsidian Sync

**Status:** Gereed voor installatie  
**Datum:** 2026-06-15  
**Doel:** Obsidian vault beschikbaar op alle 4 apparaten

---

## Overzicht: Ster-topologie via Tailscale

```
                    ┌─────────────────────────┐
                    │  Raspberry Pi 5          │
                    │  100.77.5.104            │
                    │  Syncthing (hub)         │
                    │  /home/redactielinks/    │
                    │    n8n-obsidian-share/   │
                    └──────────┬──────────────┘
                               │ Syncthing via Tailscale
           ┌───────────────────┼──────────────────────┐
           │                   │                      │
           ▼                   ▼                      ▼
  MacBook Pro             Mac Mini              iPhone
  100.111.45.105          100.99.111.39         (Tailscale IP)
  ~/ObsidianVault/        ~/ObsidianVault/      "On My iPhone/
  Syncthing               Syncthing              Obsidian/"
  Obsidian desktop        Obsidian desktop      Möbius Sync
                          (+ LLM context)       Obsidian iOS
```

**Pi 5 is de hub:** altijd aan, altijd beschikbaar, n8n schrijft hier. Alle andere apparaten syncronen via Pi 5.

---

## Status per apparaat

| Apparaat | IP | Syncthing | Obsidian | Status |
|---|---|---|---|---|
| Raspberry Pi 5 | 100.77.5.104 | ✅ Hub | n.v.t. (n8n schrijft) | Klaar |
| MacBook Pro | 100.111.45.105 | Handmatig instellen | Desktop | Installeren |
| Mac Mini | 100.99.111.39 | Handmatig instellen | Desktop (+ LLM context) | Installeren |
| iPhone | Tailscale IP | Möbius Sync app | iOS | Installeren |

---

## Fase 1: MacBook Pro

```bash
# 1. Syncthing installeren
brew install syncthing
brew services start syncthing

# 2. Vault map aanmaken
mkdir -p ~/ObsidianVault
```

**In Syncthing UI op MacBook (http://localhost:8384):**
- **Add Remote Device** → Device ID van Pi 5 (zie: `ssh redactielinks@100.77.5.104 syncthing --device-id`)
- Name: `Pi5-n8n`

**In Syncthing UI op Pi 5 (http://100.77.5.104:8384):**
- Bij de folder `obsidian-vault`: **Edit** → **Sharing** → vink MacBook aan
- Device ID van MacBook opvragen: `syncthing --device-id` op MacBook

**Terug in MacBook Syncthing UI:**
- Accepteer de folder van Pi 5
- Local Path: `~/ObsidianVault`

**Obsidian op MacBook:**
- Download: https://obsidian.md
- **Open folder as vault** → selecteer `~/ObsidianVault`

---

## Fase 2: Mac Mini

```bash
# SSH naar Mac Mini
ssh redactielinks@100.99.111.39

# Setup script uitvoeren
bash ~/n8n/docs/angie/setup-syncthing-mac-mini.sh
```

Het script installeert Syncthing (via Homebrew of directe binary), start het als LaunchAgent (autostart), maakt `~/ObsidianVault` aan, en print de Device ID.

**In Syncthing UI op Pi 5 (http://100.77.5.104:8384):**
- **Add Remote Device** → Device ID van Mac Mini
- Name: `MacMini-LLM`
- folder `obsidian-vault` → **Edit** → **Sharing** → vink `MacMini-LLM` aan

**In Mac Mini Syncthing UI (http://localhost:8384 of http://100.99.111.39:8384):**
- Accepteer het verbindingsverzoek van Pi 5
- Accepteer de gedeelde folder
- Local Path: `~/ObsidianVault`

**Obsidian op Mac Mini (optioneel):**
```bash
brew install --cask obsidian
# Open → Open folder as vault → ~/ObsidianVault
```

---

## Fase 3: iPhone

### Optie A — Möbius Sync (aanbevolen, €3-4 eenmalig)

Möbius Sync is een iOS Syncthing-client. Syncthing zelf is volledig FOSS; alleen de iOS wrapper is betaald. Dit is de enige volwaardige iOS Syncthing-client.

**Stap 1: Möbius Sync installeren**
- App Store → zoek "Möbius Sync"
- Installeer en open de app

**Stap 2: Device ID ophalen**
- In Möbius Sync: tik op het ⚙️ icoontje → **Device ID**
- Noteer de ID (of gebruik de QR-code)

**Stap 3: iPhone toevoegen aan Pi 5 Syncthing**
- Open Pi 5 Syncthing UI: **http://100.77.5.104:8384**
- **Add Remote Device** → plak de Möbius Sync Device ID
- Name: `iPhone-Angie`
- Ga naar folder `obsidian-vault` → **Edit** → **Sharing** → vink `iPhone-Angie` aan

**Stap 4: Folder accepteren in Möbius Sync**
- In Möbius Sync: accepteer het verbindingsverzoek van Pi 5
- **Add Folder** → accepteer de `obsidian-vault` folder
- Kies als lokale map: **"On My iPhone" → maak nieuwe map "Obsidian" aan**
- Wacht tot de initiële sync klaar is (kan minuten duren bij grote vault)

**Stap 5: Obsidian iOS openen op de gesynchroniseerde vault**
- Installeer Obsidian uit de App Store (gratis)
- Open Obsidian → **Open folder as vault**
- Navigeer in de bestandskiezer naar **"On My iPhone" → "Obsidian"**
- Selecteer de map

> **Werkwijze:** Möbius Sync synct op de achtergrond wanneer de iPhone actief is en WiFi/Tailscale beschikbaar is. De vault is altijd up-to-date als de app regelmatig op de voorgrond komt.

**Tailscale op iPhone (als nog niet geïnstalleerd):**
- App Store → "Tailscale" → installeer
- Log in met hetzelfde Tailscale-account
- De iPhone krijgt automatisch een Tailscale IP

### Optie B — Volledig FOSS via Gitea + Obsidian Git (gratis, complexer)

Voor wie niet wil betalen voor Möbius Sync. Vereist het opzetten van Gitea (self-hosted Git server) op de Ubuntu Server.

**Architectuur:**
```
Ubuntu Server (100.90.10.15)
└── Gitea Docker container
    └── obsidian-vault repository

MacBook / Mac Mini: Obsidian Git plugin → auto-sync met Gitea
iPhone: Working Copy app (iOS Git client, gratis basisversie) → sync met Gitea
```

**Beknopte setup Gitea op Ubuntu Server:**
```bash
ssh redactielinks@100.90.10.15

docker run -d \
    --name gitea \
    --restart always \
    -p 3000:3000 \
    -p 2222:22 \
    -v /home/redactielinks/gitea-data:/data \
    gitea/gitea:latest

# Open: http://100.90.10.15:3000
# Maak account + repository 'obsidian-vault' aan
# Push vault: cd ~/ObsidianVault && git init && git remote add origin http://100.90.10.15:3000/redactielinks/obsidian-vault.git && git push -u origin main
```

**Obsidian Git plugin (MacBook + Mac Mini):**
- In Obsidian: **Community Plugins** → zoek "Obsidian Git" → installeer
- Instellingen: remote URL = `http://100.90.10.15:3000/redactielinks/obsidian-vault.git`
- Auto-sync interval instellen (bijv. elke 5 minuten)

**iPhone (Working Copy):**
- App Store → "Working Copy" (gratis, push vereist betaalde versie)
- Clone de Gitea repository
- Obsidian iOS → open Working Copy-map als vault

> **Nadeel Git-aanpak:** conflicten bij gelijktijdige edits op meerdere apparaten vereisen handmatige merge. Voor een schrijf-heavy Second Brain is Syncthing robuuster.

---

## Syncthing Apparaten: Snel Overzicht

### Alle Device IDs ophalen

```bash
# Pi 5
ssh redactielinks@100.77.5.104 "syncthing --device-id"

# MacBook Pro (in terminal op MacBook)
syncthing --device-id

# Mac Mini
ssh redactielinks@100.99.111.39 "syncthing --device-id"

# iPhone: zie Möbius Sync app → ⚙️ → Device ID
```

### Syncthing status controleren

```bash
# Pi 5 (hub)
curl -s http://100.77.5.104:8384/rest/system/status \
    -H "X-API-Key: $(grep apikey ~/.config/syncthing/config.xml | head -1 | grep -o '[A-Za-z0-9]*' | tail -1)" \
    | python3 -m json.tool | head -20
```

---

## Samenvatting: Welk apparaat doet wat?

| Apparaat | Schrijft | Leest | Reden |
|---|---|---|---|
| Pi 5 | Ja (n8n) | Nee | Centrale schrijfhub voor Telegram-notities |
| MacBook Pro | Nee (Obsidian) | Ja + edits | Primaire werkplek, verwerkt Inbox |
| Mac Mini | Nee | Ja (LLM context) | LLM kan vault raadplegen voor context |
| iPhone | Via Telegram → n8n | Ja (Obsidian iOS) | Capture via bot, browse via Obsidian |

**Gouden regel:** Telegram-berichten → n8n op Pi 5 → vault. Obsidian op MacBook → verwerken en organiseren. iPhone → lezen en capture via Telegram.

---

## Troubleshooting

### Syncthing "Out of Sync" op een apparaat

```bash
# Controleer conflicterende bestanden (eindigend op .sync-conflict)
ssh redactielinks@100.77.5.104 "find /home/redactielinks/n8n-obsidian-share -name '*.sync-conflict*'"
```

Syncthing maakt automatisch `.sync-conflict` bestanden aan bij echte conflicten. Verwijder de ongewenste versie en houd de juiste.

### Möbius Sync synchroniseert niet via Tailscale

**Controle:**
1. Is Tailscale actief op iPhone? → Tailscale app → check verbinding
2. Ping Pi 5 vanuit Möbius Sync? → In Möbius Sync: Remote Devices → Pi 5 status
3. Firewall op Pi 5? → `sudo ufw status` — Syncthing gebruikt poort 22000 (TCP/UDP)

```bash
# Syncthing poort openen op Pi 5 als ufw actief is
sudo ufw allow 22000/tcp
sudo ufw allow 22000/udp
sudo ufw allow 21027/udp  # Syncthing discovery
```

### Obsidian iOS ziet de vault niet in Möbius Sync map

**Oorzaak:** Möbius Sync heeft de bestanden naar de verkeerde locatie gesynchroniseerd.

**Controle in iOS Files app:**
- Open **Bestanden** → **Op mijn iPhone** → zoek de Obsidian-map
- Als niet zichtbaar: ga in Möbius Sync naar de folder-instellingen en controleer het pad

**Fix:** In Obsidian iOS: **Open another vault** → **Open folder as vault** → navigeer opnieuw naar de juiste map.

### Mac Mini Syncthing UI niet bereikbaar via browser

Mac Mini Syncthing UI draait standaard op 127.0.0.1:8384 (alleen lokaal).

Om het via Tailscale te bereiken:
```bash
# Op Mac Mini: config aanpassen
sed -i '' 's/127.0.0.1:8384/0.0.0.0:8384/' ~/Library/Application\ Support/Syncthing/config.xml
brew services restart syncthing
```

Daarna bereikbaar op: **http://100.99.111.39:8384**

---

## Gerelateerde Bestanden

| Bestand | Doel |
|---|---|
| `docs/angie/setup-syncthing-pi.sh` | Syncthing installeren op Pi 5 (hub) |
| `docs/angie/setup-syncthing-mac-mini.sh` | Syncthing installeren op Mac Mini |
| `docs/angie/DOSSIER-MULTI-DEVICE-SYNC.md` | Dit dossier |
| `docs/angie/DOSSIER-OBSIDIAN-KOPPELING.md` | Obsidian vault + workflow dossier |
