## Context

`format-source` is done and its contract was read before this document was
written. It takes `(source filename width dialect)`, returns two values — the
formatted text or `#f`, and a `format-result` carrying a status in
`{ok, unclean-parse, unsupported-line-ending, check-failed}`, a status-specific
detail, and a `tainted?` flag — and it performs no I/O. `dialect-style-table`
raises on a symbol naming no dialect, which `tests/test-format.sps` asserts. A
`diagnostic` carries a message, a token, and a line and column derived from that
token. Every formatted file ends with a newline. Formatting is idempotent, and
`tests/test-format.sps` asserts it over every source file in this repository.

Constraints that bear directly:

- `docs/DESIGN.md` §3 already specifies this program's central behavior: "The
  CLI, when there is one, **refuses to format** an unclean tree: exit non-zero,
  leave the file untouched, report the position." That sentence predates the
  pipeline; this change discharges it.
- `CLAUDE.md` bounds configuration at width and dialect. The flag set is
  therefore closed, not extensible, and adding to it is a design change.
- `docs/DESIGN.md` §4: file extensions are not reliable dialect signals, because
  `.scm` and `.ss` are used by both camps. They are usable as a discovery filter
  and as nothing else.
- Everything in `src/pitch/` is `#!r6rs` and portable. Only two operations this
  program needs are outside R6RS: listing a directory and asking whether a path
  names one. `command-line` and `exit` are `(rnrs programs (6))`; file reading
  and writing are `(rnrs io ports (6))`. That was verified against Chez 10.4.1
  rather than assumed: `(command-line)` under `--program` yields the script path
  followed by the user's arguments, `directory-list` returns bare entry names
  with no `.` or `..`, and `file-directory?` follows symbolic links.

What does not exist is any caller of the pipeline outside the test suite, and any
code in this repository that writes to a file the user did not create.

## Goals / Non-Goals

**Goals:**

- A program that formats files, with the refusal behavior `docs/DESIGN.md` §3
  specified, and with the write path stated precisely enough to test.
- Policy separated from host services, so the interesting behavior — the write
  decision, the recursion, the exit-status aggregation — is asserted by
  `make test` rather than by a shell script nobody runs.
- An exit-status contract a CI script can branch on, distinguishing "unformatted
  code" from "you spelled the flag wrong".
- A no-op run that is genuinely a no-op: no file rewritten, no mtime touched,
  when the tree is already formatted.
- Portability held everywhere it can be. Exactly one file in `src/pitch/` becomes
  implementation-specific, and it contains no decisions.

**Non-Goals:**

- Dialect inference. `--dialect` is explicit; sniffing is a separate change.
- A compiled binary. The wrapper can be replaced later without a user-visible
  difference.
- Diff output, configuration files, parallelism, caching, or a verbosity flag.
- Any change to `format-source`. The CLI is a caller.

## Decisions

### The driver takes a host record, and that is what makes the write path testable

`(pitch cli)` exports `run-cli`, taking an argument list and a *host*, and
returning an exit status. It never calls `exit` and never opens a file itself.
The host bundles ten operations:

```
read-file      path -> string, or raise
write-file     path string -> unspecified, or raise
rename-file    from to -> unspecified, or raise
list-directory path -> list of entry names
directory?     path -> boolean, following symbolic links
symbolic-link? path -> boolean
file-exists?   path -> boolean
stdin          textual input port
stdout         textual output port
stderr         textual output port
```

`rename-file` is there for the atomic write argued below. `stdin` is there
because the driver does no I/O outside the host and standard input is I/O.
`symbolic-link?` is separate from `directory?` because the walk must descend
into a directory and must not descend into a link naming one; asking the two
questions separately keeps that decision in the driver rather than in whichever
host happens to answer it.

`src/pitch/main.sps` builds the real one over `(rnrs io ports)`, `directory-list`
and `file-directory?`; `tests/test-cli.sps` builds one over an association list
of path to contents, with string ports for the two streams.

The alternative is the obvious one: have `(pitch cli)` call the file operations
directly and test the program by running it as a subprocess against a temporary
directory. It was rejected on three counts. Subprocess tests need a temporary
directory, cleanup that survives a failing assertion, and a Chez invocation
inside `make test` that differs from every other line of that target. They are
slow enough that people stop running them. And most decisively: the claim that
matters here is *negative* — that a refused file is not written and an unchanged
file is not written. Asserting a negative against a real filesystem means
checking mtimes and hoping about clock resolution. Against an in-memory host it
is a check that the write log is empty, which is exact.

The record is deliberately not a general "filesystem" abstraction with an
implementation to swap. It is the enumeration of what this program needs from the
world, which is short because the program does very little to the world.

### Argument validation happens before any file is opened

`--dialect` and `--width` are parsed and checked up front, and an invalid value
is a usage error that exits 2 having done nothing.

