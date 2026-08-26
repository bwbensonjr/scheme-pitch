## Context

See [proposal.md](proposal.md) for motivation. Pitch currently consists of seventeen R6RS libraries plus a small Chez-specific program. The formatter core is isolated from operating-system effects by `(pitch cli)`'s host record, but its source uses R6RS library declarations, record and condition syntax, hash tables, sorting/list helpers, bitwise and fixnum procedures, and R6RS port names. `src/pitch/main.sps` additionally uses Chez directory, symlink, and rename operations.

Emit now supplies the R7RS-small intersection audited in its archived `support-pitch-r7rs-prerequisites` change: modules, records, textual ports, bytevectors, multiple values, cycle-safe `equal?`, `case-lambda`, Unicode character operations, continuable exceptions, process context, and writers. It intentionally does not supply R6RS compatibility, arbitrary-precision exact numbers, or the non-standard filesystem operations Pitch's real host needs. Emit libraries are manifest-resolved `.sld` units and a manifest program entry is the supported standalone build boundary.

Two project constraints shape the port. First, the output checks and formatter behavior may not weaken merely to fit a smaller runtime. Second, `vendor/laesare/` is pristine and `src/pitch/reader.sls` must remain the one reviewable derived reader and candidate upstream patch.

## Goals / Non-Goals

**Goals:**

- Compile the complete library closure and run the unchanged Pitch CLI contract through both `emit run` and an Emit-built standalone executable.
- Keep the formatter, CST, layout engine, and CLI driver free of compiler-specific branches; isolate Emit integration at library/build and real-host edges.
- Preserve every losslessness and output-verification invariant, including fresh reads of formatter output.
- Keep one hand-edited derived reader and retain the pristine upstream regression as independent evidence.
- Make valid R6RS/R7RS numeric token acceptance independent of the selected host's numeric tower.

**Non-Goals:**

- Add R6RS compatibility libraries or syntax to Emit.
- Continue supporting the complete Pitch application as a Chez program or preserve R6RS library-consumer compatibility.
- Modify Emit or `vendor/laesare/` in this repository; the filesystem extension is a separately versioned prerequisite.
- Broaden Emit's numeric tower or implement arbitrary-precision arithmetic in Pitch.
- Change formatting, configuration, normalization, dialect acceptance, CLI options, file-selection rules, or write safety.

## Decisions

### D1. Maintain one R7RS-small application, not dual R6RS/R7RS sources

Every maintained Pitch library except the authoritative derived-reader source becomes an R7RS `define-library` unit. The program becomes an R7RS top-level program importing `(scheme process-context)`, the required standard libraries, the Pitch CLI, and the narrow Emit filesystem extension. The complete Chez launcher and install path are removed.

Chez stays in the developer matrix only where independence is the point: laesare's pristine regression runs against `reader.sls`, and differential host-reader/oracle checks may invoke Chez out of process. This is test compatibility, not application compatibility.

Alternative considered: retain parallel `.sls` and `.sld` implementations. Library declarations, imports, record declarations, conditions, and host entry points would be duplicated across nearly every module. The copies would have no automatic behavioral correspondence and would turn every future change into a two-runtime migration. A broad R6RS compatibility layer in Emit is worse: the earlier prerequisite audit deliberately separated standard R7RS gaps from Pitch-local adaptations, and Pitch does not justify a second language surface in the compiler.

### D2. Port operations behind small Pitch-owned interfaces

R6RS-only facilities are replaced according to the semantic operation Pitch needs:

- Records use explicit R7RS constructors, predicates, accessors, and mutators. R6RS sealing, opacity, nongenerative UIDs, and constructor protocols are not reproduced because no supported runtime dynamically links old record definitions; constructor initialization becomes ordinary helper code.
- Raised values are Pitch record types carrying the fields callers inspect. `guard` dispatches on their predicates, and a small message adapter handles both Pitch errors and R7RS error objects. Composite R6RS conditions are not emulated.
- Symbol/integer maps use Emit's available hash-table surface where equality semantics match. Identity-keyed layout memoization uses a Pitch-owned `eq?` associative table so structural `equal?` cannot merge distinct documents. The interface, not callers, owns the eventual performance substitution.
- `for-all`, `exists`, filtering, and stable sorting live in one small sequence utility rather than being copied among modules. Sorting remains deterministic and stable.
- The layout engine replaces its per-document bit mask with an explicit set of fullness indexes. This removes bitwise/fixnum dependencies without changing what dynamic failure records.
- Positive integer division uses R7RS `quotient`; fixed-width arithmetic names become ordinary integer operations only where Emit's checked fixnum range is already sufficient for source sizes and layout columns.
- R7RS textual port names replace R6RS port/transcoder construction. UTF-8 and no-newline-normalization behavior are verified at the host boundary rather than configured through R6RS transcoder objects.

