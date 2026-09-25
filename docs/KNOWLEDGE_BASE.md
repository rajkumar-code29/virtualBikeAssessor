# Knowledge base and pricing

The app's bike knowledge lives in two JSON files. You can change how the app
diagnoses and prices without touching the code.

| File | What it holds | Who edits it |
|---|---|---|
| `app/assets/kb/mcheck_kb.json` | Checks, symptoms, repairs, questions and safety flags | A bike technician |
| `app/assets/config/shop_config.json` | Prices, labour rate, service tier prices, booking details | Each shop |

After editing either file, run `flutter test`. The tests check that every
reference points to something that exists and that every repair has a price.

---

## mcheck_kb.json

Current version: **0.2.0**: 6 sections, 36 checks, 44 repairs, 13 symptoms.

### Top-level structure

| Key | Purpose |
|---|---|
| `meta` | Name, version and notes |
| `answer_codes` | The M-check form's Y / N / * / ** codes, for reference |
| `service_tiers` | Bronze, Silver, Gold, Platinum, plus "repair" (quoted separately) and "recycle" (not repairable) |
| `standalone_services` | Brake bleed, cable services, Cycle Care, puncture sealant |
| `sections` | The M-check sections, each containing its checks |
| `repairs` | Every repair the app can recommend |
| `symptoms` | Customer complaints and their likely causes |
| `non_check_causes` | Likely causes that aren't M-check line items (for example a tyre not seated) |
| `intake_questions` | The opening questions |

### A check

```json
{
  "id": "brake_pads",
  "mcheck_text": "Do the brake pads have enough braking material left?",
  "fault_label": "Worn brake pads",
  "tier": "gold",
  "safety_critical": true,
  "customer_question": "Do the brakes squeal or make a grinding, metal-on-metal noise? …",
  "self_test": "Rim brakes: look at the grooves on the pads; …",
  "photo_request": { "needed": true, "guidance": "Rim: close-up of the pad against the rim. …" },
  "remote_confidence": "photo",
  "on_fail": {
    "repairs": ["brake_pads_replace"],
    "stop_riding_if": "grinding_noise",
    "diy_possible": true
  }
}
```

| Field | Meaning |
|---|---|
| `id` | Unique id, used everywhere else |
| `mcheck_text` | The original wording on the M-check form (shown to technicians) |
| `fault_label` | Customer-facing name shown on results when the check fails |
| `tier` | The lowest service tier that includes this check, or `repair` / `recycle` / `null` |
| `safety_critical` | Always asked in symptom flows, highlighted in chat, can't be cleared by a photo |
| `stop_work` | Failing it means no work can be done (eBike eligibility) |
| `applies_if` | When the check is relevant: `brake_type in ['rim', 'mechanical_disc']`, `brake_type == 'hydraulic_disc'`, `bike.is_ebike == true`, `bike.has_suspension == true` |
| `customer_question` | What the rider is asked. `null` means it's never asked directly |
| `self_test` | A quick check the rider can do, shown under the question |
| `photo_request` | Whether a photo helps, and what to photograph |
| `video_request` | Optional video guidance (for future tech video review) |
| `remote_confidence` | How far it can be judged remotely: `photo`, `self_test`, `conversation` or `tech_only` |
| `on_fail.repairs` | Repair ids. **The first is the most likely fix**, the rest are alternatives |
| `on_fail.outcome` | Special outcomes: `cannot_service`, `not_repairable`, `booking_note`, `product_suggestion` |
| `on_fail.message` | Text shown to the rider for that outcome |
| `on_fail.stop_riding` / `stop_riding_if` | Stop-riding warning, always or on a condition |
| `on_fail.diy_possible` | Shows a *DIY possible* tag |
| `on_fail.service_upsell` | Standalone service to suggest (for example a brake service) |
| `advice` | General advice added to the booking notes |

### A symptom

```json
{
  "id": "creak_knock_pedalling",
  "label": "Creak or knock when pedalling",
  "customer_phrases": ["creaks when pedalling", "clicking every pedal stroke"],
  "candidates": { "bottom_bracket": 0.35, "pedals": 0.3, "seat_secure": 0.15,
                  "chain_wear": 0.1, "frame_undamaged": 0.1 },
  "ask_order": ["bottom_bracket", "pedals", "seat_secure"],
  "extra_questions": [{
    "id": "creak_seated",
    "ask": "Does the noise stop when you stand up on the pedals?",
    "options": [
      { "value": "stops", "label": "Yes, it stops when I stand", "supports": ["seat_secure"] },
      { "value": "continues", "label": "No, it carries on", "weakens": ["seat_secure"] }
    ]
  }]
}
```

| Field | Meaning |
|---|---|
| `label` | Shown on the symptom choice button |
| `customer_phrases` | Everyday wording. Used by offline matching and given to the AI as examples |
| `candidates` | Likely causes (check ids or `non_check_causes` ids) with starting probabilities adding up to about 1 |
| `ask_order` | Which checks can be asked, and the tie-break order |
| `extra_questions` | Questions that aren't M-check items. Each option `supports` or `weakens` causes |
| `safety_critical` | Marks the symptom itself as safety-related |
| `service_upsell` | A standalone service to suggest (for example puncture sealant for flats) |
| `flow: "full_mcheck"` | Only on `general_check`: run the whole M-check |

### A repair

```json
{ "id": "chain_cassette_replace", "label": "Replace chain and cassette/freewheel",
  "parts": ["chain", "cassette_or_freewheel"], "labour_minutes": null, "price": null }
```

`parts` is used to spot combined jobs: a repair whose parts cover two other
repairs can replace both. Leave the prices in the KB `null`; prices belong in
the shop config.

### Common edits

- **Add a customer phrase:** append to a symptom's `customer_phrases`. This
  improves offline matching straight away.
- **Adjust likelihoods:** change a symptom's `candidates`. Keep them adding up
  to about 1.
- **Add a symptom:** add an entry with `id`, `label`, `customer_phrases`,
  `candidates` and `ask_order`. It appears as a choice automatically.
- **Add a repair:** add it to `repairs`, reference it from a check's
  `on_fail.repairs`, and give it a price in `shop_config.json`.
- **Bump `meta.version`** whenever you change the diagnosis, so logged
  sessions record which version they used.

---

## shop_config.json

```json
{
  "name": "Example Bike Workshop",
  "currency": "£",
  "example_prices": true,
  "booking_email": "bookings@example.com",
  "booking_url": null,
  "labour_rate_per_hour": 40,
  "service_tiers": { "bronze": 25, "silver": 40, "gold": 60, "platinum": 90 },
  "repairs": {
    "brake_pads_replace": { "labour_minutes": 15, "parts_estimate": 15 },
    "wheel_true": { "price": 25 }
  }
}
```

| Field | Meaning |
|---|---|
| `name` | Shown in the estimate note |
| `currency` | Symbol put in front of prices |
| `example_prices` | When `true`, the estimate is labelled *(example prices)* |
| `booking_email` | "Request a booking" opens an email to this address with the assessment summary |
| `booking_url` | If set, "Request a booking" opens this page instead |
| `labour_rate_per_hour` | Used when a repair has labour minutes but no fixed price |
| `service_tiers` | Tier prices shown in the tier tip |
| `repairs.<id>.price` | Fixed price (labour and parts). Takes priority |
| `repairs.<id>.labour_minutes` / `parts_estimate` | Used to work out a price when no fixed price is set |

> ⚠️ The values currently in the file are **placeholders for development**.
> Replace them with real shop prices before showing estimates to customers.
