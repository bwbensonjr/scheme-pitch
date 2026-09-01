## Context

See `proposal.md` — Why, including the prior-art survey that decided the rule.
What follows is the current state that shapes the approach.

Lookup happens in one place, `compound-shape`, and it already has a
position-decided case that consults no table:

```scheme
(define (compound-shape node tbl)
  (cond
    ((bytevector-node? node) 'fill)
    ((not (list-node? node)) 'generic)
    (else (let ((head (head-symbol node)))
            (or (and head (style-table-ref tbl head)) 'generic)))))
```

Both `'generic` results are the fallback this change is about, and neither is
reached by looking at a head symbol's identity — the second is reached by the
table *not* holding it. That is what makes the change small: the rule is "which
fallback", not "which head".

A subform carries an *element style*, and `styled-node-doc` reads it. This is the
existing channel for a property that travels from a parent to a child:

```scheme
;;   expression   the ordinary rules; a list here consults the table
;;   datum        no lookup, and no shape of its own
;;   (nested s)   no lookup, and its elements are styled by s
```

`prefix-doc` binds a marker to its datum with nothing between them and hands the
datum to `node-doc` — the ordinary rules, which is how a quoted list reaches
`compound-shape` today.

Constraints that bear:

- `CLAUDE.md`: per-form layout rules live in the style grammar, not in `cond`
  branches on head symbols. This change adds no branch on `quote` as a symbol.
- `style-grammar`: the terminal enumeration is closed. This change adds no
  terminal and no table entry.
- The declared-normalizations list is empty and stays empty.
- `format-pipeline` requires idempotence, and both safety layers compare against
  re-read output.

## Goals / Non-Goals

**Goals:**

- One property, decided by position, propagating to the bottom of the quoted
  subtree, changing one thing: which fallback an unstyled compound takes.
- The existing filled rendering is reused, not re-derived. `fill-body` is what
  `f`, `l`, `h` and bytevectors already get.
- Style lookup, `head-symbol`, the tables and the grammar are untouched, and so
  are the layout engine, the algebra and the cost factory.

**Non-Goals:**

- Suppressing lookup inside a quote. An earlier draft did this; `proposal.md`
  records why it was dropped.
- Filling ordinary function calls, as ANSI CL does. Out of scope and much larger.
- Preserving hand-grouping expressed by line breaks alone. Pitch discards a line
  break it did not choose, everywhere; the `; fmt: off` hatch — still open in
  `docs/DESIGN.md` §2 — is where that eventually belongs.

## Decisions

### 1. The property travels on the element-style channel

Add `quoted` beside `expression`, `datum` and `(nested s)`. It means: look up as
usual, but fall back to `fill` instead of `generic`, and pass `quoted` to the
children. `prefix-doc` assigns it to its datum when the marker is `'`.

*Why over the alternatives:*

- **A `quoted?` boolean threaded through `node-doc` and every emitter.**
  Rejected: a second, parallel channel for a fact the item already has a slot
  for, which every emitter would have to remember to forward. There is exactly
  one function, `styled-node-doc`, that reads the element style.
- **A case in `compound-shape` testing whether the node's parent is a quote.**
  Rejected: the CST has no parent pointers, and adding them to answer one layout
  question is a large change with a long shadow.
- **A table entry for `quote`.** Cannot be written — see `proposal.md` — and
  would be a head-symbol branch besides.

`compound-shape` gains the property as an argument and returns `fill` where it
returns `generic` today, in both of its fallback positions. It does not gain a
new way to find a style.

### 2. Composition with the terminals: `quoted` overrides `expression`, data wins over `quoted`

Three-line rule, and each line has its own argument:

- An `e` or `body`/`fill` element inside a quoted subtree stays quoted. Otherwise
  the property would die at the first styled form, and
  `'(begin (alpha one two ... ))` would fill at the top and staircase inside.
- `i`, `d`, `f`, `l`, `h` and a clause's first element keep their meaning. A
  terminal naming data is a specific claim about one argument of one form — a
  literals list is a list of names whether or not someone quoted the enclosing
  expression — and a quote makes no claim about shape at all. `f`, `l` and `h`
  fill already, so the only visible effect is that lookup stays suppressed where
  a terminal suppressed it.
- Clause tails are read as clauses as they are anywhere else.

The failure this avoids is specific: `'(lambda (let cond) body)` must not lay out
its formals as a `let` form. `style-layout` already prohibits that outside a
quote, and the ordering above is what keeps the prohibition inside one.

### 3. The fallback, not the lookup — and the evidence for it

