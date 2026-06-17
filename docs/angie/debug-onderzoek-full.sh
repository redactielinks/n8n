#!/bin/bash
# Eenmalig diagnose-script: doet exact dezelfde stappen als het
# /onderzoek-commando, maar toont de echte foutmelding per stap in
# plaats van de samengevatte tekst die Telegram laat zien.
set -uo pipefail

VRAAG="nieuwste inzichten over twice exceptional"

docker exec n8n node -e "
const VRAAG = '$VRAAG';
const SEARX_URL = 'http://100.77.5.104:8081/search?format=json&q=' + encodeURIComponent(VRAAG);
const LLM_URL = 'http://100.68.46.126:27124/v1/chat/completions';

(async () => {
  console.log('== Stap 1: SearXNG ==');
  let results = [];
  try {
    const t0 = Date.now();
    const searchRes = await fetch(SEARX_URL);
    console.log('HTTP status:', searchRes.status, '| duur:', Date.now() - t0, 'ms');
    const searchData = await searchRes.json();
    results = (searchData.results || []).slice(0, 8).map(r => ({
      titel: r.title || '', url: r.url || '', samenvatting: r.content || ''
    }));
    console.log('Aantal resultaten:', results.length);
  } catch (e) {
    console.log('FOUT in stap 1:', e.name, '-', e.message);
    process.exit(1);
  }

  if (results.length === 0) {
    console.log('Geen resultaten, stop hier (zelfde als de echte tekst die je zag).');
    process.exit(0);
  }

  const bronnenTekst = results.map((r, i) =>
    (i + 1) + '. ' + r.titel + ' (' + r.url + ')\n' + r.samenvatting
  ).join('\n\n');
  console.log('Lengte bronnenTekst:', bronnenTekst.length, 'tekens');

  console.log('');
  console.log('== Stap 2: LM Studio (chat completion, kan traag zijn) ==');
  try {
    const t0 = Date.now();
    const controller = new AbortController();
    const llmTimeout = setTimeout(() => controller.abort(), 45000);
    const llmRes = await fetch(LLM_URL, {
      signal: controller.signal,
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        model: 'google/gemma-3-4b',
        messages: [{
          role: 'system',
          content: 'Je krijgt een onderzoeksvraag en zoekresultaten van het internet. Beoordeel welke bronnen betrouwbaar lijken en geef een kort antwoord met bronnenlijst.'
        }, {
          role: 'user',
          content: 'ONDERZOEKSVRAAG: ' + VRAAG + '\n\nZOEKRESULTATEN:\n' + bronnenTekst
        }],
        stream: false,
        temperature: 0.3
      })
    });
    clearTimeout(llmTimeout);
    console.log('HTTP status:', llmRes.status, '| duur:', Date.now() - t0, 'ms');
    const llmData = await llmRes.json();
    console.log('Antwoord (eerste 200 tekens):', (llmData?.choices?.[0]?.message?.content || JSON.stringify(llmData)).slice(0, 200));
  } catch (e) {
    console.log('FOUT in stap 2:', e.name, '-', e.message);
    process.exit(1);
  }
})();
"
