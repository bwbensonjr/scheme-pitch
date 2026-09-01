## Context

See `proposal.md` — Why. What follows is the current state that shapes the
approach.

The pipeline in `src/pitch/format.sld` is four stages, and stage 4 is the one
that constrains everything here:

```scheme
;; Stage 3.
(let-values (((output result) (layout (cst->document tree table)
                                      (default-cost-factory width))))
  ;; Stage 4. Two texts: the one that came in, and the one just produced.
  ;; Never the tree either was built from.
  (let-values (((ok? layer detail) (check-output source output)))
    ...))
```

`check-output` takes two source *texts* and cannot be handed a tree. That is
deliberate — `docs/DESIGN.md` §1 calls comparing a tree against itself the
vacuousness trap — and it is what makes the placement of a new stage a real
decision rather than a detail.

Three facts about the layout engine decide the shape of the answer:

- A `pretty-expressive` document is resolved bottom-up against a cost factory. A
  node cannot see its siblings' final columns, so "the same column as the line
  above" is not expressible as a document.
- The code's own width is not known until resolution finishes. A column computed
  before layout would be computed against the wrong code.
- `(pitch doc)`, `(pitch cost)` and `(pitch layout)` know nothing about Scheme —
  no tokens, no comments, no brackets. Teaching one of them about comment
  columns would break the layering invariant outright.

Two facts about the reader make the source side cheap: every token carries its
exact text, its offset span, and the **line and column of both ends** of that
span (`token-source-recording`), for all seven recognized line endings
(`reader-source-position`). So "which trailing comments share a column with an
adjacent line's" is a scan over the token vector, not a re-derivation.

Constraints that bear:

- `CLAUDE.md`: every check compares against text re-read from the formatter's
  output; the declared-normalizations list is empty; configuration never alters
  terminal indentation.
- `format-pipeline` requires idempotence over the whole corpus at any width.
- `comment-placement` already guarantees a trailing comment stays on its line and
  never crosses a code token, so a comment that was trailing in the source is
  still trailing in the output.

## Goals / Non-Goals

**Goals:**

- The alignment decision is made in one place, from three inputs — the source
  text, the rendered text, and the page width — and from nothing else.
- The layout engine, the document algebra, the cost factory and the CST
  translation are untouched, and `make oracle-layout` is the evidence.
- Idempotence is a consequence of the recognition rule, not a property patched in
  afterwards.

**Non-Goals:**

- Making the layout engine aware of columns across lines. It cannot be, and this
  design does not want it to be.
- Any alignment beyond trailing line comments. See `proposal.md` — What Changes.
- Recovering an author's column when the code reflowed. The column is re-derived;
  see Decision 2.

## Decisions

### 1. A pass over the rendered text, between layout and verification

Alignment is stage 3.5: it takes the source text, the rendered text and the
width, and returns rendered text with some gaps widened. It runs before
`check-output`, so the verified text is the emitted text.

*Why over the alternatives:*

- **A new document primitive.** Rejected: the column depends on sibling lines,
  which the Πe algebra cannot express, and adding it would put Scheme's comment
  conventions inside an engine that deliberately knows no Scheme. It would also
  put pitch and the reference implementation on different algebras, which
  `make oracle-layout` exists to prevent.
- **Encoding the column in the cost factory.** Rejected for the same reason and
  one more: a cost is a value in the factory's own representation, and the
  translation must not build one.
- **A pass after verification.** Rejected outright. It would return text nothing
  had checked while still reporting success — the exact failure the check
  apparatus exists to prevent. The new `format-pipeline` requirement states this
  so that a later edit has to argue with a spec rather than with a comment.

The cost is that alignment can turn a passing format into a check failure. That
is the correct failure mode and it is cheap to reason about: the pass only widens
a run of spaces between two tokens, so layer 1 compares the same token sequence
and layer 2 the same data. If it ever does fail, something is genuinely wrong.

### 2. Recognition by shared column, application by re-derived column

Detection happens on the **source**, because the rendered text has no alignment
in it to detect — the printer emits one space everywhere. Application happens on
the **output**, because that is where the code's real widths are.

A trailing line comment is *aligned* when an adjacent source line's trailing
comment begins at the same column. Then, over output lines, maximal runs of
consecutive lines ending in aligned trailing comments are formed, and each run's
comments go to one column: one past the widest code in the run.

