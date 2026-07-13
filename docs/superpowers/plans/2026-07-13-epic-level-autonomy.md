# Epic-Level Autonomy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let a pm-managed epic run through phase transitions and destructive actions without the user present for each one, while preserving genuine safety stops — via a per-epic `autonomy` contract, a standalone epic-id-parameterized preflight risk-scan, a five-criteria execution-time decision rule, and an end-of-epic report.

**Architecture:** All new state lives in `.conductor/state.json` as an optional `autonomy` object per epic (default `level: "off"`, unchanged behavior). A new `set-autonomy` CLI verb (engine, deterministic, tested) writes it. The risk-scan itself and the execution-time decision rule are agent behavior driven by instructions injected into `CLAUDE.md` (the `rulesBlock()` function) and documented in the `conductor` skill — consistent with pm's law that the engine only emits instructions, never acts on Jira/tests/git itself.

**Tech Stack:** Node 18+ built-ins only (`node:fs`, `node:path`, `node:child_process`, `node:url`) — zero dependencies, per `plugins/pm/scripts/conductor.mjs`'s existing constraint. Tests via `node --test`.

## Global Constraints

- `plugins/pm/scripts/conductor.mjs` is Node 18+ built-ins only — never add an npm dependency.
- All tests pass via `node --test plugins/pm/scripts/conductor.test.mjs` before any commit — no exceptions.
- Every new CLI subcommand needs a matching command doc under `plugins/pm/commands/` and coverage in `conductor.test.mjs`.
- The engine never opens a network connection or calls an external system (Jira, git, tests) — it only emits instructions for the interactive agent to act on.
- A feature release bumps `plugins/pm/.claude-plugin/plugin.json` `version`, adds a `CHANGELOG.md` entry, and — only if `state.json` schema changes in a way existing data must be *transformed* to remain valid — adds a `MIGRATIONS` entry (additive, idempotent, backward-compatible).
- Design source: `docs/superpowers/specs/2026-07-13-epic-level-autonomy-design.md`. Read it before Task 1 if anything below is ambiguous — it is the source of truth for *why*, this plan is the source of truth for *how*.

---

## Schema decision: no MIGRATIONS entry needed

The new `autonomy` field is optional and purely additive: any epic without it behaves exactly as
today (`level: "off"`, computed via a default at read-time, never written unless
`set-autonomy` is called). Unlike the 0.3.0 lane-stamp or 0.5.0 link-repair migrations — both of
which had to *transform* existing malformed/missing data — no existing `state.json` needs
correction here. A state file written by an older engine loads fine under the new one (missing
field defaults cleanly); a state file written by the new engine loads fine under an older one
(unknown JSON fields are ignored). Per the Global Constraints rule, a migration is only required
when this doesn't hold — it holds here, so `MIGRATIONS` is untouched by this plan.

---

### Task 1: Preflight risk-scan primitive — skill content + second dogfood validation

This is the "standalone primitive" from the design (section 2). It is agent behavior, not
engine code — there is no deterministic function that can read prose and reason about risk. Its
implementation IS the documented process in the `conductor` skill, and its "test" is running it
for real against a second target (the design was already dogfooded once against
`openspec/changes/archive/2026-06-25-add-hierarchy-and-tracker-awareness/`; this task proves it
generalizes rather than being a one-off lucky result).

**Files:**
- Modify: `plugins/pm/skills/conductor/SKILL.md`

**Interfaces:**
- Produces: a documented process any future agent invocation follows — "given an epic id, read
  its lane-appropriate source in full, and return destructive-risk points + genuine unknowns as
  one short batch of questions." Task 3 (rules block) and Task 6 (tracker addendum) both
  reference this section by name, so the heading text below must stay exactly
  `## Epic-level autonomy — the preflight scan`.

- [ ] **Step 1: Add the preflight-scan section to the conductor skill**

Open `plugins/pm/skills/conductor/SKILL.md` and insert this new section immediately before the
final `## state.json reference` section (i.e. after the "## Importing an existing roadmap"
section, so it reads as part of the operational guidance rather than the reference appendix):

