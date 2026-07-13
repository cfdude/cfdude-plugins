# Epic-level autonomy — design

> First sub-project of a larger vision (epic autonomy → initiative orchestration → portfolio
> architecture-consistency → infra-runbook preflight). This spec covers **only** epic-level
> autonomy. The other three are named in "Forward-compatibility" below but explicitly out of
> scope — see rationale.

## Problem

Executing a single pm-managed epic today requires the user present for every phase transition
and every safety-parameter stop, even when the user is willing to grant broad trust up front.
Stalls come from three distinct causes, roughly evenly:

1. **Manual phase-transition invocation** — the epic finishes a phase cleanly but waits for the
   user to say "now do the next one."
2. **Safety-parameter stops on destructive actions** — a delete/DB-change/git-removal guardrail
   halts execution for permission, even when the user would have said yes.
3. **Genuine decision blockers** — an actual ambiguity or missing design decision the agent
   shouldn't guess on.

A workable design has to address all three, not just one — and it has to avoid becoming
"useless" (the user's word) by making every epic trip a blocker because the upfront analysis was
shallow.

## Scope boundary (important)

This is **development-time** autonomy only — building/testing/refactoring inside a repo, DB
schema/data changes, tearing down and rebuilding local infrastructure. It explicitly does **not**
cover actions with irreversible *external* side effects (sending email/Slack, deploying to
production, calling paid third-party APIs, pushing to a shared branch) — those happen after
development and are out of scope by definition, not because of a reversibility judgment call.

## Design

### 1. Per-epic autonomy contract (new state)

New `autonomy` object on each epic in `.conductor/state.json`:

```
autonomy: {
  level: "off" | "autonomous",                    // default "off" = today's behavior, unchanged
  preAuthorized: [{ action, reason, grantedAt }],  // specific things explicitly blessed
  context: [ "freeform notes / decisions supplied up front" ],
  notifications: [{ what, when }]                  // log of things the user has been told about
}
```

Scoped **per epic**, not global. This is deliberate: a future initiative-level orchestrator needs
to set this independently per child epic (an epic touching infrastructure needs more context and
approval than a sibling that doesn't) — see Forward-compatibility.

This is a small, law-compliant engine addition: new fields + a verb to set them (e.g. extend
`update-epic` or add `set-autonomy <epic> --level autonomous`), same shape as the existing
`set-active`/`clear-active` verbs. No external calls, no violation of the instruction-layer law —
it's data storage the engine already does for every other epic field.

### 2. The preflight (what prevents autonomy from being useless)

Before an epic's `autonomy.level` can be set to `autonomous`, the agent runs a **full read +
structured risk scan** of that epic's actual source (its `tasks.md` / `planPath` / OpenSpec
spec — whichever is the progress source for its lane). It reasons over the whole document (not
a keyword grep) to find:

- destructive-risk points (schema changes, deletions, infra teardown, anything that looks hard
  to undo)
- genuine unknowns (a design decision the plan doesn't actually resolve)

It returns these as **one batch of questions**, presented to the user before execution starts —
not discovered one at a time mid-run. The user answers each (approve / reject / "use your
judgment"); answers are written into that epic's `preAuthorized` and `context` fields.

**Why full-read over keyword-triggered:** a keyword scan (grep for `DROP`, `migration`,
`teardown`, `rm`, `schema`) is cheaper but misses risks that aren't destructive per se — an
ambiguous design decision the plan glossed over won't match a keyword pattern. The user chose
full agent read as worth the cost, since a shallow preflight is what turns autonomous execution
into a wall of blockers (defeating the point).

### 3. Execution-time decision rule

While executing an `autonomous`-level epic, the agent checks any destructive action against
these criteria, in this order, before treating it as a stop:

1. **Already surfaced + approved in the preflight?** → proceed, log it in `notifications`.
2. **No backup/restore path exists?** → **STOP** regardless of autonomy level. (This is the one
   unconditional line — matches "no possible way to back up and restore other than
   redeploying.")
3. **Destructive but restorable** (e.g. a table you've dumped first, a branch you've tagged
   first)? → **WARN** — log it as a flagged decision, proceed without stopping.
4. **No context to act on?** → **STOP** — this is a real gap, not a false stall; the whole point
   is to stop for genuine blockers while removing false ones.
5. **Consequential and not yet notified?** → record it for the end-of-epic report even when it
   didn't block.

This directly answers the "even mix of three causes" finding: cause 1 (manual transitions) is
fixed by `autonomous` level alone (agent proceeds through phases without asking); cause 2 (safety
stops) is fixed by the preflight + decision rule; cause 3 (genuine blockers) is *preserved* by
rule 4 — autonomy never overrides an actual unresolved unknown.

**Enforcement mechanism — instruction-layer, not a hard gate.** This decision rule is enforced
the same way every other pm rule is: injected into the agent's instructions (CLAUDE.md rules
block / brief), followed because the agent is told to, not because a hook mechanically blocks
the tool call. That's consistent with pm's instruction-layer law, but it is honestly weaker than
Comet's PreToolUse write-blocking — an instruction can, in principle, be missed. If in practice
this proves insufficient (the validation-plan epic reveals the agent skipping a stop it
shouldn't have), a hard PreToolUse guard is the fallback, following the same opt-in pattern
already planned for the reconcile gate (`pm-optional-gate-guard-hook`) rather than being built
into this design speculatively.

### 4. End-of-epic report

On completion (or reconcile-gate-equivalent for a detour-free run):

- What was asked (the preflight questions and answers)
- What was done
- Decisions made in the user's absence (the `WARN`-class log)
- Anything flagged but not blocking (`notifications` not yet acknowledged)
- Explicit "are you OK with these?" checkpoint
- Then run tests to confirm nothing broke
- Room to iterate — including rewriting already-written code — if the user isn't satisfied

## Approaches considered (preflight mechanism)

| Approach | Trade-off |
|---|---|
| **Full agent read + structured risk scan** (chosen) | Most thorough; catches ambiguity a keyword can't. Higher token cost per epic, paid once at preflight time. |
| Keyword-triggered lightweight scan | Cheap/fast; misses non-keyword ambiguity — risks silently sailing through, which is worse than the stalls it's meant to fix. |
| Keyword-first, then full read of flagged sections only | Middle ground; rejected for v1 in favor of full read — can revisit if preflight cost becomes a real problem in practice. |

## Forward-compatibility (explicitly not built in this sub-project)

- **Initiative-level orchestration**: a future orchestrator will need to walk an initiative's
  child epics and set each one's `autonomy` block individually (an epic touching infrastructure
  gets more context/approval than a sibling that doesn't). Per-epic scoping above is designed so
  this requires no schema change later — just a new caller that sets the same fields on multiple
  epics. "Initiative" itself isn't modeled in `state.json` yet; the existing parent/child
  hierarchy (`parent` field) may end up being the grouping, but that decision is deferred.
- **Portfolio/architecture-consistency scanning** and **infra-runbook preflight** are separate
  concerns layered on top of initiative orchestration, not this sub-project. Not designed here.

## Validation plan

Prove this on **one real epic** before building anything else — pick one of the five
already-`planned` Comet-incorporation epics in `.conductor/state.json` as the test case, run it
through preflight → autonomous execution → end-of-epic report, and confirm in practice that:

- phase transitions no longer require manual invocation
- destructive actions correctly split into stop/warn per the five-criteria rule
- the end-of-epic report is actually useful for the "are you OK with this" checkpoint

## Out of scope

- Initiative-level orchestration (concern B)
- Portfolio/architecture-consistency scanning (concern C)
- Infra-runbook preflight wiring (concern D)
- Any change to non-destructive, non-safety-gated execution (unaffected — `level: "off"` epics
  behave exactly as today)
