# style-layout Specification

## Purpose

What a style *renders as* -- the layout semantics SRFI 272 declines to supply,
stated here as requirements rather than left for the cost objective to discover.
Every terminal before the tail is a slot sharing the opening line with the head,
at a gap where no break may be taken; the tail lies beneath it, indented two
columns from the opening delimiter and never from the head, so that a long name
cannot push a body across the page. A styled form denotes exactly two layouts,
flat or broken, and they differ in both width and height, so unlike the generic
shape it needs no tie-breaking argument to stay deterministic. Clause terminals
recurse into the generic shape with the clause's first element read as its head,
so a clause introduces no rendering of its own; fill and the packing terminals
choose at each gap independently, because a list of names or of octets carries no
per-element judgment worth a line apiece. Lookup follows position: an expression
position consults the table, a data position does not, so `(syntax-rules (let)
...)` is not a `let`. Everything a style cannot describe -- a head with no entry,
too few elements, an atom where a list was required, an improper list, a comment
forcing a break inside the slot region -- falls back to the generic shape. A
style never raises, never drops an element, and never moves a comment, because it
only chooses among layouts of an item sequence the comment rules already built.
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

### Requirement: A body or clause tail is indented two columns from the opening delimiter

The indentation of a broken tail SHALL be measured from the form's opening
delimiter and SHALL be two columns.

It MUST NOT be measured from the head symbol. It MUST NOT vary with the length of
the head.

This value SHALL be a constant of the implementation and MUST NOT be exposed as
configuration.

#### Scenario: A body is indented two columns

- **WHEN** `(when (ready? x) (go))` is laid out at a width that forces breaking
  with the opening delimiter at column 0
- **THEN** `(go)` begins at column 2

#### Scenario: A long head does not change the indentation

- **WHEN** two styled forms with heads of different lengths and the same style
  are laid out broken from the same column
- **THEN** their tails begin at the same column

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

Applying a style SHALL NOT change which element a comment is attached to, SHALL
NOT change whether a comment stands on its own line, and SHALL NOT change a
comment's contents.

A style SHALL choose among layouts of an item sequence that was already built by
the comment-placement rules. It MUST NOT rebuild that sequence and MUST NOT
consult a comment in deciding a shape, other than to detect that one has forced a
break inside the slot region and fall back.

Styled output SHALL satisfy the same output checks as unstyled output, and the
token sequence of styled output SHALL equal that of the input.

#### Scenario: A trailing comment stays trailing under a style

- **WHEN** a `when` form whose test carries a trailing line comment is laid out
- **THEN** the comment remains on the same line as the test

#### Scenario: Styled output passes the output checks

- **WHEN** every source file in the repository is formatted under the dialect it
  is written in, and a subset of them under each of the other dialect tables
- **THEN** every one passes token equivalence and datum equivalence

#### Scenario: Styling does not break idempotence

- **WHEN** a source is formatted twice under the same dialect and width
- **THEN** the second output equals the first
