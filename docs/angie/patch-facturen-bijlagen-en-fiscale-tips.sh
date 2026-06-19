#!/bin/bash
# ============================================================
# Project Angie — Originele facturen/bonnen bewaren + boekhoudkundige
# verwerking met fiscale tips
# Machine: Raspberry Pi 5 (100.77.5.104)
# ============================================================
# Twee gerelateerde fixes voor administratie/declaratie/tickets/kopen/
# garantie/verzekeringen (de rubrieken uit patch-persoonlijke-rubrieken.sh):
#
# 1. Geuploade facturen/bonnen (PDF) belandden als "notitie" onder
#    Persoonlijk in plaats van onder de juiste rubriek, en het originele
#    PDF-bestand werd nergens bewaard -- alleen de geextraheerde tekst.
#    Dat is niet handig: voor de belastingdienst of een winkel (garantie)
#    moet je het origineel kunnen tonen, niet alleen een tekstkopie.
#    Fix: een deterministische "lijkt dit op een factuur"-heuristiek
#    (zelfde patroon als de eerdere receptdetectie) zet zo'n bericht altijd
#    op /administratie, ook als de LLM-classificatie traag is of timeout.
#    En: de wiki-site (app.py, los gedeployed via update-wiki-site.sh)
#    bewaart het originele PDF-bestand voortaan in een staging-map; deze
#    workflow verplaatst het naar bijlagen/ binnen de uiteindelijke pagina
#    en linkt het er vanuit. Komt een upload toch als notitie terecht
#    (vangnet), dan wordt de bijlage ook daar niet stilletjes verloren.
#
# 2. /administratie, /declaratie, /tickets, /kopen, /garantie en
#    /verzekeringen sloegen tot nu toe alleen de rauwe tekst op. Nu haalt
#    een lokaal LLM-model boekhoudkundige/fiscale kerngegevens uit de tekst
#    (leverancier, bedrag, btw, vermoedelijke aftrekbaarheid) en geeft een
#    proactieve tip, plus een vaste herinnering aan de wettelijke
#    bewaarplicht (7 jaar) en een disclaimer dat dit geen fiscaal advies is.
#
# Bevat ook de latere verbeteringen (gebundeld, voor een schone installatie
# in 1 keer): deterministische herkenning van tickets/garantie/verzekeringen
# (naast facturen/recepten), een "factuur"-regex zonder woordgrens-bug (matcht
# ook "factuurnummer"), en echte LLM-gegenereerde korte titels (titel_kort /
# genereerKorteTitel) in plaats van kale tekst-afkapping. Draait dit script
# al op een bestaande installatie? Gebruik dan
# patch-rubrieken-en-llm-titels.sh, die voegt alleen die verbeteringen toe.
#
# Vereist dat patch-persoonlijke-rubrieken.sh al is uitgevoerd (anders
# bestaat SIMPELE_RUBRIEKEN nog niet om uit te breiden).
#
# Voer dit uit OP de Raspberry Pi. Verwijder eerst een eventuele oude lokale
# kopie en download daarna vers:
#   rm -f patch-facturen-bijlagen-en-fiscale-tips.sh
#   curl -fsSL -o patch-facturen-bijlagen-en-fiscale-tips.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/patch-facturen-bijlagen-en-fiscale-tips.sh?t=$(date +%s)"
#   grep -q "verwerkFinancieelDocument" patch-facturen-bijlagen-en-fiscale-tips.sh && echo "OK: juiste versie gedownload" || echo "FOUT: oude/verkeerde versie"
#   bash patch-facturen-bijlagen-en-fiscale-tips.sh
#
# Daarna ALSNOG update-wiki-site.sh opnieuw draaien (deze patch alleen doet
# de n8n-kant; app.py moet ook vers gedownload worden voor de bijlage-
# opslag):
#   rm -f update-wiki-site.sh
#   curl -fsSL -o update-wiki-site.sh "https://raw.githubusercontent.com/redactielinks/n8n/claude/angie-https-tunnel-foss-hfqqzl/docs/angie/update-wiki-site.sh?t=$(date +%s)"
#   bash update-wiki-site.sh
# ============================================================
set -euo pipefail

SCRIPT_VERSIE="2026-06-19-facturen-bijlagen-fiscale-tips-1"
echo "==> Scriptversie: ${SCRIPT_VERSIE} (regel-aantal: $(wc -l < "${BASH_SOURCE[0]}"))"

WF_ID="YdNGeswnhhzFdTFy"
DB="/home/redactielinks/.n8n/database.sqlite"
KENNISBANK_DIR="/home/redactielinks/kennisbank"

echo "==> Exporteren..."
docker exec n8n n8n export:workflow --all --output=/tmp/sec.json 2>/dev/null
docker cp n8n:/tmp/sec.json /tmp/sec.json

echo "==> Patchen..."
python3 - <<'PYEOF_INNER'
import json

