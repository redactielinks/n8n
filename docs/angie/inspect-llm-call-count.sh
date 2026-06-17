#!/bin/bash
# Alleen-lezen: telt precies hoe vaak de lokale LLM-node ("Lokale LLM
# (Mac Mini)") is aangeroepen tijdens de laatste succesvolle uitvoering
# van de Secretaresse-agent, en hoe lang elke afzonderlijke aanroep
# duurde. Gebruikt n8n's eigen 'flatted'-library (dezelfde die n8n zelf
# gebruikt om executiedata te (de)serialiseren, zie
# packages/@n8n/db/src/repositories/execution.repository.ts) om de data
# correct te lezen, in plaats van te gokken op basis van platte tekst.
#
# Doel: vaststellen of de trage reactie (~1 minuut) komt door één
# eenmalige opwarmkosten, of doordat de agent meerdere keren achter
# elkaar de LLM aanroept (bv. omdat het kleine lokale model niet in
# één keer een geldig tool-aanroep-antwoord geeft).
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
LLM_NODE="Lokale LLM (Mac Mini)"

LAST_OK=$(sqlite3 "$DB" "SELECT id FROM execution_entity WHERE workflowId='${WF_ID}' AND status='success' ORDER BY id DESC LIMIT 1;")
if [ -z "$LAST_OK" ]; then
  echo "Geen succesvolle uitvoering gevonden."
  exit 0
fi
echo "==> Laatste succesvolle uitvoering: ID ${LAST_OK}"
sqlite3 -header -column "$DB" \
  "SELECT id, datetime(startedAt) as gestart, datetime(stoppedAt) as gestopt,
          (julianday(stoppedAt) - julianday(startedAt)) * 86400.0 as duur_seconden
   FROM execution_entity WHERE id=${LAST_OK};"

sqlite3 "$DB" "SELECT data FROM execution_data WHERE executionId='${LAST_OK}';" > /tmp/last_exec_raw.txt
docker cp /tmp/last_exec_raw.txt n8n:/tmp/last_exec_raw.txt

echo ""
echo "==> Per-node uitvoeringen en duur (via n8n's eigen flatted-parser)..."
docker exec n8n node -e '
const fs = require("fs");
let flatted;
try {
  flatted = require("flatted");
} catch (e) {
  try {
    flatted = require("/usr/local/lib/node_modules/n8n/node_modules/.pnpm/flatted@3.4.2/node_modules/flatted");
  } catch (e2) {
    console.log("GEEN flatted-module gevonden in de container, kan niet structureel parsen.");
    process.exit(1);
  }
}
const raw = fs.readFileSync("/tmp/last_exec_raw.txt", "utf8");
let data;
try {
  data = flatted.parse(raw);
} catch (e) {
  console.log("Kon data niet parsen met flatted:", e.message);
  process.exit(1);
}
const runData = data && data.resultData && data.resultData.runData;
if (!runData) {
  console.log("Geen resultData.runData gevonden. Top-level keys:", Object.keys(data || {}));
  process.exit(1);
}
for (const nodeName of Object.keys(runData)) {
  const runs = runData[nodeName];
  const totalMs = runs.reduce((sum, r) => sum + (r.executionTime || 0), 0);
  console.log(`Node "${nodeName}": ${runs.length}x uitgevoerd, totaal ${totalMs}ms`);
  runs.forEach((run, i) => {
    console.log(`  run ${i}: ${run.executionTime}ms (status: ${run.executionStatus || "?"})`);
  });
}
'
docker exec n8n rm -f /tmp/last_exec_raw.txt
rm -f /tmp/last_exec_raw.txt

echo ""
echo "============================================================"
echo "  Kijk naar de regel voor '${LLM_NODE}': het aantal 'x uitgevoerd'"
echo "  vertelt hoe vaak de lokale LLM is aangeroepen voor dit ene"
echo "  Telegram-bericht. Veel keren (bv. 4-8x) verklaart de duur."
echo "============================================================"
