#!/bin/bash
# ============================================================
# Project Angie — n8n Docker Startcommando (handmatig gebruik)
# Gebruik: bash n8n-docker-start.sh <WEBHOOK_URL>
# Voorbeeld: bash n8n-docker-start.sh https://pi5.tailxxxxxx.ts.net
# ============================================================
# Als je de WEBHOOK_URL niet weet, voer dan eerst uit:
#   tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))"
# ============================================================

set -euo pipefail

WEBHOOK_URL="${1:-}"

if [[ -z "$WEBHOOK_URL" ]]; then
    echo "GEBRUIK: $0 <WEBHOOK_URL>"
    echo "VOORBEELD: $0 https://pi5.tailxxxxxx.ts.net"
    echo ""
    echo "Of laat het script de URL zelf ophalen:"
    WEBHOOK_URL=$(tailscale status --json \
        | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
    echo "Gevonden URL: $WEBHOOK_URL"
fi

# Stop en verwijder bestaande container
docker stop n8n 2>/dev/null && docker rm n8n 2>/dev/null || true

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

echo "n8n gestart. Bereikbaar op:"
echo "  Lokaal:  http://100.77.5.104:5678"
echo "  Extern:  ${WEBHOOK_URL}"
