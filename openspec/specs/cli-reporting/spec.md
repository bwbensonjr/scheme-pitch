# cli-reporting Specification

## Purpose

What a run tells its caller. Three exit statuses, and they are not collapsible:
0 for a clean run, 1 for code that was refused or that `--check` says would
change, 2 for an invocation or an environment that is wrong. A
continuous-integration job must be able to tell "this code is unformatted" from
"this invocation is wrong", so an unreadable or missing path yields 2 rather than
1, which would claim a formatting violation that does not exist. A run's status
is the worst status of its parts, which is what lets it continue past a failure
without the failure being forgotten. Diagnostics go to standard error as
`path:line:column: message`, the form editors and line-oriented tools already
parse, with the position taken from the token the diagnostic is anchored to and
never invented for a refusal that has none; several diagnostics from one unclean
parse come out in source order. A tainted layout is reported to nobody and
changes nothing: it is a withdrawn minimality claim over text that is complete
and checked, its usual cause is a token wider than the page, and a warning nobody
can act on teaches people to ignore the ones that matter.
## Requirements

### Requirement: The exit status distinguishes success, failure, and usage error

The system SHALL exit with one of exactly three statuses:

| Status | Meaning |
|---|---|
| 0 | every selected input succeeded; under `--check`, nothing would change |
| 1 | at least one input was refused, or under `--check` at least one would change |
| 2 | a usage error: no arguments at all, an invocation naming no input, an unknown option, a missing option value, an invalid width or dialect, incompatible dispositions, `-` combined with another operand, or a path that cannot be read |

The three SHALL NOT be collapsed. A continuous-integration job must be able to
tell "this code is unformatted" from "this invocation is wrong", and a single
non-zero status makes that impossible.

A path that does not exist or cannot be read or written SHALL yield status 2
rather than 1. It is a fact about the invocation or the environment, not about
the formatting of any code, and a `--check` job reporting status 1 for an
unreadable file would claim a formatting violation that does not exist.

#### Scenario: A clean run exits zero

- **WHEN** every selected file is formatted successfully
- **THEN** the exit status is 0

#### Scenario: A refusal exits one

- **WHEN** any selected file is refused by the pipeline
- **THEN** the exit status is 1

#### Scenario: Check mode exits one when something would change

- **WHEN** `--check` is given and any selected file would change
- **THEN** the exit status is 1

#### Scenario: Check mode exits zero when nothing would change

- **WHEN** `--check` is given and no selected file would change
- **THEN** the exit status is 0

#### Scenario: A bad option exits two

- **WHEN** an unknown option is given
- **THEN** the exit status is 2

#### Scenario: A bare invocation exits two

- **WHEN** the program is invoked with no arguments at all
- **THEN** the exit status is 2
- **AND** the usage summary is on standard error

#### Scenario: An explicit help request exits zero

- **WHEN** the program is invoked with `--help`
- **THEN** the exit status is 0
- **AND** the usage summary is on standard output

#### Scenario: Naming no input exits two

- **WHEN** the program is invoked with `--check` and no operand
- **THEN** the exit status is 2

#### Scenario: A dash mixed with another operand exits two

- **WHEN** the program is invoked with the operands `-` and a file
- **THEN** the exit status is 2

#### Scenario: An unreadable path exits two rather than one

- **WHEN** an operand names a file that cannot be read and every other file is
  already formatted
- **THEN** the exit status is 2

### Requirement: The status of a run is the worst status of its parts

Where several inputs are processed, the system SHALL return the worst status any
one of them produced, ordered success then failure then usage error.

Aggregating this way means a single bad file cannot be lost among many good ones,
and it is what lets a run continue past a failure without the failure being
forgotten.

#### Scenario: One failure among many succeeds is a failure

- **WHEN** nine files are formatted successfully and one is refused
- **THEN** the exit status is 1

#### Scenario: A usage error outranks a refusal

- **WHEN** one operand does not exist and another file is refused
- **THEN** the exit status is 2

#### Scenario: An empty selection succeeds

- **WHEN** a directory operand contains no file matching the discovery filter
- **THEN** nothing is written
- **AND** the exit status is 0

### Requirement: Diagnostics are written to standard error in a parseable format

The system SHALL write every diagnostic to standard error, and SHALL write
nothing but formatted text to standard output.

Each diagnostic concerning a position SHALL be written as `path:line:column:
message`, the form editors and line-oriented tools already parse. The position
SHALL come from the token the diagnostic is anchored to.

A refusal with no position — a failed output check — SHALL name the path and the
failing layer, and MUST NOT invent a position for it.

Where an unclean parse produces several diagnostics, they SHALL be reported in
source order.

#### Scenario: A parse diagnostic carries its position

- **WHEN** a file containing an unclosed delimiter is processed
- **THEN** a message of the form `path:line:column: message` is written to
  standard error

#### Scenario: A check failure names the layer and no position

- **WHEN** the pipeline reports a failed output check for a file
- **THEN** the path and the failing layer are written to standard error
- **AND** no line or column is reported

#### Scenario: Diagnostics never reach standard output

- **WHEN** a run produces both formatted text under `--stdout` and a diagnostic
  for another file
- **THEN** standard output holds only the formatted text

#### Scenario: Several diagnostics are in source order

- **WHEN** a file produces more than one parse diagnostic
- **THEN** they are written in increasing source position order

### Requirement: A tainted layout is not reported and does not affect the status

Where the pipeline reports that it could not prove a layout minimal, the system
SHALL treat the run as successful, SHALL write no warning, and SHALL NOT change
the exit status.

Taint is a withdrawn minimality claim, not a defect: the text is complete,
verified by the output checks, and written like any other. Its usual cause is a
token wider than the page, which the user cannot act on, and a warning nobody can
act on teaches people to ignore the ones that matter.

#### Scenario: A tainted file formats silently

- **WHEN** a file containing a token longer than the page width is formatted in
  place
- **THEN** the file is written with the formatted text
- **AND** nothing is written to standard error
- **AND** the exit status is 0
