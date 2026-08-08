## Why

Tokens carry exact character offsets but no line or column. Every consumer that
reports a source location to a human — and `docs/DESIGN.md` commits to one, since
malformed input means the CLI refuses to format and reports the position — would
have to convert offsets itself, either by scanning the source per lookup or by
building and maintaining a line index.

The reader can supply this exactly and almost for free. The `get-token` wrapper
already runs immediately before `get-token*`, at the same point upstream's
`reader-mark` fires and before any character of the token is consumed, so
`reader-line` and `reader-column` there are the token's true start.

There is also a live trap. `reader-saved-line` and `reader-saved-column` look
like they give a token's position, and for tokens that involve no recursion they
do. But `get-token*` recurses into itself on the `#;`, directive and
error-recovery paths, so after such a token is returned those fields hold the
innermost mark. Reading `(a\n  #;(b\n     c)\n  d)` yields a datum-comment token
whose true start is line 2, column 2, while `reader-saved-line`/`-column` report
3/6. Being right most of the time is what makes this worth closing now.

Doing it before the CST design matters: the token record is a published shape,
and adding fields once the CST destructures tokens is a second breaking change
and a second UID bump.

## What Changes

- The token record gains `start-line`, `start-column`, `end-line`, and
  `end-column`. The wrapper reads the reader's line and column before calling
  `get-token*` and again after it returns.
- Positions are correct for every token kind, including the recursive paths where
  `reader-saved-line`/`-column` are not. The wrapper brackets the outermost call,
  so nesting cannot displace a recorded position.
- The existing `start` and `end` character offsets stay. They are what the CST's
  text-ownership decision depends on, and they remain the cheapest way to slice
  the source.
- Line and column conventions become normative rather than incidental: line is
  1-based, column is 0-based, and a position denotes the next character to be
  consumed. These are already what the reader uses for annotations.
- **BREAKING** for direct consumers of the token record: its shape changes and
  its `nongenerative` UID is bumped. `get-token*` and the datum-reading path are
  untouched.

Explicitly not in scope: the CST layer; any change to `get-token*` or to how
lexemes are classified; and whether `read-annotated`'s annotations are themselves
skewed on nested constructs, which is pre-existing upstream behavior on a path
this change does not touch.

## Capabilities

### New Capabilities

None. This extends what the reader already records.

### Modified Capabilities

- `token-source-recording`: the token record's enumerated contents change to
  include the line and column of both ends of the token, and a new requirement
  covers the positions themselves, including their correctness on the recursive
  lexer paths.
- `reader-source-position`: adds a requirement fixing the line and column
  conventions, which the existing requirements assume but never state.

## Impact

- `src/pitch/reader.sls` — the token record definition, its UID, the export list,
  and the `get-token` wrapper. `get-char`, `get-token*`, `get-lexeme`,
  `read-annotated`, `read-datum` and `detect-scheme-file-type` are unchanged.
- `tests/test-recording.sps` — new position coverage. The vendored baseline in
  `tests/test-reader.sps` must keep passing at 196, unchanged.
- `docs/DESIGN.md` §3 — the "Position information" subsection states that the
  reader does not capture source position, which contradicts "Text ownership" in
  the same section describing `token-start`/`token-end`. It needs to say line and
  column specifically, and to record what this change settles.
- `vendor/laesare/` untouched; `make vendor-diff` remains the changeset and
  `make vendor-verify` must keep passing.
- The change should stay legible as a single commit so it can be ported to the
  `recording-tokens` branch of the GitHub mirror the same way as its predecessor.
