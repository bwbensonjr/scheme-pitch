#!/bin/sh
# Compare the generated R7RS layout engine with the authoritative Chez source.
set -eu

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT HUP INT TERM

chez_output=$tmp_dir/chez.out
emit_output=$tmp_dir/emit.out

${CHEZ:-chez} --libdirs src:. --program tests/oracle/oracle.sps >"$chez_output"
EMIT_VERBOSITY=quiet ${EMIT:-emit} run tests/oracle/oracle-emit.scm >"$emit_output"

if ! cmp -s "$chez_output" "$emit_output"; then
  echo "layout parity: FAILED (left: Chez, right: Emit)" >&2
  diff -u "$chez_output" "$emit_output" >&2 || true
  exit 1
fi

echo "layout parity: $(head -1 "$emit_output"), all agree"
