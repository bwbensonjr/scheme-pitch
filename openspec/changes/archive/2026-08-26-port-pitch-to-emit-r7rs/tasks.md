## 1. Establish the Port Baseline and Prerequisites

- [x] 1.1 Record the exact Emit revision that passes Emit's `pitch-prerequisites` fixture and compile a small imported-library probe; verify modules, records, textual ports, bytevectors, cycle-safe `equal?`, `case-lambda`, Unicode character operations, continuable exceptions, process context, and writers through `emit run` and `emit build`
- [x] 1.2 Confirm the separately specified `(emit filesystem)` library exports `directory-list`, `file-directory?`, `file-symbolic-link?`, and atomic `replace-file` with the semantics in design D5; verify a standalone probe lists a directory, distinguishes a linked directory, and replaces a same-directory target, and stop the port if this external prerequisite is absent
- [x] 1.3 Add an Emit prerequisite preflight to the build that runs before any Pitch compilation; verify an older/missing Emit reports the required capability and revision while the selected supported Emit passes silently
- [x] 1.4 Capture the current Chez application results for the full test suite, CLI exit/output/effect fixtures, self-format check, `make vendor-diff`, and `make vendor-verify`; verify these baseline artifacts can be used to detect behavioral drift during the port

## 2. Add Narrow R7RS Portability Modules

- [x] 2.1 Add a Pitch sequence utility for `for-all`, `exists`, filtering, folds needed outside `(scheme base)`, and deterministic stable sorting; verify focused tests cover empty, singleton, duplicate-key stability, and path-order cases
- [x] 2.2 Add Pitch table interfaces for symbol/integer equality and document identity, using `eq?` lookup for layout memo keys; verify distinct but structurally equal document records occupy distinct entries and cyclic keys terminate
- [x] 2.3 Add Pitch error records and one message adapter for Pitch errors and R7RS error objects; verify `guard` can distinguish config, reader, and layout failures and CLI reporting retains their messages
- [x] 2.4 Replace the layout dynamic-failure bit mask with an explicit fullness-index set behind the same logical operations; verify every existing static/dynamic failure and tainted-layout case returns the Chez-baseline result without bitwise procedures
- [x] 2.5 Audit the ported source for remaining R6RS condition, hash-table, sorting/list-helper, bitwise, fixnum, and transcoder identifiers; verify the audit permits only the authoritative `reader.sls` source and the closed mappings owned by the reader generator

## 3. Preserve and Adapt the Derived Reader

- [x] 3.1 Define the closed mapping from the R6RS reader's wrapper, imports, records, conditions, fixnum operations, hash tables, mutable pairs, and port names to the R7RS portability interfaces; verify every current R6RS-only form in `reader.sls` is either mapped explicitly or rejected by the mapping audit
- [x] 3.2 Implement the deterministic syntax-aware reader generator without editing `vendor/laesare/`; verify it emits a generated-header `reader.sld`, rejects an injected unknown import/form, and produces byte-identical output on two runs
- [x] 3.3 Add generated-reader regeneration and drift-check targets; verify changing the checked artifact without changing `reader.sls` makes the check fail and regeneration restores it
- [x] 3.4 Add a complete R6RS/R7RS numeric syntax recognizer to authoritative `src/pitch/reader.sls`, update its header change list, and keep value construction separate; verify valid integer, rational, decimal, exponent, exactness/radix, rectangular/polar complex, infinity, and NaN forms classify correctly while invalid near-misses report syntax errors
- [x] 3.5 Add the private opaque numeric marker/value path for valid host-unrepresentable lexemes; verify representable numbers remain host numbers, large/rational/complex lexemes remain numeric without diagnostics on Emit, and opaque values cannot satisfy number or octet checks
- [x] 3.6 Update CST projection and `datum=?` for opaque numeric values without reparsing text; verify two fresh reads of the same opaque number compare equal, opaque values differ from all source-constructible ordinary data, cyclic equality terminates, `#xff` remains equivalent to `255`, and layer 1 rejects alternate opaque spellings
- [x] 3.7 Add authoritative/generated reader parity fixtures over token kinds, exact text, offsets, line/column spans, representable values, diagnostics, directives, and dialect modes; verify parity under Chez and Emit and retain `tests/test-reader.sps` unchanged beyond its existing library rename
- [x] 3.8 Run `make vendor-diff` and `make vendor-verify` after the reader work; verify the derived-reader diff remains legible, contains the updated change-list entry, and the pristine vendor tree is unchanged

## 4. Port the Library Graph to R7RS-small