```markdown
## Epic-level autonomy — the preflight scan

An epic can be granted broad execution trust so it runs through phase transitions and
destructive actions without a human present for each one — but ONLY after a preflight scan, and
autonomy never removes a genuine safety stop. This section defines the scan; the decision rule
and reporting obligations that consume its output are in the rules block re-injected into
CLAUDE.md (see `/pm:epic` → `set-autonomy`).

**When:** before setting any epic's `autonomy.level` to `"autonomous"` (see `set-autonomy` below).

**How to scan an epic (`epicId`):**

1. Read that epic's FULL source, not a summary — whichever is its lane's real progress source:
   - `openspec` lane: `openspec/changes/<epicId>/{proposal,design,tasks}.md` and everything under
     its `specs/` directory.
   - `superpowers` lane: the file at the epic's `planPath`.
   - `claude-code` lane: the epic's inline `stories[]` in `.conductor/state.json`.
   - `external`/tracker-linked: see the tracker-specific addendum below — pull the tracker issue
     first, it IS the source.
2. Reason over the WHOLE document — do not keyword-grep for "DROP"/"migration"/"rm". A shallow
   scan is worse than no scan: it creates false confidence and lets a real risk slip through
   silently. Full read is the only approach approved for this primitive (see the design doc's
   "Approaches considered" table for why keyword-triggered scanning was rejected).
3. Produce exactly two sections:
   - **Destructive-risk points** — anything that changes/deletes/migrates existing data or state
     in a way that could be hard to undo. For each: what it is, why it's risky, and whether a
     backup/restore path is obvious from the plan or not.
   - **Genuine unknowns** — real ambiguities or missing decisions that should NOT just be
     guessed on — things needing explicit human approval or clarification before this epic could
     run start-to-finish unattended.
4. Keep it SHORT and high-signal. If there is nothing destructive, say so plainly. If there is
   no genuine unknown, say so plainly. Padding the output with non-issues defeats the entire
   point — it is exactly what turns autonomous execution into a wall of blockers.
5. Present the findings as ONE batch of questions to the user, before execution starts. Record
   the answers with `set-autonomy <epicId> --preauthorize "<action>:<reason>"` (repeatable, one
   per approved item) and `--context "<note>"` (repeatable, one per piece of background supplied)
   — then, only once recorded, `set-autonomy <epicId> --level autonomous`.

This same read-and-scan process is the one reused, unchanged, by any future work that needs to
scan several epics at once (e.g. a parent epic's children) — it takes one epic id at a time
regardless of caller.
```

- [ ] **Step 2: Dogfood the scan a second time, against a different real target, to confirm it generalizes**

Run (foreground, so you see the result before continuing):

```
Use the Agent tool (general-purpose, run_in_background: false) with this prompt:

"You are testing the epic preflight risk-scan process documented in
plugins/pm/skills/conductor/SKILL.md under 'Epic-level autonomy — the preflight scan'. Read that
section first. Then apply it to this real target, exactly as documented (full read, two
sections, short and high-signal, no padding):

openspec/changes/archive/<pick a second archived change directory under
openspec/changes/archive/ that is NOT 2026-06-25-add-hierarchy-and-tracker-awareness — list the
directory first to find one>

Read its proposal.md, design.md, tasks.md, and anything under specs/. Then return your
destructive-risk-points and genuine-unknowns findings as your final message — that IS the
deliverable."
```

Expected: a short (under ~400 words), high-signal result with the same two-section shape as the
first dogfood run in the design spec. If the result pads with non-issues, or misses an obvious
destructive point present in the target docs, the skill text from Step 1 needs sharpening before
moving on — do not proceed to Task 2 until this run's output is judged genuinely useful (show it
to the user and get their read, since "useful" here is a human judgment call, not a `node --test`
assertion).

- [ ] **Step 3: Commit**

```bash
git add plugins/pm/skills/conductor/SKILL.md
git commit -m "docs(pm): document the epic preflight risk-scan process in the conductor skill"
```

---

