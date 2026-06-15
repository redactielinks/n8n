# Technisch Dossier — Project Angie: HTTPS Tunnel voor Telegram Webhooks

**Status:** Opgelost  
**Datum:** 2026-06-15  
**Betrokken machine:** Raspberry Pi 5 (`redactielinks@100.77.5.104`)

---

## Probleem

Telegram accepteert alleen HTTPS-URLs als webhook-endpoint. De n8n-instantie op de Pi 5 draait lokaal via HTTP, waardoor de Telegram Trigger node niet geactiveerd kon worden. Foutmelding:

```
Bad Request: bad webhook: An HTTPS URL must be provided for webhook
```

---

## Gekozen Oplossing: Tailscale Funnel

**Tailscale Funnel** is de FOSS-conforme oplossing voor dit probleem. Het routeert inkomend HTTPS-verkeer van internet via de Tailscale-servers naar een lokale poort, zonder dat je een VPS, eigen domein, of open poorten in je router nodig hebt.

### Waarom Tailscale Funnel?

| Criterium | Tailscale Funnel |
|---|---|
| Open-source client | Ja (github.com/tailscale/tailscale, BSD-3) |
| Gratis | Ja (Personal/Hobbyist plan) |
| Vereist externe VPS | Nee |
| Permanente URL | Ja (vast gekoppeld aan machine-naam) |
| Automatisch HTTPS/TLS | Ja (Let's Encrypt via Tailscale) |
| Werkt als achtergronddienst | Ja (via Tailscale-daemon, geen extra systemd unit nodig) |
| Vereist open router-poorten | Nee |
| Al in gebruik in dit project | Ja |

### URL-formaat

```
https://<machine-hostname>.<tailnet-naam>.ts.net
```

Voorbeeld voor de Pi 5: `https://raspberrypi.tail1a2b3c.ts.net`

De exacte URL is te vinden met:
```bash
tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))"
```

---

## Architectuuroverzicht

```
Telegram-servers (internet)
        |
        | HTTPS POST naar https://<pi5>.ts.net/webhook/...
        v
  Tailscale-relay (ts.net)
        |
        | TLS-terminatie + doorsturen naar Pi 5
        v
  Raspberry Pi 5 (100.77.5.104)
  Tailscale Funnel luistert op poort 5678
        |
        v
  Docker container: n8n
  Poort 5678 — Telegram Trigger node
        |
        v
  HTTP Request node → Mac Mini LLM (100.99.111.39:27124)
        |
        v
  Read/Write Files node → /home/node/obsidian-share/angie-notitie.md
        |
        v
  Gedeelde map op Pi 5: /home/redactielinks/n8n-obsidian-share/
```

---

## Vereisten (eenmalige setup in Tailscale Admin Console)

Ga naar **https://login.tailscale.com/admin/dns** en zet:
1. **MagicDNS** aan
2. **HTTPS Certificates** aan → klik "Enable HTTPS Certificates"

Dit is een eenmalige handeling. Daarna beheert Tailscale de TLS-certificaten automatisch.

---

## Exacte Commando's (installatie op Pi 5)

### Optie A: Volledig automatisch script

```bash
ssh redactielinks@100.77.5.104
bash <(curl -fsSL https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/setup-https-tunnel.sh)
```

Of na clonen van de repo:

```bash
ssh redactielinks@100.77.5.104
bash ~/n8n/docs/angie/setup-https-tunnel.sh
```

### Optie B: Stap voor stap (handmatig)

**1. Tailscale Funnel activeren (één commando, permanent):**

```bash
sudo tailscale funnel --bg 5678
```

De `--bg` vlag slaat de configuratie op in Tailscale. De Funnel herstart automatisch met de Tailscale-daemon na een reboot — geen aparte systemd-service vereist.

**2. Webhook URL ophalen:**

```bash
WEBHOOK_URL=$(tailscale status --json \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
echo $WEBHOOK_URL
```

**3. Bestaande n8n container stoppen:**

```bash
docker stop n8n && docker rm n8n
```

**4. n8n opnieuw starten met WEBHOOK_URL:**

```bash
docker run -d \
    --name n8n \
    --restart always \
    -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    n8nio/n8n:latest
```

**5. Verificatie:**

```bash
# Controleer of n8n draait
docker ps | grep n8n

# Controleer WEBHOOK_URL in container
docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | grep WEBHOOK

# Test lokale bereikbaarheid
curl -s http://localhost:5678/healthz

# Test externe bereikbaarheid
curl -s "https://<jouw-pi5-fqdn>/healthz"

# Funnel status
tailscale funnel status
```

---

## n8n Workflow Activeren na Tunnel Setup

1. Open n8n in browser: **http://100.77.5.104:5678**
2. Open workflow **"Angie Telegram naar Obsidian"**
3. Klik op de **Telegram Trigger** node
4. Klik **"Execute Node"** — controleer of er geen foutmelding meer is
5. Klik de **Activate**-toggle rechtsbovenin (wordt groen)
6. Stuur een testbericht naar je Telegram-bot
7. Controleer of `/home/redactielinks/n8n-obsidian-share/angie-notitie.md` aangemaakt is

---

## Omgevingsvariabelen: Compleet Overzicht n8n Container

| Variabele | Waarde | Doel |
|---|---|---|
| `N8N_SECURE_COOKIE` | `false` | Staat HTTP-toegang toe via lokaal netwerk |
| `WEBHOOK_URL` | `https://<pi5-fqdn>` | Vertelt n8n welke publieke URL het moet registreren bij Telegram |

---

## Volume Mounts: Compleet Overzicht

| Host pad (Pi 5) | Container pad | Inhoud |
|---|---|---|
| `/home/redactielinks/.n8n` | `/home/node/.n8n` | n8n configuratie, workflows, credentials |
| `/home/redactielinks/n8n-obsidian-share` | `/home/node/obsidian-share` | Gedeelde Obsidian-notities |

---

## Tailscale Funnel: Beheercommando's

```bash
# Status bekijken
tailscale funnel status

# Funnel uitschakelen (als nodig)
sudo tailscale funnel --bg --off

# Funnel opnieuw inschakelen
sudo tailscale funnel --bg 5678

# Tailscale daemon status
sudo systemctl status tailscaled
```

---

## Troubleshooting

### Fout: `funnel: failed to get self HTTPS cert for domain`

**Oorzaak:** HTTPS Certificates niet ingeschakeld in Tailscale admin.  
**Oplossing:** Ga naar https://login.tailscale.com/admin/dns → Enable HTTPS Certificates.

---

### Fout: `Bad Request: bad webhook` nog steeds na activeren Funnel

**Oorzaak 1:** n8n container draait nog zonder `WEBHOOK_URL` omgevingsvariabele.  
**Controle:**
```bash
docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | grep WEBHOOK
```
**Oplossing:** Container stoppen, verwijderen en opnieuw starten met de `-e WEBHOOK_URL=...` vlag.

**Oorzaak 2:** De Funnel staat nog niet actief.  
**Controle:** `tailscale funnel status`  
**Oplossing:** `sudo tailscale funnel --bg 5678`

---

### Fout: n8n bereikbaar lokaal maar niet extern

**Controle:**
```bash
curl -v https://<pi5-fqdn>/healthz
```

**Oorzaak:** Tailscale Funnel wijst naar verkeerde poort of staat niet aan.  
**Oplossing:**
```bash
sudo tailscale funnel --bg --off
sudo tailscale funnel --bg 5678
tailscale funnel status
```

---

### n8n container start niet op na herstart Pi

**Controle:** `docker ps -a | grep n8n`

`--restart always` in het startcommando zorgt dat Docker n8n automatisch herstart. Controleer Docker-status:

```bash
sudo systemctl status docker
docker logs n8n --tail 50
```

---

### Funnel URL onbekend na reboot

```bash
tailscale status --json \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))"
```

De URL verandert nooit zolang je dezelfde Pi 5 op hetzelfde Tailscale-account gebruikt.

---

## Herstel na Calamiteit (Compleet Heropzetscript)

Als je het systeem compleet opnieuw moet inrichten op een nieuwe Pi 5:

```bash
# 1. Tailscale installeren
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up

# 2. Docker installeren
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker redactielinks

# 3. Mappen aanmaken
mkdir -p /home/redactielinks/.n8n
mkdir -p /home/redactielinks/n8n-obsidian-share

# 4. n8n-data herstellen vanuit backup (kopieer .n8n map)
# rsync -av backup/.n8n/ /home/redactielinks/.n8n/

# 5. Tailscale Funnel activeren
# (Eerst HTTPS Certificates inschakelen in Tailscale admin console)
sudo tailscale funnel --bg 5678

# 6. Webhook URL ophalen
WEBHOOK_URL=$(tailscale status --json \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")

# 7. n8n starten
docker run -d \
    --name n8n \
    --restart always \
    -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    n8nio/n8n:latest

echo "Systeem hersteld. n8n beschikbaar op: http://$(tailscale ip -4):5678"
```

---

## Gerelateerde Bestanden in Dit Project

| Bestand | Doel |
|---|---|
| `docs/angie/setup-https-tunnel.sh` | Volledig geautomatiseerd installatiescript |
| `docs/angie/n8n-docker-start.sh` | Minimaal script om n8n te starten met juiste variabelen |
| `docs/angie/DOSSIER-HTTPS-TUNNEL.md` | Dit dossier |
