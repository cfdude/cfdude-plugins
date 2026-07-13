# Incorporation backlog — what to borrow from Comet

> The reconciler's **short, mostly-instructional** list (adopt), then the synthesis's fuller list annotated with the debate's **reject-by-default** guidance. Every stateful borrow must pass one gate before it is even planned: **"Does this keep pm an INSTRUCTION layer that only emits instructions — not a tool that generates/hashes artifacts or does work?"** If no, reject.

## Adopt now (reconciler's top list — each fits pm's law or is a safety fix)

### 1. [S] Fix the status-taxonomy drift NOW: either add `later` and `blocked` to KNOWN_STATUSES with correct NEXT-UP/lanes-rollup exclusion, or purge them from README.md, SKILL.md, init.md, and sync.md.

Verified live bug, not a hypothetical: KNOWN_STATUSES at conductor.mjs:52 excludes both, so `/pm:epic add --status later` is rejected at conductor.mjs:804 — breaking the roadmap-import onboarding flow the README itself pitches. This is exactly the doc/engine drift a solo project accrues; both critiques independently confirmed it (pro-keep found a third stray `n` token too). Prereq to any onboarding polish.

### 2. [S] Make the state.json write atomic: write to a temp file and rename() over the target (node:fs only, zero deps, no law violation).

pm's single system of record is written with a plain fs.writeFileSync (confirmed at conductor.mjs:90) — no tmp+rename, no lock. A crash or full disk mid-write corrupts the one file everything depends on. This is pm's most defensible safety borrow from Comet's atomic-write posture, costs ~3 lines, and does NOT drag in the heavier machine-owned-fields/CLI-verb apparatus bundled with it in the synthesis. Adopt the atomic write; DEFER the rest of that item.

### 3. [S] Replace the free-form 'Gate 1 / Gate 2' review prose in CLAUDE.md with a bounded, dedup'd review-count table (off | standard | thorough) giving an explicit per-mode reviewer budget and trigger.

Pure instruction-layer improvement, fully within pm's law, borrowed from Comet's review_mode single-source table. Makes 'how many reviews and when' deterministic, testable, and cheaper for the agent to follow than prose — directly serves the user's gate-obsessed CLAUDE.md without any engine change.

### 4. [M] Add an OPTIONAL, opt-in local PreToolUse guard hook that blocks the single highest-stakes skip — writing source before the reconcile gate runs on a detour POP — surfacing a one-line override.

This is the one place the pro-switch's core concern (gates that MUST fire) can be answered WITHOUT switching. The pro-keep critique's sharpest finding is that pm ALREADY ships hooks and Comet's 'hard' enforcement is itself just installed hook scripts — so a blocking guard is within pm's plugin model and touches no network/tracker. It does cross pm's self-imposed 'engine never mechanically blocks' line, so present it as a deliberate design DECISION for Rob, opt-in and off by default — not a silent adoption. Highest-value single takeaway of the whole debate.

### 5. [M] Document and apply the 'recompute, don't remember' recovery principle: on resume, re-derive the reconcile-gate obligation and active-pointer validity from on-disk evidence rather than trusting stored flags.

Hardens pm's already-strong compaction survival against stale/hand-forged state — a correctness property, not cosmetic. Low cost because pm already recomputes progress and self-heals archived pointers; this extends the same discipline to the highest-stakes flags. Explicitly REJECT-BY-DEFAULT the heavier stateful borrows it was bundled with (events.jsonl audit log, ~/.pm cross-repo registry, and above all the sha256 handoff GENERATOR) — those turn pm into a mini-Comet and must each pass a 'does this still only emit instructions?' gate first.

## Fuller candidate list (from synthesis — triage against the instruction-layer gate)

