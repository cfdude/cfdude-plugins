# Lane-Agnostic Epics for `pm` — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the `pm` conductor lane-agnostic — OpenSpec becomes one of several execution lanes (openspec | superpowers | claude-code | decision | external), with per-lane progress, plan import, an `add-epic` command, a bounded briefing, lane-aware detour wording, and a version-aware upgrade subsystem.

**Architecture:** All engine logic lives in one zero-dependency Node ESM file, `plugins/pm/scripts/conductor.mjs`. Tests are **subprocess integration** tests (`node:test`) that invoke the real CLI against a temp `CLAUDE_PROJECT_DIR` — no refactor of the import-time dispatch. New command surfaces are thin markdown files under `plugins/pm/commands/`.

**Tech Stack:** Node 18+ (`node:fs`, `node:path`, `node:child_process`, `node:url`), `node:test` + `node:assert/strict`. No third-party dependencies (hard constraint).

**Spec:** `docs/superpowers/specs/2026-06-18-pm-lane-agnostic-epics-design.md` — read it before starting.

## Global Constraints

- **Zero runtime dependencies.** Engine and tests use only Node built-ins. Node 18+.
- **Backward compatibility.** A v0.2.0 `state.json` (epics without `lane`/`planPath`/`stories`, no `pmVersion`) MUST keep working: missing `lane` reads as `"openspec"`; missing `pmVersion` reads as `"0.0.0"`.
- **`role` ⊥ `lane`.** `role` stays `epic|detour`; `lane` is a new orthogonal field. Never conflate.
- **Known lanes:** `openspec`, `superpowers`, `claude-code`, `decision`, `external`. Lane rank order (for sorting + count display): `openspec(0) · superpowers(1) · claude-code(2) · decision(3) · external(4)`, unknown lanes last (`9`).
- **Single semver helper.** All version comparison goes through `cmpVer(a,b)` (numeric major.minor.patch). Never string `>`.
- **Migrations mutate raw `state.epics`** (never `resolveEpics()` output) so derived fields are never persisted.
- **Run tests with:** `node --test plugins/pm/scripts/conductor.test.mjs` (from repo root).
- **Commit per task** with a conventional-commit message.
- **Docs + version bump are deferred to AFTER Gate 2** (implementation review). Tasks 1–11 are code+tests only; the real `plugin.json`/`marketplace.json` version stays `0.2.0` during implementation (version tests use fixtures, not the shipped file).

---

## File Structure

- `plugins/pm/scripts/conductor.mjs` — **modify**: engine (helpers, resolver, render, brief, sync, add-epic, upgrade, dispatch).
- `plugins/pm/scripts/conductor.test.mjs` — **create**: subprocess integration tests + shared harness.
- `plugins/pm/commands/epic.md` — **create**: `/pm:epic` (drives `add-epic`).
- `plugins/pm/commands/upgrade.md` — **create**: `/pm:upgrade` (drives `upgrade`).
- `plugins/pm/.claude-plugin/plugin.json` — **modify** (deferred to post-Gate-2): version → `0.3.0`.
- `.claude-plugin/marketplace.json` — **modify** (deferred): `pm` entry version → `0.3.0`.
- `plugins/pm/CHANGELOG.md` — **create** (deferred): `0.3.0` entry.
- `plugins/pm/README.md`, `plugins/pm/skills/conductor/SKILL.md` — **modify** (deferred): lane-agnostic reframing.

---

## Task 1: Test harness + baseline characterization

**Files:**
- Create: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces (for all later tasks): `run(args, {cwd, env})` → stdout string; `tmpRepo()` → temp dir path; `readState(cwd)`, `writeState(cwd, obj)`, `projectMd(cwd)`, `claudeMd(cwd)`, `parseBrief(cwd)` helpers.

- [ ] **Step 1: Write the harness + first failing test**

Create `plugins/pm/scripts/conductor.test.mjs`:

```js
import { test } from "node:test";
import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const ENGINE = path.join(path.dirname(fileURLToPath(import.meta.url)), "conductor.mjs");

export function tmpRepo() {
  return fs.mkdtempSync(path.join(os.tmpdir(), "pm-test-"));
}
export function run(args, { cwd, env = {} } = {}) {
  return execFileSync("node", [ENGINE, ...args], {
    cwd,
    env: { ...process.env, CLAUDE_PROJECT_DIR: cwd, ...env },
    encoding: "utf8",
  });
}
export function readState(cwd) {
  return JSON.parse(fs.readFileSync(path.join(cwd, ".conductor", "state.json"), "utf8"));
}
export function writeState(cwd, obj) {
  fs.mkdirSync(path.join(cwd, ".conductor"), { recursive: true });
  fs.writeFileSync(path.join(cwd, ".conductor", "state.json"), JSON.stringify(obj, null, 2) + "\n");
}
export function projectMd(cwd) {
  return fs.readFileSync(path.join(cwd, "PROJECT.md"), "utf8");
}
export function claudeMd(cwd) {
  return fs.readFileSync(path.join(cwd, "CLAUDE.md"), "utf8");
}
export function parseBrief(cwd) {
  const out = run(["brief"], { cwd });
  return out.trim() ? JSON.parse(out).hookSpecificOutput.additionalContext : "";
}

test("init scaffolds state.json, PROJECT.md, and CLAUDE.md rules block", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const state = readState(cwd);
  assert.equal(state.version, 1);
  assert.deepEqual(state.epics, []);
  assert.deepEqual(state.detourStack, []);
  assert.match(projectMd(cwd), /PROJECT — Conductor Index/);
  assert.match(claudeMd(cwd), /BEGIN pm-conductor rules/);
});
```

- [ ] **Step 2: Run to verify it passes against the CURRENT engine**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS (this characterizes existing behavior; it establishes the harness works).

- [ ] **Step 3: Commit**

```bash
git add plugins/pm/scripts/conductor.test.mjs
git commit -m "test(pm): add subprocess test harness + init characterization"
```

---

