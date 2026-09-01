# First device run

**Device:** iPhone 14 Pro (`iPhone15,2`), iOS 26.6
**Built with:** Xcode 26.2, free personal team, 7-day provisioning
**Date:** 2026-08-31

Captured automatically by `DeviceDiagnostics`, which emits one line per
capability — identifier, availability, and whether a sample arrived. It logs
**no readings**: writing location or health values into the system log would be
a worse privacy failure than anything this app exists to expose.

Reproduce with:

```bash
xcrun devicectl device process launch --device <name> --console fit.glasshouse.app
```

## Headline

| | Simulator | Device |
|---|---|---|
| Capabilities present | 50 | 50 |
| Producing readings | 7 | **10** |
| Readable with no prompt | 7 | **8** |
| Unexplained anomalies | 0 | **0** |

Zero anomalies means every silent capability gave a reason for its silence that
matched what the ledger predicted. That is the property the whole
`SensorAvailability` design exists to protect, and it held on first contact with
real hardware.

## The three that only work on a phone

These had never produced a single sample before — every Core Motion path in the
project had only ever reported "unavailable".

| Capability | Device result |
|---|---|
| `core_motion.accelerometer` | `ready`, 3 fields |
| `core_motion.gyroscope` | `ready`, 3 fields |
| `device.battery` | `ready`, 3 fields |

All three were **broken until the code review**, and would have reported nothing
even on hardware:

- The accelerometer and gyroscope read `accelerometerData` immediately after
  `start`, before the first sample lands, so both would have returned nil on
  every refresh — and never stopped the sensor afterwards.
- Battery checked `batteryLevel` in the same breath as enabling monitoring; the
  level populates asynchronously, so the first read saw `-1` and reported
  "this device doesn't have the hardware" on a phone that plainly has a battery.

The review caught all three as theory. The device confirmed the fixes.

## Waiting on a permission prompt

Correct behaviour, not failures. Each needs the dialog before it can report:

`calendar.events` · `contacts.all` · `core_location.position` ·
`core_location.heading` · `core_motion.altimeter_relative` ·
`core_motion.pedometer` · `photos.library` · `photos.asset_location` ·
`reminders.all` · `pasteboard.contents` (app-level consent, not a system dialog)

**Next run should grant these**, which is what will exercise the barometer, the
pedometer's historical query, and the photo-EXIF location mapping — the last of
which is the app's best demonstration and has still only ever run against the
simulator's six seeded images.

## Still unimplemented

Twenty-six capabilities report `notImplemented`, which is honest rather than
broken — they are in the ledger with no adapter yet. The most valuable to build
next, given they can only be verified here:

- **`bluetooth.scan`** — the highest-value sensor needing no entitlement, and
  completely unavailable in a simulator.
- **`health.*`** — free-team signable, and the deepest data on the device.
- **`av.microphone`** and **`av.camera`** — the camera in particular has never
  been exercised, since a simulator reports zero capture devices.
- **`telephony.radio_technology`** — worth doing purely to confirm the measured
  simulator trap (an empty dictionary inside a non-nil Optional) behaves
  differently on a phone with a real baseband.

## Toolchain note

The build targeted iOS 26.6 from Xcode 26.2, whose newest iOS SDK is 26.2. The
device-support mismatch I expected to block this **did not materialise** —
install and launch both worked without complaint. The recommendation to upgrade
Xcode stands, but it is a smaller problem than the earlier report implied.

## Getting here

Two steps needed a human and could not be automated, both correctly:

1. **Pairing.** The phone arrived unpaired; `xcrun devicectl manage pair`
   triggers the prompt, but the Trust tap is physical.
2. **Trusting the developer certificate.** Settings → General → VPN & Device
   Management → the developer profile → Trust. Until then, launch fails with
   "invalid code signature, inadequate entitlements or its profile has not been
   explicitly trusted".

One thing that cost time and is worth writing down: the Team ID is **not** the
identifier in the certificate's common name. `Apple Development: you@example.com
(A1B2C3D4E5)` — that parenthetical is a per-developer ID. The Team ID is in the
certificate's **OU** field, readable with:

```bash
security find-certificate -c "Apple Development: <email> (<id>)" -p \
  | openssl x509 -noout -subject
```
