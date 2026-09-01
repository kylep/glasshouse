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

## D3 — The privacy report decoder supports both candidate schemas

**Decided:** Built the App Privacy Report decoder to detect and handle *both*
schemas research turned up, rather than waiting for your real export to pick one.

**Why:** The alternative was leaving Phase 4 entirely blocked for eight hours.
Supporting both cost about thirty extra lines, and the decoder reports which
schema it detected, so a real export will immediately tell us which is right.

The design rule that matters more than the schema question: an unrecognised
shape **fails loudly** rather than decoding to an empty result. This data cannot
be re-fetched — the window is seven days and switching the report off in
Settings erases it — so a silent empty import would be much worse than a visible
error.

**Confidence:** high on the approach; **low on whether either schema is
correct.** Apple documents the report's contents and never documents the export
format. The fixtures are hand-authored from research descriptions, not captured
from a phone, so the tests pin the decoder's *behaviour* without being evidence
about iOS 26's actual output.

**What I need from you:** export a real App Privacy Report and drop it somewhere
local (not in the repo — it is personal data and the repo is public). Ten minutes
against a real file settles this.

**Reversal:** `PrivacyReportDecoder` is one file with no callers depending on the
schema enum. Deleting the losing branch once we know is trivial.

---

## D4 — Overlapping imports keep the larger hit count, not the sum

**Decided:** When the same app-and-domain pair appears in two imports,
`PrivacyReportHistory` keeps `max(hits)` rather than adding them.

**Why:** `hits` counts within a single seven-day window, and windows overlap
whenever the user imports more than once a week. Summing would inflate the
numbers. Taking the maximum under-reports a genuinely busier later window.

Under-reporting is the right direction to err in, because these numbers are used
to make claims about *other people's* apps. Overstating "this app contacted a
tracker 52 times" when it was 42 is a worse failure than understating it.

**Confidence:** medium. A more accurate approach would track per-window records
and sum only non-overlapping ones, which is a real improvement if the numbers
ever matter precisely.

**Reversal:** One `Swift.max` in `PrivacyReportHistory.merge`, with a test
(`hitsDoNotAccumulate`) that pins the current behaviour and will fail loudly if
it changes.

---

## D5 — I wrote the sensor adapters directly instead of fanning out to agents

**Decided:** Built the live adapters myself rather than dispatching one
implementer agent per ledger row, which is what the plan described.

**Why:** All the verified Apple research was already in context from the six
research agents that ran the day before — exact plist keys, measured simulator
behaviour, entitlement tiers, and the specific traps (`AVCaptureDevice` returning
an empty array, `CBManager.authorization` disagreeing with `state`).

Dispatching implementers would have meant each one re-deriving facts already
established, and — the real risk — some of them reaching for training-data recall
instead of re-verifying. That is precisely the failure mode `apple-api-researcher`
exists to prevent, and it would have been reintroduced by the fan-out itself.

The harness is real and the agent definitions are good. The fan-out just was not
the cheapest correct path on this particular day, with this particular context
already loaded.

**Confidence:** high for today. The calculus reverses for the next batch of
sensors, when the research is no longer in context.

**Reversal:** Nothing to undo. `.claude/agents/` is ready for the next batch, and
an independent reviewer agent audited the adapters afterwards.

---

## D6 — Attribution history is stored with complete file protection

**Decided:** `attribution-history.json` is written with
`.completeFileProtection` rather than the project's default of
complete-until-first-unlock.

**Why:** It holds other people's app activity — which apps touched a camera or a
microphone, and when — which the ledger classifies as `intimate`. Complete
protection makes it unreadable while the device is locked. That normally costs
background access, but this app only ever runs in the foreground, so it costs
nothing here.

**Confidence:** high. This is the strictest sensible option and it has no
downside for the current design.

**Reversal:** One options array in `AttributionStore.save()`. Note that if the
app ever gains background behaviour, this becomes a real constraint rather than a
free win.

---

## D7 — Local network scanning stays unimplemented, on purpose

**Decided:** `network.local` gets no adapter in this phase, despite being
catalogued and despite `NSLocalNetworkUsageDescription` already shipping.

**Why:** discovering devices on the LAN means sending mDNS and Bonjour traffic.
That is packets leaving the device, which the project's no-egress invariant
forbids — and `NWBrowser` is on the banned list precisely so this cannot be
added absent-mindedly.

The invariant could be relaxed for it. I would rather not: "nothing leaves the
device" is the strongest claim this app makes, and the moment it acquires an
exception for one convenient case it becomes a claim with a footnote. Local
network discovery is also the one sensor whose readings are about *other
people's* hardware on a shared network, which makes it the worst candidate for
the first exception.

**Confidence:** medium. A reasonable person would say multicast on your own LAN
is not "leaving the device" in any meaningful sense, and they would have a point.

**Reversal:** add `NWBrowser` to the allowlist in `InvariantTests`, alongside
the existing `NWPathMonitor` carve-out, and write the adapter. The ledger row,
the usage description, and the research are all already there.

## D8 — One shared sensor store across the tabs

**Decided:** `SensorStore` is created once in `GlasshouseApp` and passed into
both `RootView` and `RecordingView`, rather than each tab owning its own.

**Why:** replay would otherwise be a lie. Loading a recording in the Record tab
has to change what the sensor list shows; with two independent stores the app
could display live readings on one screen while claiming to replay on another.

An app whose entire argument is that people are misled about their own data has
no business being ambiguous about whether a number on its own screen is real.
That is also why replaying puts an orange banner above everything — "These are
recorded readings, not live" — rather than a subtle badge.

**Confidence:** high on the sharing; medium on the shape. A single shared store
is the simplest thing that guarantees consistency, but it does mean the two
tabs are coupled through it.

**Reversal:** give `RecordingView` its own store again and pass replay state
through a binding or an environment value instead. The banner logic already
reads from a single `replaying` property, so it would move intact.
