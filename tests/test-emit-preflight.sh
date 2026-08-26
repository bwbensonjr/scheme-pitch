#!/bin/sh
set -u

cd "$(dirname "$0")/.."

checker=tools/check-emit-prerequisites.sh
supported_emit=${EMIT:-../emit/build/emit}
supported_manifest=${EMIT_MANIFEST:-../emit/emit-libs.scm}
fixture_dir=$(mktemp -d)
trap 'rm -rf "$fixture_dir"' EXIT HUP INT TERM

fail () {
  echo "test-emit-preflight: $1" >&2
  exit 1
}

supported_output=$(EMIT="$supported_emit" EMIT_MANIFEST="$supported_manifest" sh "$checker" 2>&1) ||
  fail "supported Emit was rejected: $supported_output"
[ -z "$supported_output" ] ||
  fail "supported Emit did not pass silently: $supported_output"

missing_output=$(EMIT="$fixture_dir/missing-emit" EMIT_MANIFEST="$supported_manifest" sh "$checker" 2>&1)
missing_status=$?
[ "$missing_status" -ne 0 ] || fail "missing Emit was accepted"
printf '%s\n' "$missing_output" | grep -q '86669d560964b5f76c9b48529d86066c26fa6eb7' ||
  fail "missing-Emit diagnostic omitted the required revision"
printf '%s\n' "$missing_output" | grep -q '(emit filesystem)' ||
  fail "missing-Emit diagnostic omitted the required capability"

cat > "$fixture_dir/old-emit" <<'EOF'
#!/bin/sh
echo "emit: unresolved import (not baked, not in the manifest): (emit filesystem)" >&2
exit 1
EOF
chmod +x "$fixture_dir/old-emit"

old_output=$(EMIT="$fixture_dir/old-emit" EMIT_MANIFEST="$supported_manifest" sh "$checker" 2>&1)
old_status=$?
[ "$old_status" -ne 0 ] || fail "older Emit was accepted"
printf '%s\n' "$old_output" | grep -q '86669d560964b5f76c9b48529d86066c26fa6eb7' ||
  fail "older-Emit diagnostic omitted the required revision"
printf '%s\n' "$old_output" | grep -q '(emit filesystem)' ||
  fail "older-Emit diagnostic omitted the required capability"

echo "test-emit-preflight: ok"
