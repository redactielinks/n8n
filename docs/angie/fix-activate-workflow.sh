#!/bin/bash
# ============================================================
# Project Angie — Eenmalige fix: activeer Secretaresse workflow
# Voer uit OP de Raspberry Pi 5 via Termius:
#   bash <(curl -fsSL https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/fix-activate-workflow.sh)
# ============================================================

set -euo pipefail
GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[LET OP]${NC} $1"; }
err()  { echo -e "${RED}[FOUT]${NC} $1"; exit 1; }

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
VAULT="/home/redactielinks/n8n-obsidian-share"

echo ""
echo "============================================================"
echo "  Project Angie — Workflow Activatie Fix"
echo "============================================================"
echo ""

# ── 1. Vault-mappen ────────────────────────────────────────
mkdir -p "${VAULT}/Inbox" "${VAULT}/Dagboek" "${VAULT}/Archief"
chmod -R 777 "${VAULT}"
ok "Vault-mappen aangemaakt: ${VAULT}"

# ── 2. activeVersionId instellen ───────────────────────────
ACTIVE_VID=$(sqlite3 "${DB}" \
  "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;" 2>/dev/null || true)

if [ -z "$ACTIVE_VID" ]; then
    err "Geen versie gevonden in workflow_history voor ${WF_ID}. Eerst patch-script uitvoeren."
fi
ok "Actieve versie-ID: ${ACTIVE_VID}"

# ── 3. n8n stoppen ────────────────────────────────────────
docker stop n8n 2>/dev/null && ok "n8n gestopt" || warn "n8n was al gestopt"

# ── 4. DB updaten ─────────────────────────────────────────
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1, activeVersionId='${ACTIVE_VID}' WHERE id='${WF_ID}';"
RESULT=$(sqlite3 "${DB}" "SELECT active, activeVersionId FROM workflow_entity WHERE id='${WF_ID}';")
ok "DB bijgewerkt: ${RESULT}"

# ── 5. Tailscale Funnel activeren ─────────────────────────
sudo tailscale funnel --bg 5678 2>/dev/null && ok "Tailscale Funnel actief" || warn "Funnel al actief of fout (check: tailscale funnel status)"

# ── 6. WEBHOOK_URL bepalen ────────────────────────────────
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
ok "Webhook URL: ${WEBHOOK_URL}"

# ── 7. n8n herstarten met alle variabelen ─────────────────
docker rm n8n 2>/dev/null || true
docker run -d \
    --name n8n \
    --restart always \
    -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v "${VAULT}:/home/node/obsidian-share" \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path \
    n8nio/n8n:latest
ok "n8n container gestart"

# ── 8. Wachten en controleren ─────────────────────────────
echo ""
echo "Wacht 12 seconden op opstart..."
sleep 12
docker logs n8n --tail 8

echo ""
echo "============================================================"
echo -e "${GREEN}  KLAAR${NC}"
echo "============================================================"
echo ""
echo "  Stuur nu '/notitie test' via Telegram."
echo "  Bot moet antwoorden: 'Notitie opgeslagen: \"test\"'"
echo ""
echo "  Bestand controleren:"
echo "  ls ${VAULT}/Inbox/"
echo ""
