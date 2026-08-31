# Threat model

Draft, Phase 0. Owned by `docs-security-steward`; revisit whenever a sensor
lands.

## What makes this app unusual

Most apps hold one or two sensitive data types. Glasshouse deliberately
concentrates **the most sensitive data a phone holds** into a single local
store — location history, health, contacts, calendar, photo metadata with
coordinates, and the surrounding Bluetooth population — and it does so on
purpose, because showing the aggregate is the product.

That aggregate is worth more than the sum of its parts. Location history plus
health plus calendar reconstructs a life. A single sensor reading is
uninteresting; the join is not.

**And a later phase intends to expose it over a public MCP server to
third-party AI.** That is the actual threat, and it is why security is designed
in now rather than added later.

## Assets, in rough order of severity

1. **The aggregated local store.** The join is the asset, not any single stream.
2. **Location history**, including photo EXIF coordinates and barometric
   altitude, which is effectively a floor-level position fix.
3. **Health data**, which is unrevocable — you cannot un-share it.
4. **Contacts and calendar**, which contain data about *other people* who never
   consented to this app.
5. **Imported App Privacy Report history**, which reveals behavioural patterns
   across every app on the phone.

Note asset 4 carefully: contacts and calendar are the only streams where the
data subject is someone other than the user. They deserve stricter defaults for
that reason alone.

## Adversaries

| Adversary | Access | Mitigation |
|---|---|---|
| Someone holding the unlocked phone | Everything the UI shows | Data Protection classes; no automatic export |
| Someone holding a locked phone | File system at rest | Complete-until-first-unlock minimum; stricter for `intimate` |
| A malicious or careless future dependency | Whatever it can read in-process | Zero third-party dependencies, enforced by test |
| Anything on the network | Nothing, in this phase | **No network stack exists.** Enforced by test |
| A future MCP client (Phase 2) | Whatever the boundary permits | `phase-2-boundary.md` — unwritten, and blocking |
| Me, the developer, by accident | Committed secrets or real captures | `.gitignore` + steward review |

The last row is not a joke. The most likely breach of this repository is a
recorded sensor trace or a real App Privacy Report export committed to a public
GitHub repo by accident. Captures are gitignored for exactly this reason, and
only synthetic or hand-authored fixtures may be committed.

## Trust boundary

**In this phase, the trust boundary is the device.** Nothing crosses it.

There is no network stack, no analytics, no crash reporting, and no third-party
SDK. A test fails the build if `URLSession`, `Network`, or a socket API appears
outside a documented allowlist. The single planned exception — bundle-ID lookup
for resolving app names — is isolated behind one named boundary, off by default,
and does not exist yet.

This is a deliberate constraint rather than an accident of scope. Phase 2 must
*add* a network stack consciously; it cannot inherit an open port.

## Non-goals

- Defending against a jailbroken device or a compromised OS.
- Defending against physical extraction with the passcode known.
- Anti-forensics, or hiding the app's own activity. The premise is informed
  exposure; concealment would be self-defeating.

## Open, and blocking Phase 2

`phase-2-boundary.md` is unwritten and must be written **during** Phase 1, while
the constraints are still cheap to impose. It must answer:

- Authentication and authorization model for MCP clients
- Scope granularity — per-sensor, per-time-window, per-precision
- Redaction and aggregation defaults (coarse before precise, always)
- Revocation, and what a client keeps after revocation
- Audit logging: what was read, by whom, when — visible to the user
- **The explicit list of streams that should never be exposed regardless of
  auth.** Health and precise location history are the obvious candidates.

One thing worth stating plainly now: exposing this data to third-party model
providers means handing it over under *their* terms, not yours. That may be a
trade worth making knowingly. It should never be one made by default.
