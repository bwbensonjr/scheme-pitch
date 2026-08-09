## Context

The defect was found by running pitch over `src/repl-core.ss` in an unrelated
R7RS project. Everything below was read, and the fix was prototyped and the suite
run against it, before this document was written.

`(pitch print)` dispatches a list with no keyword through `headless-doc`:

```scheme
(define (headless-doc node shape tbl)
  (let* ((raw (children->items (compound-children node) blank-cap-inside))
         (items (if shape (assign-styles raw shape #f) raw)))
    (if (or (bytevector-node? node)
            (and shape (null? (styled-slots shape)) (tail-fill? (styled-tail shape))))
        (fill-body node items tbl)
        (generic-body node items tbl))))
```

`generic-body` offers flat, aligned and hanging, and its aligned alternative is:

```scheme
(define (aligned-body items tbl)
  (let ((head (car items)) (rest (cdr items)))
    (concat (item-doc head tbl)
            (concat (gap head (car rest) space)      ;hard space: no break here
                    (align (join-items rest nl tbl))))))
```

The hard space is what welds binding 2 to binding 1, and the `align` entered
after it is what puts bindings 3..n at binding 2's column. Both are correct for a
list with a head. Neither is correct for a list without one.

Which lists reach this path is decided by the style, not by the node:

| Style position | Example | Shape | Path today |
|---|---|---|---|
| starred terminal in a **tail** | `(cond . ec*)` | — | `styled-body`, one per line — correct |
| starred terminal in a **slot** | `let`'s `fc*` | no slots, no fill | `generic-body` — **the bug** |
| nested tail **with** a slot | `guard`'s `(i . ec*)` | one slot | `generic-body` — correct, it is a clause |
| `f`, `l`, `h` | `lambda`'s formals | no slots, fill | `fill-body` — correct |

So the broken case is precisely: a nested shape with **no slots and no fill**.
That predicate is already computed in `headless-doc`; it is simply not read on
this branch.

Constraints that bear:

- `CLAUDE.md`: no `cond` branch on a head symbol. The fix dispatches on the
  descriptor, which is what every emitter below `compound-shape` already does.
- The declared-normalizations list is empty. This changes which column a line
  starts at and nothing else, so both safety checks are untouched.
- `cst-translation` requires the generic shape to remain correct independently of
  any table, and requires the translation to build no cost value. The fix adds an
  emitter beside the existing ones and touches neither.

## Goals / Non-Goals

**Goals:**

- A binding list laid out the way every Scheme community writes it.
- The rule stated as a requirement, since the absence of one is why this shipped.
- The clause path and the tail path provably unmoved, pinned by tests.
- No head symbol reachable from any emitter.

**Non-Goals:**

- Trailing-comment alignment. Separate problem, separate change.
- Any change to the tables or the grammar; both are already right.
- Revisiting the generic shape, which is correct for lists that have a head.

## Decisions

### Read the existing predicate one branch further

`headless-doc` becomes a three-way `cond`: filling peers pack, non-filling peers
align, everything else takes the generic shape.

The alternative — a new field on the shape saying "headless" — was rejected
because the information is already present and derivable. A shape with no slots
is a shape that distinguishes no element; that *is* what "peers" means, and
recording it twice invites the two copies to disagree.

### `peer-body` is `fill-body` with a different separator

```scheme
(define (peer-body node items tbl)
  (if (null? items)
      (concat (open-doc node) (close-doc node))
      (group (whole node (align (join-items items nl tbl))))))
```

`fill-body` is the same construction with the filling separator and no `group`.
The parallel is the point: both are "a list of peers", differing only in whether
a gap chooses independently (fill) or all gaps break together (peer).

The `group` supplies the flat alternative, so `(let ([a 1] [b 2]) ...)` stays on
one line when it fits. `align` is entered immediately after the opening
delimiter, so it captures the first element's column and cannot be moved by a
break inside the first element — the same reasoning that makes `fill-body` safe
against a trailing comment, and the reason this needs no new argument.

The empty-list case mirrors `fill-body` exactly: `(let () ...)` emits `()` with
no alternatives, and `align` over no items would otherwise be a group with
nothing in it.

### Two layouts, not three

A peer list denotes flat or fully broken. No hanging alternative is offered.

Hanging exists to put a head alone on the opening line and its arguments beneath.
A peer list has no head, so hanging would mean

```scheme
(let (
    [a 1]
```

which nothing in either community writes. Offering it would enlarge the search
for a layout the objective should never pick, and would reintroduce the
tie-breaking question that `cst-translation` had to settle structurally for the
generic shape. Two layouts differing in both width and height need no
tie-breaker, exactly as the styled shape does not.

### The requirement is what stops this recurring

The code fix is four lines. The reason a four-line bug reached a release is that
nothing said what a binding list should look like: `style-layout` specifies the
starred *tail*, and the natural reading is that it covers the slot case too.

So the requirement is written to name the distinction directly — a list whose
style distinguishes no first element is never laid out with its first element as
a head — and the tests pin the clause and tail paths as unchanged, so a future
edit that collapses the three cases back into two fails rather than silently
restoring the staircase.

## Risks / Trade-offs

- **A peer list with a very long first element pushes the rest far right.** →
  True, and it is what everyone writes; the alternative is hanging, rejected
  above. The engine still chooses flat when it fits, and a binding list wide
  enough for this to hurt has a formatting problem the layout cannot solve.

- **7 of 13 of pitch's own files re-flow, so this diff is mostly noise.** → The
  tasks put the fix and its tests first and complete, and `make format` last as
  one mechanical step, so the two are separable by commit. The whitespace-only
  check and the bootstrap comparison confirm the mechanical step.

- **`(null? (styled-slots shape))` now carries more weight than before.** → It
  was already load-bearing for the fill branch; the fix makes it decide two
  branches instead of one. It is derived from the compiled style rather than
  stored, so it cannot drift out of sync with the table.

- **`do`'s step clauses change shape.** `do`'s binding list is `fc*` in a slot,
  so it is in scope. Its elements are `(var init step)` triples, and aligning
  them one per line is what `do` is conventionally written as, so this is a fix
  there too rather than collateral. Pinned by a test so it is a decision on the
  record rather than an accident.

- **The suite passing with the prototype means the tests did not cover this.** →
  Which is a finding, not a reassurance. The task list treats the tests as the
  deliverable and the code as the easy part.