### Task 2: `autonomy` state schema + `getAutonomy()` default helper

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs:51-52` (constants) and near `plugins/pm/scripts/conductor.mjs:310` (`validLink` helper — add `getAutonomy` next to it, same "small pure helper" grouping)
- Test: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Produces: `KNOWN_AUTONOMY_LEVELS` (array `["off", "autonomous"]`), `DEFAULT_AUTONOMY` (frozen
  object), `getAutonomy(epic) → { level, preAuthorized, context, notifications }` — Task 3
  (`set-autonomy`), Task 4 (render/brief), and Task 3/6 (rules-block tests) all import/call this
  by that exact name and shape.

- [ ] **Step 1: Write the failing test**

Add to `plugins/pm/scripts/conductor.test.mjs` (near the other small-helper tests, e.g. right
after the `expectFail` definition around line 196 — as a new test, not touching the helper
itself):

```js
test("epic with no autonomy field defaults to level off via render/brief (no crash, no marker)", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  run(["add-epic", "--id", "a", "--lane", "claude-code", "--status", "active"], { cwd });
  const md = projectMd(cwd);
  assert.match(md, /`a`/);
  assert.doesNotMatch(md, /🤖/);              // no autonomy marker for a plain epic
  const brief = parseBrief(cwd);
  assert.doesNotMatch(brief, /🤖/);
});
```

- [ ] **Step 2: Run test to verify it fails (or rather, passes vacuously — confirm it runs clean before any code exists, as a baseline)**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS (this test doesn't require new code yet — it's a baseline-behavior guard that
must stay true after Tasks 2-4 land; run it now to confirm the assertions are well-formed against
current `render`/`brief` output, i.e. no marker exists to accidentally match).

- [ ] **Step 3: Add `KNOWN_AUTONOMY_LEVELS`, `DEFAULT_AUTONOMY`, and `getAutonomy()`**

In `plugins/pm/scripts/conductor.mjs`, find:

```js
const KNOWN_LANES = ["openspec", "superpowers", "claude-code", "decision", "external"];
const KNOWN_STATUSES = ["untriaged", "queued", "active", "paused", "planned", "archived"];
```

Replace with:

```js
const KNOWN_LANES = ["openspec", "superpowers", "claude-code", "decision", "external"];
const KNOWN_STATUSES = ["untriaged", "queued", "active", "paused", "planned", "archived"];
const KNOWN_AUTONOMY_LEVELS = ["off", "autonomous"];
```

Then find the `validLink` helper (around line 310):

```js
function validLink(l) {
```

Insert immediately before it:

```js
// `autonomy` is optional per epic — absent means "off", today's behavior, unchanged.
// getAutonomy() is the ONLY place that should read epic.autonomy directly; everywhere
// else (render, brief, set-autonomy) calls this so a missing field never needs a
// migration to backfill — it defaults cleanly at read-time.
const DEFAULT_AUTONOMY = Object.freeze({ level: "off", preAuthorized: [], context: [], notifications: [] });
function getAutonomy(epic) {
  const a = epic.autonomy;
  if (!a) return DEFAULT_AUTONOMY;
  return {
    level: a.level || "off",
    preAuthorized: Array.isArray(a.preAuthorized) ? a.preAuthorized : [],
    context: Array.isArray(a.context) ? a.context : [],
    notifications: Array.isArray(a.notifications) ? a.notifications : [],
  };
}

```

- [ ] **Step 4: Run tests to verify they still pass**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS, all tests including the new one from Step 1.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): add autonomy schema constants and getAutonomy() default helper"
```

---

### Task 3: `set-autonomy` CLI verb

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`parseFlags`, new `setAutonomy()` function, dispatch table + usage string)
- Test: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Consumes: `getAutonomy(epic)`, `KNOWN_AUTONOMY_LEVELS` (Task 2); `loadState()`, `saveState()`,
  `render()`, `parseFlags()` (existing).
- Produces: CLI verb `set-autonomy <id> [--level off|autonomous] [--preauthorize
  "<action>:<reason>"] [--context "<note>"] [--notify "<what>"]`, all repeatable except `--level`.
  Task 4 (render/brief marker) and Task 6 (tracker addendum test) both create epics via this verb
  in their tests.

- [ ] **Step 1: Write the failing tests**

Add to `plugins/pm/scripts/conductor.test.mjs`, near the `set-active`/`update-epic` tests (after
line 662, `"add-epic --status active sets the .active pointer too"`):

```js
// ──────────────── epic-level autonomy: set-autonomy ────────────────

test("set-autonomy sets level and rejects an unknown level", () => {
  const cwd = tmpRepo(); run(["init"], { cwd });
  run(["add-epic", "--id", "a", "--lane", "claude-code"], { cwd });
  run(["set-autonomy", "a", "--level", "autonomous"], { cwd });
  assert.equal(readState(cwd).epics.find(e => e.id === "a").autonomy.level, "autonomous");
  assert.ok(expectFail(() => run(["set-autonomy", "a", "--level", "bogus"], { cwd })), "bad level rejected");
});

test("set-autonomy records preauthorize/context/notify entries, repeatable and merged across calls", () => {
  const cwd = tmpRepo(); run(["init"], { cwd });
  run(["add-epic", "--id", "a", "--lane", "claude-code"], { cwd });
  run(["set-autonomy", "a",
    "--preauthorize", "drop-scratch-table:reviewed, safe to drop",
    "--preauthorize", "rename-field:no external readers",
    "--context", "staging DB only, no prod access",
  ], { cwd });
  let a = readState(cwd).epics.find(e => e.id === "a").autonomy;
  assert.equal(a.preAuthorized.length, 2);
  assert.deepEqual(
    { action: a.preAuthorized[0].action, reason: a.preAuthorized[0].reason },
    { action: "drop-scratch-table", reason: "reviewed, safe to drop" },
  );
  assert.ok(a.preAuthorized[0].grantedAt);            // timestamp present
  assert.deepEqual(a.context, ["staging DB only, no prod access"]);

  // a second call APPENDS, does not clobber
  run(["set-autonomy", "a", "--notify", "ran a schema migration"], { cwd });
  a = readState(cwd).epics.find(e => e.id === "a").autonomy;
  assert.equal(a.preAuthorized.length, 2);            // unchanged by the second call
  assert.equal(a.notifications.length, 1);
  assert.equal(a.notifications[0].what, "ran a schema migration");
  assert.ok(a.notifications[0].when);
});

test("set-autonomy on an unknown id exits non-zero and writes nothing", () => {
  const cwd = tmpRepo(); run(["init"], { cwd });
  const before = fs.readFileSync(path.join(cwd, ".conductor", "state.json"), "utf8");
  assert.ok(expectFail(() => run(["set-autonomy", "ghost", "--level", "autonomous"], { cwd })));
  assert.equal(fs.readFileSync(path.join(cwd, ".conductor", "state.json"), "utf8"), before);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL — `set-autonomy` is not a recognized subcommand yet (usage error / non-zero exit
where a clean run was expected).

- [ ] **Step 3: Extend `parseFlags` to treat the new flags as repeatable**

Find in `plugins/pm/scripts/conductor.mjs`:

```js
function parseFlags(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const k = a.slice(2);
    const v = (argv[i + 1] !== undefined && !argv[i + 1].startsWith("--")) ? argv[++i] : true;
    if (k === "link") (o.link || (o.link = [])).push(v);
    else if (k === "intent") (o.intent || (o.intent = [])).push(v);
    else o[k] = v;
  }
  return o;
}
```

Replace with:

```js
// Flags that accumulate into an array across repeated `--flag value` occurrences,
// shared by add-epic/add-many (--link), set-tracker (--intent), and set-autonomy
// (--preauthorize/--context/--notify).
const REPEATABLE_FLAGS = ["link", "intent", "preauthorize", "context", "notify"];
function parseFlags(argv) {
  const o = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (!a.startsWith("--")) continue;
    const k = a.slice(2);
    const v = (argv[i + 1] !== undefined && !argv[i + 1].startsWith("--")) ? argv[++i] : true;
    if (REPEATABLE_FLAGS.includes(k)) (o[k] || (o[k] = [])).push(v);
    else o[k] = v;
  }
  return o;
}
```

- [ ] **Step 4: Add `setAutonomy()`**

Find `updateEpic()`'s closing brace and the `// ---------- tracker ----------` comment that
follows it (around line 990-992):

