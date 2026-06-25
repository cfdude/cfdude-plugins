# bulk-epic-creation Specification

## Purpose
TBD - created by archiving change add-hierarchy-and-tracker-awareness. Update Purpose after archive.
## Requirements
### Requirement: add-many bulk creation from JSON

The `add-many --from <path|->` subcommand SHALL read a JSON batch and create multiple epics in a
single operation. The input format is `{ "parent"?: {…}, "epics": [ {…}, … ] }`. When `parent`
is present it is created first and each entry in `epics` defaults its `parent` to the parent's id.
Input is JSON only (the engine is zero-dependency; JSON parses natively). `-` reads from stdin.

#### Scenario: Parent plus children created together

- **WHEN** `add-many` is given a batch with a `parent` and three `epics`
- **THEN** the parent and all three children are created, and each child's `parent` is set to the
  parent's id

#### Scenario: Children-only batch

- **WHEN** `add-many` is given a batch with no `parent` and an `epics` array
- **THEN** the listed epics are created with whatever `parent` each explicitly carries (or none)

### Requirement: add-many is atomic

`add-many` SHALL validate every entry before writing anything — id format, uniqueness against
both existing epics AND others within the same batch, lane, status, and parent references. On any
validation failure it MUST write nothing, exit non-zero, and name the offending entry. A
successful run persists all epics in a SINGLE state write (removing the write race that forced
chaining individual `add-epic` calls).

#### Scenario: One invalid entry aborts the whole batch

- **WHEN** a batch contains one entry with a malformed id or a duplicate id
- **THEN** the engine writes no epics at all, exits non-zero, and identifies the bad entry

#### Scenario: Duplicate id within the batch is rejected

- **WHEN** two entries in the same batch share an id
- **THEN** the batch is rejected and nothing is written

#### Scenario: Intra-batch parent cycle is rejected

- **WHEN** a batch defines entries whose `parent` references form a cycle entirely within the
  batch (e.g. `x` parent `y` and `y` parent `x`)
- **THEN** the batch is rejected, exits non-zero, and nothing is written

#### Scenario: Successful batch writes once

- **WHEN** a fully valid batch is applied
- **THEN** all epics are persisted and state is saved exactly once

