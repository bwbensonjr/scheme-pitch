# style-grammar Specification

## Purpose

What a style *is*, and nothing about what it renders as. The on-disk notation is
SRFI 272's -- `(_ h . body)`, `(_ i? fc* . body)`, `(_ e l . dc*)` -- adopted
because it is Scheme-native and already community-vetted, and adopted for the
grammar alone: SRFI 272 is a datum printer that explicitly leaves the layout
algorithm unspecified, and the algorithm is the one property pitch sells. A style
is compiled into a shape descriptor when the table holding it is constructed, so
a defective entry raises where it was written rather than surprising someone
mid-format, and that compilation runs on every run whatever source is in front of
it. A table is an immutable mapping from a symbol to a descriptor holding no
procedure, no document and no tree; the library defining tables imports neither
the CST, the document, nor the reader library, which is what turns "style tables
are data, not code" into something checkable rather than aspirational. A head is
matched by the token's parsed value, so `|cond|` and, under `#!fold-case`,
`COND`, match what they mean. Three tables exist -- a shared core and one per
dialect -- because `define-record-type` is a genuine R6RS/R7RS collision that no
union of the two shapes resolves; a dialect at this layer selects a table and
nothing else.
## Requirements

### Requirement: A style is written in the SRFI 272 style notation

A style SHALL be a Scheme datum of the form `(_ . fmt-tail)`, where:

```
fmt-tail ::= body | body0 | fill | dc* | ec* | fc* | lc*
           | (i? . fmt-tail) | (fmt . fmt-tail)
fmt      ::= i | d | e | f | l | h | dc | ec | fc | lc | fmt-tail
```

The system SHALL accept every terminal in that grammar. No terminal outside it
SHALL be accepted.

The grammar is SRFI 272's, with one addition. `body0` is pitch's own and is not
an SRFI 272 terminal; every other terminal above is SRFI 272's, spelled as SRFI
272 spells it. The grammar SHALL remain closed: the terminals are a finite
enumeration, and a datum naming anything outside it is refused rather than
interpreted.

The addition is admitted for one reason and its scope is bounded by it. A rule
about how a particular form is laid out has to be expressible as data, because
per-form layout rules are prohibited from appearing as code that branches on a
head symbol. A form whose body is not indented is such a rule, so the notation
is where it has to live. No further extension SHALL be made on this precedent
without its own argument.

The system MUST NOT depend on SRFI 272 for the layout of any form, because SRFI
272 leaves the layout algorithm unspecified. Every terminal's layout semantics,
`body0`'s included, is pitch's own and is stated in `style-layout`.

#### Scenario: A style with slots and a body tail is accepted

- **WHEN** the style `(_ i? fc* . body)` is read
- **THEN** it is accepted

#### Scenario: Every terminal is accepted somewhere

- **WHEN** styles exercising each of `i`, `d`, `e`, `f`, `l`, `h`, `i?`, `dc`,
  `ec`, `fc`, `lc`, `dc*`, `ec*`, `fc*`, `lc*`, `body`, `body0`, and `fill` are
  read
- **THEN** each is accepted

#### Scenario: A nested tail is accepted in a slot position

- **WHEN** the style `(_ (i . ec*) . body)` is read
- **THEN** it is accepted
- **AND** the first slot describes a subform that is itself a list

#### Scenario: A zero-indent body tail is accepted

- **WHEN** the style `(_ d . body0)` is read
- **THEN** it is accepted
- **AND** its tail is the zero-indent body terminal

#### Scenario: The grammar stays closed

- **WHEN** a style naming a terminal that is neither SRFI 272's nor `body0` is
  read
- **THEN** it is refused where the table is built

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

A resolved configuration SHALL provide three tables: a shared core, an R6RS
table, and an R7RS table. Each dialect table SHALL comprise the resolved core
entries followed by its dialect-specific additions, replacements, and removals.
A shared entry that neither dialect overrides SHALL compile to one descriptor
reachable from both dialect tables.

A dialect SHALL be named by a symbol, and the system SHALL provide an operation
mapping that symbol and a resolved configuration to its table. A symbol naming
no dialect SHALL raise, because it comes from a caller or validated
configuration rather than from a Scheme source file.

A dialect at this layer SHALL select a style table and nothing else.

The shipped default configuration SHALL give `define-record-type` different
styles in the R6RS and R7RS tables and no entry in the core, since the two shapes
are incompatible and no union of them is correct.

#### Scenario: A shared entry appears in both dialect tables

- **WHEN** `cond` is configured in the common table and not overridden in either
  dialect table
- **THEN** the same descriptor is returned from the resolved R6RS and R7RS
  tables

#### Scenario: The colliding head differs by dialect

- **WHEN** the shipped default configuration is resolved and
  `define-record-type` is looked up in the R6RS and R7RS tables
- **THEN** the two descriptors differ

#### Scenario: The colliding head is absent from the core

- **WHEN** the shipped default configuration is resolved and
  `define-record-type` is looked up in the core table
- **THEN** the lookup reports that there is none

#### Scenario: An unknown dialect raises

- **WHEN** a symbol naming no dialect is given to the table-selecting operation
  with a resolved configuration
- **THEN** it raises

### Requirement: Style entries are supplied as configuration data

The style library SHALL expose the closed style grammar, descriptor types, and
operations for constructing and looking up immutable tables. It MUST NOT embed
Pitch's default head-to-style entries or instantiate process-global default
tables.

Adding, replacing, or removing a configured per-form rule MUST NOT require a
change to the style library, CST translation, or layout engine. A malformed
configured style SHALL be refused when configuration is resolved, before any
source is formatted.

The style library SHALL continue to import neither the CST, document, reader,
nor configuration-loading libraries. Configuration may depend on the style
grammar; the style grammar MUST NOT depend on configuration or I/O.

#### Scenario: Changing a macro style changes only data

- **WHEN** a project changes the configured style for one macro
- **THEN** no Scheme library or executable needs to be rebuilt

#### Scenario: The style library has no default entries

- **WHEN** the style library is inspected
- **THEN** it contains no list mapping Pitch's default head names to styles
- **AND** it performs no configuration file I/O

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
