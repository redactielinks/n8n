#!/bin/bash
# Alleen-lezen: zoekt de ECHTE oorzaak van de terugkerende "Credentials
# could not be decrypted"-fout. Eerder werd dit losgemaakt door de
# credential opnieuw op te slaan, maar het kwam terug — dus de
# encryptiesleutel zelf verandert blijkbaar af en toe. De meest
# waarschijnlijke oorzaak: als n8n (binnen de container, gebruiker
# "node") het bestand ~/.n8n/config niet kan LEZEN door een
# eigenaarschap/rechten-mismatch, denkt het dat er nog geen sleutel
# bestaat en maakt het er stilletjes een NIEUWE — die het OOK meteen
# overschrijft in dat bestand. Dit script toont eigenaarschap, rechten
# en tijdstempels, zonder de geheime sleutel zelf te tonen.
set -euo pipefail

DB="/home/redactielinks/.n8n/database.sqlite"
CONFIG="/home/redactielinks/.n8n/config"
NFOLDER="/home/redactielinks/.n8n"

echo "==> Eigenaarschap en rechten van ~/.n8n en de belangrijkste bestanden (op de Pi zelf)..."
ls -la "$NFOLDER" | head -20
echo ""
stat -c '%n: eigenaar=%U(%u) groep=%G(%g) rechten=%A gewijzigd=%y' "$CONFIG" "$DB" 2>/dev/null || true

echo ""
echo "==> Welke gebruiker draait er ÍN de container, en kan die het config-bestand lezen?..."
docker exec n8n id
docker exec n8n ls -la /home/node/.n8n/config /home/node/.n8n/database.sqlite 2>&1 || true
docker exec n8n cat /home/node/.n8n/config > /tmp/config-leesbaar-check.json 2>&1 && echo "Container kan config LEZEN (inhoud niet getoond)." || echo "FOUT: container kan config NIET lezen (zie foutmelding hierboven)."
rm -f /tmp/config-leesbaar-check.json

echo ""
echo "==> Alle credentials: aangemaakt/gewijzigd t.o.v. het moment dat config voor het laatst is gewijzigd..."
echo "Config laatst gewijzigd: $(stat -c '%y' "$CONFIG" 2>/dev/null)"
sqlite3 -header -column "$DB" \
  "SELECT id, name, type, datetime(createdAt) as aangemaakt, datetime(updatedAt) as gewijzigd
   FROM credentials_entity ORDER BY updatedAt;"

echo ""
echo "==> Docker-logs van de container sinds laatste start (zoek naar 'Auto-generating' = bewijs van sleutel-regeneratie)..."
docker logs n8n 2>&1 | grep -iE "encryption|auto-generat|mismatch" || echo "(geen relevante regel gevonden in huidige containerlogs)"
