# Open work

Things that are known, deliberate, and not yet done. Ordered by whether they
block anything.

---

## Your batch — do these whenever, in any order

Nothing below blocks further work; each just unlocks verification.

### Taps in the app (one minute total)

Open Glasshouse, tap into the row, hit **Ask for permission**:

| Row | Unlocks |
|---|---|
| **Bluetooth devices nearby** | The device census. Built and untested — needs no entitlement, impossible to test without hardware. |
| **Photo library** | Also unlocks **Photo locations** — the EXIF map, the app's best demonstration, still only run against simulator fixtures. |
| **Reminders** | Separate grant from calendar. |
| **Clipboard contents (notified)** | The banner half of the clipboard pair. App-level consent, not a system dialog. |
| **Vital signs** | Also unlocks **Activity and fitness** — heart rate going back years, resting rate, blood oxygen, VO2 max. The deepest data on the phone. |

Granting Photos covers both photo rows in one tap; iOS grants per permission,
not per sensor.

### Two minutes in Settings

**Turn on the App Privacy Report** — Settings → Privacy & Security → App Privacy
Report. It only records forward and keeps seven days, so every day it is off is
data that cannot be recovered later. This blocks the cross-app attribution
feature, which is built but unverified: the decoder handles two candidate
schemas because Apple documents neither, and the fixtures are hand-authored
rather than captured. See `DECISIONS.md` D3.

Once it has a few days of data, export it (share button on that screen) and drop
the `.ndjson` somewhere local — **not in this repo**, which is public.

### A decision, not a task

**Xcode 26.6.** You are on 26.2 against a phone running 26.6. The device-support
mismatch has not bitten once, so this is lower priority than it sounded
yesterday — but only a toolchain upgrade closes it, and CI is already building
against 26.6.

---

## Not blocked — just not done

### Sensors with no adapter

See the README table for the full list. The ones worth doing next, in order of
what they'd teach:

1. **Bluetooth scan** — needs no entitlement, impossible to test without
   hardware, and a rolling census of the devices around you is the most
   striking thing the app could show.
2. **HealthKit** — free-team signable and the deepest data on the phone.
3. **Camera hardware detail** — lens aperture, focal length, ISO, and the
   iOS 26 `nominalFocalLengthIn35mmFilm`, all readable without capturing a frame.
4. **Vision on the photo library** — faces and text across the camera roll.

### Known gaps in what exists

- **Values are unverified.** Every reading on device has been checked for
  *shape* — right field count, plausible type — never for correctness. Nobody
  has confirmed the battery percentage matches the phone.
- **Replay implementations do not exist.** The architecture describes live,
  fake, and replay; only live and fake are built. Recording real traces on
  device and playing them back in the Simulator is the missing third.

### Toolchain

- **Xcode 26.2 against a phone on iOS 26.6.** The device-support mismatch has
  not bitten, but the gap is real and only a toolchain upgrade closes it.

---

## Solved

Kept because the evidence is worth more than the conclusion.

### ~~Pedometer query terminates the process~~ — SOLVED 2026-09-01

**Cause: calling `CMPedometer` from a `@MainActor` context.** Nothing to do
with the API, the query window, or the usage description.

Established by bisection on an iPhone 14 Pro, iOS 26.6, Motion & Fitness
granted. Each row is a device run:

| Configuration | Result |
|---|---|
| `queryPedometerData`, 24h window, MainActor, shared object | SIGTRAP |
| `queryPedometerData`, 1h window, MainActor, shared object | SIGTRAP |
| `startUpdates`, MainActor, shared object | SIGTRAP |
| `queryPedometerData`, 1h, **detached task, own object** | **works** |

In every failing case the completion handler was never invoked and the
process died in under five seconds — before the internal timeout could fire —
so Core Motion was terminating us rather than any Swift code trapping.

Ruled out along the way: missing `NSMotionUsageDescription` (present in the
shipped bundle), the historical-query pattern in general (`CMMotionActivityManager`
queries fine from the same context), and the query window.

**One honest caveat**: the working configuration changed two things at once —
off the main actor *and* onto its own `CMPedometer`. Both are plausible causes
and I did not isolate which. The fix is stable and reproducible; the precise
mechanism is not established.

`MotionManagerBox.readSteps` is `nonisolated`, runs on a detached task, owns
its pedometer, and holds it with `withExtendedLifetime` for the duration of the
query. Do not "tidy" it back onto the MainActor.

