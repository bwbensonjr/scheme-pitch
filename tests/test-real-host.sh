#!/bin/sh
# Exercise the complete Emit host against real ports and filesystem effects.
set -eu

cd "$(dirname "$0")/.."

fixture_dir=$(mktemp -d)
trap 'chmod -R u+w "$fixture_dir" 2>/dev/null || true; rm -rf "$fixture_dir"' EXIT HUP INT TERM

fail () {
  echo "test-real-host: $1" >&2
  exit 1
}

run_pitch () {
  EMIT_VERBOSITY=quiet build/pitch "$@"
}

run_status () {
  expected=$1
  shift
  set +e
  run_pitch "$@" >"$fixture_dir/stdout" 2>"$fixture_dir/stderr"
  actual=$?
  set -e
  [ "$actual" -eq "$expected" ] ||
    fail "expected status $expected, got $actual for: $*"
}

file_inode () {
  ls -di "$1" | awk '{print $1}'
}

# The three standard ports: stdin is formatted onto stdout without a diagnostic.
printf '(f a b)\n' >"$fixture_dir/stdin-expected"
run_status 0 --stdout <"$fixture_dir/stdin-expected"
cmp "$fixture_dir/stdin-expected" "$fixture_dir/stdout" ||
  fail "standard-input formatting changed already-formatted text"
[ ! -s "$fixture_dir/stderr" ] || fail "standard-input success wrote a diagnostic"

# A real directory tree covers deterministic walking, every supported suffix,
# hidden-file exclusion, non-Scheme exclusion, and linked-directory avoidance.
tree=$fixture_dir/tree
external=$fixture_dir/external
mkdir -p "$tree/sub" "$external"
unformatted='(define (f x)
(g x))
'
printf '%s' "$unformatted" >"$tree/a.sls"
printf '%s' "$unformatted" >"$tree/b.scm"
printf '%s' "$unformatted" >"$tree/sub/c.ss"
printf '%s' "$unformatted" >"$tree/ignored.txt"
printf '%s' "$unformatted" >"$tree/.hidden.sld"
printf '%s' "$unformatted" >"$external/linked.scm"
ln -s "$external" "$tree/linked"
cp "$tree/ignored.txt" "$fixture_dir/ignored-before"
cp "$tree/.hidden.sld" "$fixture_dir/hidden-before"
cp "$external/linked.scm" "$fixture_dir/linked-before"

run_status 1 --check "$tree"
[ ! -s "$fixture_dir/stdout" ] || fail "directory check wrote standard output"
printf '%s\n' \
  "$tree/a.sls: would reformat" \
  "$tree/b.scm: would reformat" \
  "$tree/sub/c.ss: would reformat" \
  >"$fixture_dir/directory-expected"
cmp "$fixture_dir/directory-expected" "$fixture_dir/stderr" ||
  fail "directory traversal was not deterministic or selected the wrong files"

# In-place output is a same-directory replacement: the inode changes, the
# complete formatted file passes check, and no temporary remains.
before_inode=$(file_inode "$tree/a.sls")
run_status 0 "$tree"
[ ! -s "$fixture_dir/stdout" ] || fail "in-place formatting wrote standard output"
[ ! -s "$fixture_dir/stderr" ] || fail "successful in-place formatting wrote a diagnostic"
after_inode=$(file_inode "$tree/a.sls")
[ "$before_inode" != "$after_inode" ] || fail "changed file was not replaced"
[ ! -e "$tree/a.sls.pitch-tmp" ] || fail "successful replacement left its temporary"
run_status 0 --check "$tree"
[ ! -s "$fixture_dir/stderr" ] || fail "formatted directory did not pass check"

# A second in-place run must perform no replacement at all.
steady_inode=$(file_inode "$tree/a.sls")
run_status 0 "$tree"
[ "$steady_inode" = "$(file_inode "$tree/a.sls")" ] ||
  fail "unchanged file was replaced"

cmp "$fixture_dir/ignored-before" "$tree/ignored.txt" ||
  fail "unsupported extension was modified"
cmp "$fixture_dir/hidden-before" "$tree/.hidden.sld" ||
  fail "hidden Scheme file was modified"
cmp "$fixture_dir/linked-before" "$external/linked.scm" ||
  fail "walk descended through a linked directory"

# Refusal is status 1 and leaves malformed source byte-identical.
printf '(a\n' >"$fixture_dir/refused.scm"
cp "$fixture_dir/refused.scm" "$fixture_dir/refused-before"
run_status 1 "$fixture_dir/refused.scm"
cmp "$fixture_dir/refused-before" "$fixture_dir/refused.scm" ||
  fail "refused source was modified"
[ ! -e "$fixture_dir/refused.scm.pitch-tmp" ] ||
  fail "refusal created a temporary"

# A pre-existing directory at the temporary path forces the temporary write to
# fail. The failure is status 2 and the original remains untouched.
printf '%s' "$unformatted" >"$fixture_dir/write-failure.scm"
cp "$fixture_dir/write-failure.scm" "$fixture_dir/write-failure-before"
mkdir "$fixture_dir/write-failure.scm.pitch-tmp"
printf 'block deletion\n' >"$fixture_dir/write-failure.scm.pitch-tmp/child"
run_status 2 "$fixture_dir/write-failure.scm"
cmp "$fixture_dir/write-failure-before" "$fixture_dir/write-failure.scm" ||
  fail "failed temporary write modified the original"
[ -d "$fixture_dir/write-failure.scm.pitch-tmp" ] ||
  fail "failed temporary-write fixture was unexpectedly removed"

echo "test-real-host: ok"
