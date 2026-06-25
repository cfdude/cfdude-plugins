## Why

The conductor can track a flat list of epics but cannot express the two relationships real
project work needs: **hierarchy** (a sprint parent over its child tickets) and **external
identity** (a conductor epic ↔ its Jira/GitHub/Linear issue). Today users hack hierarchy with
`blocks:` links and rely on a kebab-case naming coincidence (`job-498` ≈ `JOB-498`) for tracker
identity — both break silently and render poorly. Filing a sprint of N tickets means chaining N
`add-epic` calls with `&&` to dodge a write race. And after an upgrade, epics archived under an
older link schema render as `undefined undefined`. These came in as a concrete feature request
from a downstream project bundling 12 audit-derived tickets.

## What Changes

- **First-class hierarchy.** New optional `parent` field on an epic; `add-epic --parent <id>`;
  PROJECT.md renders children indented under their parent with a "X/Y children archived" rollup.
- **External-tracker awareness.** A `tracker` config block in `state.json` (system, instance,
  project key, mechanism, semantic status-intent map) plus per-epic `externalId`/`externalUrl`.
  The plugin becomes *aware* a tracker is in use and weaves sync responsibilities into the
  instructions it already emits (CLAUDE.md rules block + the brief). **The engine never calls the
  tracker** — the interactive agent owns the actual Jira/GitHub work. New `set-tracker` and
  `update-epic` (write-back) subcommands; detection is agent-driven in `init`/`upgrade`.
- **Bulk creation.** New `add-many --from <path|->` reads a JSON batch and creates a parent +
  children atomically (all-or-nothing, single write — removes the `&&`-chaining race).
- **Render robustness + migration.** Defensive link rendering (never emit `undefined`) and a
  `0.5.0` migration that normalizes malformed `links` entries. `pmVersion` → `0.5.0`.
- All schema additions are optional and backward-compatible: a `state.json` written by v0.4.1
  loads unchanged. No breaking changes.

## Capabilities

### New Capabilities
- `epic-hierarchy`: parent/child epics — the `parent` field, `--parent` validation
  (existing-ref, no self-parent, no cycles), and indented tree rendering with a child-archived
  rollup.
- `external-tracker-awareness`: the `tracker` config block, per-epic external identity fields,
  `set-tracker` + `update-epic` subcommands, agent-driven detection, and the
  instruction-weaving surfaces (rules-block sync section + brief drift) — engine emits
  instructions only, never integrates.
- `bulk-epic-creation`: `add-many` atomic JSON batch creation of a parent and its children.
- `state-robustness-and-migration`: backward-compatible schema load, defensive link rendering,
  and the additive/idempotent `0.5.0` migration that normalizes malformed `links`.

### Modified Capabilities
<!-- None. openspec/specs/ is empty (this repo had no prior OpenSpec specs); all behavior here
     is introduced as new capabilities above. -->

## Impact

- **Code:** `plugins/pm/scripts/conductor.mjs` (schema, validation, render, brief, new
  subcommands, `MIGRATIONS`), `plugins/pm/scripts/conductor.test.mjs` (new coverage).
- **Commands/docs:** `commands/epic.md` (add-many, --parent, --external-id), a new tracker
  command doc, `commands/init.md` + `commands/upgrade.md` (agent-driven detection step),
  `README.md`, `skills/conductor/SKILL.md`.
- **Release:** `plugins/pm/.claude-plugin/plugin.json` → `0.5.0`; `CHANGELOG.md` entry.
- **Dependencies:** none added — engine stays zero-dependency (JSON parsed natively).
- **External systems:** none touched by the engine. Tracker sync is delegated to the
  interactive agent via emitted instructions.
