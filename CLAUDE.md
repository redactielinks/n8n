# Project Angie

Dit is een fork van de n8n-broncode, maar voor deze gebruiker is alleen
`docs/angie/` relevant: een persoonlijke n8n-workflow + wiki-site op een
Raspberry Pi ("Project Angie", een Telegram/wiki-secretaresse-assistent). De
rest van de repo is onaangeroerde upstream n8n-code — negeer die.

Dit bestand is de **bron van waarheid over de huidige stand van zaken**.
Werk het bij zodra de infrastructuur wijzigt (nieuw model, nieuwe node,
nieuwe credential, Telegram aan/uit, etc.), zodat een volgende sessie niet
opnieuw hoeft te worden bijgepraat. `docs/angie/TODO.md` is iets anders: dat
is de lijst met *openstaande* punten met een klaarstaand script.

## Vaste instructies van de gebruiker

- **Antwoord altijd in het Nederlands.**
- **De gebruiker heeft geen eigen bedrijf/onderneming** (geen zzp, geen btw-
  aangifte). Fiscaal advies in patches/prompts mag dus nooit uitgaan van
  zakelijke kostenaftrek — alleen de specifieke wettelijke persoonlijke
  aftrekposten (giften aan een ANBI, hypotheekrente, niet-vergoede
  zorgkosten boven de drempel, e.d.) zijn relevant. Eerdere bug: het
  fiscale prompt in `verwerkFinancieelDocument` ging hier ten onrechte van
  uit ("zelfstandig ondernemer/particulier") en adviseerde "vermoedelijk
  zakelijk aftrekbaar" voor een gewone verzekeringspolis — gefixt in
  `patch-fiscaal-particulier-en-llm-retry.sh`.
- "Ik wil dat je perfect werkt, dus geen schoonheidsfoutjes — die moet je
  altijd oplossen." Kleine/cosmetische bugs proactief fixen, niet alleen
  signaleren.
- Geef **nooit** alleen een diagnose als een concrete fix mogelijk is — bouw
  en valideer het patchscript.
- Echte secrets (API-keys, tokens) komen **nooit** in een commit. Patches
  gebruiken alleen placeholders in de broncode; de echte waarde wordt pas
  lokaal-op-de-Pi, tijdens het uitvoeren van het script, ontsleuteld (bv.
  `n8n export:credentials --all --decrypted`) en direct na gebruik verwijderd
  — nooit geprint of gelogd.

## Geen directe toegang tot de Pi

Ik (Claude) heb **geen** SSH/Tailscale/Docker-toegang tot de Raspberry Pi.
Alle wijzigingen verlopen via bash-patchscripts in `docs/angie/`, die ik
commit en push naar branch `claude/angie-https-tunnel-foss-hfqqzl`. De
gebruiker downloadt en draait ze zelf, met cache-busting:

```bash
rm -f <script>.sh
curl -fsSL -o <script>.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/<script>.sh?t=$(date +%s)"
bash <script>.sh
```

Ik kan dus pas zien of iets werkt via wat de gebruiker terugmeldt (tekst,
screenshots, curl-output) — nooit aannemen dat een eerdere fix al "live"
staat zonder dat bevestigd te zien.

## Conventies voor patchscripts

- `set -euo pipefail`, een `SCRIPT_VERSIE`-banner die meteen wordt geprint.
- Idempotentie-guard: check een precondition-marker (vorige patch al
  toegepast) én dat de eigen marker nog *niet* aanwezig is; anders een
  duidelijke Nederlandse `SystemExit`-melding en stoppen zonder iets te
  wijzigen.
- Voor surgical (niet-full-replace) patches: `js.count(oude_string)` exact
  controleren vóór een `replace`, anders afbreken.
- Elke `docker run` die n8n herstart **moet** `N8N_ENCRYPTION_KEY` expliciet
  meegeven (dynamisch gelezen uit `~/.n8n/config`) ÉN de kennisbank-map
  mounten (`-v "${KENNISBANK_DIR}:${KENNISBANK_DIR}"`, dezelfde absolute
  host-pad binnen de container omdat de jsCode dat pad direct gebruikt).
  Zonder de encryptiesleutel genereert n8n soms een nieuwe sleutel, waardoor
  alle bestaande credentials onleesbaar worden ("Credentials could not be
  decrypted... different encryptionKey") — gebeurd op 17 juni 2026 (fix:
  `fix-openrouter-credential.sh`) én opnieuw rond 19 juni 2026 doordat
  `patch-rubrieken-en-llm-titels.sh` (gedraaid vóór deze regel als
  standaardconventie was vastgelegd) de sleutel niet meegaf. Check dus bij
  élke nieuwe `docker run`-regel in een patchscript: staat `N8N_ENCRYPTION_KEY`
  er expliciet in?
- Vóór opleveren altijd valideren: `bash -n`, ingesloten Python-heredocs
  los `ast.parse()`'n, ingesloten JS los door `node --check` (in een async
  IIFE), en idealiter een dry-run met gefabriceerde fixture-JSON die zowel
  het succespad als alle afbreek-paden test.

## Huidige architectuur (stand: 19 juni 2026)

