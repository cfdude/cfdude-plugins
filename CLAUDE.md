# CLAUDE.md

> Project memory for **`cfdude-plugins`** — a public Claude Code plugin marketplace.
> Current development focus: the **`pm`** plugin (`plugins/pm/`). This repo is itself
> `pm`-conductor-managed (we dogfood the plugin on its own development).

## What this repo is

- A marketplace of Claude Code plugins. Each plugin lives under `plugins/<name>/` with its own
  `.claude-plugin/plugin.json`, `commands/`, `skills/`, `hooks/`, `scripts/`, `agents/`.
- The active work item is tracked by the conductor in `.conductor/state.json`
  (system of record) and surfaced in `PROJECT.md` (generated — never hand-edit).

## The `pm` engine — hard constraints (must follow)

- **`plugins/pm/scripts/conductor.mjs` is ZERO-DEPENDENCY.** Node 18+ built-ins only
  (`node:fs`, `node:path`, `node:os`, `node:child_process`, `node:url`). **Never** add an npm
  package or a `package.json` dependency. If a format needs parsing, prefer JSON (native) over
  pulling a parser.
- **Tests:** `node --test plugins/pm/scripts/conductor.test.mjs`. All tests pass before any
  commit — no exceptions, no `--no-verify`.
- **Architectural law — the `pm` plugin is an INSTRUCTION layer, never an INTEGRATION layer.**
  It emits instructions for the interactive Claude agent to act on (the managed `CLAUDE.md`
  rules block, the SessionStart/PreCompact brief, command-doc markdown). It must **never** open
  a network connection or call an external system (Jira, GitHub, Linear, …) itself. External
  tracker sync is the *agent's* job; the engine's only role is to know a tracker is in use and
  shape the instructions it already emits. No code path in the engine talks to a tracker.
- **Release discipline.** A feature: (1) bumps `plugins/pm/.claude-plugin/plugin.json`
  `version`; (2) adds a `CHANGELOG.md` entry; (3) if the `state.json` schema changes, adds a
  `MIGRATIONS` entry keyed to the new release (additive, idempotent, backward-compatible — a
  state file written by the prior version must still load). `state.json` carries `pmVersion`.
  The user-facing update sequence is: update the plugin → `/reload-plugins` (or restart) →
  `/pm:upgrade` per repo.
- Engine subcommands are dispatched at the bottom of `conductor.mjs`; every new subcommand needs
  a matching command doc under `plugins/pm/commands/` and coverage in `conductor.test.mjs`.

## Four-system coordination (in this repo)

- **pm conductor** — what's active / queued / parked. Dogfooded here. After any change to
  epics/status/priority/detour stack, re-render with `/pm:status`. Never hand-edit `PROJECT.md`.
- **OpenSpec** — the build lane for capability epics (this 0.5.0 work qualifies: multi-subsystem
  new capability). Flow: `/opsx:propose` → **spec review gate** → `/opsx:apply` (TDD per task) →
  **implementation review gate** → docs → `/opsx:archive`. Keep the OpenSpec change id equal to
  the conductor epic id so the two stay linked.
- **Superpowers** — disciplines applied in every lane: brainstorming before design, TDD
  (red → green → refactor), the two review gates, verification-before-completion.
- **Honcho** — workspace is **`personal`** for this repo (it is not a Highway project). Mirror
  epic completion and every detour PUSH/POP to a one-line Honcho memory.

## Commits

Conventional commits (`feat|fix|docs|test|chore|refactor`), scoped to the plugin
(e.g. `feat(pm): …`). This repo is **not** Jira-tracked, so no issue-key prefix. Never
`git commit --no-verify`.

<!-- BEGIN pm-conductor rules (managed by /pm:init — safe to delete this block) -->
## PM Conductor — operating rules

This repo is managed by the `pm` plugin. The conductor sits ABOVE OpenSpec and Superpowers.
Epics are **lane-agnostic** (openspec | superpowers | claude-code | decision | external);
OpenSpec is one lane. Stories come from each epic's source (OpenSpec `tasks.md`, a Superpowers
plan, or a manual list). Follow these rules:

1. **Detours** — when something blocks the active epic, CLASSIFY before fixing:
   - *Minimal* (small, self-contained, no design ambiguity): fix → test → commit → push,
     then run `/pm:detour --minimal "<what>"` so it is recorded in `.conductor/detours.log`.
     Then resume.
   - *Substantial* (own design / changes shared behavior / multi-step): run `/pm:detour`.
     It becomes its own epic in the appropriate lane (OpenSpec proposal, Superpowers plan,
     etc.); PUSH the current epic onto the detour stack in `.conductor/state.json` with a
     concrete reason and `reconcileOnResume`.
2. **State of record is `.conductor/state.json`.** After any change to epics, status,
   priority, or the detour stack, re-render with `/pm:status`. Never hand-edit `PROJECT.md`.
3. **Resuming after a detour** — use `/pm:resume`. If the popped frame had
   `reconcileOnResume`, run the reconcile gate (reconciler agent) BEFORE writing code.
4. **Honcho** — on every PUSH and POP, also write a one-line memory to Honcho
   ("paused X for Y" / "resumed X, reconciled vs Y") so the relationship survives outside
   this repo.
5. **Keep `tasks.md` checkboxes truthful** — they are the source of truth for story progress.
6. **Roadmap as backlog** — work you intend to do but haven't proposed yet can be
   registered now with `/pm:epic add … --status planned` (any lane). Planned epics show
   as ordered backlog in `PROJECT.md` and a `planned: N` count in the briefing, without a
   "no change on disk" warning; `/pm:sync` flips an openspec planned epic to untriaged once
   its change is proposed. Have a roadmap doc? Read it in-session and load each item this way.
<!-- END pm-conductor rules -->
