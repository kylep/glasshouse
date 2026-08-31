# What each signing tier actually buys

The living answer to "should I pay Apple $99, and what would App Store release
take?" Verified 2026-08-30 against Apple's published capability matrix and
Xcode 26.2's own cached portal capability list
(`DVTPortal.framework/.../DVTPortalCachedPortalCapabilities.json`), which is the
data Xcode itself uses to decide what a team may sign.

**Current tier: free Personal Team.** Sideloaded, no App Store intent.

## Free Personal Team

Richer than folklore suggests. A free Apple Account can sign:

**App Groups · AutoFill Credential Provider · Data Protection · HealthKit ·
HomeKit · Increased Memory Limit · Inter-App Audio · Mac Catalyst · Maps ·
Wireless Accessory Configuration**

Plus two that are free because they are not portal-gated at all:
**Keychain Sharing** (`keychain-access-groups`) and **Background Modes**
(`UIBackgroundModes` is an Info.plist array, not an entitlement — so *all*
background modes qualify, including background location and `bluetooth-central`).

**HealthKit being free is the most counterintuitive finding here**, and it is
confirmed independently by Apple's matrix and Xcode's own capability data.

Anything needing only an Info.plist usage string is also free, which covers most
of what this app does: Core Motion, Core Location, camera, microphone, Photos,
Contacts, EventKit, Speech, Core Bluetooth, Vision, ARKit, NearbyInteraction.

### Operational limits

- Provisioning profiles expire after **7 days**. Re-signing is routine, not an
  incident.
- **10** concurrent App IDs, each expiring after 7 days.
- **3** registered devices per platform, also expiring after 7 days.

## What $99/yr adds

Push Notifications · iCloud/CloudKit · Sign in with Apple · Associated Domains ·
Access WiFi Information · Core NFC · Network Extensions · App Attest/DeviceCheck ·
Siri · Wallet · Apple Pay · WeatherKit · Communication Notifications (and
therefore Focus status) · Family Controls (development only) · 1-year profiles ·
TestFlight · ad-hoc distribution.

Relevant to this app specifically:

| Capability | Why you might want it |
|---|---|
| Access WiFi Information | SSID/BSSID — but *also* requires precise location authorization |
| Core NFC | Tag reading |
| Communication Notifications | Focus status — returns one Bool, not the Focus name |
| Associated Domains | Universal links on `glasshouse.fit` |
| WeatherKit | 500k calls/month included per membership |

## What money alone cannot buy

These need the paid program **plus** a per-entitlement request granted by Apple:

- **Multicast networking** (`networking.multicast`) — needed to browse arbitrary
  Bonjour service types. Without it, LAN enumeration is limited even on device.
- **HotspotHelper**, **CarPlay**, **Critical Alerts**, **Fall Detection**,
  **Family Controls distribution**.

And one that is effectively closed to a personal project at any price:

- **SensorKit** (`sensorkit.reader.allow`) — ambient light, PPG, ECG, wrist
  temperature, keyboard metrics, phone and message usage. Granted only for
  Apple-approved research studies with ethics-board sign-off, submitted through
  researchandcare.org. The system terminates an app whose signature lacks it.
  *Documented and closed.* (Also being redesigned: `SRSensorReader` is deprecated
  in iOS 27 in favour of a generic `SRReader`.)

## What App Store release would take

Not a current goal, recorded so the cost stays visible:

1. **App Review will reject gratuitous sensor access.** Every permission needs a
   user-facing justification tied to a feature. "Showing you that this data
   exists" is a coherent argument, but it must be built into the product rather
   than asserted in review notes.
2. **A privacy manifest becomes mandatory.** `PrivacyInfo.xcprivacy` is an App
   Store Connect *upload* gate, not a runtime requirement — the OS never reads
   it and the simulator ignores it, so a sideloaded build needs none. But the
   required-reason API categories (file timestamps, boot time, disk space,
   active keyboards, `UserDefaults`) are precisely what a read-everything app
   touches. **Write one anyway**; it is cheap now and blocking later.
3. **Privacy labels** must be declared manually in App Store Connect. There is
   no API.
4. **Fingerprinting is banned regardless of consent.** Apple's wording is
   explicit: even with tracking permission granted, fingerprinting is not
   allowed. An app that reads every available signal is exactly the shape that
   attracts scrutiny here.
5. **`LSApplicationWorkspace` is an automatic rejection** by static binary scan,
   even in dead code.

## Recommendation

Stay free through Phase 5. The only capabilities the paid tier unlocks that this
app genuinely wants are Wi-Fi SSID, NFC, and Focus status — three sensors out of
a dozen-plus. Decide at device day, with the checklist in
`device-verification.md` in hand and evidence of what actually broke.

One argument for paying sooner: an App ID reservation would let you hold the
name in App Store Connect without publishing. Nothing suggests the name is under
competition, so this is weak.