```js
  saveState(state);
  render();
  process.stderr.write(`conductor: updated '${id}'\n`);
}

// ---------- tracker ----------
```

Insert a new section between them:

```js
  saveState(state);
  render();
  process.stderr.write(`conductor: updated '${id}'\n`);
}

// ---------- autonomy ----------

/** `set-autonomy <id> [--level off|autonomous] [--preauthorize "<action>:<reason>"]
 *  [--context "<note>"] [--notify "<what>"]` — writes/merges an epic's `autonomy` block.
 *  Every flag is additive (repeated calls APPEND to preAuthorized/context/notifications,
 *  never clobber) except --level, which replaces. Pure local state write — no external
 *  calls, consistent with the engine's instruction-layer law. */
function setAutonomy() {
  if (!isInitialized()) { process.stderr.write("conductor: run /pm:init first\n"); process.exit(1); }
  const argv = process.argv.slice(3);
  const id = argv[0] && !argv[0].startsWith("--") ? argv[0] : undefined;
  if (!id) {
    process.stderr.write(
      "usage: conductor.mjs set-autonomy <id> [--level off|autonomous] " +
      "[--preauthorize \"<action>:<reason>\"] [--context \"<note>\"] [--notify \"<what>\"]\n");
    process.exit(1);
  }
  const f = parseFlags(argv.slice(1));
  const state = loadState();
  const epic = state.epics.find(e => e.id === id);
  if (!epic) { process.stderr.write(`conductor: epic '${id}' not found\n`); process.exit(1); }

  const level = typeof f.level === "string" ? f.level : undefined;
  if (level !== undefined && !KNOWN_AUTONOMY_LEVELS.includes(level)) {
    process.stderr.write(`conductor: --level must be one of ${KNOWN_AUTONOMY_LEVELS.join("|")}\n`);
    process.exit(1);
  }

  const a = { ...getAutonomy(epic) };
  if (level !== undefined) a.level = level;

  for (const s of (f.preauthorize || [])) {
    if (typeof s !== "string") continue;
    const i = s.indexOf(":");
    const action = i === -1 ? s.trim() : s.slice(0, i).trim();
    const reason = i === -1 ? undefined : s.slice(i + 1).trim();
    const entry = { action, grantedAt: new Date().toISOString() };
    if (reason) entry.reason = reason;
    a.preAuthorized = [...a.preAuthorized, entry];
  }
  for (const c of (f.context || [])) {
    if (typeof c === "string") a.context = [...a.context, c];
  }
  for (const n of (f.notify || [])) {
    if (typeof n === "string") a.notifications = [...a.notifications, { what: n, when: new Date().toISOString() }];
  }

  epic.autonomy = a;
  saveState(state);
  render();
  process.stderr.write(`conductor: autonomy for '${id}' is now level=${a.level}\n`);
}

// ---------- tracker ----------
```

- [ ] **Step 5: Wire the dispatch table and usage string**

Find:

