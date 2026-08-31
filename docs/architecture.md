# Architecture

Two constraints drive the whole layout: Xcode project files are hostile to
automated editing, and `xcodebuild test` against a simulator is far too slow to
sit inside a red-green-refactor loop.

## Logic lives in a Swift package, not the app

Everything with behaviour goes into an SPM library that builds and tests **on
macOS**. `swift test` runs in seconds — no simulator, no signing, no Xcode
project — which is the only loop fast enough for agents to iterate in.

```
Sources/
  GlasshouseCore/      Pure Swift. NO Apple sensor frameworks. All logic.
  GlasshouseSensors/   #if os(iOS) adapters. Deliberately thin.
App/                   SwiftUI shell.
Tests/                 swift test — the development loop.
```

**`GlasshouseCore` must never import CoreMotion, CoreLocation, HealthKit,
AVFoundation, Photos, Contacts, or EventKit.** Core Motion does not exist on
macOS at all, so a single import would break the fast loop permanently. Where a
framework type is needed, define a value type in Core and map to it in the
adapter.

The corollary matters as much: **anything worth testing must live on the macOS
side of that line.** The adapters cannot be unit tested here, so they must be
thin enough to be obviously correct by inspection.

## The Xcode project is generated

`project.yml` (XcodeGen) generates `Glasshouse.xcodeproj`, which is gitignored.
No agent ever touches a `.pbxproj`, and there are no merge conflicts in
generated XML. Run `scripts/bootstrap.sh` to regenerate.

From Phase 1, Info.plist usage-description strings are generated from the
capability ledger rather than hand-written, so a sensor cannot ship without a
declared purpose string.

## Every sensor is one protocol, three implementations

- **Live** — the real framework call. iOS only. Trivial by design.
- **Fake** — deterministic, seeded, no I/O. What tests run against.
- **Replay** — plays back a recorded trace. What the simulator UI runs against.

This is not a testing nicety. The simulator produces real data for roughly two
of the app's data sources and offers **no motion injection whatsoever**, so
replay is the primary development surface. It also means that when hardware
finally arrives, the work is writing thin adapters against a proven interface
rather than discovering the architecture.

## The capability ledger

`capability-ledger.yml` (Phase 1) is the spine. Each sensor declares its
framework, exact Info.plist key, required entitlement, signing tier, true
simulator behaviour, sensitivity class, and a source URL with a verification
date.

It earns its place by being **executable**. Tests assert that every registered
sensor has a row, that every row with a `plist_key` produces that key in the
generated Info.plist, that nothing above the current signing tier is reachable
from the shipping target, and that no row's `verified` date has gone stale.

The vocabulary is already typed in `GlasshouseCore`: `SensorID`, `Sensitivity`,
`SigningTier`, `SimulatorBehavior`, `RuntimeEnvironment`. Phase 1 fills the rows.

The ledger also generates the docs tables and, ultimately, the app's own
explanatory copy — it *is* the product's content, not scaffolding around it.

## Why `SimulatorBehavior` is a first-class type

The simulator fails silently: an empty array, an empty dictionary inside a
non-nil Optional, an availability flag that is quietly false. "Zero samples, no
error" is indistinguishable between a sensor that is unavailable and one that
simply has nothing to report.

Only the ledger knows which. That is why expected behaviour is recorded as data
and enforced by tests, and why `SimulatorBehavior.silenceIsExpected` exists.

## Test tiers

| Tier | Runner | Speed | Covers |
|---|---|---|---|
| Unit | `scripts/test.sh` | seconds | All logic. **Where agents live.** |
| Integration | `scripts/test-simulator.sh` | minutes | Linking, permission flows, snapshots. A gate. |
| Device | `docs/device-verification.md` | manual | Everything the simulator cannot prove |

The device checklist is generated from the ledger's `simulator:` column, so the
work is enumerated in advance rather than rediscovered on device day.
