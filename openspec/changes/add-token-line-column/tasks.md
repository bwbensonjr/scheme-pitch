Intended to land as one commit, so it can be ported to the `recording-tokens`
branch of the mirror the same way as its predecessor — with the end-of-input
column fix called out separately in that commit's message. Run `make test` and
`make vendor-verify` before and after; `vendor/laesare/` must stay untouched.

## 1. End-of-input column

- [ ] 1.1 Guard the line and column update in `get-char` on the value being a
      character, matching the existing guard on the offset and text updates, so
      the column no longer advances past end of input
- [ ] 1.2 Run the baseline suite; it must stay at **196 passed, 0 failed**. This
      is the check that nothing depended on the old end-of-input column.
- [ ] 1.3 Add a test asserting the reader's line and column are unchanged by
      reading past end of input

## 2. Token positions

- [ ] 2.1 Add `start-line`, `start-column`, `end-line`, `end-column` to the token
      record, keeping the existing `start` and `end` character offsets
- [ ] 2.2 Bump the token record's `nongenerative` UID; the layout changed. Use
      `token-v0-09440c9d-4d3c-4540-a624-43b7be9f7a40`.
- [ ] 2.3 Export the four new accessors
- [ ] 2.4 In the `get-token` wrapper, read `reader-line` and `reader-column`
      before calling `get-token*` and again after it returns, and pass all four
      into the token
- [ ] 2.5 Confirm `get-char`, `get-token*`, `get-lexeme`, `read-annotated`,
      `read-datum` and `detect-scheme-file-type` are otherwise untouched
- [ ] 2.6 Re-run both suites

## 3. Position tests

- [ ] 3.1 Add a reference procedure that walks a source string to an offset and
      returns the line and column, independent of the reader, and assert every
      token's recorded start and end positions agree with it
- [ ] 3.2 Assert the first token of a source starts at line 1, column 0
- [ ] 3.3 Cover a token confined to one line: start and end lines equal, end
      column is start column plus the token's length
- [ ] 3.4 Cover a token spanning lines, such as a nested `#| |#` comment, where
      the end column is measured from the start of its final line
- [ ] 3.5 Cover the datum comment case from the design: reading
      `(a\n  #;(b\n     c)\n  d)` must give the `#;` token a start of line 2,
      column 2, not the innermost mark at 3/6
- [ ] 3.6 Cover a `#!r6rs` directive that is not at the start of the source, and
      a malformed construct read in tolerant mode
- [ ] 3.7 Cover every line-ending form — LF, CR, CRLF, CR-NEL, NEL, U+2028,
      U+2029 — so positions agree with the line counting already in place
- [ ] 3.8 Assert the end-of-file token's start and end positions are equal, and
      match its zero-width offset span
- [ ] 3.9 Assert half-openness directly: each token's end position equals the
      next token's start position
- [ ] 3.10 Cover a token whose text ends with a line ending, such as a line
      comment: its end position is line+1, column 0

## 4. Documentation

- [ ] 4.1 Update the change list in the `src/pitch/reader.sls` header to cover
      token positions and the end-of-input column fix
- [ ] 4.2 Amend `docs/DESIGN.md` §3 "Position information": it currently says the
      reader does not capture source position, which contradicts "Text ownership"
      in the same section. State that offsets were already recorded, that line
      and column are now recorded too, and give the conventions.
- [ ] 4.3 Review `make vendor-diff` end to end and confirm it still reads as a
      reviewable changeset
- [ ] 4.4 Confirm `make vendor-verify` passes
