## Why

Pitch was run over an outside R7RS codebase for the first time and mangled a
`let`:

```scheme
;; written, and what every Scheme community writes
(let ([s0 (vector-ref *repl-env* 0)]
      [s1 (vector-ref *repl-env* 1)]
      [sme *repl-macro-env*]
      [sk *repl-known*]
      [sn *repl-n*])
  ...)

;; what pitch produced
(let ([s0 (vector-ref *repl-env* 0)] [s1 (vector-ref *repl-env* 1)]
                                     [sme *repl-macro-env*]
                                     [sk *repl-known*]
                                     [sn *repl-n*])
  ...)
```

**A binding list is being laid out as though its first binding were a head.**
The generic shape's *aligned* alternative puts the head and the first argument on
the opening line joined by a hard space at which no break may be taken, then
begins every remaining element at the first argument's column. That is exactly
right for `(some-function a b c)`, where the head is genuinely distinguished. It
is wrong for `([s0 ...] [s1 ...] [sme ...])`, where every element is a peer: the
second binding gets welded to the first, and the rest staircase off its column.

The style table is not at fault. `((let) (_ i? fc* . body))` correctly says the
binding list is a list of `fc` clauses with no distinguished element. What is
wrong is the translation's dispatch: `headless-doc` routes that list to
`generic-body`, whose comment states the assumption plainly — "It has no keyword,
so its first element plays that part." True of a `cond` clause, where the first
element is the test. False of a binding list.

**The specification is silent here, which is why this shipped.** `style-layout`
says what a starred *tail* does — "each remaining element on its own line" — and
that path is correct, which is why `cond` and `case-lambda` are fine. It says
nothing about what happens when a starred terminal appears in a *slot*, which is
the binding list. No requirement covers the case, and **the entire test suite —
1587 assertions — passes with the bug fixed**, so nothing exercised it either.

## What Changes

- **A third branch in `headless-doc`, and a `peer-body` emitter.** A list whose
  shape has no slots and whose tail does not fill is a list of peers: it renders
  flat if it fits, otherwise one element per line, every element aligned at the
  first element's column. Two layouts, not three — a peer list has no head, so
  the hanging alternative that exists to separate a head from its arguments has
  nothing to separate and is not offered.

- **The dispatch already had the signal it needed.** `headless-doc` tests
  `(null? (styled-slots shape))` today and uses it only to route the filling
  case. A binding list's shape has no slots because every element is described by
  the starred tail; a clause's shape has exactly one, the distinguished first
  element. The fix reads the same test one branch further rather than inventing a
  new distinction.

- **A requirement covering peer lists**, so the case is specified rather than
  merely fixed.

- **Pitch's own sources are reformatted**, since 7 of the 13 files in
  `FORMAT_SOURCES` contain a multi-binding `let` and re-flow.

Affected forms — every entry whose style puts a bare starred terminal in a slot:
`let`, `let*`, `letrec`, `letrec*`, `let-values`, `let*-values`, `let-syntax`,
`letrec-syntax`, `do`, `parameterize` (R7RS), `with-syntax` (R6RS).

Deliberately unaffected, and each for a reason worth stating:

- **`cond`, `case`, `case-lambda`, `syntax-rules`, `syntax-case`, `cond-expand`.**
  Their starred terminal is in *tail* position, so the clauses go through
  `styled-body` and already come out one per line. This change must not move
  them.
- **`guard`.** Its slot is `(i . ec*)`, a nested shape *with* a slot, so it is a
  clause and its first element really is distinguished. It keeps the generic
  shape.
- **Formals, literals, definition heads, and bytevectors.** Shape with no slots
  but a *filling* tail; they pack, and that branch is untouched.

Explicitly not in scope:

- **Trailing-comment alignment.** The same file exposed a second, unrelated
  problem: a column of hand-aligned margin comments collapses to one space, and
  the own-line continuation lines under it dedent to column 0, detaching them
  from the form they annotate. That is a question about whether aligned comment
  runs are structure or incidental whitespace, it argues against "reflows from
  scratch", and it deserves its own exploration rather than being smuggled in
  behind a layout fix.
- **Any change to the style tables or the grammar.** They are already correct.
- **A hanging alternative for peer lists.** Nobody writes `(let (` with the
  bindings two columns in; offering a layout no one wants costs search and
  invites the objective to pick it.

## Capabilities

### Modified Capabilities

- `style-layout`: gains a requirement for a list of peers — a list whose style
  distinguishes no first element — stating that it is laid out flat or with every
  element aligned at the first element's column, that it is never laid out with
  its first element treated as a head, and that this is distinct from a clause,
  whose first element *is* distinguished and which keeps the generic shape.

### New Capabilities

None. This specifies a case an existing capability left uncovered.

## Impact

- `src/pitch/print.sls` — `headless-doc` gains a branch; `peer-body` is added
  beside `fill-body`, which it closely resembles: same `whole`/`align`
  construction, `nl` instead of the filling separator, wrapped in a `group` for
  the flat alternative. No head symbol is examined and `compound-shape` is
  untouched.
- `tests/test-print.sps` — the coverage gap that let this ship: a multi-binding
  `let` at a width that forces breaking, the same for `let*` and `do`, a `cond`
  and a `case-lambda` pinned as *unchanged* so a future edit cannot quietly move
  the tail path, and a plain call pinned to the aligned shape so the head case is
  not lost.
- `src/pitch/*.sls` — 7 files re-flow under `make format`: `check`, `cli`,
  `cost`, `datum`, `layout`, `parse`, `print`.
- `openspec/specs/style-layout/spec.md` — the new requirement, at sync.
- `src/pitch/style.sls`, `src/pitch/reader.sls`, `tests/`, `vendor/` — untouched.
