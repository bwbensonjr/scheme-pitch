## Context

`(pitch print)` folds a child sequence into items. Whitespace never becomes an
item; it contributes two facts, one of which is how many blank lines it holds.
That count was `endings - 1`, floored at zero, on the reasoning that the first
ending in a run terminates the line the previous element sat on.

The reasoning is right for a datum and wrong for a comment, because the lexer
gives a line comment a token text that *includes* its terminating line ending —
the same fact that forces `leaf-doc` to split that ending off and re-emit it as
an explicit break, and the same fact `check.sls` compensates for when it drops
one trailing ending before comparing token text. It is a recurring source of
off-by-one, and this is the third place it has had to be handled.

Three observed symptoms, one cause:

```
"; one\n\n; two\n"    -> "; one\n; two\n"        blank line dropped
"; one\n\n\n(a)\n"    -> raises                  assertion in gap
"(x ; c\n\n\nb)\n"    -> "(x ; c\n  \n  b)\n"    blank line holds two spaces
```

The third does not occur today, because the first prevents the blank line from
existing at all. That is what makes these one change rather than three.

## Goals / Non-Goals

**Goals:**

- A blank line written after a comment survives, at the same caps as anywhere
  else.
- A preserved blank line contains no characters.
- Valid input never raises.
- The two guards on a comment swallowing following code stay intact, and the
  weaker of the two gets sharper rather than looser.

**Non-Goals:**

- Any change to the caps, to what counts as a line ending, or to the empty
  declared-normalizations list.
- Reworking how a comment's break is emitted. The unconditional break in
  `leaf-doc` is the load-bearing safety construction and is not touched.

## Decisions

### The count discounts an ending only where one was consumed

```scheme
(define (blank-count endings prev-broken? cap)
  (min cap (max 0 (if prev-broken? endings (- endings 1)))))
```

`prev-broken?` is whether the preceding non-whitespace child ended in a forced
break, which is exactly the condition under which that child's own text already
carried the ending that terminated its line. It is the same `node-broken?` the
fold already computes for the item, so no new notion is introduced.

The alternative was to make the lexer, or the CST, not fold the ending into the
comment's text. That is a much deeper change — it would alter what `cst->text`
concatenates and therefore the round-trip invariant — and the ending genuinely is
part of the comment's lexeme. Compensating at the three places that care is the
right side of that trade.

### The break that lands on a blank line is taken at indentation zero

`hard-breaks` already arranges this for the breaks the joiner emits: all but the
last are taken under `reset`, so the lines they open are empty and only the final
break indents the line that has content. What it cannot arrange is the *first*
break when the previous item supplied it, which is what a comment does.

So `leaf-doc` gains an optional flag, and emits `(reset hard-nl)` in place of
`hard-nl` when set. Both branches still emit a break unconditionally — the
property that makes a comment swallowing code unrepresentable is untouched.

**Whether the flag is set is recorded on the item, not passed at each join.**
Only the element before a blank run can know a blank run follows, and there are
five places that materialize an item — `join-items`, the singleton case, the
aligned and hanging bodies, and the styled body's split into head and tail.
Threading a lookahead argument through all five is five chances to miss one, and
a missed one is silent: the output still passes every check, because trailing
whitespace is whitespace and layer 1 filters it. So a pass at the end of the fold
sets `blank-after?` on each item from the next item's blank count, and
`item-doc` reads it. One place decides, and every emitter inherits the decision.

The narrower alternative — have `join-items` alone look ahead — was rejected for
exactly the case that would have escaped it: `styled-body` joins its head and its
tail with two separate calls, so the item at that boundary would never see its
successor.

### The guard tests the branch, not the document

```scheme
(else
 (assert (not (item-broken? prev)))
 sep)
```

The old form computed the separator and then asserted `(not (eq? d sep))`. That
is a proxy for "we did not take the `sep` branch", and the proxy is unsound:
`hard-breaks 1` is `(concat (reset empty-doc) hard-nl)`, the constructors
simplify an empty concatenation away, and the result is the very same `hard-nl`
object that serves as the separator between top-level forms. A comment followed
by one blank line at top level therefore tripped a guard on output that was
correct.

Asserting inside the branch says what the requirement says — no separator after
an element ending in a forced break — and cannot be fooled by two documents
happening to be the same value. It is also cheaper, and it is impossible for a
future edit to satisfy it accidentally, since reaching it at all is the thing
being prohibited.

## Risks / Trade-offs

**The item record grows a field that only matters for two token kinds.** →
Accepted. The alternative is recomputing it at five call sites, and the field is
set once by the same pass that builds the record. `blank-after?` is meaningful
only when `broken?` is true, and `item-doc` tests both rather than relying on the
caller to have set it consistently.

**More output changes than the bug report suggests.** Every file with a comment
followed by a blank line now formats differently — the blank line comes back. →
That is the fix. Idempotence, both checks and the whole corpus confirm the
outputs are still valid and still fixpoints, and the suite gained cases pinning
the new behavior at both caps.

**A third compensation for the comment-carries-its-ending fact.** → Recorded
rather than removed. The three sites now are `leaf-doc` splitting the ending off,
`check.sls` dropping one before comparing, and `blank-count` not discounting one.
If a fourth appears, that is the argument for changing the representation instead
of compensating again.

## Open Questions

- Whether a shebang should behave as a comment does here. It is a forced-break
  leaf, so it does today, and a blank line after `#!/usr/bin/env scheme-script`
  is now preserved. That seems right and no input has argued otherwise.
