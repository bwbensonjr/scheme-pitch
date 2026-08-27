# emit-application Specification

## Purpose

Defines Pitch as an Emit-compiled R7RS-small application whose development and standalone execution paths preserve the formatter's complete command-line, safety, filesystem, and installation contracts.

## Requirements

### Requirement: Emit is the supported application runtime

The maintained Pitch application SHALL consist of R7RS-small libraries accepted by Emit and an R7RS-small program entry accepted by both `emit run` and `emit build`.

The complete application SHALL NOT require Chez Scheme at compile time or runtime. Chez MAY remain a development-only oracle for tests whose value comes from an implementation independent of Emit, but the project SHALL NOT ship or install a Chez launcher for the complete application.

#### Scenario: The application compiles without Chez

- **WHEN** the Pitch application is built on a host with the required Emit toolchain and no Chez executable
- **THEN** the build produces a standalone Pitch executable

#### Scenario: Chez is not an application target

- **WHEN** the supported runtime and install targets are enumerated
- **THEN** they name the Emit development runner and Emit-built executable
- **AND** they do not name a Chez-based Pitch launcher

### Requirement: Development and standalone execution agree

The project SHALL provide a development command that runs the application through `emit run` and a build command that produces a standalone executable through `emit build` from the same program entry and library manifest.

For the same arguments, source files, configuration, and process environment, the two execution paths SHALL produce the same formatted text, diagnostics, filesystem effects, and exit status.

#### Scenario: Check mode has door parity

- **WHEN** the same unformatted file is passed with `--check` through the development runner and through the standalone executable
- **THEN** both leave the file unchanged, report it on standard error, write nothing to standard output, and exit with status 1

#### Scenario: A refusal has door parity

- **WHEN** the same malformed file is passed through both execution paths
- **THEN** both report the same refusal class, exit non-zero, and leave the file byte-identical

### Requirement: The Emit host preserves the complete CLI filesystem contract

The real host used by the Emit program SHALL support every operation enumerated by the CLI host interface: reading and writing text files, atomically replacing a target with a same-directory temporary, listing a directory, distinguishing directories from symbolic links, testing file existence, and exposing the three standard textual ports.

Running under Emit MUST NOT narrow the accepted operand kinds or weaken the requirements of `cli-file-selection` or `cli-output-disposition`. In particular, directory operands SHALL still be traversed deterministically without following linked directories, and an in-place write SHALL still be atomic.

The build SHALL fail with an actionable prerequisite diagnostic before compiling Pitch if the selected Emit installation does not provide the required host filesystem capability.

#### Scenario: Directory traversal is preserved

- **WHEN** an Emit-built Pitch receives a directory containing supported Scheme files and a symbolic link to another directory
- **THEN** it processes the supported files in deterministic order and does not descend through the symbolic link

#### Scenario: Replacement remains atomic

- **WHEN** an Emit-built Pitch changes a file in place
- **THEN** it writes a temporary in the target directory and atomically replaces the target

#### Scenario: A missing filesystem prerequisite is reported early

- **WHEN** the selected Emit installation lacks the required filesystem capability
- **THEN** the Pitch build stops before compiling application libraries
- **AND** the diagnostic names the missing capability and the required Emit version or prerequisite change

### Requirement: The application is manifest-defined and relocatably installed

The repository SHALL provide one Emit manifest naming every Pitch library and one program entry named `pitch`. Relative paths in that manifest SHALL make the project build independent of the caller's working directory.

Installation SHALL place the standalone executable, its shipped default configuration, and any required wrapper so the executable finds its configuration after the checkout is moved or removed. The installed application SHALL NOT resolve a library or resource through the source checkout.

#### Scenario: Named program build

- **WHEN** the user builds the manifest program named `pitch`
- **THEN** Emit compiles the transitive Pitch library closure and produces the configured standalone executable

#### Scenario: Installed application is independent of the checkout

- **WHEN** Pitch is installed, the source checkout is moved away, and the installed executable formats standard input
- **THEN** it loads the installed default configuration and succeeds without reading the old checkout

### Requirement: The derived reader retains one source of truth

`src/pitch/reader.sls` SHALL remain the only hand-edited Pitch reader derived from laesare. The Emit-compatible reader library SHALL be generated deterministically from it, SHALL identify itself as generated, and MUST NOT be maintained as an independent implementation.

The project SHALL provide a check that regenerates the Emit reader and fails on drift. The generated library SHALL have behavior parity with the authoritative reader for token kinds, exact token text, spans, parsed values, diagnostics, and dialect mode over their shared supported host values.

#### Scenario: Generated reader drift is detected

- **WHEN** the checked Emit reader artifact differs from a fresh generation from `src/pitch/reader.sls`
- **THEN** the generated-source check fails

#### Scenario: Vendored reader remains pristine

- **WHEN** all Emit reader artifacts are generated and tested
- **THEN** `make vendor-verify` still confirms that `vendor/laesare/` is unmodified
- **AND** `make vendor-diff` continues to compare the authoritative reader directly with pristine upstream

### Requirement: The verification matrix covers the shipped target and retained oracles

Running the repository's primary test target from the repository root SHALL exercise the Pitch-specific suite through Emit, exercise the complete CLI through both development and standalone doors where behavior can differ, run the pristine reader regression against the authoritative derived reader, and check generated-reader and vendor integrity.

Tests that use Chez or Racket SHALL identify those implementations as test oracles and MUST NOT make the complete application depend on either at runtime.

#### Scenario: Primary verification covers the Emit application

- **WHEN** the primary test target succeeds from the repository root
- **THEN** the Pitch libraries have compiled with Emit
- **AND** the Pitch-specific behavior and development/AOT parity tests have passed
- **AND** generated-reader and vendor-integrity checks have passed
