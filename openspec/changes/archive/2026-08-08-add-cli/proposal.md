## Why

Every layer is built and wired: `format-source` takes a source text and returns
formatted text or a reason why not, verified by re-reading its own output. What
does not exist is any way to run it. Pitch is a formatter that cannot format a
file — there is no argument parsing, no file reading, no file writing, and no
exit status, so the only caller is the test suite. Six archived proposals in a
row deferred the CLI as "separate and small"; it is now the only thing between
the pipeline and a user.

It is also the first code in this repository that can destroy someone's work.
Everything below `format-source` is a pure function: the worst a bug can do is
return a wrong string, and the safety checks exist to catch exactly that. The
CLI writes to files. That asymmetry is the reason this change is worth a
proposal rather than a commit, and it is why the write path gets requirements of
its own rather than being treated as plumbing.

## What Changes

- **A driver, `(pitch cli)`, pure R6RS and testable without a subprocess.**
  `run-cli` takes an argument list and a *host* — a record bundling the handful
  of operations R6RS does not portably provide: read a file, write a file, list a
  directory, ask whether a path is a directory, and two output ports. It returns
  an exit status rather than calling `exit`. The tests construct a host backed by
  in-memory strings, so the write path, the recursion, and the exit-status table
  are all asserted in `make test` without touching the filesystem or spawning a
  process. This is the seam that makes "the CLI leaves the file untouched when a
  check fails" a testable claim instead of a promise.

- **A program, `src/pitch/main.sps`.** The Chez-specific half: build a real host
  from `command-line`, the port operations, `directory-list` and `file-directory?`,
  call `run-cli`, and `exit` with what it returned. It contains no policy, and
  nothing else in `src/pitch/` learns a Chez-ism.

- **In-place is the default; `--stdout` opts out.** `pitch f.sls` rewrites
  `f.sls`. `pitch --stdout f.sls` writes to standard output and touches nothing.
  This follows black rather than gofmt, and it is the shape the pre-commit and
  format-on-save cases want. The cost — a bare invocation mutates the working
  tree — is paid down by the write rule below rather than by a flag.

- **A file is written only when its text actually changes.** Formatting is
  idempotent, so a run over an already-formatted tree must be a no-op at the
  filesystem level: no rewritten mtimes, no rebuild storm, no diff noise. This
  is a requirement, not an optimization.

- **A refusal never writes.** An unclean parse, an unsupported line ending, or a
  failed safety check leaves the file exactly as it was and reports the position
  on standard error. `docs/DESIGN.md` §3 has specified this behavior for the CLI
  since before there was one — "exit non-zero, leave the file untouched, report
  the position" — and this is the change that owes it. In a multi-file run the
  refusal is per-file: the other files are still formatted, and the exit status
  remembers.

- **`--check` writes nothing and reports whether anything would change.** The CI
  and pre-commit shape. It runs the identical pipeline and compares the result
  against the file's current contents; a file that would change is named on
  standard error and makes the run exit non-zero.

- **Operands: files, directories, and standard input, which must be named.**
  Standard input is selected explicitly — by the operand `-`, or by `--stdout`
  with no operand — and never by the mere absence of one. A directory operand is
  walked for Scheme source files. Extensions are a *discovery* filter only;
  `docs/DESIGN.md` §4 is explicit that they are not reliable dialect signals, and
  nothing here treats them as one. Where `-` appears it must be the only operand:
  mixing it with files would rewrite one input in place while streaming another
  to standard output, which is the most confusing thing the grammar can say.

- **A bare `pitch` prints usage and fails.** The gofmt convention of reading
  standard input when given nothing is the one input this grammar refuses to
  infer. An invocation that named no input asked for nothing, and a script that
  reaches one by accident should not see success — it should see the usage
  summary on standard error and status 2.

- **`--dialect`, and nothing that guesses.** `common` (the default), `r6rs`, or
  `r7rs`, passed straight through to `format-source`. `dialect-style-table`
  *raises* on an unknown symbol, so the CLI validates the name before any file is
  opened and reports it as a usage error; letting that condition escape from
  inside a multi-file loop would abandon a partially-processed run with a
  backtrace. Content sniffing and the magic-comment override are explicitly out
  of scope — see below.

- **`--width` (default 88), `--version`, `--help`.** Width is passed through.
  `--help` and `--version` write to standard output and exit zero, because a user
  who asked for them got what they asked for. That is exactly what distinguishes
  them from the bare invocation above, and it is why both spellings earn their
  keep: the explicit request succeeds on standard output, the accidental one
  fails on standard error.

- **An exit-status table that distinguishes the three outcomes.** 0 for success,
  1 for "a file was refused or would change", 2 for a usage error. A CI script
  needs to tell "your code is unformatted" from "you spelled the flag wrong", and
  collapsing them into a single non-zero makes that impossible.

