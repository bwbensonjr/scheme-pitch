#!/bin/sh
# Reject legacy R6RS surfaces from maintained R7RS application libraries.
set -u

chez_command=${CHEZ:-chez}
reader_source=src/pitch/reader.sls
reader_generator=tools/generate-reader.sps

# reader.sld is checked through the syntax-aware generator audit below. A text
# search cannot distinguish its quoted dialect names (such as rnrs and r6rs)
# from executable imports or identifiers.
files=$(find src/pitch -type f -name '*.sld' ! -name 'reader.sld' -print | sort)
[ -n "$files" ] || {
  echo "audit-r7rs: no maintained .sld libraries found" >&2
  exit 1
}

legacy_pattern='#!r6rs|\(rnrs|define-condition-type|make-(message|who|irritants)-condition|message-condition\?|condition-message|assertion-violation|make-eq(v)?-hashtable|hashtable-|\(rnrs sorting|\bremp\b|\bbitwise-|\bfx[a-z?+*/<=>!-]*\b|make-transcoder|utf-8-codec|eol-style|error-handling-mode'

# Word splitting is intentional: maintained source paths contain no spaces.
# shellcheck disable=SC2086
matches=$(rg -n -e "$legacy_pattern" $files 2>/dev/null)
status=$?

if [ "$status" -eq 0 ]; then
  echo "audit-r7rs: legacy portability surface found" >&2
  printf '%s\n' "$matches" >&2
  exit 1
fi

if [ "$status" -ne 1 ]; then
  echo "audit-r7rs: search failed" >&2
  exit 1
fi

if ! "$chez_command" --program "$reader_generator" --audit "$reader_source"; then
  echo "audit-r7rs: authoritative reader is outside the closed generator mapping" >&2
  exit 1
fi

echo "audit-r7rs: ok"
