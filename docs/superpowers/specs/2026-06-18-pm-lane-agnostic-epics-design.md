# Design: Lane-agnostic epics for the `pm` plugin

- **Date:** 2026-06-18
- **Plugin:** `pm` (in `cfdude/cfdude-plugins`)
- **Version:** 0.2.0 → **0.3.0** (minor: additive schema + new commands)
- **Engine:** `plugins/pm/scripts/conductor.mjs` (single file, ~450 lines, zero deps, Node 18+)

## Problem

The conductor is documented as sitting "ABOVE OpenSpec and Superpowers" and being the
"state of record," but mechanically it only ingests **OpenSpec** changes: `init` and `sync`
derive epics solely from `openspec/changes/`, and the briefing/render layers assume every
epic is an OpenSpec proposal.

Projects that route work by size — e.g. *"<2h → Claude Code alone; 2–8h → Superpowers;
>8h/cross-system → OpenSpec"* — therefore have **2 of 3 execution lanes invisible** to the
conductor. Any work correctly routed away from OpenSpec never becomes an epic, so the
"system of record" silently misses most of the backlog. This is a structural blind spot,
not a usage error.

### Where the blind spot lives (verified in code)

- `buildBrief()` line ~240 filters NEXT UP with `&& e.present` — drops any epic without an
  on-disk OpenSpec change.
- `render()` Epics table is headed `Epic (OpenSpec change)`.
- `storyProgress(id)` reads only `openspec/changes/<id>/tasks.md`.
- `sync()` scans only `openspec/changes/`.
- `rulesBlock()` (the CLAUDE.md block) states "epics = proposals."

### What already works (so this is an extension, not a rewrite)

- `sync()` is additive — preserves hand-authored `state.epics`.
- `resolveEpics()` already tags epics `present:true|false` (on-disk vs state-only).
- `state.epics` entries are free-form; extra fields survive round-trips.

## Goals / Non-goals

**Goals**
- Make the conductor **lane-agnostic**: OpenSpec is one lane of several.
- Non-OpenSpec epics are first-class: tagged, registered, shown, and progress-tracked.
- Close the same blind spot in the **detour** path, not just the epic path.
- Keep the briefing cheap at scale (it is injected on every SessionStart + compaction).
- Give existing projects a **version-aware upgrade** path so plugin updates inform what a
  migrated project must do — no blind re-init, no silent drift.

**Non-goals**
- The conductor does **not** decide routing (which lane a task belongs to). `lane` records
  a human/Claude decision; it is a descriptive tag, not a routing engine.
- No lifecycle/progress machinery for `decision`/`external` lanes (YAGNI — see §5).

## Decisions (locked during brainstorming)

1. Progress = **precedence resolver** (not an explicit `type` field).
2. `sync` **does** import Superpowers plans as epics (additive).
3. Field name is **`lane`**.
4. Process: design doc → analytical review → writing-plans → TDD with `node:test`. No
   OpenSpec ceremony (cfdude-plugins is not an OpenSpec repo).

---

## Design

### 1. Schema — three optional fields per epic (`.conductor/state.json`)

```jsonc
{
  "id": "refactor-auth",
  "title": "Refactor auth client",
  "priority": "P1",
  "status": "queued",
  "role": "epic",                                 // epic | detour (UNCHANGED, orthogonal to lane)
  "links": [],
  "lane": "superpowers",                          // NEW: openspec|superpowers|claude-code|decision|external
  "planPath": "docs/superpowers/plans/auth.md",   // NEW (optional): a progress source
  "stories": [{ "title": "vend token", "done": false }] // NEW (optional): a progress source
}
```

- **Backward-compat:** an epic missing `lane` is treated as `"openspec"`. OpenSpec-derived
  epics are tagged `"openspec"`. Existing `state.json` files (e.g. the live `personal-finance`
  repo) keep working unchanged.
- `role` (epic|detour) stays **orthogonal** to `lane` (execution lane).
- `lane` is validated against the known set on write (`add-epic`), but unknown values are
  tolerated on read (render as their literal tag) so the field never hard-fails an old repo.

### 2. Progress — precedence resolver