## Task 2: `lane` field + lane-aware render + deterministic sort

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`resolveEpics`, `render`; add lane helpers)
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: every resolved epic carries `lane` (string, default `"openspec"`); `resolveEpics()` sorts by `(priorityRank, laneRank, id)`. `render()` Epics table has a `Lane` column.

- [ ] **Step 1: Write failing tests**

Append to `conductor.test.mjs`:

```js
test("epic without lane reads as openspec (back-compat) and shows a Lane column", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, {
    version: 1, active: null, detourStack: [],
    epics: [{ id: "legacy", title: "Legacy epic", priority: "P1", status: "queued", role: "epic", links: [], reconcileNeeded: false }],
  });
  run(["render"], { cwd });
  const md = projectMd(cwd);
  assert.match(md, /\| Lane \|/);            // Lane column header exists
  assert.match(md, /`legacy`/);
  assert.match(md, /\| openspec \|/);        // legacy epic defaulted to openspec
});

test("epics sort by priority then lane rank deterministically", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, {
    version: 1, active: null, detourStack: [],
    epics: [
      { id: "b-sp", title: "b", priority: "P1", status: "queued", role: "epic", lane: "superpowers", links: [] },
      { id: "a-os", title: "a", priority: "P1", status: "queued", role: "epic", lane: "openspec", links: [] },
      { id: "c-cc", title: "c", priority: "P0", status: "queued", role: "epic", lane: "claude-code", links: [] },
    ],
  });
  run(["render"], { cwd });
  const md = projectMd(cwd);
  // P0 claude-code first, then P1 openspec before P1 superpowers
  const order = ["c-cc", "a-os", "b-sp"].map(id => md.indexOf(`\`${id}\``));
  assert.ok(order[0] < order[1] && order[1] < order[2], `bad order: ${order}`);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: the two new tests FAIL (no Lane column; sort lacks lane tiebreak).

- [ ] **Step 3: Add lane helpers**

In `conductor.mjs`, after the `CHANGES_DIR`/`ARCHIVE_DIR` constants (~line 47), add:

```js
const PLANS_DIR = path.join(ROOT, "docs", "superpowers", "plans");
const KNOWN_LANES = ["openspec", "superpowers", "claude-code", "decision", "external"];
const LANE_RANK = { openspec: 0, superpowers: 1, "claude-code": 2, decision: 3, external: 4 };
const laneRank = (l) => (l in LANE_RANK ? LANE_RANK[l] : 9);
```

- [ ] **Step 4: Default lane in `resolveEpics` and add the sort tiebreak**

Replace the body of `resolveEpics` (lines ~119-140) with:

```js
function resolveEpics(state) {
  const onDisk = new Set(activeChangeIds());
  const known = new Map(state.epics.map(e => [e.id, e]));
  const out = [];

  for (const id of onDisk) {
    const meta = known.get(id) || {
      id, title: id, priority: "P?", status: "untriaged", role: "epic",
      links: [], reconcileNeeded: false,
    };
    const lane = meta.lane || "openspec";
    out.push({ ...meta, lane, progress: epicProgress({ ...meta, lane }), present: true });
  }
  for (const e of state.epics) {
    if (!onDisk.has(e.id)) {
      const lane = e.lane || "openspec";
      out.push({ ...e, lane, progress: epicProgress({ ...e, lane }),
        status: isArchived(e.id) ? "archived" : e.status, present: false });
    }
  }
  const rank = { P0: 0, P1: 1, P2: 2, P3: 3, "P?": 9 };
  out.sort((a, b) =>
    ((rank[a.priority] ?? 9) - (rank[b.priority] ?? 9)) ||
    (laneRank(a.lane) - laneRank(b.lane)) ||
    a.id.localeCompare(b.id));
  return out;
}
```

> Note: `epicProgress` is introduced in Task 3. For this task, temporarily keep the call as `progress: storyProgress(meta.id || e.id)`? **No** — instead, implement Task 3's `epicProgress` and `bar` together with this task is cleaner. To keep tasks independent, in THIS task replace `epicProgress({...meta, lane})` with `storyProgress(id)` and `epicProgress({...e, lane})` with `storyProgress(e.id)` so it compiles now; Task 3 swaps `storyProgress` → `epicProgress`. (Use `storyProgress` here.)

So for Task 2, use `progress: storyProgress(id)` (first loop) and `progress: storyProgress(e.id)` (second loop).

- [ ] **Step 5: Add the Lane column in `render`**

Replace the Epics table header + row loop in `render` (lines ~305-313) with:

```js
  md.push("## Epics");
  md.push("");
  md.push("| Priority | Epic | Lane | Role | Status | Progress | Links |");
  md.push("|----------|------|------|------|--------|----------|-------|");
  for (const e of epics) {
    const links = (e.links || []).map(l => `${l.type}→${l.epic}`).join("; ") || "-";
    md.push(`| ${e.priority} | \`${e.id}\` | ${e.lane} | ${e.role} | ${e.status}${e.reconcileNeeded ? " ⚠" : ""} | ${bar(e.progress)} | ${links} |`);
  }
  md.push("");
```

- [ ] **Step 6: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS (all tests, including Task 1).

- [ ] **Step 7: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): add lane field, lane column, and deterministic lane sort"
```

---

## Task 3: Precedence progress resolver + progress-aware `bar()`

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (replace `storyProgress`, add `countCheckboxes`/`epicProgress`, replace `bar`, swap call sites)
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: `epicProgress(epic) → { done, total, source, warn }` where `source ∈ {stories,plan,openspec,none}`; `bar(progress) → "⚠ <warn>" | "<done>/<total> <unit>" | "—"`.
- Consumes: `resolveEpics` (Task 2) now calls `epicProgress` instead of `storyProgress`.

- [ ] **Step 1: Write failing tests**

Append to `conductor.test.mjs`:

