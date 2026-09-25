# AI providers

The AI in Virtual Bike Assessor does exactly three jobs:

| Job | Input | Output |
|---|---|---|
| **Classify symptom** | What the rider typed ("it goes wonky when I ride") | A symptom id, or none |
| **Interpret answer** | A typed reply to a check question | `ok`, `problem` or `unsure` |
| **Assess photo** | A photo plus the check it's for | Verdict (`ok` / `problem` / `unclear`), confidence 0–1, and a short observation |

Everything else (which question to ask, the diagnosis, safety warnings,
prices) is done by the rule engine. All providers share one interface,
`AiService` in `app/lib/ai/ai_service.dart`.

## Choosing a provider

The provider is chosen when the app is built, in this order:

| Setting present | Provider | Where the key lives |
|---|---|---|
| `GEMINI_API_KEY` | **Gemini** (`GeminiAiService`), called from the app | Built into the app |
| `ASSESS_ENDPOINT` | **Backend function** (`RemoteAiService`), which calls Claude | On the server |
| neither | **Offline** (`LocalAiService`), keyword matching only | none |

Gemini and the backend both **fall back to offline matching** if a call fails
(bad key, rate limit, no signal). The chat then shows a short notice with the
reason, so failures are never silent.

---

## Offline (default, free)

- Symptom matching compares the rider's words against each symptom's
  `customer_phrases` and `label`.
- Answer interpretation only acts on clear words: *fine / good / ok* means
  ok, and *worn / loose / broken / noise / leaking…* means problem. Anything
  else is `unsure`. "Yes" and "no" are deliberately ignored, because questions
  mix polarity.
- Photos are attached to the session for a technician but not judged.

## Gemini (free tier, for prototyping)

1. Create a key at <https://aistudio.google.com/apikey>.
2. Create the secrets file from the template (it's gitignored):
   ```bash
   cd app && cp secrets.example.json secrets.json
   ```
3. Put your key in `app/secrets.json`:
   ```json
   {
     "GEMINI_API_KEY": "your-key",
     "GEMINI_MODEL": "gemini-3.8-flash"
   }
   ```
4. Run or build with it:
   ```bash
   cd app && flutter run --release --dart-define-from-file=secrets.json
   ```

The home screen doesn't show the provider name. To confirm Gemini is working,
type a free-text answer: if Gemini fails, the chat says so.

**How it calls Gemini:** `POST https://generativelanguage.googleapis.com/v1beta/models/<model>:generateContent`,
with the key in the `x-goog-api-key` header (never in the URL). It uses a JSON
response schema, so the reply is always structured. Photos are sent inline as
base64. The app also sends `X-Ios-Bundle-Identifier: uk.bikeassessor.bikeAssessor`,
so the key can be restricted to this app in Google Cloud.

**Important:**
- The key is built into the app, so anyone with the app file could extract it.
  Only use this for personal testing and demos.
- On Gemini's free tier, Google may use what you send to improve its
  products. Don't send real customers' photos or personal details through it.
- Free-tier rate limits change. Check Google's current limits if requests start failing.

## Claude, through the backend function (for production)

The Supabase Edge Function in `supabase/functions/assess/index.ts` keeps the
API key on the server. The app sends `{ "action": "classify" | "interpret" | "photo", … }`
and gets structured JSON back.

1. Create a Supabase project and install the Supabase CLI.
2. Store the key and deploy:
   ```bash
   supabase secrets set ANTHROPIC_API_KEY=your-key
   ```
   ```bash
   supabase functions deploy assess
   ```
3. Build the app pointing at it (these can also go in `secrets.json`):
   ```bash
   cd app && flutter run --release --dart-define=ASSESS_ENDPOINT=https://<project>.supabase.co/functions/v1/assess --dart-define=ASSESS_API_KEY=<supabase anon key>
   ```

The model defaults to `claude-opus-5` and can be changed with the
`CLAUDE_MODEL` secret. Server-side refusal fallbacks are turned on.

The same function can be adapted to call Gemini's paid tier instead. The app
side doesn't change, because it only talks to the function.

## Adding another provider

Implement `AiService` (`name`, `lastError`, `classifySymptom`,
`interpretAnswer`, `assessPhoto`), then select it in `AppServices.load()` in
`app/lib/app_services.dart`. Keep the safety wording from the existing prompts:
never judge a safety-critical item as fine unless the evidence is clear.
