## Why

Layers 0 and 2 are in place. Layer 1 is the one the README calls primary, and it
is the only check that can see most of what a formatter can break.

Datum equivalence passes with every comment deleted, every bracket flipped,
every abbreviation expanded, and every number respelled — those are pinned as
tests in `tests/test-datum.sps` precisely because they are weaknesses rather than
oversights. Layer 1 catches all of them, because the token sequence includes
every delimiter and every trivia token, so it determines the parse tree and
hence the datum. It is strictly stronger than layer 2 and cheap: the tokenizer
already exists and already accounts for every character.

The check was verified against the real tokenizer before being proposed. Each
of these produces a differing token sequence:

| Breakage | Caught because |
|---|---|
| `(- 1)` → `(-1)` | `-` and `1` merge into one `value` token |
| `(a . b)` → `(a .b)` | `dot` and `b` merge into one identifier |
| `(a ; c⏎ b)` → `(a ; c b)` | the comment swallows `b)`; two tokens vanish |
| a dropped comment | the `comment` token is missing |
| a dropped `)` | the `closep` token is missing |
| `[a]` → `(a)` | `openb`/`closeb` versus `openp`/`closep` |
| `'x` → `(quote x)` | one `abbrev` versus three tokens |
| `#xff` → `255`, `"\x41;"` → `"A"` | token text differs |
| a `#;` dropped, or moved to elide a different form | the `inline-comment` token is missing or out of place |
| two comments swapped | the sequence order differs |

The third row is the one that matters most. A line comment that fails to be
followed by a line break silently eats the rest of the line, and it is the most
dangerous printer bug in any Lisp formatter. Layer 1 sees it as missing tokens.

Building this now, after layer 2, also preserves the independence argument that
justifies keeping layer 2 at all: neither comparator was written against the
other's assumptions.

## What Changes

- A token-equivalence check over two source texts. Tokenize each, filter
  whitespace, and compare what remains — code tokens and comments in one
  interleaved sequence — by token kind and text.
- **Kind and text, never position.** Kind matters independently of text because
  a mode-changing directive can make the same text lex differently; `#u8(` after
  `#!r6rs` is not the token it is elsewhere. Line and column necessarily change
  under formatting and are never compared.
- **One interleaved sequence**, not separate code and comment subsequences. This
  additionally catches a comment migrating across a code token — `(a ; c⏎ b)`
  becoming `(a b ; c)` — which changes which code the comment documents and is
  therefore a meaning change, not a layout one.
- **A trailing line ending is filtered as whitespace.** A line comment's token
  text includes the line ending that terminates it, so `; c` and `; c⏎` are
  different token texts even though they differ only in whitespace. The
  comparator drops a single trailing line ending from a token's text before
  comparing. Only `comment` and `shebang` tokens can end with one; `#|...|#`
  ends with `|#`, `#;` and `#!r6rs` end with neither.

  This is not a normalization: no comment *content* is changed or ignored, so
  the declared-normalizations list stays empty. It stops a tokenization boundary
  from turning a whitespace change into a text change, and it means a printer
  may end a file with a newline even when the file ends in a comment. Line
  endings themselves are layer 0's business, where they are checked byte for
  byte.
- **A failure reports where.** The first differing index, and both tokens. The
  sequence is flat, so this is trivial here, unlike layer 2, where locating a
  difference means walking a possibly cyclic graph. Layer 1 is the check that
  will actually fire during printer development, so a precise failure is worth
  much more than a boolean.
- A combined check running layer 1 then layer 2 over the same pair of texts,
  reporting which layer failed. Layer 1 runs first: it is stronger and its
  failure is more informative.

Explicitly not in scope:

- **Layer 1 cannot run end to end**, for the same reason layer 2 cannot: there
  is no printer, so there is no output to re-read. What ships is the mechanism
  plus tests on hand-written text pairs, including the whole table above.
- The printer-time assertion that a line comment is always followed by a line
  break. `docs/DESIGN.md` §6 wants that asserted where it happens rather than
  diagnosed three layers downstream; it belongs to the printer's change. Layer 1
  catching the same bug is a backstop, not a substitute.
- Layer 3 idempotence, which needs a formatter to iterate.
- Layer 0 in the combined check. It compares a tree against its own input rather
  than two texts, so it does not share this signature; folding it in belongs
  with the printer.
- Any change to the reader, CST, parser, or datum projection. This is a new
  consumer of `tokenize`.

## Capabilities

### New Capabilities

- `token-equivalence`: the layer 1 check — what is filtered, what is compared,
  the interleaved sequence, the trailing-line-ending rule, failure reporting,
  and the requirement that it compare two texts.
- `output-verification`: the combined runner over layers 1 and 2, its ordering,
  and how it reports which layer failed. Deliberately minimal, and speculative
  until a printer gives it a caller.

### Modified Capabilities

None. `cst-construction` supplies `tokenize` and `datum-equivalence` supplies
layer 2; both are consumed unchanged.

## Impact

- `src/pitch/check.sls` — layer 1 and the combined runner join layer 2 in the
  library that already exists for verification.
- `tests/test-check.sps` — new. Layer 2's tests currently live in
  `tests/test-datum.sps`, which is where they landed when the projection and the
  check shipped together; with two checks in the library, the check tests want a
  file of their own. Layer 2's existing check tests move there unchanged, so the
  total assertion count does not drop.
- `Makefile` — the new test file joins the `test` target.
- `docs/DESIGN.md` §1 — record what layer 1 compares and the trailing-line-ending
  rule, and note that the `#;`-moved and comment-migration cases are why the
  sequence is interleaved.
- `README.md` — the layer 1 row becomes shipped, and the claim that layer 1 is
  strictly stronger than layer 2 can name the cases that make it so.
- `src/pitch/reader.sls` and `vendor/laesare/` untouched.
