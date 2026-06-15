#!/bin/bash
# ============================================================
# Project Angie — Obsidian Vault initialiseren op Raspberry Pi 5
# Voer uit OP de Pi 5: ssh redactielinks@100.77.5.104
# ============================================================

set -euo pipefail

VAULT="/home/redactielinks/n8n-obsidian-share"
GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log()  { echo -e "${GREEN}[OK]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

echo ""
echo "============================================================"
echo "  Project Angie — Obsidian Vault Setup"
echo "  Pad: $VAULT"
echo "============================================================"
echo ""

# ── Vault mappen aanmaken ───────────────────────────────────
info "Vault-mapstructuur aanmaken..."

mkdir -p "$VAULT"/{Inbox,Dagboek,Archief,.obsidian}

log "Mappen aangemaakt:"
log "  $VAULT/Inbox/      ← alle nieuwe Telegram-notities"
log "  $VAULT/Dagboek/    ← dagboek (één bestand per dag)"
log "  $VAULT/Archief/    ← verwerkte notities (handmatig)"
log "  $VAULT/.obsidian/  ← Obsidian-configuratie"

# ── Obsidian basis-config schrijven ────────────────────────
info "Obsidian-configuratie schrijven..."

cat > "$VAULT/.obsidian/app.json" <<'EOF'
{
  "defaultViewMode": "source",
  "legacyEditor": false,
  "livePreview": true,
  "foldHeading": true,
  "foldIndent": true,
  "showLineNumber": false,
  "strictLineBreaks": false,
  "alwaysUpdateLinks": true,
  "newFileLocation": "folder",
  "newFileFolderPath": "Inbox"
}
EOF

cat > "$VAULT/.obsidian/workspace.json" <<'EOF'
{
  "main": {
    "id": "main",
    "type": "split",
    "children": []
  },
  "left": {
    "id": "left",
    "type": "split",
    "children": [],
    "direction": "horizontal",
    "width": 300
  },
  "right": {
    "id": "right",
    "type": "split",
    "children": [],
    "direction": "horizontal"
  }
}
EOF

# Hotkeys en community plugins config
cat > "$VAULT/.obsidian/community-plugins.json" <<'EOF'
[]
EOF

log "Obsidian-configuratie geschreven."

# ── Welkomstnotitie aanmaken ────────────────────────────────
info "Welkomstnotitie aanmaken..."

cat > "$VAULT/Inbox/WELKOM-Second-Brain.md" <<'EOF'
---
tags:
  - systeem
  - welkom
datum: 2026-06-15
bron: systeem
---

# Welkom in je Second Brain

Deze vault is gekoppeld aan Angie, je persoonlijke AI-assistent via Telegram.

## Mapstructuur

- **Inbox/** — alle binnenkomende notities van Telegram (verwerk deze regelmatig)
- **Dagboek/** — dagelijkse reflecties (automatisch bijgehouden door Angie)
- **Archief/** — verwerkte notities die je handmatig hierheen verplaatst

## Telegram-commando's

| Commando | Resultaat |
|---|---|
| `/notitie [tekst]` | Nieuwe notitie in Inbox |
| `/taak [tekst]` | Taak-checkbox in Inbox |
| `/idee [tekst]` | Idee-notitie in Inbox |
| `/dagboek [tekst]` | Toevoeging aan dagboek van vandaag |
| `/zoek [query]` | Zoeken in alle notities |

## Vrije tekst

Stuur een bericht zonder prefix — Angie classificeert automatisch via het lokale AI-model op de Mac Mini.
EOF

log "Welkomstnotitie aangemaakt in Inbox/"

# ── Rechten instellen ───────────────────────────────────────
info "Bestandsrechten instellen voor n8n Docker container..."
chmod -R 777 "$VAULT"
log "Rechten ingesteld (n8n schrijft als 'node' user in de container)."

# ── Overzicht ──────────────────────────────────────────────
echo ""
echo "============================================================"
echo -e "${GREEN}  VAULT KLAAR${NC}"
echo "============================================================"
echo ""
echo "  Vault pad: $VAULT"
echo ""
echo "  Structuur:"
find "$VAULT" -not -path '*/\.*' | head -20 | sed 's/^/  /'
echo ""
echo "  Volgende stap:"
echo "  Stel Syncthing in om deze map te synchroniseren"
echo "  met de Obsidian vault op je MacBook."
echo "  Zie: docs/angie/setup-syncthing-pi.sh"
echo ""
