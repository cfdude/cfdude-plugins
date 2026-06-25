## ADDED Requirements

### Requirement: Backward-compatible schema load

A `state.json` written by the prior release (v0.4.1) SHALL load without error or data loss in the
0.5.0 engine. All new fields (`parent`, `externalId`, `externalUrl`, the `tracker` block) are
optional and absent values are treated as unset, never fabricated.

#### Scenario: Prior-version state loads

- **WHEN** the 0.5.0 engine loads a v0.4.1 `state.json`
- **THEN** all epics and the detour stack load intact and the engine operates normally

### Requirement: Defensive link rendering

Rendering SHALL emit a link only when both its `type` and `epic` are strings. Malformed or
partial link entries (including those on archived epics not present in `state.epics`) MUST be
skipped rather than rendered as `undefined`.

#### Scenario: Malformed link does not render undefined

- **WHEN** an epic carries a link entry missing its `type` or `epic`
- **THEN** the rendered PROJECT.md and brief contain no `undefined` token for that link, and the
  epic still renders otherwise

### Requirement: 0.5.0 migration normalizes links

A `0.5.0` entry in the engine's `MIGRATIONS` SHALL normalize stored `links`, dropping or repairing
malformed entries, and stamp `pmVersion` to `0.5.0`. The migration MUST be additive and idempotent
— running it a second time changes nothing.

#### Scenario: Migration drops malformed links

- **WHEN** `/pm:upgrade` runs against state containing a malformed link entry
- **THEN** that entry is removed/normalized and `pmVersion` becomes `0.5.0`

#### Scenario: Migration is idempotent

- **WHEN** the 0.5.0 migration runs a second time on already-migrated state
- **THEN** no further change is made
