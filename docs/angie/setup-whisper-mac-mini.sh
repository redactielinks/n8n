#!/bin/bash
# Zet een zelf-gehoste Whisper-server op via faster-whisper, voor
# spraak-naar-tekst van Telegram-spraakberichten. Draait naast LM Studio
# op de Mac Mini, als macOS LaunchAgent (zelfde patroon als
# setup-lmstudio-autostart.sh).
# Voer uit OP de Mac Mini (via SSH of Terminal).
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }
err()  { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

APP_DIR="$HOME/.whisper-bot"
VENV="$APP_DIR/venv"
PLIST="$HOME/Library/LaunchAgents/com.angie.whisper.plist"
PORT=27125
MODEL="${WHISPER_MODEL:-small}"

echo ""
echo "============================================================"
echo "  Whisper spraak-naar-tekst server — Mac Mini"
echo "============================================================"
echo ""

# ── 1. Python3 controleren ────────────────────────────────────
command -v python3 >/dev/null 2>&1 || err "python3 niet gevonden. Installeer Python 3 eerst."
ok "python3 gevonden: $(python3 --version)"

# ── 2. Map en venv aanmaken ───────────────────────────────────
mkdir -p "$APP_DIR"
if [ ! -d "$VENV" ]; then
    python3 -m venv "$VENV"
    ok "Virtual environment aangemaakt: $VENV"
else
    ok "Virtual environment bestaat al"
fi

echo "==> Dependencies installeren (faster-whisper, flask)..."
"$VENV/bin/pip" install --quiet --upgrade pip
"$VENV/bin/pip" install --quiet faster-whisper flask
ok "Dependencies geinstalleerd"

# ── 3. Server-script kopieren ─────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cp "$SCRIPT_DIR/whisper_server.py" "$APP_DIR/whisper_server.py"
ok "Server-script geplaatst: $APP_DIR/whisper_server.py"

# ── 4. LaunchAgent map en plist ───────────────────────────────
mkdir -p "$HOME/Library/LaunchAgents"

cat > "$PLIST" << PLISTEOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>com.angie.whisper</string>
    <key>ProgramArguments</key>
    <array>
        <string>${VENV}/bin/python</string>
        <string>${APP_DIR}/whisper_server.py</string>
    </array>
    <key>EnvironmentVariables</key>
    <dict>
        <key>WHISPER_MODEL</key>
        <string>${MODEL}</string>
        <key>WHISPER_PORT</key>
        <string>${PORT}</string>
    </dict>
    <key>RunAtLoad</key>
    <true/>
    <key>KeepAlive</key>
    <true/>
    <key>StandardOutPath</key>
    <string>/tmp/whisper-server.log</string>
    <key>StandardErrorPath</key>
    <string>/tmp/whisper-server-error.log</string>
</dict>
</plist>
PLISTEOF
ok "LaunchAgent aangemaakt: $PLIST"

# ── 5. Laden (of herladen) ────────────────────────────────────
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"
ok "LaunchAgent geladen"

# ── 6. Wachten en testen ──────────────────────────────────────
echo ""
echo "Wacht op opstart (model '$MODEL' wordt bij eerste start gedownload, kan even duren)..."
sleep 10

for i in 1 2 3 4 5; do
    if curl -s --max-time 5 "http://127.0.0.1:${PORT}/health" | grep -q '"status"'; then
        ok "Server antwoordt op poort ${PORT}"
        break
    fi
    if [ "$i" -eq 5 ]; then
        warn "Server reageert nog niet. Check: cat /tmp/whisper-server-error.log"
    else
        sleep 15
    fi
done

echo ""
echo "============================================================"
echo -e "${GREEN}  KLAAR — Whisper-server draait op poort ${PORT}${NC}"
echo "============================================================"
echo ""
echo "  Test vanaf de Pi (via Tailscale):"
echo "    curl http://100.68.46.126:${PORT}/health"
echo ""
echo "  Stoppen:    launchctl unload ~/Library/LaunchAgents/com.angie.whisper.plist"
echo "  Herstarten: launchctl unload ~/Library/LaunchAgents/com.angie.whisper.plist && launchctl load ~/Library/LaunchAgents/com.angie.whisper.plist"
echo "  Logs:       cat /tmp/whisper-server.log"
echo ""
echo "  Trager dan gewenst? Zet WHISPER_MODEL=base in de plist en herstart"
echo "  (minder nauwkeurig, wel sneller). Nauwkeuriger: WHISPER_MODEL=medium."
echo ""
