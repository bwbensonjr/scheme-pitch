## Context

Everything this change plugs into already exists and was read before this
document was written. `(pitch print)` folds a child sequence into *items* — a
document, a preceding blank count, whether it ends in a forced break, whether it
is a comment written on its own line — and every placement decision is already
made by the time a shape is chosen. `compound-shape` is one function that ignores
its argument and returns `generic`, and the three generic alternatives (flat,
aligned, hanging) are built from `group`, `align` and `nest 2` over that item
list. `(pitch doc)` supplies `alternatives`, `group`, `nl`, `space`, `nest`,
`align` and `reset`; `(pitch layout)` resolves a document to the layout
minimizing a cost objective over the whole document rather than greedily.

SRFI 272 supplies the notation and nothing else. Its grammar is:

```
⟨style⟩    ⟶ (⟨_⟩ . ⟨fmt-tail⟩)
⟨fmt-tail⟩ ⟶ body | fill | dc* | ec* | fc* | lc*
             | (i? . ⟨fmt-tail⟩) | (⟨fmt⟩ . ⟨fmt-tail⟩)
⟨fmt⟩      ⟶ i | d | e | f | l | h | dc | ec | fc | lc | ⟨fmt-tail⟩
```

It is explicit that the layout algorithm is unspecified, and its terminals are
described in terms of *printing* — "print as identifier", "print as literal" —
because SRFI 272 uses them to colour and classify, not to break lines. Deciding
what each one denotes as a document is therefore the substantive work here, and
it is not something the SRFI can be deferred to.

Constraints from `CLAUDE.md` and `docs/DESIGN.md` that bear directly:

- Style tables are data, not code. Per-form layout rules go in the style grammar,
  not in `cond` branches on head symbols. The seam already exists; the binding
  constraint is that nothing outside it acquires a head symbol.
- The declared-normalizations list is empty. A style may change which whitespace
  is emitted and must never change which characters are.
- Malformed input is refused, not guessed at — but a *well-formed* form that does
  not match its style is ordinary input, and must degrade rather than fail.
- The CST and the layout engine never branch on dialect. The dialect seam is at
  the edges, and a style table is one of the three things a dialect bundles.

## Goals / Non-Goals

**Goals:**

- A style notation that is read and validated once, so the table is a value and a
  typo in it is a load-time failure rather than a layout surprise.
- A layout semantics for every SRFI 272 terminal, stated as requirements, so that
  what a form looks like is predictable from its style rather than emergent from
  the cost objective.
- Degradation to the generic shape on every path where a style does not fit the
  form in front of it, with no path that crashes and no path that repairs.
- The dialect architecture the `define-record-type` collision demands, without
  the selection machinery it does not.
- Idempotence and both safety checks preserved with no new argument needed: the
  fixpoint argument in `docs/DESIGN.md` extends to styled output unchanged.

**Non-Goals:**

- A complete table. The R7RS-small core plus the R6RS core is finite and is an
  afternoon; per-dialect library macros are a long tail this change does not
  chase.
- Configuration. No registry, no magic comment, no exposed `pp-tab`.
- A tuned cost objective. Styles remove alternatives rather than adding them,
  which is if anything a reason the objective matters less.

## Decisions

### A terminal says whether a subform is code or data, and that is the point

The vocabulary looks like eleven terminals plus four starred forms. At the layout
level it collapses onto two orthogonal facts, and stating them this way is what
makes the semantics small enough to be checkable:

**Whether the subform is looked up.** `e` and the elements of a `body` or `fill`
tail are *expressions*: they are laid out by the ordinary rules, so a compound
among them consults the table for its own head. Every other terminal names
*data*, and data is never looked up.

That distinction is not decoration. `(syntax-rules (let) ((_ x) ...))` has a
literals list `(let)` whose head is the symbol `let`; `(let ((if 1)) ...)` has a
binding `(if 1)` whose head is the symbol `if`. Laying either out as the form it
spells would be a visible defect, and the terminal in that position is exactly
what says it is not one. The same argument is why `ec*` is not a synonym for
`body` even though both put one element per line: `body` looks its elements up
and `ec*` refuses to.

