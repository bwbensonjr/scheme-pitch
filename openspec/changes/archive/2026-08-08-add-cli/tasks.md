## 1. The host record

- [x] 1.1 Create `src/pitch/cli.sls` as `#!r6rs`, exporting `run-cli` and the
      host constructor and accessors; the header states why the host exists —
      the driver performs no I/O except through it, so that "a refused file is
      not written" is a testable claim rather than a promise
- [x] 1.2 Define the host record with the eight operations design.md enumerates:
      `read-file`, `write-file`, `rename-file`, `list-directory`, `directory?`,
      `file-exists?`, `stdout`, `stderr`
- [x] 1.3 Create `tests/test-cli.sps` with an in-memory host over an association
      list of path to contents, string ports for the two streams, and a write
      log recording every path written and in what order; add it to the `test`
      target in the `Makefile`
- [x] 1.4 Give the in-memory host a way to mark a path unreadable and a path
      whose write fails, so the error paths in sections 5 and 6 are reachable

## 2. Argument parsing

- [x] 2.1 Parse the closed option set — `--stdout`, `--check`, `--width`,
      `--dialect`, `--help`, `--version` — into an options record with the
      defaults 88 and `common`; interleaved options and operands, `--` ending
      option parsing, `-` an operand naming standard input
- [x] 2.2 Report an unknown option and a missing option value as usage errors,
      before any file is opened
- [x] 2.3 Validate `--width` as a positive exact integer and `--dialect` against
      `common`/`r6rs`/`r7rs` in the parser, with a comment recording why the
      dialect is checked here rather than left to `dialect-style-table`: that
      procedure raises, and letting the condition escape from the per-file loop
      would abandon a partially rewritten run
- [x] 2.4 Reject `--stdout` together with `--check` as a usage error
- [x] 2.5 Handle `--help` and `--version` before anything else: write to
      standard output, return success, read no file even when operands are given
- [x] 2.6 Reject an invocation that names no input — no arguments at all, or
      options with no operand such as `--width 40` or `--check` — by writing the
      same usage summary to standard *error* and returning the usage-error
      status; comment the contrast with 2.5, that the explicit request succeeds
      on standard output and the accidental one fails on standard error, and
      that exiting 0 here would let a script whose file list came out empty
      report a clean run over nothing
- [x] 2.7 Reject `-` combined with any other operand as a usage error, so a
      single run cannot rewrite one input in place while streaming another
- [x] 2.8 Test the whole grammar against the in-memory host — defaults, each
      flag, interleaving, `--`, `-`, every usage error including the bare
      invocation and the options-without-operand case, that `--help` goes to
      standard output with status 0 while the bare invocation goes to standard
      error with status 2, and that every usage error leaves the write log empty
      and reads no input

## 3. Input selection

- [x] 3.1 Read standard input only when it is named — the operand `-`, or
      `--stdout` with no operand — formatting it with the filename `<stdin>` and
      writing to standard output; absence of an operand never selects it, and
      the rejection of that case lives in 2.6
- [x] 3.2 Format a named file whatever its extension
- [x] 3.3 Walk a directory operand depth-first with each directory's entries
      sorted by name, selecting `.sls`, `.sps`, `.scm`, `.ss`, `.sld`, skipping
      entries whose names begin with `.`, and not descending into a symbolic
      link that names a directory
- [x] 3.4 Note at the extension list that it filters discovery and never selects
      a dialect — `docs/DESIGN.md` §4 on `.scm` and `.ss` being used by both
      camps
- [x] 3.5 Report an operand that names nothing, and one that cannot be read, as
      usage errors while continuing with the remaining operands
- [x] 3.6 Test selection: extension filtering, descent, dot-directories skipped,
      a named non-Scheme file honored, deterministic order across two runs, and
      a directory symlink not descended into but followed when named
- [x] 3.7 Test the standard-input paths: `-` alone, `--stdout` alone, `--check -`
      checking the stream, a refusal on the stream naming `<stdin>` with a
      position, and — as negatives — that `--check` alone and `-` mixed with a
      file are usage errors that read no input at all

## 4. The per-file driver

- [x] 4.1 Read the file, call `format-source` with the path, the width, and the
      dialect, and branch on the status; the driver holds one call site for the
      pipeline so the three dispositions cannot drift apart
- [x] 4.2 In-place: compare the formatted text to the text read and return
      without writing when they are equal — the requirement, not an
      optimization; idempotence makes this the steady state and a formatter that
      rewrites unconditionally makes its no-op case indistinguishable from its
      working case
