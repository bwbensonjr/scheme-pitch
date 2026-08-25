## Purpose

Define Pitch's bounded configuration as validated Scheme data, including how
shipped defaults, an explicit user file, and command-line overrides compose
before any source is formatted.

## ADDED Requirements

### Requirement: Configuration is inert versioned Scheme data

A configuration file SHALL contain exactly one datum of this form:

```scheme
(pitch-config 1
  (width 88)
  (dialect common)
  (styles common
    ((head ...) (_ . fmt-tail))
    ((head ...) remove))
  (styles r6rs ...)
  (styles r7rs ...))
```

The `width` and `dialect` fields and each dialect's `styles` field SHALL be
optional in a user configuration and SHALL occur at most once. Width SHALL be a
positive exact integer. Dialect SHALL be `common`, `r6rs`, or `r7rs`. Each style
definition SHALL name a non-empty list of distinct symbols and SHALL contain
either a style accepted by `style-grammar` or the literal symbol `remove`.

The system SHALL reject an unsupported version, an unknown or duplicate field,
an unknown dialect, a repeated head within one style section, an invalid value,
an unclean parse, more or fewer than one top-level datum, and any malformed
style. It MUST NOT silently ignore configuration data.

Configuration SHALL be parsed as data through Pitch's own reader and datum
projection. The system MUST NOT pass configuration text to a host
implementation's `read`, `load`, or `eval`, and configuration MUST NOT be able to
execute code.

#### Scenario: A partial user configuration is accepted

- **WHEN** a user configuration contains only `(pitch-config 1 (width 100))`
- **THEN** it is accepted as an overlay that changes only the page width

#### Scenario: Comments do not make configuration executable

- **WHEN** a valid configuration contains line or block comments
- **THEN** it is parsed as inert data and the comments have no effect on its
  values

#### Scenario: An unknown field is refused

- **WHEN** a configuration contains `(reorder-definitions #t)`
- **THEN** the configuration is rejected rather than ignoring or interpreting
  that field

#### Scenario: Host evaluation syntax is never executed

- **WHEN** configuration text contains a datum that would execute only if it
  were passed to `load` or `eval`
- **THEN** no code is executed
- **AND** the datum is rejected by the configuration schema

### Requirement: Shipped defaults are external configuration

Pitch SHALL ship a complete default configuration containing width 88, dialect
`common`, and the common, R6RS, and R7RS style entries. Those scalar defaults and
style entries MUST reside in an installed data file rather than in a Scheme
library or compiled program image.

Every formatting invocation SHALL read and validate the shipped default
configuration before resolving settings. A missing, unreadable, or invalid
default configuration SHALL fail the invocation and SHALL NOT fall back to
compiled values.

#### Scenario: No user configuration uses external defaults

- **WHEN** Pitch formats a source without `--config`, `--width`, or `--dialect`
- **THEN** it reads the shipped default configuration
- **AND** formats at width 88 under the common style table described by that
  file

#### Scenario: A missing default file is not hidden

- **WHEN** the installed default configuration cannot be read
- **THEN** the invocation reports a configuration error
- **AND** no source input is read or written

### Requirement: Configuration layers compose deterministically

The system SHALL resolve configuration in this order, from lowest to highest
precedence:

1. the shipped default configuration;
2. the one user configuration explicitly named by `--config`, when present;
3. explicit `--width` and `--dialect` values.

A user scalar field SHALL replace the corresponding default. A user style
definition SHALL add or replace that head's definition in the named dialect.
The literal `remove` SHALL make that head absent in the named dialect.

The resolved common table SHALL be formed first. The resolved R6RS and R7RS
tables SHALL each inherit that common table and then apply their own dialect
operations, so a dialect-specific `remove` can mask an inherited common entry.
Composition SHALL be independent of the textual ordering of `styles` sections.

The system SHALL NOT search the working directory, operand directories, parent
directories, a home directory, or environment-specific configuration locations
for another file. Naming a configuration SHALL be explicit and one invocation
SHALL use one resolved configuration for all of its inputs.

#### Scenario: Command-line width wins

- **WHEN** the default width is 88, a user configuration sets width 100, and
  `--width 72` is present
- **THEN** every source in the invocation is formatted at width 72

#### Scenario: A project macro adds a common style

- **WHEN** a user configuration adds `my-let` to the common styles
- **THEN** `my-let` uses that style under the common, R6RS, and R7RS dialects

#### Scenario: A dialect removes an inherited style

- **WHEN** a user configuration removes `when` from R6RS styles only
- **THEN** `when` uses the generic shape under R6RS
- **AND** retains its configured common style under `common` and R7RS

#### Scenario: No configuration is discovered implicitly

- **WHEN** an unmentioned configuration file exists beside an operand or in an
  ancestor directory
- **THEN** it has no effect on the invocation

### Requirement: Configuration failure precedes source processing

The shipped and user configurations SHALL be read, parsed, composed, and fully
validated before any source operand or standard input is read. Any configuration
error SHALL identify the configuration path and the invalid field or datum,
produce the usage-error status, and leave every source file untouched.

Help, version, an unknown option, and another error discoverable from the
argument list SHALL complete without reading either configuration file.

#### Scenario: A malformed style leaves every source untouched

- **WHEN** a user configuration contains a malformed style and the invocation
  names multiple source files
- **THEN** Pitch reports the configuration path and malformed style
- **AND** none of the source files is read or written

#### Scenario: Help does not depend on installed configuration

- **WHEN** `pitch --help` is invoked while the shipped default is missing
- **THEN** help is written successfully
- **AND** no configuration file is read
