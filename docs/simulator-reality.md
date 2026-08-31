# What the Simulator can and cannot prove

Everything on this page was **measured**, not inferred, unless marked otherwise.
Probe binaries were compiled against `iPhoneSimulator26.2.sdk` and run inside a
booted iPhone 17 Pro on iOS 26.2, and `simctl` behaviour was taken from local
`xcrun simctl help` output rather than documentation.

Verified 2026-08-30 against Xcode 26.2 (17C52) / iOS 26.2 (23C54).

## The two facts that shape the project

**The Simulator does not enforce entitlements.** `iPhoneSimulator.platform`
sets `CODE_SIGNING_ALLOWED = NO`. Simulator builds are unsigned, carry no
provisioning profile, and have nothing to enforce. Every restricted framework —
SensorKit, FamilyControls, CoreNFC, NetworkExtension — ships in the simulator
SDK and links cleanly. Xcode will even scaffold a Family Controls extension from
a stock template that a free Personal Team can never sign.

So a build can be perfect here and unshippable on a phone, and the discovery
arrives all at once on first device deploy. Budget for it.

**The Simulator fails silently.** It rarely throws when hardware is missing; it
returns something empty, and empty looks like working code that found nothing:

| API | What you get |
|---|---|
| `AVCaptureDevice.DiscoverySession` | An **empty array**, not nil — so `devices.first!` crashes |
| `CTTelephonyNetworkInfo` | An **empty dictionary inside a non-nil Optional** |
| `CBManager.authorization` | `.allowedAlways`, while `CBCentralManager.state` is `.unsupported` |
| `simctl status_bar --batteryLevel` | Status-bar chrome only; never reaches `UIDevice` |
| `simctl privacy grant photos` | Writes TCC, but PhotoKit still reads `.notDetermined` |

**Always gate Bluetooth on `state`, never on `authorization`.** And never treat
zero samples as success — check the expected behaviour in the ledger.

## Measured: what returns nothing

Every Core Motion availability check returns `false`, without exception:
accelerometer, gyroscope, magnetometer, device motion, all six pedometer
capabilities, relative and absolute altimeter, motion activity, headphone
motion, sensor recorder.

Also dead: `CLLocationManager.headingAvailable()` (no magnetometer), iBeacon
ranging, camera and depth capture, ARKit in every configuration,
NearbyInteraction, proximity monitoring, battery level and state (monitoring
cannot even be enabled), and `SpeechTranscriber` (iOS 26) which reports
unavailable with zero locales.

`processorCount` and `physicalMemory` report the **host Mac**, not a phone.

`JournalingSuggestions.framework` is absent from the simulator SDK entirely.

## Measured: what actually works, with real seeded data

This was the pleasant surprise. A stock simulator is not empty:

- **~90 calendar events** across several calendars — birthdays, holidays,
  found-in-mail — plus a Reminders list. The richest seeded source.
  (Two probes counted 87 and 92 over different windows; treat as approximate.)
- **6 contacts** with full phone numbers, emails, and postal addresses.
- **6 photos carrying real GPS and full EXIF** — Iceland, San Francisco, Marin
  — down to `Make=NIKON CORPORATION, Model=NIKON D90`, ISO, aperture, focal
  length. One carries a `-180,-180` sentinel for the no-GPS case, which is a
  free edge-case fixture.

Also working: location (fully scriptable), microphone (passes through real host
Mac audio), `HKHealthStore.isHealthDataAvailable()` returning **true**, Vision's
text recognition, pasteboard, network path, locale, and accessibility settings.

Face ID is testable once enrolled through Features → Face ID.

**Vision is partial.** `RecognizeTextRequest` works; faces, barcodes, saliency,
and body pose all fail with `Could not create inference context`. The ANE-backed
paths need a device. *(Observed on one Apple Silicon Mac — worth one
confirmation on yours.)*

## The control surface

```bash
# Deterministic GPS tracks — the one genuinely drivable sensor
xcrun simctl location booted start --speed=15 --interval=1 \
    43.6532,-79.3832 43.7615,-79.4111

xcrun simctl location booted set 45.4215,-75.6972
xcrun simctl location booted run "Freeway Drive"   # also: City Run, City Bicycle Ride, Apple
xcrun simctl location booted list                  # empty unless the device is BOOTED

# Permissions
xcrun simctl privacy booted grant  photos fit.glasshouse.app
xcrun simctl privacy booted reset  all

# Fixtures
xcrun simctl addmedia booted photo-with-gps.jpg contacts.vcf
xcrun simctl pbcopy booted < clipboard-fixture.txt

# Isolation
xcrun simctl clone <device> "glasshouse-test" && xcrun simctl erase <clone>
```

**Valid `privacy` services:** `all`, `calendar`, `contacts`, `contacts-limited`,
`location`, `location-always`, `photos`, `photos-add`, `media-library`,
`microphone`, `motion`, `reminders`, `siri` — plus two that work but are
**absent from the help text**: `camera` and `willow` (HomeKit).

**No service exists** for Bluetooth, HealthKit, local network, tracking (ATT),
speech recognition, notifications, or Focus. Those need a driven prompt or a
device.

### Two scripting gotchas

- **There is no motion injection.** Nothing in `simctl` feeds accelerometer,
  gyroscope, magnetometer, or barometer data. `privacy motion` toggles the
  permission with no data behind it. This is why every Core Motion reader sits
  behind a protocol with a replay implementation.
- **Headless boots hang.** With Simulator.app not attached, `simctl ui` and
  `simctl status_bar` hang indefinitely. Attach Simulator.app in automation.

## Toolchain version gap

The local runtime is iOS 26.2 while shipping iOS is 26.6.x. This cannot be
closed without upgrading Xcode — measured: `xcodebuild -downloadPlatform iOS
-buildVersion` refuses 26.1, 26.3, 26.5 and 26.9 as "not available for
download", while 18.6 downloads immediately. Apple exposes *previous majors* to
an older Xcode, never newer point releases of its own.

**Anything that changed in iOS 26.3–26.6 is untested here by construction.**

## Still unverified

- Whether `HKHealthStore.requestAuthorization` presents its sheet in the
  simulator. The framework is available; the prompt is untested — a CoreSimulator
  crash interrupted the attempt. **Test this first.**
- Whether region enter/exit events actually fire when location is driven by
  `simctl location start`. The API reports available; delivery is unproven.
- Whether `startMonitoringVisits` produces anything. Assume not.
- Whether Vision's neural failures reproduce on other machines.
