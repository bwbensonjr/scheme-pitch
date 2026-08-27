#!/bin/sh
# Prove the shipped Emit application builds and formats stdin without Chez.
set -eu

cd "$(dirname "$0")/.."
repo=$(pwd -P)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

# Remove every PATH component that supplies a `chez` executable while retaining
# the ordinary compiler/linker tools and the installed Emit command.
without_chez=
old_ifs=$IFS
IFS=:
for directory in $PATH; do
  [ -n "$directory" ] || directory=.
  if [ -x "$directory/chez" ]; then
    continue
  fi
  if [ -z "$without_chez" ]; then
    without_chez=$directory
  else
    without_chez=$without_chez:$directory
  fi
done
IFS=$old_ifs
PATH=$without_chez
export PATH

if command -v chez >/dev/null 2>&1; then
  echo "test-no-chez: chez remains on PATH" >&2
  exit 1
fi
command -v emit >/dev/null 2>&1 || {
  echo "test-no-chez: emit was removed with chez" >&2
  exit 1
}

cd "$fixture_dir"
EMIT_VERBOSITY=quiet emit build pitch \
  --manifest "$repo/emit-libs.scm" \
  -o "$fixture_dir/pitch"
cp "$repo/src/pitch/default-config.scm" "$fixture_dir/default-config.scm"

printf '(f a b)\n' >"$fixture_dir/expected"
"$fixture_dir/pitch" --stdout <"$fixture_dir/expected" \
  >"$fixture_dir/actual" 2>"$fixture_dir/error"
cmp "$fixture_dir/expected" "$fixture_dir/actual"
[ ! -s "$fixture_dir/error" ] || {
  echo "test-no-chez: stdin smoke test wrote a diagnostic" >&2
  exit 1
}

echo "test-no-chez: ok"
