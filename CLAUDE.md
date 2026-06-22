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

## Hermes Agent (Mac Mini) — sinds 20 juni 2026

- Naast Project Angie (Pi) draait sinds 20 juni 2026 ook **Hermes Agent**
  (NousResearch, https://github.com/NousResearch/hermes-agent) op de Mac
  Mini — een zelfstandige CLI-agent, los geïnstalleerd door de gebruiker.
  Bewuste keuzes (door de gebruiker bevestigd): model **OpenRouter /
  nousresearch/hermes-4-70b** (dezelfde OpenRouter-credential als Angie),
  het bestaande (nog niet-geroteerde) Telegram-bottoken hergebruikt voor de
  Hermes-gateway, en koppeling met Angie via MCP.
- `docs/angie/hermes-agent/angie_mcp_bridge.py`: een stdio-MCP-server
  (Python, `mcp`-package, `FastMCP`) die op de Mac Mini naast Hermes Agent
  draait en tool-aanroepen doorzet naar de bestaande n8n-webhook
  (`/webhook/angie-cli`) — zo kan Hermes Agent de Angie-wiki/kennisbank
  gebruiken zonder dat n8n zelf een MCP-server moet worden. Verwacht één
  env var: `ANGIE_WEBHOOK_URL` (de volledige webhook-URL). Gevalideerd met
  een gemockte webhook (succespad + onbereikbaar-pad).
- **Belangrijke beperking:** ik (Claude) heb, net als bij de Pi, geen
  directe terminal-/SSH-toegang tot de Mac Mini. De officiële
  configuratiedocs (`hermes-agent.nousresearch.com/docs/...`) blokkeren
  geautomatiseerd ophalen (HTTP 403) — alleen de bronbestanden in de
  GitHub-repo zelf (`.env.example`, `cli-config.yaml.example`) waren
  bruikbaar. Daaruit bevestigd: env-vars `OPENROUTER_API_KEY`,
  `TELEGRAM_BOT_TOKEN` (plus `TELEGRAM_ALLOWED_USERS` e.d.), en een
  `mcp_servers:`-blok in `cli-config.yaml` met per server `command`+`args`
  (stdio, zoals onze bridge) of `url` (remote/SSE). De **exacte**
  installatielocatie van die config (repo-clone-pad vs. `~/.hermes/...`)
  staat niet vast vanuit de documentatie — dit moet bevestigd worden via
  een korte discovery op de Mac Mini zelf voor verdere stappen.

## Geleerde les (meta)

Samenvattingen van lange gesprekken kunnen feiten laten "verschuiven" (bv.
eerder in deze sessie dacht ik dat Hermes het huidige hoofdmodel was, terwijl
`TODO.md` al documenteerde dat dat is teruggedraaid naar Mistral). Bij twijfel
over de huidige staat: check eerst dit bestand en `docs/angie/TODO.md`
("Afgerond") en het meest recente patchscript dat de relevante node/credential
aanraakt, in plaats van op eerdere conversatie-aannames te vertrouwen.