```js
test("progress precedence: manual stories win", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, { version: 1, active: null, detourStack: [], epics: [
    { id: "m", title: "m", priority: "P1", status: "queued", role: "epic", lane: "claude-code",
      stories: [{ title: "a", done: true }, { title: "b", done: false }], links: [] },
  ]});
  run(["render"], { cwd });
  assert.match(projectMd(cwd), /1\/2 stories/);
});

test("progress precedence: planPath checkboxes when no stories", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  fs.mkdirSync(path.join(cwd, "docs", "superpowers", "plans"), { recursive: true });
  fs.writeFileSync(path.join(cwd, "docs", "superpowers", "plans", "p.md"),
    "# Plan\n- [x] one\n- [ ] two\n- [ ] three\n");
  writeState(cwd, { version: 1, active: null, detourStack: [], epics: [
    { id: "sp", title: "sp", priority: "P1", status: "queued", role: "epic", lane: "superpowers",
      planPath: "docs/superpowers/plans/p.md", links: [] },
  ]});
  run(["render"], { cwd });
  assert.match(projectMd(cwd), /1\/3 tasks/);
});

test("dangling planPath renders a warning, not a count", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, { version: 1, active: null, detourStack: [], epics: [
    { id: "sp", title: "sp", priority: "P1", status: "queued", role: "epic", lane: "superpowers",
      planPath: "docs/superpowers/plans/missing.md", links: [] },
  ]});
  run(["render"], { cwd });
  assert.match(projectMd(cwd), /⚠ planPath missing/);
});

test("decision lane with no source renders an em dash", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, { version: 1, active: null, detourStack: [], epics: [
    { id: "d", title: "d", priority: "P2", status: "queued", role: "epic", lane: "decision", links: [] },
  ]});
  run(["render"], { cwd });
  assert.match(projectMd(cwd), /`d` \| decision \| epic \| queued \| — \|/);
});

test("openspec lane still reads tasks.md by id", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const ch = path.join(cwd, "openspec", "changes", "feat-x");
  fs.mkdirSync(ch, { recursive: true });
  fs.writeFileSync(path.join(ch, "tasks.md"), "- [x] a\n- [x] b\n- [ ] c\n");
  run(["sync"], { cwd });
  run(["render"], { cwd });
  assert.match(projectMd(cwd), /2\/3 stories/);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: new tests FAIL (no plan/stories/em-dash handling; "no tasks.md" string still used).

- [ ] **Step 3: Replace `storyProgress` with `countCheckboxes` + `epicProgress`**

Replace `storyProgress` (lines ~105-116) with:

```js
/** Count [ ] / [x] checkboxes in a markdown file. */
function countCheckboxes(absPath) {
  let total = 0, done = 0, exists = false;
  try {
    const txt = fs.readFileSync(absPath, "utf8");
    exists = true;
    for (const line of txt.split("\n")) {
      const m = line.match(/^\s*[-*]\s+\[([ xX])\]/);
      if (m) { total++; if (m[1].toLowerCase() === "x") done++; }
    }
  } catch { /* missing file */ }
  return { done, total, exists };
}

/** Resolve an epic's progress by precedence: stories -> planPath -> openspec tasks.md -> none. */
function epicProgress(epic) {
  if (Array.isArray(epic.stories)) {
    const total = epic.stories.length;
    const done = epic.stories.filter(s => s && s.done).length;
    return { done, total, source: "stories", warn: null };
  }
  if (epic.planPath) {
    const c = countCheckboxes(path.join(ROOT, epic.planPath));
    if (!c.exists) return { done: 0, total: 0, source: "plan", warn: "planPath missing" };
    return { done: c.done, total: c.total, source: "plan", warn: null };
  }
  if ((epic.lane || "openspec") === "openspec") {
    const c = countCheckboxes(path.join(CHANGES_DIR, epic.id, "tasks.md"));
    return { done: c.done, total: c.total, source: "openspec", warn: null };
  }
  return { done: 0, total: 0, source: "none", warn: null };
}
```

- [ ] **Step 4: Replace `bar`**

Replace `bar` (lines ~142-144) with:

```js
function bar(p) {
  if (!p) return "—";
  if (p.warn) return `⚠ ${p.warn}`;
  if (p.total > 0) return `${p.done}/${p.total} ${p.source === "plan" ? "tasks" : "stories"}`;
  return "—";
}
```

- [ ] **Step 5: Swap `resolveEpics` call sites to `epicProgress`**

In `resolveEpics` (Task 2 edit), change `progress: storyProgress(id)` → `progress: epicProgress({ ...meta, lane })` and `progress: storyProgress(e.id)` → `progress: epicProgress({ ...e, lane })`.

- [ ] **Step 6: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): precedence progress resolver (stories|plan|openspec) + progress-aware bar"
```

---

## Task 4: Blind-spot fix — non-OpenSpec epics in NEXT UP, missing-change marker, lane in NOW/NEXT

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (add `missing`; `buildBrief` NOW + NEXT UP; `render` missing marker)
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: `missing(e) = e.lane === "openspec" && !e.present && !isArchived(e.id)`. NEXT UP filter uses `!missing(e)`. NOW + NEXT lines include lane.

- [ ] **Step 1: Write failing tests**

Append:

```js
test("non-openspec epic appears in NEXT UP", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, { version: 1, active: null, detourStack: [], epics: [
    { id: "sp1", title: "sp1", priority: "P1", status: "queued", role: "epic", lane: "superpowers",
      stories: [{ title: "x", done: false }], links: [] },
  ]});
  const brief = parseBrief(cwd);
  assert.match(brief, /NEXT UP/);
  assert.match(brief, /`sp1` \(P1, superpowers, queued\)/);
});

test("missing openspec change is marked and excluded from NEXT UP", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, { version: 1, active: null, detourStack: [], epics: [
    { id: "ghost", title: "ghost", priority: "P1", status: "queued", role: "epic", lane: "openspec", links: [] },
  ]});
  run(["render"], { cwd });
  assert.match(projectMd(cwd), /no change on disk/);
  const brief = parseBrief(cwd);
  assert.doesNotMatch(brief, /`ghost`/);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: both FAIL (NEXT UP still requires `present`; no missing marker).

- [ ] **Step 3: Add `missing` predicate**

In `conductor.mjs`, right after `resolveEpics` add:

```js
/** An openspec epic with no change on disk and not archived = genuinely missing its change. */
function missing(e) {
  return e.lane === "openspec" && !e.present && !isArchived(e.id);
}
```

- [ ] **Step 4: NOW line + NEXT UP filter in `buildBrief`**

In `buildBrief`, change the NOW line (line ~220) to include lane:

```js
    L.push(`NOW: \`${active.id}\` (${active.lane}, ${active.role}, ${active.priority}) — ${bar(active.progress)}`);