These are implementation modules, not a generic R6RS facade. Each exposes only operations already demanded by a Pitch caller.

Alternative considered: create `(pitch r6rs)` exporting renamed copies of the R6RS surface. That would preserve accidental API shape, obscure which equality or failure semantics a caller needs, and make it easy for new R6RS dependencies to enter unnoticed.

### D3. Generate the Emit reader from the authoritative derived reader

`src/pitch/reader.sls` remains the only hand-edited laesare-derived source. A deterministic, syntax-aware build tool produces an Emit-compatible `reader.sld` by replacing the outer library declaration/import set and translating a closed, audited set of portability forms whose semantics are fixed by D2. The generated file carries a prominent generated header and is never edited directly.

The generator fails on an R6RS import or portability form outside its closed mapping; it does not silently copy an unknown dependency into the Emit library. A generated-source check recreates the output and compares it byte for byte. The source header's change list is updated for every substantive reader edit, including the numeric lexer work in D4.

Two suites prevent the adapter from becoming an unreviewed fork:

1. laesare's baseline `tests/test-reader.sps` continues to run under Chez against `reader.sls`, ported no further than its existing library rename;
2. Emit runs the recording and parser corpus against generated `reader.sld`, with a parity fixture comparing serialized token kinds, texts, spans, representable values, and diagnostics from the two forms.

Alternative considered: hand-port `reader.sls` into a second `.sld`. That directly violates the one-source reader rule and makes `make vendor-diff` cease to describe the code the shipped application runs. Moving the shared body into an include file also destroys the legible upstream diff by relocating nearly the entire file.

### D4. Separate numeric syntax acceptance from host number construction

The reader gains a number lexer that validates the full numeric syntax accepted by its permissive R6RS/R7RS profiles before asking the host to construct a value. This replaces the current `string->number`-as-recognizer TODO, which confuses valid-but-unrepresentable syntax with invalid syntax on a bounded host.

For a valid lexeme:

1. if the host constructs the number, the token value remains that ordinary number;
2. otherwise the token value is a private vector containing a module-private singleton marker and the exact numeric lexeme.

The marker cannot be constructed by reading source, so the vector cannot collide with an ordinary vector datum. Both independent reads in one process use the same marker object, and Emit's cycle-safe structural `equal?` compares the vector text while treating the marker by identity. `cst->datum` continues to consume token values rather than reparsing their text and introduces no second number parser.

This opaque value is an acceptance and checking representation, not a number: arithmetic predicates are never applied to it, it is never accepted as a configuration width or bytevector octet, and it is not part of a public numeric API. Bytevector validation therefore continues to require a representable exact integer from 0 through 255.

Layer 2 retains ordinary semantic equivalence for host-representable numbers, including `#xff` versus `255`. Two different spellings of an unrepresentable value may compare unequal because the opaque representation retains text rather than performing arbitrary-precision normalization. This does not weaken output safety: layer 1 runs first and rejects every token respelling by exact kind and text. Layer 2 still independently detects structural loss or reordering after re-reading the formatter's output.

Alternatives considered:

- Rejecting valid unrepresentable numbers would violate the permissive-reader invariant and make acceptance depend on the compiler running Pitch.
- Treating them as symbols would conflate two datum kinds and could make a numeric token compare equal to an identifier.
- Implementing canonical arbitrary-precision integers, rationals, reals, and complex numbers solely for layer 2 would create a second numeric tower whose correctness burden is larger than the check it serves.
- Comparing trees or reusing the input token value would be vacuous; both texts are still tokenized, parsed, and projected independently.

### D5. Require a narrow Emit filesystem extension at the real-host edge

R7RS-small provides textual files, existence checks, and deletion, but not directory enumeration, directory/symlink classification, or atomic replacement. Those operations are necessary for existing CLI requirements and cannot be implemented portably inside Pitch.

The port therefore requires a separately specified ordinary Emit library `(emit filesystem)` exporting:

- `directory-list`, returning entry names without `.` or `..`;
- `file-directory?`, following links for the driver's separate directory decision;
- `file-symbolic-link?`, so the driver can refuse traversal through a linked directory;
- `replace-file`, atomically renaming a same-filesystem source over the destination.

Only the R7RS program adapter imports this library and maps it into the existing host record. The CLI driver remains compiler-agnostic and retains the decisions about selection, ordering, traversal, temporary paths, and when replacement is permitted. The Makefile preflight checks the selected Emit version/capability before compiling any Pitch unit and points to the external prerequisite when absent.

Alternative considered: initially support only standard input or individual files. That would make the program compile, but it would not be the Pitch application specified by `cli-file-selection` and `cli-output-disposition`; it would also weaken the one operation capable of destroying source. Shelling out or using configuration as code is prohibited and Emit has no portable FFI suitable for hiding these operations locally.

