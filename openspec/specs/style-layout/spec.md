# style-layout Specification

## Purpose

What a style *renders as* -- the layout semantics SRFI 272 declines to supply,
stated here as requirements rather than left for the cost objective to discover.
Every terminal before the tail is a slot sharing the opening line with the head,
at a gap where no break may be taken; the tail lies beneath it, indented from
the opening delimiter and never from the head by an amount its terminal
selects -- two columns for `body` and the clause terminals, zero for `body0`,
which exists for forms wrapping a whole compilation unit -- so that a long name
cannot push a body across the page. A styled form denotes exactly two layouts,
flat or broken, and they differ in both width and height, so unlike the generic
shape it needs no tie-breaking argument to stay deterministic. Clause terminals
recurse into the generic shape with the clause's first element read as its head,
so a clause introduces no rendering of its own; a list whose style distinguishes
no first element, a binding list among them, is aligned at that first element
rather than treated as having a head, because it has none; fill and the packing
terminals choose at each gap independently, because a list of names or of octets
carries no per-element judgment worth a line apiece. Lookup follows position: an
expression position consults the table, a data position does not, so
`(syntax-rules (let) ...)` is not a `let`. Everything a style cannot describe --
a head with no entry, too few elements, an atom where a list was required, an
improper list, a comment forcing a break inside the slot region -- falls back to
the generic shape. A style never raises, never drops an element, and never moves
a comment, because it only chooses among layouts of an item sequence the comment
rules already built.
## Requirements

### Requirement: A matched style puts its slots on the opening line and its tail beneath

A style SHALL describe an ordered list of slots followed by a tail rule. For a
form matching it:

- The head and every slot SHALL share the opening line, separated by single
  spaces at which no line break may be taken.
- Every remaining element SHALL be covered by the tail rule and SHALL be laid out
  beneath the opening line.
- The whole SHALL denote exactly two layouts: everything on one line, or the
  opening line followed by the broken tail. There SHALL be no layout in which
  some tail elements share the opening line and others do not.

The choice between the two SHALL be made by the cost objective, as for every
other layout choice.

Because the two layouts differ in both width and height, a styled form MUST NOT
require a tie-breaking argument of the kind the generic shape needs.

#### Scenario: A styled form that fits is laid out flat

- **WHEN** `(when a b)` is laid out at a width that accommodates it
- **THEN** the output is `(when a b)` on one line

#### Scenario: A slot stays on the opening line when the form breaks

- **WHEN** `(when (ready? x) (go) (stop))` is laid out at a width that forces
  breaking
- **THEN** the first line is `(when (ready? x)`
- **AND** `(go)` and `(stop)` each begin a line of their own

#### Scenario: There is no partially broken tail

- **WHEN** a styled form with three tail elements is laid out at any width
- **THEN** either all three share the opening line or none does

### Requirement: A body or clause tail is indented from the opening delimiter by its terminal's amount

The indentation of a broken tail SHALL be measured from the form's opening
delimiter, and its amount SHALL be determined by the tail's terminal:

| Terminal | Indent |
|---|---|
| `body`, `fill`, `dc*`, `ec*`, `fc*`, `lc*` | two columns |
| `body0` | zero columns |

It MUST NOT be measured from the head symbol. It MUST NOT vary with the length of
the head. It MUST NOT vary with anything other than which terminal the tail is.

Both values SHALL be constants of the implementation and MUST NOT be exposed as
configuration. The terminal selects between them; nothing else does, and no
mechanism SHALL exist for a style to name an indent of its own.

A `body0` tail SHALL be identical to a `body` tail in every other respect: one
element per line, each element looked up as an expression, the same flat
alternative, and the same fallback when the form does not match its style.

#### Scenario: A body is indented two columns

- **WHEN** `(when (ready? x) (go))` is laid out at a width that forces breaking
  with the opening delimiter at column 0
- **THEN** `(go)` begins at column 2

#### Scenario: A zero-indent body sits at the opening delimiter's column

- **WHEN** a form whose style has a `body0` tail is laid out at a width that
  forces breaking with the opening delimiter at column 0
- **THEN** its tail elements begin at column 0

#### Scenario: A zero-indent body is measured from the delimiter, not the file