```js
const cmd = process.argv[2];
({
  init,
  render,
  brief,
  snapshot,
  "commit-nudge": commitNudge,
  sync: () => sync(false),
  "log-detour": logDetour,
  "add-epic": addEpic,
  "add-many": addMany,
  "update-epic": updateEpic,
  "set-active": setActive,
  "clear-active": clearActive,
  "set-tracker": setTracker,
  upgrade,
  changelog,
  rules: () => process.stdout.write(rulesBlock(currentTracker())),
  "write-rules": writeRules,
}[cmd] || (() => {
  process.stderr.write("usage: conductor.mjs init|render|brief|snapshot|commit-nudge|sync|log-detour|add-epic|add-many|update-epic|set-active|clear-active|set-tracker|upgrade|changelog|rules|write-rules\n");
  process.exit(1);
```

Replace with:

```js
const cmd = process.argv[2];
({
  init,
  render,
  brief,
  snapshot,
  "commit-nudge": commitNudge,
  sync: () => sync(false),
  "log-detour": logDetour,
  "add-epic": addEpic,
  "add-many": addMany,
  "update-epic": updateEpic,
  "set-active": setActive,
  "clear-active": clearActive,
  "set-tracker": setTracker,
  "set-autonomy": setAutonomy,
  upgrade,
  changelog,
  rules: () => process.stdout.write(rulesBlock(currentTracker())),
  "write-rules": writeRules,
}[cmd] || (() => {
  process.stderr.write("usage: conductor.mjs init|render|brief|snapshot|commit-nudge|sync|log-detour|add-epic|add-many|update-epic|set-active|clear-active|set-tracker|set-autonomy|upgrade|changelog|rules|write-rules\n");
  process.exit(1);
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS, all tests including the three from Step 1.

- [ ] **Step 7: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): add set-autonomy CLI verb for per-epic autonomy contracts"
```

---

### Task 4: Surface autonomy status in `render()` and `buildBrief()`

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`render()` epic row, `buildBrief()` NOW line)
- Test: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Consumes: `getAutonomy(epic)` (Task 2).
- Produces: a `🤖` marker in `PROJECT.md`'s epic table (Status column) and in the brief's `NOW:`
  line, ONLY when `autonomy.level === "autonomous"`. Task 2's baseline test (no marker for a
  plain epic) must keep passing.

- [ ] **Step 1: Write the failing tests**

Add to `plugins/pm/scripts/conductor.test.mjs`, immediately after the three `set-autonomy` tests
from Task 3:

```js
test("render marks an autonomous epic with 🤖 in its Status cell; a plain epic gets no marker", () => {
  const cwd = tmpRepo(); run(["init"], { cwd });
  run(["add-epic", "--id", "auto", "--lane", "claude-code"], { cwd });
  run(["add-epic", "--id", "plain", "--lane", "claude-code"], { cwd });
  run(["set-autonomy", "auto", "--level", "autonomous"], { cwd });
  const md = projectMd(cwd);
  const autoLine = md.split("\n").find(l => l.includes("`auto`"));
  const plainLine = md.split("\n").find(l => l.includes("`plain`"));
  assert.match(autoLine, /🤖/);
  assert.doesNotMatch(plainLine, /🤖/);
});

test("brief NOW line shows 🤖 autonomous only when the active epic is autonomous", () => {
  const cwd = tmpRepo(); run(["init"], { cwd });
  run(["add-epic", "--id", "a", "--lane", "claude-code", "--status", "active"], { cwd });
  assert.doesNotMatch(parseBrief(cwd), /🤖/);
  run(["set-autonomy", "a", "--level", "autonomous"], { cwd });
  assert.match(parseBrief(cwd), /NOW: `a`.*🤖 autonomous/);
});
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL — no `🤖` is emitted anywhere yet.

- [ ] **Step 3: Add the marker in `render()`**

Find (around line 585-596):

```js
  const epicRow = (e, depth) => {
    const links = (e.links || []).filter(validLink).map(l => `${l.type}→${l.epic}`).join("; ") || "-";
    const miss = missing(e) ? " ⚠ no change on disk" : "";
    const indent = depth > 0 ? "└─ ".repeat(depth) : "";
    const kids = childrenOf(e.id);
    let progress = bar(e.progress);
    if (kids.length) {
      const archived = kids.filter(k => k.status === "archived").length;
      const rollup = `${archived}/${kids.length} children archived`;
      progress = progress === "—" ? rollup : `${rollup} · ${progress}`;
    }
    md.push(`| ${e.priority} | ${indent}\`${e.id}\` | ${e.lane} | ${e.role} | ${e.status}${e.reconcileNeeded ? " ⚠" : ""}${miss} | ${progress} | ${links} |`);
  };