```

Replace the NEXT UP block (lines ~240-245) with:

```js
  const queued = epics.filter(e => ["queued", "untriaged"].includes(e.status) && !missing(e));
  if (queued.length) {
    L.push("NEXT UP (by priority, then lane):");
    for (const e of queued) L.push(`  • \`${e.id}\` (${e.priority}, ${e.lane}, ${e.status}) — ${bar(e.progress)}`);
    L.push("");
  }
```

(The size cap is added in Task 5.)

- [ ] **Step 5: Missing marker in `render` Epics table**

In the `render` Epics row loop (from Task 2), change the status cell to include the marker:

```js
    const miss = missing(e) ? " ⚠ no change on disk" : "";
    md.push(`| ${e.priority} | \`${e.id}\` | ${e.lane} | ${e.role} | ${e.status}${e.reconcileNeeded ? " ⚠" : ""}${miss} | ${bar(e.progress)} | ${links} |`);
```

- [ ] **Step 6: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): show non-openspec epics in NEXT UP; mark missing openspec changes"
```

---

## Task 5: Bounded briefing (top-5 + per-lane counts + "+N more")

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`buildBrief` NEXT UP)
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: brief NEXT UP shows at most `NEXT_CAP` (5) entries, a `(+N more — see PROJECT.md)` line when truncated, and a `lanes: <lane> <n> · …` count line. Active epic + detour stack remain unconditionally shown.

- [ ] **Step 1: Write failing tests**

Append:

```js
function manyEpics(n) {
  return Array.from({ length: n }, (_, i) => ({
    id: `e${String(i).padStart(2, "0")}`, title: `e${i}`, priority: "P1",
    status: "queued", role: "epic", lane: "superpowers",
    stories: [{ title: "x", done: false }], links: [],
  }));
}

test("brief caps NEXT UP at 5 and reports the remainder", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  writeState(cwd, { version: 1, active: null, detourStack: [], epics: manyEpics(8) });
  const brief = parseBrief(cwd);
  const shown = (brief.match(/^ {2}• /gm) || []).length;
  assert.equal(shown, 5);
  assert.match(brief, /\(\+3 more — see PROJECT\.md\)/);
  assert.match(brief, /lanes: superpowers 8/);
});

test("active epic is shown even when NEXT UP is capped", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const epics = manyEpics(8);
  epics.push({ id: "live", title: "live", priority: "P0", status: "active", role: "epic", lane: "openspec", links: [] });
  writeState(cwd, { version: 1, active: "live", detourStack: [], epics });
  const brief = parseBrief(cwd);
  assert.match(brief, /NOW: `live`/);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: cap test FAILS (all 8 shown; no remainder/lanes line).

- [ ] **Step 3: Add cap + counts to `buildBrief` NEXT UP**

Replace the NEXT UP block from Task 4 with:

```js
  const NEXT_CAP = 5;
  const queued = epics.filter(e => ["queued", "untriaged"].includes(e.status) && !missing(e));
  if (queued.length) {
    L.push("NEXT UP (by priority, then lane):");
    for (const e of queued.slice(0, NEXT_CAP)) {
      L.push(`  • \`${e.id}\` (${e.priority}, ${e.lane}, ${e.status}) — ${bar(e.progress)}`);
    }
    if (queued.length > NEXT_CAP) L.push(`  (+${queued.length - NEXT_CAP} more — see PROJECT.md)`);
    const counts = {};
    for (const e of epics) if (!missing(e)) counts[e.lane] = (counts[e.lane] || 0) + 1;
    const ordered = KNOWN_LANES.filter(l => counts[l]).map(l => `${l} ${counts[l]}`);
    const unknown = Object.keys(counts).filter(l => !KNOWN_LANES.includes(l)).sort().map(l => `${l} ${counts[l]}`);
    L.push(`  lanes: ${[...ordered, ...unknown].join(" · ")}`);
    L.push("");
  }
```

- [ ] **Step 4: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): bound the briefing (top-5 next-up + per-lane counts)"
```

---

## Task 6: `add-epic` subcommand + `/pm:epic` command

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`parseFlags`, `addEpic`, dispatch)
- Create: `plugins/pm/commands/epic.md`
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces CLI: `conductor.mjs add-epic --id X --title "…" --lane <known> [--priority P1] [--status queued] [--plan PATH] [--link "type:epic:reason"]`. Defaults: `--priority P?`, `--status queued`. Requires valid `--id` (`^[a-z0-9][a-z0-9._-]*$`) and known `--lane`. Refuses duplicate id (exit 1). Re-renders on success.

- [ ] **Step 1: Write failing tests**

Append:

```js
function expectFail(fn) {
  try { fn(); return null; } catch (e) { return e; }
}

test("add-epic inserts a lane-tagged epic with defaults", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  run(["add-epic", "--id", "refactor-auth", "--title", "Refactor auth", "--lane", "superpowers", "--priority", "P1"], { cwd });
  const e = readState(cwd).epics.find(x => x.id === "refactor-auth");
  assert.equal(e.lane, "superpowers");
  assert.equal(e.priority, "P1");
  assert.equal(e.status, "queued");
  assert.equal(e.role, "epic");
});

test("add-epic rejects a duplicate id", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  run(["add-epic", "--id", "dup", "--lane", "claude-code"], { cwd });
  const err = expectFail(() => run(["add-epic", "--id", "dup", "--lane", "claude-code"], { cwd }));
  assert.ok(err, "expected non-zero exit on duplicate");
});

test("add-epic rejects a bad id and an unknown lane", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  assert.ok(expectFail(() => run(["add-epic", "--id", "Bad ID", "--lane", "claude-code"], { cwd })));
  assert.ok(expectFail(() => run(["add-epic", "--id", "ok", "--lane", "nope"], { cwd })));
});

test("add-epic stores planPath and links", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  run(["add-epic", "--id", "x", "--lane", "superpowers", "--plan", "docs/superpowers/plans/x.md",
       "--link", "blocks:y:needs token"], { cwd });
  const e = readState(cwd).epics.find(x => x.id === "x");
  assert.equal(e.planPath, "docs/superpowers/plans/x.md");
  assert.deepEqual(e.links, [{ type: "blocks", epic: "y", reason: "needs token" }]);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL (`add-epic` not a recognized subcommand → engine prints usage + exit 1; but the success test also fails because nothing is inserted).

- [ ] **Step 3: Add `parseFlags` + `addEpic`**

In `conductor.mjs`, before the dispatch block, add:

```js
function parseFlags(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const k = a.slice(2);
    const v = (argv[i + 1] !== undefined && !argv[i + 1].startsWith("--")) ? argv[++i] : "true";
    if (k === "link") (o.link || (o.link = [])).push(v);
    else o[k] = v;
  }
  return o;
}