**What the subform's own shape is.** `i`, `d` and `e` impose nothing — the
element is laid out by its own rule, which for a list with no entry is the
generic shape. `f`, `l` and `h` name lists of names or literals, and those are
*filled*: `(define (compute a b c) ...)` wraps its head list by packing, not one
name per line. The clause terminals `dc`, `ec`, `fc`, `lc` say the element is a
list read as `(first . body)`, whose `first` takes the style `d`, `e`, `f` or `l`
respectively.

`i?` is the one terminal with matching behaviour rather than layout behaviour: it
consumes the element only if that element is an identifier leaf, and otherwise
consumes nothing and lets the rest of the style match at the same position. That
is what lets one entry cover both `(let ((x 1)) b)` and `(let loop ((x 1)) b)`.

The alternative considered was giving each terminal its own emitter, faithful to
the eleven names. It was rejected because eleven emitters that mostly agree is
eleven places for them to stop agreeing, and because the honest finding —
`raco fmt`'s 183 head names collapse to about six shapes — is the reason a table
is affordable at all. The names are kept in the notation, since the notation is
the part being borrowed; they collapse behind it.

### A style is slots then a tail, and it denotes exactly two layouts

A style compiles to a descriptor: an ordered list of **slots**, each with a
terminal, and a **tail rule** covering every remaining element. Rendering a
matched form:

- The head and every slot share the opening line, joined by a single space that
  is not a break opportunity. That is what a slot *is*.
- The tail is laid out beneath, indented from the **opening delimiter** by
  `pp-tab`, taken as 2.
- The whole is wrapped in `group`, so the document denotes the all-flat rendering
  and the fully-broken one and nothing between.

```scheme
(when (ready? x)            (cond                        (define (f a b)
  (go))                       ((null? xs) acc)             (+ a b))
                              (else (loop (cdr xs))))
```

Exactly two layouts is worth stating as a property rather than an accident. The
generic shape offers three and needs an argument — recorded in `cst-translation`
— that aligned and hanging can never tie under an objective ranking overflow
before height. A styled form needs no such argument: its two candidates differ in
line count *and* in width, and the flat one is available only when it fits. Adding
a style to a form therefore removes work from the cost objective instead of
adding a tie for it to break.

`fill` is the exception and is deliberate: a filled tail joins its elements with
`(alternatives space nl)` at each gap, so each gap chooses independently and the
tail denotes many layouts. This needs no addition to `(pitch doc)` — `space`,
`nl` and `alternatives` are already exported — and a per-gap choice is precisely
the case Πe was built to resolve in polynomial time rather than by backtracking.

### `pp-tab` is measured from the opening delimiter, and `pp-max-tab` is dropped

SRFI 272 specifies `pp-tab` as an offset "relative to the start of the form's
keyword". With the keyword one column right of the delimiter, a `pp-tab` of 2
would put a body at three columns from the delimiter, which nothing in either
community writes. Pitch measures from the opening delimiter, so a body sits two
columns in — what Emacs produces, what `raco fmt` produces, and what the existing
hanging shape already does, so the constant does not change and neither does the
`nest`.

`pp-max-tab` exists to cap the rightward drift a long keyword causes when a body
is offset from the keyword rather than from the delimiter. Measuring from the
delimiter means there is no such drift and nothing to cap, so the knob has no
referent here and is not implemented. Both stay constants either way:
`README.md` fixes the configuration surface at width and dialect.

### A clause is the generic shape with its first element's style overridden

A clause — `((null? xs) acc)`, `((1 2 3) => f)`, `((x 1))` — is laid out by the
existing generic alternatives, treating its first element as the head. Broken,
the remaining elements align under the first, which is what Emacs and `raco fmt`
both produce and what every Scheme file in the wild already looks like.

