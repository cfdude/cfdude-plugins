# cfdude-plugins

Rob Sherman's public [Claude Code](https://code.claude.com) plugins, distributed as a
single marketplace.

## Install

```
/plugin marketplace add cfdude/cfdude-plugins
```

Then install any plugin from it:

```
/plugin install pm@cfdude-plugins
/plugin install directory-tree@cfdude-plugins
```

## Plugins

| Plugin | Version | What it does |
|--------|---------|--------------|
| [`pm`](https://github.com/cfdude/pm) | 0.9.3 | A project-management conductor above OpenSpec and Superpowers — tracks proposals as epics, maintains an explicit detour stack, and enforces a reconcile gate so nothing is lost when work pivots or context is compacted. Lives in its own repo, referenced here via a `github` source. |
| [`directory-tree`](plugins/directory-tree) | 1.1.0 | Generates and optimizes `directory_tree.md` with a `.gitignore`-aware tree script, plus `--include` overrides and `.gitignore` improvement suggestions. |

## Repository layout

```
.claude-plugin/marketplace.json   marketplace catalog (pluginRoot: ./plugins; pm points at cfdude/pm)
plugins/directory-tree/            the directory-tree plugin
```

## License

MIT © Rob Sherman