NIEUWE_JS = r"""
const inp = $input.first().json;
let text = (inp.text || inp.message?.text || '').trim();
const chatId = String(inp.message?.from?.id || inp.chatId || '7319477310');
const source = inp.source || 'telegram';
const bijlage = inp.bijlage || null;
const voice = inp.message?.voice || inp.message?.audio;
const fs = require('fs');
const path = require('path');
const http = require('http');
const https = require('https');
const { URL } = require('url');

const TELEGRAM_TOKEN = '8622180504:AAF-WK0seg3n8I4VGUS5xo_dQgw9PXGVyUU';
const LLM_URL = 'http://100.68.46.126:27124/v1/chat/completions';
const WHISPER_URL = 'http://100.68.46.126:27125/transcribe';
const SEARX_BASE = 'http://100.77.5.104:8081/search?format=json&q=';

// Buffer is hier niet beschikbaar (bleek eerder al bij de /onderzoek-fix).
// Voor binaire audio gebruiken we daarom 'binary' (latin1) string-encoding:
// elke byte komt 1-op-1 overeen met een char code 0-255, dus dat is
// lossless zonder ooit de Buffer-API aan te raken.
function httpRequest(opts) {
  return new Promise((resolve, reject) => {
    const u = new URL(opts.url);
    const lib = u.protocol === 'https:' ? https : http;
    const isBinaryBody = typeof opts.body === 'string' && opts.bodyEncoding === 'binary';
    let bodyStr;
    if (isBinaryBody) {
      bodyStr = opts.body;
    } else if (opts.body !== undefined) {
      bodyStr = JSON.stringify(opts.body);
    }
    const headers = Object.assign({}, opts.headers || {});
    if (bodyStr !== undefined && !headers['Content-Type']) {
      headers['Content-Type'] = isBinaryBody ? 'application/octet-stream' : 'application/json';
    }
    const req = lib.request({
      hostname: u.hostname,
      port: u.port || (u.protocol === 'https:' ? 443 : 80),
      path: u.pathname + (u.search || ''),
      method: opts.method || 'GET',
      headers,
    }, (res) => {
      res.setEncoding(opts.binary ? 'binary' : 'utf8');
      let data = '';
      res.on('data', chunk => { data += chunk; });
      res.on('end', () => {
        if (res.statusCode >= 400) {
          reject(new Error('HTTP ' + res.statusCode + ': ' + data.slice(0, 200)));
          return;
        }
        if (opts.binary) { resolve(data); return; }
        if (opts.json) {
          try { resolve(JSON.parse(data)); }
          catch (e) { reject(new Error('Geen geldige JSON: ' + data.slice(0, 200))); }
        } else {
          resolve(data);
        }
      });
    });
    req.on('error', reject);
    req.setTimeout(opts.timeout || 30000, () => req.destroy(new Error('Timeout na ' + (opts.timeout || 30000) + 'ms')));
    if (bodyStr !== undefined) req.write(bodyStr, isBinaryBody ? 'binary' : 'utf8');
    req.end();
  });
}

const KENNISBANK_WIKI = '/home/redactielinks/kennisbank/wiki';
const now = new Date();
const pad = n => String(n).padStart(2, '0');
const dateStr = now.getFullYear() + '-' + pad(now.getMonth()+1) + '-' + pad(now.getDate());
const timeStr = pad(now.getHours()) + ':' + pad(now.getMinutes());
const timestamp = dateStr + ' ' + timeStr;
const fileTs = String(now.getFullYear()) + pad(now.getMonth()+1) + pad(now.getDate()) + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds());

// Voegt een link naar een nieuwe pagina toe aan de bijbehorende
// categoriepagina (bijv. persoonlijk.md, koken.md), zodat de nieuwe
// pagina altijd bereikbaar is vanaf de wiki en geen wees-pagina wordt.
function linkInCategorie(categorieBestand, kop, titel, relPad) {
  const indexPath = path.join(KENNISBANK_WIKI, categorieBestand);
  const link = '- [' + titel + '](' + relPad + ')\n';
  if (fs.existsSync(indexPath)) {
    fs.appendFileSync(indexPath, link, 'utf8');
  } else {
    fs.writeFileSync(indexPath, '# ' + kop + '\n\n' + link, 'utf8');
  }
}

// Titels/previews komen soms uit vrije, meerregelige tekst (bijv. een
// gedeeld recept of bericht met witregels). Zonder opschonen breekt zo'n
// titel de markdown-link op de categoriepagina over meerdere regels.
function cleanPreview(s) {
  return String(s).replace(/\s+/g, ' ').trim();
}

// De eerste tekstregel van een document (aanhef van een brief, kopregel van
// een bon) beschrijft zelden waar het document over gaat -- vandaar een
// echte LLM-samenvatting in plaats van kaal afkappen. Kort en met een eigen
// (kleinere) timeout, want dit mag niet de hele opslag laten mislukken.
async function genereerKorteTitel(content) {
  const fallback = cleanPreview(content).substring(0, 60);
  try {
    const llmData = await httpRequest({
      method: 'POST', url: LLM_URL,
      headers: { 'Content-Type': 'application/json' },
      body: {
        model: 'google/gemma-3-4b',
        messages: [{
          role: 'system',
          content: 'Geef een korte titel (max 8 woorden) die samenvat waar de tekst van de gebruiker over gaat. Antwoord met alleen de titel zelf, in het Nederlands, zonder aanhalingstekens, zonder opmaak, zonder uitleg.'
        }, { role: 'user', content: content.substring(0, 2000) }],
        stream: false, temperature: 0.2,
      },
      json: true, timeout: 20000,
    });
    const titel = (llmData?.choices?.[0]?.message?.content || '').replace(/^["'`]+|["'`]+$/g, '').trim();
    return titel ? cleanPreview(titel).substring(0, 70) : fallback;
  } catch (e) {
    return fallback;
  }
}

// Het origineel van een geupload bestand (bv. een PDF-factuur) staat tot
// hier in een staging-map (zie save_attachment() in app.py) -- nodig omdat
// tekstextractie lossy is en je voor de belastingdienst/garantie het
// origineel moet kunnen tonen, niet alleen de geextraheerde tekst.
// Verplaatst het naar bijlagen/ binnen de map van de nieuwe pagina en geeft
// het relatieve linkpad terug (of '' als er geen bijlage was of verplaatsen
// mislukte -- dan gaat het opslaan van de pagina zelf gewoon door).
function linkBijlage(dir, bijlagePad) {
  if (!bijlagePad) return '';
  try {
    const srcPath = path.join(KENNISBANK_WIKI, bijlagePad);
    if (!fs.existsSync(srcPath)) return '';
    const bijlageDir = path.join(dir, 'bijlagen');
    if (!fs.existsSync(bijlageDir)) fs.mkdirSync(bijlageDir, { recursive: true });
    const bestandsnaam = path.basename(bijlagePad);
    fs.renameSync(srcPath, path.join(bijlageDir, bestandsnaam));
    return 'bijlagen/' + bestandsnaam;
  } catch (e) {
    return '';
  }
}

// Rubrieken onder Persoonlijk voor facturen/bonnen/documenten: een lokaal
// LLM-model haalt boekhoudkundige/fiscale kerngegevens uit de tekst
// (leverancier, bedrag, btw, vermoedelijke aftrekbaarheid) en geeft een
// proactieve tip, zodat dit niet alleen een opgeslagen tekstje is maar
// meteen bruikbaar voor de administratie/belastingaangifte.
const SIMPELE_RUBRIEKEN = {
  administratie: 'Administratie',
  declaratie: 'Declaratie',
  tickets: 'Tickets',
  kopen: 'Kopen',
  garantie: 'Garantie',
  verzekeringen: 'Verzekeringen',
};

async function verwerkFinancieelDocument(content) {
  const defaults = {
    leverancier: '', factuurdatum: '', factuurnummer: '',
    bedrag_excl_btw: '', btw_percentage: '', btw_bedrag: '', bedrag_incl_btw: '',
    categorie_fiscaal: '', aftrekbaar: 'onbekend', titel_kort: '',
    tip: 'Kon niet automatisch geanalyseerd worden (LLM niet bereikbaar of timeout) -- controleer zelf het bedrag en de btw.',
  };
  try {
    const llmData = await httpRequest({
      method: 'POST', url: LLM_URL,
      headers: { 'Content-Type': 'application/json' },
      body: {
        model: 'google/gemma-3-4b',
        messages: [{
          role: 'system',
          // "titel_kort" is bewust apart van "leverancier": zonder herkende
          // leverancier (bv. bij tickets/garantiebewijzen) was de titel
          // voorheen alleen het kale rubrieklabel of een afgekapte ruwe
          // tekstregel -- geen van beide beschrijft waar het document
          // werkelijk over gaat.
          content: 'Je bent een Nederlandse boekhoudkundig en fiscaal assistent voor een zelfstandig ondernemer/particulier. Je krijgt de tekst van een factuur, bon, ticket of ander document. Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel_kort":"korte titel van max 8 woorden die samenvat waar dit document over gaat, bv. \'Vliegticket KLM Amsterdam-Londen\' of \'Garantiebewijs wasmachine Bosch\', in het Nederlands","leverancier":"naam leverancier/winkel/maatschappij, of leeg","factuurdatum":"YYYY-MM-DD indien herkenbaar, anders de datum zoals vermeld, of leeg","factuurnummer":"factuur-, bon- of ticketnummer, of leeg","bedrag_excl_btw":"bedrag exclusief btw als getal met punt, of leeg","btw_percentage":"21|9|0|onbekend","btw_bedrag":"btw-bedrag als getal met punt, of leeg","bedrag_incl_btw":"totaalbedrag inclusief btw als getal met punt, of leeg","categorie_fiscaal":"korte kostencategorie, bv. Kantoorkosten, Reiskosten, Representatiekosten, ICT, Vakliteratuur, Verzekering, Aankoop, Overig","aftrekbaar":"ja|nee|deels|onbekend, vanuit het perspectief van een zelfstandig ondernemer met gemengd zakelijk/prive gebruik","tip":"1-2 zinnen praktisch en proactief advies specifiek voor dit document (bv. btw-aftrek, zakelijk vs prive gebruik, garantietermijn, bewaartermijn) -- geen algemeen fiscaal advies herhalen, dat staat al vast in de pagina"}'
        }, { role: 'user', content }],
        stream: false, temperature: 0.2,
      },
      json: true, timeout: 60000,
    });
    const raw = llmData?.choices?.[0]?.message?.content || '{}';
    const parsed = JSON.parse(raw.replace(/```json\n?|\n?```/g, '').trim());
    return Object.assign({}, defaults, parsed);
  } catch (e) {
    return defaults;
  }
}

async function slaFinancieelDocumentOp(rubriek, label, content, bijlagePad) {
  const dir = path.join(KENNISBANK_WIKI, 'persoonlijk', rubriek);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });

  const analyse = await verwerkFinancieelDocument(content);
  const bijlageLink = linkBijlage(dir, bijlagePad);

  const fmLines = ['---', 'tags:', '  - ' + rubriek, '  - ' + source];
  if (analyse.leverancier) fmLines.push('leverancier: ' + analyse.leverancier);
  if (analyse.factuurdatum) fmLines.push('factuurdatum: ' + analyse.factuurdatum);
  if (analyse.factuurnummer) fmLines.push('factuurnummer: ' + analyse.factuurnummer);
  if (analyse.bedrag_incl_btw) fmLines.push('bedrag_incl_btw: ' + analyse.bedrag_incl_btw);
  if (analyse.btw_percentage) fmLines.push('btw_percentage: ' + analyse.btw_percentage);
  if (analyse.aftrekbaar) fmLines.push('aftrekbaar: ' + analyse.aftrekbaar);
  if (bijlageLink) fmLines.push('bijlage: ' + bijlageLink);
  fmLines.push('datum: ' + timestamp, 'bron: ' + source, '---');

  // Zonder leverancier moet de kop toch beschrijven waar de pagina over
  // gaat -- anders is de titel alleen het rubrieklabel (bv. "Administratie"),
  // en laat "Recent toegevoegd" op de wiki-homepage dan voor elk document
  // dezelfde naam zien zonder enig idee wat erin staat. "titel_kort" komt
  // van het LLM en beschrijft de inhoud echt (bv. "Vliegticket KLM
  // Amsterdam-Londen"); alleen als zelfs dat leeg is (LLM-timeout) valt het
  // terug op een ruwe tekst-afkapping.
  const titel = analyse.leverancier
    ? label + ': ' + analyse.leverancier
    : label + ': ' + (analyse.titel_kort || cleanPreview(content).substring(0, 50));
  const samenvattingRegels = [
    analyse.leverancier ? '- Leverancier: ' + analyse.leverancier : '',
    analyse.factuurdatum ? '- Datum: ' + analyse.factuurdatum : '',
    analyse.factuurnummer ? '- Nummer: ' + analyse.factuurnummer : '',
    analyse.bedrag_excl_btw ? '- Bedrag excl. btw: ' + analyse.bedrag_excl_btw : '',
    analyse.btw_percentage && analyse.btw_percentage !== 'onbekend' ? '- Btw: ' + analyse.btw_percentage + '%' + (analyse.btw_bedrag ? ' (' + analyse.btw_bedrag + ')' : '') : '',
    analyse.bedrag_incl_btw ? '- Totaal incl. btw: ' + analyse.bedrag_incl_btw : '',
    analyse.categorie_fiscaal ? '- Fiscale categorie: ' + analyse.categorie_fiscaal : '',
    '- Vermoedelijk aftrekbaar: ' + (analyse.aftrekbaar || 'onbekend'),
  ].filter(Boolean).join('\n');

  // Geen blanco regels weglaten: de wiki-renderer (markdown_to_html in
  // app.py) groepeert opeenvolgende niet-lege regels tot 1 blok, dus zonder
  // lege regel tussen bv. de laatste bullet en "**Tip:**" zou die tekst aan
  // de vorige bullet vastplakken in plaats van een eigen alinea te worden.
  const bodyDelen = ['# ' + titel, ''];
  if (bijlageLink) bodyDelen.push('[Bekijk origineel](' + bijlageLink + ')', '');
  bodyDelen.push(
    '## Samenvatting', '',
    samenvattingRegels, '',
    '**Tip:** ' + analyse.tip, '',
    '_Bewaarplicht: bewaar het origineel minimaal 7 jaar voor de belastingdienst (fiscale bewaarplicht). Dit is een automatische inschatting, geen fiscaal advies -- check bij twijfel je boekhouder of de Belastingdienst._', '',
    '## Originele tekst', '',
    content
  );

  const filename = fileTs + '-' + rubriek + '.md';
  fs.writeFileSync(path.join(dir, filename), fmLines.join('\n') + '\n\n' + bodyDelen.join('\n') + '\n', 'utf8');

  const previewLabel = analyse.leverancier && analyse.bedrag_incl_btw
    ? titel + ' (' + analyse.bedrag_incl_btw + ')'
    : titel;
  linkInCategorie('persoonlijk.md', 'Persoonlijk', previewLabel, 'persoonlijk/' + rubriek + '/' + filename);

  let reply = label + ' opgeslagen';
  if (analyse.leverancier) reply += ': ' + analyse.leverancier;
  if (analyse.bedrag_incl_btw) reply += ' (' + analyse.bedrag_incl_btw + ')';
  reply += '.';
  if (analyse.aftrekbaar && analyse.aftrekbaar !== 'onbekend') reply += ' Vermoedelijk aftrekbaar: ' + analyse.aftrekbaar + '.';
  if (bijlageLink) reply += ' Origineel bewaard.';
  if (analyse.tip) reply += '\n\nTip: ' + analyse.tip;
  return reply;
}

let viaSpraak = false;

// Spraakbericht: eerst transcriberen, daarna verder als gewone tekst.
if (!text && voice && voice.file_id) {
  try {
    const fileInfo = await httpRequest({
      method: 'GET',
      url: 'https://api.telegram.org/bot' + TELEGRAM_TOKEN + '/getFile?file_id=' + voice.file_id,
      json: true, timeout: 15000,
    });
    const filePath = fileInfo?.result?.file_path;
    const audioData = await httpRequest({
      url: 'https://api.telegram.org/file/bot' + TELEGRAM_TOKEN + '/' + filePath,
      binary: true, timeout: 20000,
    });
    const transcriptData = await httpRequest({
      method: 'POST', url: WHISPER_URL,
      body: audioData, bodyEncoding: 'binary', json: true, timeout: 60000,
    });
    text = (transcriptData.text || '').trim();
    viaSpraak = true;
  } catch (e) {
    return [{ json: { replyText: 'Spraakbericht kon niet worden verwerkt (' + e.message + '). Controleer of de Whisper-server draait op de Mac Mini, of typ je bericht.', chatId, text: '', source } }];
  }
  if (!text) {
    return [{ json: { replyText: 'Ik heb niets kunnen verstaan in dat spraakbericht. Probeer het opnieuw of typ je bericht.', chatId, text: '', source } }];
  }
}

const cmdMatchRaw = text.match(/^\/(\w+)\s*([\s\S]*)/);
let cmd = (cmdMatchRaw?.[1] || '').toLowerCase();
let content = (cmdMatchRaw?.[2] || '').trim();

// Geen / getypt: eerst kijken of het overduidelijk een recept is (bevat
// zowel "ingredienten" als "bereidingswijze"/"bereiding"), zonder daarvoor
// van de LLM af te hangen — die kan bij lange, gedeelde teksten timeouten
// en valt dan terug op 'notitie', waardoor het recept niet bij Koken
// terechtkomt. Is het geen duidelijk recept, dan bepaalt Gemma de intentie.
const lijktOpRecept = /ingredi[eë]nten/i.test(text) && /bereidings?wijze|bereiding\b/i.test(text);
// Een gedeelde/geuploade factuur of bon valt zonder deze check vaak terug
// op 'notitie' onder Persoonlijk in plaats van Administratie: de LLM-
// classificatie hieronder kan bij lange, geextraheerde PDF-tekst timeouten
// (zelfde probleem als eerder bij recepten), en valt dan terug op 'notitie'.
// Let op: "factuur" zonder \b erna, want "factuurnummer" heeft geen
// woordgrens tussen "factuur" en "nummer" -- \bfactuur\b miste daardoor
// juist de meest voorkomende factuurtekst.
const lijktOpFactuur = /factuur|invoice|\bbon(nummer)?\b|\bnota\b|kwitantie|kassabon/i.test(text)
  && /btw|vat|totaalbedrag|total amount|factuurnummer|invoice number|te betalen|bedrag/i.test(text);
// Zelfde probleem als bij facturen: zonder deterministieke check voor
// tickets/garantie/verzekeringen hangt de rubriek volledig af van de
// LLM-classificatie hieronder, die bij lange geextraheerde PDF-tekst kan
// timeouten en dan altijd op 'notitie' uitkomt -- waardoor deze documenten
// nooit in hun eigen rubriek belanden.
const lijktOpTicket = /boarding pass|instapkaart|vluchtnummer|flight number|gate\s*\d|vertrektijd|departure time|stoel(plaats)?\b|seat\b|e-?ticket|treinkaartje|reisbiljet|boekingsnummer|booking reference|\bpnr\b/i.test(text);
const lijktOpGarantie = /garantie(bewijs|termijn|certificaat|periode)?\b|warranty/i.test(text);
const lijktOpVerzekering = /polis(nummer)?\b|verzekering(spolis)?\b|premie\b|dekking\b|insurance policy|eigen risico\b/i.test(text);
const VRIJE_TEKST_INTENTS = ['notitie', 'dagboek', 'idee', 'taak', 'wiki', 'onderzoek', 'braindump', 'recept', 'administratie', 'declaratie', 'tickets', 'kopen', 'garantie', 'verzekeringen'];
if (!cmdMatchRaw && text && lijktOpRecept) {
  cmd = 'recept';
  content = text;
} else if (!cmdMatchRaw && text && lijktOpTicket) {
  cmd = 'tickets';
  content = text;
} else if (!cmdMatchRaw && text && lijktOpGarantie) {
  cmd = 'garantie';
  content = text;
} else if (!cmdMatchRaw && text && lijktOpVerzekering) {
  cmd = 'verzekeringen';
  content = text;
} else if (!cmdMatchRaw && text && lijktOpFactuur) {
  cmd = 'administratie';
  content = text;
} else if (!cmdMatchRaw && text) {
  try {
    const llmData = await httpRequest({
      method: 'POST', url: LLM_URL,
      headers: { 'Content-Type': 'application/json' },
      body: {
        model: 'google/gemma-3-4b',
        messages: [{
          role: 'system',
          content: 'Bepaal welke actie het beste past bij dit bericht. Antwoord uitsluitend als JSON: {"intent":"wiki|onderzoek|braindump|idee|taak|dagboek|notitie|recept|administratie|declaratie|tickets|kopen|garantie|verzekeringen"}. wiki = vraag over eigen kennisbank/aantekeningen. onderzoek = vraag die feitelijke informatie van het internet nodig heeft. braindump = een gedachte, brainwave of idee dat verder uitgewerkt en gecheckt moet worden. idee = kort, simpel idee zonder verdere uitwerking. taak = iets dat gedaan moet worden. dagboek = persoonlijke reflectie of dagverslag. recept = een kookrecept, een receptidee, of een lijst ingredienten waar een recept van gemaakt moet worden. administratie = officiele documenten, formulieren, brieven, contracten of belastingzaken. declaratie = onkostendeclaraties of bonnetjes die je later wilt terugvragen. tickets = vlieg-, trein- of evenemententickets en boarding passes. kopen = aankoopbonnen, aankoopbewijzen, of dingen die je wilt kopen of net gekocht hebt. garantie = garantiebewijzen of garantietermijnen van producten. verzekeringen = polissen of verzekeringsdocumenten. notitie = losse aantekening die nergens anders bij past.'
        }, { role: 'user', content: text }],
        stream: false, temperature: 0.1,
      },
      json: true, timeout: 45000,
    });
    const raw = llmData?.choices?.[0]?.message?.content || '{}';
    const parsed = JSON.parse(raw.replace(/```json\n?|\n?```/g, '').trim());
    cmd = VRIJE_TEKST_INTENTS.includes(parsed.intent) ? parsed.intent : 'notitie';
  } catch (e) {
    cmd = 'notitie';
  }
  content = text;
}

let replyText = '';

if (cmd === 'notitie' || cmd === 'notities' || cmd === 'note') {
  const dir = path.join(KENNISBANK_WIKI, 'persoonlijk', 'notities');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const filename = fileTs + '-notitie.md';
  // Een echte LLM-samenvatting in plaats van de eerste tekstregel afkappen --
  // die eerste regel is vaak een aanhef of kopregel en beschrijft zelden
  // waar de notitie werkelijk over gaat.
  const preview = await genereerKorteTitel(content);
  // Vangnet: als een geuploade bijlage (PDF) hier toch belandt omdat de
  // classificatie het niet als factuur/document herkende, gaat het
  // origineel niet stilletjes verloren -- het wordt alsnog gelinkt.
  const bijlageLink = linkBijlage(dir, bijlage);
  const fmLines = ['---', 'tags:', '  - notitie', '  - ' + source, 'datum: ' + timestamp, 'bron: ' + source];
  if (bijlageLink) fmLines.push('bijlage: ' + bijlageLink);
  fmLines.push('---');
  // Zonder eigen '# '-kop valt de wiki terug op het bestandspad als titel
  // (zie extract_title in app.py) -- "Recent toegevoegd" liet dan alleen
  // een tijdstempel zien in plaats van waar de notitie over ging.
  const bodyDelen = ['# ' + (preview || 'Notitie'), ''];
  if (bijlageLink) bodyDelen.push('[Bekijk origineel](' + bijlageLink + ')', '');
  bodyDelen.push(content);
  fs.writeFileSync(path.join(dir, filename), fmLines.join('\n') + '\n\n' + bodyDelen.join('\n') + '\n', 'utf8');
  linkInCategorie('persoonlijk.md', 'Persoonlijk', preview || 'Notitie', 'persoonlijk/notities/' + filename);
  replyText = 'Notitie opgeslagen: "' + preview + '"';

} else if (cmd === 'dagboek' || cmd === 'journal') {
  const dir = path.join(KENNISBANK_WIKI, 'persoonlijk', 'dagboek');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const filename = dateStr + '.md';
  const filepath = path.join(dir, filename);
  const isNieuw = !fs.existsSync(filepath);
  const entry = '\n## ' + timestamp + '\n\n' + content + '\n';
  if (isNieuw) {
    const header = ['---', 'tags:', '  - dagboek', '  - ' + source, 'datum: ' + dateStr, 'bron: ' + source, '---', '', '# Dagboek ' + dateStr, ''].join('\n');
    fs.writeFileSync(filepath, header + entry, 'utf8');
    linkInCategorie('persoonlijk.md', 'Persoonlijk', 'Dagboek ' + dateStr, 'persoonlijk/dagboek/' + filename);
  } else {
    fs.appendFileSync(filepath, entry, 'utf8');
  }
  replyText = 'Dagboek bijgewerkt voor ' + dateStr + '.';

} else if (cmd === 'idee') {
  let titel = cleanPreview(content).substring(0, 60);
  let samenvatting = '';
  let categorie = 'Projecten';
  let prioriteit = 'Normaal';
  let tags = ['idee', source];

  try {
    const llmData = await httpRequest({
      method: 'POST',
      url: LLM_URL,
      headers: { 'Content-Type': 'application/json' },
      body: {
        model: 'google/gemma-3-4b',
        messages: [{
          role: 'system',
          content: 'Antwoord uitsluitend als JSON (geen markdown). Velden: {"titel":"max 60 tekens","samenvatting":"2-3 zinnen","categorie":"Projecten|Zakelijk|Uitvinding|Levensstijl|Kopen|Reizen|Lezen|Gezondheid|Financien","prioriteit":"Laag|Normaal|Hoog","tags":["3-5 trefwoorden"]}'
        }, {
          role: 'user',
          content: 'Brainstormidee: ' + content
        }],
        stream: false,
        temperature: 0.3
      },
      json: true,
      timeout: 45000,
    });
    const llmContent = llmData?.choices?.[0]?.message?.content || '{}';
    const meta = JSON.parse(llmContent.replace(/```json\n?|\n?```/g, '').trim());
    if (meta.titel)        titel        = cleanPreview(meta.titel).substring(0, 60);
    if (meta.samenvatting) samenvatting = String(meta.samenvatting);
    if (meta.categorie)    categorie    = String(meta.categorie);
    if (meta.prioriteit)   prioriteit   = String(meta.prioriteit);
    if (Array.isArray(meta.tags)) tags  = meta.tags.concat(['idee', source]);
  } catch(e) {
    // LLM niet beschikbaar of timeout: sla op zonder verrijking
  }

  const dir = path.join(KENNISBANK_WIKI, 'persoonlijk', 'ideeen');
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
  const tagLines = tags.map(t => '  - ' + t).join('\n');
  const fileContent = [
    '---', 'tags:', tagLines,
    'titel: ' + titel,
    'categorie: ' + categorie,
    'prioriteit: ' + prioriteit,
    'datum: ' + timestamp, 'bron: ' + source, '---', '',
    '# ' + titel, '',
    samenvatting || content, '',
    samenvatting ? ('\n## Origineel\n\n' + content) : '',
  ].join('\n');
  const filename = fileTs + '-idee.md';
  fs.writeFileSync(path.join(dir, filename), fileContent, 'utf8');
  linkInCategorie('persoonlijk.md', 'Persoonlijk', titel, 'persoonlijk/ideeen/' + filename);
  const preview = titel.length > 60 ? titel.substring(0, 60) + '...' : titel;
  replyText = 'Idee opgeslagen: "' + preview + '"' +
    (samenvatting ? '\n\n' + samenvatting.substring(0, 120) : '');

} else if (cmd === 'recept') {
  if (!content) {
    replyText = 'Stuur een recept of een lijst ingrediënten/receptidee. Voorbeeld: /recept Romige champignonsoep: champignons, room, bouillon, ui... Of: /recept ik heb kip, broccoli en rijst, wat kan ik maken?';
  } else {
    const KOKEN_DIR = path.join(KENNISBANK_WIKI, 'koken');
    if (!fs.existsSync(KOKEN_DIR)) fs.mkdirSync(KOKEN_DIR, { recursive: true });

    const REFLUX_PROMPT = `Rol: Acteer als een culinair redacteur en nutritionist. Je bent expert in de "Food Lab"-stijl en gespecialiseerd in maagvriendelijke gastronomie.

Je krijgt een bronrecept, OF een receptidee/lijst ingrediënten. Is het een lijst ingrediënten of een vaag idee, verzin dan eerst een passend basisrecept en pas daarna onderstaand protocol toe.

Transformeer het (bron)recept naar een variant met Nutri-Score A die refluxklachten actief helpt verminderen.

Het Reflux-Filter-Protocol (strikt):
1. Elimineer triggers: verwijder vetrijk vlees, frituur, rauwe ui, knoflook, chili, citrusvruchten, tomaten, chocolade en munt.
2. Voeg kalmerende ingrediënten toe: gebruik ingrediënten die de maagwand beschermen of zuur binden, zoals havermout, gember, venkel, meloen, banaan, magere vis, gevogelte (optioneel), volkoren granen en niet-zure groenten (bijv. broccoli, wortel, courgette).
3. Structuur: behoud de ziel van het gerecht, maar zorg dat het licht verteerbaar is.

Strikte richtlijnen voor de content:
- Geen emoji.
- Altijd voor 4 personen. Maak invriezen/meal-prep mogelijk.
- Toon: informeel (je/jij), direct en zonder clichés.
- Scroll-vrije instructies: vermeld bij elke stap de exacte hoeveelheid van elk toegevoegd ingrediënt.

Output (uitsluitend platte markdown, geen JSON, geen code-omkadering om het hele antwoord):
1. Titel & ondertitel als markdown-kop (# Titel, daaronder een korte cursieve ondertitel), gericht op textuur en smaak, niet medisch klinkend.
2. Teaser: compact, geschikt voor Substack.
3. Intro: max 3 zinnen, legt uit hoe deze versie de maag ontziet zonder in te leveren op de culinaire ervaring.
4. Stats per portie: markdown-tabel met kcal, koolhydraten, vetten, eiwitten, vezels en zout.
5. Ingrediënten: lijst voor 4 personen, gecategoriseerd.
6. Instructies per apparaat (Klassiek, Thermomix, Airfryer, Magnetron): herhaal bij elke stap de exacte hoeveelheid.
7. Meal prep & bewaaradvies: focus op kwaliteitsbehoud bij invriezen.

Begin je antwoord direct met de titel als "# Titel", zonder inleidende zin ervoor.`;

    let titel = cleanPreview(content.split('\n')[0].replace(/^#+\s*/, '')).substring(0, 60).trim() || 'Recept';
    let lichaam = '# ' + titel + '\n\n' + content;
    let herschreven = false;

    try {
      const llmData = await httpRequest({
        method: 'POST', url: LLM_URL,
        headers: { 'Content-Type': 'application/json' },
        body: {
          model: 'google/gemma-3-4b',
          messages: [{ role: 'system', content: REFLUX_PROMPT }, { role: 'user', content }],
          stream: false, temperature: 0.3,
        },
        json: true, timeout: 150000,
      });
      const raw = (llmData?.choices?.[0]?.message?.content || '').trim();
      if (raw) {
        lichaam = raw;
        const titleMatch = raw.match(/^#\s+(.*)$/m);
        if (titleMatch) titel = cleanPreview(titleMatch[1]).substring(0, 60).trim();
        herschreven = true;
      }
    } catch (e) {
      // LLM niet beschikbaar of timeout: bewaar het origineel ongestructureerd, niet verloren laten gaan.
    }

    const slug = (titel.toLowerCase()
      .replace(/[^a-z0-9\s-]/g, '')
      .trim()
      .replace(/\s+/g, '-')
      .substring(0, 50)) || ('recept-' + fileTs);
    let filepath = path.join(KOKEN_DIR, slug + '.md');
    let linkPad = slug;
    if (fs.existsSync(filepath)) {
      linkPad = slug + '-' + fileTs;
      filepath = path.join(KOKEN_DIR, linkPad + '.md');
    }

    const fmLines = ['---', 'tags:', '  - recept'];
    if (herschreven) fmLines.push('  - reflux-vriendelijk');
    fmLines.push('  - ' + source, 'datum: ' + timestamp, 'bron: ' + source, '---');
    fs.writeFileSync(filepath, fmLines.join('\n') + '\n\n' + lichaam.trim() + '\n', 'utf8');

    linkInCategorie('koken.md', 'Koken', titel, 'koken/' + linkPad + '.md');

    replyText = herschreven
      ? 'Recept herschreven (maagvriendelijk, reflux-filter) en opgeslagen onder Koken: "' + titel + '"'
      : 'Recept opgeslagen onder Koken: "' + titel + '" (LLM niet bereikbaar nu, dus NIET herschreven naar de maagvriendelijke versie — het origineel is wel veilig bewaard).';
  }

} else if (cmd === 'taak') {
  if (!content) {
    replyText = 'Geef een taaknaam op. Voorbeeld: /taak rapport afmaken';
  } else {
    const dir = path.join(KENNISBANK_WIKI, 'persoonlijk', 'taken');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const filename = fileTs + '-taak.md';
    const lines = [
      '---', 'tags:', '  - taak', '  - ' + source,
      'datum: ' + timestamp, 'bron: ' + source, '---', '',
      '- [ ] ' + content, '',
    ].join('\n');
    fs.writeFileSync(path.join(dir, filename), lines, 'utf8');
    const cleanContent = cleanPreview(content);
    const preview = cleanContent.length > 60 ? cleanContent.substring(0, 60) + '...' : cleanContent;
    linkInCategorie('persoonlijk.md', 'Persoonlijk', preview, 'persoonlijk/taken/' + filename);
    replyText = 'Taak aangemaakt: "' + content + '"';
  }

} else if (cmd === 'taken') {
  const openTaken = [];
  function scanDir(dir) {
    let entries;
    try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch(e) { return; }
    for (const e of entries) {
      if (e.name.startsWith('.')) continue;
      const fp = path.join(dir, e.name);
      if (e.isDirectory()) { scanDir(fp); continue; }
      if (!e.name.endsWith('.md')) continue;
      try {
        const txt = fs.readFileSync(fp, 'utf8');
        txt.split('\n').filter(l => l.includes('- [ ]')).forEach(t => openTaken.push(t.trim()));
      } catch(e2) {}
    }
  }
  scanDir(KENNISBANK_WIKI);
  if (openTaken.length === 0) {
    replyText = 'Geen openstaande taken gevonden.';
  } else {
    const lijst = openTaken.slice(0, 20).join('\n');
    replyText = 'Openstaande taken (' + openTaken.length + '):\n\n' + lijst;
  }

} else if (cmd === 'wiki') {
  if (!content) {
    replyText = 'Stel een vraag. Voorbeeld: /wiki wat staat er over de schrijfstijl?';
  } else {
    try {
      let wikiText = '';
      function scanWiki(dir, baseDir) {
        let entries;
        try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch (e) { return; }
        for (const e of entries) {
          if (e.name.startsWith('.')) continue;
          const fp = path.join(dir, e.name);
          if (e.isDirectory()) { scanWiki(fp, baseDir); continue; }
          if (!e.name.endsWith('.md')) continue;
          const rel = path.relative(baseDir, fp);
          try {
            wikiText += '\n\n## ' + rel + '\n\n' + fs.readFileSync(fp, 'utf8');
          } catch (e2) {}
        }
      }
      scanWiki(KENNISBANK_WIKI, KENNISBANK_WIKI);

      if (!wikiText.trim()) {
        replyText = 'De wiki is nog leeg.';
      } else {
        const llmData = await httpRequest({
          method: 'POST',
          url: LLM_URL,
          headers: { 'Content-Type': 'application/json' },
          body: {
            model: 'google/gemma-3-4b',
            messages: [{
              role: 'system',
              content: 'Je beantwoordt vragen uitsluitend op basis van de meegegeven wiki-inhoud. Schrijf in duidelijk, spreektaalachtig Nederlands, informeel met "je", direct ter zake, korte alinea\'s van max 3-4 regels, geen lange gedachtenstreep, geen emoji, geen clichés. Staat het antwoord niet in de wiki-inhoud, zeg dat dan expliciet in plaats van te gokken.'
            }, {
              role: 'user',
              content: 'WIKI-INHOUD:\n' + wikiText + '\n\nVRAAG: ' + content
            }],
            stream: false,
            temperature: 0.3
          },
          json: true,
          timeout: 45000,
        });
        replyText = llmData?.choices?.[0]?.message?.content || 'Geen antwoord ontvangen van het model.';
      }
    } catch(e) {
      replyText = 'Wiki niet doorzoekbaar nu (' + e.message + '). Controleer of de kennisbank-map gemount is in de n8n-container, of dat LM Studio draait op de Mac Mini.';
    }
  }

} else if (cmd === 'onderzoek') {
  if (!content) {
    replyText = 'Stel een onderzoeksvraag. Voorbeeld: /onderzoek nieuwste inzichten over twice exceptional';
  } else {
    const SEARX_URL = SEARX_BASE + encodeURIComponent(content);
    try {
      const searchData = await httpRequest({
        method: 'GET',
        url: SEARX_URL,
        json: true,
        timeout: 15000,
      });
      const results = (searchData.results || []).slice(0, 8).map(r => ({
        titel: r.title || '', url: r.url || '', samenvatting: r.content || ''
      }));

      if (results.length === 0) {
        replyText = 'Geen zoekresultaten gevonden voor "' + content + '".';
      } else {
        const bronnenTekst = results.map((r, i) =>
          (i + 1) + '. ' + r.titel + ' (' + r.url + ')\n' + r.samenvatting
        ).join('\n\n');

        const llmData = await httpRequest({
          method: 'POST',
          url: LLM_URL,
          headers: { 'Content-Type': 'application/json' },
          body: {
            model: 'google/gemma-3-4b',
            messages: [{
              role: 'system',
              content: 'Je krijgt een onderzoeksvraag en zoekresultaten van het internet. Beoordeel welke bronnen betrouwbaar lijken: officiele organisaties, vakliteratuur en bekende media wegen zwaarder dan onbekende sites of forums. Geef een kort, feitelijk antwoord gebaseerd op de betrouwbaarste bronnen, en sluit af met een genummerde lijst van de gebruikte bronnen (titel en link). Schrijf in duidelijk, spreektaalachtig Nederlands, informeel met "je", korte alinea\'s van max 3-4 regels, geen lange gedachtenstreep, geen emoji, geen clichés.'
            }, {
              role: 'user',
              content: 'ONDERZOEKSVRAAG: ' + content + '\n\nZOEKRESULTATEN:\n' + bronnenTekst
            }],
            stream: false,
            temperature: 0.3
          },
          json: true,
          timeout: 120000,
        });
        replyText = (llmData?.choices?.[0]?.message?.content || 'Geen antwoord ontvangen van het model.') +
          '\n\n(Niet automatisch opgeslagen. Plaats dit zelf in raw/ als je het wilt bewaren.)';
      }
    } catch(e) {
      replyText = 'Onderzoek niet mogelijk nu (' + e.message + '). Controleer of SearXNG (poort 8081) en LM Studio draaien.';
    }
  }

} else if (cmd === 'braindump' || cmd === 'park') {
  if (!content) {
    replyText = 'Beschrijf de gedachte die je wilt parkeren. Voorbeeld: /braindump wat als ik een cursus geef over twice exceptional ondernemerschap';
  } else {
    const dir = path.join(KENNISBANK_WIKI, 'persoonlijk', 'braindumps');
    if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
    const cleanContent = cleanPreview(content);
    const titel = cleanContent.length > 60 ? cleanContent.substring(0, 60) + '...' : cleanContent;
    const filename = fileTs + '-braindump.md';
    const filepath = path.join(dir, filename);

    // Stap 1: parkeren. Dit moet altijd lukken, los van wat hierna gebeurt,
    // anders is het geen "los kunnen laten" maar gewoon weer een open lus.
    const header = [
      '---', 'tags:', '  - braindump', '  - ' + source,
      'titel: ' + titel,
      'datum: ' + timestamp, 'bron: ' + source, '---', '',
      '# ' + titel, '',
      '## Oorspronkelijke gedachte', '',
      content, '',
    ].join('\n');
    fs.writeFileSync(filepath, header, 'utf8');
    linkInCategorie('persoonlijk.md', 'Persoonlijk', titel, 'persoonlijk/braindumps/' + filename);

    // Stap 2: verificatie, doorontwikkeling, brainstorm en mindmap.
    try {
      const SEARX_URL = SEARX_BASE + encodeURIComponent(content);

      let bronnenTekst = 'Geen zoekresultaten gevonden.';
      try {
        const searchData = await httpRequest({ method: 'GET', url: SEARX_URL, json: true, timeout: 15000 });
        const results = (searchData.results || []).slice(0, 8).map(r => ({
          titel: r.title || '', url: r.url || '', samenvatting: r.content || ''
        }));
        if (results.length > 0) {
          bronnenTekst = results.map((r, i) => (i + 1) + '. ' + r.titel + ' (' + r.url + ')\n' + r.samenvatting).join('\n\n');
        }
      } catch (e) {
        // Zoeken mislukt: LLM geeft hierna een eigen beoordeling zonder bronnen.
      }

      const llmData = await httpRequest({
        method: 'POST',
        url: LLM_URL,
        headers: { 'Content-Type': 'application/json' },
        body: {
          model: 'google/gemma-3-4b',
          messages: [{
            role: 'system',
            content: 'Je helpt een geparkeerde gedachte verder te brengen. Antwoord uitsluitend als JSON (geen markdown). Velden: {"verificatie":"2-4 zinnen die inschatten of de gedachte klopt of haalbaar is, gebaseerd op de meegegeven zoekresultaten; zeg expliciet als er geen bronnen zijn","bronnen":["titel (url), max 3"],"ontwikkeling":["3-5 concrete manieren om het idee verder uit te werken"],"brainstorm":["3-5 verwante ideeen of varianten"]}'
          }, {
            role: 'user',
            content: 'GEDACHTE: ' + content + '\n\nZOEKRESULTATEN:\n' + bronnenTekst
          }],
          stream: false,
          temperature: 0.4
        },
        json: true,
        timeout: 90000,
      });
      const llmContent = llmData?.choices?.[0]?.message?.content || '{}';
      const result = JSON.parse(llmContent.replace(/```json\n?|\n?```/g, '').trim());
      const verificatie = String(result.verificatie || 'Geen beoordeling ontvangen.');
      const bronnen = Array.isArray(result.bronnen) ? result.bronnen : [];
      const ontwikkeling = Array.isArray(result.ontwikkeling) ? result.ontwikkeling : [];
      const brainstorm = Array.isArray(result.brainstorm) ? result.brainstorm : [];

      function sanitize(s, max) {
        return String(s).replace(/[\(\)\[\]"`\n]/g, '').trim().substring(0, max || 70);
      }

      const mindmapLines = ['```mermaid', 'mindmap', '  root((' + sanitize(titel, 50) + '))'];
      if (verificatie) {
        mindmapLines.push('    Verificatie');
        mindmapLines.push('      ' + sanitize(verificatie, 70));
      }
      if (ontwikkeling.length) {
        mindmapLines.push('    Ontwikkeling');
        ontwikkeling.slice(0, 5).forEach(o => mindmapLines.push('      ' + sanitize(o, 70)));
      }
      if (brainstorm.length) {
        mindmapLines.push('    Brainstorm');
        brainstorm.slice(0, 5).forEach(b => mindmapLines.push('      ' + sanitize(b, 70)));
      }
      mindmapLines.push('```');

      const extra = [
        '', '## Verificatie', '',
        verificatie, '',
        bronnen.length ? ('Bronnen:\n' + bronnen.map(b => '- ' + b).join('\n')) : '',
        '', '## Verdere ontwikkeling', '',
        ontwikkeling.map(o => '- ' + o).join('\n'), '',
        '## Brainstorm', '',
        brainstorm.map(b => '- ' + b).join('\n'), '',
        '## Mindmap', '',
        mindmapLines.join('\n'), '',
      ].join('\n');
      fs.appendFileSync(filepath, extra, 'utf8');

      replyText = 'Gedachte geparkeerd en uitgewerkt: "' + titel + '"\n\n' +
        verificatie.substring(0, 200) + '\n\n' +
        ontwikkeling.length + ' ontwikkelrichtingen, ' + brainstorm.length + ' brainstormideeen en een mindmap toegevoegd. Open de pagina in de wiki om alles te zien.';
    } catch (e) {
      replyText = 'Gedachte geparkeerd: "' + titel + '"\n\nVerdere verwerking (onderzoek/brainstorm/mindmap) is nu niet gelukt (' + e.message + '). De gedachte staat wel veilig in de wiki, je kunt het later opnieuw proberen.';
    }
  }

} else if (cmd === 'zoek' || cmd === 'search' || cmd === 'find') {
  if (!content || content.length < 2) {
    replyText = 'Geef een zoekterm op. Voorbeeld: /zoek project aanpak';
  } else {
    const results = [];
    function searchWiki(dir, q) {
      if (results.length >= 5) return;
      let entries;
      try { entries = fs.readdirSync(dir, { withFileTypes: true }); } catch(e) { return; }
      for (const e of entries) {
        if (results.length >= 5) break;
        if (e.name.startsWith('.')) continue;
        const fp = path.join(dir, e.name);
        if (e.isDirectory()) { searchWiki(fp, q); }
        else if (e.name.endsWith('.md')) {
          try {
            const txt = fs.readFileSync(fp, 'utf8');
            if (txt.toLowerCase().includes(q.toLowerCase())) {
              const lines = txt.split('\n');
              const hit = lines.find(l => l.toLowerCase().includes(q.toLowerCase()) && l.trim() && !l.startsWith('---') && !l.startsWith('tags:')) || '';
              const clean = hit.trim().replace(/^#+\s*/, '').replace(/[*_`\[\]]/g, '').substring(0, 80);
              results.push({ name: e.name.replace('.md', ''), preview: clean });
            }
          } catch(e2) {}
        }
      }
    }
    searchWiki(KENNISBANK_WIKI, content);
    if (results.length === 0) {
      replyText = 'Geen notities gevonden voor "' + content + '".';
    } else {
      const list = results.map((r, i) =>
        (i + 1) + '. ' + r.name + (r.preview ? '\n   ' + r.preview : '')
      ).join('\n\n');
      replyText = 'Gevonden (' + results.length + ') voor "' + content + '":\n\n' + list;
    }
  }
} else if (SIMPELE_RUBRIEKEN[cmd]) {
  if (!content) {
    replyText = 'Geef de tekst op die je onder ' + SIMPELE_RUBRIEKEN[cmd] + ' wilt opslaan. Voorbeeld: /' + cmd + ' ...';
  } else {
    replyText = await slaFinancieelDocumentOp(cmd, SIMPELE_RUBRIEKEN[cmd], content, bijlage);
  }

} else {
  replyText = 'Beschikbare commando\'s:\n/notitie /dagboek /idee /taak /taken /wiki /onderzoek /braindump /recept /administratie /declaratie /tickets /kopen /garantie /verzekeringen /zoek\n\nJe kunt ook gewoon typen of een spraakbericht sturen zonder commando, dan bepaal ik zelf wat je bedoelt.';
}

if (viaSpraak) {
  replyText = 'Gehoord: "' + text.substring(0, 80) + (text.length > 80 ? '...' : '') + '"\n\n' + replyText;
}

return [{ json: { replyText, chatId, text, source } }];
""".strip()

