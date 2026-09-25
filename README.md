# Virtual Bike Assessor

**Remote bike diagnosis based on the workshop M-check.**

Virtual Bike Assessor is a mobile app (iPhone, Android and web) that helps a
cyclist work out what's wrong with their bike before they visit a workshop.
It asks the questions a technician would ask at the counter, guides the rider
through quick self-tests, looks at photos, and then tells them:

- what is **most likely wrong**, and how confident it is,
- whether it's **safe to ride**,
- what the repair **should cost**, and
- how to **request a booking**.

It also records what a technician later finds on the bike, so the app's
diagnosis can be measured and improved over time.

> Created by **Raj Kumar G K**, a working bicycle technician. The diagnostic
> logic comes from real workshop practice: the 36-point M-check used during
> services and repair assessments.

---

## Contents

| Document | What it covers |
|---|---|
| [Architecture](docs/ARCHITECTURE.md) | How the pieces fit together, the design principles, and the folder layout |
| [Diagnostic engine](docs/DIAGNOSTIC_ENGINE.md) | How questions are chosen, how likelihoods update, the safety rules, and how results and prices are worked out |
| [Knowledge base and pricing](docs/KNOWLEDGE_BASE.md) | The format of the M-check knowledge base and the shop price file, and how to edit them |
| [AI providers](docs/AI_PROVIDERS.md) | Offline mode, Gemini and Claude, where API keys go, and privacy notes |
| [Setup, testing and release](docs/SETUP_AND_RELEASE.md) | Running the app, tests, installing on an iPhone, changing the icon, troubleshooting |
| [Roadmap and learning loop](docs/ROADMAP.md) | How the app will learn from technician feedback, and what's planned next |

---

## Features

- **Conversational assessment.** Tap an answer or type in your own words.
  Questions come with a *quick check* the rider can do in about 30 seconds.
- **Symptom-led or full check.** Start from a problem ("my chain skips") or run
  the full M-check, with safety-critical items first.
- **Photo guidance.** The app asks for specific photos (for example "close-up
  of the pad against the rim") and can have an AI judge them.
- **Safety first.** Safety-critical questions are highlighted and always
  asked. A confirmed safety fault shows a *stop riding* warning. A photo can
  never clear a safety-critical item on its own.
- **Honest confidence.** Every finding is labelled *High confidence*, *Likely*
  or *Possible*. Items that can't be judged remotely are marked *Needs
  hands-on check*.
- **Price estimates.** Uses the shop's own price list, gives a range, merges
  overlapping jobs (for example chain + cassette), and suggests a service tier
  when it's better value.
- **eBike eligibility.** Checks the eBike rules (approved system, EAPC
  compliance, battery condition, no modifications) before anything else.
- **Booking request.** Sends the shop a ready-written summary by email, or
  opens a booking page.
- **Tech review.** Technicians confirm what was actually wrong. That builds
  the labelled data used to improve the diagnosis.
- **Works offline.** Every flow works with no AI and no internet. The AI only
  adds free-text understanding and photo judging.

## Tech stack

| Layer | Technology |
|---|---|
| App | Flutter 3 (Dart), Material 3, one codebase for iOS, Android and web |
| Diagnosis | Custom rule engine in pure Dart, driven by a JSON knowledge base |
| AI (optional) | Google Gemini (called from the app) or Anthropic Claude (through a backend function) |
| Backend (optional) | Supabase Edge Function (Deno / TypeScript) |
| Storage | JSON files on the device (a Supabase database is planned) |

## Quick start

```bash
cd app && flutter pub get
```

```bash
cd app && flutter test
```

```bash
cd app && flutter run
```

To run with Gemini AI, see [AI providers](docs/AI_PROVIDERS.md). To install
on an iPhone, see [Setup, testing and release](docs/SETUP_AND_RELEASE.md).

## Project layout

```
virtualBikeAssessor/
├── app/                        Flutter app
│   ├── assets/kb/              M-check knowledge base (JSON)
│   ├── assets/config/          Shop prices and booking details (JSON)
│   ├── assets/icon/            Source image for the app icon
│   ├── lib/                    App source code
│   └── test/                   Automated tests
├── supabase/functions/assess/  Optional backend function for server-side AI
├── docs/                       Documentation
├── LICENSE
└── README.md
```

## Status

This is a working **MVP**:

- The diagnostic engine, chat, results, pricing, booking request and tech
  review all work.
- The automated tests pass.
- Prices in `shop_config.json` are **example values** for development.

See the [Roadmap](docs/ROADMAP.md) for what comes next.

## Disclaimer

Virtual Bike Assessor gives remote guidance only. It is not an inspection, and
some faults can only be found hands-on. If there is any doubt about whether a
bike is safe, it should not be ridden until a qualified technician has checked it.

## License

Copyright © 2026 **Raj Kumar G K**. All rights reserved.

This is proprietary software. No part of it may be used, copied, modified or
distributed without the author's written permission. See [LICENSE](LICENSE).
