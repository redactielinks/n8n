#!/bin/bash
# ============================================================
# Project Angie — Wiki-site bijwerken: kopieer/deel + verwijderen
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Haalt de nieuwste app.py op (kopieer/deel-knoppen met behoud van de
# rauwe markdown-opmaak, en een verwijderknop per pagina) en herstart de
# wiki-site-container. De kennisbank-map was tot nu toe read-only gemount
# (--ro) omdat de site alleen las; voor de verwijderfunctie moet de
# container nu ook mogen schrijven, dus de mount wordt hier read-write.
#
# Voer dit uit OP de Raspberry Pi:
#   curl -fsSL -o update-wiki-site.sh https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/update-wiki-site.sh
#   bash update-wiki-site.sh
# ============================================================
set -euo pipefail

APP_DIR="/home/redactielinks/wiki-site"
KENNISBANK_DIR="/home/redactielinks/kennisbank"
APP_URL="https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/wiki-site/app.py"
PORT=8090

echo "==> Nieuwe app.py downloaden..."
curl -fsSL -o "${APP_DIR}/app.py" "$APP_URL"
echo "    Opgeslagen in ${APP_DIR}/app.py"

echo ""
echo "==> Container herstarten met schrijftoegang tot de kennisbank..."
docker stop wiki-site 2>/dev/null || true
docker rm wiki-site 2>/dev/null || true
docker run -d --name wiki-site --restart always -p "${PORT}:${PORT}" \
    -v "${APP_DIR}:/app" -w /app \
    -v "${KENNISBANK_DIR}:${KENNISBANK_DIR}" \
    -e "KENNISBANK_DIR=${KENNISBANK_DIR}" \
    python:3-slim python3 app.py

echo ""
echo "==> Wachten tot de site opstart..."
sleep 4
docker logs wiki-site --tail 5

echo ""
echo "============================================================"
echo "  Klaar"
echo "============================================================"
echo "  Open een pagina (bijv. een recept onder Koken) en je ziet nu"
echo "  onderaan: Kopieer, Delen en Verwijderen."
echo "  - Kopieer/Delen geven de rauwe markdown door, dus opmaak zoals"
echo "    **vet**, lijstjes en koppen blijft behouden bij plakken."
echo "  - Verwijderen vraagt eerst om bevestiging en knipt daarna ook"
echo "    de link uit de bijbehorende categoriepagina."
echo ""
