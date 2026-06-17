#!/bin/bash
# Eenmalig: SearXNG opzetten op de Pi. Open source, zelf gehoste
# metasearch-engine, geen tracking, geen grote-techbedrijf-afhankelijkheid.
# Nodig voor het /onderzoek-commando (Gemma + websearch).
set -euo pipefail

DIR="/home/redactielinks/searxng"
mkdir -p "$DIR"

if [ ! -f "$DIR/settings.yml" ]; then
  SECRET=$(openssl rand -hex 16)
  cat > "$DIR/settings.yml" <<EOF
use_default_settings: true
server:
  secret_key: "${SECRET}"
search:
  formats:
    - html
    - json
EOF
  echo "==> settings.yml aangemaakt met JSON-output ingeschakeld."
fi

docker stop searxng 2>/dev/null || true
docker rm searxng 2>/dev/null || true
# Poort 8081 op de host (niet 8080): die bleek al in gebruik door een
# andere dienst op de Pi. Binnen de container blijft het gewoon 8080.
docker run -d --name searxng --restart always -p 8081:8080 \
    -v "${DIR}/settings.yml:/etc/searxng/settings.yml:ro" \
    searxng/searxng:latest

echo "==> Wachten op opstart..."
sleep 8
curl -s "http://localhost:8081/search?q=test&format=json" | head -c 200
echo ""
echo "SearXNG draait op poort 8081. Test: http://100.77.5.104:8081"
