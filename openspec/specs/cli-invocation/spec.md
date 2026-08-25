# cli-invocation Specification

## Purpose

The program's surface: what it accepts, when it validates, and what it refuses to
grow into. The option set admits one explicitly named inert configuration plus
width and dialect overrides, but remains closed against implicit discovery and
knobs that weaken formatter invariants. Argument-list errors are resolved before
configuration or source reads. An invocation naming no input is a usage error,
not a read of standard input: the exit status is the only channel a script reads,
and a formatter that exits 0 over an empty file list reports a clean run over
nothing. `--help` and the bare invocation print the same text to opposite streams
under opposite statuses, and that contrast is the reason both exist. The command
line is a driver over a host, taking an argument list and returning a status
rather than terminating the process, so that the behaviors that matter -- a
refused file is not written, an unchanged file is not written -- are asserted
against memory instead of a real filesystem.
## Requirements

### Requirement: The command line accepts a closed set of options

The system SHALL provide a command-line program accepting exactly these options
and no others:

| Option | Meaning |
|---|---|
| `--stdout` | write formatted text to standard output instead of rewriting files |
| `--check` | write nothing; report whether any input would change |
| `--config PATH` | overlay the shipped defaults with the named configuration file |
| `--width N` | page width, a positive exact integer overriding configuration |
| `--dialect D` | one of `common`, `r6rs`, `r7rs`, overriding configuration |
| `--help` | write usage to standard output |
| `--version` | write the version to standard output |

The option set SHALL be closed. Configuration SHALL be bounded by the
`configuration-loading` schema; no option SHALL be added that weakens a safety
check, permits a normalization, reorders code, changes comment contents, or
executes configuration as code.

At most one `--config` SHALL be accepted. An unrecognized option, a repeated
`--config`, or an option requiring a value that is given none SHALL be a usage
error.

#### Scenario: The defaults apply when no option is given

- **WHEN** the program is invoked with a single file operand and no options
- **THEN** the shipped default configuration is loaded
- **AND** the file is formatted at width 88 under the shared core dialect
- **AND** the file is rewritten in place

#### Scenario: A configuration file supplies invocation settings

- **WHEN** the program is invoked with `--config project/pitch.scm` and a file
  operand
- **THEN** that file overlays the shipped configuration for the invocation

#### Scenario: A repeated configuration option is a usage error

- **WHEN** the program is invoked with two `--config` options
- **THEN** it exits with the usage-error status
- **AND** no configuration or source file is read

#### Scenario: An unknown option is a usage error

- **WHEN** the program is invoked with `--verbose`
- **THEN** it reports the unknown option on standard error
- **AND** it exits with the usage-error status
- **AND** no configuration or source file is read or written

#### Scenario: An option missing its value is a usage error

- **WHEN** the program is invoked with `--width` as the final argument
- **THEN** it reports the missing value on standard error
- **AND** it exits with the usage-error status

### Requirement: Option values are validated before any file is opened

The system SHALL parse and validate every option value before reading or writing
any file. Where a value is invalid, it SHALL report the error, exit with the
usage-error status, and leave every input untouched.

The dialect name SHALL be validated against the accepted set by the program
itself. The style-table lookup raises on an unknown dialect, and that condition
MUST NOT be allowed to escape from inside the per-file loop, where it would
abandon a partially processed run without a usable message.

The width SHALL be rejected unless it is a positive exact integer.

#### Scenario: An unknown dialect is rejected before any work is done

- **WHEN** the program is invoked with `--dialect r5rs` and three file operands
- **THEN** it reports the invalid dialect on standard error
- **AND** it exits with the usage-error status
- **AND** none of the three files is read or written

#### Scenario: A non-numeric width is rejected

- **WHEN** the program is invoked with `--width wide`
- **THEN** it reports the invalid width on standard error
- **AND** it exits with the usage-error status

#### Scenario: A non-positive width is rejected

- **WHEN** the program is invoked with `--width 0`
- **THEN** it exits with the usage-error status

#### Scenario: An accepted dialect reaches the formatter

- **WHEN** the program is invoked with `--dialect r6rs` and a file operand
- **THEN** the file is formatted under the R6RS style table

### Requirement: Operands are distinguished from options

The system SHALL treat an argument beginning with `-` as an option, with two
exceptions: the argument `-` alone names standard input, and every argument
following a bare `--` is an operand regardless of its spelling.

