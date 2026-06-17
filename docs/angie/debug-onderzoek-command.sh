#!/bin/bash
# Eenmalig diagnose-script voor het /onderzoek-commando.
# Test SearXNG en LM Studio, zowel vanaf de Pi-host als vanuit de
# n8n-container (de fout treedt op in de container, dus host-only
# testen is niet genoeg).
set -uo pipefail

SEARX_TS="http://100.77.5.104:8081/search?q=test&format=json"
SEARX_LOCAL="http://localhost:8081/search?q=test&format=json"
LLM_URL="http://100.68.46.126:27124/v1/models"

echo "== 1. SearXNG container (ook gestopte tonen) =="
docker ps -a --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep searxng || echo "GEEN searxng container gevonden."

echo ""
echo "== 1b. Wat luistert er op poort 8080 (de oude conflicterende poort)? =="
sudo ss -tlnp 2>/dev/null | grep ':8080 ' || echo "Niets (meer) op 8080, of 'ss' niet beschikbaar."

echo ""
echo "== 2. SearXNG bereikbaar vanaf de Pi-host (localhost) =="
curl -s -o /dev/null -w "HTTP status: %{http_code}\n" "$SEARX_LOCAL" --max-time 10

echo ""
echo "== 3. SearXNG bereikbaar vanaf de Pi-host (Tailscale-IP) =="
curl -s -o /dev/null -w "HTTP status: %{http_code}\n" "$SEARX_TS" --max-time 10

echo ""
echo "== 4. SearXNG bereikbaar vanuit de n8n-container (zelfde fetch als het commando gebruikt) =="
docker exec n8n node -e "
fetch('$SEARX_TS', { signal: AbortSignal.timeout(10000) })
  .then(r => r.text().then(t => console.log('HTTP status:', r.status, '| eerste 150 tekens:', t.slice(0,150))))
  .catch(e => console.log('FOUT:', e.message));
"

echo ""
echo "== 5. LM Studio bereikbaar vanuit de n8n-container =="
docker exec n8n node -e "
fetch('$LLM_URL', { signal: AbortSignal.timeout(10000) })
  .then(r => r.text().then(t => console.log('HTTP status:', r.status, '| eerste 150 tekens:', t.slice(0,150))))
  .catch(e => console.log('FOUT:', e.message));
"

echo ""
echo "== Klaar. Stuur deze output terug. =="