```

Replace with:

```js
  const epicRow = (e, depth) => {
    const links = (e.links || []).filter(validLink).map(l => `${l.type}→${l.epic}`).join("; ") || "-";
    const miss = missing(e) ? " ⚠ no change on disk" : "";
    const indent = depth > 0 ? "└─ ".repeat(depth) : "";
    const kids = childrenOf(e.id);
    let progress = bar(e.progress);
    if (kids.length) {
      const archived = kids.filter(k => k.status === "archived").length;
      const rollup = `${archived}/${kids.length} children archived`;
      progress = progress === "—" ? rollup : `${rollup} · ${progress}`;
    }
    const autonomous = getAutonomy(e).level === "autonomous" ? " 🤖" : "";
    md.push(`| ${e.priority} | ${indent}\`${e.id}\` | ${e.lane} | ${e.role} | ${e.status}${e.reconcileNeeded ? " ⚠" : ""}${miss}${autonomous} | ${progress} | ${links} |`);
  };
```

- [ ] **Step 4: Add the marker in `buildBrief()`**

Find (around line 449-459):

```js
  const activeEpic = state.active ? byId[state.active] : null;
  const active = activeEpic && activeEpic.status !== "archived" ? activeEpic : null;
  if (active) {
    L.push(`NOW: \`${active.id}\` (${active.lane}, ${active.role}, ${active.priority}) — ${bar(active.progress)}`);
    if (active.reconcileNeeded)
      L.push(`  ⚠ RECONCILE PENDING: re-validate this proposal before continuing (a detour touched shared code).`);
```

Replace with:

```js
  const activeEpic = state.active ? byId[state.active] : null;
  const active = activeEpic && activeEpic.status !== "archived" ? activeEpic : null;
  if (active) {
    const autonomous = getAutonomy(active).level === "autonomous" ? ", 🤖 autonomous" : "";
    L.push(`NOW: \`${active.id}\` (${active.lane}, ${active.role}, ${active.priority}${autonomous}) — ${bar(active.progress)}`);
    if (active.reconcileNeeded)
      L.push(`  ⚠ RECONCILE PENDING: re-validate this proposal before continuing (a detour touched shared code).`);
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS, all tests including the two from Step 1, and the Task 2 baseline test still
green.

- [ ] **Step 6: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): surface autonomous-epic status in PROJECT.md and the session brief"
```

---

### Task 5: Core "Epic-level autonomy" rules-block section (unconditional)

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`rulesBlock()`)
- Test: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Consumes: nothing new (pure string content).
- Produces: a `## Epic-level autonomy` section always present in the rules block, unconditional
  (not gated by a tracker), mirroring the design's five-criteria decision rule. Task 6 appends a
  further addendum specifically inside the existing tracker-conditional block, not this one.

- [ ] **Step 1: Write the failing test**

Add to `plugins/pm/scripts/conductor.test.mjs`, right after the `"rules block is lane-agnostic,
not openspec-only"` test (line 398):

```js
test("rules block always includes the epic-level autonomy section, with the five-criteria decision rule", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const out = run(["rules"], { cwd });
  assert.match(out, /## Epic-level autonomy/);
  assert.match(out, /set-autonomy/);
  assert.match(out, /No backup\/restore path exists\? → STOP/);
  assert.match(out, /Destructive but restorable.*→ WARN/);
  assert.match(out, /irreversible EXTERNAL side/i);   // scope boundary called out explicitly
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL — no such section exists yet.

- [ ] **Step 3: Add the section to `rulesBlock()`**

Find the end of the main numbered list, right before the tracker conditional (around line
374-380):

```js
    "6. **Roadmap as backlog** — work you intend to do but haven't proposed yet can be",
    "   registered now with `/pm:epic add … --status planned` (any lane). Planned epics show",
    "   as ordered backlog in `PROJECT.md` and a `planned: N` count in the briefing, without a",
    "   \"no change on disk\" warning; `/pm:sync` flips an openspec planned epic to untriaged once",
    "   its change is proposed. Have a roadmap doc? Read it in-session and load each item this way.",
  ];
  if (tracker && tracker.system) {
```

Replace with:

```js
    "6. **Roadmap as backlog** — work you intend to do but haven't proposed yet can be",
    "   registered now with `/pm:epic add … --status planned` (any lane). Planned epics show",
    "   as ordered backlog in `PROJECT.md` and a `planned: N` count in the briefing, without a",
    "   \"no change on disk\" warning; `/pm:sync` flips an openspec planned epic to untriaged once",
    "   its change is proposed. Have a roadmap doc? Read it in-session and load each item this way.",
    "",
    "## Epic-level autonomy",
    "",
    "An epic's `autonomy` block (`.conductor/state.json`) can grant it broad execution trust —",
    "`level: \"off\"` by default (today's behavior, unchanged). Setting `level: \"autonomous\"`",
    "removes the need to ask before each phase transition, but NEVER removes a genuine safety stop.",
    "This is development-time only — it never covers actions with irreversible EXTERNAL side",
    "effects (sending email/Slack, deploying to production, third-party API calls, pushing to a",
    "shared branch); those are out of scope regardless of autonomy level.",
    "",
    "1. **Preflight before flipping the switch** — see the `conductor` skill's",
    "   \"Epic-level autonomy — the preflight scan\" section for the full process. In short: read",
    "   the epic's full source, produce a short batch of destructive-risk-points +",
    "   genuine-unknowns questions, get the user's answers, THEN record them:",
    "   `set-autonomy <id> --preauthorize \"<action>:<reason>\"` / `--context \"<note>\"`, and only",
    "   then `set-autonomy <id> --level autonomous`.",
    "2. **Execution-time decision rule** — check every destructive action against these, in",
    "   order, before treating it as a stop:",
    "   a. Already pre-authorized in the preflight? → proceed, record via `--notify`.",
    "   b. No backup/restore path exists? → STOP regardless of autonomy level.",
    "   c. Destructive but restorable (backed up first)? → WARN — log it, proceed.",
    "   d. No context to act on? → STOP — a real gap, not a false stall.",
    "   e. Consequential and not yet notified? → record it for the end-of-epic report.",
    "3. **End-of-epic report** — on completion, report what was asked, what was done, decisions",
    "   made in the user's absence (the WARN-class log), and an explicit \"are you OK with",
    "   these?\" checkpoint, THEN run tests. Leave room to iterate — including rewriting code —",
    "   if the user is not satisfied.",
  ];
  if (tracker && tracker.system) {
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS, all tests including the one from Step 1.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): inject the epic-level autonomy contract into the CLAUDE.md rules block"
```

---

### Task 6: Tracker-linked autonomy addendum (Jira etc.)

**Files:**
- Modify: `plugins/pm/scripts/conductor.mjs` (`rulesBlock()`, inside the existing `if (tracker &&
  tracker.system)` block)
- Test: `plugins/pm/scripts/conductor.test.mjs`

**Interfaces:**
- Consumes: nothing new.
- Produces: additional lines inside the tracker-conditional section covering lane-aware source
  reading, comment-mirroring, and mid-run drift — present ONLY when a tracker is configured
  (matching the existing pattern where the whole tracker section is conditional).

- [ ] **Step 1: Write the failing test**

Add to `plugins/pm/scripts/conductor.test.mjs`, right after the `"rules block gains an External
tracker sync section only when a tracker is configured"` test (line 939):

