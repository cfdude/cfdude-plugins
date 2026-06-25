## Context

The `pm` conductor engine (`plugins/pm/scripts/conductor.mjs`) is a single zero-dependency Node
ES module. It owns `.conductor/state.json` (state of record) and emits three instruction
surfaces that the interactive Claude agent consumes: the managed CLAUDE.md rules block, the
SessionStart/PreCompact brief (`buildBrief`), and the command-doc markdown. Today an epic is a
flat record (`id`, `title`, `priority`, `status`, `role`, `lane`, `links[]`, `reconcileNeeded`,
optional `planPath`/`stories`). There is no hierarchy, no external-identity, no bulk create, and
render assumes well-formed `links`.

This change is cross-cutting (schema + validation + render + brief + new subcommands + migration +
command docs) and carries migration and backward-compatibility complexity, so it warrants a design
doc. Motivation is in `proposal.md`; testable behavior is in the four capability specs.

## Goals / Non-Goals

**Goals:**

- First-class single-parent hierarchy with validated `--parent` and an indented tree render.
- Tracker *awareness*: the engine knows a tracker is in use and shapes its emitted instructions
  accordingly — while never calling the tracker itself.
- A closed sync loop: `update-epic` write-back lets the agent record an issue key after creating it.
- Atomic bulk creation that also fixes the multi-write race.
- Robust render + an additive, idempotent, backward-compatible migration.

**Non-Goals:**

- The engine opening any network connection or calling Jira/GitHub/Linear (architectural law).
- Two-way pull sync from the tracker into the conductor.
- Multiple parents per child (a real DAG); only a single-parent tree.
- Cross-repo conductor federation; UI/dashboard.
- YAML parsing (`add-many` is JSON-only — zero-dep constraint).
- Transition-drift detection — deferred to a future optional per-epic `syncedStatus` field.

## Decisions

**1. Hierarchy as a `parent` pointer, not a `children[]` array.** A single `parent: <id> | null`
on the child keeps the edge in one place and avoids two-sided consistency bugs. Children and
rollups are derived at render time by indexing epics by parent. Alternative (a `children[]` on the
parent) was rejected: it duplicates the edge and drifts. Cycle/self checks run against the derived
ancestor chain on every `--parent` set (in `add-epic`, `add-many`, and `update-epic`).

**2. Tracker identity split: system-level vs per-epic.** System facts (`system`, `instance`,
`projectKey`, `mechanism`, `statusIntent`) live ONCE in a `tracker` block; each epic carries only
`externalId`/`externalUrl`. This keeps epics DRY and makes "is this project tracker-aware?" a
single check. `statusIntent` stores a SEMANTIC target (e.g. `done`), never a literal transition
name — the agent resolves the actual workflow transition with its own tooling, because workflows
differ per project and the engine cannot (and must not) query them.

**3. Engine emits instructions; the agent integrates.** The two behavioral surfaces are the rules
block (a static "External tracker sync" responsibilities section, present only when a tracker is
configured) and the brief (a `TRACKER SYNC` block). Detection of *which* tracker a repo uses lives
in the `init`/`upgrade` command docs (the agent inspects signals and confirms with the user, then
calls `set-tracker`) — not in the engine, which would otherwise have to guess. `upgrade` only runs
detection when no `tracker` block exists yet, so it never clobbers configured state.

**4. Drift is only what's honestly computable.** The brief lists unmirrored epics (real status,
no `externalId`) as "create issues" — that is computable from state alone. It does NOT fabricate
transition-drift, because the engine cannot see the tracker's current state; claiming otherwise
would be dishonest. Keeping status transitions in sync is delegated via the on-change rule in the
rules block. A future `syncedStatus` per-epic field (written back by the agent after a successful
transition) would make transition-drift truthfully computable — explicitly deferred.

**5. `update-epic` is the write-back primitive.** `add-epic` rejects known ids and `add-many` is
create-only, so without an update path the agent could never record `externalId` onto an existing
epic and the create-issue drift line would never clear. `update-epic <id>` mutates
`externalId`/`externalUrl`/`parent`/`status`/`priority` on an existing epic under the same
validation as creation. It also serves as the general re-parent / re-status primitive.

**6. `add-many` validates-all-then-writes-once.** Full validation (id format, uniqueness vs
existing AND within-batch, lane, status, parent refs) happens before any mutation; a single
`saveState` at the end is the only write. This gives all-or-nothing atomicity AND removes the race
that forced callers to chain individual `add-epic` invocations with `&&`. JSON only — `JSON.parse`
is native, so no parser dependency is introduced.

**7. Defensive render is the durable stale-link fix; migration is the cleanup.** The
`undefined undefined` bug is a render fault: it should never emit a link whose `type`/`epic` are
not strings. Fixing render covers archived epics that aren't even in `state.epics`. The `0.5.0`
migration additionally normalizes stored malformed `links`. Before writing the migration,
implementation MUST inspect the actual old (v0.0.0-era) link shape in a real archived epic so the
normalization matches reality rather than a guess.

## Risks / Trade-offs

- **Render restructuring could regress the existing flat table / `stamp-on-content-change`
  behavior.** → Add a tree-structure render test and keep the unchanged-content skip; verify a
  no-hierarchy repo renders identically to before.
- **Cycle detection has edge cases (deep chains, re-parenting via `update-epic`).** → Centralize
  one ancestor-walk helper used by all three write paths; test a→b→a and self-parent directly.
- **Migration guessing the old link shape wrong could drop valid links.** → Inspect a real
  archived epic first (Gate-1 / pre-implementation); make the migration conservative (only drop
  entries that fail the both-strings test) and idempotent; backward-compat load test guards it.
- **Tracker instructions could leak into tracker-unaware repos.** → Gate every tracker surface on
  `tracker` block presence; test brief/rules emit nothing when unset.
- **Scope is large for one change.** → Tasks are ordered precondition-first so hierarchy is a
  complete, tested, demoable slice before tracker work; Gate-1 may split tracker-awareness into its
  own change if it proves unwieldy.

## Migration Plan

1. Ship 0.5.0; user updates the plugin → `/reload-plugins` (or restart) → `/pm:upgrade` per repo.
2. `/pm:upgrade` runs the additive, idempotent `0.5.0` migration (normalize links, stamp
   `pmVersion`) and refreshes the rules block. No data is lost; a v0.4.1 state file still loads.
3. Rollback: revert the plugin version; 0.5.0-written state remains loadable by 0.4.1 because all
   additions are optional fields the older engine ignores.

## Open Questions

- None blocking. The exact old link shape for the migration is resolved during implementation by
  inspecting a real archived epic (see Decision 7).
