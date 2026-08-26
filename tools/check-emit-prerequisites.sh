#!/bin/sh
# Fail before Pitch compilation when the selected Emit lacks the port baseline.
set -u

emit_command=${EMIT:-emit}
emit_manifest=${EMIT_MANIFEST:-}
required_revision=86669d560964b5f76c9b48529d86066c26fa6eb7

fail () {
  echo "pitch: Emit prerequisite check failed" >&2
  echo "pitch: required revision: $required_revision or newer" >&2
  echo "pitch: required capability: (emit filesystem) exporting directory-list, file-directory?, file-symbolic-link?, and replace-file" >&2
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
      '(and (choose) (char-alphabetic? #\x03bb) (eq? (char-general-category #\x2003) (quote Zs)) (pair? (command-line)) (procedure? write-shared) (procedure? directory-list) (procedure? file-directory?) (procedure? file-symbolic-link?) (procedure? replace-file))' \
    | EMIT_VERBOSITY=quiet "$emit_command" run - --manifest "$emit_manifest" 2>&1
  )
else
  probe_output=$(
    printf '%s\n' \
      '(import (scheme base) (scheme case-lambda) (scheme char) (scheme process-context) (scheme write) (emit filesystem))' \
      '(define choose (case-lambda (() #t) (args #f)))' \
      '(and (choose) (char-alphabetic? #\x03bb) (eq? (char-general-category #\x2003) (quote Zs)) (pair? (command-line)) (procedure? write-shared) (procedure? directory-list) (procedure? file-directory?) (procedure? file-symbolic-link?) (procedure? replace-file))' \
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
