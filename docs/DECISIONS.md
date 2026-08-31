# Decisions made without Kyle

Judgement calls made during autonomous work, for review. Each one records what
was decided, why, how confident I am, and how to reverse it.

**Legend** — Confidence: `high` = would defend it unprompted · `medium` = a
reasonable call among alternatives · `low` = flagging because I might be wrong.

---

## D1 — Capability ledger is Swift source, not YAML

**Decided:** The ledger lives in `Sources/GlasshouseCore/Capability/` as typed
Swift values, not `capability-ledger.yml` as the plan said.

**Why:** Swift has no YAML parser in the standard library, and the project has a
zero-third-party-dependency invariant. The options were to add Yams (breaks the
invariant), write a YAML subset parser (a parser nobody asked for, and a real
source of bugs), or use JSON (no comments, and provenance matters here).

Swift source is better than all three: rows are compile-time checked, so a
malformed row fails the build rather than a test; comments are allowed; there is
no parser to get wrong; and an agent editing a row gets immediate type feedback.

**Secondary benefit that changed the design:** it collapses two things into one.
The plan had a *registry* of implemented sensors and a *ledger* of capability
metadata, kept in sync by a test. Making the ledger the registry means the
"every sensor has a ledger row" invariant is structurally impossible to violate
rather than merely tested.

**Confidence:** high.

**Reversal:** The rows are plain `Codable` values. A `swift run glasshouse-ledger
export` emits JSON; swapping to a data file later means writing a decoder and
deleting the Swift literals. Nothing else depends on the storage format.

---

## D2 — Sensitivity has four levels, and two of them collect by default

**Decided:** `ambient` → `identifying` → `personal` → `intimate`, with `ambient`
and `identifying` enabled by default and the other two off until switched on.

**Why:** The app's premise is informed exposure, so collecting personal or
intimate data before the user has engaged would be self-defeating. But making
*everything* opt-in would mean a first launch that shows an empty app and proves
nothing — and the genuinely instructive category is precisely the data that
needs no permission at all (battery, thermal state, network path, pasteboard
shape). Those are `ambient`/`identifying`, and showing them immediately is the
whole argument.

**Confidence:** medium. The line between `identifying` and `personal` is a
judgement call, and reasonable people would put coarse location on either side.
I put it in `personal`.

**Reversal:** One property, `Sensitivity.isEnabledByDefault`. Changing the
default stance is a one-line edit with a test that will fail loudly.

---
