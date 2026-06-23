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

## Upstream n8n-codebase (alleen relevant buiten docs/angie/)

Onderstaande commando's gelden voor de rest van de monorepo (pnpm workspaces
+ Turbo), maar zijn voor dit project verder niet van belang — er wordt hier
niet aan de n8n-broncode zelf ontwikkeld.

- Package manager: **pnpm ≥10.2.1** (Node.js ≥22.16), via corepack.
- `pnpm build` / `pnpm build:backend` / `pnpm build:frontend` / `pnpm build:nodes`
- `pnpm dev` (alles) / `pnpm dev:be` / `pnpm dev:fe`
- `pnpm lint` / `pnpm lintfix` / `pnpm format` / `pnpm typecheck`
- `pnpm test` (alles) / `pnpm test:backend` / `pnpm test:frontend`
  — binnen een losse package-map: `pnpm build` / `pnpm test` / `pnpm dev`
  voor alleen die package.
- E2E: `pnpm dev:e2e` (interactief) / `pnpm test:e2e:ui` (headless, Cypress).
- Workspace-structuur: `packages/cli` (n8n-CLI/backend-server),
  `packages/core` (workflow-executionengine, webhooks, LangChain-integraties),
  `packages/workflow` (gedeelde interfaces/baselogic), `packages/nodes-base`
  (400+ standaard nodes/credentials), `packages/frontend/editor-ui`
  (Vue 3-editor), plus ~30 interne `packages/@n8n/*`-libs.

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

## Werkwijze / codeervoorkeuren (algemeen)

- Always suggest tests first.
- Prefer composition over inheritance.
- Explain complex logic with comments.
- Never use `any` without explicit permission.
- Think before coding. State your assumptions out loud. If the request is
  ambiguous, ask. If a simpler approach exists, push back. Stop when you
  are confused, name what is unclear, do not just pick one interpretation
  and run.
- Simplicity first. Write the minimum code that solves the problem. No
  speculative abstractions. No flexibility nobody asked for. The test:
  would a senior engineer call this overcomplicated.
- Surgical changes. Touch only what the task requires. Do not improve
  neighboring code. Do not refactor what is not broken. Every changed
  line should trace back to the request.
- Goal-driven execution. Turn vague instructions into verifiable targets
  before writing a line. "Add validation" becomes "write tests for
  invalid inputs, then make them pass."

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
- **Telegram wordt niet meer via n8n gebruikt** — de gebruiker werkt
  rechtstreeks via de wiki-site-chat en de CLI-webhook (`/webhook/angie-cli`,
  toegevoegd door `patch-cli-bypass.sh`). Sinds Hermes Agent (Mac Mini, 22
  juni 2026) een eigen Telegram-gateway draait op datzelfde bottoken, kan
  de Telegram Trigger-node in de n8n-workflow niet langer ook actief
  blijven — één bottoken kan niet gelijktijdig een n8n-webhook én een
  losse gateway bedienen. Script staat klaar: `patch-telegram-trigger-uit.sh`
  (23 juni 2026, **nog niet bevestigd gedraaid**) — zet de node op
  `disabled` en ruimt Telegram's eigen webhook-registratie op via
  `deleteWebhook`.
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
- **Encryptiesleutel opnieuw gewisseld (ontdekt 23 juni 2026, via
  `inspect-telegram-trigger-status.sh`).** Zelfde terugkerende probleem als
  17/19 juni: een docker-herstart gaf `N8N_ENCRYPTION_KEY` niet expliciet
  mee, waardoor n8n een nieuwe sleutel genereerde. Dit keer is niet alleen
  de Telegram-credential geraakt maar ook **OpenRouter** — dus de hele
  assistent (wiki-chat, CLI-webhook, documentverwerking) stond hierdoor
  stil. Oorzaak (welke `docker run` de sleutel miste) nog niet
  achterhaald. Script staat klaar: `fix-credentials-na-sleutelwissel.sh`
  (23 juni 2026, **nog niet bevestigd gedraaid**) — laat de OpenRouter-key
  en het Telegram-bottoken opnieuw lokaal invoeren onder de huidige
  sleutel, en zet die sleutel daarna vast. **Moet vóór alle andere
  openstaande patches gedraaid worden** (die falen anders al bij de
  credential-decryptiestap, zoals ook bij `patch-telegram-trigger-uit.sh`
  gebeurde).
