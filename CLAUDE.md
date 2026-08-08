# Coding Guidelines

- Use OpenSpec for all non-trivial system designs and changes.
- We value simplicity and modularity with well-defined interfaces providing
  observability between layers and components.
- There are some green field design decisions in `docs/DESIGN.md` that may
  evolve but should be referenced as the concrete change designs are developed 
  with OpenSpec.

# Invariants

These hold across the whole codebase. A change that violates one is wrong even
if its tests pass.

## Losslessness

- Concatenating the source text of a CST reproduces the input byte for byte.
  This is checked directly; it is not an aspiration.
- No stage may discard a comment, a `#;` datum comment, a `#| |#` block, a
  bracket shape, a quote abbreviation, a numeric lexeme, or a string escape
  spelling. If a representation cannot carry one of these, the representation
  is wrong.

## Safety checks

- Every check compares against text **re-read from the formatter's output**.
  Comparing an in-memory tree against itself is vacuous and will pass no matter
  what the printer did. This is the single easiest mistake to make here.
- Pitch never calls a host implementation's `read` at runtime. `cst->datum` is
  ours. Host readers appear only in CI, as differential-test oracles.
- The declared-normalizations list is empty. Output tokens must match input
  tokens exactly, modulo whitespace. Adding an entry requires an OpenSpec
  proposal that argues for it.

## Layering

- The CST and the layout engine never branch on dialect. A dialect is a bundle
  of (reader profile, style table, normalization policy) applied at the edges.
- The reader is permissive: it accepts anything valid in R6RS or R7RS and never
  rejects input on dialect grounds. Dialect affects output, not acceptance.
- Style tables are data, not code. Per-form layout rules go in the SRFI 272
  style grammar, not in `cond` branches on head symbols.
- Malformed input is refused, not guessed at. Pitch exits non-zero and leaves
  the file untouched rather than emitting a repair.

## Non-goals

Pitch never reorders code, never rewrites comment contents, and does not grow
configuration beyond width and dialect. These are prohibitions. Existing Lisp
formatters that sort definitions or drop comments are cautionary examples, not
precedents.

# Vendored code

- `vendor/laesare/` is a pristine copy of upstream at the pinned tag. **Never
  edit anything under it.** `make vendor-verify` enforces this.
- All reader work happens in `src/pitch/reader.sls`. Keep the diff against
  `vendor/laesare/reader.sls` legible and minimal; it is both the record of what
  we changed and the candidate patch to offer upstream.
- Any change to the derived reader updates its header change list in the same
  commit.
- `tests/test-reader.sps` is laesare's suite and is the regression baseline.
  Port it no further than library renaming. Pitch-specific tests go in
  `tests/test-recording.sps` or a new file.

# Testing

```
make test             # reader regression suite plus pitch's own tests
make vendor-diff      # changeset against pristine upstream
make vendor-verify    # confirm vendor/ is unmodified
```

Tests must be run from the repository root; the baseline suite opens a relative
path.

# Resources

- We use `ghq` for managing local source code repositories giving access to
  - `../../../gitlab.com/weinholt/laesare` — the `laesare` R6RS/R7RS reader
  - `../../cisco/ChezScheme/` — the Chez Scheme R6RS implementation
- Chez Scheme is normally available as `chez`
- Racket is normally available as `racket` (used to run `raco fmt` for output
  comparison, and as the reference for the `pretty-expressive` layout engine)