with open('/tmp/sec.json', encoding='utf-8') as f:
    data = json.load(f)

wf = next(w for w in (data if isinstance(data, list) else [data])
          if w.get('id') == 'YdNGeswnhhzFdTFy')
print(f"Gevonden: {wf['name']}")

by_name = {n['name']: n for n in wf['nodes']}
handler = by_name.get('Verwerk Wiki Commando')
if handler is None:
    raise SystemExit("Node 'Verwerk Wiki Commando' niet gevonden -- naam/structuur is anders dan verwacht, patch afgebroken.")

huidige_js = handler['parameters']['jsCode']
if 'SIMPELE_RUBRIEKEN' not in huidige_js:
    raise SystemExit("Verwachte 'SIMPELE_RUBRIEKEN' niet gevonden -- patch-persoonlijke-rubrieken.sh moet eerst uitgevoerd zijn, patch afgebroken.")
if 'lijktOpFactuur' in huidige_js or 'verwerkFinancieelDocument' in huidige_js:
    raise SystemExit("Deze patch lijkt al uitgevoerd te zijn ('lijktOpFactuur'/'verwerkFinancieelDocument' staat er al in) -- niet opnieuw uitvoeren.")

handler['parameters']['jsCode'] = NIEUWE_JS
print("  ~ 'Verwerk Wiki Commando': factuurherkenning + bijlage-behoud (origineel PDF) + boekhoudkundige/fiscale verrijking met proactieve tips")

