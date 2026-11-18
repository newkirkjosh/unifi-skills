#!/usr/bin/env bash
# Fail when text about to be published matches a private term. Terms are
# built-in patterns (absolute home paths) plus ~/.config/git/private-terms and
# the gitignored private-terms.local at the repo root when present: one
# extended regex per line, matched case-insensitively; blank lines and lines
# starting with # are ignored. Commits are checked by the global hooks from
# the dotfiles; this script is for CI and manual runs.
#
# usage: scripts/check-private.sh --staged      added lines in the index
#        scripts/check-private.sh --msg <file>  a commit message
#        scripts/check-private.sh [--all]       every tracked file (CI)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
self="scripts/check-private.sh"

patterns=('/var/[h]ome/' '/[h]ome/[a-z_][a-z0-9_-]*/' '/[U]sers/[A-Za-z]')
found_terms=0
for f in "${XDG_CONFIG_HOME:-$HOME/.config}/git/private-terms" "$root/private-terms.local"; do
  [ -f "$f" ] || continue
  found_terms=1
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in ''|'#'*) continue ;; esac
    patterns+=("$line")
  done < "$f"
done
[ "$found_terms" -eq 1 ] || [ -n "${CI:-}" ] || echo "check-private: no private-terms file; checking built-in patterns only" >&2

args=()
for p in "${patterns[@]}"; do args+=(-e "$p"); done

# grep exits 1 for no match; anything above that (a bad pattern, a failed git
# command) is an error, never a clean result.
scan() {
  local rc=0
  hits="$("$@")" || rc=$?
  if [ "$rc" -gt 1 ]; then
    echo "check-private: scan failed (exit $rc); fix the pattern or the command" >&2
    exit 2
  fi
}
staged() {
  git -C "$root" diff --cached -U0 --no-color -- . ":(exclude)$self" \
    | { grep -E '^\+' || [ $? -eq 1 ]; } | { grep -vE '^\+\+\+ ' || [ $? -eq 1 ]; } | grep -inE "${args[@]}"
}
msg() { grep -vE '^#' "$1" | grep -inE "${args[@]}"; }

hits=""
case "${1:---all}" in
  --staged) scan staged ;;
  --msg) scan msg "$2" ;;
  --all) scan git -C "$root" grep -inIE "${args[@]}" -- . ":(exclude)$self" ;;
  *)
    echo "usage: $0 [--staged | --msg <file> | --all]" >&2; exit 2 ;;
esac

if [ -n "$hits" ]; then
  echo "check-private: private terms found (this repo is public; see AGENTS.md, Security and privacy):" >&2
  echo "$hits" >&2
  exit 1
fi
