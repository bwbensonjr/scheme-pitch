## MODIFIED Requirements

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
