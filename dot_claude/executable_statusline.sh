#!/usr/bin/env bash
# Read JSON data that Claude Code sends to stdin
input=$(cat)

# Extract fields using jq
MODEL=$(echo "$input" | jq -r '.model.display_name')
DIR=$(echo "$input" | jq -r '.workspace.current_dir')
# The "// 0" provides a fallback if the field is null
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)

# Current worktree, identified by its branch (worktrunk keeps one branch per
# worktree). Detached HEAD falls back to the short SHA; outside a repo the
# segment is dropped entirely.
BRANCH=$(git -C "$DIR" symbolic-ref --quiet --short HEAD 2>/dev/null \
  || git -C "$DIR" rev-parse --short HEAD 2>/dev/null)

WORKTREE=""
if [ -n "$BRANCH" ]; then
  # Trunk vs task worktree. NOT a linked-worktree test: worktrunk can keep a
  # central .git with every checkout linked (trunk included), so git-dir vs
  # git-common-dir marks them all as linked. Compare against the default
  # branch instead — origin/HEAD when it is set, else the usual names.
  DEFAULT=$(git -C "$DIR" symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null)
  DEFAULT=${DEFAULT#origin/}
  case "$BRANCH" in
    "${DEFAULT:-master}" | master | main) WORKTREE=" | 🌳 $BRANCH" ;;
    *) WORKTREE=" | 🌿 $BRANCH" ;;
  esac
fi

# Output the status line - ${DIR##*/} extracts just the folder name
echo "[$MODEL] 📁 ${DIR##*/}$WORKTREE | ${PCT}% context"