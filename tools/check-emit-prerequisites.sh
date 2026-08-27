#!/bin/sh
# Fail before Pitch compilation when the selected Emit lacks the port baseline.
set -u

emit_command=${EMIT:-emit}
emit_manifest=${EMIT_MANIFEST:-}
required_revision=41c6f43cd60d205230bc2771d2acc7a5142e0826

fail () {
  echo "pitch: Emit prerequisite check failed" >&2
  echo "pitch: required revision: $required_revision or newer" >&2
  echo "pitch: required capabilities: explicit project-manifest chaining, stable string output ports, make-eq-hash-table, and (emit filesystem) exporting directory-list, file-directory?, file-symbolic-link?, and replace-file" >&2
  if [ "$#" -gt 0 ] && [ -n "$1" ]; then
    echo "pitch: $1" >&2
  fi
  exit 1
}

if ! command -v "$emit_command" >/dev/null 2>&1; then
  fail "selected Emit executable was not found: $emit_command"
fi

if [ -n "$emit_manifest" ]; then
  probe_output=$(
    printf '%s\n' \
      '(import (scheme base) (scheme case-lambda) (scheme char) (scheme process-context) (scheme write) (emit filesystem))' \
      '(define choose (case-lambda (() #t) (args #f)))' \
      '(define retained (open-output-string))' \
      '(do ((index 0 (+ index 1))) ((= index 8)) (open-output-string))' \
      '(write-string "stable" retained)' \
      '(and (choose) (string=? (get-output-string retained) "stable") (char-alphabetic? #\x03bb) (eq? (char-general-category #\x2003) (quote Zs)) (pair? (command-line)) (procedure? write-shared) (procedure? make-eq-hash-table) (procedure? directory-list) (procedure? file-directory?) (procedure? file-symbolic-link?) (procedure? replace-file))' \
    | EMIT_VERBOSITY=quiet "$emit_command" run - --manifest "$emit_manifest" 2>&1
  )
else
  probe_output=$(
    printf '%s\n' \
      '(import (scheme base) (scheme case-lambda) (scheme char) (scheme process-context) (scheme write) (emit filesystem))' \
      '(define choose (case-lambda (() #t) (args #f)))' \
      '(define retained (open-output-string))' \
      '(do ((index 0 (+ index 1))) ((= index 8)) (open-output-string))' \
      '(write-string "stable" retained)' \
      '(and (choose) (string=? (get-output-string retained) "stable") (char-alphabetic? #\x03bb) (eq? (char-general-category #\x2003) (quote Zs)) (pair? (command-line)) (procedure? write-shared) (procedure? make-eq-hash-table) (procedure? directory-list) (procedure? file-directory?) (procedure? file-symbolic-link?) (procedure? replace-file))' \
    | EMIT_VERBOSITY=quiet "$emit_command" run - 2>&1
  )
fi
probe_status=$?

if [ "$probe_status" -ne 0 ]; then
  fail "capability probe failed: $probe_output"
fi

if [ "$probe_output" != "#t" ]; then
  fail "capability probe returned an unexpected result: $probe_output"
fi

# An explicit project manifest must still fall through to Emit's installed
# manifest for non-baked standard libraries. This is what lets every build
# target pass Pitch's absolute manifest from any working directory without
# copying installation paths into the project manifest.
manifest_probe_dir=$(mktemp -d)
trap 'rm -rf "$manifest_probe_dir"' EXIT HUP INT TERM
printf '%s\n' \
  '(import (scheme base) (scheme file))' \
  '(display (procedure? file-exists?))' \
  >"$manifest_probe_dir/probe.scm"
printf '%s\n' \
  '((program pitch-manifest-probe' \
  '          (source "probe.scm")' \
  '          (output "probe")))' \
  >"$manifest_probe_dir/emit-libs.scm"

manifest_run_output=$(EMIT_VERBOSITY=quiet "$emit_command" run \
  "$manifest_probe_dir/probe.scm" \
  --manifest "$manifest_probe_dir/emit-libs.scm" 2>&1)
manifest_run_status=$?
if [ "$manifest_run_status" -ne 0 ] || [ "$manifest_run_output" != "#t" ]; then
  fail "explicit project-manifest run probe failed: $manifest_run_output"
fi

manifest_build_output=$(EMIT_VERBOSITY=quiet "$emit_command" build \
  pitch-manifest-probe \
  --manifest "$manifest_probe_dir/emit-libs.scm" \
  -o "$manifest_probe_dir/probe" 2>&1)
manifest_build_status=$?
if [ "$manifest_build_status" -ne 0 ]; then
  fail "explicit project-manifest build probe failed: $manifest_build_output"
fi

manifest_executable_output=$("$manifest_probe_dir/probe" 2>&1)
manifest_executable_status=$?
if [ "$manifest_executable_status" -ne 0 ] || [ "$manifest_executable_output" != "#t" ]; then
  fail "explicit project-manifest executable probe failed: $manifest_executable_output"
fi
