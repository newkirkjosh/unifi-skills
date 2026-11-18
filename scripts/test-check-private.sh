#!/usr/bin/env bash
# Regression tests for check-private.sh: clean, hit, bad pattern, unreadable
# input, failed git command, and CI output that never repeats a match.
set -uo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
export XDG_CONFIG_HOME="$tmp/config" HOME="$tmp/home"
mkdir -p "$tmp/repo/scripts" "$HOME"
cp "$here/check-private.sh" "$tmp/repo/scripts/"
git -C "$tmp/repo" init -q
git -C "$tmp/repo" -c user.name=t -c user.email=t@example.com -c commit.gpgsign=false commit -q --allow-empty -m init
check() { bash "$tmp/repo/scripts/check-private.sh" "$@" 2>"$tmp/err"; }
fail=0
expect() { # <want rc> <name> <args...>
  local want="$1" name="$2"; shift 2
  check "$@"; local rc=$?
  if [ "$rc" -eq "$want" ]; then echo "ok   $name"; else echo "FAIL $name: rc $rc, want $want"; cat "$tmp/err"; fail=1; fi
}
echo hello > "$tmp/repo/a.txt"; git -C "$tmp/repo" add a.txt
expect 0 "clean tree" --all
expect 0 "clean staged" --staged
printf 'see /%s/someone/x\n' home > "$tmp/repo/b.txt"; git -C "$tmp/repo" add b.txt
expect 1 "hit in tree" --all
expect 1 "hit in staged" --staged
CI=1 check --all; grep -qE 'someone|b\.txt' "$tmp/err" && { echo "FAIL CI output repeats a match or path"; fail=1; } || echo "ok   CI output names neither match nor path"
printf '/%s/someone/x\n' home > "$tmp/msg"; expect 1 "hit in message" --msg "$tmp/msg"
printf '# /%s/someone/ in a comment\nfine\n' home > "$tmp/msg"; expect 0 "comment lines ignored" --msg "$tmp/msg"
expect 2 "unreadable message" --msg "$tmp/missing"
printf '(\n' > "$tmp/repo/private-terms.local"; expect 2 "bad pattern" --all; rm "$tmp/repo/private-terms.local"
git -C "$tmp/repo" rm -q --cached b.txt; rm "$tmp/repo/b.txt"
printf 'private-device\n' > "$tmp/repo/c.txt"; git -C "$tmp/repo" add c.txt
printf '^private-device$\n' > "$tmp/repo/private-terms.local"
expect 1 "anchored pattern in tree" --all
expect 1 "anchored pattern in staged" --staged
printf '++ %s\n' private-device > "$tmp/repo/c.txt"; git -C "$tmp/repo" add c.txt
printf 'private-device\n' > "$tmp/repo/private-terms.local"
expect 1 "added line starting with ++" --staged
rm "$tmp/repo/private-terms.local"
git -C "$tmp/repo" rm -q --cached c.txt; rm "$tmp/repo/c.txt"
printf 'x\n' > "$tmp/repo/secret-npc.md"; git -C "$tmp/repo" add secret-npc.md
printf 'secret-npc\n' > "$tmp/repo/private-terms.local"
expect 1 "private term in a tracked path" --all
expect 1 "private term in a staged path" --staged
CI=1 check --all; grep -q secret "$tmp/err" && { echo "FAIL CI output names a matching path"; fail=1; } || echo "ok   CI output omits matching paths"
printf '(secret\n' > "$tmp/repo/private-terms.local"
CI=1 check --all; grep -q secret "$tmp/err" && { echo "FAIL CI error output echoes a pattern"; fail=1; } || echo "ok   CI error output hides the pattern"
git -C "$tmp/repo" rm -q --cached secret-npc.md; rm "$tmp/repo/secret-npc.md"
printf 'x\n' > "$tmp/repo/$(printf 'tab\tname')"; printf 'x\n' > "$tmp/repo/caf\303\251-npc.md"
git -C "$tmp/repo" add -A
printf '^tab\tname$\n' > "$tmp/repo/private-terms.local"
expect 1 "anchored term in a path with a tab" --all
expect 1 "anchored term in a staged path with a tab" --staged
printf 'caf\303\251-npc\n' > "$tmp/repo/private-terms.local"
expect 1 "non-ASCII term in a path" --all
git -C "$tmp/repo" rm -q --cached -- "$(printf 'tab\tname')" "$(printf 'caf\303\251-npc.md')"; rm "$tmp/repo/$(printf 'tab\tname')" "$tmp/repo/$(printf 'caf\303\251-npc.md')"
printf 'one\n\n' > "$tmp/msg"; printf '^$\n' > "$tmp/repo/private-terms.local"
expect 1 "trailing blank line kept" --msg "$tmp/msg"
printf '' > "$tmp/msg"; expect 0 "empty message is clean" --msg "$tmp/msg"
printf 'bin\0ary secret-npc\n' > "$tmp/repo/blob.bin"; git -C "$tmp/repo" add blob.bin
printf 'secret-npc\n' > "$tmp/repo/private-terms.local"
expect 1 "private term in binary content" --all
expect 1 "private term in staged binary content" --staged
git -C "$tmp/repo" rm -q --cached blob.bin; rm "$tmp/repo/blob.bin"
printf 'x\n' > "$tmp/repo/$(printf 'bad\377-secret-npc')"; git -C "$tmp/repo" add -A
printf 'secret-npc\n' > "$tmp/repo/private-terms.local"
expect 1 "term in a path with invalid UTF-8" --all
expect 1 "term in a staged path with invalid UTF-8" --staged
git -C "$tmp/repo" rm -q --cached -- "$(printf 'bad\377-secret-npc')"; rm "$tmp/repo/$(printf 'bad\377-secret-npc')"
printf '# secret-npc\n' >> "$tmp/repo/scripts/check-private.sh"; git -C "$tmp/repo" add scripts/check-private.sh
expect 1 "term added to the scanner itself" --all
expect 1 "term staged in the scanner itself" --staged
cp "$here/check-private.sh" "$tmp/repo/scripts/"; git -C "$tmp/repo" add scripts/check-private.sh
ln -s "/opt/secret-npc/x" "$tmp/repo/innocent-link"; git -C "$tmp/repo" add innocent-link
printf 'secret-npc\n' > "$tmp/repo/private-terms.local"
expect 1 "term in a symlink target" --all
git -C "$tmp/repo" rm -q --cached innocent-link; rm "$tmp/repo/innocent-link"
printf 'ok\0\nsecret-npc\n' > "$tmp/msg"
expect 1 "term in a message with a NUL byte" --msg "$tmp/msg"
rm "$tmp/repo/private-terms.local"
mkdir -p "$tmp/bin"; printf '#!/bin/sh\nexit 128\n' > "$tmp/bin/git"; chmod +x "$tmp/bin/git"
PATH="$tmp/bin:$PATH" expect 2 "failed git diff" --staged
PATH="$tmp/bin:$PATH" expect 2 "failed git grep" --all
exit $fail