with open('/tmp/sec-modified.json', 'w', encoding='utf-8') as f:
    json.dump([wf], f, ensure_ascii=False, indent=2)
print("Klaar: /tmp/sec-modified.json")
PYEOF_INNER

echo "==> Importeren..."
docker cp /tmp/sec-modified.json n8n:/tmp/sec-modified.json
docker exec n8n n8n import:workflow --input=/tmp/sec-modified.json --overwrite-all

echo "==> Activeren en n8n herstarten met toegang tot de kennisbank..."
ACTIVE_VID=$(sqlite3 "${DB}" "SELECT versionId FROM workflow_history WHERE workflowId='${WF_ID}' ORDER BY createdAt DESC LIMIT 1;")
docker stop n8n 2>/dev/null || true
sqlite3 "${DB}" "UPDATE workflow_entity SET active=1, activeVersionId='${ACTIVE_VID}' WHERE id='${WF_ID}';"
WEBHOOK_URL=$(tailscale status --json | python3 -c "import sys,json; d=json.load(sys.stdin); print('https://' + d['Self']['DNSName'].rstrip('.'))")
docker rm n8n 2>/dev/null || true
docker run -d --name n8n --restart always -p 5678:5678 \
    -v /home/redactielinks/.n8n:/home/node/.n8n \
    -v /home/redactielinks/n8n-obsidian-share:/home/node/obsidian-share \
    -v "${KENNISBANK_DIR}:${KENNISBANK_DIR}" \
    -e N8N_SECURE_COOKIE=false \
    -e WEBHOOK_URL="${WEBHOOK_URL}" \
    -e NODE_FUNCTION_ALLOW_BUILTIN=fs,path,http,https,url \
    n8nio/n8n:latest
