# Diagnostic engine

The engine (`app/lib/engine/assessment_engine.dart`) turns a conversation into
a diagnosis. It works the way a technician does at the counter: start from
the most likely causes of a symptom, ask the question that best narrows them
down, and stop once the answer is clear, while never skipping safety checks.

The engine is deterministic: the same answers always give the same result.
All of its knowledge comes from `mcheck_kb.json` (see
[Knowledge base](KNOWLEDGE_BASE.md)).

## 1. Intake

Every assessment starts with the KB's `intake_questions`, in order:

| Question | Used for |
|---|---|
| Make and model (free text, optional photo, can skip) | Stored for the technician |
| Is it an eBike? | Turns on the eBike section and eligibility checks |
| Brake type (rim / cable disc / hydraulic disc / not sure) | Filters brake checks through `applies_if` |
| Suspension (none / front / front and rear) | Turns on the suspension check |
| Reason | Routes to a symptom or to the full check |

If the brake type is "not sure", every brake check applies. It's safer to ask
an extra question than to skip one.

## 2. Routing

The reason is either a tapped symptom or free text, which the AI (or offline
keyword matching) turns into a symptom id. That leads to one of two flows.

### Full check (`general_check`)

Every applicable check that has a customer question is asked, in this order:

1. eBike eligibility checks (the ones that stop all work if failed),
2. the rest of the eBike section,
3. all **safety-critical** checks,
4. everything else, in M-check form order.

Checks whose failure only produces a booking note (battery key, battery
charged) aren't asked. They're shown as reminders on the results screen.

### Symptom flow

Each symptom lists its **candidate causes**, each with a starting probability,
for example:

```json
"gears_slipping": { "chain_wear": 0.35, "chainring_cassette": 0.25,
                    "gears_operate": 0.25, "gear_mechs": 0.15 }
```

The engine keeps a live probability for each candidate (the `posterior`) and
updates it after every answer.

## 3. Choosing the next question

For a symptom flow, the next question is chosen like this:

1. **eBike gate.** If the bike is an eBike, any unanswered eligibility check
   (a `stop_work` check) is asked first. If the shop can't work on the bike,
   nothing else matters.
2. **Safety first.** Any safety-critical check in the symptom's `ask_order`
   that applies and hasn't been answered is asked next, whatever its
   probability.
3. **Most likely cause.** Otherwise, the engine asks about the cause with the
   highest current probability. That covers both M-check questions and the
   symptom's extra questions (an extra question scores by the most likely
   cause it affects). The order in `ask_order` breaks ties.
4. **Stop.** When every remaining question is about a cause below 10%
   (`askThreshold = 0.1`), the assessment ends.

## 4. Updating probabilities

After each answer the probability of the cause asked about is multiplied by
a factor, and then all probabilities are rescaled to add up to 1:

| Answer | Factor | Constant |
|---|---|---|
| Something's wrong | × 5 | `problemFactor` |
| All good | × 0.15 | `okFactor` |
| Not sure | × 1 (no change) | |
| Extra-question option that *supports* a cause | × 4 (a cause not yet listed starts at 0.05) | `supportFactor` |
| Extra-question option that *weakens* a cause | × 0.2 | `weakenFactor` |

These factors are hand-set starting values. The plan is to replace them with
values measured from technician-confirmed outcomes (see [Roadmap](ROADMAP.md)).

**Stop-work rule:** if an eBike eligibility check fails (unapproved system,
not EAPC-compliant, damaged battery, modified), the assessment ends at once
with *"We can't service this bike"*.

## 5. Photos and free text

The chat screen, not the engine, combines the rider's answer with an AI photo
verdict:

- The rider's answer always wins, except when they answer **Not sure**.
- If they're unsure and the photo verdict is at least **70% confident**:
  - a photo showing a **problem** is recorded as a problem,
  - a photo showing the part is **OK** is recorded as OK, **unless the check is
    safety-critical**. A photo alone never clears brakes, frame, headset, hubs,
    bars or battery.

Typed answers are classified by the AI as `ok / problem / unsure`, taking the
question's wording into account ("yes" can mean either). Offline, only clear
words count ("fine" means ok, "worn" means problem), and anything else is
"unsure".

## 6. Building the result

| Result part | How it's produced |
|---|---|
| **Findings** | Every check answered *Something's wrong*, plus causes supported by extra questions |
| **Most likely (unconfirmed)** | In a symptom flow where nothing was confirmed, the top one or two remaining causes (not ones answered *All good*), shown as *Possible* and needing a hands-on check |
| **Not sure list** | Checks answered *Not sure*, shown as "Worth a technician looking at" |
| **Can't service** | Failed eBike eligibility checks, with the KB's message |
| **Booking notes** | eBike reminders (bring the key, charge the battery) and advice such as "Replace brake fluid every 12 months" |

Findings are sorted with **stop riding** first, then safety-critical, then the rest.

### Confidence

| Label | Rule |
|---|---|
| **High confidence** | Rider reported a problem **and** an AI photo verdict agreed with at least 70% confidence |
| **Likely** | Rider reported a problem (self-test, photo or conversation) |
| **Possible** | Inferred rather than confirmed, **or** the check is `tech_only` (frame cracks, chain wear) |

A finding is marked **Needs hands-on check** if it's unconfirmed, `tech_only`
or safety-critical.

### Stop riding

A confirmed finding shows the *stop riding* warning if its check has
`stop_riding: true`, or if it's safety-critical with a `stop_riding_if`
condition. Those conditions (such as "grinding noise" or "cranks loose") can't
be verified remotely, so the app plays safe.

## 7. Price estimate

`app/lib/engine/estimate.dart` prices each finding using the shop config:

- **The most likely repair** is the first repair in the check's
  `on_fail.repairs` list. That sets the **low** end of the range.
- **The dearest alternative** in the same list sets the **high** end.
- **Repair price** = the shop's fixed `price` if set, otherwise
  `labour_minutes ÷ 60 × labour_rate_per_hour + parts_estimate`. Anything
  unpriced shows as *Price on inspection*.
- **Combined jobs.** If two findings can be fixed by one repair offered for
  both (for example worn chain + worn cassette gives *Replace chain and
  cassette*), they're quoted once, and the second shows *Included above*.
- **Service tier tip.** With two or more findings, the app suggests the lowest
  service tier (Bronze → Platinum) whose checks cover all of them, with its
  price if the shop has set one.

## 8. Tests

`app/test/engine_test.dart` covers:

- KB integrity: 36 checks, 13 symptoms, every reference resolves, every
  repair priced.
- Intake order, and hiding the eBike symptom for non-eBikes.
- Symptom flows: confirmed cause, safety checks always asked, stop-riding
  warnings, extra questions, the unconfirmed fallback.
- Full check: safety-critical first, filtering out checks that don't apply,
  the eBike stop-work rule.
- Pricing: ranges, merged combined jobs, tier suggestion, customer-facing
  fault names.

Run them with:

```bash
cd app && flutter test
```
