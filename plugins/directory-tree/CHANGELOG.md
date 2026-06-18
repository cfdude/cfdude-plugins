# Changelog

All notable changes to the directory-tree plugin will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
