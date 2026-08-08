## ADDED Requirements

### Requirement: In-place rewriting is the default for file operands

Where the program is given file or directory operands and neither `--stdout` nor
`--check`, it SHALL replace each file's contents with its formatted text.

Exactly one disposition SHALL be in effect. Giving both `--stdout` and `--check`
SHALL be a usage error, because they name incompatible outcomes and silently
preferring one would hide the mistake.

#### Scenario: A file operand is rewritten

- **WHEN** a file that is not already formatted is given as the only operand
- **THEN** the file's contents afterward are the formatted text
- **AND** nothing is written to standard output

#### Scenario: Two dispositions together are a usage error

- **WHEN** the program is invoked with both `--stdout` and `--check`
- **THEN** it exits with the usage-error status
- **AND** no file is read or written

### Requirement: A file is written only when its formatted text differs

The system SHALL compare the formatted text to the text it read, and SHALL NOT
write the file when they are equal.

Formatting is idempotent, so an already-formatted tree is the steady state, and a
run over one MUST be a no-op at the filesystem level: no file replaced, no
modification time changed. A formatter that rewrites every file on every run
produces rebuild storms and makes its own no-op case indistinguishable from its
working case.

#### Scenario: An already-formatted file is not written

- **WHEN** a file whose contents are already pitch's output is formatted in place
- **THEN** the file is not written at all

#### Scenario: A second run writes nothing

- **WHEN** a directory is formatted in place twice in succession
- **THEN** the second run writes no file

#### Scenario: A changed file is written exactly once

- **WHEN** a file that is not already formatted is formatted in place
- **THEN** the file is written once
- **AND** its contents afterward are the formatted text

### Requirement: A refused file is left untouched

Where the pipeline reports any status other than success — an unclean parse, an
unsupported line ending, or a failed output check — the system SHALL NOT write
that file, SHALL leave its contents byte-identical, and SHALL report the refusal.

No partial output SHALL be written under any status, and no repaired form of the
input SHALL be emitted. The pipeline returns no text at all when a check fails,
so there is nothing to write even by accident; this requirement states that the
program does not manufacture one.

#### Scenario: An unclean parse leaves the file alone

- **WHEN** a file containing an unclosed delimiter is formatted in place
- **THEN** the file is not written
- **AND** its contents afterward are byte-identical to its contents before

#### Scenario: An unsupported line ending leaves the file alone

- **WHEN** a file whose block comment contains a carriage return followed by a
  line feed is formatted in place
- **THEN** the file is not written
- **AND** its contents afterward are byte-identical to its contents before

#### Scenario: A failed check leaves the file alone

- **WHEN** the pipeline reports a failed output check for a file being formatted
  in place
- **THEN** the file is not written
- **AND** its contents afterward are byte-identical to its contents before

### Requirement: The write is atomic

The system SHALL write a file's new contents to a temporary path in the same
directory and then rename it over the target, so that an interrupted run leaves
the file either wholly unchanged or wholly replaced.

The temporary SHALL be created in the target's own directory, so the rename stays
within one filesystem and is atomic.

This is the only operation in the system that can destroy a user's source, and a
truncated source file is a worse outcome than any the safety checks exist to
prevent.

#### Scenario: The target is renamed into place

- **WHEN** a file is rewritten in place
- **THEN** the new contents are written to a temporary path in the same directory
- **AND** that path is renamed over the target

#### Scenario: A failed write leaves the original intact

- **WHEN** writing the temporary fails
- **THEN** the target file's contents are unchanged
- **AND** the failure is reported

### Requirement: `--stdout` writes formatted text and touches no file

Where `--stdout` is given, the system SHALL write each input's formatted text to
standard output and SHALL write no file.

Standard output SHALL carry formatted text and nothing else, so that redirecting
it produces a file containing only source. Every diagnostic goes to standard
error.

Where several operands are given with `--stdout`, their formatted texts are
written in operand order with no separator, header, or filename banner between
them: a banner would be text the formatter did not produce, in the stream
reserved for text it did.

Where `--stdout` is given with no operand, the input is standard input, per
`cli-file-selection`. That is the one case in which an option selects an input
rather than a disposition, and it is admitted because the disposition it names is
already the only one a stream can have.

#### Scenario: Standard output receives the formatted text

- **WHEN** a file is formatted with `--stdout`
- **THEN** its formatted text is written to standard output
- **AND** the file is not written

#### Scenario: A refusal writes nothing to standard output

- **WHEN** a file containing an unclosed delimiter is formatted with `--stdout`
- **THEN** nothing is written to standard output for that file
- **AND** the diagnostic is written to standard error

#### Scenario: Several files concatenate

- **WHEN** two files are formatted with `--stdout`
- **THEN** standard output holds the first file's formatted text followed by the
  second's, with nothing between them

### Requirement: `--check` writes nothing and reports what would change

Where `--check` is given, the system SHALL format each input, compare the result
to the input's current contents, write no file and no formatted text, and name
each file that would change on standard error.

A file the pipeline refuses SHALL be reported as a failure in check mode as well:
it is not formatted, so it is not in the state a successful check asserts.

`--check` requires an operand. It SHALL NOT read standard input in the absence of
one; `--check -` names the stream explicitly, and `--check` alone is a usage
error.

#### Scenario: A file that would change is named

- **WHEN** a file that is not already formatted is checked
- **THEN** its path is written to standard error
- **AND** the file is not written
- **AND** nothing is written to standard output

#### Scenario: A file that would not change is silent

- **WHEN** a file whose contents are already pitch's output is checked
- **THEN** nothing is written for that file
- **AND** the file is not written

#### Scenario: A refused file is a check failure

- **WHEN** a file containing an unclosed delimiter is checked
- **THEN** the refusal is reported on standard error
- **AND** the run does not report success

### Requirement: A multi-file run continues past a failure

The system SHALL process every selected input, whatever any earlier input did. A
refusal, an unreadable path, or a failed write SHALL NOT abandon the inputs that
follow.

An editor formatting a whole project and a hook formatting a changeset both need
the good files formatted and the bad ones named; stopping at the first failure
gives them neither.

#### Scenario: One refusal does not stop the run

- **WHEN** three files are formatted in place and the second contains an unclosed
  delimiter
- **THEN** the first and third are formatted
- **AND** the second is left byte-identical
- **AND** the refusal is reported

#### Scenario: Every failure is reported

- **WHEN** two of five files are refused
- **THEN** both refusals are reported on standard error