- **Taint does not affect exit status.** A tainted layout is a withdrawn
  minimality claim, not a defect; the text is complete and checked like any
  other. `format-pipeline` already says so, and the CLI must not quietly promote
  it to a failure.

- **`bin/pitch` and `make install`.** A generated wrapper that execs
  `chez --libdirs <src> --program <main.sps>`, plus an install target taking
  `PREFIX`. No new toolchain, and it matches how `make test` already runs.

Explicitly not in scope:

- **Dialect sniffing and the magic comment.** `detect-scheme-file-type` is
  already vendored and `docs/DESIGN.md` §4 specifies the inference, but it comes
  with its own refusal semantics on ambiguous input and its own override syntax.
  Folding it in would make this change about dialect inference rather than about
  delivering the formatter. `--dialect` is the explicit escape hatch until then.
- **A compiled executable.** `compile-program` and a boot file would cut startup
  time and drop the runtime dependency on `chez` being on `PATH`. That is a
  packaging change with its own build machinery, and it can replace the wrapper
  later without any user-visible difference.
- **A diff mode.** `--diff` is what black offers alongside `--check`. It needs a
  diff algorithm or an external one, and `--stdout` piped to `diff` covers the
  case today.
- **Configuration files.** `CLAUDE.md` bounds configuration at width and dialect.
  No `pitch.toml`, no per-project defaults, no `; pp-styles:` file-level plumbing
  here — the last is the style grammar's business.
- **Parallelism, caching, and a `--quiet` flag.** Speed work wants a corpus to
  measure against.
- **Any change to `format-source`.** The CLI is a caller. If it needs something
  the pipeline does not expose, that is a signal to look again rather than to
  widen the pipeline.

## Capabilities

### New Capabilities

- `cli-invocation`: the argument grammar — the flag set, their defaults, how
  operands are distinguished from flags, `--` and `-`, `--help` and `--version`,
  the refusal of an invocation that names no input, and what else counts as a
  usage error. Includes the up-front validation of `--dialect` and `--width`
  before any file is opened, so that a bad argument cannot be discovered halfway
  through a run.
- `cli-file-selection`: what gets formatted — named files, standard input when
  and only when it is named, directory recursion, the extension set used for
  discovery, a deterministic traversal order, the fact that a file named
  explicitly is formatted regardless of its extension while a directory walk
  filters, and the prohibition on combining `-` with any other operand.
- `cli-output-disposition`: what happens to the formatted text — in-place by
  default, `--stdout`, `--check`, the rule that a file is written only when its
  text differs, the rule that a refusal leaves the file untouched, and how a
  multi-file run continues past a failure rather than abandoning the remaining
  files.
- `cli-reporting`: what the user is told and what the shell sees — the
  exit-status table, the aggregation rule across many files, the diagnostic
  format on standard error including file, line and column, the separation of
  formatted text on standard output from diagnostics on standard error, and the
  requirement that taint is not reported as a failure.

### Modified Capabilities

None. `format-pipeline` gains a caller, not a requirement: `format-source` keeps
its signature, its statuses, and its refusal to return unverified text. No
requirement in `cst-translation`, `output-verification`, `style-grammar`, or any
other existing spec changes.

## Impact

- `src/pitch/cli.sls` — new. Argument parsing, the host record, the per-file
  driver, the write decision, the reporting, and the status aggregation. Pure
  R6RS: it imports `(pitch format)` and `(pitch diagnostic)` and performs no I/O
  except through the host it was handed.
- `src/pitch/main.sps` — new. The Chez program: real host, `command-line`,
  `exit`. The only file in the repository that is not portable R6RS, and it is
  small enough to read in one screen.
- `tests/test-cli.sps` — new, joining `make test`. In-memory hosts covering the
  argument grammar, the three dispositions, recursion, the exit-status table,
  and — most importantly — that a refused file is byte-identical afterward and
  that an already-formatted file is not written at all.
- `Makefile` — `test` gains `test-cli.sps`; new `bin/pitch` generation and an
  `install`/`uninstall` pair taking `PREFIX`; `help` gains the new targets.
- `bin/` — new directory, holding the generated wrapper. Ignored by git.
- `README.md` — a usage section: installation, the flags, the exit statuses, and
  the pre-commit invocation. The note that pitch has no CLI comes out.
- `docs/DESIGN.md` — §3's "the CLI, when there is one" becomes a statement about
  a CLI that exists; §4's note that the command line does not exist yet is
  narrowed to sniffing alone.
- `src/pitch/format.sls`, `src/pitch/reader.sls`, `vendor/laesare/`, and every
  other existing library: untouched.