- **LLM-hallucinatie bij niet-factuurtekst (gemeld door gebruiker 23 juni
  2026, met screenshots).** De vrije-tekst-instructie "koppel mijn
  brouwer.gert@gmail.com account aan n8n" (gestuurd via Telegram, naar
  Hermes Agent, maar nog beantwoord door de **n8n Telegram Trigger** —
  bewijst dat die node op dat moment nog actief was, zie hieronder) werd
  door de intentclassificatie ten onrechte als `administratie`
  geclassificeerd. `verwerkFinancieelDocument` MOEST daardoor JSON-
  factuurvelden teruggeven en verzon een complete nepfactuur ("Bakkerij De
  Gouden Brood", FB-2024-0315-001, €105,93) die echt op de wiki werd
  opgeslagen. Script staat klaar:
  `patch-fix-llm-hallucinatie-niet-document.sh` (23 juni 2026, **nog niet
  bevestigd gedraaid**) — voegt een `is_document`-veld toe aan de
  LLM-extractie (geen verzonnen velden meer als de tekst geen document is,
  valt dan terug op een gewone notitie), verduidelijkt de
  intentclassificatie, én ruimt de al opgeslagen nepfactuur + koppeling op
  de Persoonlijk-pagina automatisch op. Lost niet de eigenlijke
  Gmail-koppeling op — dat kan alleen via de n8n-webinterface (OAuth2),
  zie `TODO.md`.
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

## Hermes Agent (Mac Mini) — sinds 20 juni 2026

- Naast Project Angie (Pi) draait sinds 20 juni 2026 ook **Hermes Agent**
  (NousResearch, https://github.com/NousResearch/hermes-agent) op de Mac
  Mini — een zelfstandige CLI-agent, los geïnstalleerd door de gebruiker.
  Bewuste keuzes (door de gebruiker bevestigd): het bestaande (nog
  niet-geroteerde) Telegram-bottoken hergebruikt voor de Hermes-gateway,
  en koppeling met Angie via MCP.
- **Model: OpenRouter / `mistralai/mistral-large-2512`** (niet Hermes-4-70b
  — bevestigd onbruikbaar, zie hieronder). 22 juni 2026 eerst geprobeerd
  met `nousresearch/hermes-4-70b` (zelfde OpenRouter-credential als Angie),
  maar Hermes Agent zelf geeft bij het opstarten een harde waarschuwing:
  "Nous Research Hermes 3 & 4 models are NOT agentic and are not designed
  for use with Hermes Agent. They lack tool-calling capabilities required
  for agent workflows." Dit bevestigt de eerdere bevinding bij Angie's
  hoofd-AI Agent (17 juni 2026, zie `TODO.md` "Afgerond") in een tweede,
  onafhankelijke context — ondanks dat OpenRouter's eigen modelpagina
  "function calling" als capability vermeldt. Overgezet naar
  `mistralai/mistral-large-2512` via `/model mistralai/mistral-large-2512`
  in de Hermes-chat (of `hermes model`); bevestigd functioneel getest:
  Hermes Agent roept de `angie-wiki`-MCP-tool succesvol aan en geeft het
  antwoord van de Angie-webhook correct terug.
- `docs/angie/hermes-agent/angie_mcp_bridge.py`: een stdio-MCP-server
  (Python, `mcp`-package, `FastMCP`) die op de Mac Mini naast Hermes Agent
  draait en tool-aanroepen doorzet naar de bestaande n8n-webhook
  (`/webhook/angie-cli`) — zo kan Hermes Agent de Angie-wiki/kennisbank
  gebruiken zonder dat n8n zelf een MCP-server moet worden. Verwacht één
  env var: `ANGIE_WEBHOOK_URL` (de volledige webhook-URL). Eerst gevalideerd
  met een gemockte webhook (succespad + onbereikbaar-pad), en op 22 juni
  2026 bevestigd end-to-end werkend op de Mac Mini tegen de echte Pi-webhook
  (`hermes mcp test angie-wiki` + een echte tool-aanroep vanuit een
  Hermes-chatsessie).
- **Belangrijke beperking:** ik (Claude) heb, net als bij de Pi, geen
  directe terminal-/SSH-toegang tot de Mac Mini. De officiële
  configuratiedocs (`hermes-agent.nousresearch.com/docs/...`) blokkeren
  geautomatiseerd ophalen (HTTP 403) — alleen de bronbestanden in de
  GitHub-repo zelf (`.env.example`, `cli-config.yaml.example`) waren
  bruikbaar.
- **Bevestigd via discovery op de Mac Mini (22 juni 2026):** het echte,
  actief ingelezen configuratiebestand is **`~/.hermes/config.yaml`**
  (overrideable via `HERMES_HOME`) — niet `cli-config.yaml`. Dat laatste
  bestaat alleen als voorbeeldbestand (`cli-config.yaml.example`) in de
  meegeklonede repo onder `~/.hermes/hermes-agent/`. `.env` staat ook in
  `~/.hermes/.env`. De structuur van `config.yaml` wijkt af van het
  voorbeeldbestand: geen top-level `mcp_servers:`-blok, maar een eigen
  generatorformaat. **MCP-servers dus nooit handmatig in de YAML
  schrijven** — gebruik `hermes mcp add <naam> --command ... --env
  KEY=VALUE --args <pad>` (let op: `--args` moet de laatste optie zijn,
  hij consumeert de rest van de regel). Bevestigd werkend op 22 juni 2026:
  ```
  hermes mcp add angie-wiki \
    --command /opt/homebrew/bin/python3.11 \
    --env ANGIE_WEBHOOK_URL=https://raspberrypi.tailf98f98.ts.net/webhook/angie-cli \
    --args /Users/gertbrouwer/hermes-mcp/angie_mcp_bridge.py
  ```
  → `hermes mcp test angie-wiki` en `hermes mcp list` bevestigen
  verbinding + 1 tool (`angie_command`) ingeschakeld.
- Tailscale-naam van de Pi (voor `ANGIE_WEBHOOK_URL`), opgezocht via
  `tailscale status --json` op de Mac Mini: `raspberrypi.tailf98f98.ts.net`
  (geen secret, vrij te documenteren). Webhook bevestigd bereikbaar en
  werkend via curl (`{"reply":"Geen openstaande taken gevonden."}`).
  Belangrijk: de buitenste JSON-sleutel van `/webhook/angie-cli` is
  `reply`, niet `replyText` (dat is alleen het interne n8n-veldnaam vóór
  de Respond-node 'm hernoemt, zie `patch-cli-bypass.sh`) — `angie_mcp_bridge.py`
  keek hier eerst per ongeluk naar de verkeerde sleutel (gefixt).

## Geleerde les (meta)

Samenvattingen van lange gesprekken kunnen feiten laten "verschuiven" (bv.
eerder in deze sessie dacht ik dat Hermes het huidige hoofdmodel was, terwijl
`TODO.md` al documenteerde dat dat is teruggedraaid naar Mistral). Bij twijfel
over de huidige staat: check eerst dit bestand en `docs/angie/TODO.md`
("Afgerond") en het meest recente patchscript dat de relevante node/credential
aanraakt, in plaats van op eerdere conversatie-aannames te vertrouwen.
