# Open work

Things that are known, deliberate, and not yet done. Ordered by whether they
block anything.

---

## Blocked on Kyle

### 1. Pedometer query terminates the process — needs the crash report

**Status:** quarantined behind `MotionManagerBox.pedometerQueryEnabled = false`,
so the rest of the app works. The row reports `.unavailable(.knownDefect)`
rather than claiming ready and returning nothing.

**What happens:** with Motion & Fitness granted, `CMPedometer.queryPedometerData`
kills the process with SIGTRAP. Established by bisection on an iPhone 14 Pro,
iOS 26.6, Xcode 26.2, free personal signing:

| Observation | Value |
|---|---|
| `CMPedometer.authorizationStatus()` | `.authorized` (3) |
| `CMPedometer.isStepCountingAvailable()` | true |
| `NSMotionUsageDescription` in the shipped bundle | present |
| Completion handler invoked | **never** |
| Time to death | under 5s — before the internal timeout fires |
| Disabling only this call | whole refresh completes normally |

So Core Motion terminates us inside the call; nothing in this codebase traps.
The usual explanation (missing usage description) is ruled out.

**What's needed:** the crash report names the exception and the Core Motion
frame. Only Kyle can fetch it:

> Settings → Privacy & Security → Analytics & Improvements → Analytics Data →
> find `Glasshouse-2026-…​.ips` → share it somewhere local (**not** into this
> repo — it is public, and `.ips` files carry device identifiers).

**Hypotheses worth testing once the report exists**, roughly in order:

1. A narrower query window. 24 hours may span a period with no recorded data,
   or cross a boundary Core Motion mishandles. Try 1 hour, then `startUpdates`.
2. Querying too soon after the grant, before `motiond` has provisioned the app.
   Try a delay, or trigger on a later refresh rather than the first.
3. `queryPedometerData` called from a `@MainActor` context. Try a detached
   background call.
4. A genuine iOS 26.6 defect. If so, file feedback with the sample and keep the
   quarantine.

**Do not** re-enable the flag without a device run proving it survives.

### 2. A real App Privacy Report export

Blocks the cross-app attribution feature, which is built and unverified — the
decoder handles two candidate schemas because Apple documents neither, and the
fixtures are hand-authored rather than captured. See `DECISIONS.md` D3.

Turn the report on now regardless (Settings → Privacy & Security → App Privacy
Report): it only records forward and keeps seven days, so every day it is off is
data that cannot be recovered.

### 3. Permissions still ungranted on the device

Each is one tap in the app, and each unlocks a group:

- **Photos** — unlocks the library and photo locations. The EXIF map is the
  app's best demonstration and has still only run against simulator fixtures.
- **Reminders** — separate grant from calendar.
- **Clipboard (notified)** — app-level consent, not a system dialog.

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
- **`LiveSystemStateSource` reports four ledger rows' worth of data under
  `device.thermal`** — uptime, low-power mode, and memory belong in their own
  rows.

### Toolchain

- **Xcode 26.2 against a phone on iOS 26.6.** The device-support mismatch has
  not bitten, but the gap is real and only a toolchain upgrade closes it.
