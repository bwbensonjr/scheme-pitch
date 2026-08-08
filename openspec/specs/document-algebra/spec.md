# document-algebra Specification

## Purpose

The language the layout engine resolves. A document denotes a set of candidate
layouts rather than one rendering, and is an immutable value carrying no
resolution state, so it may be shared, cached, and resolved any number of times
under any number of cost objectives. The core is ten constructors - text,
newline, concat, alternatives, nest, align, reset, full, cost and fail - with
every other combinator defined in terms of them. `text` refuses a line ending,
because column arithmetic is the whole cost model and because a line comment's
token text carries the newline that terminated it. Construction simplifies where
simplification preserves the denoted layouts and their costs. Nothing here knows
about Scheme: no tokens, no comments, no brackets, no dialects.
## Requirements

### Requirement: A document is an immutable value describing a set of layouts

The system SHALL provide a document type. A document denotes a set of candidate
layouts; it does not denote a single rendering, and it carries no state that
resolution mutates.

The same document SHALL be resolvable any number of times, with any cost
factories, always yielding the same result for the same arguments. Documents
SHALL be shareable: the same document value may appear at many positions inside
a larger one.

#### Scenario: Resolving a document twice gives the same result

- **WHEN** a document is laid out twice with the same factory and offset
- **THEN** both results are identical in text, cost, and taint

#### Scenario: A document may be shared

- **WHEN** one document value is used as a sub-document in several positions
- **THEN** the result is the same as if a structurally equal copy had been used
  at each position

### Requirement: The core constructors

The system SHALL provide these document constructors, and every other combinator
SHALL be definable in terms of them.

| Constructor | Meaning |
|---|---|
| `(text s)` | the literal string `s`, advancing the column by its length |
| `(newline s)` | a line break; when flattened it becomes `(text s)`, or fails if `s` is `#f` |
| `(concat a b)` | `a` followed by `b` |
| `(alternatives a b)` | either `a` or `b`, whichever the resolver prefers |
| `(nest n d)` | `d` with the indentation increased by `n` |
| `(align d)` | `d` with the indentation set to the current column |
| `(reset d)` | `d` with the indentation set to zero |
| `(full d)` | `d`, required to be followed by a line break |
| `(cost n d)` | `d`, with `n` added to its cost |
| `fail` | no layout |

Indentation affects only what a `newline` emits after the break. It SHALL NOT
affect a document that contains no `newline`.

#### Scenario: Text advances the column

- **WHEN** `(text "abc")` is laid out at column 0
- **THEN** the rendered text is `abc` and the resulting column is 3

#### Scenario: A newline indents by the current indentation

- **WHEN** `(nest 4 (concat (text "a") (concat hard-nl (text "b"))))` is laid out
  at column 0 and indentation 0
- **THEN** the rendered text is `a`, a line break, four spaces, and `b`

#### Scenario: Align sets indentation to the current column

- **WHEN** `(concat (text "ab") (align (concat (text "c") (concat hard-nl (text "d")))))`
  is laid out at column 0
- **THEN** the second line is indented to column 2

#### Scenario: Reset returns indentation to zero

- **WHEN** a document containing a line break appears inside `reset`, nested
  within an enclosing `nest` or `align`
- **THEN** the line after the break is indented to column 0

#### Scenario: Indentation is unobservable without a line break

- **WHEN** `(nest 4 (text "a"))` and `(text "a")` are laid out identically
- **THEN** both render as `a`

### Requirement: Text may not contain a line ending

`(text s)` SHALL raise an error when `s` contains a line ending. It MUST NOT
split the string, and MUST NOT accept it.

The line endings recognized SHALL be the same set the reader's grammar counts and
`token-equivalence` names: line feed, carriage return, carriage return followed
by line feed, carriage return followed by next line, next line, line separator,
and paragraph separator.

The reason is that the column arithmetic and the cost of a text are computed from
its length, so an embedded line ending makes both silently wrong. It also forces
a caller emitting a line comment — whose token text includes its terminating line
ending — to split that ending off and state explicitly what follows it.

#### Scenario: A line feed inside text is refused

- **WHEN** `(text "a\nb")` is constructed
- **THEN** an error is raised
- **AND** no document is produced

#### Scenario: Every recognized line ending is refused

- **WHEN** `text` is given a string containing any one of the seven recognized
  line endings
- **THEN** an error is raised in each case

#### Scenario: A comment's token text is refused

- **WHEN** `text` is given the text of a line comment token, which ends with the
  line ending that terminated it
- **THEN** an error is raised

#### Scenario: Text without a line ending is accepted

- **WHEN** `(text "; a comment")` is constructed
- **THEN** a document is produced

### Requirement: Failure is the unit of choice and the zero of concatenation

`fail` SHALL denote the empty set of layouts.

Concatenation with `fail` on either side SHALL be `fail`. Choice with `fail` on
either side SHALL be the other alternative. A document all of whose alternatives
fail SHALL itself fail.

`(concat (full d) (text s))` with `s` non-empty SHALL be `fail`, because nothing
may follow a document required to end its line.

#### Scenario: Concatenation with failure fails

- **WHEN** `(concat fail (text "a"))` or `(concat (text "a") fail)` is constructed
- **THEN** the result denotes no layout

#### Scenario: Choice discards a failing alternative

