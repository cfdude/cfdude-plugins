## ADDED Requirements

### Requirement: Tracker configuration block

`state.json` SHALL support an optional `tracker` block describing an external issue tracker the
project mirrors epics to: `system`, `instance`, `projectKey`, `mechanism`, and a `statusIntent`
map from conductor lifecycle status to a SEMANTIC target. The block is optional; its absence
means the project is tracker-unaware (the default) and no tracker behavior activates.

#### Scenario: No tracker block means tracker-unaware

- **WHEN** `state.json` has no `tracker` block
- **THEN** no tracker instructions are emitted in the rules block or the brief

#### Scenario: statusIntent is semantic, not a literal transition

- **WHEN** a `statusIntent` maps `archived` to `done`
- **THEN** the value is recorded and surfaced as a semantic target, and the engine never emits
  or resolves a literal tracker transition name itself

### Requirement: statusIntent flag encoding

`set-tracker` SHALL accept the `statusIntent` map via a REPEATABLE `--intent <status>:<target>`
flag (e.g. `--intent active:in-progress --intent archived:done`), each occurrence adding one
entry to the map. Because the engine's `parseFlags` overwrites repeated flags for every key
except the explicitly-accumulated `link`, `intent` MUST be added to that accumulation list so
repeated `--intent` flags collect into an array rather than the last one winning. Each value is
split once on the first `:` into `{ status, target }`.

#### Scenario: Multiple --intent flags build a map

- **WHEN** `set-tracker … --intent active:in-progress --intent paused:todo --intent archived:done`
  is run
- **THEN** `tracker.statusIntent` is `{ active: "in-progress", paused: "todo", archived: "done" }`
  and re-reads identically (a 3-entry map, not a single scalar)

### Requirement: Per-epic external identity

An epic SHALL support optional `externalId` and `externalUrl` fields linking it to a specific
tracker issue. The tracker `system` is NOT stored per-epic; it is inherited from the `tracker`
block so epic records stay DRY.

#### Scenario: External id recorded on an epic

- **WHEN** an epic has `externalId` set to `JOB-506`
- **THEN** the engine treats that epic as mirrored to the tracker and excludes it from
  create-issue drift

### Requirement: set-tracker subcommand

The engine SHALL provide a `set-tracker` subcommand that writes/updates the `tracker` block from
flags (`--system`, `--instance`, `--project`, `--mechanism`, `--intent`). It performs a pure
local state write and never contacts the tracker.

#### Scenario: set-tracker round-trips the block

- **WHEN** `set-tracker --system jira --project JOB --instance onvex` is run
- **THEN** `state.json` gains a `tracker` block with those values and re-reads identically

### Requirement: update-epic write-back subcommand

The engine SHALL provide an `update-epic <id>` subcommand to update an EXISTING epic's
`externalId`, `externalUrl`, `parent`, `status`, and `priority`. The epic id is a POSITIONAL
argument (read from `process.argv`, like `log-detour`), NOT a `--id` flag — `parseFlags` skips
non-`--` tokens. This closes the sync loop: after the agent creates a tracker issue it records the
key back onto the epic. Updates SHALL enforce the same validation as creation (parent existence,
no self-parent, no cycle, known status/priority).

#### Scenario: Record external id onto an existing epic

- **WHEN** `update-epic job-506 --external-id JOB-506 --external-url https://…/JOB-506` is run
- **THEN** the epic's `externalId` and `externalUrl` are set and persisted

#### Scenario: update-epic enforces parent validation

- **WHEN** `update-epic a --parent b` would create a cycle
- **THEN** the engine exits non-zero and writes nothing

#### Scenario: update-epic on unknown id fails

- **WHEN** `update-epic missing-id …` targets an epic that does not exist
- **THEN** the engine exits non-zero and writes nothing

### Requirement: Tracker-aware instruction weaving

When a `tracker` block is configured, the engine SHALL weave sync responsibilities into the
instructions it already emits — and ONLY emit instructions, never perform tracker calls. The
CLAUDE.md rules block SHALL gain an "External tracker sync" section assigning the agent ownership
(create issue + record key via `update-epic` for an unmirrored epic; transition the linked issue
toward the `statusIntent` equivalent on status change, resolving the real transition itself;
create a parent epic as a tracker epic and link children). The brief SHALL surface only
honestly-computable drift.

#### Scenario: Rules block gains a sync section when configured

- **WHEN** the rules block is written and a `tracker` block exists
- **THEN** it includes an "External tracker sync" section naming the configured system and the
  agent's responsibilities

#### Scenario: Brief lists unmirrored epics as create-issue drift

- **WHEN** the brief is built, a tracker is configured, and an active-work epic — status
  `queued`, `active`, or `paused` — has no `externalId`
- **THEN** the brief's tracker-sync block lists that epic as needing a tracker issue created

#### Scenario: Done and not-yet-real epics are excluded from create-issue drift

- **WHEN** the brief is built and an epic is `archived` (completed work), is `untriaged`/`planned`
  (not yet real work), or is a `missing()` ghost (an openspec epic with no change on disk)
- **THEN** that epic is NOT listed as create-issue drift, regardless of `externalId`

#### Scenario: No fabricated transition drift

- **WHEN** the brief is built and epics already carry `externalId`
- **THEN** the brief does NOT claim to detect un-synced status transitions (the engine cannot see
  tracker state); transition sync is left to the on-change rule in the rules block

> NOTE: Agent-driven tracker DETECTION (in the `init`/`upgrade` command docs) is intentionally
> agent-side and therefore not engine-testable — it inspects the live session for tracker signals
> and confirms with the user before calling `set-tracker`. Only `set-tracker`'s persisted result
> is covered by engine tests.