```js
test("tracker-linked autonomy addendum appears only when a tracker is configured", () => {
  const cwd = tmpRepo();
  run(["init"], { cwd });
  const noTracker = run(["rules"], { cwd });
  assert.doesNotMatch(noTracker, /Epic-level autonomy on tracker-linked epics/);

  run(["set-tracker", "--system", "jira", "--project", "JOB"], { cwd });
  const withTracker = run(["rules"], { cwd });
  assert.match(withTracker, /Epic-level autonomy on tracker-linked epics/);
  assert.match(withTracker, /mid-run drift/i);
  assert.match(withTracker, /non-authoritative/i);
});
```

- [ ] **Step 2: Run test to verify it fails**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: FAIL — no such addendum exists yet.

- [ ] **Step 3: Add the addendum inside the tracker conditional**

Find the end of the tracker conditional block (around line 390-398 — this is inside the existing
`const sys = tracker.system;` scope, so the `${sys}` template lines below are genuine template
strings, backtick-delimited, not literal text):

```js
      `- A real epic has no \`externalId\` → create the ${sys} issue, then record its key with`,
      "  `/pm:epic` → `update-epic <id> --external-id <KEY> --external-url <url>`.",
      "- An epic moves to a status with a `statusIntent` (e.g. active/archived) → transition the",
      "  linked issue toward that SEMANTIC target, resolving the real workflow transition yourself.",
      `- A parent epic → create it as a ${sys} epic and link its children.`,
      "The SessionStart brief lists epics not yet mirrored under `TRACKER SYNC`. Status-transition",
      "sync is your responsibility on every status change (the brief does not fabricate it).",
    );
  }
  lines.push(RULES_END, "");