- **WHEN** a form whose style has a `body0` tail is laid out broken with its
  opening delimiter at a column other than 0
- **THEN** its tail elements begin at that same column

#### Scenario: A long head does not change the indentation

- **WHEN** two styled forms with heads of different lengths and the same style
  are laid out broken from the same column
- **THEN** their tails begin at the same column

#### Scenario: The two terminals do not affect each other

- **WHEN** a form with a `body` tail and a form with a `body0` tail are laid out
  broken from the same column
- **THEN** the first form's tail begins two columns further right than the
  second's

### Requirement: Expression positions are looked up and data positions are not

The terminal `e`, and every element of a `body` or `fill` tail, SHALL name an
expression: such an element is laid out by the ordinary rules, so a list among
them consults the style table for its own head.

Every other terminal — `i`, `d`, `f`, `l`, `h`, and the first element of any
clause other than an `ec` clause — SHALL name data. A list in a data position
MUST NOT be looked up in the style table, whatever symbol its first element
spells.

The elements of a `dc*`, `ec*`, `fc*`, or `lc*` tail SHALL be read as clauses and
MUST NOT be looked up as forms.

#### Scenario: A literals list spelling a styled head is not styled

- **WHEN** `(syntax-rules (let) ((_ x) x))` is laid out
- **THEN** the literals list `(let)` is not laid out as a `let` form

#### Scenario: A binding whose name spells a styled head is not styled

- **WHEN** `(let ((if 1)) if)` is laid out at a width that forces breaking
- **THEN** the binding `(if 1)` is not laid out as an `if` form

#### Scenario: A body element is looked up

- **WHEN** `(when a (cond (b c) (else d)))` is laid out at a width that forces
  breaking
- **THEN** the inner `cond` takes its own style

### Requirement: A formals, literals, or definition-head list is filled

Where a slot's terminal is `f`, `l`, or `h` and the element is a list, that list
SHALL be laid out by packing: its elements are joined by a separator that renders
as a space or as a line break, chosen independently at each gap.

Where the element is not a list, the terminal SHALL impose nothing beyond
suppressing lookup.

A bytevector node's elements SHALL be laid out by packing, without reference to
any table, because its elements are octets and no per-form judgment applies.

#### Scenario: A long formals list packs rather than breaking once per name

- **WHEN** a `lambda` whose formals list is too wide for the page is laid out
- **THEN** the formals list occupies more than one line
- **AND** at least one of its lines holds more than one name

#### Scenario: A non-list formals position is unaffected

- **WHEN** `(lambda args (f args))` is laid out
- **THEN** `args` is emitted as itself

#### Scenario: A long bytevector packs

- **WHEN** a bytevector too wide for the page is laid out
- **THEN** at least one of its lines holds more than one octet

### Requirement: A clause is the generic shape with its first element's style overridden

A clause is a list read as a first element followed by a body. A clause SHALL be
laid out by the generic shape, treating its first element as the head. It
therefore introduces no rendering of its own, and its body is not indented from
the clause's own delimiter: it takes whichever of the generic alternatives the
cost objective selects, exactly as any other list would.

The clause terminal SHALL determine only the style of the first element: `d` for
`dc`, `e` for `ec`, `f` for `fc`, and `l` for `lc`. The elements after the first
SHALL be expressions.

A `dc*`, `ec*`, `fc*`, or `lc*` tail SHALL place each remaining element on its own
line, indented as any other tail, with each element laid out as a clause of the
corresponding kind. An element of such a tail that is not a list SHALL be emitted
as itself.

#### Scenario: A cond clause takes the generic shape

- **WHEN** `(cond ((p x) (f x) (g x)))` is laid out at a width that forces the
  clause to break but leaves room to align
- **THEN** `(f x)` shares the line with `(p x)` and `(g x)` begins at the column
  of `(f x)`, which is the generic aligned rendering with `(p x)` as the head
- **AND** at a narrower width the clause drops to the generic hanging rendering,
  as any other list would

#### Scenario: Clauses each begin a line

- **WHEN** `(cond (a b) (else c))` is laid out at a width that forces breaking
- **THEN** `cond` is alone on the first line
- **AND** each clause begins a line of its own, indented two columns

#### Scenario: A case clause fills its literals

- **WHEN** a `case` clause whose literal list is too wide for the page is laid
  out