function addEpic() {
  if (!isInitialized()) { process.stderr.write("conductor: run /pm:init first\n"); process.exit(1); }
  const f = parseFlags(process.argv.slice(3));
  if (!f.id || !/^[a-z0-9][a-z0-9._-]*$/.test(f.id)) {
    process.stderr.write("conductor: --id required, format ^[a-z0-9][a-z0-9._-]*$\n"); process.exit(1);
  }
  const lane = f.lane;
  if (!KNOWN_LANES.includes(lane)) {
    process.stderr.write(`conductor: --lane must be one of ${KNOWN_LANES.join("|")}\n`); process.exit(1);
  }
  const state = loadState();
  if (state.epics.some(e => e.id === f.id)) {
    process.stderr.write(`conductor: epic '${f.id}' already exists\n`); process.exit(1);
  }
  const links = (f.link || []).map(s => {
    const [type, epic, ...rest] = s.split(":");
    const reason = rest.join(":").trim();
    return reason ? { type, epic, reason } : { type, epic };
  });
  const epic = {
    id: f.id, title: f.title || f.id, priority: f.priority || "P?",
    status: f.status || "queued", role: "epic", lane, links, reconcileNeeded: false,
  };
  if (f.plan) epic.planPath = f.plan;
  state.epics.push(epic);
  saveState(state);
  render();
  process.stderr.write(`conductor: added epic '${f.id}' (${lane})\n`);
}
```

- [ ] **Step 4: Register in dispatch**

In the dispatch object (lines ~435-444) add `"add-epic": addEpic,` and update the usage string to include `add-epic`.

- [ ] **Step 5: Create the command file**

Create `plugins/pm/commands/epic.md`:

```markdown
---
description: Register a non-OpenSpec epic in the conductor (lane-tagged)
allowed-tools: Bash, Read
---

Register an epic in a non-OpenSpec lane (superpowers, claude-code, decision, external) —
for work that is correctly routed away from OpenSpec but still belongs in the system of record.

Usage: `/pm:epic add <id> "<title>" <lane> [priority] [--plan <path>] [--link type:epic:reason]`

1. Parse the user's request into: id (kebab-case), title, lane (one of
   openspec|superpowers|claude-code|decision|external), priority (P0–P3, default P?),
   optional plan path, optional links.

2. Run the engine:

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/conductor.mjs" add-epic \
     --id "<id>" --title "<title>" --lane "<lane>" --priority "<P?>" \
     [--plan "<docs/superpowers/plans/...md>"] [--link "blocks:<id>:<reason>"]
   ```

   If `${CLAUDE_PLUGIN_ROOT}` is empty:
   `ENGINE=$(find ~/.claude -name conductor.mjs -path '*pm*' 2>/dev/null | head -1); node "$ENGINE" add-epic …`

3. Show the result with `/pm:status`.
```

- [ ] **Step 6: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs plugins/pm/commands/epic.md
git commit -m "feat(pm): add-epic subcommand + /pm:epic command"
```

---

## Task 7: `sync` imports Superpowers plans (collision-safe)

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`planFiles`, `firstHeading`, `sync`)
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: `sync` adds `docs/superpowers/plans/*.md` as `superpowers`-lane epics (`id` = filename sans `.md`, `planPath` set, `title` = first `# heading` or id). Tolerates a missing plans dir. Skips + warns on id collision with an existing epic (including openspec changes added in the same run).

- [ ] **Step 1: Write failing tests**

Append:

```js
test("sync imports superpowers plans as lane-tagged epics", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  fs.mkdirSync(path.join(cwd, "docs", "superpowers", "plans"), { recursive: true });
  fs.writeFileSync(path.join(cwd, "docs", "superpowers", "plans", "big-refactor.md"), "# Big Refactor\n- [ ] a\n");
  run(["sync"], { cwd });
  const e = readState(cwd).epics.find(x => x.id === "big-refactor");
  assert.equal(e.lane, "superpowers");
  assert.equal(e.title, "Big Refactor");
  assert.equal(e.planPath, "docs/superpowers/plans/big-refactor.md");
});

test("sync tolerates a missing plans dir", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });            // no docs/ dir at all
  run(["sync"], { cwd });            // must not throw
  assert.ok(Array.isArray(readState(cwd).epics));
});

test("sync skips a plan whose id collides with an existing epic", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  run(["add-epic", "--id", "auth", "--lane", "openspec"], { cwd });
  fs.mkdirSync(path.join(cwd, "docs", "superpowers", "plans"), { recursive: true });
  fs.writeFileSync(path.join(cwd, "docs", "superpowers", "plans", "auth.md"), "# Auth\n- [ ] a\n");
  run(["sync"], { cwd });
  const matches = readState(cwd).epics.filter(x => x.id === "auth");
  assert.equal(matches.length, 1);
  assert.equal(matches[0].lane, "openspec");   // original kept; plan skipped
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: import + collision tests FAIL (sync ignores plans).

- [ ] **Step 3: Add `planFiles` + `firstHeading`**

In `conductor.mjs`, near `activeChangeIds` add:

```js
function planFiles() {
  try {
    return fs.readdirSync(PLANS_DIR, { withFileTypes: true })
      .filter(d => d.isFile() && d.name.endsWith(".md"))
      .map(d => d.name);
  } catch { return []; }
}

function firstHeading(absPath) {
  try {
    for (const line of fs.readFileSync(absPath, "utf8").split("\n")) {
      const m = line.match(/^#\s+(.+)/);
      if (m) return m[1].trim();
    }
  } catch { /* ignore */ }
  return null;
}
```

- [ ] **Step 4: Extend `sync`**

Replace `sync` (lines ~408-420) with:

```js
function sync(quiet = false) {
  const state = loadState();
  const known = new Set(state.epics.map(e => e.id));
  let added = 0;
  for (const id of activeChangeIds()) {
    if (!known.has(id)) {
      state.epics.push({ id, title: id, priority: "P?", status: "untriaged", role: "epic", lane: "openspec", links: [], reconcileNeeded: false });
      known.add(id); added++;
    }
  }
  for (const fname of planFiles()) {
    const id = fname.replace(/\.md$/, "");
    if (known.has(id)) {
      if (!quiet) process.stderr.write(`conductor: sync skipped plan '${id}' — id already exists\n`);
      continue;
    }
    const planPath = path.join("docs", "superpowers", "plans", fname);
    const title = firstHeading(path.join(PLANS_DIR, fname)) || id;
    state.epics.push({ id, title, priority: "P?", status: "untriaged", role: "epic", lane: "superpowers", planPath, links: [], reconcileNeeded: false });
    known.add(id); added++;
  }
  saveState(state);
  if (!quiet) process.stderr.write(`conductor: synced (${added} new epic(s) added as untriaged)\n`);
}
```

- [ ] **Step 5: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): sync imports superpowers plans (collision-safe, lane-tagged)"
```

