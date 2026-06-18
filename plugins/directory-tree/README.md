# directory-tree

Generate and optimize your project's `directory_tree.md` visualization with a bundled,
`.gitignore`-aware tree script and automatic `.gitignore` improvement suggestions.

## Features

- **Automatic tree generation**: Creates/updates `directory_tree.md` in your project root
- **.gitignore-driven exclusions**: Derives the exclude list from your `.gitignore` plus core exclusions (`.git`, `.DS_Store`)
- **Re-include override**: `--include name1,name2` surfaces entries `.gitignore` would otherwise hide
- **Smart optimization**: Identifies build artifacts/dependencies and suggests `.gitignore` additions
- **Size monitoring**: Flags trees over 500 lines and offers optimization
- **Project-agnostic**: Works with any project structure

## Installation

```bash
/plugin marketplace add cfdude/cfdude-plugins
/plugin install directory-tree@cfdude-plugins
```

After installation, restart Claude Code to activate the plugin.

## Usage

The skill activates automatically when you mention directory trees or `.gitignore` optimization:

```
"Update the directory tree"
"The directory tree is too big"
"Optimize .gitignore"
"Run make_tree.sh"
```

### Manual Invocation

```bash
# Default run — exclusions from .gitignore + core
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh

# Re-include entries .gitignore would hide
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh --include .env,.serena

# Usage
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh --help
```

## How It Works

1. Operates on the current working directory
2. Parses `.gitignore` for literal directory/file exclusions (glob and negation lines are skipped)
3. Generates a fenced, markdown-formatted `tree` visualization with sizes and dates
4. If the tree is large (>500 lines), suggests `.gitignore` improvements
5. Applies improvements and regenerates, reporting before/after line counts

## Requirements

- **tree**: `brew install tree` (macOS) or the platform equivalent
- **zsh**: the script uses zsh (default on macOS)

## Version

Current version: 1.1.0 — see [CHANGELOG.md](CHANGELOG.md).

## License

MIT © Rob Sherman
