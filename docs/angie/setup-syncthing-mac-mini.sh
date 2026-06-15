#!/bin/bash
# ============================================================
# Project Angie — Syncthing op Mac Mini (100.99.111.39)
# Voer uit OP de Mac Mini (via SSH of terminal)
# ============================================================
# De Mac Mini heeft het Obsidian vault nodig zodat het LLM
# straks ook context uit je Second Brain kan ophalen.
# ============================================================

set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

OBSIDIAN_PATH="$HOME/ObsidianVault"
PI5_IP="100.77.5.104"

echo ""
echo "============================================================"
echo "  Project Angie — Syncthing Setup (Mac Mini)"
echo "  Tailscale IP: 100.99.111.39"
echo "============================================================"
echo ""

# ── Installatie ─────────────────────────────────────────────
info "Syncthing installeren..."

if command -v syncthing >/dev/null 2>&1; then
    log "Syncthing al aanwezig: $(syncthing --version | head -1)"
elif command -v brew >/dev/null 2>&1; then
    brew install syncthing
    log "Syncthing geïnstalleerd via Homebrew."
else
    warn "Homebrew niet gevonden. Syncthing downloaden als binary..."
    ARCH=$(uname -m)
    if [[ "$ARCH" == "arm64" ]]; then
        SYNCTHING_URL="https://github.com/syncthing/syncthing/releases/download/v1.27.3/syncthing-macos-arm64-v1.27.3.zip"
    else
        SYNCTHING_URL="https://github.com/syncthing/syncthing/releases/download/v1.27.3/syncthing-macos-amd64-v1.27.3.zip"
    fi
    cd /tmp
    curl -fsSL -o syncthing.zip "$SYNCTHING_URL"
    unzip -q syncthing.zip
    sudo mv syncthing-*/syncthing /usr/local/bin/syncthing
    rm -rf syncthing.zip syncthing-*/
    cd -
    log "Syncthing binary geïnstalleerd in /usr/local/bin/"
fi

# ── Autostart configureren ───────────────────────────────────
info "Syncthing configureren als achtergrondservice..."

if command -v brew >/dev/null 2>&1; then
    brew services start syncthing 2>/dev/null || true
    log "Syncthing gestart via brew services."
else
    # LaunchAgent voor autostart zonder Homebrew
    PLIST="$HOME/Library/LaunchAgents/net.syncthing.syncthing.plist"
    mkdir -p "$HOME/Library/LaunchAgents"
    cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>net.syncthing.syncthing</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/syncthing</string>
        <string>serve</string>
        <string>--no-browser</string>
        <string>--no-restart</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/syncthing-mac-mini.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/syncthing-mac-mini-err.log</string>
</dict>
</plist>
EOF
    launchctl load "$PLIST"
    log "Syncthing gestart via LaunchAgent."
fi

# Wacht tot Syncthing opgestart is
sleep 4

# ── Device ID ophalen ────────────────────────────────────────
info "Syncthing Device ID ophalen..."

DEVICE_ID=$(syncthing --device-id 2>/dev/null || echo "NIET GEVONDEN")

log "Mac Mini Syncthing Device ID:"
echo ""
echo "  ┌──────────────────────────────────────────────────────┐"
echo "  │  $DEVICE_ID  │"
echo "  └──────────────────────────────────────────────────────┘"
echo ""

# ── Vault map aanmaken ───────────────────────────────────────
info "Obsidian vault map aanmaken op Mac Mini..."
mkdir -p "$OBSIDIAN_PATH"
log "Vault map aangemaakt: $OBSIDIAN_PATH"

# ── Instructies voor koppelen ────────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN}  SYNCTHING KLAAR OP MAC MINI${NC}"
echo "============================================================"
echo ""
echo "  Syncthing Web UI: http://localhost:8384"
echo "  Device ID:        $DEVICE_ID"
echo "  Vault pad:        $OBSIDIAN_PATH"
echo ""
echo "  ─────────────────────────────────────────────────────────"
echo "  KOPPELEN MET PI 5: doe dit in de Syncthing UI op Pi 5"
echo "  ─────────────────────────────────────────────────────────"
echo ""
echo "  Open: http://$PI5_IP:8384"
echo ""
echo "  1. Klik 'Add Remote Device'"
echo "     → Device ID: $DEVICE_ID"
echo "     → Name: MacMini-LLM"
echo ""
echo "  2. Ga naar de 'obsidian-vault' folder op Pi 5"
echo "     → Klik 'Edit' → 'Sharing' tab"
echo "     → Vink 'MacMini-LLM' aan"
echo "     → Sla op"
echo ""
echo "  3. Terug in Mac Mini Syncthing UI (http://localhost:8384):"
echo "     → Accepteer het verzoek van Pi 5"
echo "     → Stel Local Path in op: $OBSIDIAN_PATH"
echo "     → Klik 'Add'"
echo ""
echo "  Sync verloopt via Tailscale (100.99.111.39 ↔ 100.77.5.104)"
echo ""
