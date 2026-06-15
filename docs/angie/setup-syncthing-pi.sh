#!/bin/bash
# ============================================================
# Project Angie — Syncthing installeren op Raspberry Pi 5
# Synchroniseert Obsidian vault naar MacBook via Tailscale
# Voer uit OP de Pi 5: ssh redactielinks@100.77.5.104
# ============================================================

set -euo pipefail

VAULT="/home/redactielinks/n8n-obsidian-share"
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo ""
echo "============================================================"
echo "  Project Angie — Syncthing Setup (Pi 5)"
echo "============================================================"
echo ""

# ── Installatie ─────────────────────────────────────────────
info "Syncthing installeren..."

if command -v syncthing >/dev/null 2>&1; then
    log "Syncthing is al geïnstalleerd: $(syncthing --version | head -1)"
else
    # Officiële Syncthing APT repo
    curl -fsSL https://syncthing.net/release-key.gpg \
        | sudo gpg --dearmor -o /usr/share/keyrings/syncthing-archive-keyring.gpg

    echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] \
https://apt.syncthing.net/ syncthing stable" \
        | sudo tee /etc/apt/sources.list.d/syncthing.list >/dev/null

    sudo apt-get update -qq && sudo apt-get install -y syncthing
    log "Syncthing geïnstalleerd: $(syncthing --version | head -1)"
fi

# ── Systemd user service ─────────────────────────────────────
info "Syncthing als systemd user-service inschakelen..."

systemctl --user enable syncthing 2>/dev/null || true
systemctl --user start syncthing 2>/dev/null || true

# Wacht even tot Syncthing opstart en config genereert
sleep 4

if systemctl --user is-active --quiet syncthing; then
    log "Syncthing draait als achtergrondservice."
else
    warn "Syncthing-service start niet automatisch. Probeer:"
    warn "  export XDG_RUNTIME_DIR=/run/user/\$(id -u)"
    warn "  systemctl --user enable syncthing && systemctl --user start syncthing"
fi

# ── Device ID ophalen ────────────────────────────────────────
info "Syncthing Device ID ophalen..."

DEVICE_ID=$(syncthing --device-id 2>/dev/null || \
    grep -o 'deviceID="[^"]*"' ~/.config/syncthing/config.xml 2>/dev/null | head -1 | cut -d'"' -f2 || \
    echo "NIET GEVONDEN — controleer: syncthing --device-id")

log "Pi 5 Syncthing Device ID:"
echo ""
echo "  ┌──────────────────────────────────────────────────────┐"
echo "  │  $DEVICE_ID  │"
echo "  └──────────────────────────────────────────────────────┘"
echo ""

# ── Syncthing Web UI bereikbaar via Tailscale ───────────────
TAILSCALE_IP="100.77.5.104"

info "Syncthing Web UI configureren voor toegang via Tailscale..."

CONFIG="$HOME/.config/syncthing/config.xml"

if [[ -f "$CONFIG" ]]; then
    # Verander GUI bind address van 127.0.0.1 naar 0.0.0.0 zodat
    # je de UI kunt bereiken via Tailscale IP
    if grep -q '127.0.0.1:8384' "$CONFIG" 2>/dev/null; then
        sed -i 's/127.0.0.1:8384/0.0.0.0:8384/' "$CONFIG"
        systemctl --user restart syncthing 2>/dev/null || true
        sleep 2
        log "Syncthing UI nu bereikbaar via: http://$TAILSCALE_IP:8384"
    else
        log "Syncthing UI al geconfigureerd voor extern toegang."
    fi
else
    warn "Config nog niet gevonden. Wacht 10 seconden en herstart het script."
fi

# ── Overzicht en volgende stappen ────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN}  SYNCTHING KLAAR OP PI 5${NC}"
echo "============================================================"
echo ""
echo "  Syncthing UI (Pi 5):  http://$TAILSCALE_IP:8384"
echo "  Pi 5 Device ID:       $DEVICE_ID"
echo ""
echo "  ─────────────────────────────────────────────────────────"
echo "  HANDMATIGE STAPPEN — doe dit op je MacBook:"
echo "  ─────────────────────────────────────────────────────────"
echo ""
echo "  1. Installeer Syncthing op MacBook:"
echo "     brew install syncthing"
echo "     brew services start syncthing"
echo "     → UI: http://localhost:8384"
echo ""
echo "  2. Voeg de Pi 5 toe als 'Remote Device' in MacBook Syncthing UI:"
echo "     → Klik 'Add Remote Device'"
echo "     → Device ID: $DEVICE_ID"
echo "     → Device Name: Pi5-n8n"
echo ""
echo "  3. Open Syncthing UI op Pi 5: http://$TAILSCALE_IP:8384"
echo "     → Klik 'Add Folder'"
echo "     → Folder ID: obsidian-vault"
echo "     → Folder Path: $VAULT"
echo "     → Vink de MacBook aan als 'Share With'"
echo ""
echo "  4. Accepteer de folder op je MacBook Syncthing UI"
echo "     → Kies als lokaal pad: ~/ObsidianVault  (of bestaand vault-pad)"
echo "     → Klik 'Add'"
echo ""
echo "  5. Open Obsidian op MacBook → 'Open folder as vault'"
echo "     → Selecteer ~/ObsidianVault (of waar je de map hebt ingesteld)"
echo ""
echo "  Sync werkt via Tailscale (100.77.5.104 ↔ 100.111.45.105)"
echo "  Bestanden syncronen zodra beide apparaten online zijn."
echo ""
