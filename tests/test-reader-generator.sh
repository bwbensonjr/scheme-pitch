#!/bin/sh
set -u

cd "$(dirname "$0")/.."
generator=tools/generate-reader.sps
source=src/pitch/reader.sls
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

chez --program "$generator" --self-test "$source" || exit 1
chez --program "$generator" "$source" "$fixture_dir/first.sld" || exit 1
chez --program "$generator" "$source" "$fixture_dir/second.sld" || exit 1

cmp "$fixture_dir/first.sld" "$fixture_dir/second.sld" || {
  echo "test-reader-generator: output is not deterministic" >&2
  exit 1
}

grep -q '^;;; GENERATED FILE -- DO NOT EDIT$' "$fixture_dir/first.sld" || {
  echo "test-reader-generator: generated header is missing" >&2
  exit 1
}

echo "test-reader-generator: ok"
