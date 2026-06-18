#!/bin/bash
# ============================================================
# Project Angie — Niet-publieke wiki-site met zoekfunctie
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Zet een eigen website op met de kennisbank-wiki, de TODO-lijst
# prominent boven aan, en een zoekfunctie. De site draait in een eigen
# Docker-container (los van n8n, andere poort: 8090) en is uitsluitend
# bereikbaar via Tailscale (`tailscale serve`, GEEN funnel) — dus niet
# vanaf het publieke internet, alleen vanaf apparaten in jouw tailnet
# (zoals je iPhone, waar Tailscale al op staat voor de SSH-verbinding).
#
# Voer dit script uit OP de Raspberry Pi:
#   curl -fsSL -o setup-wiki-site.sh https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/setup-wiki-site.sh
#   bash setup-wiki-site.sh
# ============================================================
set -euo pipefail

APP_DIR="/home/redactielinks/wiki-site"
KENNISBANK_DIR="/home/redactielinks/kennisbank"
APP_URL="https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/wiki-site/app.py"
TODO_URL="https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/TODO.md"
PORT=8090

echo "============================================================"
echo "  Wiki-site installeren"
echo "============================================================"
echo ""

echo "==> app.py downloaden..."
mkdir -p "$APP_DIR"
curl -fsSL -o "${APP_DIR}/app.py" "$APP_URL"
echo "    Opgeslagen in ${APP_DIR}/app.py"

echo ""
echo "==> TODO.md downloaden (eenmalig — daarna leest de site 'm lokaal,"
echo "    verversen kan later met refresh-todo.sh)..."
curl -fsSL -o "${APP_DIR}/TODO.md" "$TODO_URL"

echo ""
echo "==> Bestaande container (indien aanwezig) opruimen..."
docker stop wiki-site 2>/dev/null || true
docker rm wiki-site 2>/dev/null || true

echo ""
echo "==> Container starten op poort ${PORT}..."
docker run -d --name wiki-site --restart always -p "${PORT}:${PORT}" \
    -v "${APP_DIR}:/app" -w /app \
    -v "${KENNISBANK_DIR}:${KENNISBANK_DIR}:ro" \
    -e "KENNISBANK_DIR=${KENNISBANK_DIR}" \
    python:3-slim python3 app.py

echo ""
echo "==> Tailscale serve activeren (alleen voor jouw tailnet, geen funnel)..."
tailscale serve --bg "${PORT}" 2>/dev/null || sudo tailscale serve --bg "${PORT}" 2>/dev/null || true

echo ""
echo "==> Wachten tot de site opstart..."
sleep 4
docker logs wiki-site --tail 5

TAILSCALE_FQDN=$(tailscale status --json 2>/dev/null \
    | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['Self']['DNSName'].rstrip('.'))" 2>/dev/null || true)

echo ""
echo "============================================================"
echo "  Klaar"
echo "============================================================"
if [[ -n "$TAILSCALE_FQDN" ]]; then
    echo "  Open op je iPhone (met Tailscale aan): https://${TAILSCALE_FQDN}/"
else
    echo "  Open op je iPhone (met Tailscale aan): https://<jouw-tailscale-naam>/"
fi
echo "  Alleen bereikbaar binnen je tailnet, niet vanaf het publieke internet."
echo ""
