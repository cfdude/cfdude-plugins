## ADDED Requirements

### Requirement: Epic parent field

An epic record SHALL support an optional `parent` field holding the id of another epic, forming
a single-parent tree of arbitrary depth. The field is optional and backward-compatible: an epic
without `parent` (including every epic in a v0.4.1 `state.json`) is treated as a root epic and
loads unchanged.

#### Scenario: Epic with no parent is a root

- **WHEN** an epic record has no `parent` field
- **THEN** the engine treats it as a root epic and loads it without error

#### Scenario: v0.4.1 state loads unchanged

- **WHEN** a `state.json` written by v0.4.1 (no `parent` fields anywhere) is loaded
- **THEN** every epic loads successfully and no `parent` value is fabricated

### Requirement: add-epic accepts and validates --parent

The `add-epic` subcommand SHALL accept a `--parent <id>` flag. The engine MUST reject the
operation, write nothing, and exit non-zero when the parent does not reference an existing epic,
when an epic is set as its own parent, or when the link would introduce a cycle.

#### Scenario: Valid parent reference

- **WHEN** `add-epic --id child --parent existing-parent` is run and `existing-parent` exists
- **THEN** the child epic is created with `parent` set to `existing-parent`

#### Scenario: Parent does not exist

- **WHEN** `add-epic --parent missing-id` references an id that is not a known epic
- **THEN** the engine exits non-zero, names the missing parent, and writes no epic

#### Scenario: Self-parent rejected

- **WHEN** an epic is created or updated with its own id as `parent`
- **THEN** the engine exits non-zero and writes nothing

#### Scenario: Cycle rejected

- **WHEN** setting a `parent` would make an epic an ancestor of itself (a → b → a)
- **THEN** the engine exits non-zero and writes nothing

### Requirement: Hierarchical PROJECT.md rendering

`PROJECT.md` (the `render()` output) SHALL render children indented beneath their parent in the
Epics table. Grouping is a `render()`-only concern: it MUST NOT change `resolveEpics`'s shared
`priority → lane → id` sort, so the brief (`buildBrief`) and its NEXT UP ordering are unaffected
(a P0 child of a P2 parent keeps its P0 position in NEXT UP). Within `render()`:

- Top-level (root) epics appear in the existing `resolveEpics` order. Each root is immediately
  followed by its descendants in a depth-first walk.
- A descendant's Epic-id cell is prefixed with `└─ ` repeated once per depth level (depth 1 =
  `└─ `, depth 2 = `└─ └─ `), so arbitrary nesting depth renders deterministically.
- Children of the same parent are ordered by the same `priority → lane → id` comparison used for
  roots.
- A parent epic's **Progress cell** carries an `X/Y children archived` rollup (X = direct
  children archived, Y = direct children) prefixed to its own progress string.

#### Scenario: Children render under their parent

- **WHEN** PROJECT.md is rendered and an epic has children
- **THEN** each child appears directly beneath its parent, its id cell prefixed with a `└─`
  indent marker, and is not also listed as a separate top-level row

#### Scenario: Grandchildren indent one level deeper

- **WHEN** an epic has a child which itself has a child (depth 2)
- **THEN** the grandchild renders beneath its parent with a doubled `└─ └─ ` indent marker

#### Scenario: Parent shows child-archived rollup in its Progress cell

- **WHEN** a parent has Y direct children of which X are archived
- **THEN** the parent's Progress cell shows an `X/Y children archived` rollup

#### Scenario: Grouping does not reorder the brief

- **WHEN** a P0 child belongs to a P2 parent
- **THEN** the child keeps its P0 position in the brief's NEXT UP (render-only grouping does not
  touch `resolveEpics`'s sort)

#### Scenario: Brief annotates a child with its parent

- **WHEN** a child epic appears in the brief's NEXT UP list
- **THEN** the line notes its parent id
