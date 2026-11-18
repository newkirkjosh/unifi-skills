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
#        scripts/check-private.sh --published-msg <file>  committed messages, every line
#        scripts/check-private.sh --export-messages <file>  write every reachable commit message
#        scripts/check-private.sh --history     every path and blob reachable from any ref (CI)
#        scripts/check-private.sh [--all]       every tracked file (CI)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

# Patterns match raw line content (anchors work) and file paths. Producers
# write to temp files so line boundaries survive exactly. grep exits 1 for no
# match; anything above that is an error, never a clean result. In CI, raw
# scanner errors are suppressed too: they can echo a private pattern.
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
# A duplicated descriptor, not /dev/stderr: reopening that truncates a log file.
if [ -n "${CI:-}" ]; then exec 3>/dev/null; else exec 3>&2; fi
die() { echo "check-private: $1" >&2; exit 2; }
hits=""
match_paths() { # <file of NUL-separated raw paths>: each path is one record
  local rc=0
  LC_ALL=C grep -qzaiE "${args[@]}" "$1" 2>&3 || rc=$?
  [ "$rc" -le 1 ] || die "bad pattern or read error"
  [ "$rc" -eq 0 ] || return 0
  LC_ALL=C grep -zaiE "${args[@]}" "$1" >"$tmp/path-hits" 2>/dev/null || true
  hits+="path:$(head -c 4000 "$tmp/path-hits" | tr '\0' '\n')"$'\n'
}
match() { # <label> <file>: append "<label>:<line>:<text>" for each matching line
  local rc=0
  LC_ALL=C grep -qainE "${args[@]}" "$2" 2>&3 || rc=$?
  [ "$rc" -le 1 ] || die "bad pattern or read error"
  [ "$rc" -eq 1 ] || hits+="$(LC_ALL=C grep -ainE "${args[@]}" "$2" 2>/dev/null | LABEL="$1" LC_ALL=C awk '{print ENVIRON["LABEL"] ":" $0}')"$'\n'
}

# The private-terms file is configuration, never content: reject it in the index.
case "${1:---all}" in --msg|--published-msg|--history|--export-messages) ;; *)
tracked="$(git -C "$root" ls-files -- private-terms.local 2>&3)" || die "git ls-files failed"
if [ -n "$tracked" ]; then
  hits="private-terms.local is tracked or staged"$'\n'
