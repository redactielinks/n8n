#!/bin/bash
# ============================================================
# Project Angie — HTTPS Tunnel Setup voor Telegram Webhooks
# Machine: Raspberry Pi 5 (100.77.5.104)
# Methode: Tailscale Funnel (FOSS, gratis, geen VPS vereist)
# ============================================================
# Voer dit script uit OP de Raspberry Pi 5:
#   ssh redactielinks@100.77.5.104
#   bash setup-https-tunnel.sh
# ============================================================

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }
err()  { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo ""
echo "============================================================"
echo "  Project Angie — HTTPS Tunnel Installer"
echo "  Raspberry Pi 5 @ 100.77.5.104"
echo "============================================================"
echo ""

# ------------------------------------------------------------
# STAP 0: Vereisten controleren
# ------------------------------------------------------------
info "STAP 0: Vereisten controleren..."

command -v tailscale >/dev/null 2>&1 || err "Tailscale is niet geïnstalleerd. Installeer eerst: curl -fsSL https://tailscale.com/install.sh | sh"
command -v docker >/dev/null 2>&1    || err "Docker is niet geïnstalleerd."

TAILSCALE_VERSION=$(tailscale version | head -1)
log "Tailscale versie: $TAILSCALE_VERSION"

TAILSCALE_STATUS=$(tailscale status 2>&1 || true)
if echo "$TAILSCALE_STATUS" | grep -q "Logged out\|not running"; then
    err "Tailscale is niet verbonden. Start eerst: sudo tailscale up"
fi
log "Tailscale is actief en verbonden."

# ------------------------------------------------------------
# STAP 1: Tailscale FQDN ophalen
# ------------------------------------------------------------
info "STAP 1: Tailscale hostname ophalen..."

TAILSCALE_FQDN=$(tailscale status --json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Self']['DNSName'].rstrip('.'))" \
    2>/dev/null) || err "Kan Tailscale FQDN niet ophalen. Controleer of MagicDNS actief is in de Tailscale admin console."

if [[ -z "$TAILSCALE_FQDN" ]]; then
    err "Lege FQDN ontvangen. Zorg dat MagicDNS ingeschakeld is: https://login.tailscale.com/admin/dns"
fi

WEBHOOK_URL="https://${TAILSCALE_FQDN}"
log "Tailscale FQDN: $TAILSCALE_FQDN"
log "Webhook URL wordt: $WEBHOOK_URL"

# ------------------------------------------------------------
# STAP 2: HTTPS-certificaten activeren (vereiste controle)
# ------------------------------------------------------------
info "STAP 2: HTTPS-certificaatondersteuning controleren..."

warn "HANDMATIGE ACTIE VEREIST (als je dit nog niet gedaan hebt):"
echo ""
echo "  1. Ga naar: https://login.tailscale.com/admin/dns"
echo "  2. Schakel 'MagicDNS' in (als nog niet actief)"
echo "  3. Klik op 'Enable HTTPS Certificates'"
echo "  4. Sla op"
echo ""
read -rp "Heb je HTTPS Certificates ingeschakeld in de Tailscale admin console? [j/n]: " HTTPS_ENABLED

if [[ ! "$HTTPS_ENABLED" =~ ^[jJ]$ ]]; then
    warn "Activeer eerst HTTPS Certificates en herstart dit script."
    echo "URL: https://login.tailscale.com/admin/dns"
    exit 1
fi

# Test certificaataanvraag
info "Tailscale HTTPS-certificaat aanvragen voor $TAILSCALE_FQDN ..."
sudo tailscale cert "$TAILSCALE_FQDN" >/dev/null 2>&1 && log "HTTPS-certificaat succesvol verkregen." \
    || warn "Certificaattest mislukt — Funnel werkt mogelijk toch als HTTPS-terminatie via Tailscale-servers verloopt."

# ------------------------------------------------------------
# STAP 3: Tailscale Funnel activeren (permanent, achtergrond)
# ------------------------------------------------------------
info "STAP 3: Tailscale Funnel activeren voor poort 5678..."

# Funnel: stuurt HTTPS-verkeer van internet door naar lokale poort 5678
# --bg slaat de configuratie permanent op in Tailscale (overleeft reboots)
sudo tailscale funnel --bg 5678

log "Tailscale Funnel actief op poort 5678."

# Status verificatie
echo ""
info "Huidige Funnel-configuratie:"
tailscale funnel status 2>/dev/null || tailscale serve status 2>/dev/null || warn "Kan status niet ophalen, maar Funnel is ingesteld."

# ------------------------------------------------------------
# STAP 4: n8n Docker-container herstart met WEBHOOK_URL
# ------------------------------------------------------------
info "STAP 4: n8n Docker-container bijwerken met WEBHOOK_URL..."

if docker ps -a --format '{{.Names}}' | grep -q "^n8n$"; then
    warn "Bestaande n8n container stoppen en verwijderen..."
    docker stop n8n && docker rm n8n
    log "Oude n8n container verwijderd."
fi

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

log "n8n container gestart met WEBHOOK_URL=${WEBHOOK_URL}"

# ------------------------------------------------------------
# STAP 5: Verificatie
# ------------------------------------------------------------
info "STAP 5: Installatie verificeren..."

sleep 5

# Controleer of n8n draait
if docker ps --format '{{.Names}}' | grep -q "^n8n$"; then
    log "n8n container draait."
else
    err "n8n container is niet gestart. Controleer: docker logs n8n"
fi

# Controleer WEBHOOK_URL in de container
WEBHOOK_CHECK=$(docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' | grep WEBHOOK_URL || true)
if [[ -n "$WEBHOOK_CHECK" ]]; then
    log "WEBHOOK_URL correct ingesteld in container: $WEBHOOK_CHECK"
else
    err "WEBHOOK_URL ontbreekt in container. Herstart het script."
fi

# Bereikbaarheidstest lokaal
HEALTH=$(curl -sf "http://localhost:5678/healthz" 2>/dev/null && echo "bereikbaar" || echo "niet bereikbaar")
if [[ "$HEALTH" == "bereikbaar" ]]; then
    log "n8n lokaal bereikbaar op poort 5678."
else
    warn "n8n lokaal nog niet bereikbaar (kan nog opstarten, wacht 10 seconden en check: curl http://localhost:5678/healthz)"
fi

echo ""
echo "============================================================"
echo -e "${GREEN}  INSTALLATIE VOLTOOID${NC}"
echo "============================================================"
echo ""
echo "  Webhook URL (voor Telegram & n8n Trigger node):"
echo -e "  ${BLUE}${WEBHOOK_URL}${NC}"
echo ""
echo "  Volgende stap in n8n:"
echo "  1. Open n8n: http://100.77.5.104:5678"
echo "  2. Open workflow 'Angie Telegram naar Obsidian'"
echo "  3. Klik op de Telegram Trigger node"
echo "  4. Klik op 'Execute Node' om te testen"
echo "  5. Klik 'Activate' (toggle rechtsbovenin)"
echo ""
echo "  De workflow is nu bereikbaar voor Telegram via:"
echo -e "  ${BLUE}${WEBHOOK_URL}/webhook/...${NC}"
echo ""
