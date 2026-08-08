## Why

Pitch's Layer 0 correctness check is byte-exact round-tripping: reading a source
file and re-emitting it unchanged before any formatting decision is applied. The
vendored laesare reader cannot support that check, because every token payload it
returns is a semantic value rather than source text. The lexical analysis itself
is exactly what pitch needs and is the expensive part to get right; only the
recording is missing.

The information is destroyed inside `get-token` before control returns to the
caller, so no external wrapper can recover it. Re-slicing the source from
positions does not work either: the reader tracks no absolute offset, and
`get-token` marks its position on entry and then recursively tail-calls itself,
so the saved line and column describe the innermost mark rather than the token
actually returned.

## What Changes

- Add absolute offset tracking and a source-text accumulator to the reader,
  updated at the single point where characters are consumed.
- Split the existing `get-token` into an unchanged inner lexer and a thin
  recording wrapper, so that every token returned to a caller carries the exact
  source substring that produced it, along with its start and end offsets and the
  parsed value laesare already computed.
- Preserve the parsed value on every token. Raw text drives printing; the parsed
  value drives datum-equivalence checking. The fork records alongside laesare's
  lexical decisions rather than relitigating any of them.
- Correct the line counter so line and column stay accurate for `#\return`,
  U+0085, U+2028, and U+2029 line endings, which the comment lexer already
  recognizes but the character reader does not.
- **BREAKING** for direct `get-token` callers: the exported `get-token` returns a
  token record instead of two values. `read-annotated`, `read-datum`,
  `detect-scheme-file-type`, and the rest of the public API are unchanged, and
  the existing two-value lexer remains available under a new name.

Explicitly not in scope: the CST layer that assembles tokens into a tree, the
layout engine, and any change to how laesare classifies or parses lexemes.

## Capabilities

### New Capabilities

- `token-source-recording`: Every token returned by the reader carries the exact
  source substring that produced it, its offset span, and its parsed value, such
  that concatenating the raw text of all tokens reproduces the input byte for
  byte. Includes the compatibility guarantee that the existing datum-reading API
  is unaffected.
- `reader-source-position`: The reader tracks an absolute character offset, and
  reports line and column correctly for every line ending recognized by the
  R6RS/R7RS grammars, not only line feed.

### Modified Capabilities

None. `openspec/specs/` is currently empty; this change introduces the project's
first capabilities.

## Impact

- `src/pitch/reader.sls` - the derived reader. All changes land here.
- `vendor/laesare/` - untouched. `make vendor-diff` remains the authoritative
  statement of the fork's changeset, and `make vendor-verify` must keep passing.
- New pitch-side test suite, seeded from `vendor/laesare/tests/test-reader.sps`,
  which serves as the regression baseline proving the vendored lexical analysis
  still behaves identically.
- Downstream: unblocks the lossless lexer to CST step and the round-trip and
  idempotence checks described in the README architecture.
- The resulting diff is intended to be portable to the `recording-tokens` branch
  of the GitHub mirror as a candidate upstream contribution, so it should stay
  legible as a small series of named commits.
