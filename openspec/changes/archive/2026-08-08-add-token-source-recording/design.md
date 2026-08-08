## Context

`src/pitch/reader.sls` is a derived copy of laesare's `reader.sls`, pinned at tag
`v1.0.3` (commit `15a7583`). The pristine original is kept at
`vendor/laesare/reader.sls`, and `make vendor-diff` is the authoritative statement
of what the fork changes. The only change made so far is the file header and a
rename of the library to `(pitch reader)`.

The lexical analysis is what pitch wants and is the part that is expensive to get
subtly right: dialect gating on every construct, nested `#| |#` with level
counting, `#;` that recursively consumes intervening atmosphere, `#!r6rs` and
`#!fold-case` directives that mutate reader mode mid-stream, Guile's `#! !#` in
permissive mode, Unicode general-category identifier rules, peculiar identifiers,
and `->` versus `-` disambiguation. None of that should be relitigated.

What is missing is recording. Each token payload is a semantic value, so `#xff`
returns `255`, `"\x41;"` returns `"A"`, `#t` and `#true` both return `#t`, the
char-name table maps `nul`/`null`, `linefeed`/`newline`, and `esc`/`escape` onto
identical values, `|foo|` and `foo` both return the symbol `foo`, and `#;` returns
the parsed datum with the commented-out text gone.

The following were confirmed by reading the vendored source, and constrain the
design:

- Every consumed character passes through `get-char` (`src/pitch/reader.sls:83`).
  Lookahead goes through `lookahead-char`, which does not consume.
- The reader record (`src/pitch/reader.sls:113`) has no absolute offset, only
  `line`, `column`, `saved-line`, and `saved-column`. It is `(sealed #t)` and
  carries `(nongenerative reader-v0-eec5b78f-a766-4be4-9cd0-fbb52ec572dc)`.
- `get-token` (`src/pitch/reader.sls:476`) calls `reader-mark` on entry and then
  recursively tail-calls itself in 11 places, so after it returns, `saved-line`
  and `saved-column` describe the innermost mark rather than the token returned.
  Re-slicing the source from reported positions is therefore not viable.
- `get-lexeme` (`src/pitch/reader.sls:469`) is a separate consumer of `get-token`
  that skips atmosphere. It is what `read-annotated`, `read-datum`, and
  `detect-scheme-file-type` run on.
- `get-char` advances the line counter only on `#\linefeed`, while `get-comment`
  already treats `#\return`, U+0085, U+2028, and U+2029 as line endings.

## Goals / Non-Goals

**Goals:**

- Every token carries the exact source substring that produced it, plus its
  offset span and the parsed value laesare already computes.
- Concatenating token text reproduces the input byte for byte, including
  whitespace, comments, directives, shebang lines, and malformed input read in
  tolerant mode.
- The existing datum-reading API is provably unchanged, evidenced by the vendored
  test suite still passing.
- The diff stays small and legible enough to port to the `recording-tokens`
  branch as a candidate upstream contribution.

**Non-Goals:**

- The CST layer that assembles tokens into a tree.
- Any change to how laesare classifies, parses, or gates lexemes.
- Preserving source text across `read-annotated` / `read-datum`. Those keep
  returning parsed data; recording is opt-in through the token API.
- Making the recording reader allocation-free or otherwise optimized. Correctness
  first; pitch reads whole files, not streams.

## Decisions

### Record at `get-char`, not at the return sites

The naive fix is to change every return site to carry raw text alongside the
value. There are 13 `(values 'value ...)` sites alone, plus the atmosphere and
punctuation returns, and each would have to thread an accumulator by hand.

Instead, record at the single point where characters are consumed. `get-char`
gains responsibility for advancing an offset counter and appending to a text
accumulator. Every construct is then recorded automatically, and the fork does
not have to know how any individual lexeme is parsed.

*Alternative considered:* threading raw text through each return site. Rejected as
roughly forty edit sites, each an opportunity to diverge from upstream, making the
change nearly unreviewable and unportable.

### Split `get-token` into an inner lexer and a recording wrapper

Rename the existing `get-token` to `get-token*` and repoint its 11 internal
recursive tail-calls at `get-token*`. Define a new `get-token` that notes the
offset, resets the accumulator, calls `get-token*`, and returns a token record.

Bracketing only the outermost call is what makes the recursion tractable. The
inner calls keep consuming into the same accumulator, so their text is attributed
to the outer token.

The 11 recursive sites fall into four groups, and this attribution is correct or
desirable in each:

