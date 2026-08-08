## ADDED Requirements

### Requirement: A verbatim combinator emits a string that may contain a line ending

The system SHALL provide `(verbatim s)`, a derived combinator defined in terms of
the core, producing a document that renders `s` exactly.

Where `s` contains no line ending, `verbatim` SHALL be `(text s)`.

Where `s` contains line endings, `verbatim` SHALL split `s` at them and join the
pieces with a line break that fails when flattened and that adds no indentation.
The line endings recognized SHALL be the ones `text` refuses. That set SHALL have
exactly one definition in the codebase, shared by every layer that needs it
rather than copied into each.

This exists because `text` refuses a line ending and a caller may hold a string
that legally contains one. Adding indentation to the continuation lines is not
permitted: the caller may be emitting a string literal, where indentation changes
the value denoted, or a comment, where it rewrites the comment's contents.

`verbatim` MUST NOT alter the characters between the endings, and MUST NOT
collapse, insert, or remove any.

#### Scenario: A string without a line ending is a text

- **WHEN** `(verbatim "abc")` is laid out at column 0
- **THEN** the rendered text is `abc` and the resulting column is 3

#### Scenario: A string with a line ending renders on two lines

- **WHEN** `(verbatim "ab\ncd")` is laid out at column 0
- **THEN** the rendered text is `ab`, a line break, and `cd`

#### Scenario: Continuation lines receive no indentation

- **WHEN** `(nest 4 (verbatim "ab\n  cd"))` is laid out
- **THEN** the second line is exactly `  cd`
- **AND** the four spaces of the enclosing indentation are not added to it

#### Scenario: Alignment does not reach inside

- **WHEN** `(concat (text "xy") (align (verbatim "ab\ncd")))` is laid out at
  column 0
- **THEN** the second line is exactly `cd`

#### Scenario: A verbatim containing a line ending has no flat layout

- **WHEN** `(group (verbatim "ab\ncd"))` is laid out
- **THEN** the result still occupies two lines
- **AND** no single-line alternative is available to choose

#### Scenario: Every recognized line ending splits

- **WHEN** `verbatim` is given a string containing any one of the seven
  recognized line endings
- **THEN** the result renders on two lines in each case

#### Scenario: Interior characters are untouched

- **WHEN** `(verbatim "a  b\n   c  ")` is laid out
- **THEN** every space between the endings appears in the output unchanged
