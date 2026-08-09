## MODIFIED Requirements

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

## ADDED Requirements

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

## RENAMED Requirements

- FROM: `### Requirement: A body or clause tail is indented two columns from the opening delimiter`
- TO: `### Requirement: A body or clause tail is indented from the opening delimiter by its terminal's amount`
