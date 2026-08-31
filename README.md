# Glasshouse

An iPhone app that reads every sensor it can legally reach and shows you the
readings — so "your phone knows everything about you" stops being an abstract
claim and becomes a list of numbers you can scroll.

It is deliberately invasive, and deliberately honest about it. Nothing is
collected without a visible affordance, and in this phase nothing leaves the
device at all.

> **Status: Phase 0.** Harness bootstrap. There is a build, a test suite, and
> an app shell that reports its own runtime environment. No sensors are
> implemented yet.

## Why it exists

Most people have a rough sense that apps can read their location or their
contacts. Very few have seen what that actually looks like: barometric
altitude to the metre, every photo tagged with where it was taken, the
neighbourhood of Bluetooth devices around them, or the fact that an app can
learn there is a URL on their clipboard without triggering the paste banner.

Glasshouse shows the readings, names the permission behind each one, and marks
the ones that need no permission at all.

## What it can and cannot do

Some of this is fixed by the iOS sandbox rather than by effort:

- **Reading other apps' permissions is impossible.** No public API exposes it,
  at any entitlement tier. Apple Developer Technical Support has said so
  directly. The one legitimate route to per-app sensor history is importing the
  App Privacy Report that iOS lets *you* export, which is a planned feature.
- **SensorKit is out of reach.** The framework that exposes ambient light, PPG,
  ECG, and keyboard metrics is granted only for Apple-approved research studies.
- **A free Apple Account goes further than expected.** HealthKit, all background
  modes, App Groups, Keychain Sharing, and HomeKit are all signable for free.
  Push, iCloud, NFC, Wi-Fi SSID, and Family Controls are not.

`docs/` carries the detail, with sources.

## Building

Requires Xcode 26.2 or later.

```bash
scripts/test.sh              # unit tests on macOS — seconds, no simulator
scripts/bootstrap.sh         # regenerate Glasshouse.xcodeproj from project.yml
scripts/test-simulator.sh    # build against the iOS Simulator
```

The `.xcodeproj` is **generated and gitignored**. Edit `project.yml` instead;
hand edits to the project file are overwritten.

## Architecture in one paragraph

All logic lives in `GlasshouseCore`, which imports no Apple sensor frameworks
and therefore builds and tests on macOS in seconds — that is the development
loop. `GlasshouseSensors` holds the iOS-only adapters and is kept deliberately
thin, because it cannot be unit tested. Every sensor is a protocol with three
implementations: live, a deterministic fake for tests, and a replay of recorded
traces for the simulator. That is not a testing nicety; the simulator produces
real data for roughly two of the app's data sources, so replay is the primary
development surface.

## A note on the simulator

The iOS Simulator does not enforce code signing, and every restricted framework
links cleanly there. A build can therefore appear to work perfectly while using
entitlements the signing account could never obtain — the failure arrives all at
once on first device deploy. Worse, the simulator usually fails *silently*:
`AVCaptureDevice` returns an empty array rather than nil, CoreTelephony returns
an empty dictionary inside a non-nil Optional, and Core Motion reports every
capability unavailable. "Zero samples, no error" looks the same as a working
sensor with nothing to say.

That is why expected simulator behaviour is recorded as data in the capability
ledger and enforced by tests, rather than discovered at runtime.

## Privacy

Everything stays on the device. There is no network stack in this phase, no
analytics, no crash reporting, and no third-party dependencies — and a test
fails the build if any of that changes. See `docs/` for the threat model and
the data classification.

## Licence

MIT. See `LICENSE`.
