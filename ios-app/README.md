# n8n Mobile — iPhone 5S companion app

Een open source iOS-app waarmee je verbinding maakt met je eigen n8n-instantie,
workflows kunt bekijken en webhooks kunt activeren — rechtstreeks vanaf je iPhone 5S.

## Kenmerken

| Functie | Details |
|---|---|
| Meerdere servers | Sla meerdere n8n-instanties op |
| Workflowoverzicht | Bekijk al je workflows met actief/inactief-status |
| Webhooks activeren | Stuur een GET/POST-verzoek naar elk webhook-pad |
| Lokale opslag | Serverinstellingen worden lokaal opgeslagen via UserDefaults |
| iOS 12 | Werkt op iPhone 5S (iOS 12.0+) |

## Vereisten

- Xcode 15 of nieuwer (gratis via de Mac App Store)
- Een actieve n8n-instantie (zelf gehost of n8n.cloud)
- Je n8n API-sleutel (Instellingen > API in n8n)
- iPhone 5S met iOS 12.0 of hoger **of** de iOS Simulator

## Project openen

```bash
open ios-app/n8nMobile.xcodeproj
```

Kies in Xcode een simulator of je eigen apparaat en tik op **Run** (▶).

## n8n configureren

1. Open je n8n-instantie in de browser.
2. Ga naar **Instellingen > n8n API**.
3. Maak een nieuwe API-sleutel aan en kopieer deze.
4. Voeg in de app een server toe met je basis-URL
   (bijv. `https://n8n.example.com`) en plak de sleutel.

## Webhook gebruiken

1. Maak in n8n een workflow aan met een **Webhook**-trigger.
2. Stel het pad in (bijv. `mijn-workflow`).
3. Open de workflow in de app en voer het pad in het veld in.
4. Tik **Webhook activeren** — de reactie van n8n verschijnt direct.

## Architectuur

```
ios-app/
├── n8nMobile.xcodeproj/          Xcode-projectbestand
└── n8nMobile/
    ├── Sources/
    │   ├── Models/
    │   │   └── N8NServer.swift   Data-modellen (server, workflow)
    │   ├── Services/
    │   │   ├── N8NAPIClient.swift  REST-client voor de n8n API
    │   │   └── ServerStore.swift   Opslaan/laden van servers
    │   └── ViewControllers/
    │       ├── ServerListViewController.swift
    │       ├── ServerFormViewController.swift
    │       ├── WorkflowListViewController.swift
    │       └── WorkflowDetailViewController.swift
    ├── Resources/
    │   └── Info.plist
    └── AppDelegate.swift
```

## Bijdragen

Pull requests zijn welkom! Open eerst een issue om de wijziging te bespreken.

## Licentie

[Apache 2.0](../LICENSE.md) — dezelfde licentie als het n8n-project.
