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

# Patterns match raw line content, so anchors (^term$) work. grep and
# git grep exit 1 for no match; anything above that (a bad pattern, a failed
# read) is an error, never a clean result.
die() { echo "check-private: $1" >&2; exit 2; }
match() { # <label> : match stdin lines; hits get "<label>:<n>:" prefixes
  local rc=0
  hits="$(grep -inE "${args[@]}")" || rc=$?
  [ "$rc" -le 1 ] || die "bad pattern or read error (grep exit $rc)"
}

hits=""
case "${1:---all}" in
  --staged)
    diff="$(git -C "$root" diff --cached -U0 --no-color -- . ":(exclude)$self")" || die "git diff failed"
    # Added lines are the "+" lines inside hunks; file headers ("+++ b/...")
    # sit between "diff --git" and the first "@@" and are skipped.
    added="$(awk '/^diff --git /{h=1; next} /^@@/{h=0; next} !h && /^\+/{print substr($0, 2)}' <<<"$diff")" || die "parsing the staged diff failed"
    match <<<"$added" ;;
  --msg)
    [ -r "${2:-}" ] || die "cannot read message file: ${2:-<none>}"
    rc=0; body="$(grep -vE '^#' "$2")" || rc=$?
    [ "$rc" -le 1 ] || die "cannot read message file: $2"
    match <<<"$body" ;;
  --all)
    rc=0; hits="$(git -C "$root" grep -inIE "${args[@]}" -- . ":(exclude)$self")" || rc=$?
    [ "$rc" -le 1 ] || die "git grep failed (exit $rc)" ;;
  *)
    echo "usage: $0 [--staged | --msg <file> | --all]" >&2; exit 2 ;;
esac

if [ -n "$hits" ]; then
  echo "check-private: private terms found (this repo is public; see AGENTS.md, Security and privacy):" >&2
  if [ -n "${CI:-}" ]; then
    # CI logs are public: never repeat a match or a path that may contain one.
    echo "$(wc -l <<<"$hits") matching line(s); run scripts/check-private.sh locally to see them." >&2
  else
    echo "$hits" >&2
  fi
  exit 1
fi
