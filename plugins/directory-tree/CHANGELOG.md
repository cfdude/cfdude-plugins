# Changelog

All notable changes to the directory-tree plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.1] - 2026-08-16

### Changed
- **Self-gitignoring is now global-aware.** The script uses `git check-ignore` instead of a
  literal `.gitignore` grep, so `directory_tree.md` is appended to a repo's `.gitignore` only
  when it isn't *already* ignored by some other mechanism — a global `core.excludesfile`,
  `.git/info/exclude`, or an existing entry. A setup that ignores `directory_tree.md` globally
  no longer accrues a redundant per-repo line in every project.

## [1.2.0] - 2026-08-16

### Added
- **Repo-root anchoring.** `make_tree.sh` now resolves `git rev-parse --show-toplevel` and writes
  `directory_tree.md` at the project root regardless of which subdirectory it's invoked from
  (falls back to the current directory outside a git repo).
- **`.gitignore` glob patterns are honored.** Lines like `*.log` / `*.pyc` are now passed to
  `tree -I` (which does fnmatch) instead of being silently dropped.
- **Self-gitignoring.** The script ensures `directory_tree.md` is listed in `.gitignore`,
  appending it (and creating `.gitignore` if absent) when missing — the generated tree is not
  meant to be version-controlled.
- Expanded the core exclusion set (`node_modules`, `dist`, `build`, `.next`, `out`, `target`,
  `coverage`, `__pycache__`, `.pytest_cache`, `.ruff_cache`, `.mypy_cache`, `venv`, `.venv`,
  `env`, `*.egg-info`, `settings.local.json`) so a tree is sensible even with no `.gitignore`.

### Changed
- **⚠️ Behavior change — path-qualified `.gitignore` entries now actually exclude.** `tree -I`
  matches basenames, so the parser reduces every pattern to its final path segment. Previously a
  slash-bearing token (e.g. `docs/build` from `docs/build/`) matched no basename and was a
  **silent no-op**; it now excludes anything named `build` anywhere in the tree. A repo whose
  tree suddenly loses a directory after upgrading is that `.gitignore` entry *finally working* —
  not a regression. Wildcard-tail idioms (`build/**`, `**/.terraform/*`, `logs/*`) reduce to the
  nearest real name (`build`, `.terraform`, `logs`) rather than collapsing to a match-everything
  `*`. Negation lines (`!keep`) remain unsupported by `tree -I` and are skipped.
- The skill's `allowed-tools` scopes Bash to the bundled script plus the read-only helpers it
  uses (`wc`, `head`, `cat`, `fd`) instead of a blanket `Bash` grant, so it runs without a
  permission prompt while narrowing what it can execute.

### Fixed
- **No more stray `temp` file.** The markdown-fence wrap uses `mktemp` instead of a literal
  `temp` file in the repo root, so a mid-write failure no longer leaves an orphan behind.

## [1.1.0] - 2026-06-17

### Changed
- Renamed plugin from `directory-tree-maintenance` to `directory-tree` (no maintenance daemon — it generates/optimizes on demand).
- Migrated into the `cfdude-plugins` marketplace; install is now `directory-tree@cfdude-plugins`.
- Modernized `make_tree.sh`: adopted the CLI-arg-driven variant.

### Added
- `--include` / `-i name1,name2` flag to re-include entries that `.gitignore` would otherwise exclude.
- `--help` / `-h` usage output.

## [1.0.1] - 2025-11-04

### Changed
- Transitioned from project-level skill to global plugin
- Now available across all projects (not just Stocks)

### Fixed
- Updated script path references to use ${CLAUDE_PLUGIN_ROOT}
- Improved portability across different project structures

## [1.0.0] - 2025-11-04

### Added
- Initial release of directory-tree-maintenance plugin
- Automatic directory tree generation and maintenance
- Smart .gitignore analysis and optimization
- Bundled make_tree.sh script for tree generation
- Support for project-agnostic operation (works in any directory)
- Size monitoring with 500-line threshold
- Intelligent pattern recognition for build artifacts, dependencies, and temporary files
- Comprehensive skill documentation with workflow guidelines

### Features
- Auto-detects current working directory as project root
- Parses .gitignore to avoid duplicate entries
- Suggests categorized .gitignore improvements
- Verifies improvements with before/after metrics
- Calculates tree-to-source-file ratio for optimization guidance

### Documentation
- Complete README with installation and usage instructions
- Detailed SKILL.md with workflow patterns and examples
- Best practices and troubleshooting guide
