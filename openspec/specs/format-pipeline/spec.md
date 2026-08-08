# format-pipeline Specification

## Purpose

The end-to-end operation: source text in, formatted text out, or a reason why
not. It tokenizes, parses, translates, lays out, and then verifies its own work
by re-reading the text it just produced -- never the tree it walked, which is
structurally impossible here because the checks do not accept a tree. It refuses
more than it formats: an unclean parse is not formatted, a source whose
multi-line tokens carry a line ending the engine cannot reproduce is not
formatted, and output that fails a check is not returned at all, because
returning unverified text invites a caller to write it to a file. A tainted
layout is reported rather than failed: the text is complete and checked, and only
the claim that it is minimal was withdrawn. Formatting is idempotent.
## Requirements

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

### Requirement: The pipeline refuses to format an unclean parse

Where tokenizing or parsing produces a non-empty diagnostics list, the operation
SHALL report an unclean-parse status, return no formatted text, and carry the
diagnostics as the detail.

No token SHALL be inserted, dropped, or substituted to repair the input, and no
partial formatting SHALL be emitted.

#### Scenario: An unclosed delimiter is refused

- **WHEN** the source `(a` is formatted
- **THEN** the status is unclean parse
- **AND** no formatted text is returned
- **AND** the diagnostics name the position

#### Scenario: A stray closing delimiter is refused

- **WHEN** the source `(a))` is formatted
- **THEN** the status is unclean parse
- **AND** no formatted text is returned

### Requirement: The pipeline refuses a source whose multi-line tokens carry a foreign line ending

Where a token's text contains a line ending other than the one the layout engine
emits, the operation SHALL report an unsupported-line-ending status, return no
formatted text, and identify the token.

Line endings between tokens SHALL NOT trigger this refusal: they live in
whitespace, which the formatter re-derives, and re-deriving whitespace is the one
change pitch is permitted to make.

The alternative — normalizing the ending — is prohibited, because the declared-
normalizations list is empty and every entry must be argued for in its own
proposal.

#### Scenario: A CRLF inside a block comment is refused

- **WHEN** a source containing a `#| ... |#` comment whose interior line ending is
  a carriage return followed by a line feed is formatted
- **THEN** the status is unsupported line ending
- **AND** no formatted text is returned

#### Scenario: A CRLF-delimited file with no multi-line token is formatted

- **WHEN** a source whose lines are separated by carriage return and line feed,
  containing no string or comment spanning lines, is formatted
- **THEN** the status is success
- **AND** the output's line endings are the engine's

### Requirement: The pipeline verifies output by re-reading the text it produced

The operation SHALL run the combined output check over the input text and the
text the layout produced. It MUST NOT compare a tree against itself, and MUST NOT
pass any in-memory tree to the check.

Where a check fails, the operation SHALL report a check-failed status, carry the
failing layer and its detail, and **return no formatted text**. Output that could
not be verified is never returned under any status.

#### Scenario: The check receives the produced text

- **WHEN** a source is formatted
- **THEN** the check is given the string the layout returned

#### Scenario: A failing check suppresses the output

- **WHEN** the translation is made to produce output that fails token equivalence
- **THEN** the status is check failed
- **AND** the layer reported is token equivalence
- **AND** no formatted text is returned

#### Scenario: A layout-only difference passes

- **WHEN** a source containing comments, brackets, datum comments, and numeric
  lexemes is formatted
- **THEN** both checks pass
- **AND** the status is success

### Requirement: A tainted layout is reported, not failed

Where the layout engine reports that it could not prove the layout minimal, the
operation SHALL still return the formatted text with a success status, and SHALL
report the taint in its result.

Taint means the optimality claim was withdrawn, not that the text is wrong: the
output is complete, valid, and checked like any other.

#### Scenario: An unavoidably wide form still formats

- **WHEN** a source containing a token longer than the page width is formatted
- **THEN** the status is success
- **AND** the result reports the layout as tainted
- **AND** the checks pass

#### Scenario: An ordinary source is not tainted

- **WHEN** a source that fits the page width is formatted
- **THEN** the result reports the layout as not tainted

### Requirement: Formatting is idempotent

Formatting the output of a successful format SHALL produce a byte-identical
result. This SHALL hold at any page width and over the whole test corpus.

#### Scenario: A second run changes nothing

- **WHEN** a source is formatted and its output is formatted again at the same
  width
- **THEN** the two outputs are byte identical

#### Scenario: Idempotence holds for sources with comments

- **WHEN** a source with trailing comments, own-line comments, and blank lines is
  formatted twice
- **THEN** the two outputs are byte identical

#### Scenario: Idempotence holds across the in-repo corpus

- **WHEN** every source file in the repository is formatted twice
- **THEN** each file's two outputs are byte identical