The alternative was making a clause a styled form with zero slots and a `body`
tail, which would indent clause bodies two columns from the clause's delimiter
rather than one:

```scheme
((null? xs)        ; chosen: aligned under the first element
 acc)

((null? xs)        ; rejected: body indented from the delimiter
  acc)
```

Uniformity with other bodies was the argument for the rejected form and it is not
worth what it costs in familiarity. The chosen form also reuses an emitter that
already exists and is already tested, so a clause introduces no new rendering
code at all — only the decision to suppress head lookup and, for `fc` and `lc`,
to fill the first element.

### The head is matched by the token's value

The head is the first datum child of a list node. When it is a leaf of kind
`identifier`, its `token-value` — the symbol the reader produced — is the lookup
key. Any other head, including a compound, matches nothing and yields the generic
shape.

Matching on `token-text` was the alternative, and it was rejected as wrong rather
than merely inconvenient: `|let|` is `let`, and under `#!fold-case` so is `LET`,
and a formatter that styles one spelling of a symbol and not another is reporting
a lexical accident as a semantic difference. The reader has already done this
work and `token-value` is exactly its answer.

This widens what the translation is permitted to read, and the widening is stated
narrowly. Recorded offsets, lines and columns remain forbidden — the trap
`docs/DESIGN.md` §3 warns about is untouched, and comment classification still
comes from whitespace text rather than arithmetic. Every character the
translation *emits* still comes from `token-text`. What a value may now do is
select a layout, which is to say select whitespace, which is the one thing pitch
is allowed to change.

### The table is a value, compiled at load, holding no code

`(pitch style)` reads each entry from the SRFI 272 notation into a descriptor at
library initialization and stores the result in an immutable hashtable keyed by
symbol. Lookup on the hot path is one hashtable reference.

A malformed style is an assertion violation at that point. This is a programmer
error in pitch's own data, not a property of anyone's input, so it must surface
where the mistake is rather than as strange output on a file that happens to use
that form — and validating at load means every entry is exercised on every run
regardless of what is being formatted.

`(pitch style)` imports nothing from `(pitch cst)`, `(pitch doc)` or
`(pitch reader)`. It maps a symbol to an inert descriptor and knows about neither
trees nor documents. That is `CLAUDE.md`'s "style tables are data, not code" made
structural: a table cannot contain a document or a procedure, because the library
that defines tables cannot name one.

### Three tables, and a dialect that selects among them

`define-record-type` is the collision, and one is enough:

```scheme
(define-record-type <point> (make-point x y) point? (x point-x))  ; R7RS
(define-record-type point (fields (immutable x)) (protocol ...))  ; R6RS
```

The tables are `core`, `r6rs` and `r7rs`; the dialect tables are the core plus
their own entries, so an entry is written once. `cst->document` and
`format-source` take an optional dialect symbol, defaulting to `common`, which
selects `core`. In `core` the colliding head has no entry and degrades to the
generic shape — the degradation path doing exactly the job it exists for, rather
than a union table quietly rendering one dialect's form under the other's rule.

A dialect here names a style table and nothing else. `docs/DESIGN.md` §4 defines
it as a bundle of three, and the other two — a reader profile and a normalization
policy — have nothing to configure: the reader is a permissive union by
invariant, and the normalization list is empty. Introducing empty fields to
honour a definition would be inventing structure ahead of its content. An unknown
dialect symbol is an assertion violation, since it comes from a caller rather
than from a file.

### Degradation is enumerated, and every path lands on the generic shape

SRFI 272 has a non-matching form printed as a plain datum. Pitch's version is that
the generic shape is the universal fallback, which is why it had to exist and be
correct before the table did. The paths, all of which are ordinary input:

| Condition | Why |
|---|---|
| head is not an identifier leaf | nothing to look up |
| head has no entry in the selected table | the common case, and `if` deliberately |
| fewer elements than the style has required slots | `(let)` in a half-typed buffer |
| a slot's terminal expects a list and the element is not one | `(lambda x body)` against `f` |
| the list is improper | a dot in a styled form has no place in any slot |
| a gap inside the slot region is not a plain space | a comment forced a break there |

