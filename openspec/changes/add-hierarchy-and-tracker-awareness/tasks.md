## 1. Epic hierarchy (precondition slice — ship first, demoable)

- [ ] 1.1 RED: add test asserting a v0.4.1-shaped `state.json` (no `parent`/`tracker`/external
      fields) loads intact — the backward-compatibility baseline guarding all later schema work.
- [ ] 1.2 RED: add tests for `add-epic --parent` — valid existing parent sets `parent`; missing
      parent, self-parent, and a cycle (a→b→a) each exit non-zero and write nothing.
- [ ] 1.3 GREEN: add optional `parent` field; implement one ancestor-walk validation helper
      (existence + no-self + no-cycle) and wire it into `add-epic`. Tests 1.1–1.2 pass.
- [ ] 1.4 RED: add render tests — children indent under their parent (`└─`), families grouped and
      ordered by parent priority, parent row shows `X/Y children archived`; brief NEXT-UP annotates
      a child with its parent id; a no-hierarchy repo renders identically to before.
- [ ] 1.5 GREEN: implement hierarchical render in `render()` (index by parent, derive rollup) and
      the parent annotation in `buildBrief()`, preserving the stamp-on-content-change skip. Tests pass.
- [ ] 1.6 Document `--parent` in `commands/epic.md`. Manual demo: add a parent + two children,
      `render`, eyeball the tree + rollup in PROJECT.md.

## 2. Render robustness (independent stale-link fix)

- [ ] 2.1 RED: add a test that an epic carrying a malformed link (missing `type` or `epic`) renders
      with NO `undefined` token in PROJECT.md or the brief, and still renders the epic otherwise.
- [ ] 2.2 GREEN: make link rendering in `render()` and `buildBrief()` emit a link only when both
      `type` and `epic` are strings. Test passes.

## 3. External-tracker awareness

- [ ] 3.1 RED: add a `set-tracker` round-trip test (`--system/--instance/--project/--mechanism/
      --intent` write a `tracker` block that re-reads identically).
- [ ] 3.2 GREEN: implement the `tracker` block + `set-tracker` subcommand (pure local write).
- [ ] 3.3 RED: add tests for per-epic `externalId`/`externalUrl` persistence and `update-epic`
      write-back — sets external fields on an existing epic; reuses parent validation (cycle
      rejected); unknown id exits non-zero and writes nothing.
- [ ] 3.4 GREEN: add `externalId`/`externalUrl` fields and the `update-epic <id>` subcommand
      (`--external-id/--external-url/--parent/--status/--priority`) sharing the validation helper.
- [ ] 3.5 RED: add tests for instruction weaving — rules block gains the "External tracker sync"
      section ONLY when a tracker is configured; brief lists unmirrored real epics as create-issue
      drift; brief invents NO transition drift; with no tracker block, neither surface emits
      tracker text.
- [ ] 3.6 GREEN: implement the tracker-sync section in `rulesBlock()` and the `TRACKER SYNC` drift
      block in `buildBrief()`, both gated on `tracker` presence. Tests pass.
- [ ] 3.7 Docs: add a `/pm:tracker` command doc; add the agent-driven detection step to
      `commands/init.md` and `commands/upgrade.md` (inspect signals → confirm with user →
      `set-tracker`; upgrade detects only when no `tracker` block exists).

## 4. Bulk creation

- [ ] 4.1 RED: add `add-many` tests — parent+children (children inherit parent id), children-only
      batch, atomicity (one malformed/duplicate entry aborts the whole batch with nothing written),
      duplicate-within-batch rejected, and a valid batch persists in a single state write.
- [ ] 4.2 GREEN: implement `add-many --from <path|->` reading JSON `{parent?, epics[]}`,
      validate-all-then-write-once (native `JSON.parse`, no dependency). Tests pass.
- [ ] 4.3 Docs: document `add-many` and `--external-id` in `commands/epic.md`.

## 5. Migration + release

- [ ] 5.1 Inspect a real archived epic's old (v0.0.0-era) `links` shape so the migration normalizes
      the actual stored shape, not a guess.
- [ ] 5.2 RED: add tests that the `0.5.0` migration normalizes/drops malformed `links` and stamps
      `pmVersion` to `0.5.0`, and that a second run is a no-op (idempotent).
- [ ] 5.3 GREEN: add the `0.5.0` `MIGRATIONS` entry (normalize links). Tests pass.
- [ ] 5.4 Bump `plugins/pm/.claude-plugin/plugin.json` to `0.5.0`; add the `0.5.0` `CHANGELOG.md`
      entry (added fields/subcommands, tracker awareness, backward-compat note, upgrade steps).
- [ ] 5.5 Update `README.md` and `skills/conductor/SKILL.md` for hierarchy, tracker awareness,
      `add-many`, and `update-epic`.
- [ ] 5.6 Verification: full suite green (`node --test plugins/pm/scripts/conductor.test.mjs`);
      end-to-end manual demo (configure a tracker, `add-many` a parent+children batch, render the
      tree, confirm the brief's tracker-sync drift lists unmirrored epics). Then run the Gate-2
      implementation review against the committed diff before docs are considered final.
