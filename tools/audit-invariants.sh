#!/bin/sh
# Reject implementation surfaces that violate Pitch's cross-layer invariants.
set -u

files=$(find src/pitch -type f -name '*.sld' -print | sort)
[ -n "$files" ] || {
  echo "audit-invariants: no maintained .sld libraries found" >&2
  exit 1
}

reject () {
  description=$1
  pattern=$2
  shift 2

  matches=$(rg -n -e "$pattern" "$@" 2>/dev/null)
  status=$?

  if [ "$status" -eq 0 ]; then
    echo "audit-invariants: $description" >&2
    printf '%s\n' "$matches" >&2
    exit 1
  fi

  if [ "$status" -ne 1 ]; then
    echo "audit-invariants: search failed while checking $description" >&2
    exit 1
  fi
}

# No maintained library selects an implementation or language surface at
# expansion time. Dialect is inert edge data, not a compilation branch.
# Word splitting is intentional: maintained source paths contain no spaces.
# shellcheck disable=SC2086
reject "conditional implementation or dialect branch found" \
  'cond-expand' $files

# The permissive CST and layout layers cannot depend on the output dialect.
reject "dialect branch found below the configuration/translation edge" \
  '\(config-dialect([[:space:]]|\))|\((case|cond|if)[^;]*(dialect|r6rs|r7rs)' \
  src/pitch/cst.sld src/pitch/layout.sld

# Runtime source text is parsed only by Pitch's reader.
# shellcheck disable=SC2086
reject "host reader or evaluator call found" \
  '\((read|eval|load)([[:space:]]|\))|\(scheme (read|eval|load)\)' $files

# Output spelling is lossless. These modules may rederive whitespace and strip
# a line-comment terminator for token comparison, but may not normalize token
# or comment contents.
reject "undeclared output normalization found" \
  '\((normalize|normalization|declare-normalization)([[:space:]]|\))|(string|char)-(downcase|upcase|foldcase)' \
  src/pitch/check.sld src/pitch/format.sld src/pitch/print.sld

# Configuration is parsed as inert data and never evaluated or loaded.
reject "executable configuration surface found" \
  '\(scheme (eval|load|process-context)\)|interaction-environment|scheme-report-environment' \
  src/pitch/config.sld

# Filesystem and process capabilities belong only in the real-host
# program adapter. The host-independent library graph receives operations
# through (pitch cli)'s host record.
# shellcheck disable=SC2086
reject "direct operating-system access found below the real-host edge" \
  '\(scheme (file|process-context)\)|\(emit filesystem\)|\((open-input-file|open-output-file|call-with-input-file|call-with-output-file|delete-file|file-exists\?|directory-list|file-directory\?|file-symbolic-link\?|replace-file|command-line|exit|emergency-exit|system)([[:space:]]|\))' \
  $files

echo "audit-invariants: ok"
