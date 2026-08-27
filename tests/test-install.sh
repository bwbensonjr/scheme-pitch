#!/bin/sh
# Build/install from a disposable checkout, move it away, then uninstall safely.
set -eu

cd "$(dirname "$0")/.."
repo=$(pwd -P)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

run_status () {
  expected=$1
  shift
  set +e
  "$@"
  actual=$?
  set -e
  if [ "$actual" -ne "$expected" ]; then
    echo "test-install: expected status $expected, got $actual for: $*" >&2
    exit 1
  fi
}

project=$fixture_dir/project
moved_project=$fixture_dir/project-moved
prefix=$fixture_dir/prefix
mkdir -p "$project/src/pitch" "$project/tools" "$prefix/bin"

# Only the maintained Emit application inputs are staged. This prevents the
# test from succeeding through an accidental dependency on the real checkout.
cp "$repo/Makefile" "$repo/emit-libs.scm" "$project/"
cp "$repo"/src/pitch/*.sld "$project/src/pitch/"
cp "$repo/src/pitch/main.scm" "$repo/src/pitch/default-config.scm" \
  "$project/src/pitch/"
cp "$repo/tools/check-emit-prerequisites.sh" "$project/tools/"

make -C "$project" install PREFIX="$prefix" EMIT=emit
[ -x "$prefix/bin/pitch" ]
[ -x "$prefix/libexec/pitch/pitch" ]
[ -f "$prefix/libexec/pitch/default-config.scm" ]

# Moving the complete staged checkout also moves its build directory. The
# installed launcher and config must remain sufficient from an unrelated cwd.
mv "$project" "$moved_project"
mkdir "$fixture_dir/run"
cd "$fixture_dir/run"
printf '(f a b)\n' >"$fixture_dir/expected"
"$prefix/bin/pitch" --stdout <"$fixture_dir/expected" \
  >"$fixture_dir/actual" 2>"$fixture_dir/error"
cmp "$fixture_dir/expected" "$fixture_dir/actual"
[ ! -s "$fixture_dir/error" ]

# The installed launcher must preserve all three public statuses after the
# checkout and its build output have moved away.
printf '(f  a b)\n' >"$fixture_dir/run/unformatted.scm"
run_status 1 "$prefix/bin/pitch" --check "$fixture_dir/run/unformatted.scm" \
  >"$fixture_dir/check-output" 2>"$fixture_dir/check-error"
[ ! -s "$fixture_dir/check-output" ]
[ -s "$fixture_dir/check-error" ]
run_status 2 "$prefix/bin/pitch" --not-an-option \
  >"$fixture_dir/usage-output" 2>"$fixture_dir/usage-error"
[ ! -s "$fixture_dir/usage-output" ]
[ -s "$fixture_dir/usage-error" ]

# Uninstall names only Pitch-owned paths, leaving neighbors in both directories.
printf 'keep\n' >"$prefix/bin/unrelated"
printf 'keep\n' >"$prefix/libexec/pitch/unrelated"
make -C "$moved_project" uninstall PREFIX="$prefix"
[ ! -e "$prefix/bin/pitch" ]
[ ! -e "$prefix/libexec/pitch/pitch" ]
[ ! -e "$prefix/libexec/pitch/default-config.scm" ]
[ -f "$prefix/bin/unrelated" ]
[ -f "$prefix/libexec/pitch/unrelated" ]

echo "test-install: ok"
