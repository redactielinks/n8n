#!/bin/bash
# Zet een apart "boek-logboek" op in de Obsidian-vault, los van Inbox/
# Dagboek/Archief, specifiek om het Second Brain-project (Angie) op
# project-niveau te documenteren voor een boek over valkuilen/oplossingen.
#
# Schrijft rechtstreeks naar de vaultmap op de Pi (geen n8n nodig, gewoon
# bestanden — Syncthing synct ze daarna automatisch door naar je andere
# apparaten).
set -euo pipefail

VAULT="/home/redactielinks/n8n-obsidian-share"
BOEKDIR="$VAULT/Boek-Project-Angie"

mkdir -p "$BOEKDIR"

cat > "$BOEKDIR/00-Architectuur.md" <<'EOF'
---
tags:
  - boek
  - architectuur
datum: 2026-06-17
---

# Architectuur — Project Angie (stand van zaken)

## Apparaten
- **Raspberry Pi 5** (`raspberrypi`, Tailscale 100.77.5.104) — draait n8n in Docker, altijd aan, centrale hub.
- **Mac Mini** (Tailscale 100.68.46.126) — draait een zelfgehoste Whisper-server (spraak-naar-tekst voor Telegram-spraakberichten). Draaide eerder ook LM Studio (lokaal LLM, gemma-3-4b) voor de Secretaresse-agent zelf — die rol is per 17 juni 2026 gestopt (zie logboek).
- **iPhone** — enige dagelijkse interface: Telegram (gebruik van de bot) + Termius (SSH naar de Pi om scripts te draaien). Geen toegang tot de n8n-webinterface vanaf dit apparaat (geen browser-sessie mogelijk op dit toestel voor n8n).
- **Ubuntu server** — (rol nader aan te vullen zodra relevant).

## Software
- **n8n** (Docker op de Pi) — workflow-engine, host van de "Secretaresse — Persoonlijk AI Assistent"-workflow (ID `YdNGeswnhhzFdTFy`).
- **Telegram** — interface voor de gebruiker (bot "JaOuiYes Angie").
- **OpenRouter + Mistral** (sinds 17 juni 2026) — taalmodel-provider voor de Secretaresse-agent. Model: `mistralai/mistral-large-2512` (Mistral Large 3), gekozen vanwege Europese herkomst en betere tool-calling-betrouwbaarheid dan het kleine lokale model.
- **SearXNG** (eigen open-source zoekmachine) — `web_zoeken`-tool, privacy-vriendelijk alternatief voor Google-zoekopdrachten.
- **Tailscale** — VPN/netwerk tussen Pi, Mac Mini en de buitenwereld; ook gebruikt voor de HTTPS-tunnel (`tailscale funnel`) waarmee Telegram de Pi kan bereiken.
- **Obsidian-vault** (deze vault, `n8n-obsidian-share` op de Pi) — "Second Brain", gesynchroniseerd via Syncthing. Mappen: `Inbox/` (nieuwe Telegram-notities), `Dagboek/` (dagelijkse reflecties), `Archief/` (handmatig verwerkt), `Boek-Project-Angie/` (dit logboek, voor het boek).
- **Diverse Google API's** (Calendar, Docs, Sheets, Drive, Workspace, Gmail) — via OAuth2-credentials in n8n.

## Belangrijkste architectuurkeuzes
- Privacy-first waar mogelijk: eigen SearXNG in plaats van Google Search; aanvankelijk volledig lokaal LLM op de Mac Mini in plaats van cloud — dat laatste is teruggedraaid (zie logboek, 17 juni) omdat een klein lokaal model te onbetrouwbaar bleek voor agent/tool-gebruik.
- Alle wijzigingen aan de n8n-workflow gaan via scripts (export → patchen met Python → importeren → container herstarten), niet via de webinterface, omdat de gebruiker dit project uitsluitend via iPhone (Telegram + Termius/SSH) beheert en geen browsertoegang tot n8n heeft.
EOF

cat > "$BOEKDIR/Logboek.md" <<'EOF'
---
tags:
  - boek
  - logboek
---

# Logboek — Project Angie

Chronologisch logboek van problemen, oorzaken, oplossingen en lessen,
bijgehouden voor het boek over het opzetten van een Second Brain-project.
Nieuwe items worden onderaan toegevoegd.

## 2026-06-17 — Van lokaal LLM naar OpenRouter/Mistral

**Context:** de Secretaresse-agent draaide op een klein lokaal model
(`google/gemma-3-4b` via LM Studio op de Mac Mini) voor privacy en
kostenbesparing.

### Probleem 1 — Google Maps-tool crashte (`fetch is not defined`)
- **Oorzaak:** de tool-code gebruikte het globale `fetch()`, dat niet
  bestaat in de sandbox waarin n8n Code-tools draaien. Die sandbox
  geeft alleen een `helpers`-object mee (geen globale `fetch`).
- **Oplossing:** `fetch(url)` + `resp.json()` vervangen door
  `helpers.httpRequest({ method: "GET", url, json: true })`.
- **Les:** n8n Code/Tool-nodes draaien in een eigen VM-sandbox
  (`NodeVM` uit `@n8n/vm2`) — alleen wat expliciet in de
  `sandbox`-context wordt meegegeven (waaronder `helpers`) is
  beschikbaar, geen Node.js- of browser-globals zoals `fetch`.

