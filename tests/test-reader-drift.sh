#!/bin/sh
set -u

cd "$(dirname "$0")/.."
generated=src/pitch/reader.sld
fixture_dir=$(mktemp -d)
cp "$generated" "$fixture_dir/reader.sld"
trap 'cp "$fixture_dir/reader.sld" "$generated"; rm -rf "$fixture_dir"' EXIT HUP INT TERM

make reader-check >/dev/null || exit 1
printf '\n;;; injected drift\n' >> "$generated"

if make reader-check >/dev/null 2>&1; then
  echo "test-reader-drift: changed artifact was not detected" >&2
  exit 1
fi

make reader-generate || exit 1
cmp "$fixture_dir/reader.sld" "$generated" || {
  echo "test-reader-drift: regeneration did not restore exact output" >&2
  exit 1
}
make reader-check >/dev/null || exit 1

echo "test-reader-drift: ok"
