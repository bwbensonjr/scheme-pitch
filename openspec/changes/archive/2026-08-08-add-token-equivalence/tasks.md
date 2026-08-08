## 1. Token equivalence

- [x] 1.1 In `src/pitch/check.sls`, add a header section for layer 1 stating
      that it uses the lexer only, and why: layer 2 runs through the lexer, the
      parser and the projection, so a failure there has three possible authors
      while layer 1 has one.
- [x] 1.2 Implement the trailing-line-ending trim over a token's text: drop one
      line ending, recognizing line feed, carriage return, CR+LF, CR+NEL, NEL,
      line separator, and paragraph separator, with the two-character forms
      counting as one.
- [x] 1.3 Implement `token=?`, comparing kind and trimmed text. Do not compare
      line, column, or value.
- [x] 1.4 Implement the filtered sequence: every non-whitespace token from
      `tokenize`, in order, comments and directives interleaved with code, eof
      included.
- [x] 1.5 Define the mismatch record: index, and the token from each side, where
      either side may be absent when one sequence ran out.
- [x] 1.6 Implement `check-token-equivalence` over two source texts, returning
      whether the sequences are equivalent, the first mismatch, and the
      diagnostics from either text. Diagnostics fail the check before any
      comparison.

## 2. The combined runner

- [x] 2.1 Implement `check-output` over two source texts: collect diagnostics
      first, then run token equivalence, then datum equivalence.
- [x] 2.2 Report which layer failed, with token equivalence blamed when both
      would fail, and no layer attributed when diagnostics stopped the run
      before any layer.
- [x] 2.3 Document in the library header that round-trip and idempotence are not
      included, that round-trip compares a tree against its own input rather
      than two texts, and that the printer's change is expected to revise this.
- [x] 2.4 Export the new operations from `(pitch check)`.

## 3. Tests

- [x] 3.1 Create `tests/test-check.sps` using `(tests runner)`, following the
      structure of `tests/test-datum.sps`.
- [x] 3.2 Record the current pass count of `tests/test-datum.sps` before moving
      anything, so the move can be shown not to have dropped an assertion.
      **Baseline: 165 passing.**
- [x] 3.3 Move the four `layer2-*` groups from `tests/test-datum.sps` into
      `tests/test-check.sps` unchanged. Leave the projection, label, diagnostic,
      totality, `datum=?`, number-edge-case and differential-oracle groups where
      they are.
- [x] 3.4 `token=?` tests: equal kind and text are equivalent; differing text is
      not; differing kind with differing text is not; position does not matter.
- [x] 3.5 Trailing-line-ending tests: `(a) ; c` matches `(a) ; c\n`; comment
      content still compared exactly; a nested comment is unaffected; a shebang
      with and without its newline matches; every line ending form is trimmed.
- [x] 3.6 Whitespace-filtering tests: reindentation and reflowing are
      equivalent, including a reindented comment.
- [x] 3.7 Interleaving tests: a comment moving across a code token is caught;
      two comments exchanged are caught.
- [x] 3.8 Layer 1 catches what layer 2 cannot, one test per case: deleted
      comment, deleted `#;`, `#;` relocated to elide a different form, bracket
      flip, expanded abbreviation, radix change, escape respelling, character
      name respelling. Each of these is asserted to PASS layer 2 in
      `tests/test-check.sps`'s moved groups, so assert both here to make the
      strength difference explicit.
- [x] 3.9 Merging and swallowing tests: `(- 1)` versus `(-1)`, `(a . b)` versus
      `(a .b)`, a line comment swallowing the rest of the line, a lost closing
      delimiter.
- [x] 3.10 Mismatch-reporting tests: the first differing index is reported with
      both tokens; a dropped token reports an absent side; an equivalent pair
      reports no mismatch.
- [x] 3.11 Diagnostic tests: identical malformed texts fail rather than compare;
      a clean pair reports no diagnostics.
- [x] 3.12 Combined-runner tests: a layout-only difference passes with no layer
      blamed; a comment deletion fails at token equivalence; a datum difference
      is blamed on token equivalence rather than datum equivalence; a malformed
      text fails with diagnostics and no layer attributed.
- [x] 3.13 Add `tests/test-check.sps` to the `test` target in the `Makefile`.
- [x] 3.14 Run `make test`. Confirm the 196-test baseline is unchanged, the CST
      suite is unchanged, and the sum of the datum and check suites is at least
      the datum suite's previous count plus the new assertions — no assertion
      lost in the move. **Verified: datum 165 -> 134 (exactly the 31 moved),
      check 112 (31 moved + 81 new); 134 + 112 = 246 = 165 + 81.**
- [x] 3.15 Confirm `make vendor-verify` passes and the reader is untouched.

## 4. Documentation

- [x] 4.1 `docs/DESIGN.md` §1: state what layer 1 compares — kind and text, never
      position — and that whitespace including a token's trailing line ending is
      filtered, with the reasoning that this is not a normalization because no
      comment content changes.
- [x] 4.2 `docs/DESIGN.md` §1: record that the sequence is interleaved rather
      than split into code and comment subsequences, and that this is what
      catches a `#;` relocated to elide a different form and a comment migrating
      across a code token. Reconcile the existing "compare the comment
      subsequence in order" wording with this.
- [x] 4.3 `docs/DESIGN.md` §1: record that layer 1 depends on the lexer alone,
      which is what makes its independence from layer 2 real.
- [x] 4.4 `docs/DESIGN.md` §6: note that layer 1 catches a line comment not
      followed by a line break as missing tokens, and that the printer-time
      assertion is still wanted as the place it is diagnosed.
- [x] 4.5 `README.md`: the layer 1 row becomes shipped; name the cases that make
      it strictly stronger than layer 2; mention that layers 1 and 2 are not yet
      wired to a formatter.
- [x] 4.6 Record the carried-forward open questions in `docs/DESIGN.md`: whether
      a comment may ever move across a code token, whether `check-output` should
      grow layers 0 and 3, and whether layer 1 should report all differences
      rather than the first.