Options and operands MAY be interleaved.

#### Scenario: A file whose name begins with a dash is reachable

- **WHEN** the program is invoked with `--` followed by `-weird.sls`
- **THEN** `-weird.sls` is treated as a file operand

#### Scenario: Options may follow operands

- **WHEN** the program is invoked with a file operand followed by `--width 40`
- **THEN** the file is formatted at width 40

#### Scenario: A bare dash is an operand, not an option

- **WHEN** the program is invoked with `-`
- **THEN** it names standard input rather than being reported as an unknown
  option

### Requirement: An invocation naming no input is a usage error

Where the program is given no arguments at all, it SHALL write the usage summary
to standard error, exit with the usage-error status, and read and write nothing.

It MUST NOT read standard input. The absence of an operand SHALL NOT be treated
as naming a stream: standard input is selected only by `-` or by `--stdout` with
no operand, per `cli-file-selection`.

Nor SHALL such an invocation report success. Under an in-place default, an
invocation carrying no operand is overwhelmingly a script whose file list came
out empty, and a formatter that exits 0 there reports a clean run over nothing.
The exit status is the only channel a script reads, so it is the one that must
carry the fact that no input was named.

The same rule applies to any invocation that sets options but names no input,
such as `--width 40` alone.

#### Scenario: A bare invocation prints usage and fails

- **WHEN** the program is invoked with no arguments at all
- **THEN** the usage summary is written to standard error
- **AND** it exits with the usage-error status
- **AND** standard input is not read

#### Scenario: Options without an operand are still a usage error

- **WHEN** the program is invoked with `--width 40` and no operand
- **THEN** it exits with the usage-error status
- **AND** standard input is not read

#### Scenario: A bare invocation writes nothing to standard output

- **WHEN** the program is invoked with no arguments at all
- **THEN** nothing is written to standard output

### Requirement: Help and version succeed

The system SHALL write a usage summary to standard output for `--help` and a
version string to standard output for `--version`, and SHALL exit with the
success status in both cases. It SHALL do so without reading or writing any file,
even when operands are also given.

These outputs go to standard output rather than standard error because the user
asked for them; they are the program's result, not a complaint about it.

This contrast is the reason both `--help` and the bare-invocation usage exist and
why they must not be collapsed into one behavior: the same text answers an
explicit request on standard output with status 0, and an accidental invocation
on standard error with status 2. A user who typed `pitch` to find out what it
does is still told; a script that lost its path argument still fails.

#### Scenario: Help exits successfully

- **WHEN** the program is invoked with `--help`
- **THEN** a usage summary naming every option is written to standard output
- **AND** it exits with the success status

#### Scenario: Version exits successfully

- **WHEN** the program is invoked with `--version`
- **THEN** a version string is written to standard output
- **AND** it exits with the success status

#### Scenario: Help wins over operands

- **WHEN** the program is invoked with `--help` and a file operand
- **THEN** the usage summary is written
- **AND** the file is not read or written

### Requirement: The driver is separable from the host and returns a status

The system SHALL implement the command line as a driver taking an argument list
and a host, and returning an exit status rather than terminating the process.

The host SHALL be the enumeration of the operations the driver needs from the
outside world — reading a file, writing a file, renaming a file, listing a
directory, testing whether a path is a directory, testing whether a path is a
symbolic link, testing whether a path exists, and the standard input, standard
output and standard error ports — and the driver MUST perform no input or output
except through it.

Testing for a directory and testing for a symbolic link SHALL be separate
operations, so that the rule about not descending into a linked directory is
decided by the driver rather than by whichever host answers the question.

This exists so that the behaviors that matter most, in particular that a refused
file is not written and an unchanged file is not written, can be asserted against
an in-memory host rather than by inspecting a real filesystem.

The implementation-specific program SHALL contain only the construction of the
real host and the call into the driver, and no policy.

#### Scenario: The driver runs against an in-memory host

- **WHEN** the driver is given an argument list and a host backed by in-memory
  contents
- **THEN** it formats and reports entirely against that host
- **AND** it returns an exit status without terminating the process

#### Scenario: Every write is observable

- **WHEN** the driver processes any invocation against an in-memory host
- **THEN** every file the driver wrote is recorded by that host
- **AND** no file outside that record was modified