tailscale funnel --bg 5678 2>/dev/null || sudo tailscale funnel --bg 5678 2>/dev/null || true
sleep 8 && docker logs n8n --tail 3
echo ""
echo "BELANGRIJK: draai ook update-wiki-site.sh opnieuw (zie commentaar boven"
echo "in dit script) -- anders bewaart de wiki-site het originele PDF-bestand"
echo "nog niet, en komt er nooit een 'bijlage' bij deze nieuwe verwerking."
echo ""
echo "Test (factuurtekst zonder /commando, moet automatisch op /administratie"
echo "belanden, ook zonder bijlage):"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d '"'"'{"text":"Factuur van Bol.com\nFactuurnummer: F2026-001234\nBTW 21%: 8.68\nTotaalbedrag: 50.00"}'"'"''
echo "Verwacht: 'Administratie opgeslagen: Bol.com (50.00)...' met een tip en"
echo "een bewaarplicht-vermelding, NIET als losse notitie onder Persoonlijk."
echo "  cat \$(ls -t ~/kennisbank/wiki/persoonlijk/administratie/*.md | head -1)"
echo ""
echo "Test bijlage-behoud end-to-end (pas dit aan met een echte PDF op de Pi):"
echo "  cp test-factuur.pdf ~/kennisbank/wiki/_bijlagen/$(date +%Y%m%d%H%M%S)-test-factuur.pdf"
echo '  curl -s -X POST http://localhost:5678/webhook/angie-cli -H "Content-Type: application/json" -d "{\"text\":\"/administratie test\",\"bijlage\":\"_bijlagen/<exacte-bestandsnaam-hierboven>.pdf\"}"'
echo "Verwacht: het PDF-bestand staat na afloop in"
echo "~/kennisbank/wiki/persoonlijk/administratie/bijlagen/ (niet meer in _bijlagen/),"
echo "en de nieuwe pagina heeft een '[Bekijk origineel](bijlagen/...)'-link."
