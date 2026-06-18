---
name: directory-tree
description: Generate and optimize the directory_tree.md file by running the bundled make_tree.sh script and analyzing results to suggest .gitignore improvements. Use when the user mentions directory tree, make_tree.sh, updating .gitignore, or when directory_tree.md is too large (>500 lines).
allowed-tools: Read, Edit, Bash, Grep, Glob
---

# Directory Tree

This skill generates and keeps a clean, manageable `directory_tree.md` file by:
1. Generating/refreshing the directory tree visualization
2. Analyzing the tree for unwanted artifacts (build files, dependencies, test caches, etc.)
3. Suggesting and applying .gitignore improvements
4. Verifying improvements after changes

## When to Use This Skill

- User asks to "update the directory tree"
- User runs or mentions `./make_tree.sh`
- User asks about optimizing .gitignore
- directory_tree.md file is larger than 500 lines
- User mentions the directory tree is "too big" or "has too many files"

## The Bundled Script

The script lives at `${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh` and runs against
the current working directory. It derives its exclude list from the project's `.gitignore`
(directory entries and literal paths; glob/negation lines are skipped) plus core exclusions
(`.git`, `.DS_Store`), then writes a fenced markdown tree to `directory_tree.md`.

It accepts CLI flags:

```bash
# Default run (exclusions come entirely from .gitignore + core)
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh

# Re-INCLUDE entries that .gitignore would otherwise exclude (comma-separated)
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh --include .env,.serena
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh -i dist

# Usage
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh --help
```

`--include` removes the named entries from the computed exclude set, so a directory or file
that `.gitignore` hides can still appear in the tree when you explicitly want it visible.

## Core Workflow

### Mode 1: Simple Update
When the user just wants to refresh the directory tree:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh
wc -l directory_tree.md
```

Report the result: "Directory tree updated. Currently X lines."

### Mode 2: Optimization (when tree is >500 lines or user requests optimization)

#### Step 1: Generate Current Tree
```bash
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh
wc -l directory_tree.md
```

Record the initial line count.

#### Step 2: Analyze Tree for Unwanted Patterns
Read the first 200-300 lines of directory_tree.md to identify patterns:

```bash
head -300 directory_tree.md
```

Look for common artifacts that should be excluded:
- **Build outputs**: `.next/`, `out/`, `dist/`, `build/`, `target/`
- **Dependencies**: `node_modules/`, `vendor/`, `__pycache__/`
- **Virtual environments**: `.venv/`, `venv/`, `env/`, `ENV/`
- **Test caches**: `.pytest_cache/`, `.coverage/`, `htmlcov/`, `.nyc_output/`
- **IDE files**: `.vscode/`, `.idea/`, `.DS_Store`
- **Temporary files**: `tmp/`, `temp/`, `*.tmp`, `*.log`
- **Archives**: `archive/`, `docs/archive/`
- **Package managers**: `yarn.lock`, `package-lock.json`, `Gemfile.lock`

#### Step 3: Read Current .gitignore
```bash
cat .gitignore
```

Identify what's already excluded and what's missing.

#### Step 4: Suggest .gitignore Additions
Create a prioritized list of additions organized by category:

```
# Next.js build output (removing ~2000 lines from tree)
.next/
out/

# Python virtual environments (removing ~800 lines from tree)
.venv/
venv/

# Test coverage (removing ~150 lines from tree)
.coverage
htmlcov/
```

#### Step 5: Apply Changes to .gitignore
Use the Edit tool to add the suggestions to appropriate sections:
- Add to existing sections when they exist
- Create new sections if needed (e.g., "# Next.js" if not present)
- Maintain logical organization (Node, Python, Testing, etc.)

#### Step 6: Regenerate Tree and Verify
```bash
${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh
wc -l directory_tree.md
```

Calculate and report the improvement:
- **Before**: X lines
- **After**: Y lines
- **Reduction**: Z lines (P%)

#### Step 7: Evaluate If Further Optimization Needed

If the tree is still >500 lines after initial optimization:

1. **Analyze project scale**:
   ```bash
   fd -e py -e js -e ts -e tsx -e java -e go -e rb -e php | wc -l
   ```

2. **Calculate ratio**: `tree_lines / source_files`
   - Ratio < 5:1 → Tree size is appropriate for project scale
   - Ratio 5-10:1 → Moderate; optimization may help
   - Ratio > 10:1 → Significant reduction likely possible

3. **Report findings to the user**, then **wait for confirmation** before applying any
   additional exclusions. Do NOT auto-apply beyond the initial pass.

## Pattern Recognition Guidelines

### High-Priority Exclusions (likely >100 lines each)
1. Framework build outputs (`.next/`, `dist/`, `build/`)
2. Package dependencies (`node_modules/`, `vendor/`)
3. Virtual environments (`.venv/`, `venv/`)
4. Test coverage data (`htmlcov/`, `.coverage`)

### Medium-Priority Exclusions (likely 50-100 lines each)
5. Compiled code (`__pycache__/`, `*.pyc`, `*.class`)
6. Log directories (`logs/` with many dated files)
7. Cache directories (`.pytest_cache/`, `.turbo/`)

### Low-Priority Exclusions (likely <50 lines each)
8. Archive directories
9. Backup files (`*.bak`, `*.backup`)
10. IDE settings

## Target Metrics

**Project Size Guidelines**:
- **Small projects** (<50 source files): 200-500 lines ideal
- **Medium projects** (50-200 files): 500-1000 lines acceptable
- **Large projects** (200-500 files): 1000-2000 lines acceptable
- **Enterprise projects** (>500 files): 2000+ lines may be necessary

**Optimization Triggers**:
- **Auto-optimize**: >500 lines (initial pass)
- **Ask user**: After initial optimization, if ratio > 5:1
- **No action needed**: Ratio < 5:1 indicates appropriate size for project scale

## Best Practices

1. **Always regenerate after changes**: Run the bundled script after editing .gitignore
2. **Verify improvements**: Always show before/after line counts
3. **Organize .gitignore logically**: Group similar patterns (Python, Node, Testing, etc.)
4. **Be conservative**: Only exclude build artifacts, dependencies, and temporary files
5. **Preserve important files**: Don't exclude source code, configs, or documentation

## Error Handling

If the bundled script doesn't exist:
- Inform the user the plugin may not be properly installed
- Check if `${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh` exists

If `tree` is not installed:
- Suggest `brew install tree` (macOS) or the platform equivalent

If .gitignore doesn't exist:
- Ask the user if they want to create one before proceeding

If directory_tree.md shows no improvement after changes:
- Verify the patterns were added correctly to .gitignore
- Check if .gitignore patterns are using correct syntax (the script only honors literal
  directory/file entries, not glob or negation lines)
- Suggest alternative patterns or consider `--include`/exclusion adjustments

## Plugin Information

This skill is part of the **directory-tree** plugin.
- Script location: `${CLAUDE_PLUGIN_ROOT}/skills/directory-tree/make_tree.sh`
- Operates on the current working directory
- Compatible with any project structure