- [x] 4.3 In-place: write to a temporary path in the target's own directory and
      rename over the target, so an interrupted run leaves the file wholly
      unchanged or wholly replaced; comment that this is the only operation in
      the codebase that can destroy a user's source
- [x] 4.4 `--stdout`: write the formatted text to standard output, write no file,
      and emit no separator, banner, or filename between several inputs
- [x] 4.5 `--check`: write nothing at all, name a file that would change on
      standard error, and count a refused file as a check failure
- [x] 4.6 Any status other than success: write nothing under every disposition,
      and leave the file untouched
- [x] 4.7 Continue to the next input after any per-file failure

## 5. Reporting and exit status

- [x] 5.1 Write every diagnostic to standard error as `path:line:column:
      message`, taking the position from `diagnostic-line` and
      `diagnostic-column`, and report multiple parse diagnostics in source order
      via `sort-diagnostics`
- [x] 5.2 Report a check failure as the path and the failing layer, inventing no
      position; report an unsupported line ending against the offending token's
      position
- [x] 5.3 Ignore `format-result-tainted?` entirely: no warning, no effect on the
      status, with a comment citing `format-pipeline`'s requirement that taint is
      a withdrawn minimality claim rather than a defect
- [x] 5.4 Aggregate per-input outcomes as the worst of success, failure, usage
      error, and return that as the exit status; unreadable and unwritable paths
      aggregate as usage errors rather than failures
- [x] 5.5 Test the status table exhaustively: clean run, refusal, check with and
      without changes, bad option, bare invocation, `--check` with no operand,
      `-` mixed with a file, missing path, unreadable path, one failure among
      nine successes, usage error outranking a refusal, and an empty selection
      succeeding

## 6. The write-path tests, stated as negatives

- [x] 6.1 An already-formatted file: the write log is empty
- [x] 6.2 A directory formatted twice: the second run's write log is empty
- [x] 6.3 Each of the three refusal statuses in place: the write log is empty and
      the host's contents for that path are byte-identical to what they were
- [x] 6.4 A refusal under `--stdout`: standard output holds nothing for that file
- [x] 6.5 A refusal under `--check`: no write and no formatted text anywhere
- [x] 6.6 Three files with the middle one refused: the outer two written, the
      middle byte-identical, one diagnostic
- [x] 6.7 A failed write: the target's contents unchanged and the failure
      reported
- [x] 6.8 `--stdout` with a diagnostic for another file: standard output holds
      only formatted text

## 7. The program and packaging

- [x] 7.1 Create `src/pitch/main.sps` importing `(rnrs)`, `(pitch cli)`, and
      exactly `directory-list` and `file-directory?` from `(chezscheme)`; build
      the real host, call `run-cli` with `(cdr (command-line))`, and `exit` with
      what it returns — `command-line` and `exit` are `(rnrs programs (6))` and
      need no implementation-specific import
- [x] 7.2 Keep every decision out of `main.sps`; its header states that porting
      pitch to another R6RS implementation means rewriting this file and nothing
      else
- [x] 7.3 Add a `bin/pitch` target to the `Makefile` generating a wrapper that
      execs `chez --libdirs <abs src> --program <abs main.sps> "$@"`, and add
      `bin/` to `.gitignore` — the wrapper embeds absolute paths and committing
      it would commit one checkout's layout
- [x] 7.4 Add `install` and `uninstall` targets taking `PREFIX`, copying `src/`
      to `$(PREFIX)/lib/pitch` and generating a wrapper pointing at the installed
      copy rather than back into the source tree
- [x] 7.5 Extend the `Makefile` `help` target with `bin/pitch`, `install`, and
      `uninstall`

## 8. Acceptance and documentation

- [x] 8.1 Build `bin/pitch` and run `bin/pitch --check src/pitch/*.sls` against
      the real filesystem, confirming the real host behaves as the in-memory one
      does — this is the step that covers the gap the in-memory tests leave
- [x] 8.2 Run `bin/pitch --stdout` over a file and confirm the output is
      byte-identical to what `format-source` returns for it
- [x] 8.3 Confirm `make test` passes and `make oracle-layout` is unaffected
- [x] 8.4 Add a usage section to `README.md`: installation, the option table, the
      exit-status table, `pitch -` as the standard-input invocation for editors
      with a note that a bare `pitch` prints usage instead of reading a stream,
      and a pre-commit example; remove the statement that the command line does
      not exist
- [x] 8.5 Update `docs/DESIGN.md` §3 so "the CLI, when there is one" describes a
      CLI that exists, and narrow §4's note about the command line so it refers
      to dialect sniffing alone
- [x] 8.6 Add `src/pitch/cli.sls` and `src/pitch/main.sps` to the repository
      layout listing in `README.md`
