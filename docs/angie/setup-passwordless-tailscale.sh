#!/bin/bash
# Eenmalig: maak 'sudo tailscale ...' wachtwoordloos, zodat patch-scripts
# niet steeds om een wachtwoord vragen. Beperkt tot het tailscale-commando
# zelf, niet tot sudo in het algemeen.
set -euo pipefail

TAILSCALE_BIN=$(command -v tailscale || echo "/usr/bin/tailscale")
SUDOERS_FILE="/etc/sudoers.d/tailscale-nopasswd"

echo "==> Tailscale gevonden op: ${TAILSCALE_BIN}"
echo "==> Sudo zal hierna eenmalig om je wachtwoord vragen, en daarna nooit meer voor tailscale."

echo "$(whoami) ALL=(ALL) NOPASSWD: ${TAILSCALE_BIN}" | sudo tee "${SUDOERS_FILE}" > /dev/null
sudo chmod 440 "${SUDOERS_FILE}"
sudo visudo -c -f "${SUDOERS_FILE}"

echo "==> Testen (geen wachtwoord meer nodig)..."
sudo tailscale status > /dev/null && echo "OK: sudo tailscale werkt zonder wachtwoord."