*Why shared column rather than "two or more spaces", which is how issue #14
counts the sites:* the padding test does not survive its own output. Align a run
whose code widths are 20, 30 and 25 at column 31 and line two receives a single
space. Format that output again: the padding test does not recognize line two,
the run splits into two runs of one, and both collapse back to single spaces.
**Not idempotent**, and idempotence is a shipped requirement. Shared column
re-detects the run exactly, because after alignment all three comments begin at
column 31.

A rejected repair for the padding rule: align to *two* past the widest code, so
every line of a run is padded. It restores idempotence but the extra column is
arbitrary, and it leaves a lone padded comment padded forever, which reads as a
bug. Shared column needs no such constant.

*Why a run of one needs no special case:* one past the widest code in a run of
one is one space, which is what an unaligned comment gets. The formula covers it.

### 3. Source-to-output correspondence is by ordinal, and is checked

The pass carries a flag per line comment, in source order, and matches it to the
line comments of the output in output order. That correspondence is exactly what
layer 1 asserts, one stage later.

Because the pass runs *before* layer 1, it cannot lean on that assertion, so it
verifies the one thing it needs: that the two comment sequences have the same
length. If they do not, it aligns nothing and returns the rendered text
unchanged, and layer 1 then reports the real defect. Guessing at a pairing would
turn a printer bug into a cosmetic anomaly and hide it.

Determining which comments are in the output requires tokenizing the output.
`check-output` tokenizes it again immediately afterwards. That is one redundant
tokenization per file and it is accepted rather than optimized away: sharing the
token vector would put a value derived from the pre-alignment text into the
verification path, which is the vacuousness trap wearing a different hat. (See
`reduce-formatting-cost` for where formatting time actually goes; it is not
here.)

### 4. Declining is per run, and never buys alignment with an overflowing line

If aligning a run would put any of its comments past the page width, the run
keeps single spaces. Per run, so one wide line does not un-align an unrelated
block.

*Alternatives considered:* align to the widest column that still fits — rejected,
because the resulting column is a function of comment lengths as well as code
widths and is hard to predict from reading the source; and align anyway —
rejected, because pitch would then be lengthening a line on purpose, which
nothing else it does can be described as.

The declined case is stable under re-formatting for the same reason the aligned
one is: single spaces at differing columns are recognized as unaligned.

### 5. A separate library, importing neither the algebra nor the engine

`(pitch align)` imports `(pitch lines)` and the reader's token interface, and
nothing from `(pitch doc)`, `(pitch cost)`, `(pitch layout)`, `(pitch print)` or
`(pitch style)`. This is checkable in the same way `style-grammar` makes "style
tables are data" checkable — by what the library is allowed to import — and it is
worth a test rather than a comment.

## Risks / Trade-offs

- **Idempotence.** The single largest risk, and the reason Decision 2 exists.
  → Recognition by shared column makes the fixed point structural; tasks §2
  pins the three cases that break a padding rule, including the widest-line case
  specifically.
- **A run that reflows apart, or two runs that reflow together.** Runs are formed
  over *output* lines, so both happen. → Both are stable: the output's own
  columns are what the next run recognizes. Tasks §2 covers each.
- **Alignment pushes a line over the width and the layout never saw it coming.**
  The cost model priced the line without the padding. → Decision 4 declines
  rather than overflowing, so the rendered line's length is an upper bound on the
  aligned one only when the run is aligned at all.
- **The correspondence is wrong and the output is silently mis-aligned.**
  → Decision 3's length check, plus tasks §3's negative case, plus layer 1
  immediately after.
- **372 sites in Emit re-align to columns the author did not choose.** → That is
  what "re-derive the column" means, and the acceptance evidence in tasks §5 is
  a read of the actual diff rather than a count.
- **One extra tokenization per file.** → Accepted; see Decision 3. Measured in
  tasks §4 against the numbers in issue #15 so that it is a recorded cost rather
  than an assumed-small one.

## Migration Plan

No data, no configuration, no interface changes. Visible only as different
output for sources with column-aligned trailing comments.

- Pitch's own sources are reformatted in the same commit so `make format-check`
  stays a no-op.
- Rollback is reverting the commit; nothing persists.
- `docs/DESIGN.md` §2 and the README's preserved-formatting section grow from one
  entry to two, which is what an adopting project reads before deciding.
