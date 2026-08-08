## ADDED Requirements

### Requirement: Standard input is selected explicitly

The system SHALL read standard input when, and only when, it is named: by the
operand `-`, or by `--stdout` given with no operand at all. It SHALL read the
whole of standard input as one source text and write the formatted text to
standard output, since in-place rewriting is meaningless for a stream.

The absence of an operand SHALL NOT imply standard input. An invocation naming
no input is a usage error, not a read of a stream, and is specified under
`cli-invocation`.

Diagnostics concerning that input SHALL name it `<stdin>`.

`--check` SHALL be honored on standard input when it is named, writing nothing
and reporting whether the input is already formatted. `--check` with no operand
SHALL be a usage error, because once absence stops implying a stream it stops
implying one under every disposition.

#### Scenario: A bare dash reads standard input

- **WHEN** the program is invoked with the single operand `-`
- **THEN** standard input is formatted and the result written to standard output
- **AND** no file is written

#### Scenario: `--stdout` with no operand reads standard input

- **WHEN** the program is invoked with `--stdout` and no operand
- **THEN** standard input is formatted and the result written to standard output

#### Scenario: A refused standard input writes no text

- **WHEN** standard input is named and holds a source with an unclosed delimiter
- **THEN** nothing is written to standard output
- **AND** the diagnostic names `<stdin>` with a line and column

#### Scenario: Check mode works on named standard input

- **WHEN** the program is invoked with `--check -` and standard input holds a
  source that is not already formatted
- **THEN** nothing is written to standard output
- **AND** the exit status reports that the input would change

#### Scenario: Check mode with no operand is a usage error

- **WHEN** the program is invoked with `--check` and no operand
- **THEN** it exits with the usage-error status
- **AND** standard input is not read

### Requirement: Standard input cannot be mixed with other operands

Where the operand `-` appears, it SHALL be the only operand. An invocation
combining `-` with a file or directory operand SHALL be a usage error and SHALL
read and write nothing.

Mixing them would put two dispositions in one run, decided per operand and
announced by no flag: the named file rewritten in place while the stream goes to
standard output. Rejecting the combination costs a user nothing they cannot say
in two commands.

#### Scenario: A dash mixed with a file is rejected

- **WHEN** the program is invoked with the operands `-` and `a.sls`
- **THEN** it exits with the usage-error status
- **AND** `a.sls` is neither read nor written
- **AND** standard input is not read

#### Scenario: A dash mixed with a file is rejected under `--stdout` too

- **WHEN** the program is invoked with `--stdout` and the operands `-` and
  `a.sls`
- **THEN** it exits with the usage-error status

### Requirement: A named file is formatted regardless of its extension

Where an operand names an existing file, the system SHALL format that file
whatever its name. A user naming a file explicitly is a stronger signal than its
suffix.

#### Scenario: An unusual extension is honored when named

- **WHEN** an operand names an existing file called `notes.txt` containing
  Scheme source
- **THEN** the file is formatted

#### Scenario: A file with no extension is honored when named

- **WHEN** an operand names an existing file with no extension
- **THEN** the file is formatted

### Requirement: A directory operand is walked for Scheme source files

Where an operand names a directory, the system SHALL walk it recursively and
format the files it discovers.

Discovery SHALL select entries whose names end in `.sls`, `.sps`, `.scm`, `.ss`,
or `.sld`. The extension set is a discovery filter and nothing else: it SHALL NOT
be used to choose a dialect, because these extensions are used by both standards
and are not a reliable signal.

Entries whose names begin with `.` SHALL be skipped, which keeps a walk out of
version-control and editor directories without naming any of them.

Traversal SHALL be depth-first with the entries of each directory visited in
name order, so that the sequence of files processed, and therefore the order of
any diagnostics, is reproducible across machines and across runs.

#### Scenario: A directory yields its Scheme files

- **WHEN** an operand names a directory containing `a.sls`, `b.sps`, and
  `readme.md`
- **THEN** `a.sls` and `b.sps` are formatted
- **AND** `readme.md` is not read

#### Scenario: The walk descends

- **WHEN** an operand names a directory whose subdirectory contains a `.scm` file
- **THEN** that file is formatted

#### Scenario: Dot directories are skipped

- **WHEN** an operand names a directory containing a `.git` subdirectory holding
  a file ending in `.scm`
- **THEN** that file is not read

#### Scenario: The order is deterministic

- **WHEN** the same directory is walked twice
- **THEN** the files are processed in the same order both times
- **AND** that order is the name order of each directory's entries

### Requirement: Directory symbolic links are not followed

The system SHALL follow a symbolic link that names a file and SHALL NOT descend
into a symbolic link that names a directory during a walk.

Descending into linked directories admits cycles, and detecting a cycle requires
path identity the host does not expose. Skipping is the refusal-rather-than-guess
behavior the project applies elsewhere. A user who wants a linked tree formatted
can name it as an operand, which is followed.

#### Scenario: A linked directory is not descended into

- **WHEN** a walked directory contains a symbolic link to another directory
- **THEN** the files under that link are not formatted by the walk

#### Scenario: A linked directory named as an operand is walked

- **WHEN** an operand names a symbolic link to a directory
- **THEN** that directory is walked

### Requirement: Every operand is processed and a missing path is a usage error

The system SHALL process operands in the order given. Where an operand names
neither an existing file nor an existing directory, it SHALL report the path on
standard error and treat it as a usage error, while still processing the
remaining operands.

A path that exists but cannot be read is reported the same way. Neither is a
formatting failure: it is a fact about the invocation or the environment, not
about the code's formatting.

#### Scenario: A nonexistent operand is reported

- **WHEN** an operand names a path that does not exist
- **THEN** the path is reported on standard error
- **AND** the run ends with the usage-error status

#### Scenario: The remaining operands are still processed

- **WHEN** the operands are a nonexistent path followed by a well-formed file
- **THEN** the well-formed file is formatted
- **AND** the run still ends with the usage-error status

#### Scenario: An unreadable file is reported

- **WHEN** an operand names a file that exists but cannot be read
- **THEN** the path is reported on standard error
- **AND** the run ends with the usage-error status
