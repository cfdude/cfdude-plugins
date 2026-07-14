# CLAUDE.md

> Project memory for **`cfdude-plugins`** — a public Claude Code plugin marketplace.
> This repo is itself `pm`-conductor-managed (we dogfood the plugin on marketplace-level work).
> **The `pm` plugin's own code, tests, and engine hard-constraints now live in its own repo,
> [`cfdude/pm`](https://github.com/cfdude/pm)** — extracted 2026-07-14, preserving full history
> via `git subtree split`. This repo's `.claude-plugin/marketplace.json` references it via a
> `github` source (`cfdude/pm`, `ref: main`); there is no `plugins/pm/` directory here anymore.

## What this repo is

- A marketplace of Claude Code plugins. Each *locally-hosted* plugin lives under
  `plugins/<name>/` with its own `.claude-plugin/plugin.json`, `commands/`, `skills/`, `hooks/`,
  `scripts/`, `agents/`. Some entries (`pm`, `honcho`) instead point at their own external repos
  via a `github`/`git-subdir` source in `marketplace.json` — the marketplace here only carries
  the manifest for those, not the code.
- The active work item is tracked by the conductor in `.conductor/state.json`
  (system of record) and surfaced in `PROJECT.md` (generated — never hand-edit).

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

## Epic-level autonomy

An epic's `autonomy` block (`.conductor/state.json`) can grant it broad execution trust —
`level: "off"` by default (today's behavior, unchanged). Setting `level: "autonomous"`
removes the need to ask before each phase transition, but NEVER removes a genuine safety stop.
This is development-time only — it never covers actions with irreversible EXTERNAL side
effects (sending email/Slack, deploying to production, third-party API calls, pushing to a
shared branch); those are out of scope regardless of autonomy level.

1. **Preflight before flipping the switch** — see the `conductor` skill's
   "Epic-level autonomy — the preflight scan" section for the full process. In short: read
   the epic's full source, produce a short batch of destructive-risk-points +
   genuine-unknowns questions, get the user's answers, THEN record them:
   `set-autonomy <id> --preauthorize "<action>:<reason>"` / `--context "<note>"`, and only
   then `set-autonomy <id> --level autonomous`.
2. **Execution-time decision rule** — check every destructive action against these, in
   order, before treating it as a stop:
   a. Already pre-authorized in the preflight? → proceed, record via `--notify`.
   b. No backup/restore path exists? → STOP regardless of autonomy level.
   c. Destructive but restorable (backed up first)? → WARN — log it, proceed.
   d. No context to act on? → STOP — a real gap, not a false stall.
   e. Consequential and not yet notified? → record it for the end-of-epic report.
3. **End-of-epic report** — on completion, report what was asked, what was done, decisions
   made in the user's absence (the WARN-class log), and an explicit "are you OK with
   these?" checkpoint, THEN run tests. Leave room to iterate — including rewriting code —
   if the user is not satisfied.
<!-- END pm-conductor rules -->
