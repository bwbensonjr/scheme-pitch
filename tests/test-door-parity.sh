#!/bin/sh
# Compare the Emit development and standalone doors over the complete CLI matrix.
set -eu

cd "$(dirname "$0")/.."
repo=$(pwd -P)
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

case_dir=$fixture_dir/case
unformatted='(define (f x)
(g x))
'

fail () {
  echo "test-door-parity: $1" >&2
  exit 1
}

prepare_case () {
  name=$1
  rm -rf "$case_dir"
  mkdir -p "$case_dir"
  : >"$fixture_dir/$name.stdin"
  case $name in
    stdin)
      printf '(f\n a b)\n' >"$fixture_dir/$name.stdin"
      ;;
    stdout|check|in-place)
      printf '%s' "$unformatted" >"$case_dir/input.scm"
      ;;
    config-error)
      printf '%s' "$unformatted" >"$case_dir/input.scm"
      printf '(pitch-config 999)\n' >"$case_dir/bad-config.scm"
      ;;
    malformed)
      printf '(a\n' >"$case_dir/bad.scm"
      ;;
    multi-file)
      printf '(a\n' >"$case_dir/bad.scm"
      printf '%s' "$unformatted" >"$case_dir/good.scm"
      ;;
    directory)
      mkdir "$case_dir/tree" "$case_dir/tree/sub"
      printf '%s' "$unformatted" >"$case_dir/tree/b.scm"
      printf '%s' "$unformatted" >"$case_dir/tree/a.sls"
      printf '%s' "$unformatted" >"$case_dir/tree/sub/c.ss"
      printf '%s' "$unformatted" >"$case_dir/tree/ignored.txt"
      ;;
  esac
}

invoke () {
  door=$1
  name=$2
  stdout_path=$fixture_dir/$door-$name.stdout
  stderr_path=$fixture_dir/$door-$name.stderr
  status_path=$fixture_dir/$door-$name.status

  case $name in
    help) set -- --help ;;
    version) set -- --version ;;
    stdin) set -- - ;;
    stdout) set -- --stdout "$case_dir/input.scm" ;;
    check) set -- --check "$case_dir/input.scm" ;;
    in-place) set -- "$case_dir/input.scm" ;;
    config-error) set -- --config "$case_dir/bad-config.scm" "$case_dir/input.scm" ;;
    malformed) set -- "$case_dir/bad.scm" ;;
    multi-file) set -- "$case_dir/bad.scm" "$case_dir/good.scm" ;;
    directory) set -- "$case_dir/tree" ;;
    *) fail "unknown case $name" ;;
  esac

  set +e
  if [ "$door" = dev ]; then
    EMIT_VERBOSITY=quiet emit run "$repo/src/pitch/main.scm" \
      --manifest "$repo/emit-libs.scm" -- "$@" \
      <"$fixture_dir/$name.stdin" >"$stdout_path" 2>"$stderr_path"
  else
    "$repo/build/pitch" "$@" \
      <"$fixture_dir/$name.stdin" >"$stdout_path" 2>"$stderr_path"
  fi
  status=$?
  set -e
  printf '%s\n' "$status" >"$status_path"
}

for name in help version stdin stdout check in-place config-error malformed multi-file directory; do
  prepare_case "$name"
  invoke dev "$name"
  cp -R "$case_dir" "$fixture_dir/dev-$name.effects"

  prepare_case "$name"
  invoke aot "$name"

  cmp "$fixture_dir/dev-$name.status" "$fixture_dir/aot-$name.status" ||
    fail "$name exit statuses differ"
  cmp "$fixture_dir/dev-$name.stdout" "$fixture_dir/aot-$name.stdout" ||
    fail "$name standard output differs"
  cmp "$fixture_dir/dev-$name.stderr" "$fixture_dir/aot-$name.stderr" ||
    fail "$name standard error differs"
  diff -r "$fixture_dir/dev-$name.effects" "$case_dir" >/dev/null ||
    fail "$name filesystem effects differ"
  echo "test-door-parity: $name ok"
done

echo "test-door-parity: ok"
