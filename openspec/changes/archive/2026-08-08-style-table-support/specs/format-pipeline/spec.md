## MODIFIED Requirements

### Requirement: One operation runs the whole pipeline over a source text

The system SHALL provide an operation taking a source text, a filename for
diagnostics, a page width, and a dialect, and running tokenizing, parsing,
translation, layout, and the output checks.

It SHALL return the formatted text together with a result value reporting the
status, the detail belonging to that status, and whether the layout was tainted.
The formatted text SHALL be absent whenever the status is not success.

The page width SHALL default to 88. The dialect SHALL default to the shared core,
so that a caller naming no dialect gets the entries common to both standards and
nothing that differs between them. A symbol naming no dialect SHALL raise rather
than falling back silently.

The dialect SHALL be passed to the translation and SHALL affect nothing else in
the pipeline: parsing, the refusals, the layout engine, and the checks are all
independent of it. It SHALL NOT affect whether a source is accepted.

The operation SHALL perform no file input or output: it takes a text and returns
a text.

#### Scenario: A well-formed source is formatted

- **WHEN** a well-formed source is given to the operation
- **THEN** the status is success
- **AND** the formatted text is returned

#### Scenario: The width is honored

- **WHEN** the same source is formatted at two different page widths
- **THEN** the narrower width produces output with at least as many lines

#### Scenario: Already-formatted input is returned unchanged

- **WHEN** a source that is already in pitch's output form is formatted
- **THEN** the output is identical to the input

#### Scenario: The dialect defaults to the shared core

- **WHEN** a source is formatted with no dialect given
- **THEN** the output is the same as formatting it under the shared core table

#### Scenario: The dialect changes output but not acceptance

- **WHEN** a source using `define-record-type` is formatted under the R6RS
  dialect and under the R7RS dialect
- **THEN** both runs succeed
- **AND** the two outputs may differ

#### Scenario: A source valid in either standard is accepted under either dialect

- **WHEN** a source containing `#vu8(1 2)` is formatted under the R7RS dialect
- **THEN** it is accepted and its opening delimiter is reproduced as `#vu8(`

#### Scenario: An unknown dialect raises

- **WHEN** a symbol naming no dialect is given to the operation
- **THEN** it raises
