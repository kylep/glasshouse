# Glasshouse — working notes for Claude

An iPhone app that reads every sensor it can legally reach and shows the user
the readings. Deliberately invasive, deliberately honest about it.

Read `docs/architecture.md` before making structural changes, and
`docs/simulator-reality.md` before trusting anything a simulator tells you.

## Hard rules

1. **`GlasshouseCore` must never import an Apple sensor framework.** No
   CoreMotion, CoreLocation, HealthKit, AVFoundation, Photos, Contacts,
   EventKit. Core Motion does not exist on macOS, so one import permanently
   breaks the fast test loop. Define value types in Core; map in the adapter.
2. **Never edit `.pbxproj` or the `.xcodeproj`.** They are generated from
   `project.yml` and gitignored. Run `scripts/bootstrap.sh`.
3. **No network stack in this phase.** No `URLSession`, no `Network`, no
   sockets. Phase 2 must add one deliberately.
4. **No third-party dependencies.** Zero is the target.
5. **Never commit captured personal data.** Real sensor traces, App Privacy
   Report exports, and GPX from an actual phone are personal data. Only
   synthetic or hand-authored fixtures go in git. This repo is public.
6. **Never `git add -A`.** Add files individually.

## The development loop

```bash
scripts/test.sh              # macOS unit tests — seconds. Use this constantly.
scripts/test-simulator.sh    # simulator build gate — minutes. Use sparingly.
```

Logic goes in `GlasshouseCore` and is tested on macOS. Adapters go in
`GlasshouseSensors`, are iOS-only, and are kept thin enough to be obviously
correct — because they cannot be unit tested here.

## Two things that will mislead you

**The simulator enforces no entitlements.** `CODE_SIGNING_ALLOWED = NO`, and
every restricted framework links cleanly. A build can look perfect while using
capabilities a free account could never sign. The failure arrives all at once on
first device deploy. This is what `capability-ledger.yml` exists to prevent.

**The simulator fails silently.** `AVCaptureDevice` returns an empty array, not
nil. CoreTelephony returns an empty dictionary inside a non-nil Optional.
`CBManager.authorization` says `.allowedAlways` while `CBCentralManager.state`
is `.unsupported` — **gate Bluetooth on `state`, never authorization**. Never
treat zero samples as success; check the ledger's `simulator:` column.

## Apple facts go stale

Verify against live Apple docs before asserting anything version-sensitive; this
project has already been bitten repeatedly. Apple's doc pages are JS shells that
cause hallucinated summaries — append `.md` to a doc URL, or use
`developer.apple.com/tutorials/data/documentation/<Path>.json`. Local sources
(`xcrun simctl help`, SDK headers) beat the web for toolchain facts.

Use the `apple-api-researcher` agent rather than recalling API behaviour.

## Agents

`.claude/agents/` — `apple-api-researcher` (verify first), `sensor-implementer`
(one sensor, TDD), `privacy-report-analyst` (NDJSON import),
`swift-test-runner` (cheap test runs), `docs-security-steward` (docs +
invariants), `ui-builder` (SwiftUI against fixtures only).

## Naming

Domain `glasshouse.fit`; bundle prefix `fit.glasshouse`; app is
`fit.glasshouse.app`.