---

## Task 8: Version stamping + `cmpVer` + upgrade nudge

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`fileURLToPath` import, `pluginVersion`, `cmpVer`, `stampVersion`, `init` stamps, `buildBrief` nudge)
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: `pluginVersion()` (env-first via `CLAUDE_PLUGIN_ROOT`, else relative to the script); `cmpVer(a,b)` numeric semver compare; `stampVersion(state)` sets `state.pmVersion`. `init` stamps. `buildBrief` prepends a one-line upgrade nudge when `cmpVer(stamped ?? "0.0.0", running) < 0`.

- [ ] **Step 1: Write failing tests**

Append. These create a fixture plugin dir so the "running" version can differ from the stamped one:

```js
function fixturePluginRoot(version) {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "pm-plugin-"));
  fs.mkdirSync(path.join(dir, ".claude-plugin"), { recursive: true });
  fs.writeFileSync(path.join(dir, ".claude-plugin", "plugin.json"), JSON.stringify({ name: "pm", version }) + "\n");
  return dir;
}

test("init stamps pmVersion from the running plugin", () => {
  const cwd = tmpRepo();
  const root = fixturePluginRoot("0.3.0");
  run(["init"], { cwd, env: { CLAUDE_PLUGIN_ROOT: root } });
  assert.equal(readState(cwd).pmVersion, "0.3.0");
});

test("brief nudges when stamped pmVersion is older than running (semver-aware)", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  // simulate an old repo: stamp 0.9.0, run as 0.10.0 (string compare would get this wrong)
  const s = readState(cwd); s.pmVersion = "0.9.0"; writeState(cwd, s);
  const root = fixturePluginRoot("0.10.0");
  const out = JSON.parse(run(["brief"], { cwd, env: { CLAUDE_PLUGIN_ROOT: root } })).hookSpecificOutput.additionalContext;
  assert.match(out, /pm 0\.9\.0 → 0\.10\.0 since this repo was set up/);
  assert.match(out, /\/pm:upgrade/);
});

test("no nudge when stamped equals running", () => {
  const cwd = tmpRepo();
  const root = fixturePluginRoot("0.3.0");
  run(["init"], { cwd, env: { CLAUDE_PLUGIN_ROOT: root } });
  const out = JSON.parse(run(["brief"], { cwd, env: { CLAUDE_PLUGIN_ROOT: root } })).hookSpecificOutput.additionalContext;
  assert.doesNotMatch(out, /since this repo was set up/);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL (no `pmVersion` stamp; no nudge).

- [ ] **Step 3: Add the `fileURLToPath` import**

At the top of `conductor.mjs`, add to the imports:

```js
import { fileURLToPath } from "node:url";
```

- [ ] **Step 4: Add `pluginVersion`, `cmpVer`, `stampVersion`**

Add near the other helpers:

```js
/** The running plugin's release. Env-first so tests can point at a fixture plugin.json. */
function pluginVersion() {
  const root = process.env.CLAUDE_PLUGIN_ROOT
    ? process.env.CLAUDE_PLUGIN_ROOT
    : path.join(path.dirname(fileURLToPath(import.meta.url)), "..");
  const pj = readJSON(path.join(root, ".claude-plugin", "plugin.json"), null);
  return pj && pj.version ? String(pj.version) : null;
}

/** Numeric semver compare: <0 if a<b, 0 if equal, >0 if a>b. */
function cmpVer(a, b) {
  const pa = String(a).split(".").map(n => parseInt(n, 10) || 0);
  const pb = String(b).split(".").map(n => parseInt(n, 10) || 0);
  for (let i = 0; i < 3; i++) {
    const d = (pa[i] || 0) - (pb[i] || 0);
    if (d) return d;
  }
  return 0;
}

function stampVersion(state) {
  const v = pluginVersion();
  if (v) state.pmVersion = v;
}
```

- [ ] **Step 5: Stamp on `init`**

In `init` (lines ~343-357), after `sync(true)` and before `render()`, stamp:

```js
  sync(true);                 // pull in existing openspec changes + plans
  { const s = loadState(); stampVersion(s); saveState(s); }
  writeRules();
  render();
