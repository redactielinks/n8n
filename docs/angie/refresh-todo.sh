#!/bin/bash
# ============================================================
# Project Angie — TODO.md verversen op de wiki-site
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# De wiki-site leest TODO.md altijd van de lokale schijf, niet live van
# GitHub (geen doorlopende cloud-afhankelijkheid). Dit script is de enige
# plek die GitHub raadpleegt, en alleen op het moment dat je het zelf
# draait — bijvoorbeeld nadat TODO.md in de repo is bijgewerkt.
#
# Voer dit uit OP de Raspberry Pi:
#   curl -fsSL -o refresh-todo.sh https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/refresh-todo.sh
#   bash refresh-todo.sh
# ============================================================
set -euo pipefail

APP_DIR="/home/redactielinks/wiki-site"
TODO_URL="https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/TODO.md"

curl -fsSL -o "${APP_DIR}/TODO.md" "$TODO_URL"
echo "TODO.md bijgewerkt. De wiki-site pikt dit binnen 5 minuten op (cache)."
