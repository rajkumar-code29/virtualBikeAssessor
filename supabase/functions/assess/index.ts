// Copyright (c) 2026 Raj Kumar G K. All rights reserved.
// Proprietary and confidential. See LICENSE in the project root.

// Supabase Edge Function: the only place the Claude API key lives.
//
// The app sends one of three narrow jobs. Claude never decides the diagnosis
// or the next question; the app's rule engine does. Claude only turns free
// text and photos into structured answers.
//
//   action "classify"  { text, symptoms: [{id, label, phrases}] }         -> { symptom_id, confidence }
//   action "interpret" { question, check, answer }                        -> { answer: ok|problem|unsure }
//   action "photo"     { check: {...}, media_type, image_base64 }         -> { verdict, confidence, observations, image_usable }
//
// Deploy:  supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
//          supabase functions deploy assess

import Anthropic from "npm:@anthropic-ai/sdk";

const client = new Anthropic(); // reads ANTHROPIC_API_KEY
const MODEL = Deno.env.get("CLAUDE_MODEL") ?? "claude-opus-5";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, content-type, apikey, x-client-info",
};

const IMAGE_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"] as const;
type ImageType = (typeof IMAGE_TYPES)[number];

const SYSTEM = `You help a bike workshop assess bikes remotely, using the workshop's M-check.
Customers describe problems in everyday words and may be unsure of bike terminology.
Be conservative: if something is unclear, say so rather than guessing.
Never judge a safety-critical item (brakes, frame, headset, hubs, handlebars, eBike battery) as fine unless the evidence is clear.`;

type Json = Record<string, unknown>;

async function ask(
  content: Anthropic.Beta.BetaContentBlockParam[] | string,
  schema: Json,
  effort: "low" | "medium",
): Promise<Json> {
  const response = await client.beta.messages.create({
    model: MODEL,
    max_tokens: 2048,
    betas: ["server-side-fallback-2026-07-01"],
    // On a safety-classifier decline, re-run on Anthropic's recommended model.
    fallbacks: "default",
    system: SYSTEM,
    output_config: { effort, format: { type: "json_schema", schema } },
    messages: [{ role: "user", content }],
  });

  if (response.stop_reason === "refusal") throw new Error("refused");
  if (response.stop_reason === "max_tokens") throw new Error("truncated");
  const text = response.content.find((b) => b.type === "text");
  if (!text || text.type !== "text") throw new Error("no text block");
  return JSON.parse(text.text);
}

function classify(body: Json) {
  const symptoms = body.symptoms as { id: string; label: string; phrases: string[] }[];
  const list = symptoms
    .map((s) => `- ${s.id}: ${s.label} (e.g. ${s.phrases.join("; ")})`)
    .join("\n");
  return ask(
    `A customer described their bike problem as:
<customer>${body.text}</customer>

Pick the single best matching symptom id from this list. Use "general_check" if they
just want the bike checked over, and null if none fits or it's too vague.
${list}`,
    {
      type: "object",
      properties: {
        symptom_id: { type: ["string", "null"], enum: [...symptoms.map((s) => s.id), null] },
        confidence: { type: "number" },
      },
      required: ["symptom_id", "confidence"],
      additionalProperties: false,
    },
    "low",
  );
}

function interpret(body: Json) {
  return ask(
    `The workshop check is: "${body.check}"
We asked the customer: "${body.question}"
They replied: <customer>${body.answer}</customer>

Classify the reply for this check:
- "ok": the check passes (no fault described)
- "problem": they describe a fault this check would fail on
- "unsure": they don't know, didn't answer, or it's ambiguous
Watch the question's polarity: "yes" can mean ok or problem depending on how it was asked.`,
    {
      type: "object",
      properties: { answer: { type: "string", enum: ["ok", "problem", "unsure"] } },
      required: ["answer"],
      additionalProperties: false,
    },
    "low",
  );
}

function photo(body: Json) {
  const check = body.check as {
    id: string;
    mcheck_text: string;
    guidance?: string;
    safety_critical?: boolean;
  };
  const mediaType = body.media_type as string;
  if (!IMAGE_TYPES.includes(mediaType as ImageType)) {
    throw new Error(`unsupported media type ${mediaType}`);
  }
  return ask(
    [
      {
        type: "image",
        source: { type: "base64", media_type: mediaType as ImageType, data: body.image_base64 as string },
      },
      {
        type: "text",
        text: `Workshop check: "${check.mcheck_text}"
The customer was asked for: ${check.guidance ?? "a photo of this area"}.
${check.safety_critical ? "This is a SAFETY-CRITICAL check. Only return \"ok\" if the photo clearly shows the part in good condition.\n" : ""}
Judge only this check from the photo.
- verdict "ok" / "problem" / "unclear" (use "unclear" if the relevant part isn't visible or in focus)
- confidence 0-1
- observations: one or two plain-English sentences for the customer about what you can see
- image_usable: false if the photo doesn't show the requested area`,
      },
    ],
    {
      type: "object",
      properties: {
        verdict: { type: "string", enum: ["ok", "problem", "unclear"] },
        confidence: { type: "number" },
        observations: { type: "string" },
        image_usable: { type: "boolean" },
      },
      required: ["verdict", "confidence", "observations", "image_usable"],
      additionalProperties: false,
    },
    "medium",
  );
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return new Response("POST only", { status: 405, headers: cors });

  try {
    const body = (await req.json()) as Json;
    const handlers: Record<string, (b: Json) => Promise<Json>> = { classify, interpret, photo };
    const handler = handlers[body.action as string];
    if (!handler) {
      return Response.json({ error: "unknown action" }, { status: 400, headers: cors });
    }
    return Response.json(await handler(body), { headers: cors });
  } catch (e) {
    if (e instanceof Anthropic.RateLimitError) {
      return Response.json({ error: "busy, try again" }, { status: 429, headers: cors });
    }
    if (e instanceof Anthropic.APIError) {
      console.error("Claude API error", e.status, e.message);
      return Response.json({ error: "ai unavailable" }, { status: 502, headers: cors });
    }
    console.error(e);
    return Response.json({ error: String(e) }, { status: 500, headers: cors });
  }
});