- **THEN** the literal list occupies more than one line
- **AND** at least one of its lines holds more than one literal

### Requirement: A list of peers is aligned at its first element and never treated as having a head

A list whose style distinguishes no first element — a list whose compiled shape
has no slots, every element being described by a starred tail — is a list of
*peers*. A binding list is the ordinary case: `let`, `let*`, `letrec`, `letrec*`,
`let-values`, `let*-values`, `let-syntax`, `letrec-syntax`, `do`, `parameterize`
and `with-syntax` all place a bare starred terminal in a slot, and the list that
fills that slot is a list of peers.

Such a list SHALL be laid out as one of exactly two renderings:

- **flat** — the opening delimiter, the elements separated by single spaces, and
  the closing delimiter, all on one line;
- **aligned** — one element per line, with **every** element, including the
  first, beginning at the column immediately after the opening delimiter.

It MUST NOT be laid out with its first element treated as a head. In particular
the second element MUST NOT share the opening line with the first, and the
remaining elements MUST NOT begin at the second element's column.

No hanging rendering SHALL be offered. Hanging exists to separate a head from its
arguments, and a peer list has no head.

The alignment SHALL be measured from the opening delimiter, so a break forced
inside the first element — by a trailing comment — cannot move it.

This is distinct from a clause, whose first element *is* distinguished by its
terminal and which keeps the generic shape, and from a filling list, whose gaps
each choose independently. A list of peers whose tail fills SHALL fill; only a
peer list whose tail does not fill is covered here.

#### Scenario: A multi-binding let aligns its bindings

- **WHEN** `(let ([a 1] [b 2] [c 3]) (body))` is laid out at a width that forces
  the binding list to break
- **THEN** each binding begins a line of its own
- **AND** every binding, `[a 1]` included, begins at the same column
- **AND** that column is the one immediately after the binding list's opening
  delimiter

#### Scenario: A binding list that fits stays flat

- **WHEN** `(let ([a 1] [b 2]) (body))` is laid out at a width that accommodates
  it
- **THEN** the whole form is on one line

#### Scenario: The second binding never shares the first binding's line

- **WHEN** a binding list too wide for the page is laid out
- **THEN** no line holds more than one binding

#### Scenario: The rule holds for every form that puts a starred terminal in a slot

- **WHEN** `let*`, `letrec`, `let-values`, `do`, and `parameterize` forms with
  multiple bindings are laid out at a width that forces breaking
- **THEN** each one's binding list places one binding per line, all at the same
  column

#### Scenario: An empty binding list is emitted without alternatives

- **WHEN** `(let () (body))` is laid out
- **THEN** the binding list is emitted as its two delimiters with nothing between
  them

#### Scenario: A clause is unaffected and keeps the generic shape

- **WHEN** `(cond ((p x) (f x) (g x)))` is laid out at a width that forces the
  clause to break but leaves room to align
- **THEN** `(f x)` shares the line with `(p x)`, which is the generic aligned
  rendering with `(p x)` as the head

#### Scenario: A starred tail is unaffected

- **WHEN** a `cond` and a `case-lambda` are laid out at a width that forces
  breaking
- **THEN** each clause begins a line of its own, indented from the opening
  delimiter as any other tail

#### Scenario: A form with a real head is unaffected

- **WHEN** `(some-function a b c)` is laid out at a width that forces breaking
  but leaves room to align
- **THEN** `a` shares the opening line with `some-function`
- **AND** `b` and `c` begin at `a`'s column

### Requirement: A fill tail chooses at each gap independently

A `fill` tail SHALL join its elements with a separator that renders as a single
space or as a line break, chosen independently at each gap by the cost objective.

A filled tail SHALL pack as many elements onto each line as the page width
allows. It MUST NOT place one element per line where more would fit.

#### Scenario: A long export list packs

- **WHEN** an `export` form with more names than fit on one line is laid out
- **THEN** the output occupies more than one line
- **AND** at least one line holds more than one name

#### Scenario: A fill that fits stays on one line

- **WHEN** an `export` form whose names fit within the page width is laid out
- **THEN** the output is one line

### Requirement: An optional identifier slot matches only an identifier

