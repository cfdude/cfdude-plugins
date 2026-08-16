#!/bin/zsh
# Test harness for make_tree.sh — builds a throwaway git repo, runs the script,
# asserts each of the 8 stories. Usage: ./test_make_tree.sh /abs/path/to/make_tree.sh
set -u

SCRIPT="${1:-${0:A:h}/../skills/directory-tree/make_tree.sh}"
[[ -f "$SCRIPT" ]] || { echo "no such script: $SCRIPT"; exit 2; }
SCRIPT="${SCRIPT:A}"   # resolve to absolute — the harness cd's away from cwd

PASS=0; FAIL=0
ok()   { print -r -- "  PASS: $1"; ((++PASS)); return 0; }
bad()  { print -r -- "  FAIL: $1"; ((++FAIL)); return 0; }
has()  { grep -qF -- "$2" "$1"; }              # file contains literal
lacks(){ ! grep -qF -- "$2" "$1"; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
cd "$WORK" || exit 2

git init -q
git config user.email t@t.t; git config user.name t
git config core.excludesfile /dev/null   # isolate from the machine's global gitignore
mkdir -p src docs/build nested/deep keepme
print -r -- 'build/'            >  .gitignore   # bare dir name
print -r -- 'docs/build/'       >> .gitignore   # path-qualified dir (defect 5)
print -r -- '*.log'             >> .gitignore   # glob (defect 2)
print -r -- 'secret.txt'        >> .gitignore   # literal file
print -r -- '# a comment'       >> .gitignore
print -r -- '!keepme'           >> .gitignore   # negation (ignored by script)
print -r -- '**/.terraform/*'   >> .gitignore   # wildcard tail — must NOT collapse to '*'
print -r -- 'logs/*'            >> .gitignore   # wildcard tail — must reduce to 'logs'
mkdir -p .terraform logs && : > .terraform/state && : > logs/run.txt
: > src/app.py
: > debug.log
: > secret.txt
mkdir -p build && : > build/artifact.o
: > docs/build/generated.html
: > nested/deep/thing.txt
: > keepme/file.txt

# --- Run from a SUBDIRECTORY (defect 1: must still write at repo root) ---
( cd src && zsh "$SCRIPT" >/dev/null 2>&1 )

ROOT_TREE="$WORK/directory_tree.md"
SUB_TREE="$WORK/src/directory_tree.md"

# Story/Defect 1: root anchoring
[[ -f "$ROOT_TREE" ]] && ok "d1: directory_tree.md created at repo ROOT" \
                      || bad "d1: directory_tree.md NOT at repo root"
[[ -f "$SUB_TREE" ]]  && bad "d1: stray tree left in subdir" \
                      || ok "d1: no stray tree in subdir"

# Defect 3: no stray 'temp' file
[[ -e "$WORK/temp" || -e "$WORK/src/temp" ]] && bad "d3: stray 'temp' file exists" \
                                             || ok "d3: no stray 'temp' file"

# Defect 4: directory_tree.md self-added to .gitignore
if [[ -f "$WORK/.gitignore" ]] && has "$WORK/.gitignore" 'directory_tree.md'; then
  ok "d4: directory_tree.md added to .gitignore"
else
  bad "d4: directory_tree.md NOT in .gitignore"
fi

# Markdown fence preserved
if [[ -f "$ROOT_TREE" ]]; then
  head -1 "$ROOT_TREE" | grep -q '```' && ok "fence: opens with \`\`\`" || bad "fence: missing open"
  tail -1 "$ROOT_TREE" | grep -q '```' && ok "fence: closes with \`\`\`" || bad "fence: missing close"
fi

# Defect 2: glob '*.log' honored -> debug.log excluded
[[ -f "$ROOT_TREE" ]] && { lacks "$ROOT_TREE" 'debug.log' && ok "d2: *.log glob excluded debug.log" || bad "d2: debug.log still present (glob dropped)"; }

# literal file excluded
[[ -f "$ROOT_TREE" ]] && { lacks "$ROOT_TREE" 'secret.txt' && ok "literal: secret.txt excluded" || bad "literal: secret.txt present"; }

# bare dir 'build/' excluded
[[ -f "$ROOT_TREE" ]] && { lacks "$ROOT_TREE" 'artifact.o' && ok "dir: build/ excluded" || bad "dir: build/ contents present"; }

# Defect 5: path-qualified 'docs/build/' -> basename 'build' excludes generated.html
[[ -f "$ROOT_TREE" ]] && { lacks "$ROOT_TREE" 'generated.html' && ok "d5: docs/build/ basename-excluded" || bad "d5: generated.html present (slash-token no-op)"; }

# Critical (reviewer #1): wildcard-tail patterns must NOT collapse to a universal '*'
[[ -f "$ROOT_TREE" ]] && { has "$ROOT_TREE" 'app.py' && ok "wildcard-tail: tree NOT universally excluded (app.py survives)" || bad "wildcard-tail: whole tree excluded by collapsed '*'"; }
[[ -f "$ROOT_TREE" ]] && { lacks "$ROOT_TREE" 'state' && ok "wildcard-tail: .terraform/* -> .terraform excluded" || bad "wildcard-tail: .terraform/state present"; }
[[ -f "$ROOT_TREE" ]] && { lacks "$ROOT_TREE" 'run.txt' && ok "wildcard-tail: logs/* -> logs excluded" || bad "wildcard-tail: logs/run.txt present"; }

# source still visible
[[ -f "$ROOT_TREE" ]] && { has "$ROOT_TREE" 'app.py' && ok "keep: src/app.py visible" || bad "keep: app.py missing"; }

# --- Run with --include build (re-include an excluded dir) ---
rm -f "$ROOT_TREE"
( cd "$WORK" && zsh "$SCRIPT" --include build >/dev/null 2>&1 )
[[ -f "$ROOT_TREE" ]] && { has "$ROOT_TREE" 'artifact.o' && ok "include: --include build re-included it" || bad "include: build still excluded"; }

# --- Global-ignore awareness: when directory_tree.md is already ignored by a
#     global core.excludesfile, the script must NOT add a redundant per-repo line ---
GWORK=$(mktemp -d)
GEXCL=$(mktemp)
print -r -- 'directory_tree.md' > "$GEXCL"
( cd "$GWORK" && git init -q && git config user.email t@t.t && git config user.name t \
    && git config core.excludesfile "$GEXCL" && : > file.txt \
    && zsh "$SCRIPT" >/dev/null 2>&1 )
if [[ -f "$GWORK/.gitignore" ]] && grep -qF 'directory_tree.md' "$GWORK/.gitignore"; then
  bad "global-aware: redundantly added directory_tree.md despite global ignore"
else
  ok "global-aware: skipped per-repo entry (already globally ignored)"
fi
[[ -f "$GWORK/directory_tree.md" ]] && ok "global-aware: tree still generated" || bad "global-aware: no tree produced"
rm -rf "$GWORK" "$GEXCL"

print -r -- ""
print -r -- "RESULT: $PASS passed, $FAIL failed"
[[ $FAIL -eq 0 ]]
