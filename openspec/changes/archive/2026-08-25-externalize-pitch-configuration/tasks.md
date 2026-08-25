## 1. External Style Data

- [x] 1.1 Add `src/pitch/default-config.scm` with schema version 1, width 88,
  dialect `common`, and the current common/R6RS/R7RS entries copied without
  semantic changes; verify a fixture test accounts for every current head and
  its style datum.
- [x] 1.2 Refactor `(pitch style)` to retain only the closed grammar,
  descriptors, and immutable table-construction/lookup operations, removing all
  default entries and process-global dialect tables; verify `tests/test-style.sps`
  passes and a structural test confirms the library imports no CST, reader,
  document, configuration, or I/O library.
- [x] 1.3 Extend the style table construction interface only as needed for
  precompiled shared bindings, overrides, and removals; verify unit tests prove
  inherited common descriptors are object-identical across dialect tables and
  dialect removal exposes the generic fallback.

## 2. Pure Configuration Model

- [x] 2.1 Add `(pitch config)` with parsed-overlay and opaque resolved-config
  representations and accessors needed by callers; verify invalid dialects,
  missing required default scalars, and non-positive widths cannot produce a
  resolved configuration.
- [x] 2.2 Parse exactly one `(pitch-config 1 ...)` datum through Pitch's lexer,
  parser, and `cst->datum`, with no host `read`, `load`, or `eval`; add
  `tests/test-config.sps` cases for comments, empty/multiple/unclean data,
  unsupported versions, unknown/duplicate fields, invalid scalars, unknown
  dialects, duplicate/non-symbol heads, and executable-looking data, and verify
  the test program passes under Chez.
- [x] 2.3 Validate every configured style eagerly and preserve its source path
  in configuration diagnostics; verify malformed terminals and malformed entry
  shapes identify the configuration file before any formatting operation is
  called.
- [x] 2.4 Implement default-plus-user overlay composition and final CLI scalar
  overrides, including `remove`, common inheritance, dialect masks, and
  textual-order independence; verify focused tests cover add, replace, common
  remove, dialect remove, CLI precedence, and one resolved configuration reused
  across dialect selections.
- [x] 2.5 Add `tests/test-config.sps` to `make test`; verify the target invokes it
  from the repository root and all existing test programs still load without
  compiled style defaults.

## 3. Formatting Pipeline Integration

- [x] 3.1 Change `cst->document` and recursive translation helpers to accept an
  immutable style table directly rather than a dialect, removing `(pitch print)`'s
  dependency on global dialect tables; verify print tests exercise common,
  R6RS, R7RS, added, replaced, and removed styles.
- [x] 3.2 Change `format-source` to require a resolved configuration, select its
  table at the format edge, and pass only width to layout and the table to
  translation; verify format tests show configuration changes whitespace but
  never source acceptance, parsing, checks, or token spelling.
- [x] 3.3 Update every repository library caller and fixture for the breaking
  format API; verify no compiled `default-page-width`, `default-dialect`,
  `core-style-table`, `r6rs-style-table`, or `r7rs-style-table` definition or
  reference remains outside test fixture names and the external data file.
- [x] 3.4 Add regression coverage that formats the full existing corpus through
  the shipped external defaults and byte-compares it with the pre-change golden
  output; verify default behavior, idempotence, token equivalence, datum
  equivalence, and refusal behavior are unchanged.

## 4. CLI Loading and Failure Semantics

- [x] 4.1 Extend pure argument parsing and help text with singular
  `--config PATH`, while recording width/dialect as optional explicit overrides;
  verify CLI tests cover interleaving, missing values, repeated `--config`, CLI
  precedence independent of argument order, and all existing dispositions.
- [x] 4.2 Make `run-cli` receive the shipped-default path, read the shipped and
  optional user text through the host exactly once, resolve them before operand
  expansion or standard-input reads, and reuse the result for every source;
  verify the in-memory host read log proves this ordering for files,
  directories, and standard input.
- [x] 4.3 Map missing, unreadable, or invalid configuration to an actionable
  path-qualified diagnostic and usage status 2; verify tests assert zero source
  reads, zero writes, and unchanged source bytes for every configuration failure.
- [x] 4.4 Preserve early argument outcomes ahead of configuration loading;
  verify help, version, unknown options, missing values, incompatible
  dispositions, repeated `--config`, and no-input invocations perform no
  configuration read.
- [x] 4.5 Verify the CLI performs no implicit working-directory, operand,
  ancestor, home, or environment configuration discovery by placing decoy files
  in the in-memory host and observing no reads or output changes.

## 5. Entrypoint and Installation

- [x] 5.1 Make `main.sps` derive `default-config.scm` beside its own program path
  and pass the result into the CLI; verify focused tests or an extracted pure
  helper cover absolute and relative program paths.
- [x] 5.2 Update checkout wrapper, `make format`, and `make format-check` flows as
  needed to use the external defaults; verify all three operate from the
  repository root without a compiled fallback.
- [x] 5.3 Update `make install` and `make uninstall` to install/remove the default
  data beside `main.sps`; install to a temporary `PREFIX`, run the installed
  `pitch --check` on a fixture, remove the checkout from its library path, and
  verify the installed command still finds its defaults.
- [x] 5.4 Simulate a missing installed default and verify an operational command
  reports its exact path with status 2 while `--help` and `--version` still
  succeed without reading it.

## 6. Design Precepts and User Documentation

- [x] 6.1 Revise `README.md` usage and principles to document `--config`, schema
  version 1, precedence, add/replace/remove examples, external shipped defaults,
  explicit-only discovery, and the bounded non-configurable safety surface;
  verify no statement still claims width and dialect are the whole surface or
  that Pitch never grows configuration.
- [x] 6.2 Reconcile `docs/DESIGN.md` dialect, style-table, numeric-knob, CLI, and
  open-question sections with the implemented loader, while retaining the
  exclusions for the SRFI registry, magic comments, indent knobs, and host
  readers; verify searches for “configuration surface” and related settled
  decisions find no contradiction.
- [x] 6.3 Replace the `AGENTS.md` anti-configuration prohibition with an invariant
  allowing only inert width, dialect, and declarative style data, requiring
  validation before source I/O, and keeping safety, normalization, token
  spelling, ordering, and comment contents non-configurable; verify all other
  invariants and vendored-code instructions remain unchanged.

## 7. Final Verification

- [x] 7.1 Run `make test` from the repository root and verify the reader
  regression suite plus configuration, style, print, format, safety, and CLI
  suites all pass.
- [x] 7.2 Run `make format-check` with the shipped defaults and with an explicit
  project configuration fixture; verify the default is clean and the fixture's
  width, dialect, and macro style are each observable.
- [x] 7.3 Run `make vendor-diff` and inspect that the derived-reader changeset is
  unchanged, then run `make vendor-verify` and verify `vendor/laesare/` remains
  pristine.
- [x] 7.4 Run strict OpenSpec validation for
  `externalize-pitch-configuration` and verify every configured behavior and
  documentation change is covered by a completed task and test.