The last is the one that interacts with the layer everything else in this
codebase is organized around, and it reuses machinery rather than reasoning
afresh. The item sequencer already computes the separator between two items, and
that separator is a plain space exactly when nothing forced a break. If any gap
from the head through the last slot is anything else, a comment has intervened,
the slot region cannot be kept on one line, and the style cannot describe what is
there. Falling back to the generic shape is right because the generic shape
already handles this case — it drops to hanging, for reasons `cst-translation`
records — and because the alternative, moving the comment, is what layer 1
refuses.

A style therefore never causes a comment to move and never causes one to be lost.
It chooses among layouts of an item list that was already built.

### The starter table, with the judgment calls settled

```scheme
;; core -- identical in both standards
(define                 (_ h . body))
(define-syntax          (_ i . body))
(lambda                 (_ f . body))
(case-lambda            (_ . fc*))
(let                    (_ i? fc* . body))
(let* letrec letrec* let-values let*-values let-syntax letrec-syntax
                        (_ fc* . body))
(when unless            (_ e . body))
(cond                   (_ . ec*))
(case                   (_ e . lc*))
(begin                  (_ . body))
(do                     (_ fc* ec . body))
(guard                  (_ (i . ec*) . body))
(set!                   (_ i . body))
(syntax-rules           (_ l . dc*))
(import                 (_ . body))
(export                 (_ . fill))
;; r7rs
(define-values          (_ f . body))
(define-record-type     (_ i h i . body))
(parameterize           (_ fc* . body))
(delay delay-force make-promise (_ . body))
(define-library         (_ d . body))
(cond-expand            (_ . ec*))
;; r6rs
(define-record-type     (_ i . body))
(library                (_ d . body))
(syntax-case            (_ e l . dc*))
(with-syntax            (_ fc* . body))
(assert                 (_ . body))
```

Four decisions in there are the ones `docs/DESIGN.md` §5 left open or drew
differently.

**`if` gets no entry.** §5 drafts `(if (_ . body))`, which would put the test on
its own line beneath the keyword. What everyone writes is the test on the opening
line with the branches aligned under it, and that is precisely the generic aligned
shape. Leaving `if` out of the table is therefore not a gap; it is the correct
entry, and it makes §5's own illustration — `(if ...)` and `(list ...)` drawn
identically — come out as drawn.

**`and` and `or` get no entry either.** §5 drafts `(_ . fill)`. Filling boolean
tests packs unrelated predicates onto shared lines, which reads worse than the
generic aligned shape, and there is no reason to spend a table entry making
output worse.

**`import` is a body and `export` is a fill**, which §5 records as an open taste
question. It is settled by looking at what this repository already contains:
every library here writes its import list one clause per line and its export list
packed several names per line, because an import clause is a structure worth
scanning vertically and an export is a name in a set. Choosing what the sources
already do also means the first run of pitch over pitch does not churn them.

**`define-record-type` is the only entry that differs by dialect**, and it is
absent from `core`, so the default dialect degrades it. That is the collision
doing its job as an architectural argument rather than being papered over.

### Idempotence survives without a new argument

`docs/DESIGN.md` records that the document depends on exactly three properties of
the tree: each token's text, whether a line ending separates two children, and
how many blank lines a whitespace run holds. This change adds a fourth — the head
symbol of a list node — and one derived quantity, the separator inside the slot
region, which is itself a function of the first three.

Both are already at their fixed point after one run. Formatting does not change a
token's value, since it does not change a token's text; and an own-line comment
stays own-line and an attached comment stays attached, which `comment-placement`
already requires. So the second run selects the same style, reaches the same
degradation decision, and builds the same document. The argument extends rather
than needing to be redone, and layer 3 continues to be evidence for it.

## Risks / Trade-offs

