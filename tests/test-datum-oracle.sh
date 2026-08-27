#!/bin/sh
# Compare independent serialized Chez host-reader and Emit Pitch projections.
set -eu

cd "$(dirname "$0")/.."
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

chez --program tests/oracle/datum-host.sps >"$fixture_dir/host"
EMIT_VERBOSITY=quiet emit run tests/oracle/datum-emit.scm \
  >"$fixture_dir/pitch"

if ! cmp "$fixture_dir/host" "$fixture_dir/pitch"; then
  echo "datum oracle: FAILED (left: Chez host read, right: Pitch projection)" >&2
  diff -u "$fixture_dir/host" "$fixture_dir/pitch" >&2 || true
  exit 1
fi

echo "datum oracle: serialized outputs agree"
