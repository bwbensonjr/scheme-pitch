#!/bin/sh
# Byte-level fixtures for tests/test-text-files-r7rs.scm.
set -eu

cd "$(dirname "$0")/.."

fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

# UTF-8 lambda/cafe, with CRLF line endings.
printf '(display "\316\273")\r\n; caf\303\251\r\n' >"$fixture_dir/raw-input.scm"
printf '(define \316\273 "caf\303\251")\r\n\316\273\r\n' >"$fixture_dir/accepted.scm"

# Unsupported endings within token text: CRLF in a string, and U+2028 in a
# block comment. The output sentinels must remain byte-identical.
printf '(display "a\r\nb")\r\n' >"$fixture_dir/interior-crlf.scm"
printf '(a #| before\342\200\250after |# b)\n' >"$fixture_dir/interior-unicode.scm"
printf 'sentinel\n' >"$fixture_dir/interior-crlf-output.scm"
printf 'sentinel\n' >"$fixture_dir/interior-unicode-output.scm"

build/test-text-files-r7rs "$fixture_dir"

cmp "$fixture_dir/raw-input.scm" "$fixture_dir/raw-output.scm"
printf '(define \316\273 "caf\303\251")\n\316\273\n' >"$fixture_dir/accepted-expected.scm"
cmp "$fixture_dir/accepted-expected.scm" "$fixture_dir/accepted-output.scm"
printf 'sentinel\n' >"$fixture_dir/sentinel-expected"
cmp "$fixture_dir/sentinel-expected" "$fixture_dir/interior-crlf-output.scm"
cmp "$fixture_dir/sentinel-expected" "$fixture_dir/interior-unicode-output.scm"

echo "test-text-files: byte comparisons ok"
