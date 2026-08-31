# The Phase 2 boundary

Written during Phase 1, deliberately, while the constraints are still cheap to
impose. Phase 2 intends to expose Glasshouse's data over a public MCP server to
third-party AI. This document says what must be true first.

It is not a design for that server. It is the list of things that, if skipped,
turn a privacy demonstration into a privacy incident.

## Start here

Phase 1 ships with **no network stack at all** — no `URLSession`, no `Network`,
no sockets, enforced by test. That is not an accident of scope. It means Phase 2
must *add* egress consciously rather than inherit an open port, and every
question below has to be answered before the first byte leaves.

## The thing worth saying plainly

Exposing this data to third-party model providers means handing your location
history, health record, contacts, and calendar to companies under **their**
terms, not yours. Data sent to a model provider may be retained, logged,
processed for abuse detection, or used in ways their terms permit and you have
not read.

That may well be a trade worth making knowingly. It must never be one made by
default because a port happened to be open. Everything below exists to keep the
decision explicit.

Two things sharpen it:

**The aggregate is the asset.** Any single reading is uninteresting. Location
plus health plus calendar plus photo metadata reconstructs a life — which is
precisely why this app is worth building, and precisely why exporting it is
different in kind from exporting any one of its parts.

**Some of the data is not yours to share.** Contacts and calendar describe other
people. They did not install this app, they cannot revoke anything, and they
will never know. That is a stronger argument for excluding them from export than
anything about your own privacy.

## Questions that must be answered

### 1. Authentication and authorization

- What proves a client is authorised? Not a bearer token in a config file that
  ends up in a screenshot.
- Is the credential per-client, revocable individually, and expiring by default?
- What happens on credential compromise — is there a revocation path that works
  in under a minute?
- Is the endpoint discoverable? A public MCP server on a known domain will be
  scanned within hours of DNS propagating.

### 2. Scope granularity

Whole-database access is the wrong default. Scopes should be expressible along
three axes at once:

- **Per sensor** — "calendar but not health"
- **Per time window** — "the last 24 hours", not "everything since install"
- **Per precision** — "the city", not "the coordinate"

A client asking for everything, forever, at full precision should be possible
but should require saying so.

### 3. Redaction and aggregation defaults

Default to the coarsest answer that satisfies the question:

- Coordinates → a place name or an H3 cell, never raw latitude and longitude,
  unless precision was explicitly granted. `FieldValue.isPrecise` already flags
  exactly these values, which is what that flag is for.
- Timestamps → rounded, unless precision was requested. Exact times are a
  correlation vector on their own.
- Contacts and calendar → counts and shapes by default, never names. "You have
  312 contacts, 47 with birthdays" answers most real questions without naming a
  single person.
- Health → categories and trends, never individual samples.

### 4. Streams that should never be exposed

A hard exclusion list, overridable only by an explicit deliberate action, never
by a scope grant:

- **Reproductive health.** Legally consequential in some jurisdictions, and the
  clearest case where exposure could cause direct harm.
- **Clinical records.**
- **Precise location history.** Coarse current location is a different question
  from a queryable historical track.
- **Contact and calendar detail** — names, numbers, addresses, attendees. Counts
  are fine; identities are other people's to give.
- **Raw pasteboard contents.**

The ledger already carries `sensitivity: .intimate` on most of these, so the
exclusion can be derived rather than hand-maintained — but derived is not the
same as automatic. Write the list explicitly and test it.

### 5. Audit logging

The user must be able to answer "what did it read, when, and who asked?" after
the fact, from the phone, without trusting the server.

Log every query: the client, the scope, the time, and what was returned at what
precision. Make it visible in the app. An audit trail the user cannot read is a
compliance artifact, not a safety feature.

### 6. Revocation semantics

- What does a client keep after revocation? Assume everything already sent is
  gone forever; design the scopes accordingly.
- Does revocation reach data already in a model provider's logs? It does not.
  Say so in the UI rather than implying otherwise.

## Non-negotiables

1. **Off by default.** A fresh install has no server, no credential, no listener.
2. **Egress is visible while it happens.** If data is leaving, the app says so.
3. **No silent scope widening.** A client cannot escalate without a new grant.
4. **The exclusion list is enforced server-side**, not by asking clients nicely.
5. **Local-first.** If it can be answered on the device, it is not sent.

## A cheaper alternative worth considering first

The stated goal is to make useful data available to AI assistants. That does not
strictly require a public server.

A local MCP server bound to the loopback interface, reachable only from the
user's own machine, gets most of the value with almost none of the risk: no
public attack surface, no DNS to scan, no credential to leak, and no third party
holding the data at rest. Remote access, if it turns out to be needed, could then
go through a tunnel the user controls rather than a service they expose.

**Recommendation: build the local case first and see whether the remote one is
still wanted afterwards.** It usually is not, and if it is, the scope, redaction,
and audit work above will all have been done already against a target that could
not leak while being built.

## Status

Nothing here is implemented. Phase 1 has no network stack, which is the point.
Revisit this document at the start of Phase 2, before writing any transport code.