### Probleem 2 — verkeerde tool gekozen ondanks duidelijke beschrijving
- Het kleine lokale model bleef de Google Maps-tool gebruiken voor
  vragen die er niet over gingen (bv. een vraag over hoog water), ook
  na het aanscherpen van de tool-beschrijving. Tonen wat een tool
  *niet* moet doen hielp niet genoeg bij een klein model.

### Probleem 3 — agent crashte volledig, geen Telegram-antwoord
- **Oorzaak:** als het model een tool-aanroep deed met een verkeerde
  vorm, gooide LangChain's eigen schema-validatie
  (`Tool.call()`/`DynamicStructuredTool.call()`) een fout vóórdat
  n8n's eigen foutafhandeling (zoals `N8nTool`'s fallback-parsing) kans
  kreeg om dit op te vangen. Dit crashte de hele Secretaresse-node, en
  omdat Telegram-verzending daarna in de workflow komt, werd er
  helemaal niets terugverstuurd.
- **Les:** een klein lokaal model dat het tool-aanroep-formaat niet
  altijd correct produceert is een fundamentele beperking, niet iets
  dat met betere tool-beschrijvingen valt te repareren.

### Besluit — overstap naar OpenRouter + Mistral
- Op basis van de bovenstaande problemen is besloten te stoppen met
  lokale modellen voor deze agent, en over te stappen op een cloud-
  model via OpenRouter. Gekozen is voor **Mistral** (Europese
  aanbieder, sluit aan bij de privacy-first uitgangspunten), specifiek
  `mistralai/mistral-large-2512` (Mistral Large 3) vanwege de beste
  tool-calling-betrouwbaarheid binnen de Mistral-modellenreeks.

### Probleem 4 — credential kon niet ontsleuteld worden
- Na het ombouwen van de LLM-node naar OpenRouter gaf n8n:
  *"Credentials could not be decrypted. The likely reason is that a
  different encryptionKey was used to encrypt the data."*
- **Oorzaak:** de encryptiesleutel in `~/.n8n/config` was op 13 juni
  veranderd (waarschijnlijk tijdens het opzetten van de HTTPS-tunnel),
  maar de OpenRouter-credential was sinds 10 maart nooit opnieuw
  opgeslagen — dus nog versleuteld met een oude, niet meer gebruikte
  sleutel. Vrijwel alle andere credentials (Gmail, Google Calendar,
  Workspace, enz.) hebben hetzelfde probleem.
- **Les:** een herstelscript dat de credential herversleutelt met de
  *huidige* sleutel was hiervoor al eerder geschreven, maar nooit
  uitgevoerd — vandaar dat het probleem pas nu aan het licht kwam.

### Probleem 5 — eigen herstelscript had een verborgen bug
- Het herstelscript leek te slagen, maar OpenRouter gaf daarna "401
  Missing Authentication header" — de opgeslagen API-key was leeg.
- **Oorzaak:** het script gebruikte
  `printf '%s' "$API_KEY" | python3 - <<'EOF' ... EOF`. De combinatie
  van een pipe (stdin = de API-key) én een heredoc (stdin = het
  python-script zelf, omdat `python3 -` het programma van stdin leest)
  op dezelfde file-descriptor zorgde ervoor dat `sys.stdin.read()`
  binnen het script altijd een lege string opleverde. Dit is
  empirisch bevestigd door het exacte commando los te testen.
- **Oplossing:** de API-key via een environment variable doorgeven in
  plaats van via stdin, zodat er geen conflict met de heredoc is.
- **Les:** een "geslaagd" script-resultaat (geen foutmelding) is geen
  garantie dat de inhoud klopt — vooral bij verborgen invoer is een
  losse, geïsoleerde test van de exacte constructie nodig om dit soort
  stille fouten te vinden.

### Resultaat
Na deze fix beantwoordde de Secretaresse-agent vragen snel en correct
via Mistral/OpenRouter (bevestigd met een test over hoogwater bij
Holwerd).

### Vervolgpunten (bewust uitgesteld)
- **Google Maps API-sleutel roteren:** deze stond hardcoded in de
  tool-code en is daardoor blootgesteld geraakt (zichtbaar in een
  workflow-export/terminal/chat). Eerste rotatiepoging mislukte omdat
  de letterlijke placeholder-tekst (`PLAK_HIER_JE_NIEUWE_SLEUTEL`) per
  ongeluk als sleutel werd doorgegeven in plaats van de echte nieuwe
  sleutel. Uitgesteld tot de gebruiker de sleutel in Google Cloud
  Console kan terugvinden.
- **Gmail/Calendar/Workspace-credentials herstellen:** zelfde
  oorzaak als Probleem 4, maar deze gebruiken OAuth2 (inloggen via een
  knop in de n8n-webinterface) in plaats van een los API-sleuteltje.
  De gebruiker kan de n8n-webinterface niet vanaf de iPhone bereiken,
  dus dit moet wachten tot er toegang is tot een laptop/computer met
  browser.
EOF

chmod -R 777 "$BOEKDIR"

echo "============================================================"
echo "  Boek-logboek aangemaakt"
echo "============================================================"
echo ""
echo "  $BOEKDIR/00-Architectuur.md"
echo "  $BOEKDIR/Logboek.md"
echo ""
echo "  Wordt automatisch gesynchroniseerd via Syncthing."