```

- [ ] **Step 6: Prepend the nudge in `buildBrief`**

At the very start of `buildBrief` (before `L.push("CONDUCTOR STATE …")`), add:

```js
  const running = pluginVersion();
  const stamped = state.pmVersion || "0.0.0";
  if (running && cmpVer(stamped, running) < 0) {
    L.push(`⚠ pm ${stamped} → ${running} since this repo was set up — run \`/pm:upgrade\` (CLAUDE.md rules and epic schema may need refreshing).`);
    L.push("");
  }
```

- [ ] **Step 7: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): stamp pmVersion + semver-aware upgrade nudge in the briefing"
```

---

## Task 9: `upgrade` subcommand + migration registry + `/pm:upgrade`

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`MIGRATIONS`, `upgrade`, dispatch)
- Create: `plugins/pm/commands/upgrade.md`
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces CLI: `conductor.mjs upgrade` — runs every migration with `cmpVer(release, stamped ?? "0.0.0") > 0` in order, refreshes the rules block, re-renders, and re-stamps `pmVersion`. Idempotent.
- `MIGRATIONS = [{ release, note, apply(state) }]`; the `0.3.0` entry stamps explicit `lane: "openspec"` on any epic lacking one.

- [ ] **Step 1: Write failing tests**

Append:

```js
test("upgrade on a never-stamped repo runs migrations, stamps lanes + pmVersion", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  // simulate a pre-0.3.0 repo: remove pmVersion, add an epic with no lane
  const s = readState(cwd); delete s.pmVersion;
  s.epics.push({ id: "legacy", title: "legacy", priority: "P1", status: "queued", role: "epic", links: [] });
  writeState(cwd, s);
  const root = fixturePluginRoot("0.3.0");
  run(["upgrade"], { cwd, env: { CLAUDE_PLUGIN_ROOT: root } });
  const after = readState(cwd);
  assert.equal(after.pmVersion, "0.3.0");
  assert.equal(after.epics.find(e => e.id === "legacy").lane, "openspec");
});

test("upgrade is idempotent on a second run", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const s = readState(cwd); delete s.pmVersion; writeState(cwd, s);
  const root = fixturePluginRoot("0.3.0");
  run(["upgrade"], { cwd, env: { CLAUDE_PLUGIN_ROOT: root } });
  const first = fs.readFileSync(path.join(cwd, ".conductor", "state.json"), "utf8");
  run(["upgrade"], { cwd, env: { CLAUDE_PLUGIN_ROOT: root } });
  const second = fs.readFileSync(path.join(cwd, ".conductor", "state.json"), "utf8");
  assert.equal(first, second);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL (`upgrade` not recognized).

- [ ] **Step 3: Add `MIGRATIONS` + `upgrade`**

In `conductor.mjs`, before the dispatch block:

```js
const MIGRATIONS = [
  {
    release: "0.3.0",
    note: "stamp explicit lane on epics (lane-agnostic schema)",
    apply(state) {
      for (const e of state.epics) if (!e.lane) e.lane = "openspec";
    },
  },
];

function upgrade() {
  if (!isInitialized()) { process.stderr.write("conductor: run /pm:init first\n"); process.exit(1); }
  const state = loadState();
  const stamped = state.pmVersion || "0.0.0";
  let applied = 0;
  for (const m of MIGRATIONS) {
    if (cmpVer(m.release, stamped) > 0) { m.apply(state); applied++; }
  }
  stampVersion(state);
  saveState(state);
  writeRules();
  render();
  process.stderr.write(`conductor: upgraded (${applied} migration(s)), pmVersion now ${state.pmVersion || "unknown"}\n`);
}
```

- [ ] **Step 4: Register in dispatch**

Add `upgrade,` to the dispatch object and append `upgrade` to the usage string.

- [ ] **Step 5: Create the command file**

Create `plugins/pm/commands/upgrade.md`:

```markdown
---
description: Upgrade this repo's conductor state/rules to the current pm plugin version
allowed-tools: Bash, Read
---

Bring this repository in line with the currently-installed `pm` plugin version. Safe to run
anytime; idempotent. Use it when the briefing shows a "pm <old> → <new>" upgrade nudge.

1. Run the engine's upgrade (applies any pending migrations, refreshes the CLAUDE.md rules
   block, re-renders PROJECT.md, and re-stamps the recorded version):

   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/scripts/conductor.mjs" upgrade
   ```

   If `${CLAUDE_PLUGIN_ROOT}` is empty:
   `ENGINE=$(find ~/.claude -name conductor.mjs -path '*pm*' 2>/dev/null | head -1); node "$ENGINE" upgrade`

2. Show the result with `/pm:status`.
```

- [ ] **Step 6: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs plugins/pm/commands/upgrade.md
git commit -m "feat(pm): version-aware upgrade subcommand + migration registry + /pm:upgrade"
```

---

## Task 10: Lane-agnostic rules wording (detour path)

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`rulesBlock`)
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: the CLAUDE.md rules block no longer states "epics = proposals" / "becomes its own OpenSpec proposal"; it states epics are lane-agnostic and a substantial detour becomes its own epic in the appropriate lane.

- [ ] **Step 1: Write failing test**

Append:

```js
test("rules block is lane-agnostic, not openspec-only", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const out = run(["rules"], { cwd });
  assert.match(out, /lane-agnostic/i);
  assert.match(out, /openspec \| superpowers \| claude-code/);
  assert.doesNotMatch(out, /becomes its own OpenSpec proposal/);
});
```

- [ ] **Step 2: Run to verify failure**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL (current rules say "epics = proposals" and "becomes its own OpenSpec proposal").

- [ ] **Step 3: Reword `rulesBlock`**

In `rulesBlock` (lines ~159-184), change the intro line and the substantial-detour bullet:

Replace:
```js
    "This repo is managed by the `pm` plugin. The conductor sits ABOVE OpenSpec (epics =",
    "proposals; stories = `tasks.md` checkboxes) and Superpowers. Follow these rules:",
```
with:
```js
    "This repo is managed by the `pm` plugin. The conductor sits ABOVE OpenSpec and Superpowers.",
    "Epics are **lane-agnostic** (openspec | superpowers | claude-code | decision | external);",
    "OpenSpec is one lane. Stories come from each epic's source (OpenSpec `tasks.md`, a Superpowers",
    "plan, or a manual list). Follow these rules:",
