## MODIFIED Requirements

### Requirement: One operation runs the whole pipeline over a source text

The system SHALL provide an operation taking source text, a filename for
diagnostics, and a resolved configuration, and running tokenizing, parsing,
translation, layout, and the output checks.

It SHALL return the formatted text together with a result value reporting the
status, the detail belonging to that status, and whether the layout was tainted.
The formatted text SHALL be absent whenever the status is not success.

The resolved configuration SHALL supply the page width, dialect, and that
dialect's style table. The operation MUST NOT fall back to compiled-in defaults.
Resolving a configuration that names no dialect SHALL raise rather than create
a value that could fall back silently at the formatting boundary.

The style table SHALL be passed to translation and SHALL affect nothing else in
the pipeline. Dialect and configuration SHALL NOT affect parsing, refusals, the
layout engine, or checks, and SHALL NOT affect whether a source is accepted.

The operation SHALL perform no file input or output: it takes source text and a
resolved configuration value and returns text and a result. Loading
configuration is a caller responsibility.

#### Scenario: A well-formed source is formatted

- **WHEN** a well-formed source and a resolved configuration are given to the
  operation
- **THEN** the status is success
- **AND** the formatted text is returned

#### Scenario: The width is honored

- **WHEN** the same source is formatted with resolved configurations having
  different page widths
- **THEN** the narrower width produces output with at least as many lines

#### Scenario: Already-formatted input is returned unchanged

- **WHEN** a source that is already in the output form of the resolved
  configuration is formatted with that configuration
- **THEN** the output is identical to the input

#### Scenario: A configured macro style reaches translation

- **WHEN** a resolved configuration defines a style for `my-let`
- **THEN** a `my-let` form is translated using that style

#### Scenario: The dialect defaults to the shared core

- **WHEN** the shipped default configuration is resolved without a user or
  command-line dialect override
- **THEN** its dialect is the shared core

#### Scenario: The dialect changes output but not acceptance

- **WHEN** a source using `define-record-type` is formatted under resolved R6RS
  and R7RS configurations
- **THEN** both runs succeed
- **AND** the two outputs may differ

#### Scenario: A source valid in either standard is accepted under either dialect

- **WHEN** a source containing `#vu8(1 2)` is formatted under a resolved R7RS
  configuration
- **THEN** it is accepted and its opening delimiter is reproduced as `#vu8(`

#### Scenario: An unknown dialect raises

- **WHEN** a library caller attempts to resolve configuration naming no dialect
  for use with the operation
- **THEN** resolution raises
- **AND** the operation receives no configuration value
