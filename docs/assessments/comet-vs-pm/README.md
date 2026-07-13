# Assessment — Comet vs the `pm` plugin

> Generated 2026-07-13 from a 9-agent assessment workflow (4 Comet subsystem reads + an objective pm map → synthesis → pro-switch/pro-keep adversarial debate → reconciler). Sources: Comet fork `cfdude/comet` @ `~/Documents/Repos/comet` (v0.4.0-beta.4); `pm` @ `plugins/pm` (v0.7.0).

## Verdict

**keep-pm-and-incorporate** — confidence: **high**.

Keep pm as the conductor; do not switch to Comet. The debate's load-bearing fact survived scrutiny from both sides and my own repo check: pm and Comet occupy ADJACENT layers, not the same one. Comet is a single-change build ENGINE (bundles @fission-ai/openspec, wires Superpowers as script-gated phases, hard-blocks out-of-phase writes); pm is a portfolio CONDUCTOR that sits ABOVE any build lane (lane-agnostic epic index, LIFO detour stack, reconcile-on-resume, Honcho/tracker memory bridge). Confirmed by grep in both critiques: Comet has literally zero portfolio/detour/priority concept. Switching therefore forfeits pm's entire reason to exist to gain a build-phase enforcer — and it does so by adopting a 31k-line, 8-dependency, 0.4.0-beta.4 third-party runtime coupled to two fast-moving upstreams, which Rob would have to own or fork but did not write. That is a strictly worse trade for a single maintainer than keeping a 1,134-line zero-dep file he fully controls.

The pro-switch case has one genuinely strong core — the user's own global CLAUDE.md is built around gates that MUST fire, and pm is instruction-only — but it does not survive the pro-keep rebuttal I verified: pm already ships PreToolUse/SessionStart/PreCompact hooks, and Comet's own "hard" enforcement is itself nothing more than installed Claude Code hook scripts. So pm's lack of mechanical enforcement is a self-imposed philosophy ("the engine never mechanically blocks"), NOT the structural impossibility the synthesis claims. pm can add its own opt-in blocking guard hook without touching a network and without adopting Comet's runtime. Once that's true, the switch's headline argument — "only Comet can enforce" — is false: the enforcement gap is closeable on pm's own terms.

Critically, even in the pro-switch's own worst-case-for-pm world (the detour machinery is speculative — and I did confirm it is DORMANT here: empty detourStack, no detours.log file), the correct response is NOT Comet. Comet does zero portfolio management; if pm's coordination layer is over-built, the answer is to simplify pm toward a markdown backlog, not to adopt a tool that doesn't model portfolios at all. The switch verdict only wins under a narrow conjunction (see whenSwitchWouldBeRight). Absent that conjunction, keep-pm dominates.

Where the pro-switch and pro-keep critiques AGREE, and where I concur, is that the synthesis's "incorporate 8 things" half is where the real risk hides. Four of the borrows are stateful (events.jsonl audit log, ~/.pm cross-repo registry, machine-owned atomic detour CLI verbs, and above all the sha256 handoff-artifact GENERATOR) and push pm from "emit instructions" toward "generate and hash artifacts and do work" — i.e., a hand-built, solo, zero-dep reimplementation of the very Comet subsystems that keeping pm was meant to avoid depending on. Those must be reject-by-default, each gated against an explicit "does this still only emit instructions?" test. The verdict is keep-pm-and-incorporate — but with a deliberately SHORT, mostly-instructional incorporation list, plus two cheap safety fixes, not the sprawling eight.

## Documents

| File | What |
|------|------|
| [00-comet-capability-map.md](00-comet-capability-map.md) | What Comet is and does (4 subsystems) |
| [01-pm-capability-map.md](01-pm-capability-map.md) | Objective pm capability map |
| [02-comparison-matrix.md](02-comparison-matrix.md) | 15-dimension comparison + key differences |
| [03-recommendation.md](03-recommendation.md) | Verdict, when-switch-would-be-right, the debate |
| [04-incorporation-backlog.md](04-incorporation-backlog.md) | What to borrow from Comet — candidate epics |

## One-paragraph summary

Comet and pm are **adjacent layers, not substitutes**. Comet is a single-change *build engine* that bundles OpenSpec + wires Superpowers as script-gated phases and **hard-blocks out-of-phase edits**; pm is a *portfolio conductor* that sits ABOVE any build lane (lane-agnostic epic index, LIFO detour stack, reconcile-on-resume, Honcho/tracker memory). Comet competes with pm's OpenSpec/Superpowers **lane**, not with pm's conductor role — so "switching" would replace the lane pm orchestrates and forfeit pm's reason to exist, in exchange for a 31k-line, 8-dependency beta runtime coupled to two fast-moving upstreams that you would have to own or fork. Keep pm; borrow a short, mostly-instructional set of Comet's disciplines; and consider Comet later as a *build lane pm routes to* only if you want hard TDD/review gates.
