## Context

Everything this change touches was read before this document was written.

`(pitch style)` holds the grammar. `terminal-tail` maps a tail name to a `tail`
record: `body` → `(make-tail 'expression #f)`, `fill` → `(make-tail 'expression
#t)`, and the four starred clause terminals to clause-styled tails. The `tail`
record has two fields, `style` and `fill?`. `style->shape` parses a style datum
into a `styled` record of slots plus one tail, and raises where the table is
built, so a malformed style is a load-time failure.

`(pitch print)` holds the layout. `styled-body` splits the items at the slot
count and emits

```scheme
(group (whole node (nest hanging-indent <head items> <break> <tail items>)))
```

with `hanging-indent` defined as 2. `whole` wraps the node in `align`, so the
nest is measured from the column the opening delimiter was laid out at — which
is exactly the anchor the two-column rule already specifies, and the reason this
change needs nothing new from the document algebra.

The binding constraints:

- `CLAUDE.md`: "Style tables are data, not code. Per-form layout rules go in the
  SRFI 272 style grammar, not in `cond` branches on head symbols."
- `CLAUDE.md`: the declared-normalizations list is empty; output tokens must
  match input tokens exactly, modulo whitespace.
- `style-grammar` as it stands: "No terminal outside it SHALL be accepted, and no
  notation of pitch's own SHALL be introduced alongside it."
- `style-layout` as it stands: the tail indent "SHALL be two columns" and "SHALL
  be a constant of the implementation".

The first and third are in direct tension for this change, and resolving that
tension is the substantive work here. The mechanics are a few lines.

## Goals / Non-Goals

**Goals:**

- Library bodies flush at the opening delimiter's column, in both dialects.
- The rule expressed as data in the style table, with no head symbol reachable
  from the printer.
- The grammar still closed: a finite enumeration, everything outside it refused
  at the point the table is written.
- Whitespace only. Both safety checks unaffected, idempotence preserved, the
  declared-normalizations list still empty.

**Non-Goals:**

- Configurability of either indent.
- A general indent-by-N terminal.
- Any change to the generic shape, to `fill`, or to the clause terminals.
- Re-litigating whether two columns is right for `body`. It is unchanged.

## Decisions

### Extend the notation, because the alternative is prohibited outright

The layout rule "this form's body is not indented" has to live somewhere. There
are three candidates and two of them are closed off before taste enters.

A branch in `styled-body` on the head symbol is what `CLAUDE.md` names and
forbids: per-form layout rules go in the grammar, not in `cond` branches on head
symbols. That prohibition exists because the previous generation of Lisp
formatters accreted exactly that, and it is the reason the style table was built
as data in the first place.

A property attached to the table entry but outside the style datum — an entry
becoming `((library) (_ d . body) #:indent 0)` — keeps the printer clean but
splits the description of a form's layout across two notations, one of which is
pitch's own anyway. It buys nothing over putting it in the style, and it makes
`style->shape` no longer the single thing that says what a style means.

So: a terminal. The cost is that the grammar is no longer exactly SRFI 272's, and
`style-grammar` says so in as many words. That requirement is amended rather than
worked around, and the amendment is narrow — the grammar stays closed and
enumerated, and only the claim that the enumeration is SRFI 272's verbatim is
withdrawn.

Two things make that cheap. SRFI 272 declines to specify a layout algorithm at
all, so every terminal's *meaning* is already pitch's; the SRFI supplies spelling
and a registry, not behavior. And `body0` differs from `body` in one integer.
This is not pitch inventing a notation; it is pitch adding one member to an
enumeration it already interprets by itself.

### The terminal is named `body0`

SRFI 272's terminals are short and lowercase: `i`, `d`, `e`, `f`, `l`, `h`,
`body`, `fill`, and the starred clause forms. `body0` fits that shape, says which
terminal it is a variant of, and says what the variation is. A reader who knows
`body` needs no table to guess it.

`flush` was the alternative, borrowed from typography. It reads well in prose and
badly in a table, where it gives no hint that it is a body tail and would sit
beside `fill` looking like a peer of it rather than a variant of `body`.

The trailing digit is a mild wart. It is preferable to a name that hides the
relationship.

### The indent lives on the tail record, as a number

`tail` gains an `indent` field holding 0 or 2. `terminal-tail` supplies it:
`body0` gets 0, everything else gets 2. `styled-body` reads it instead of using
`hanging-indent` directly.

A boolean `zero-indent?` was considered and rejected: `styled-body` would then
carry the conditional that turns a flag into a number, which is the same
knowledge in a worse place. A number on the record means `styled-body` gains no
branch at all — it substitutes `(tail-indent ...)` for a constant.

`hanging-indent` stays defined in `(pitch print)` and becomes the value
`terminal-tail` hands out for the indented terminals. It is still one constant in
one place, still not configuration, and `style-layout`'s requirement that the
value is a constant of the implementation survives intact — what changes is that
there are two constants and the terminal selects between them.

Note the field is on the *tail*, not on the styled shape. That is deliberate: the
indent is a property of what the tail terminal means, and putting it on the shape
would let a style specify an indent independent of its terminal, which is the
general indent-by-N mechanism this change is declining to build.

### `align` already anchors it, so the algebra needs nothing

`whole` wraps every compound in `align`, which captures the column of the opening
delimiter. `nest 0` inside that align is the identity on indentation, so the tail
sits at the delimiter's own column. For a top-level library that column is 0,
which is what was asked for; for a hypothetical nested one it is wherever the
form starts, which is the composable reading and the only one `nest` can express.

`(nest 0 d)` is well-formed and means what it says, so no combinator is added to
`(pitch doc)` and the differential oracle is untouched.

### What the safety checks see

Nothing. Indentation is whitespace; layer 1 compares token sequences and layer 2
compares data, and neither can observe a change in the whitespace between tokens.
That is the whole reason a style change is a safe change in this codebase, and it
is why the reformatting task at the end is mechanical rather than risky.

Idempotence needs a moment's thought and then holds: the fixpoint argument does
not depend on the indent value, only on the layout being a function of the
document, which it remains.

## Risks / Trade-offs

- **The grammar diverges from SRFI 272, and a future SRFI 272 terminal could
  collide with `body0`.** → Unlikely for a name shaped like this, and the
  grammar reader rejects unknown terminals, so a collision surfaces as a
  load-time failure at the table rather than as silent misbehavior. The spec
  keeps the enumeration explicit so the divergence is one list to compare.

- **Every downstream project formatted by pitch gets a large diff on its next
  run.** → Accepted; it is the change. Pitch has no released version and no
  downstream users yet, which makes now the cheapest possible moment.

- **Two indents invite a third.** → The spec enumerates the terminals and their
  indents, so a third requires amending a requirement rather than adding a case.
  The proposal declines the general mechanism explicitly.

- **Reformatting pitch's own sources in the same change makes the diff large and
  the real edit hard to find.** → The tasks put the grammar, printer and table
  edits and their tests first and complete, and the reformatting last as a single
  mechanical step, so the two are separable by commit if wanted. The bootstrap
  check is what confirms the mechanical step changed nothing but whitespace.

- **`style-layout`'s Purpose paragraph asserts the two-column rule
  unconditionally and is not a requirement, so no delta carries it.** → Flagged
  in the tasks as an edit to make when the deltas are synced, since a stale
  Purpose is exactly the kind of thing that survives review.
