#!/bin/bash
# Syncthing installeren op de Pi voor Obsidian vault sync
set -euo pipefail

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }

VAULT="/home/redactielinks/n8n-obsidian-share"
USER="$(whoami)"

echo "" && echo "============================================================"
echo "  Syncthing setup — Raspberry Pi 5" && echo "============================================================" && echo ""

curl -fsSL https://syncthing.net/release-key.gpg | sudo gpg --dearmor -o /usr/share/keyrings/syncthing-archive-keyring.gpg
echo "deb [signed-by=/usr/share/keyrings/syncthing-archive-keyring.gpg] https://apt.syncthing.net/ syncthing stable" | sudo tee /etc/apt/sources.list.d/syncthing.list > /dev/null
sudo apt-get update -qq && sudo apt-get install -y syncthing
ok "Syncthing geïnstalleerd"

sudo systemctl enable "syncthing@${USER}" --now
echo "Wacht 8 seconden op opstart..." && sleep 8
ok "Syncthing actief"

for CFG in "$HOME/.local/share/syncthing/config.xml" "$HOME/.config/syncthing/config.xml"; do
    if [ -f "$CFG" ]; then
        sed -i 's|<address>127\.0\.0\.1:8384</address>|<address>0.0.0.0:8384</address>|g' "$CFG"
        sed -i 's|<user>[^<]*</user>||g' "$CFG"
        sed -i 's|<password>[^<]*</password>||g' "$CFG"
        sudo systemctl restart "syncthing@${USER}" && sleep 4
        ok "Web UI opgesteld op 0.0.0.0:8384 (config: $CFG)"
        break
    fi
done

mkdir -p "${VAULT}" && chmod -R 777 "${VAULT}"

DEVICE_ID=$(syncthing --device-id 2>/dev/null)
TAILSCALE_IP=$(tailscale ip -4 2>/dev/null | head -1)

echo ""
echo "============================================================"
echo "  Pi Device ID:"
echo "  ${DEVICE_ID}"
echo ""
echo "  Syncthing Web UI (Safari + Tailscale VPN aan):"
echo "  http://${TAILSCALE_IP}:8384"
echo "============================================================"
echo ""
echo "  Stappen:"
echo "  1. Open Möbius Sync op iPhone → kopieer iPhone Device ID"
echo "  2. Ga naar http://${TAILSCALE_IP}:8384 in Safari"
echo "  3. Add Remote Device → plak iPhone Device ID"
echo "  4. Add Folder → pad: ${VAULT} → vink iPhone aan"
echo "  5. Möbius Sync: accepteer uitnodiging → kies 'Möbius Sync' map"
echo "  6. Obsidian iPhone → Open vault from Files → Möbius Sync map"
echo ""
