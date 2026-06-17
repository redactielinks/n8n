# TODO — Project Angie

Geparkeerde punten, bewust uitgesteld. Elke regel heeft een script dat al
klaarstaat, zodat oppakken straks één commando is.

## Open

- **OpenWeatherMap-credential herstellen.** Zelfde decryptiefout als eerder
  bij OpenRouter: credential dateert van voor de sleutelwijziging op 13
  juni, nooit opnieuw opgeslagen. Gevolg: de "Weer"-tool faalt stil, de
  agent verzint een generiek antwoord in plaats van een echte
  weersverwachting. Script staat klaar: `fix-weer-credential.sh`.
- **Google Maps API-sleutel roteren.** De oude sleutel is per ongeluk
  blootgesteld (zichtbaar geweest in een export/terminal/chat). Eerste
  rotatiepoging gebruikte per ongeluk de letterlijke placeholder-tekst in
  plaats van de echte nieuwe sleutel, dus de tool staat nu met een
  ongeldige sleutel (veilig, geen crash, maar niet functioneel). Wachten
  op: de echte sleutel terugvinden in Google Cloud Console. Script staat
  klaar: `rotate-google-maps-key.sh`.
- **Gmail/Calendar/Workspace OAuth2-credentials herstellen.** Zelfde
  sleutelwijziging-probleem als bij OpenRouter en OpenWeatherMap, maar deze
  credentials gebruiken OAuth2 (opnieuw inloggen via een knop in de
  n8n-webinterface), niet een los API-sleuteltje. Geen script mogelijk
  zonder browsertoegang tot de n8n-webinterface op een ander apparaat dan
  de iPhone. Wachten op: laptop/computer met browser beschikbaar.
- **Artikelen publiceren op Substack via n8n.** Substack heeft geen
  officiële publicatie-API. De enige route is via Substacks niet-publieke,
  reverse-engineered API met een sessiecookie (`connect.sid`) als sleutel —
  gekozen ondanks de fragiliteit (kan stoppen met werken bij wijzigingen
  aan Substacks backend). Eerste stap: die cookie ophalen uit de
  Netwerk-tab van desktop-browser-devtools (F12); dit is niet mogelijk
  vanaf de iPhone alleen, de cookie is HttpOnly en dus onzichtbaar voor
  gewone JavaScript-trucjes. Nog geen script: wachten op desktop-browser-
  toegang (bijv. via een scherm op de Mac Mini) om de cookie op te halen.

## Afgerond

- ~~Overstap van lokaal LLM (Gemma/Mac Mini) naar OpenRouter/Mistral~~ —
  17 juni 2026.
- ~~OpenRouter-credential decryptiefout~~ — 17 juni 2026.
- ~~Hermes als model proberen~~ — geen Hermes-variant op OpenRouter
  ondersteunt tool-calling, dus niet geschikt voor deze agent. Terug naar
  Mistral. 17 juni 2026.
