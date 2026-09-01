## Why

A column of hand-aligned trailing comments collapses to a single space. Reported
as issue #14:

```scheme
;; written
(define sfy-fold-limit 1073741823)              ; 2^30 - 1
(define sfy-other-limit 255)                    ; a byte
(define sfy-third 7)                            ; three bits

;; what pitch 0.1.0 produces
(define sfy-fold-limit 1073741823) ; 2^30 - 1
(define sfy-other-limit 255) ; a byte
(define sfy-third 7) ; three bits
```

No comment is lost, moved across a code token, or rewritten. Every safety layer
passes. This is not a bug in any of them; it is a question about what pitch
declares itself to preserve, and today the answer is "nothing but blank-line
runs".

**The alignment is a signal, and it is horizontal.** Three comments at one column
read as a table with three rows. The same three at ragged columns read as three
unrelated remarks. Nothing about the code changed, and yet what a reader takes
from it did — which is the definition of formatting that carries meaning. The
same argument already justified the one entry on the preserved list: a blank line
changes no code either.

**`docs/DESIGN.md` §2 is where this has to be settled, and it needs an argument
rather than a patch.** The declared-normalizations list is empty and stays empty:
no token spelling and no comment content is at stake. What is at stake is the
Preserved-formatting list, which holds exactly one entry — blank-line counts,
capped — with `; fmt: off` recorded as open. `CLAUDE.md` requires a proposal to
add an entry to that list, and this is it.

Configuration cannot reach it and should not: comment placement is not a
style-table entry, and the configuration contract explicitly excludes altering
terminal indentation.

**Impact, measured.** In Emit's 32 hand-authored sources, **372** code lines
carry a column-padded trailing comment against **7** with a single space. The
aligned column is the house convention by a factor of 53, not an artifact of
editing, and 372 sites is a visible regression in review.

## What Changes

- **The fact of alignment is preserved; the column is re-derived.** This is
  exactly how blank lines already work — the fact survives, the exact bytes do
  not. An absolute source column cannot survive reflowing, because reflowing
  changes the width of the code the column was chosen against. So pitch records
  which trailing comments the author aligned, lays the code out as it always
  would, and then aligns those comments to a column computed from the code as
  reflowed.

- **Alignment is detected as a shared column, not as padding.** A trailing
  comment is treated as aligned when a trailing comment on an adjacent source
  line begins at the same column. Counting spaces instead would not survive its
  own output: the widest line in an aligned run receives a single space, so a
  padding test would fail to re-detect that line on a second run and the run
  would break apart. A shared column re-detects itself exactly, which is what
  makes idempotence hold.

- **A new pipeline stage, between layout and verification.** The layout engine
  cannot express this: the column depends on sibling lines, which no document in
  the Πe algebra can see, and the code's own width is not known until resolution
  is done. So alignment is a pass over the rendered text. It runs *before* the
  safety checks, so that what is verified is what is written — the checks must
  never see a different text from the one that reaches the file.

- **Alignment is skipped where it would push a line past the page width.** The
  run keeps single spaces. Pitch does not buy a horizontal signal with an
  overflowing line.

- **BREAKING (output only).** Sources with aligned trailing comments now format
  differently than under 0.1.0. Token spelling and comment content are untouched,
  the declared-normalizations list stays empty, and only the whitespace between
  a code token and a `;` moves.

Deliberately out of scope, each for a reason:

- **Own-line comments.** A comment on its own line has no code to align against;
  its indentation is terminal indentation, which pitch derives and configuration
  is forbidden to alter.
- **Block comments and datum comments as trailing trivia.** They are
  inline-capable and can be followed by code on the same line, so "the comment
  ends the line" is not true of them. Line comments are the whole reported case.
- **Aligning anything else in a column** — the values in a `define` run, the
  arrows in a table of clauses. That is code reordering's cousin and pitch does
  not do it.
- **`; fmt: off`.** Still the right escape hatch for the general case and still
  open in `docs/DESIGN.md` §2. This change does not open it and does not depend
  on it.

## Capabilities

### New Capabilities

None. This adds the second entry to a list an existing capability already owns.

### Modified Capabilities

- `preserved-formatting`: gains trailing-comment column alignment as a preserved
  fact — how an aligned comment is recognized in the source, how the run and its
  column are re-derived from the reflowed output, when alignment is declined, and
  that the result is a fixed point. The capability's Purpose, which today says
  blank-line runs are "the single declared exception", changes accordingly.
- `format-pipeline`: the pipeline gains an alignment stage between layout and the
  output checks, and the requirement that the verified text is the emitted text
  becomes explicit rather than incidental.

## Impact

- `src/pitch/format.sld` — a stage between layout and `check-output`. The text
  handed to `check-output` is the text returned.
- A new `(pitch align)` library — the source-side detection, the run grouping
  over output lines, and the column arithmetic. It imports `(pitch lines)` and
  the reader's token interface, and it imports neither the document algebra nor
  the layout engine, which is what keeps this out of the engine.
- `src/pitch/doc.sld`, `src/pitch/layout.sld`, `src/pitch/cost.sld`,
  `src/pitch/print.sld`, `src/pitch/style.sld` — untouched. `make oracle-layout`
  is the check that says so.
- `tests/` — new cases for detection, re-derivation, the width refusal, the
  fixed point, and pins that own-line comments and block comments are unaffected.
- `openspec/specs/preserved-formatting/spec.md` — new requirements at sync, and
  a Purpose edit that the delta cannot carry.
- `docs/DESIGN.md` §2 and `README.md`'s preserved-formatting section — the list
  grows from one entry to two, and the README is where an adopting project reads
  it.
- Emit — unblocks the `pitch-source-formatting` one-time reformat for the 372
  sites the issue counted.