### D6. Use one manifest and one program entry for every Emit door

The repository's `emit-libs.scm` names each `(pitch …)` `.sld` unit and a `(program pitch …)` entry. Relative paths resolve against the manifest. Development execution passes the same manifest explicitly to `emit run`; standalone delivery uses `emit build pitch`. Both therefore compile the same transitive library graph and standard-library imports.

Build output lives under `build/`. The shipped default configuration is copied beside the real executable. Installation places the real executable and configuration together under a private libexec directory and installs a small shell launcher in `PREFIX/bin`; `exec` preserves arguments and makes the real executable path the program name used for resource lookup. Nothing in the installed layout points at the checkout.

Alternative considered: discover configuration from the current working directory or an environment variable. That would add implicit project configuration contrary to the configuration-loading contract and make identical invocations depend on where they were launched.

### D7. Make Emit the primary behavioral test target without losing independent evidence

Pitch-specific unit and integration tests become R7RS programs compiled/run by Emit. Shared fixtures remain data. The primary `make test`, always run from the repository root, performs:

1. generator drift and manifest checks;
2. the Chez reader regression against authoritative `reader.sls` when the required oracle tool is present according to the existing project policy;
3. Pitch-specific libraries and end-to-end formatting tests under Emit;
4. real CLI filesystem tests against both `emit run` and the built executable;
5. development/AOT output, diagnostic-class, effect, and exit-status parity;
6. `make vendor-verify`.

Oracle targets continue to compare text re-read from real output. No passing result is inferred from comparing a generated artifact with itself. The CI matrix includes a build-and-smoke job with Emit and no Chez on `PATH`, proving that the application dependency was actually removed.

Alternative considered: keep the whole suite on Chez and add only an Emit smoke test. That would let compiler incompatibilities hide outside the entry point and would not establish the shipped target as the behavior authority.

## Risks / Trade-offs

- **[The external filesystem prerequisite is unavailable when apply begins]** → Gate before source conversion, name the exact `(emit filesystem)` contract and minimum Emit revision, and do not weaken CLI behavior as a workaround.
- **[Generated reader translation drifts from its closed mapping]** → Fail on unknown imports/forms, byte-compare regenerated output, and run cross-form token/diagnostic parity plus the pristine upstream regression.
- **[Association-list identity memoization regresses layout performance]** → Preserve the memo interface, add representative corpus timing and frontier-size observations, and move to an Emit identity-table extension later only if measured data warrants it.
- **[Opaque numeric values accidentally escape into arithmetic or bytevectors]** → Keep constructor and marker private, centralize the predicate, and test configuration/bytevector rejection separately from valid source acceptance.
- **[Layer 2 no longer equates alternate spellings of an unrepresentable number]** → Document the boundary, retain semantic equality for representable numbers, and prove layer 1 rejects every respelling before layer 2 can authorize output.
- **[R7RS record identity differs from old nongenerative R6RS linking semantics]** → Treat the port as a breaking runtime/library migration and test behavior through constructors/predicates rather than serialized record identity; no cross-runtime record persistence exists.
- **[Text ports normalize or encode differently from the R6RS transcoder]** → Add byte-level UTF-8, CRLF, Unicode, and interior-line-ending fixtures at the real Emit host boundary before enabling in-place writes.
- **[The large source migration obscures behavior changes]** → Land mechanical library/import/record conversions separately from numeric and host adaptations within the change, keep formatting out of the derived reader, and require existing behavior tests before parity tests are updated.

## Migration Plan

1. Confirm and record the Emit revision providing the prerequisite audit features and `(emit filesystem)` contract; make preflight fail clearly on anything older.
2. Add the closed R7RS portability utilities, generated-reader tool, manifest skeleton, and drift/parity checks while the existing Chez application still supplies comparison output.
3. Add host-independent numeric recognition and opaque values to authoritative `reader.sls`, update its header change list, regenerate `reader.sld`, and pass reader/vendor/datum gates on both hosts.
4. Port leaf libraries and their tests in dependency order, then the format pipeline and CLI driver, without changing public behavior.
5. Add the R7RS Emit entry adapter, real filesystem tests, `emit run` path, program manifest entry, standalone build, and door-parity suite.
6. Switch `make test`, build, install, and documentation to the Emit application; remove the complete Chez launcher only after the standalone parity suite is green.
7. Run `make test`, `make vendor-diff`, `make vendor-verify`, the layout oracle where available, and the no-Chez build/smoke job from the repository root.

Rollback is a normal revert before release. The change writes no persistent application data and changes no configuration schema; generated Emit artifacts and build caches can be discarded. Users of R6RS Pitch libraries must remain on the prior release or migrate to the Emit-built command, because no dual-runtime compatibility period is provided.
