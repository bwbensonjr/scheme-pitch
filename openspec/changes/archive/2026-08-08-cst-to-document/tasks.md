## 1. `verbatim` in the document algebra

- [x] 1.1 Add `verbatim` to `src/pitch/doc.sls`: split at the endings
      `line-ending-char?` already recognizes, treating CR LF and CR NEL as one,
      and join the pieces with `hard-nl` under `reset`; return `(text s)`
      unchanged when there is no ending
- [x] 1.2 Export `verbatim` and note in the library header why it lives here
      rather than in the printer — one definition of "line ending", and it is the
      sanctioned answer to `text`'s refusal
- [x] 1.3 Extend `tests/test-doc.sps`: no-ending case, two-line case, all seven
      endings, no indentation added under `nest` and under `align`, interior
      characters untouched, and `(group (verbatim "ab\ncd"))` having no flat
      alternative

## 2. The translation skeleton

- [x] 2.1 Create `src/pitch/print.sls` exporting `cst->document`, importing
      `(pitch cst)` and `(pitch doc)` and nothing else; the header states that it
      reads token text and whitespace only, never a token position
- [x] 2.2 Emit a leaf as `(verbatim (leaf-text l))`
- [x] 2.3 Write the item sequencer: fold a child list into items carrying a
      document, a preceding blank-line count, and whether the item ends in a
      forced break
- [x] 2.4 Classify each trivia child from the intervening whitespace text —
      attached when no line ending separates it from the preceding datum, its own
      item otherwise
- [x] 2.5 Join items with `nl`, emitting no separator after an item that ends in
      a forced break, and assert that invariant at the join
- [x] 2.6 Create `tests/test-print.sps` and add it to the `test` target in the
      `Makefile`

## 3. Node kinds

- [x] 3.1 Compound: opening delimiter from its token, items inside an `align`,
      closing delimiter trailing the last item, and nothing emitted for an absent
      close
- [x] 3.2 Compound: the three alternatives — flat, aligned, hanging with an
      indent of 2 — with the aligned-versus-hanging tie-break independent of the
      resolver's frontier order. Done structurally rather than with the `cost`
      penalty the design proposed: hanging is always exactly one line taller
      than aligned, so an objective ranking overflow before height already picks
      aligned unless hanging strictly reduces overflow. `(cost n d)` takes a
      value in the cost factory's own representation, so a penalty would have
      coupled the translation to one factory
- [x] 3.3 Compound: put the closing delimiter on its own line, at the node's own
      indentation, when the last item ends in a forced break
- [x] 3.4 Prefix: marker concatenated to datum with no break opportunity; marker
      alone when the datum is absent; trivia between them sequenced normally
- [x] 3.5 List: bind the `.` leaf to the item that follows it, spaced on both
      sides, with no break between them
- [x] 3.6 Document: top-level items, and `error`: emit its leaves so the
      translation stays total on malformed trees
- [x] 3.7 Add `compound-shape`, returning one generic shape for every node
      without examining it, and route every compound through it — the single
      point a style table will later be consulted from

## 4. Comment placement

- [x] 4.1 `comment-doc`: strip exactly one trailing line ending (two-character
      forms counting as one), then `(concat (verbatim stripped) hard-nl)`, with
      no branch that omits the break and a break emitted for a comment ending the
      source
- [x] 4.2 Attach a same-line comment to its preceding item with a non-breakable
      space
- [x] 4.3 Emit block comments, `#;` and directives as ordinary items with no
      forced break; emit a shebang first and followed by a break
- [x] 4.4 Tests: trailing stays trailing across a break, own-line stays own-line,
      a comment before the close pushes the close down, `#;(b    c)` keeps its
      interior, a form with a line comment has no flat layout, and a trailing
      comment that overflows the width is still attached

## 5. Preserved formatting

- [x] 5.1 Count blank lines as a whitespace leaf's line endings less one, floored
      at zero
- [x] 5.2 Cap at one inside a compound and two at top level, and emit a preserved
      run as additional `hard-nl`s before the following item
- [x] 5.3 Drop leading and trailing blank lines; end the document with exactly
      one line ending
- [x] 5.4 Tests: each cap at and above its limit, a single line ending producing
      no blank line, a preserved blank line suppressing the flat layout, and
      indentation and space runs discarded

## 6. The pipeline

- [x] 6.1 Create `src/pitch/format.sls` exporting `format-source` and the
      `format-result` record (status, detail, tainted?), returning two values the
      way `layout` does
- [x] 6.2 Stage 1: tokenize and parse; a non-empty diagnostics list returns
      `unclean-parse` with no text
- [x] 6.3 Stage 2: screen tokens for an interior line ending other than the one
      the engine emits; return `unsupported-line-ending` with the offending token
      and no text
- [x] 6.4 Stage 3: translate and lay out at the requested width, defaulting to
      88, carrying the taint flag through without treating it as a failure
- [x] 6.5 Stage 4: run `check-output` over the input text and the produced text;
      on failure return `check-failed` with the layer and detail and **no text**
- [x] 6.6 Create `tests/test-format.sps` and add it to the `test` target

## 7. Verification

- [x] 7.1 Tests for each refusal path: unclosed delimiter, stray close, CRLF
      inside a block comment, and a CRLF-delimited file with no multi-line token
      formatting successfully
- [x] 7.2 A test that deliberately breaks the translation and confirms the check
      catches it and suppresses the output — evidence the wiring is not vacuous
- [x] 7.3 Idempotence: format twice over a corpus of hand-written cases at
      several widths, byte-comparing the results
- [x] 7.4 Idempotence and success over every `.sls` and `.sps` file in the
      repository, as the first real-input corpus
- [x] 7.5 Time the largest in-repo source file end to end and record the figure.
      `src/pitch/reader.sls`, 47KB: parse 1ms, translate 33ms, layout 2027ms,
      check 29ms. Layout is ~98% of it and scales roughly linearly, at about
      20KB of source per second. The design's proposed fallback — lay out each
      top-level form separately — was measured and **does not apply**: an R6RS
      library is a single top-level form, so `reader.sls` has exactly one and
      splitting saves nothing. Recorded rather than optimized; see the corrected
      risk entry in `design.md`
- [x] 7.6 `make test` green, `make vendor-verify` green, and `make oracle-layout`
      still agreeing after the `verbatim` addition

## 8. Documentation

- [x] 8.1 `docs/DESIGN.md` §6: record the printer assertion as discharged and by
      what construction; §2: record the blank-line rule as specified; §1: answer
      the open question about the combined runner by recording that the pipeline
      owns layers 0 and 3 and the runner stays the two-text pair
- [x] 8.2 `docs/DESIGN.md`: add the foreign-interior-line-ending refusal and the
      open question it leaves — whether `(pitch doc)` should carry a line ending
- [x] 8.3 `README.md`: the architecture diagram's middle stage is real, layer 3
      moves to shipped, the "not wired end to end" note comes out, and
      `print.sls` and `format.sls` join the repository-layout listing
- [x] 8.4 `README.md` and `docs/DESIGN.md`: state plainly that one generic shape
      ships and that per-form style is the next change, so nobody reads the
      current output as pitch's intended style