For `--width` this is ordinary hygiene. For `--dialect` it is a correctness
requirement, because `dialect-style-table` raises. Left unvalidated, a bad
dialect name would surface as an unhandled condition from inside the per-file
loop — after some files had already been rewritten, with a backtrace instead of a
message, and with the run in a state no one can reason about. Validating up front
converts that into a message and an untouched tree.

Rejected: catching the condition per file. That reports the same user error once
per file, and — worse — it makes a static property of the invocation look like a
property of the input.

### In-place is the default, and it is made safe by the write rule rather than by a flag

`pitch f.sls` rewrites `f.sls`. The user chose black's shape over gofmt's, and
the reason it is defensible is that the write is conditional in three ways, each
of which is a requirement rather than an implementation detail:

1. **No write on refusal.** Unclean parse, unsupported line ending, and failed
   check all leave the file byte-identical. `format-source` makes this easy on
   purpose: it returns no text at all when a check fails, so there is nothing to
   write even by accident.
2. **No write when the text is unchanged.** The formatted text is compared to the
   text that was read, and equal means no write at all. Idempotence guarantees
   this is the steady state, so running pitch over a formatted tree touches
   nothing — no mtimes, no rebuilds, no diff noise. Without this rule the second
   run of a pre-commit hook looks identical to the first from the filesystem's
   point of view, which trains people not to trust it.
3. **Read, format, then write, in that order, per file.** The file is fully read
   before it is opened for writing. A crash between reading and writing loses
   nothing; the failure mode of interest is a crash *during* the write.

On that last failure mode: a partial write truncates a source file. The honest
mitigation is write-to-temp-then-rename, which is atomic on POSIX. It is not
free — it needs a temporary name in the same directory, and R6RS has no `rename`,
so it pushes an eighth operation into the host and a second Chez-specific call
into `main.sps`. **The decision is to do it anyway**, because this is the only
place in the codebase where a bug costs a user their source, and the whole design
of the safety checks says that is the failure worth paying for. The host gains
`rename-file`, and the temporary lives beside the target so the rename stays
within one filesystem.

Rejected: writing a `.bak`. It moves the problem rather than solving it, and it
litters the tree.

### Standard input is named, never inferred, and a bare invocation is an error

Standard input is selected by the operand `-`, or by `--stdout` with no operand.
It is never selected by the absence of an operand: `pitch` alone writes the usage
summary to standard error and exits 2.

gofmt reads standard input when given nothing, and that is the convention being
rejected here. The reason is the in-place default. Under gofmt's stdout default,
a bare invocation that unexpectedly blocks on a terminal is a puzzled user and
nothing more. Under an in-place default, "no operand" is overwhelmingly a script
that computed an empty file list — a `find` that matched nothing, an unset
variable, a `git diff --name-only` on a clean tree — and the useful response to
that is a diagnosis, not a process silently waiting on a pipe that will never
carry anything. The input this program is most likely to be handed by accident is
no input at all, and that is precisely the one it declines to guess about.

It follows that `--check` with no operand is a usage error rather than a read of
standard input. Once absence stops implying a stream, it stops implying one
everywhere; `--check -` says the same thing in three more characters and says it
unambiguously.

Exiting 2 rather than 0 on the bare invocation is the load-bearing half. Printing
usage and succeeding is the common shape, and it means a CI step that lost its
path argument reports a green formatter run over zero files. The status is the
only channel a script reads, so it is the one that has to carry the fact that
nothing happened.

This is also the whole justification for having both spellings. `--help` is the
explicit request and gets the successful answer: usage on standard output,
status 0, no file read even when operands are also given. The bare invocation is
the accident and gets the failing one: usage on standard error, status 2. Same
text, opposite streams, opposite statuses — and a user who typed `pitch` to find
out what it does still gets told, which is the only thing the friendlier
convention was buying.

**Where `-` appears among the operands it must be the only one.** Mixing it with
files means one input is rewritten in place while another streams to standard
output — two dispositions live in a single run, decided per operand, with no flag
saying so. It is the most confusing invocation the grammar can express, and
rejecting it costs a user nothing they cannot say in two commands.

The filename reported in diagnostics for standard input is `<stdin>`, matching
the `<string>` placeholder `format-source` already uses when none is given.

### Extensions filter discovery and nothing else

A directory operand is walked, and entries matching `.sls`, `.sps`, `.scm`,
`.ss`, and `.sld` are formatted. A file named explicitly is formatted whatever it
is called, because the user naming it is a stronger signal than its suffix.

Traversal is depth-first with entries sorted by name, so a run's output order is
reproducible and a diff of two runs is meaningful. `directory-list` returns
entries in filesystem order, which is not stable across machines.

Entries beginning with `.` are skipped, which is what keeps a walk out of `.git`
without a special case naming it.

Symbolic links are followed for files and **not** followed for directories.
Following directory links means a cycle can hang the walk, and detecting cycles
needs identity comparison the host does not expose. A linked directory is skipped
rather than guessed at, in keeping with refusing rather than repairing.

### The exit-status table has three values because CI needs to tell them apart