| Idea | Source | Value | Effort | Risk |
|------|--------|-------|--------|------|
| Fix the later/blocked status drift and taxonomy (pm-internal, surfaced by the comparison): either add them to KNOWN_STATUSES with correct lanes-rollup exclusion, or purge them from README/SKILL/init docs. Prereq to any onboarding polish. | pm capability-map limitation (own bug, not Comet) | Removes a real doc/engine drift that breaks the roadmap-import onboarding flow the README pitches (--status later would be rejected by validation today). | S | low |
| Bounded review-count table (off \| standard \| thorough) with an explicit, dedup'd per-mode reviewer budget, replacing pm's ad-hoc 'Gate 1 / Gate 2' prose in CLAUDE.md. | comet:openspec+superpowers review_mode (subagent-dispatch.md single-source table) | Makes 'how many reviews and when' deterministic, testable, and cheaper to follow than free-form gate prose — a pure doc/instruction improvement, fully within pm's law. | S | low |
| Cross-repo project registry (~/.pm/registry.json, atomic tmp+rename, canonical-path keyed) to power /pm:upgrade --all-repos and a multi-repo status roll-up, instead of the current per-repo manual upgrade sequence. | comet:cli+distribution project-registry.ts (~/.comet/installations.json) | Directly fixes the awkward per-repo update→reload→upgrade dogfooding sequence; lets one command upgrade every conductor-managed repo. Stays local-fs only (no network), so it respects the instruction-layer law. | M | low |
| sha256-anchored, script-generated handoff artifact linking the OpenSpec change id to the Superpowers plan/design docs, with reciprocal frontmatter (comet_change/canonical_spec ↔ change/design-doc/base-ref) so the two stay provably in sync and drift is cheaply detectable. | comet:openspec+superpowers design-context handoff package | Gives pm's currently filesystem-implicit OpenSpec↔Superpowers coupling a verifiable link and a drift signal for the reconcile gate — a concrete upgrade to the reconciler's evidence base. | L | medium |
| Atomic + machine-owned discipline for the detour stack: give PUSH/POP/link-edit real CLI verbs with up-front validation and single-write atomicity, and treat detourStack frames as machine-owned (not hand-editable), mirroring Comet's unforgeable-field + temp+rename posture. | comet:engine+state atomic writes + machine-owned fields | Removes pm's most glaring safety gap — today the highest-stakes operation (detour push/pop) is done by hand-editing state.json with no CLI safety net or concurrency guard. | M | low |
| Append-only audit log (.conductor/events.jsonl) of epic/status/detour transitions, separate from state.json, as pm's state grows machine-owned fields. | comet:engine+state .comet/state-events.jsonl audit log | Adds tamper-evident history and post-hoc debuggability of 'what changed the active pointer / who pushed this detour' without bloating the single state file. | M | low |
| Adopt the 'recompute, don't remember' recovery principle more aggressively: on resume, re-derive not just progress but the reconcile-gate obligation and active-pointer validity from disk evidence rather than trusting stored flags, and document the principle explicitly. | comet:engine+state deterministic zero-context recovery | Hardens pm's already-strong compaction survival against stale stored state; low-cost since pm already recomputes progress and self-heals archived pointers. | M | low |
| An autonomy dial separating 'advance to next epic' from 'auto-start the next epic's work' (config precedence env > repo > default), analogous to Comet's auto_transition. | comet:engine+state auto-transition routing | Lets /pm:next cleanly support both fully-autonomous and human-in-the-loop operation between gates — matches the user's 'autonomous between check-ins' workflow preference with an explicit control. | S | low |

## Reject-by-default (turn pm into a mini-Comet — do NOT adopt without a hard justification)

These were flagged by BOTH critics and the reconciler as pushing pm from "emit instructions" toward "generate + hash artifacts + do work," i.e. a solo, zero-dep reimplementation of the very Comet subsystems that keeping pm was meant to avoid depending on:

- **sha256 handoff-artifact GENERATOR** — pm would start *producing and hashing* artifacts. Biggest law violation.
- **`.comet/state-events.jsonl`-style append-only audit log** — new stateful machinery.
- **`~/.pm` cross-repo project registry** — global mutable state outside the repo.
- **machine-owned / unforgeable atomic detour CLI verbs** — a heavier state-mutation apparatus.

## Separate, larger decision (not an incorporation)

**Comet as a build LANE that pm routes to** (a rigorous alternative to hand-run OpenSpec + Superpowers with hard TDD/review gates). This is a *lane* decision, not a conductor change, and it is NOT free: Comet stores state in `.comet.yaml`/`.comet/run-state.json` that pm's OpenSpec-implicit progress detection can't read, so it needs a `.comet`-state adapter and stands up a duplicate OpenSpec install. Treat as a future `hybrid-adopt-both` spike only if hard enforcement proves worth a second source of truth.
