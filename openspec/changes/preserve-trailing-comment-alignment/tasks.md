## 1. Recognition, tested against the source alone

- [x] 1.1 Add `tests/test-align-r7rs.scm` and register it with the runner
- [x] 1.2 Recognition: three consecutive lines whose trailing comments share a
      column are all aligned; a lone trailing comment is not; two padded comments
      at *different* columns are not
- [x] 1.3 An own-line comment is never aligned, whatever column it begins at, and
      an own-line comment between two aligned lines does not join the run
- [x] 1.4 A block comment, a datum comment and a directive are never aligned,
      even when two of them share a column on adjacent lines
- [x] 1.5 Recognition is correct for each of the seven line endings the reader
      counts, and for CRLF specifically, since a two-character ending is where a
      naive line scan miscounts
- [x] 1.6 A trailing comment on the first and on the last line of the file, and a
      file whose last line has no terminator

## 2. The fixed point, written before the implementation

- [x] 2.1 Issue #14's repro: three `define`s with comments aligned at one column,
      formatted twice, byte identical both times
- [x] 2.2 The case that breaks a padding rule: a run whose widest line receives a
      single space. Format, then format the output, and assert the run is
      recognized whole and the second output is identical. This is the test that
      justifies Decision 2 in `design.md` and it must be written first
- [x] 2.3 A source run that reflows into non-adjacent output lines: each piece
      aligns independently and the result is a fixed point
- [x] 2.4 Two source runs that reflow into adjacent output lines: they align as
      one run and the result is a fixed point
- [x] 2.5 A run declined for width: single spaces, and a fixed point
- [x] 2.6 A mixed file with alignable and declined runs, own-line comments and
      blank lines, formatted twice at three widths

## 3. The pass

- [x] 3.1 Add `(pitch align)` exporting one operation over source text, rendered
      text and page width, returning text
- [x] 3.2 Source side: walk the source tokens, mark each line comment as trailing
      or not, record its start column, and mark aligned by the adjacent-line
      shared-column rule. Produce one flag per line comment in source order
- [x] 3.3 Output side: tokenize the rendered text, locate each line comment's
      line, its start column and the end column of the last code token before it
      on that line
- [x] 3.4 Correspondence: if the two line-comment counts differ, return the
      rendered text unchanged and align nothing. Do not raise, do not guess a
      pairing, do not suppress the checks
- [x] 3.5 Group marked output comments into maximal runs of consecutive output
      lines; compute each run's column as one past the widest code end in the run
- [x] 3.6 Decline a run where any line would end past the page width after
      alignment; decline per run and never globally
- [x] 3.7 Rewrite only the run of spaces between the last code token and the `;`.
      Assert that no other character of the rendered text is touched
- [x] 3.8 Confirm `(pitch align)` imports none of `(pitch doc)`, `(pitch cost)`,
      `(pitch layout)`, `(pitch print)`, `(pitch style)`, and add a test asserting
      it, in the way `style-grammar`'s import test does
- [x] 3.9 `format.sld`: insert the pass between layout and `check-output`, and
      pass `check-output` the aligned text. Update the pipeline comment at the top
      of the file, which today names four stages

## 4. Verification

- [x] 4.1 The tests from sections 1 to 3 pass
- [x] 4.2 `make test` passes in full
- [x] 4.3 `make oracle-layout` reports every entry agreeing — the engine, the
      algebra and the cost factory are untouched
- [x] 4.4 Both safety layers pass over a corpus with aligned comments, and a
      deliberately corrupted alignment pass is confirmed to be *caught* by layer
      1 rather than passing silently — the pass must be inside the checked region
      and this is how that is demonstrated
- [x] 4.5 Format a file with no trailing comments using pitch built from this
      tree and from the previous commit: byte identical
- [ ] 4.6 Measure the added cost of the extra tokenization on the largest file in
      the corpus and record it against the baseline in issue #15, so it is a
      known number rather than an assumed-small one
- [x] 4.7 `make vendor-verify` is clean; `vendor/` and `src/pitch/reader.sld` are
      untouched

## 5. Acceptance against the reported case

- [x] 5.1 Reformat issue #14's repro and confirm the three comments land at one
      column derived from the reflowed code
- [x] 5.2 Reformat Emit's corpus and count how many of the 388 padded sites are
      aligned, how many are declined for width, and how many are recognized as
      unaligned. Report all three numbers; the third is the one that says whether
      the recognition rule matched the house convention
- [x] 5.3 Read the diff at a sample of sites rather than only counting, and record
      any place where the re-derived column reads worse than the author's
- [x] 5.4 Confirm pitch refuses nothing across the corpus and every file verifies

## 6. Reformat pitch's own sources

- [x] 6.1 Run `make format` over `PITCH_FORMAT_SOURCES`; record which files move
      and confirm each moved only at a trailing comment gap
- [x] 6.2 `make format-check` is a no-op afterwards
- [x] 6.3 Confirm every reformatted file is identical to its previous contents
      modulo whitespace

## 7. Documentation

- [ ] 7.1 `docs/DESIGN.md` §2: the Preserved-formatting list grows from one entry
      to two. State the recognition rule, the re-derivation, the width refusal,
      and the idempotence argument, since that argument is the whole reason the
      rule is shared-column rather than padding
- [ ] 7.2 `README.md`'s preserved-formatting section: the same two entries, in
      the terms an adopting project needs to decide
- [ ] 7.3 Confirm §2's `; fmt: off` open question still reads correctly beside a
      two-entry list, and that nothing in it implied the list would stay at one
- [ ] 7.4 At sync, edit `openspec/specs/preserved-formatting/spec.md`'s Purpose by
      hand — it says blank-line runs are "the single declared exception", and a
      delta's Purpose is ignored for an existing capability, so archiving will not
      change it
- [ ] 7.5 Comment on issue #14 with the resolution and the three counts from 5.2