The terminal `i?` SHALL consume the element at its position only if that element
is a leaf whose token kind is an identifier. Otherwise it SHALL consume nothing,
and the remainder of the style SHALL be matched beginning at the same element.

#### Scenario: A named let takes the optional slot

- **WHEN** `(let loop ((x 1)) (loop x))` is laid out at a width that forces
  breaking
- **THEN** `loop` and the binding list share the opening line with `let`

#### Scenario: An ordinary let skips the optional slot

- **WHEN** `(let ((x 1)) x)` is laid out at a width that forces breaking
- **THEN** the binding list shares the opening line with `let`
- **AND** `x` begins a line of its own indented two columns

### Requirement: A form that does not match its style is laid out by the generic shape

The generic shape SHALL be the fallback whenever a style cannot describe the form
in front of it. The system MUST NOT raise, MUST NOT omit any element, and MUST
NOT insert, remove, or reorder anything in order to make a form match.

The fallback SHALL apply when:

- the head is not an identifier leaf, or has no entry in the selected table;
- the form has fewer elements than the style has required slots;
- a slot's terminal requires a list and the element is not one;
- the list is improper;
- any gap from the head through the last slot is not a plain space, which is to
  say a comment has forced a break inside the region a style requires to be on
  one line.

#### Scenario: A form with wrong arity degrades

- **WHEN** `(let)` and `(when)` are laid out
- **THEN** each is emitted with every element present
- **AND** neither raises

#### Scenario: An improper styled form degrades

- **WHEN** `(begin a . b)` is laid out
- **THEN** it is emitted by the generic shape with the dot preserved

#### Scenario: A comment inside the slot region degrades

- **WHEN** a `when` form whose test is preceded by a comment on its own line is
  laid out
- **THEN** the form is laid out by the generic shape
- **AND** the comment remains on a line of its own

#### Scenario: A head with no entry degrades

- **WHEN** `(if a b c)` and `(list a b c)` are laid out at the same width
- **THEN** both take the generic shape
- **AND** the two outputs differ only in the head symbol

### Requirement: A style never moves, drops, or rewrites a comment

A style SHALL choose only among layouts of the item sequence the comment rules
already produced. It MUST NOT reorder items, MUST NOT drop an item, and MUST NOT
alter the text of any token.

Where a comment forces a break inside the region a style would place on the
opening line, the form SHALL fall back to the generic shape rather than move the
comment.

This holds for every terminal, `body0` included: changing a tail's indentation
changes which column a line begins at and nothing else, so the token sequence and
the datum are identical under either terminal.

#### Scenario: A comment is not moved by a style

- **WHEN** a styled form containing a trailing line comment is laid out
- **THEN** the comment remains attached to the item it trailed

#### Scenario: A comment in the slot region forces the generic shape

- **WHEN** a comment forces a break among the elements a style would place on the
  opening line
- **THEN** the form is laid out by the generic shape

#### Scenario: Both safety checks pass under either body terminal

- **WHEN** a source containing a form styled with `body0` is formatted
- **THEN** token equivalence and datum equivalence both pass

### Requirement: The library forms of both dialects use the zero-indent body

The R6RS table's entry for `library` and the R7RS table's entry for
`define-library` SHALL use the `body0` tail, so that a library's body sits at the
column of its opening delimiter.

Both SHALL use it. The two forms are one construct under two spellings, each
wrapping an entire compilation unit, and styling one flush while indenting the
other would make the dialects disagree about a form that plays the same role in
each.

This SHALL be expressed as the tail terminal of those table entries. No code
SHALL branch on the head symbol `library` or `define-library` to achieve it.

Forms appearing inside a library body, `import` and `export` among them, SHALL be
unaffected and keep their own styles.

#### Scenario: An R6RS library body is flush with its opening delimiter

- **WHEN** a `library` form at column 0 is laid out at a width that forces
  breaking
- **THEN** its `export`, `import`, and definition forms each begin at column 0

#### Scenario: An R7RS define-library body is flush with its opening delimiter

- **WHEN** a `define-library` form at column 0 is laid out at a width that forces
  breaking
- **THEN** its body forms each begin at column 0

#### Scenario: Forms inside the library are unaffected

- **WHEN** a library body contains a `define` whose own body breaks
- **THEN** that `define` indents its body two columns as before