- **WHEN** `(alternatives fail (text "a"))` is laid out
- **THEN** the result is `a`

#### Scenario: Text after a full document fails

- **WHEN** `(concat (full (text "a")) (text "b"))` is constructed
- **THEN** the result denotes no layout

#### Scenario: An empty text after a full document is permitted

- **WHEN** `(concat (full (text "a")) (text ""))` is laid out
- **THEN** it is equivalent to `(full (text "a"))`

### Requirement: Construction simplifies where simplification preserves meaning

The constructors SHALL simplify at construction time. Every simplification MUST
preserve the set of layouts the document denotes and the cost of each.

The simplifications SHALL include: dropping an empty `text` from a concatenation;
merging two adjacent texts; collapsing `alternatives` of a document with itself;
combining nested `nest` amounts; and dropping `nest`, `align`, or `reset` applied
to a `text`, an `align`, or a `reset`.

A consequence is that the constructors are not injective, so a caller MUST NOT
depend on recovering the shape it built.

#### Scenario: An empty text is dropped

- **WHEN** `(concat (text "") d)` is constructed
- **THEN** the result lays out identically to `d`

#### Scenario: Adjacent texts merge

- **WHEN** `(concat (text "ab") (text "cd"))` is laid out
- **THEN** the result is `abcd` with the same cost as `(text "abcd")`

#### Scenario: Nested nests combine

- **WHEN** `(nest 2 (nest 3 d))` is laid out
- **THEN** the result is identical to `(nest 5 d)`

#### Scenario: Indentation on a text is dropped

- **WHEN** `(nest 4 (text "a"))` is laid out
- **THEN** the result is identical to `(text "a")`

### Requirement: The derived combinators

The system SHALL provide, defined in terms of the core:

- `empty-doc`, equal to `(text "")`.
- `nl`, equal to `(newline " ")`; `break`, equal to `(newline "")`; `hard-nl`,
  equal to `(newline #f)`.
- `alt`, choice over any number of documents, failing when given none.
- `(flatten d)`, which replaces every `newline` in `d` by its flat string and
  fails where that string is `#f`, discarding `nest`, `align`, and `reset`
  along the way.
- `(group d)`, equal to `(alt d (flatten d))`.
- Five append families, each with an `-append` variadic form and a `-concat`
  list form: `u-` unaligned concatenation, `us-` unaligned separated by a space,
  `v-` separated by `hard-nl`, `a-` concatenation aligning the right operand,
  and `as-` the same separated by a space.

Each `-append` SHALL yield `empty-doc` when given no arguments and its sole
argument when given one.

Racket's infix aliases (`<>`, `<$>`, `<+>`, `<s>`, `<+s>`) SHALL NOT be provided.

#### Scenario: Flatten replaces a soft newline with its string

- **WHEN** `(flatten (concat (text "a") (concat nl (text "b"))))` is laid out
- **THEN** the result is `a b` on one line

#### Scenario: Flatten fails on a hard newline

- **WHEN** `(flatten hard-nl)` is laid out
- **THEN** the result denotes no layout

#### Scenario: Group chooses between flat and broken

- **WHEN** a group whose flat rendering fits the page width is laid out
- **THEN** the flat rendering is chosen
- **WHEN** the same group is laid out at a page width the flat rendering exceeds
- **THEN** the broken rendering is chosen

#### Scenario: Flatten discards indentation

- **WHEN** `(flatten (nest 4 d))` is laid out
- **THEN** the result is identical to `(flatten d)`

### Requirement: Flatten reaches a newline under every wrapper

`flatten` SHALL replace a `newline` wherever it occurs, including when it is the
immediate child of `align`, `nest`, or `reset`. Discarding those wrappers MUST
NOT cause the document beneath them to escape flattening.

This is stated separately because the reference implementation gets it wrong:
it strips the wrapper and then maps over the child's children rather than
recurring on the child, so a newline directly beneath one of the three survives.
The consequence is that `(group (align d))` — the shape a Lisp printer uses
most, "flat if it fits, else break and align" — can emit a line break from its
*flat* alternative. A formatter that promises to change only whitespace cannot
have a `group` that breaks lines behind its own back.

These scenarios MUST be asserted directly rather than through the differential
oracle, which cannot cover behavior the two implementations disagree on by
intent.

#### Scenario: A soft newline directly under align flattens

- **WHEN** `(flatten (align nl))` is laid out
- **THEN** the result is a single space
- **AND** it is not a line break

#### Scenario: A soft newline directly under nest or reset flattens

- **WHEN** `(flatten (nest 2 nl))` and `(flatten (reset nl))` are laid out
- **THEN** each result is a single space

#### Scenario: A hard newline directly under align fails

- **WHEN** `(flatten (align hard-nl))` is laid out
- **THEN** the document denotes no layout

#### Scenario: Group of that shape has only the broken alternative

- **WHEN** `(group (align hard-nl))` is laid out
- **THEN** the result is a line break
- **AND** no flat alternative is available to choose

#### Scenario: An append family with no arguments is empty

- **WHEN** `(u-append)` is laid out
- **THEN** the result is the empty string

#### Scenario: The aligned family aligns its right operand

- **WHEN** `(a-append (text "ab") d)` is laid out at column 0, where `d` contains
  a line break
- **THEN** the line after the break is indented to column 2
