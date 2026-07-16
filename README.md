# cfdude-plugins

Rob Sherman's public [Claude Code](https://code.claude.com) plugins, distributed as a
single marketplace.

## Install

```
/plugin marketplace add cfdude/cfdude-plugins
```

Then install any plugin from it:

```
/plugin install honcho@cfdude-plugins
/plugin install pm@cfdude-plugins
/plugin install directory-tree@cfdude-plugins
```

## Plugins

| Plugin | Version | What it does |
|--------|---------|--------------|
| [`honcho`](https://github.com/cfdude/claude-honcho) | 0.2.7 | Persistent, cross-session memory for Claude Code backed by [Honcho](https://honcho.dev). This cfdude fork adds a project-level `.honcho.json` workspace override, enabling clean work/personal workspace separation. Lives in its own repo, referenced here via a `git-subdir` source. |
| [`pm`](https://github.com/cfdude/pm) | 0.9.3 | A project-management conductor above OpenSpec and Superpowers — tracks proposals as epics, maintains an explicit detour stack, and enforces a reconcile gate so nothing is lost when work pivots or context is compacted. Lives in its own repo, referenced here via a `github` source. |
| [`directory-tree`](plugins/directory-tree) | 1.1.0 | Generates and optimizes `directory_tree.md` with a `.gitignore`-aware tree script, plus `--include` overrides and `.gitignore` improvement suggestions. |

## Repository layout

```
.claude-plugin/marketplace.json   marketplace catalog
plugins/directory-tree/            the directory-tree plugin (locally hosted)
```

`honcho` and `pm` are hosted in their own repos and referenced from the manifest
(`git-subdir` → `cfdude/claude-honcho`, `github` → `cfdude/pm`); only their catalog
entries live here, not their code.

## License

MIT © Rob Sherman