Replace `storyProgress(id)` with `epicProgress(epic)` returning `{ done, total, source, warn }`:

1. `epic.stories[]` is an array → count `done` / total. `source: "stories"`.
2. else `epic.planPath` set → parse `- [ ] / - [x]` checkboxes in `ROOT/planPath`.
   `source: "plan"`. If the file is **missing**, `total:0, warn:"planPath missing"`.
3. else → `openspec/changes/<id>/tasks.md` (today's behavior). `source: "openspec"`.
4. else → `{ done:0, total:0, source:"none" }`.

The existing checkbox regex is factored into `countCheckboxes(absPath) → {done,total,exists}`,
reused by both the plan and tasks.md paths. `decision`/`external` lanes naturally fall to
case 4 and render `—`.

**Renderer update.** `bar()` (today returns only `"X/Y stories"` or `"no tasks.md"`) is
replaced by a progress-aware formatter that takes `epicProgress`'s `{done,total,source,warn}`:
- `warn` set → `⚠ <warn>` (e.g. dangling `planPath`)
- `total > 0` → `<done>/<total> <unit>` (unit = `stories` for openspec/manual, `tasks` for plan)
- else → `—`

This is what lets non-OpenSpec lanes avoid the misleading `"no tasks.md"` string.

### 3. Blind-spot fix — render layer

Define a single predicate:
```
missing(e) = e.lane === "openspec" && !e.present && !isArchived(e.id)
```
(an OpenSpec epic with no change on disk and not archived = genuinely missing its change).

- **`buildBrief()` NEXT UP:** replace `&& e.present` with `&& !missing(e)`. Non-OpenSpec
  epics are no longer dropped. (See §4 for the size cap.)
- **`render()` Epics table:** header `Epic (OpenSpec change)` → `Epic`; add a **Lane**
  column. `missing(e)` epics get a `⚠ no change on disk` marker; epics whose `epicProgress`
  returns `warn` get a `⚠ <warn>` marker (e.g. dangling `planPath`). Symmetry across lanes.
- **NOW line** gains the lane tag.

### 4. Bounded briefing (cost control at scale)

`buildBrief()` is injected as `additionalContext` on **every** SessionStart and every
compaction. A 30–100-item backlog injected every compaction is recurring token cost and
undercuts the conductor's signature feature. Therefore the **brief** stays compact:

- `NOW` (active epic, with lane) + reconcile warning if any.
- Detour stack (unchanged).
- **NEXT UP: top 5** by (priority, lane) + a per-lane count summary line
  (`lanes: openspec 4 · superpowers 12 · claude-code 9`) + `(+N more — see PROJECT.md)`.
- Rules reminder (unchanged).
- Upgrade nudge if `pmVersion` is stale (see §8).

The **full epic list** lives only in `PROJECT.md` (not injected), with a Lane column,
**sorted by priority rank then lane rank**. Lane rank is an explicit curated order (matching
the count-summary line): `openspec(0) · superpowers(1) · claude-code(2) · decision(3) ·
external(4)`, unknown lanes last. This `laneRank` tiebreak is applied in **both**
`resolveEpics()`'s sort and the brief, so ordering is deterministic and assertable. ("Sorted
by priority then lane" — there are no per-lane sub-headers; lane is a column/tag. See M2 in
the original review: acceptance wording is "sorted," not "grouped.")

### 5. Lane taxonomy — full support vs. plain tags

- **Fully wired (progress + render):** `openspec`, `superpowers`, `claude-code`.
- **Plain tags (no progress, no special lifecycle):** `decision`, `external`. They render `—`
  for progress and reuse the **same** status vocabulary as every other epic
  (`untriaged|queued|active|paused|archived`) — we just don't build progress/lifecycle
  machinery specific to them. We do **not** add new status values in 0.3.0.
  - **They DO appear in NEXT UP** (and the Epics table) like any other epic — the backlog must
    be complete; they simply show a `—` bar. The NEXT UP filter keys on `status`, not lane, so
    no lane-specific exclusion is added.

### 6. `sync` imports both lanes (additive, collision-safe)