| Group | Sites | Effect on the outer span |
| --- | --- | --- |
| Error recovery in tolerant mode | 508, 517, 573, 672, 675 | Malformed prefix is retained and attributed to the token that follows, so nothing is lost |
| Directive sub-lexing (`#!name`) | 538 | Span covers `#!` plus the identifier, which is the whole directive |
| Guile `#! !#` comment | 569 | Inner result is discarded upstream, but its text is retained in the span |
| Datum comment `#;` | 520 | Span covers `#;`, intervening atmosphere, and the commented datum |

The consequence to accept: in the error-recovery and directive cases a token's raw
text may include a prefix that is not semantically part of that token. This never
loses or duplicates input, so the round-trip property is unconditional; it only
means the span is not always a minimal lexeme. That is the right trade for pitch,
which must reproduce malformed input verbatim.

### Point `get-lexeme` at `get-token*`

`get-lexeme` must call `get-token*`, not the wrapper. This is load-bearing in two
ways. It keeps the datum-reading path byte-identical in behavior to the vendored
reader, which is what makes the "API unchanged" claim provable rather than hoped
for. And it is required for correctness: the `#;` branch reads its commented datum
through `handle-lexeme`, which goes through `get-lexeme`. If that path went
through the wrapper, the accumulator would be reset partway through the `#;`
token and its recorded span would be truncated.

### Accumulate per token, not per file

The accumulator holds only the characters consumed since the current outermost
token began, and is reset when the wrapper is entered. Raw text is materialized
from it when the wrapper returns.

*Alternative considered:* accumulate the entire consumed input and slice by the
recorded start and end offsets. Simpler to describe, but it holds the whole file
in a second buffer and makes each token's text an O(n) slice of a growing
structure. The per-token accumulator gives the same result with bounded memory,
and the offsets are still recorded for callers that want to index the original
source themselves.

### Offsets are character offsets

Offsets count characters, matching what `get-char` consumes and what a caller
holding the source as a Scheme string can index. Byte-exactness is preserved for
UTF-8 input because the text is reproduced as characters and encoded once on
output; it is character-level slicing that would break under a byte offset, not
the other way around.

### Bump the nongenerative record UID

The reader record is `nongenerative` with a fixed UID. Adding fields while keeping
the UID means a previously compiled library with the old field layout can be
loaded against the new definition, which is a silent mismatch rather than a clean
error. The UID gets a new value as part of the same commit that adds the fields.

### Fix the line counter in the same change

`get-char` is already being modified, and it is the only place that can see every
consumed character. Teaching it the four additional line endings that
`get-comment` already recognizes is a few lines there and nowhere else. Splitting
it into a separate change would mean touching `get-char` twice.

## Risks / Trade-offs

- **Spans are not always minimal lexemes** (error recovery, directives) → Accepted
  and documented above; the round-trip property is unaffected. The CST layer must
  not assume a token's span contains only that token's own text.
- **The vendored test suite is the only evidence the lexer is intact, and it was
  written for `(laesare reader)`** → Adapt it as a pitch-side regression baseline
  before touching the lexer, so a green run exists to regress against, rather than
  after, when a failure is ambiguous between "my change" and "my port".
- **CRLF must count as one line ending, not two** → Requires lookahead after
  `#\return` inside `get-char`, which is the one place the change is not purely
  additive. Covered by an explicit scenario.
- **Recording adds allocation per token** → Acceptable; pitch is a formatter
  operating on files, not a hot-path parser. Revisit only if measured.
- **The change may not be acceptable upstream in this shape** → The fork stands on
  its own; upstreaming is opportunistic. Keeping the diff to a handful of named
  commits preserves the option without depending on it.
- **Rebasing onto a future upstream release** → `make vendor-verify` pins the
  comparison and `make vendor-diff` shows the changeset, so a refresh is a visible
  three-way merge rather than a guess.

## Migration Plan

There is no deployed consumer yet; pitch has no other source files. The only
compatibility surface is the reader's own API, and the plan is to keep the
two-value lexer available under `get-token*` so both shapes exist. Rollback is
`git revert` of the series, since `vendor/laesare/` is untouched throughout.

## Open Questions

- Should the token record be exported as an opaque record with accessors, or as a
  multiple-value return? A record is assumed here because five fields is past the
  point where positional values are readable, and because the CST layer will want
  to store tokens directly. Revisit if the CST layer wants something flatter.
- Should `read-annotated` optionally attach raw text to its annotations, so datum
  consumers can reach source text without dropping to the token API? Not needed
  for pitch's round-trip check and deliberately deferred.
- Does pitch want a `tokenize` convenience entry point returning a list of all
  tokens, or will the CST layer drive `get-token` itself? Deferred to the CST
  change, which has the better vantage point.