This is the decision the change turns on, and `proposal.md` carries the
measurements. In short: ANSI CL fills unstyled lists and styles quoted code;
zprint suppresses lookup deeply and does not fill; `raco fmt` does neither and
produces pitch's current output byte for byte. Filling fixes issue #13, whose
repro's head is `car` and has no entry. Suppression is what would have packed
`'(define (f x) ...)` into a paragraph, and nothing that ships does both.

The cost of choosing CL's rule is worth stating plainly: **a data position becomes
sensitive to the style table.** A project that adds an entry for `foo` changes how
`'(foo ...)` renders as data. CL has exactly this property and lives with it, and
the alternative — suppression — buys independence at the price of packing quoted
code. Tasks §5 checks the Emit corpus for a case where this reads badly.

### 4. A dot falls back to the generic shape

`compound-doc` already refuses to force a styled shape onto a form containing a
dot, degrading to `generic-body` where the dot is preserved. The quoted fallback
takes the same `has-dot?` test for the same reason.

`headless-doc` does not make this test today, which is safe only because no
existing data position admits a dotted list in practice. A quoted position does —
`'(a . b)` is ordinary — so the test goes on the new fallback specifically, not
retrofitted onto `headless-doc`, where it would change behavior this change has
not argued for.

### 5. Nothing new is asked of the layout algebra

`fill-body` is `(whole node (align (join-items items fill-sep tbl)))`, with
`fill-sep` an `(alternatives space nl)` chosen independently at each gap. The
`align` sits immediately inside `whole` so a comment-forced break cannot move the
alignment — the same property `peer-body` relies on. A quoted list with
interleaved comments therefore packs the runs between comments and keeps every
line at the column after the opening delimiter, with no new document primitive
and no engine change. `make oracle-layout` must still report every entry
agreeing.

Worth recording from the survey: the Πe paper benchmarks `fillSep` explicitly and
Πe handles it well, so this is a use the engine was measured on rather than one it
is being stretched to cover.

### 6. Pitch's packing differs from CL's, and that is fine

CL prints `'(car cdr cons ...)` with `car` on the opening line and the remaining
elements filled beneath it, because its dispatch treats an `fboundp` head as a
call. Pitch's `fill-body` packs every element from the column after the opening
delimiter, first element included.

Pitch's is the simpler rule and the one it already applies to formals, literals
and bytevectors. Adopting CL's would mean a second filled rendering distinguished
by whether the head names a procedure, which pitch cannot know and must not guess.

## Risks / Trade-offs

- **A data position becomes sensitive to the style table.** → Decision 3, argued
  above; CL ships it. Tasks §5 looks for a case where it reads badly rather than
  assuming there is none.
- **The property leaks into a position that is really code.** The worst kind of
  defect here, because the output stays valid and the checks still pass — it
  would only change the fallback, so it is quieter still. → It can enter only at
  `prefix-doc`'s quote branch; `styled-node-doc` is the only reader; tasks §3
  pins the negatives: `` ` ``, `#'`, `(quote ...)` written out, and an unquoted
  list identical to a quoted one.
- **Ordering of `quoted` against the data terminals is got backwards.** →
  Decision 2, and tasks §1 pins `'(lambda (let cond) ...)` and
  `'(syntax-rules (let) ...)` specifically, which are the cases that fail loudly
  if the ordering is wrong.
- **Hand-grouping expressed by bare line breaks is lost.** → Grouping by blank
  line or comment survives, which is what Emit's tables use. Tasks §2 pins both
  and §5 reads the two named files.

  **Realized, in this repository.** `usage-lines` in `src/pitch/cli.sld` is a
  quoted list of strings, one per line of `--help` output; the fallback packs it
  and `"" "options:"` end up sharing a line. SBCL packs the same list the same
  way, so this is the rule working as specified. Accepted knowingly: the remedy
  is the `; fmt: off` hatch, which `docs/DESIGN.md` §2 now records this as
  motivating, not a carve-out in the layout. It is the only such site in pitch's
  own sources and there is none in Emit's.
- **Output churn for every adopting project.** → Announced as breaking,
  whitespace-only, and both safety layers plus idempotence run over the reformat.
  Narrower than the earlier draft, since a quoted form with a styled head no
  longer moves.

## Migration Plan

No data, no configuration, no interface changes. Visible only as different output
for sources containing an overflowing quoted compound with no styled head.

- Pitch's own sources are reformatted in the same commit, as the peer-list change
  did, so `make format-check` stays a no-op.
- Rollback is reverting the commit; nothing persists.
- A project pinning formatted output in review sees a one-time diff, which is
  what issue #13 asks for.