- n8n + wiki-site draaien als Docker-containers op een Raspberry Pi 5,
  bereikbaar via Tailscale-IP `100.77.5.104` (geen publiek internet, behalve
  de n8n-webhook via `tailscale funnel`).
- Eén workflow: "Secretaresse — Persoonlijk AI Assistent", id
  `YdNGeswnhhzFdTFy`.
- **Telegram wordt niet meer gebruikt** — de gebruiker werkt rechtstreeks via
  de wiki-site-chat en de CLI-webhook (`/webhook/angie-cli`, toegevoegd door
  `patch-cli-bypass.sh`). De Telegram-trigger/nodes zijn niet verwijderd uit
  de workflow, maar zijn nu legacy/ongebruikt.
- Twee gescheiden LLM-paden in de workflow:
  - **Hoofd-"AI Agent"-node** (tool-calling via LangChain) → OpenRouter,
    credential `oITPdZPojDOLJaCJ` ("OpenRouter account"). Huidig model:
    **Mistral** (niet Hermes — Hermes is geprobeerd en teruggedraaid omdat
    geen Hermes-variant op OpenRouter tool-calling ondersteunt; zie
    `TODO.md` "Afgerond").
  - **Code-node "Verwerk Wiki Commando"** doet eigen rauwe `httpRequest`-
    aanroepen (niet via n8n's credential-systeem) voor platte
    JSON-extractie/titelgeneratie (geen tool-calling nodig). Draaide eerst
    op een lokale LM Studio-server op een Mac Mini; die staat sinds 19 juni
    2026 niet meer aan. Gemigreerd naar OpenRouter (zelfde credential),
    standaardmodel `nousresearch/hermes-4-70b` — de tool-calling-beperking
    van Hermes is hier irrelevant, dit zijn platte completions.
- Kennisbank-inhoud staat alleen lokaal op de Pi (`~/kennisbank`) — bewust
  nooit naar GitHub gepusht (uit git-historie verwijderd).
- Bij een mislukte LLM-aanroep in "Verwerk Wiki Commando" wordt sinds
  `patch-fiscaal-particulier-en-llm-retry.sh` één keer automatisch
  opnieuw geprobeerd (na 2s, via `metRetry`) — tijdelijke OpenRouter-
  rate-limits (HTTP 429) bij meerdere documenten kort na elkaar waren een
  waarschijnlijke oorzaak van losse mislukkingen. Lukt het dan nog niet,
  dan staat de échte foutmelding (bv. "HTTP 429: ...") in de tip-tekst in
  plaats van de oude vage "LLM niet bereikbaar of timeout" — belangrijk
  omdat ik geen Pi-/dockerlogtoegang heb en anders blind moet gokken naar
  de oorzaak.
- `verwerkFinancieelDocument` haalt sinds `patch-factuurperiode.sh` ook een
  `factuurperiode` uit herhalende/periodieke facturen (abonnement,
  verzekeringspremie, energie, huur e.d.) — zichtbaar in de frontmatter, de
  "Samenvatting"-sectie op de wiki-pagina én het directe antwoord ("...
  Periode: januari 2026."). Voor eenmalige documenten blijft dit veld leeg.
- **Pas op met de volgorde van openstaande scripts op de Pi.** Stand 19 juni
  2026, avond: de live installatie zat vast op een encryptiesleutel-fout
  (zie hierboven), waardoor zowel `patch-llm-calls-naar-openrouter.sh` als
  `patch-fiscaal-particulier-en-llm-retry.sh` nog niet bevestigd succesvol
  zijn gedraaid. `patch-factuurperiode.sh` bouwt surgical verder op de
  staat ná `patch-fiscaal-particulier-en-llm-retry.sh` (precondition-check
  op de "PARTICULIER ZONDER eigen bedrijf"-tekst). Juiste volgorde op een
  vastgelopen Pi: `fix-openrouter-credential.sh` → `patch-llm-calls-naar-openrouter.sh`
  → `patch-fiscaal-particulier-en-llm-retry.sh` → `patch-factuurperiode.sh`.
  Bij een verse/nieuwe installatie volstaat het master-script
  `patch-facturen-bijlagen-en-fiscale-tips.sh` (heeft factuurperiode al
  ingebouwd) gevolgd door `patch-llm-calls-naar-openrouter.sh` met evt.
  modelargument.
- Openstaande/bekende issues: zie `docs/angie/TODO.md`.
- Bekende, nog niet opgeloste bevinding: het Telegram-bottoken staat in
  plaintext gecommit in `patch-facturen-bijlagen-en-fiscale-tips.sh`. Laag
  operationeel risico nu Telegram niet meer gebruikt wordt, maar nog niet
  gerouleerd/verwijderd — overleg met gebruiker voor actie (roteren via
  @BotFather, of de hele Telegram-integratie opruimen).

## Geleerde les (meta)

Samenvattingen van lange gesprekken kunnen feiten laten "verschuiven" (bv.
eerder in deze sessie dacht ik dat Hermes het huidige hoofdmodel was, terwijl
`TODO.md` al documenteerde dat dat is teruggedraaid naar Mistral). Bij twijfel
over de huidige staat: check eerst dit bestand en `docs/angie/TODO.md`
("Afgerond") en het meest recente patchscript dat de relevante node/credential
aanraakt, in plaats van op eerdere conversatie-aannames te vertrouwen.
