## 1. The style grammar

- [x] 1.1 Create `src/pitch/style.sls` importing only `(rnrs)` pieces and
      `(rnrs hashtables)` — no `(pitch cst)`, no `(pitch doc)`, no
      `(pitch reader)`. The header states why: a table that cannot name a
      document or a tree cannot smuggle layout logic into data
- [x] 1.2 Define the shape descriptor as records: a `styled` shape carrying an
      ordered slot list and a tail rule, and a `generic` shape. Slots carry a
      terminal; tail rules are body, fill, clauses-of-terminal, or a nested
      styled shape for a slot that is itself a list
- [x] 1.3 Write the grammar reader `style->shape`: accept `(_ . fmt-tail)` per
      SRFI 272's BNF, with `i d e f l h` and `dc ec fc lc` as slot terminals,
      `i?` as the optional-identifier slot, `body`, `fill` and `dc* ec* fc* lc*`
      as tail rules, and a nested `fmt-tail` in a slot position
- [x] 1.4 Raise on a malformed style — missing `_`, an unknown terminal, a
      proper list with no tail, `i?` outside a slot position — with a message
      naming the offending datum
- [x] 1.5 Record on each terminal whether the position is an expression (looked
      up) or data (never looked up), and whether a list in it is filled. This is
      the whole terminal semantics and it belongs on the descriptor, not in the
      printer
- [x] 1.6 Create `tests/test-style.sps` and add it to the `test` target in the
      `Makefile`: every terminal accepted, each malformed form refused, and the
      code/data and fill classifications asserted directly. No documents or trees
      appear in this file

## 2. The tables

- [x] 2.1 Build an immutable symbol-keyed table from a list of
      `(heads... style)` entries, compiling each style at construction so a
      defective entry raises at library initialization rather than during layout
- [x] 2.2 Write the core table from `design.md`: `define`, `define-syntax`,
      `lambda`, `case-lambda`, `let` and the other binding forms, `when`,
      `unless`, `cond`, `case`, `begin`, `do`, `guard`, `set!`, `syntax-rules`,
      `import`, `export`. `if`, `and` and `or` deliberately have no entry
- [x] 2.3 Write the R7RS table: the core plus `define-values`,
      `define-record-type` as `(_ i h i . body)`, `parameterize`, the delay
      forms, `define-library`, `cond-expand`
- [x] 2.4 Write the R6RS table: the core plus `define-record-type` as
      `(_ i . body)`, `library`, `syntax-case`, `with-syntax`, `assert`
- [x] 2.5 Add `dialect-style-table`, mapping `common`, `r6rs` and `r7rs` to their
      tables and raising on anything else
- [x] 2.6 Test: a shared entry is the same descriptor in both dialect tables,
      `define-record-type` differs between them and is absent from the core, and
      an unknown dialect raises

## 3. The seam

- [x] 3.1 Give `compound-shape` a table argument and a body: read the head as the
      first datum child, take its `token-value` when it is an identifier leaf,
      look it up, and return the descriptor or `generic`. Import `token-value`
      from `(pitch reader)` and note in the header that a value may select a
      layout and never a character
- [x] 3.2 Thread the table through the translation: `cst->document` takes an
      optional dialect, resolves it to a table once, and passes it down. No other
      function in `print.sls` reads a head
- [x] 3.3 Confirm by inspection and by test that `compound-shape` is the only
      reader of a head element, and that no `cond` on a head symbol exists
      elsewhere in the printer

## 4. The styled shapes

- [x] 4.1 Emit a matched style: head and slots joined by hard spaces on the
      opening line, the tail under `nest 2` inside the existing `align`, the
      whole wrapped in `group` so it denotes exactly the flat and fully-broken
      layouts
- [x] 4.2 Emit a `body` tail: each remaining item on its own line, laid out by
      the ordinary rules so a nested compound consults the table for its own head
