#!/bin/bash
# Alleen-lezen: controleert of patch-telegram-trigger-uit.sh daadwerkelijk
# (volledig) is toegepast. Wijzigt niets aan de workflow.
#
# Achtergrond: een Telegram-bericht ("koppel mijn ... account aan n8n")
# kreeg op 23 juni 2026 een antwoord terug in de rauwe wiki-opmaak (bullets,
# "Tip:" etc.) in plaats van een natuurlijk geformuleerd Hermes-antwoord --
# een sterke aanwijzing dat de n8n Telegram Trigger-node toen nog actief
# was en patch-telegram-trigger-uit.sh dus nog niet (succesvol) is gedraaid.
# Dit script bevestigt dat met zekerheid, zonder iets te wijzigen.
#
# Checkt twee dingen onafhankelijk van elkaar:
#  1. Staat de Telegram Trigger-node in de workflow op disabled?
#  2. Heeft Telegram zelf nog een webhook-URL geregistreerd voor dit
#     bottoken (deleteWebhook in de patch ruimt dat op, maar alleen als
#     het script ook echt tot dat punt is gekomen)?
#
# Het bottoken wordt hier alleen lokaal-op-de-Pi ontsleuteld om de
# alleen-lezen getWebhookInfo-aanroep te doen, en komt nergens in output
# of logs terecht.
set -euo pipefail

SCRIPT_VERSIE="2026-06-23-inspect-telegram-trigger-status-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
TELEGRAM_CRED_ID="zk613MPgh3b3pkBZ"
TELEGRAM_CRED_NAME="jaouiyes_n8n_bot"

echo "==> 1/2: Status van de Telegram Trigger-node in de workflow..."
docker exec n8n n8n export:workflow --all --output=/tmp/inspect-tg.json 2>/dev/null
docker cp n8n:/tmp/inspect-tg.json /tmp/inspect-tg.json

python3 - <<'PYEOF'
import json

with open('/tmp/inspect-tg.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')

triggers = [n for n in wf['nodes'] if n.get('type') == 'n8n-nodes-base.telegramTrigger']
if not triggers:
    print("  Geen node van type 'n8n-nodes-base.telegramTrigger' gevonden.")
else:
    for n in triggers:
        status = "DISABLED (uit)" if n.get('disabled') else "ACTIEF (nog aan!)"
        print(f"  Node '{n['name']}': {status}")
PYEOF

echo ""
echo "==> 2/2: Heeft Telegram zelf nog een webhook geregistreerd voor dit bottoken..."
docker exec n8n n8n export:credentials --all --decrypted --output=/tmp/creds-decrypted.json 2>/dev/null
docker cp n8n:/tmp/creds-decrypted.json /tmp/creds-decrypted.json
docker exec n8n rm -f /tmp/creds-decrypted.json
TELEGRAM_BOT_TOKEN=$(python3 -c "
import json
with open('/tmp/creds-decrypted.json', encoding='utf-8') as f:
    creds = json.load(f)
cred = next((c for c in creds if c.get('id') == '${TELEGRAM_CRED_ID}' or c.get('name') == '${TELEGRAM_CRED_NAME}'), None)
if cred is None:
    raise SystemExit('Telegram-credential niet gevonden.')
print(cred['data']['accessToken'])
")
rm -f /tmp/creds-decrypted.json

curl -s "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getWebhookInfo" -o /tmp/webhook-info.json
unset TELEGRAM_BOT_TOKEN
python3 -c "
import json
with open('/tmp/webhook-info.json', encoding='utf-8') as f:
    info = json.load(f).get('result', {})
url = info.get('url', '')
if url:
    print(f'  Telegram heeft nog een webhook geregistreerd: {url}')
    print('  -> deleteWebhook is dus nog NIET (succesvol) uitgevoerd.')
else:
    print('  Telegram heeft geen webhook-URL geregistreerd voor dit bottoken.')
"
rm -f /tmp/webhook-info.json

echo ""
echo "==> Conclusie:"
echo "    - Staat de node hierboven op ACTIEF? Dan moet patch-telegram-trigger-uit.sh"
echo "      (opnieuw) gedraaid worden."
echo "    - Staat er bij Telegram nog een webhook-URL? Dan is in elk geval het"
echo "      deleteWebhook-deel van die patch niet voltooid."