- [x] 4.1 Port the leaf utility libraries (`lines`, `cost`, `style`, and `diagnostic`) to `define-library` units with explicit R7RS records/imports; verify their focused tests match the captured Chez results
- [x] 4.2 Port the document algebra library to R7RS records, case-lambda, and Pitch tables; verify every document constructor, flattening rule, failure predicate, and fold test matches the baseline
- [x] 4.3 Port the CST and parser libraries to R7RS ports, records, and sequence utilities; verify byte-for-byte CST round trips, malformed-input diagnostics, bracket distinctions, trivia retention, and source positions remain unchanged
- [x] 4.4 Port the datum and check libraries, including label tables and fresh-text layer 1/layer 2 checks; verify all projection, cyclic graph, bytevector, token-equivalence, and mutation-witness tests pass under Emit
- [x] 4.5 Port the layout library using the Pitch identity tables and fullness-index sets; verify written layout expectations and the full document corpus match Chez for text, cost, taint, and failure outcomes, and record a representative corpus timing comparison
- [x] 4.6 Port the print, configuration, and format pipeline libraries; verify style lookup remains data-driven, malformed configuration is refused before source I/O, formatter output matches the baseline, and every safety check still re-reads emitted text
- [x] 4.7 Port the CLI driver to R7RS errors, ports, sorting, and folds without importing Emit-specific libraries; verify the in-memory host suite preserves argument validation, traversal selection, reporting, write logs, refusal behavior, and exit statuses
- [x] 4.8 Audit every maintained `.sld` library for dialect branching, host reader calls, undeclared normalization, executable configuration, and direct operating-system access below the real-host edge; verify the invariant audit finds none

## 5. Port the Test Harness to the Shipped Target

- [x] 5.1 Add an R7RS/Emit test runner and convert Pitch-specific test programs without changing their assertions or fixtures; verify each library test compiles as an Emit program from the repository root
- [x] 5.2 Preserve host-reader and layout comparisons as explicit external oracle targets whose inputs come from real serialized output; verify no oracle is used by the runtime application and no check compares an in-memory tree with itself
- [x] 5.3 Add UTF-8, CRLF, Unicode, and interior-line-ending tests through real Emit textual file ports; verify byte-level input/output behavior preserves accepted text and refuses unsupported multi-line token endings without writing
- [x] 5.4 Add a no-Chez-on-`PATH` build and standard-input smoke test; verify the complete application compiles and formats with Emit alone while development-only oracle tests are clearly separated

## 6. Build and Run the Complete Emit Application

- [x] 6.1 Add `emit-libs.scm` entries for every Pitch library with paths relative to the manifest; verify Emit resolves and compiles the transitive library closure from a working directory outside the checkout
- [x] 6.2 Add the R7RS program entry and real host adapter importing only standard R7RS libraries, `(pitch cli)`, and `(emit filesystem)`; verify all ten host operations map correctly and no CLI policy moves into the adapter
- [x] 6.3 Add real filesystem integration tests for deterministic directory walking, supported-extension selection, symlink non-traversal, unchanged files, refused files, failed temporary writes, and atomic replacement; verify effects and exit statuses satisfy the existing CLI specs
- [x] 6.4 Add the manifest `(program pitch ...)` entry and development/build targets using the same source and manifest; verify `emit run` receives arguments after `--` and `emit build pitch` produces the configured standalone executable
- [x] 6.5 Add development/AOT parity tests for help, version, stdin, stdout, check, in-place formatting, configuration errors, malformed source, multi-file continuation, and directory operands; verify stdout, diagnostic class/text, filesystem effects, and exit status agree
- [x] 6.6 Add self-format and self-check targets using the Emit application; verify formatting the maintained Pitch R7RS sources is idempotent and the second run writes nothing

## 7. Package the Standalone Program and Retire the Chez Application

- [x] 7.1 Copy the shipped default configuration beside build output and add a relocatable libexec-plus-launcher install layout; verify an installed Pitch still formats after the source checkout and build directory are moved away
- [x] 7.2 Update uninstall to remove only the installed Pitch launcher/libexec/configuration paths; verify an install-uninstall round trip leaves unrelated prefix files untouched
- [x] 7.3 Remove the complete Chez launcher, wrapper generation, application build/install targets, and R6RS application libraries only after Emit parity is green; verify no shipped executable or manifest resolves Chez and the retained reader/oracle commands still run
- [x] 7.4 Update README, `docs/DESIGN.md`, build help, and source headers to state the Emit/R7RS target, the Chez-oracle boundary, opaque numeric behavior, external filesystem prerequisite, and migration from R6RS library use; verify all documented commands work as written

## 8. Final Verification

- [x] 8.1 Run the primary test target from the repository root; verify all Pitch-specific Emit tests, reader baseline/parity, generated-source checks, real-host tests, and development/AOT parity checks pass
- [x] 8.2 Run `make vendor-diff` and `make vendor-verify`; verify the former remains the reviewable authoritative reader changeset and the latter reports every vendored file pristine
- [x] 8.3 Run the Racket layout oracle where available and the full self-format/idempotence corpus; verify output text, cost, taint, token equivalence, datum equivalence, and second-run stability all pass
- [x] 8.4 Run a clean no-Chez standalone build, relocatable install smoke test, and uninstall test; verify the delivered command uses no checkout path and preserves shell-visible exit statuses 0, 1, and 2
- [x] 8.5 Run `openspec validate port-pitch-to-emit-r7rs --strict` and review the final diff against every proposal capability and codebase invariant; verify no R6RS compatibility layer, vendor edit, weakened safety check, new normalization, or narrowed CLI behavior entered the change
