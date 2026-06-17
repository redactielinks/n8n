#!/bin/bash
# Alleen-lezen: onderzoekt het probleem uit het laatste screenshot:
#   1) De agent gaf 21 minuten na elkaar TWEE KEER exact "Het is 16:00
#      uur." — terwijl de systeem-instructie {{ $now... }} elke keer
#      opnieuw zou moeten worden uitgerekend. Mogelijke oorzaak: het
#      kleine lokale model "leunt" op het vorige antwoord in het
#      geheugen (Window Buffer Memory) in plaats van de nieuwe waarde
#      in de systeem-instructie te gebruiken.
#   2) Op een latere, complexere vraag ("hoe laat is het hoog water
#      bij Holwerd") kwam in Telegram geen antwoord terug. Dit script
#      checkt of die uitvoering bestaat, en wat de status/duur/fout was.
#
# Verandert niets. Toont alleen ruwe gegevens uit de laatste paar
# uitvoeringen, inclusief het exacte geheugen (chat-historie) en de
# exacte systeem-instructie-waarde die de agent zag bij elke aanroep.
set -euo pipefail

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"

echo "============================================================"
echo "  Laatste 15 uitvoeringen van de Secretaresse-workflow"
echo "============================================================"
sqlite3 -header -column "$DB" \
  "SELECT id, status, datetime(startedAt) as gestart, datetime(stoppedAt) as gestopt,
          ROUND((julianday(stoppedAt) - julianday(startedAt)) * 86400.0, 1) as duur_sec
   FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 15;"

echo ""
echo "============================================================"
echo "  Details van de laatste 4 uitvoeringen (geheugen + antwoord)"
echo "============================================================"

IDS=$(sqlite3 "$DB" "SELECT id FROM execution_entity WHERE workflowId='${WF_ID}' ORDER BY id DESC LIMIT 4;")

for EID in $IDS; do
  echo ""
  echo "------------------------------------------------------------"
  echo "Execution ID: ${EID}"
  sqlite3 -header -column "$DB" \
    "SELECT status, datetime(startedAt) as gestart, datetime(stoppedAt) as gestopt
     FROM execution_entity WHERE id=${EID};"

  sqlite3 "$DB" "SELECT data FROM execution_data WHERE executionId='${EID}';" > "/tmp/exec_raw.txt"
  docker cp "/tmp/exec_raw.txt" "n8n:/tmp/exec_raw.txt"

  docker exec n8n node -e '
const fs = require("fs");
let flatted;
try {
  flatted = require("flatted");
} catch (e) {
  flatted = require("/usr/local/lib/node_modules/n8n/node_modules/.pnpm/flatted@3.4.2/node_modules/flatted");
}
const raw = fs.readFileSync("/tmp/exec_raw.txt", "utf8");
let data;
try {
  data = flatted.parse(raw);
} catch (e) {
  console.log("Kon data niet parsen:", e.message);
  process.exit(0);
}
const runData = data && data.resultData && data.resultData.runData;
if (!runData) {
  console.log("Geen resultData.runData. Mogelijk nog lopend of fout voor agent-node. Top-level keys:", Object.keys(data || {}));
  if (data && data.resultData && data.resultData.error) {
    console.log("FOUT:", JSON.stringify(data.resultData.error, null, 2).slice(0, 1000));
  }
  process.exit(0);
}
for (const nodeName of Object.keys(runData)) {
  const runs = runData[nodeName];
  runs.forEach((run, i) => {
    console.log(`--- Node "${nodeName}" run ${i} (status: ${run.executionStatus || "?"}, ${run.executionTime}ms) ---`);
    if (run.error) {
      console.log("  FOUT:", JSON.stringify(run.error).slice(0, 500));
    }
    try {
      const out = run.data && run.data.main && run.data.main[0] && run.data.main[0][0] && run.data.main[0][0].json;
      if (out) {
        console.log("  Output (json):", JSON.stringify(out).slice(0, 800));
      }
    } catch (e) {}
  });
}
'
  docker exec n8n rm -f "/tmp/exec_raw.txt"
  rm -f "/tmp/exec_raw.txt"
done

echo ""
echo "============================================================"
echo "  Kijk specifiek naar:"
echo "  - 'Window Buffer Memory' output: staat het vorige antwoord"
echo "    ('Het is 16:00 uur.') daar letterlijk in de geschiedenis?"
echo "  - 'Secretaresse' output bij de twee tijd-vragen: is de"
echo "    systeem-instructie-waarde (de tijd) elke keer anders?"
echo "  - De laatste uitvoering (hoog water Holwerd): status/fout?"
echo "============================================================"
