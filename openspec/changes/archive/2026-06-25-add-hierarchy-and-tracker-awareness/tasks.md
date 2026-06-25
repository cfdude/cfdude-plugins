## 1. Epic hierarchy (precondition slice — ship first, demoable)

- [x] 1.1 RED: add test asserting a v0.4.1-shaped `state.json` (no `parent`/`tracker`/external
      fields) loads intact — the backward-compatibility baseline guarding all later schema work.
- [x] 1.2 RED: add tests for `add-epic --parent` — valid existing parent sets `parent`; missing
      parent, self-parent, and a cycle (a→b→a) each exit non-zero and write nothing.
- [x] 1.3 GREEN: add optional `parent` field; implement one ancestor-walk validation helper
      (existence + no-self + no-cycle) and wire it into `add-epic`. Tests 1.1–1.2 pass.
- [x] 1.4 RED: add render tests — children indent under their parent (`└─`, doubled at depth 2),
      siblings ordered by `priority→lane→id`, parent's Progress cell shows `X/Y children archived`;
      a P0 child of a P2 parent keeps its P0 slot in the brief's NEXT UP (grouping is render-only);
      brief NEXT-UP annotates a child with its parent id; a no-hierarchy repo renders identically
      to before. Update the existing exact-match row assertions to the new render output.
- [x] 1.5 GREEN: implement hierarchical render in `render()` (index by parent, depth-first walk,
      per-depth `└─ ` prefix, derive rollup into the Progress cell) WITHOUT touching `resolveEpics`'s
      sort, and add the parent annotation in `buildBrief()`, preserving the stamp-on-content-change
      skip. Tests pass.
- [x] 1.6 Document `--parent` in `commands/epic.md`. Manual demo: add a parent + two children,
      `render`, eyeball the tree + rollup in PROJECT.md.

## 2. Render robustness (independent stale-link fix)

- [x] 2.1 RED: add a test that an epic carrying a malformed link (missing `type` or `epic`) renders
      with NO `undefined` token in PROJECT.md or the brief, and still renders the epic otherwise.
- [x] 2.2 GREEN: make link rendering in `render()` and `buildBrief()` emit a link only when both
      `type` and `epic` are strings. Test passes.

## 3. External-tracker awareness

- [x] 3.1 RED: add a `set-tracker` round-trip test including a MULTI-entry `statusIntent` built
      from repeated `--intent <status>:<target>` flags (e.g. active:in-progress + paused:todo +
      archived:done) that re-reads as a 3-entry map, plus the scalar fields.
- [x] 3.2 GREEN: extend `parseFlags` to accumulate `intent` into an array (mirroring the existing
      `link` special-case), then implement the `tracker` block + `set-tracker` subcommand (split
      each `--intent` value once on `:`; pure local write). Tests pass.
- [x] 3.3 RED: add tests for per-epic `externalId`/`externalUrl` persistence and `update-epic`
      write-back — sets external fields on an existing epic; reuses parent validation (cycle
      rejected); unknown id exits non-zero and writes nothing.
- [x] 3.4 GREEN: add `externalId`/`externalUrl` fields and the `update-epic <id>` subcommand
      (`--external-id/--external-url/--parent/--status/--priority`) sharing the validation helper.
- [x] 3.5 RED: add tests for instruction weaving — rules block gains the "External tracker sync"
      section ONLY when a tracker is configured; brief lists unmirrored real epics as create-issue
      drift; brief invents NO transition drift; with no tracker block, neither surface emits
      tracker text.
- [x] 3.6 GREEN: implement the tracker-sync section in `rulesBlock()` and the `TRACKER SYNC` drift
      block in `buildBrief()`, both gated on `tracker` presence. Tests pass.
- [x] 3.7 Docs: add a `/pm:tracker` command doc; add the agent-driven detection step to
      `commands/init.md` and `commands/upgrade.md` (inspect signals → confirm with user →
      `set-tracker`; upgrade detects only when no `tracker` block exists). Detection is
      intentionally agent-side and not engine-testable — only `set-tracker`'s persisted result is
      covered by engine tests (3.1).

## 4. Bulk creation

- [x] 4.1 RED: add `add-many` tests — parent+children (children inherit parent id), children-only
      batch, atomicity (one malformed/duplicate entry aborts the whole batch with nothing written),
      duplicate-within-batch rejected, intra-batch parent cycle (x↔y) rejected, and a valid batch
      persists in a single state write.
- [x] 4.2 GREEN: implement `add-many --from <path|->` reading JSON `{parent?, epics[]}`,
      validate-all-then-write-once (native `JSON.parse`, no dependency). Tests pass.
- [x] 4.3 Docs: document `add-many` and `--external-id` in `commands/epic.md`.

## 5. Migration + release

- [x] 5.1 Confirm the recoverable historical link shape is the colon-string `type:epic[:reason]`
      form produced by `add-epic`'s `--link` parser (no live specimen exists in-tree — links are
      `[]` and the archive is empty; ground the migration on this documented encoding, not a guess).
- [x] 5.2 RED: add tests that the `0.5.0` migration REPAIRS a colon-string link into
      `{type, epic, reason?}`, DROPS an unrecoverable entry (empty string / `{}`), passes valid
      object links through unchanged, stamps `pmVersion` to `0.5.0`, and is idempotent on a second run.
- [x] 5.3 GREEN: add the repair-first `0.5.0` `MIGRATIONS` entry. Tests pass.
- [x] 5.4 Bump `plugins/pm/.claude-plugin/plugin.json` to `0.5.0`; add the `0.5.0` `CHANGELOG.md`
      entry (added fields/subcommands, tracker awareness, backward-compat note, upgrade steps).
- [x] 5.5 Update `README.md` and `skills/conductor/SKILL.md` for hierarchy, tracker awareness,
      `add-many`, and `update-epic`.
- [x] 5.6 Verification: full suite green (`node --test plugins/pm/scripts/conductor.test.mjs`);
      end-to-end manual demo (configure a tracker, `add-many` a parent+children batch, render the
      tree, confirm the brief's tracker-sync drift lists unmirrored epics). Then run the Gate-2
      implementation review against the committed diff before docs are considered final.
