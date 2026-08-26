#!/bin/sh
set -eu

cd "$(dirname "$0")/.."
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

awk '{ print }' tests/reader-parity-chez.sps tests/reader-parity-body.scm \
  > "$fixture_dir/authoritative.sps"
awk '{ print }' tests/reader-parity-emit.scm tests/reader-parity-body.scm \
  > "$fixture_dir/generated.scm"

chez --libdirs src:. --program "$fixture_dir/authoritative.sps" \
  > "$fixture_dir/authoritative"
EMIT_VERBOSITY=quiet emit run "$fixture_dir/generated.scm" \
  > "$fixture_dir/generated"

if ! cmp -s "$fixture_dir/authoritative" "$fixture_dir/generated"; then
  echo "test-reader-parity: authoritative and generated readers differ" >&2
  diff -u "$fixture_dir/authoritative" "$fixture_dir/generated" >&2 || true
  exit 1
fi

echo "test-reader-parity: ok"
