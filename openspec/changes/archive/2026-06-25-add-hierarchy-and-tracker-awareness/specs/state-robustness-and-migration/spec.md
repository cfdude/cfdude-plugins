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

A `0.5.0` entry in the engine's `MIGRATIONS` SHALL normalize stored `links` and stamp `pmVersion`
to `0.5.0`. Normalization is **repair-first, drop-only-if-unrecoverable**: a link stored as the
colon-delimited string form `type:epic[:reason]` (the only documented historical encoding — it is
exactly what `add-epic`'s `--link` parser produces) SHALL be repaired into the current
`{ type, epic, reason? }` object; an entry that is neither a valid `{type, epic}` object nor a
parseable colon-string SHALL be dropped. Valid object links pass through unchanged. The migration
MUST be additive and idempotent — running it a second time changes nothing. (Defensive rendering —
see the requirement above — is the shape-agnostic durable fix for any malformed link, including
shapes this migration cannot repair; the migration is cleanup, not the user-facing fix.)

#### Scenario: Migration repairs a recoverable colon-string link

- **WHEN** `/pm:upgrade` runs against state where an epic's `links` entry is the string
  `"blocks:other-epic:was-flaky"`
- **THEN** that entry becomes `{ type: "blocks", epic: "other-epic", reason: "was-flaky" }` and
  `pmVersion` becomes `0.5.0`

#### Scenario: Migration drops an unrecoverable link

- **WHEN** state contains a link entry that is neither a `{type, epic}` object nor a parseable
  colon-string (e.g. an empty string or `{}`)
- **THEN** that entry is removed and the epic otherwise survives

#### Scenario: Migration is idempotent

- **WHEN** the 0.5.0 migration runs a second time on already-migrated state (all links are valid
  objects)
- **THEN** no further change is made