fi ;;
esac
case "${1:---all}" in
  --staged)
    git -C "$root" diff --cached -U0 --no-color --text -- . ":(exclude)private-terms.local" >"$tmp/diff" 2>&3 || die "git diff failed"
    # Added lines are the "+" lines inside hunks; file headers ("+++ b/...")
    # sit between "diff --git" and the first "@@" and are skipped.
    awk '/^diff --git /{h=1; next} /^@@/{h=0; next} !h && /^\+/{print substr($0, 2)}' "$tmp/diff" >"$tmp/added" || die "parsing the staged diff failed"
    git -C "$root" diff --cached --name-only -z --no-renames --diff-filter=d -- . >"$tmp/paths" 2>&3 || die "git diff failed"
    match added "$tmp/added"; match_paths "$tmp/paths" ;;
  --msg)
    [ -r "${2:-}" ] || die "cannot read message file: ${2:-<none>}"
    rc=0; LC_ALL=C grep -avE '^#' "$2" >"$tmp/msg" 2>&3 || rc=$?
    [ "$rc" -le 1 ] || die "cannot read message file: $2"
    match msg "$tmp/msg" ;;
  --published-msg)
    [ -r "${2:-}" ] || die "cannot read message file: ${2:-<none>}"
    match msg "$2" ;;
  --export-messages)
    # Raw commit objects: git log --format=%B stops at a NUL byte.
    [ -n "${2:-}" ] || die "--export-messages needs a file"
    git -C "$root" rev-list --all >"$tmp/commits" 2>&3 || die "git rev-list failed"
    : >"$2"
    while read -r commit; do
      git -C "$root" cat-file commit "$commit" >"$tmp/commit" 2>&3 || die "git cat-file failed"
      LC_ALL=C sed '1,/^$/d' "$tmp/commit" >>"$2" || die "reading a commit message failed"
      printf '\n' >>"$2"
    done <"$tmp/commits"
    exit 0 ;;
  --history)
    # Walk every reachable commit's tree: one blob can have had several names.
    git -C "$root" rev-list --all >"$tmp/commits" 2>&3 || die "git rev-list failed"
    : >"$tmp/paths"
    declare -A seen_blob=() seen_tree=() seen_path=()
    while read -r commit; do
      tree="$(git -C "$root" rev-parse "$commit^{tree}" 2>&3)" || die "git rev-parse failed"
      [ -z "${seen_tree[$tree]:-}" ] || continue
      seen_tree[$tree]=1
      git -C "$root" ls-tree -r -z "$tree" >"$tmp/entries" 2>&3 || die "git ls-tree failed"
      while IFS= read -r -d '' entry; do
        meta="${entry%%$'\t'*}"; path="${entry#*$'\t'}"
        read -r _mode type sha <<<"$meta"
        if [ -z "${seen_path[$path]:-}" ]; then
          seen_path[$path]=1
          printf '%s\0' "$path" >>"$tmp/paths"
          [ "${path##*/}" != private-terms.local ] || hits+="private-terms.local is in history"$'\n'
        fi
        # Flagged by name above; its contents are the private terms themselves.
        [ "${path##*/}" != private-terms.local ] || continue
        [ "$type" = blob ] && [ -z "${seen_blob[$sha]:-}" ] || continue
        seen_blob[$sha]=1
        # One blob at a time, so anchored patterns see only committed lines.
        git -C "$root" cat-file blob "$sha" >"$tmp/blob" 2>&3 || die "git cat-file failed"
        match "blob $sha ($path)" "$tmp/blob"
      done <"$tmp/entries"
    done <"$tmp/commits"
    match_paths "$tmp/paths" ;;
  --all)
    rc=0; LC_ALL=C git -C "$root" grep --cached --text -inE "${args[@]}" -- . ":(exclude)private-terms.local" >"$tmp/tree" 2>&3 || rc=$?
    [ "$rc" -le 1 ] || die "git grep failed (exit $rc)"
    [ ! -s "$tmp/tree" ] || hits+="$(cat "$tmp/tree")"$'\n'
    git -C "$root" ls-files -z >"$tmp/paths" 2>&3 || die "git ls-files failed"
    match_paths "$tmp/paths"
    # git grep skips symlinks, but a symlink's stored target is published too.
    git -C "$root" ls-files -s -z >"$tmp/stage" 2>&3 || die "git ls-files failed"
    : >"$tmp/links"
    while IFS= read -r -d '' entry; do
      [ "${entry%% *}" = 120000 ] || continue
      blob="${entry#* }"; blob="${blob%% *}"
      git -C "$root" cat-file blob "$blob" >>"$tmp/links" 2>&3 || die "git cat-file failed"
      printf '\n' >>"$tmp/links"
    done <"$tmp/stage"
    match link "$tmp/links" ;;
  *)
    echo "usage: $0 [--staged | --msg <file> | --published-msg <file> | --export-messages <file> | --history | --all]" >&2; exit 2 ;;
esac
hits="${hits%$'\n'}"

if [ -n "$hits" ]; then
  echo "check-private: private terms found (this repo is public; see AGENTS.md):" >&2
  if [ -n "${CI:-}" ]; then
    # CI logs are public: never repeat a match or a path that may contain one.
    echo "$(wc -l <<<"$hits") matching line(s); run scripts/check-private.sh ${1:---all} locally to see them." >&2
  else
    echo "$hits" >&2
  fi
  exit 1
fi