- OpenSpec: `openspec/changes/*` → lane `openspec` (today).
- **NEW:** `docs/superpowers/plans/*.md` → each becomes a lane `superpowers` epic:
  `id` = filename without `.md`, `planPath` = its repo-relative path, `title` = first `#`
  heading if present else the id. Additive by id. The plans dir **may not exist** (it doesn't
  in cfdude-plugins today) — the scan mirrors `activeChangeIds()`'s try/catch and returns `[]`
  when absent, so `sync`/`init` never fail on its absence.
- **Collision safety:** ids are id-keyed in the `known` map. If a derived id already exists
  (e.g. an OpenSpec change `auth/` and a plan `auth.md`), `sync` **skips and warns** rather
  than overwriting. No silent merge.

### 7. New `/pm:epic add` command

- Engine: `conductor.mjs add-epic --id X --title "…" --lane superpowers --priority P1
  --status queued [--plan PATH] [--link "type:otherId:reason"]`.
  - Validates `--id` (`^[a-z0-9][a-z0-9._-]*$` — no spaces/slashes; ids land in links and the
    TSV detour log).
  - Validates `--lane` against the known set.
  - `--status` defaults to `queued` (running `add-epic` with a priority is itself an act of
    triage); `--priority` defaults to `P?`. Both overridable. Applies to every lane, including
    `decision`/`external`.
  - Refuses a duplicate id (additive only). Re-renders on success.
- New thin command file `plugins/pm/commands/epic.md` → surfaces as `/pm:epic`, documents
  `add` (room to grow `edit`/`rm` later). Follows the existing command-file pattern: parse
  intent, call the engine subcommand, then `/pm:status`.

### 8. Version-aware upgrade subsystem

**Resolving the running version (single definition).** The engine reads its own release from
`plugin.json` resolved via **`CLAUDE_PLUGIN_ROOT` when that env var is set**, falling back to
the path relative to `conductor.mjs` (`../.claude-plugin/plugin.json`) only when it is unset.
Env-first is deliberate: it lets the test suite point at a fixture `plugin.json` with a
different version (see Testing case 7) without editing the shipped file. If neither resolves
or the file is unreadable, version features degrade gracefully (no nudge, no stamp change).

**Semver comparison (single helper).** All version comparisons — both the detect/nudge and
the migration gate — go through one `cmpVer(a, b)` helper that compares **numeric**
`major.minor.patch` segments (so `0.10.0 > 0.9.0` is true). Plain string `>` is never used.
A **missing/undefined** stamped `pmVersion` is treated as `"0.0.0"` (so every registered
migration runs on a never-stamped, pre-0.3.0 repo — this is what makes the `personal-finance`
upgrade actually apply).

**Stamp:** `init` and `upgrade` write `pmVersion` (the running release) into `state.json`. The
existing numeric `version` stays the **schema** version; `pmVersion` is the **release** that
last touched the repo. (Three version concepts now exist: `version` = state schema int;
`pmVersion` = release stamp; migration registry entries keyed by `release` — see below.)

**Detect (non-blocking):** `brief()` uses `cmpVer(stamped ?? "0.0.0", running)`. If stamped is
older, it prepends one line to the briefing:
> ⚠ pm `<old>` → `<new>` since this repo was set up — run `/pm:upgrade` (CLAUDE.md rules and
> epic schema may need refreshing).

This nudge re-appears on every SessionStart **and** every PreCompact until `/pm:upgrade` runs
(`snapshot()` also builds the brief). That recurrence is intended — one non-blocking line, not
a surprise.

**`/pm:upgrade` (→ `conductor.mjs upgrade`):** runs every migration whose `release` is
`cmpVer(release, stamped ?? "0.0.0") > 0`, in registry order; then **unconditionally**
refreshes the CLAUDE.md rules block (`writeRules()`), re-renders `PROJECT.md`, and re-stamps
`pmVersion` to the running release. Idempotent — a second run finds no migrations `> stamped`
and just re-refreshes/re-stamps to the same values.

**Migration registry (the contract):** an ordered array of `{ release, note, apply(state) }`.
- `apply(state)` mutates the **raw** `state.epics` (never `resolveEpics()` output), so derived
  fields like `present`/`progress` are never persisted into `state.json`.
