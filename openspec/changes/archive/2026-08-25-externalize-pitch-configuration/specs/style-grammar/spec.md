## MODIFIED Requirements

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

## ADDED Requirements

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
