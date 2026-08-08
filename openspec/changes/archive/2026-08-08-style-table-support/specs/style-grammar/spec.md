## ADDED Requirements

### Requirement: A style is written in the SRFI 272 style notation

A style SHALL be a Scheme datum of the form `(_ . fmt-tail)`, where:

```
fmt-tail ::= body | fill | dc* | ec* | fc* | lc*
           | (i? . fmt-tail) | (fmt . fmt-tail)
fmt      ::= i | d | e | f | l | h | dc | ec | fc | lc | fmt-tail
```

The system SHALL accept every terminal in that grammar. No terminal outside it
SHALL be accepted, and no notation of pitch's own SHALL be introduced alongside
it.

The grammar is the only part of SRFI 272 adopted. The system MUST NOT depend on
SRFI 272 for the layout of any form, because SRFI 272 leaves the layout algorithm
unspecified.

#### Scenario: A style with slots and a body tail is accepted

- **WHEN** the style `(_ i? fc* . body)` is read
- **THEN** it is accepted

#### Scenario: Every terminal is accepted somewhere

- **WHEN** styles exercising each of `i`, `d`, `e`, `f`, `l`, `h`, `i?`, `dc`,
  `ec`, `fc`, `lc`, `dc*`, `ec*`, `fc*`, `lc*`, `body`, and `fill` are read
- **THEN** each is accepted

#### Scenario: A nested tail is accepted in a slot position

- **WHEN** the style `(_ (i . ec*) . body)` is read
- **THEN** it is accepted
- **AND** the first slot describes a subform that is itself a list

### Requirement: A style is compiled once and a malformed style is refused where it is written

A style SHALL be compiled into a shape descriptor when the table containing it is
constructed, not when a form is laid out.

A datum that is not a well-formed style SHALL raise at that point. The system
MUST NOT accept a malformed style and MUST NOT silently ignore one.

Compilation SHALL be exercised on every run, so that a defective entry surfaces
regardless of what source is being formatted.

#### Scenario: A style not beginning with the placeholder is refused

- **WHEN** the datum `(x . body)` is read as a style
- **THEN** it raises

#### Scenario: An unknown terminal is refused

- **WHEN** the datum `(_ q . body)` is read as a style
- **THEN** it raises

#### Scenario: A style with no tail is refused

- **WHEN** the datum `(_ i e)` is read as a style
- **THEN** it raises

#### Scenario: A defective entry fails without any source being formatted

- **WHEN** a table containing a malformed style is constructed
- **THEN** it raises
- **AND** no CST, document, or source text is involved

### Requirement: A style table maps a head symbol to a style and holds no code

A style table SHALL be an immutable mapping from a symbol to a shape descriptor,
supporting a lookup that returns the descriptor for a symbol or an indication
that the symbol has none.

A table SHALL contain only data. It MUST NOT contain a procedure, a document, or
a CST node, and the library defining tables MUST NOT import the CST, document, or
reader libraries.

Adding, changing, or removing a per-form layout rule SHALL be an edit to a table
entry and MUST NOT require an edit to the translation.

#### Scenario: A head with an entry is found

- **WHEN** the symbol `cond` is looked up in a table containing it
- **THEN** the corresponding descriptor is returned

#### Scenario: A head with no entry is reported absent

- **WHEN** a symbol with no entry is looked up
- **THEN** the lookup reports that there is none
- **AND** it does not raise

#### Scenario: The table library depends on neither trees nor documents

- **WHEN** the library defining style tables is inspected
- **THEN** it imports neither the CST library, the document library, nor the
  reader library

### Requirement: A dialect selects one of three tables

The system SHALL provide three tables: a shared core, an R6RS table, and an R7RS
table. Each dialect table SHALL comprise the core entries plus its own, so that a
shared entry is written exactly once.

A dialect SHALL be named by a symbol, and the system SHALL provide an operation
mapping that symbol to its table. A symbol naming no dialect SHALL raise, because
it comes from a caller rather than from a source file.

A dialect at this layer SHALL select a style table and nothing else.

`define-record-type` SHALL have different styles in the R6RS and R7RS tables and
SHALL have no entry in the core, since the two shapes are incompatible and no
union of them is correct.

#### Scenario: A shared entry appears in both dialect tables

- **WHEN** `cond` is looked up in the R6RS table and in the R7RS table
- **THEN** the same descriptor is returned from each

#### Scenario: The colliding head differs by dialect

- **WHEN** `define-record-type` is looked up in the R6RS table and in the R7RS
  table
- **THEN** the two descriptors differ

#### Scenario: The colliding head is absent from the core

- **WHEN** `define-record-type` is looked up in the core table
- **THEN** the lookup reports that there is none

#### Scenario: An unknown dialect raises

- **WHEN** a symbol naming no dialect is given to the table-selecting operation
- **THEN** it raises

### Requirement: A head is matched by the token's value

A list node's head SHALL be its first datum child. Where that child is a leaf
whose token kind is an identifier, the lookup key SHALL be the token's parsed
value.

Any other head — a compound, a prefix, a string, a number, or an absent one —
SHALL match no entry.

Matching by parsed value rather than by token text means that spellings the
reader resolves to the same symbol SHALL match the same entry, including a
`|...|`-escaped identifier and an identifier folded by `#!fold-case`.

#### Scenario: An escaped spelling matches the same entry

- **WHEN** a form whose head is written `|cond|` is laid out
- **THEN** it takes the same shape as one whose head is written `cond`

#### Scenario: A folded identifier matches the same entry

- **WHEN** a source containing `#!fold-case` is laid out and a form whose head is
  written `COND` appears after it
- **THEN** that form takes the same shape as one whose head is written `cond`

#### Scenario: A compound head matches nothing

- **WHEN** a form whose first element is itself a list is laid out
- **THEN** no table entry applies to it
