# Emit port baseline

The selected Emit prerequisite revision is
`41c6f43cd60d205230bc2771d2acc7a5142e0826`. The revision is the `main`
tip of the adjacent Emit checkout used for the port baseline and is the first
revision selected for Pitch that includes both the audited R7RS facilities and
the filesystem extension and the reader-required `char-general-category`
operation in `(scheme char)`, the eq-keyed hash table required by layout
memoization, and stable string output ports required by the CLI in-memory host
suite. It also includes Emit issue #114's project-manifest chaining, which lets
Pitch compile from outside its checkout while resolving non-baked standard
libraries from Emit's installed manifest.

At that revision, `test/pitch-prerequisites-tests.sh` in Emit reports 16 passed
and 0 failed. Its combined fixture passes through both `emit run` and an
`emit build` standalone executable.

An additional imported-library probe was compiled through both doors. It
checked R7RS records, textual string ports, bytevectors, cycle-safe `equal?`,
`case-lambda`, Unicode character and string operations, continuable
exceptions, process context, and writers. Both executions produced:

```text
(#t #t #t #t #t #t #t #t)
```

The prerequisite probe also requires `make-eq-hash-table` and verifies that a
string output port retains its text after later string ports grow Emit's port
table. Task 4.6's full formatter corpus demonstrated that the earlier linear
identity table was not a usable implementation for real source files; task
4.7's 207-assertion in-memory host suite exercises the long-lived stdout and
stderr string ports.

## Filesystem prerequisite status

The selected revision provides `(emit filesystem)` as an ordinary explicit
library exporting exactly `directory-list`, `file-directory?`,
`file-symbolic-link?`, and `replace-file`. Emit's real-host fixture reports 7
passed and 0 failed. It verifies bare entry names, real and linked directory
classification, catchable errors, same-directory replacement effects,
user-library import/re-export, and matching `emit run` and standalone results.

## Chez behavior baseline

Before source conversion, `make test` passes 1,694 assertions across all 12
suites with no failures. The CLI suite contributes 207 assertions covering
exit statuses, standard streams, traversal order and selection, refusal
without writes, unchanged-file suppression, temporary writes, and atomic
replacement effects.

`make format-check` succeeds without output. `make vendor-verify` reports the
reader, writer, and license files pristine. `make vendor-diff` produces the
expected 337-line authoritative reader changeset with SHA-256:

```text
d3f46060f7f481acbcf2f8d93f8fe48b89441d947639993bbf2733c14595775c
```

These counts and the digest describe the pre-port Chez application baseline;
the existing assertions and fixtures remain the executable source of truth.

## Layout corpus timing

The 82-entry layout corpus was timed after task 4.5 with `/usr/bin/time -p`,
discarding serialized output. Three warmed executions of the Emit AOT program
`build/layout-oracle-emit` each took 0.01 seconds wall time; three executions of
the authoritative Chez `tests/oracle/oracle.sps` program each took 0.04 seconds.
Both commands include process startup and corpus parsing, so this is a
representative end-to-end comparison rather than a resolver microbenchmark.
The same runs produced byte-identical text, cost, taint, and failure outcomes.

## Eq-keyed table integration timing

On 2026-08-26, after Pitch's identity-table storage moved from a linear
association list to Emit's `make-eq-hash-table`, the complete print,
configuration, and format suites were run without narrowing. The Emit programs
were rebuilt as standalone executables with the adjacent Emit change and timed
beside the authoritative Chez programs using `/usr/bin/time -p`:

| Suite | Assertions | Chez real/user | Emit AOT real/user |
|---|---:|---:|---:|
| print | 213 passed, 0 failed | 0.17s / 0.15s | 1.55s / 0.18s |
| configuration | 44 passed, 0 failed | 0.09s / 0.08s | 0.29s / 0.03s |
| format | 192 passed, 0 failed | 5.17s / 5.01s | 170.57s / 169.63s |

The R7RS format transcript additionally names every corpus execution: all 14
maintained R6RS source files and the four-file subset under both `common` and
`r7rs`, for 22 explicit corpus passes. Every pass formats real source, re-reads
the produced text for the safety checks, formats it again, and checks the
fixpoint. The 82-entry layout oracle also remained byte-identical between Chez
and Emit. These are observed end-to-end timings, not performance thresholds.