- [x] 4.3 Emit a `fill` tail: join items with `(alternatives space nl)` at each
      gap so each gap chooses independently. Confirm no addition to `(pitch doc)`
      is needed
- [x] 4.4 Emit a clause: the existing generic emitter with the clause's first
      element as the head, its lookup suppressed, and filled when the terminal is
      `f` or `l`
- [x] 4.5 Emit a `dc*`/`ec*`/`fc*`/`lc*` tail: each remaining item on its own
      line as a clause of that kind, with a non-list element emitted as itself
- [x] 4.6 Emit an `f`, `l` or `h` slot: fill when the element is a list,
      otherwise the element alone, with lookup suppressed either way
- [x] 4.7 Emit a bytevector's elements as a fill, without reference to any table
- [x] 4.8 Match `i?` against an identifier leaf, consuming nothing and matching
      the rest of the style at the same element when it is anything else

## 5. Degradation

- [x] 5.1 Fall back to `generic` when the head is not an identifier leaf or has
      no entry
- [x] 5.2 Fall back when the form has fewer elements than the style has required
      slots, and when a slot requiring a list gets something else
- [x] 5.3 Fall back when the list is improper, so a dot never lands in a slot
- [x] 5.4 Fall back when any gap from the head through the last slot is not a
      plain space, reusing the existing `gap` rather than re-deriving the
      question. This is the comment case, and the generic shape already handles
      it by dropping to hanging
- [x] 5.5 Test each of the five paths, including `(let)`, `(when)`,
      `(begin a . b)`, `(lambda x body)`, and a `when` whose test is preceded by
      an own-line comment

## 6. The pipeline

- [x] 6.1 Add an optional dialect argument to `format-source`, defaulting to
      `common`, and pass it to `cst->document`. No stage, refusal, or check
      changes
- [x] 6.2 Test that the dialect changes output and never acceptance: `#vu8(1 2)`
      formats under `r7rs`, and a `define-record-type` source formats under both
      dialects with differing output

## 7. Tests over real output

- [x] 7.1 Extend `tests/test-print.sps` with a positive case per table entry: a
      canonical form for each head, laid out at a width that forces breaking,
      compared against a written expectation. An entry with no test is an entry
      nobody has seen work
- [x] 7.2 Test the code/data distinction where it bites: `(syntax-rules (let) …)`
      does not style its literals list, and `(let ((if 1)) if)` does not style
      its binding
- [x] 7.3 Test that a style moves no comment: a trailing comment on a slot stays
      trailing, an own-line comment stays on its own line, and the token sequence
      of styled output equals the input's
- [x] 7.4 Extend `tests/test-format.sps`: every source file in the repository
      formatted under each dialect table, all four layers green, and idempotence
      at four widths
- [x] 7.5 Measure `src/pitch/reader.sls` end to end before and after and record
      the figure in `design.md`'s risk entry. If `fill` is what costs, demote
      `export` to `body` — a one-entry data edit — and record that it was done

## 8. Documentation

- [x] 8.1 `docs/DESIGN.md` §5: move the starter table from draft to shipped,
      record the settled judgment calls (`if`, `and`/`or`, `import` versus
      `export`, `define-record-type`), state the layout semantics SRFI 272 leaves
      unspecified, and record that `pp-tab` is measured from the opening
      delimiter and `pp-max-tab` has no referent
- [x] 8.2 `docs/DESIGN.md` §5: replace the "the degenerate case ships first, and
      is currently the only case" status, and carry the remaining open questions
      from `design.md` into the section's open list
- [x] 8.3 `README.md`: the style table stops being the one stage not yet built,
      and the paragraph saying every form gets one generic shape is replaced by
      what the table covers and what still degrades
- [x] 8.4 `README.md`: add `src/pitch/style.sls` to the repository layout
- [x] 8.5 `make test` green, `make vendor-verify` green, and `make oracle-layout`
      unaffected — the document algebra is untouched, so the oracle corpus does
      not change