```

Replace it with the same lines plus a new addendum inserted before the closing `);`:

```js
      `- A real epic has no \`externalId\` → create the ${sys} issue, then record its key with`,
      "  `/pm:epic` → `update-epic <id> --external-id <KEY> --external-url <url>`.",
      "- An epic moves to a status with a `statusIntent` (e.g. active/archived) → transition the",
      "  linked issue toward that SEMANTIC target, resolving the real workflow transition yourself.",
      `- A parent epic → create it as a ${sys} epic and link its children.`,
      "The SessionStart brief lists epics not yet mirrored under `TRACKER SYNC`. Status-transition",
      "sync is your responsibility on every status change (the brief does not fabricate it).",
      "",
      "**Epic-level autonomy on tracker-linked epics:** before running the preflight scan on a",
      `tracker-linked epic, pull the ${sys} issue + its child stories/subtasks with your own`,
      "tracker tools (the same ones you use for status sync) — that IS its source, not a local",
      "file alone. Mirror the preflight Q&A as a comment on the issue for visibility — this is a",
      "non-authoritative echo, `.conductor/state.json` stays the sole source of truth. If the",
      "tracker issue changes materially after the preflight snapshot, treat that as decision-rule",
      "item (d) — mid-run drift is a new genuine unknown, not something autonomy silently absorbs.",
    );
  }
  lines.push(RULES_END, "");
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS, all tests including the one from Step 1.

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/scripts/conductor.mjs plugins/pm/scripts/conductor.test.mjs
git commit -m "feat(pm): add tracker-linked autonomy addendum (lane-aware read, comment mirror, drift stop)"
```

---

### Task 7: Command doc, CHANGELOG, and version bump

**Files:**
- Modify: `plugins/pm/commands/epic.md` (new section, mirroring the existing `set-active`/`clear-active` section)
- Modify: `plugins/pm/CHANGELOG.md`
- Modify: `plugins/pm/.claude-plugin/plugin.json`

**Interfaces:**
- Consumes: nothing (documentation + metadata only).
- Produces: user-facing docs for `set-autonomy`; a versioned, changelog-documented release.

- [ ] **Step 1: Add the `set-autonomy` section to `commands/epic.md`**

Read `plugins/pm/commands/epic.md` in full first (needed to match its existing heading style
around the `## Set the active epic — \`set-active\` / \`clear-active\`` section at line 78, and
to append after it rather than guess formatting). Insert a new section immediately after that
one, following the same structure (a short intro line, a fenced `bash` usage block, then a
one-paragraph explanation):

```markdown
## Grant epic-level autonomy — `set-autonomy`

Before an epic can run unattended through phase transitions and destructive actions, it needs a
preflight scan (see the `conductor` skill's "Epic-level autonomy — the preflight scan" section)
and the user's recorded answers.

```bash
node "${CLAUDE_PLUGIN_ROOT}/scripts/conductor.mjs" set-autonomy <id> \
  --preauthorize "drop-scratch-table:reviewed, safe to drop" \
  --context "staging DB only, no prod access" \
  --level autonomous
```

`--preauthorize`/`--context`/`--notify` are repeatable and additive — re-running `set-autonomy`
APPENDS, it never clobbers prior entries. `--level` replaces (default `"off"` — today's
behavior, unchanged). `PROJECT.md` and the session brief mark an autonomous epic with 🤖.
```

- [ ] **Step 2: Add a CHANGELOG entry**

Read `plugins/pm/CHANGELOG.md`'s existing `[0.7.0]` entry first (for exact heading/list style),
then insert a new section immediately below the `---` separator and above `## [0.7.0]`:

```markdown
## [0.8.0] — 2026-07-13

### Added

- **`set-autonomy <id>` — per-epic autonomy contract.** An epic can be granted broad execution
  trust (`autonomy.level: "autonomous"`, default `"off"` — unchanged behavior) so it runs through
  phase transitions without stopping for permission each time. Autonomy is granted only after a
  preflight risk-scan (documented in the `conductor` skill) records the user's pre-authorized
  actions and supplied context via `--preauthorize`/`--context` (repeatable, additive). A
  five-criteria execution-time decision rule (injected into the CLAUDE.md rules block) still
  hard-stops for anything with no backup/restore path or no context to act on — autonomy never
  overrides a genuine safety gate, only removes false ones. `PROJECT.md` and the session brief
  mark an autonomous epic with 🤖. Tracker-linked epics (Jira etc.) get an addendum covering
  lane-aware source reading, non-authoritative comment-mirroring of approvals, and mid-run drift
  as its own stop condition.
- Development-time scope only — this does not cover actions with irreversible EXTERNAL side
  effects (sending email/Slack, deploying to production, third-party API calls, pushing to a
  shared branch); those remain out of scope regardless of autonomy level.

---

```

- [ ] **Step 3: Bump the plugin version**

In `plugins/pm/.claude-plugin/plugin.json`, change:

```json
  "version": "0.7.0",
```

to:

```json
  "version": "0.8.0",
```

- [ ] **Step 4: Run the full test suite one last time**

Run: `node --test plugins/pm/scripts/conductor.test.mjs`
Expected: PASS — every test in the file, not just the ones added in this plan (per the repo's
"whole tree must be green" rule).

- [ ] **Step 5: Commit**

```bash
git add plugins/pm/commands/epic.md plugins/pm/CHANGELOG.md plugins/pm/.claude-plugin/plugin.json
git commit -m "docs(pm): document set-autonomy, changelog 0.8.0, bump plugin version"
```

---

## After implementation: manual validation (not a coded task)

Per the design's Validation Plan step 1, once this plan is fully implemented, prove the whole
contract end-to-end on ONE real epic — pick one of the five `planned` Comet-incorporation epics
in `.conductor/state.json`, propose it via OpenSpec (so it has a real `tasks.md`/spec to scan),
then run: preflight scan → `set-autonomy --preauthorize ... --level autonomous` → autonomous
execution → end-of-epic report. This is a usage/judgment activity, not a file-changing task, so
it isn't broken into plan steps here — do it as a follow-up once this plan's `node --test` suite
is green and the commits above have landed.
