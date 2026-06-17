#!/bin/bash
# Alleen-lezen: onderzoekt waarom de OpenRouter-credential niet meer
# ontsleuteld kan worden. Toont GEEN geheime waarden, alleen aanwezigheid,
# tijdstempels en lengtes, zodat we kunnen zien of de encryptiesleutel
# op een ander moment is aangemaakt dan de credential zelf.
set -euo pipefail

DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"

echo "==> Environment variables van de draaiende container (encryption key eruit gefilterd op aanwezigheid, niet de waarde)..."
docker inspect n8n --format '{{range .Config.Env}}{{println .}}{{end}}' \
  | sed -E 's/^(N8N_ENCRYPTION_KEY)=.*/\1=<aanwezig, lengte verborgen>/'

echo ""
echo "==> Bestaat ~/.n8n/config (waar n8n de auto-gegenereerde sleutel bewaart)?"
if [ -f "$CONFIG" ]; then
  echo "Ja. Laatst gewijzigd: $(stat -c '%y' "$CONFIG" 2>/dev/null || stat -f '%Sm' "$CONFIG")"
  echo "Bestandsgrootte: $(stat -c '%s' "$CONFIG" 2>/dev/null || stat -f '%z' "$CONFIG") bytes"
else
  echo "Nee, bestand niet gevonden op $CONFIG"
fi

echo ""
echo "==> Credential-rij(en) voor OpenRouter in de database (geen geheime waarden, alleen metadata)..."
sqlite3 -header -column "$DB" \
  "SELECT id, name, type, datetime(createdAt) as aangemaakt, datetime(updatedAt) as gewijzigd
   FROM credentials_entity WHERE name LIKE '%OpenRouter%' OR type LIKE '%openRouter%';"

echo ""
echo "==> Recente docker-events voor deze container (laat zien wanneer hij is herstart/opnieuw aangemaakt)..."
docker inspect n8n --format 'Aangemaakt (huidige container): {{.Created}}'
