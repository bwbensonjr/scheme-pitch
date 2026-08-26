# Emit port baseline

The selected Emit prerequisite revision is
`86669d560964b5f76c9b48529d86066c26fa6eb7`. The revision is the `main`
tip of the adjacent Emit checkout used for the port baseline and is the first
revision selected for Pitch that includes both the audited R7RS facilities and
the filesystem extension and the reader-required `char-general-category`
operation in `(scheme char)`.

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
