#!/bin/bash
# Zet LM Studio server-autostart op via macOS LaunchAgent
# Voer uit OP de Mac Mini (via SSH of Terminal)
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }
err()  { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

LMS="$HOME/.lmstudio/bin/lms"
PLIST="$HOME/Library/LaunchAgents/com.lmstudio.server.plist"

echo ""
echo "============================================================"
echo "  LM Studio server autostart — Mac Mini"
echo "============================================================"
echo ""

# ── 1. Controleer lms binary ──────────────────────────────────
if [ ! -f "$LMS" ]; then
    err "LM Studio CLI niet gevonden op $LMS. Installeer LM Studio eerst."
fi
ok "LM Studio CLI gevonden: $LMS"

# ── 2. LaunchAgent map aanmaken ───────────────────────────────
mkdir -p "$HOME/Library/LaunchAgents"

# ── 3. Plist schrijven ────────────────────────────────────────
cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.lmstudio.server</string>
    <key>ProgramArguments</key>
    <array>
        <string>${LMS}</string>
        <string>server</string>
        <string>start</string>
        <string>--port</string>
        <string>27124</string>
        <string>--bind</string>
        <string>0.0.0.0</string>
    </array>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/lmstudio-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/lmstudio-server-error.log</string>
</dict>
</plist>
PLISTEOF
ok "LaunchAgent aangemaakt: $PLIST"

# ── 4. Laden (of herladen) ────────────────────────────────────
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
ok "LaunchAgent geladen"

# ── 5. Wachten en testen ──────────────────────────────────────
echo ""
echo "Wacht 5 seconden op opstart..."
sleep 5

STATUS=$(launchctl list | grep lmstudio || echo "niet gevonden")
echo "Status: $STATUS"

if curl -s --max-time 5 http://127.0.0.1:27124/v1/models | grep -q '"data"'; then
    ok "Server antwoordt op poort 27124"
else
    warn "Server reageert nog niet — wacht 15 seconden meer..."
    sleep 15
    if curl -s --max-time 5 http://127.0.0.1:27124/v1/models | grep -q '"data"'; then
        ok "Server antwoordt op poort 27124"
    else
        warn "Server reageert niet. Check: cat /tmp/lmstudio-server-error.log"
    fi
fi

echo ""
echo "============================================================"
echo -e "${GREEN}  KLAAR — LM Studio start nu automatisch bij inloggen${NC}"
echo "============================================================"
echo ""
echo "  Stoppen:   launchctl unload ~/Library/LaunchAgents/com.lmstudio.server.plist"
echo "  Herstarten: launchctl unload ~/Library/LaunchAgents/com.lmstudio.server.plist && launchctl load ~/Library/LaunchAgents/com.lmstudio.server.plist"
echo "  Logs:      cat /tmp/lmstudio-server.log"
echo ""
