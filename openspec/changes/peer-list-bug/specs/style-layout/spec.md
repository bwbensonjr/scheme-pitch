## ADDED Requirements

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