```

Replace:
```js
    "   - *Substantial* (own design / changes shared behavior / multi-step): run `/pm:detour`.",
    "     It becomes its own OpenSpec proposal; PUSH the current epic onto the detour stack in",
    "     `.conductor/state.json` with a concrete reason and `reconcileOnResume`.",
```
with:
```js
    "   - *Substantial* (own design / changes shared behavior / multi-step): run `/pm:detour`.",
    "     It becomes its own epic in the appropriate lane (OpenSpec proposal, Superpowers plan,",
    "     etc.); PUSH the current epic onto the detour stack in `.conductor/state.json` with a",
    "     concrete reason and `reconcileOnResume`.",
```

- [ ] **Step 4: Run tests**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): lane-agnostic rules wording (detours are not OpenSpec-only)"
```

---

## Task 11: Acceptance integration test

**Files:**
- Modify: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Consumes: `add-epic`, `brief`, `render` from prior tasks.

- [ ] **Step 1: Write the acceptance test**

Append. This is the spec's acceptance scenario end-to-end:

```js
test("ACCEPTANCE: 30 lane-tagged epics, zero OpenSpec changes", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const lanes = ["superpowers", "claude-code", "decision"];
  for (let i = 0; i < 30; i++) {
    const lane = lanes[i % lanes.length];
    const pr = `P${i % 4}`;
    run(["add-epic", "--id", `item-${String(i).padStart(2, "0")}`, "--title", `Item ${i}`,
         "--lane", lane, "--priority", pr], { cwd });
  }
  // mark one superpowers epic active with manual progress
  const s = readState(cwd);
  const target = s.epics.find(e => e.lane === "superpowers");
  target.status = "active";
  target.stories = [{ title: "a", done: true }, { title: "b", done: false }];
  s.active = target.id;
  writeState(cwd, s);
  run(["render"], { cwd });

  // all 30 registered, none from OpenSpec
  assert.equal(readState(cwd).epics.length, 30);
  assert.equal(fs.existsSync(path.join(cwd, "openspec")), false);

  // PROJECT.md shows them with lanes and the active one's progress
  const md = projectMd(cwd);
  for (let i = 0; i < 30; i++) assert.match(md, new RegExp(`item-${String(i).padStart(2, "0")}`));
  assert.match(md, /1\/2 stories/);                  // active epic's manual progress rendered
  assert.match(md, new RegExp(`\`${target.id}\``));

  // brief is bounded and shows lane counts
  const brief = parseBrief(cwd);
  assert.match(brief, /NOW: `/);
  assert.match(brief, /lanes: /);
  assert.match(brief, /\(\+\d+ more — see PROJECT\.md\)/);
});
```

- [ ] **Step 2: Run the full suite**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS (all tasks' tests).

- [ ] **Step 3: Commit**

```bash
git add plugins/pm/scripts/conductor.test.mjs
git commit -m "test(pm): acceptance — 30 lane-tagged epics with zero OpenSpec changes"
```

---

## GATE 2 — Implementation review (BEFORE docs)

After Task 11, run `superpowers:requesting-code-review` against the full committed diff for this
change (BASE = the commit before Task 1; HEAD = Task 11's commit). Fix Critical + Important
findings before proceeding. Only then do the deferred documentation/version work below.

---

## Task 12 (POST-GATE-2): Docs + version bump

**Files:**
- Modify: `plugins/pm/.claude-plugin/plugin.json` — `version` → `0.3.0`
- Modify: `.claude-plugin/marketplace.json` — `pm` entry `version` → `0.3.0`
- Create: `plugins/pm/CHANGELOG.md`
- Modify: `plugins/pm/README.md`, `plugins/pm/skills/conductor/SKILL.md`

- [ ] **Step 1: Bump versions** in `plugin.json` and the `pm` entry of `marketplace.json` to `0.3.0`.
- [ ] **Step 2: Create `plugins/pm/CHANGELOG.md`** with a `0.3.0` entry documenting: lanes, precedence progress, `/pm:epic add`, plan import, bounded briefing, lane-aware detours, and the **upgrade path** ("existing repos: run `/pm:upgrade` after updating the plugin").
- [ ] **Step 3: Reframe `README.md` + `skills/conductor/SKILL.md`** — epics are lane-agnostic (OpenSpec is one lane); document `lane`, `planPath`, `stories`, `/pm:epic`, `/pm:upgrade`.
- [ ] **Step 4: Sanity-run** `node --test plugins/pm/scripts/conductor.test.mjs` (still green) and `git grep -n "epics = proposals"` (expect no stale framing).
- [ ] **Step 5: Commit**

```bash
git add -A
git commit -m "docs(pm): lane-agnostic docs + bump pm to 0.3.0"
```

---

## Self-Review (run by the plan author before handoff)

**Spec coverage:** §1 schema → T2/T3/T6; §2 progress → T3; §3 render fix → T2/T4; §4 bounded brief → T5; §5 lane taxonomy → T2/T3 (decision/external render `—`, appear in NEXT UP via T4); §6 sync plans → T7; §7 add-epic → T6; §8 upgrade subsystem → T8/T9; §9 lane-aware detours → T10; §10 docs → T12; §11 version/marketplace → T12; Testing → T1 harness + per-task + T11 acceptance. All sections mapped.

**Placeholder scan:** No "TBD/TODO"; every code step shows complete code; every test step shows the assertion.

**Type/name consistency:** `epicProgress` returns `{done,total,source,warn}` consumed by `bar`; `cmpVer`/`pluginVersion`/`stampVersion` used consistently in T8/T9; `missing(e)` defined T4, used T4 render + T4/T5 brief; `KNOWN_LANES`/`LANE_RANK`/`laneRank` defined T2, used T5/T6. `add-epic` flags match the `/pm:epic` command file.

**Known cross-task note:** Task 2 temporarily wires `progress: storyProgress(...)`; Task 3 replaces `storyProgress` with `epicProgress` and swaps both call sites. Implementer must do Task 3 right after Task 2 (the suite stays green at each task boundary).