- `0.3.0` entry: persist an explicit `lane: "openspec"` onto any epic (including archived /
  state-only ones) lacking one — making state self-describing rather than relying solely on
  read-time defaults. Idempotent (skips epics that already have a `lane`).
- **Discipline (documented here + in CHANGELOG):** any future release that changes the schema
  or the rules block MUST ship both a CHANGELOG entry **and** a migration registry entry. This
  is what prevents drift from recurring.

### 9. Detour path — close the same blind spot

The rules text and `/pm:detour` currently assume "substantial detour → its own **OpenSpec
proposal**." A substantial detour may be a Superpowers or claude-code job.

- A spawned-detour epic gets a `lane` like any epic (default `openspec`, others allowed).
- `rulesBlock()` wording changes from "becomes its own OpenSpec proposal" to "becomes its
  own **epic in the appropriate lane**." The detour stack frames and reconcile logic are
  unchanged (they key on `role`/links, not lane).

### 10. Docs / framing fix

- `rulesBlock()`: "epics = proposals" → "epics are **lane-agnostic**; OpenSpec is one lane
  (openspec | superpowers | claude-code | decision | external)."
- `plugins/pm/README.md` and `plugins/pm/skills/conductor/SKILL.md`: same reframing; document
  `lane`, `planPath`, `stories`, `/pm:epic add`, and `/pm:upgrade`.
- New `plugins/pm/CHANGELOG.md` with the 0.3.0 entry (incl. the upgrade note).

### 11. Version + marketplace

`plugins/pm/.claude-plugin/plugin.json` and the `pm` entry in
`.claude-plugin/marketplace.json` → **0.3.0**.

---

## Testing (TDD, `node:test`, zero deps)

Run with `node --test plugins/pm/scripts/conductor.test.mjs`. Strategy: **subprocess integration** — invoke the
real CLI (`node conductor.mjs <cmd>`) against a temp `CLAUDE_PROJECT_DIR`, asserting on
`state.json` / `PROJECT.md` / stdout. This tests the real contract without refactoring the
import-time dispatch, and naturally expresses the acceptance scenario.

Cases:
1. **Lane defaulting / back-compat:** a v0.2.0-style `state.json` (no `lane`) renders without
   error; epics read as `openspec`.
2. **Progress precedence:** `stories[]` wins; else `planPath` checkboxes; else `tasks.md`;
   else `—`. Dangling `planPath` → `⚠`.
3. **`add-epic`:** valid insert; duplicate id refused; bad id/lane rejected.
4. **`sync` plan import:** plans become superpowers epics; id collision skipped + warned.
5. **Blind-spot fix:** non-OpenSpec epics appear in NEXT UP and PROJECT.md.
6. **Bounded brief:** with >5 next-up epics, brief shows top-5 + counts + "(+N more)".
7. **Upgrade:** stale `pmVersion` triggers the nudge; `/pm:upgrade` refreshes rules, stamps
   version, persists explicit lanes; idempotent on second run.
8. **Acceptance (integration):** a temp repo with **zero** OpenSpec changes registers 30
   lane-tagged epics via `add-epic`, shows them sorted by priority then lane (lane shown per epic) in `/pm:status`,
   marks one superpowers epic active, and renders its progress bar — without creating a
   single OpenSpec change.

## Acceptance criteria

- A repo with zero OpenSpec changes but 30 backlog items can register all 30 as lane-tagged
  epics, see them sorted by priority then lane (lane shown per epic), mark one active in a superpowers lane, and show
  its progress — all without creating an OpenSpec change.
- An existing v0.2.0 repo upgrades via `/pm:upgrade` with no data loss: rules refreshed,
  lanes stamped, `pmVersion` updated; second run is a no-op.
- All `node --test` cases pass.

## Risks / open questions

- **Plan-import noise:** `docs/superpowers/plans/*.md`
  may include files that aren't real epics. Mitigation: additive + easy to delete an
  unwanted epic; ids visible in triage. Acceptable.
- **Manual `stories[]` is un-DRY** (hand-maintained). It's an escape hatch, not the main
  path; the DRY paths are openspec `tasks.md` and superpowers `planPath`.