| Status | Meaning |
|---|---|
| 0 | Every file processed successfully; in `--check`, nothing would change |
| 1 | At least one file was refused, or in `--check` at least one would change |
| 2 | Usage error: no arguments at all, an unknown flag, a missing argument, a bad width or dialect, `--check` with no operand, `-` mixed with other operands, incompatible dispositions, or a path that cannot be read |

Collapsing 1 and 2 into a single non-zero is the common shortcut and it makes a
CI failure ambiguous between "your code is unformatted" and "the pipeline
invocation is wrong". Black draws the same distinction for the same reason.

An unreadable or unwritable path is a 2 rather than a 1: it is a fact about the
invocation or the environment, not about the code's formatting, and a
`--check` job that exits 1 because a file was unreadable would report a
formatting violation that does not exist.

The aggregation rule is: process every operand, remember the worst status seen,
and return it. A refusal does not abandon the run. A ten-file invocation where
the third file has an unclosed paren still formats the other nine — that is the
behavior an editor's save-all and a pre-commit hook over a changeset both need,
and the exit status is what carries the bad news.

### Taint is invisible at the command line

A tainted layout exits 0 and prints nothing. `format-pipeline` already specifies
that taint is a withdrawn minimality claim rather than a defect, and the text is
complete and checked like any other. Reporting it would produce a warning the
user cannot act on — the usual cause is a token longer than the page width — and
a warning nobody can act on is one they learn to filter, including the ones that
matter. It stays in the result record for a caller that wants it.

### Diagnostics go to standard error in one format

Every message is `path:line:column: message`, the format editors and `grep -n`
already parse. Positions come from the diagnostic's token, per `(pitch
diagnostic)`; a status with no position — a failed check — reports the path and
the failing layer without inventing one.

The stream split is absolute: formatted text is the only thing that ever reaches
standard output in `--stdout` mode, so `pitch --stdout f.sls > g.sls` cannot
produce a `g.sls` with a warning in it.

### `main.sps` holds the implementation-specific code and no decisions

It imports `(rnrs)`, `(pitch cli)`, and exactly two Chez bindings —
`directory-list` and `file-directory?` — builds the host, calls `run-cli` with
`(cdr (command-line))`, and exits with the result. `command-line` and `exit` come
from `(rnrs programs (6))` and need no implementation-specific import at all.

Porting pitch to another R6RS implementation therefore means rewriting one file
whose entire content is two host operations. That is the point of the split, and
it is worth more than the alternative of accepting a Chez dependency throughout
`(pitch cli)` for the small convenience of not defining a record type.

### `bin/pitch` is generated, not committed

The wrapper embeds absolute paths, which differ per checkout, so committing it
would commit one developer's directory layout. `make bin/pitch` generates it and
`.gitignore` covers `bin/`. `make install PREFIX=...` generates a wrapper with
the *installed* paths — a copy of `src/` under `$(PREFIX)/lib/pitch` — rather
than one pointing back into the source tree, so an installed pitch keeps working
after the checkout moves.

## Risks / Trade-offs

- **In-place default rewrites files without a flag asking for it.** → The three
  write rules above, `--check` for anyone who wants a dry run, and the fact that
  formatting is idempotent and verified before it is written. The residual risk
  is a user who runs `pitch .` in the wrong directory, which is real and is the
  price of the chosen default; git is the mitigation and it is the same one black
  relies on.

- **Refusing a bare invocation breaks anyone who scripted `pitch < f.sls`.** →
  Nobody has, because there is no released version to have scripted against.
  This is the change that introduces the command line, so the convention is being
  chosen rather than broken, and choosing it now is far cheaper than deprecating
  it later.

- **A crash mid-write truncates a source file.** → Write to a temporary in the
  same directory and rename. Accepted cost: one extra host operation and one more
  Chez-specific call.

- **The host record could grow into a general filesystem abstraction.** → It is
  ten operations enumerated from what this program needs, and adding to it
  requires justifying what new thing the CLI does to the world. Reviewing the
  export list is a cheap way to notice scope creep.

- **The in-memory host tests what `(pitch cli)` does, not what the filesystem
  does.** → True, and it is the trade for testing the negative claims exactly.
  The gap is narrow — the real host's operations are one-line wrappers over
  `(rnrs io ports)` and two Chez procedures — and it is covered by formatting
  this repository with the built `bin/pitch` as an acceptance step in the tasks.

- **`--dialect` defaults to `common`, so `define-record-type` gets the generic
  shape.** → Already the documented behavior of `format-source`, and honest until
  sniffing exists. Users who care pass the flag.

- **Skipping directory symlinks will surprise someone with a linked source
  tree.** → They can name the directory as an operand, which is followed. The
  alternative is a walk that can hang, and refusing to guess is the house rule.

- **The wrapper depends on `chez` being on `PATH` at run time.** → Documented in
  the README, and removable later by a compiled-binary change with no user-visible
  difference.