**Fill multiplies the search space, on top of a resolver already measured at two
seconds for the largest file in the repository.** → Measured, and the fear was
misplaced in both directions. End to end, before and after:

| file | before | after |
|---|---|---|
| `src/pitch/reader.sls` | 2218ms | 2883ms |
| `src/pitch/layout.sls` | 1130ms | 803ms |
| `src/pitch/doc.sls` | 304ms | 206ms |

Two files got *faster*, and `make test` as a whole went from 9.6s to 5.5s. That
is the property the design predicted from the other end: a styled form denotes
two layouts where the generic shape denotes three, so adding entries removes
candidates from the search rather than adding them. The cost objective has less
to compare, not more.

`reader.sls` is the exception at +30%, and `fill` is **not** the cause — demoting
`export` to `body` was measured at 2872ms against 2883ms, a difference indis-
tinguishable from noise, so the entry stays `fill` and keeps matching how this
repository already writes its export lists. What `reader.sls` has that the
others do not is very large `case` and `cond` forms, whose clause lists are now
one styled decision per clause rather than one generic decision for the whole
list. The figure is recorded and not acted on, for the same reason the previous
change recorded its own: optimizing the resolver is a change to
`layout-resolution`, not to the table.

**Formatting pitch's own sources will now produce real diffs, where before the
output was uniformly wrong and nobody looked at it.** → That is the change
working. The tests continue to assert losslessness, placement and idempotence
rather than beauty, so a later taste revision does not invalidate them; the
end-to-end suite runs every source file in the repository through both dialect
tables and checks all four layers.

**A style that never matches is invisible.** A typo in a head symbol, or a slot
terminal that no real form satisfies, degrades silently to the generic shape and
looks exactly like a form with no entry. → The suite asserts *positively* for
every entry: a canonical input for each head, laid out at a width that forces
breaking, compared against a written expectation. An entry with no test is an
entry nobody has seen work.

**Baking in taste that turns out to be wrong.** → Every entry is one line of data
in one library. `raco fmt` reached 183 entries and pitch will not stay at this
size, so the cost of being wrong has to stay at "edit a line", and the test for
each entry is what makes changing one safe.

**The default dialect leaves `define-record-type` unstyled until selection
ships.** → Accepted. It is one form, it degrades rather than breaks, and the
alternative — defaulting to one of the two standards before pitch can tell which
file it is looking at — would style the other one wrong, which is worse than
styling neither.

**Reading `token-value` widens the translation's inputs.** → Narrowly, and it is
written into the spec as a narrowing rather than a removal: positions stay
forbidden, and emitted characters still come only from `token-text`. Layer 1
remains the backstop, since a value that influenced a *character* would show up as
a token mismatch.

## Open Questions

- Whether a quoted list should fill. `'(1 2 3 ... 100)` one element per line is
  nobody's intent, but the fact that makes it data is the enclosing `quote`
  prefix rather than its own head, so the rule is contextual and does not fit a
  head-keyed table. Bytevectors are decided the other way and do fill, because
  their elements are octets and no judgment is involved.
- Whether data suppression should be deep. Today `l` suppresses lookup for the
  literals list itself and its children are laid out normally, so a `syntax-rules`
  *pattern* containing something that spells `let` is still styled as a `let`.
  Deep suppression means threading a data context through the translation, which
  is real complexity for a benefit real input has not yet demonstrated.
- Whether clause bodies should indent from the clause's delimiter instead of
  aligning under its first element. Decided above on familiarity; a corpus is what
  would settle it properly.
- Whether the dialect default should become `r7rs` or stay `common` once content
  sniffing exists and a file's dialect is usually known.
- Whether `pp-tab` ever becomes configuration. `README.md` says no, and nothing
  here argues with it.
- Whether an in-file `;; * pp-styles:` comment ever ships. It is the community
  precedent for per-file style overrides and it is also configuration growth;
  the grammar being the on-disk format keeps the option open at no cost.
