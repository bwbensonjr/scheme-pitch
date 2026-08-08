## Context

The reference implementation is `sorawee/pretty-expressive` (Racket), the
artifact accompanying *A Pretty Expressive Printer* (Porncharoenwase, Pombrio,
Torlak, OOPSLA 2023). Its core is about 300 lines. It was read in full before
this document was written, so the decisions below are about what to change in the
port and why, not guesses about what the original does.

The algorithm, in one paragraph. A document resolves, relative to a starting
column `c` and an indentation `i`, to a **measure set**: a Pareto frontier of
`(last-column, cost, tokens)` triples, ordered by decreasing last column and
increasing cost, with dominated measures pruned. Concatenation resolves the right
operand once per surviving left measure and merges. Because the frontier is
pruned and the last column is bounded by the *computation width*, the frontier
stays small, which is what turns an exponential choice space into a polynomial
search. Past the computation width the resolver stops maintaining a frontier at
all and produces one lazily-forced **tainted** measure, which is what bounds the
worst case.

Two flags thread through resolution alongside `c` and `i`: `beg-full?` and
`end-full?`, which track whether the position before and after the document must
be at end of line. They exist to support `full`, the combinator that forces a
line break after a document, and they double the number of memo tables.

Constraints from `CLAUDE.md` that bear on this change:

- The CST and the layout engine never branch on dialect. Here that is easy and
  total: the engine never sees a CST either.
- Style tables are data, not code. The engine is the machinery those data drive;
  it must contain no per-form knowledge whatsoever.
- Simplicity and modularity with well-defined interfaces providing observability
  between layers.

## Goals / Non-Goals

**Goals:**

- A faithful port. Where a choice is between "simpler" and "same answers as the
  reference", same answers wins, because the oracle is only worth having if
  disagreement means a bug rather than a known divergence.
- An engine that is a pure function of `(document, cost factory, offset)`. No
  hidden state, no parameters, no I/O.
- Enough observability to debug a printer: the cost and the taint flag come back
  with the text, not just the text.
- Hardening where Scheme lets us be stricter than the reference at no cost —
  specifically, rejecting a line ending inside `text`.

**Non-Goals:**

- Performance parity with the Racket original, which uses unsafe operations,
  mutable memo tables stored on document nodes, and a tuned memoization weight.
  Correctness and legibility first; the oracle will tell us if we broke
  semantics, and profiling can tell us later if we need the tricks.
- Anything about Scheme. No CST, no tokens, no comments, no style tables, no
  dialects. If a decision here requires knowing what a `cond` clause looks like,
  the decision belongs in a later change.
- A port of Racket's `special`, `pretty-print`-to-a-port, or the parameter
  objects. See the decisions below.

## Decisions

### Three libraries, split at the parameterization seam

`(pitch doc)` is the document algebra, `(pitch cost)` is the cost factory, and
`(pitch layout)` is the resolver. The resolver imports both; neither of the other
two imports anything of ours.

The reference puts the cost factory struct in `core.rkt` next to the algorithm.
Splitting it out is worth one extra file because the cost factory is the
*substitution point for style opinions* (`docs/DESIGN.md` §6), so it is the thing
most likely to be written by a caller. A caller building a factory should not
have to import the resolver to do it, and having the interface in a library of
its own makes it obvious that the resolver is parameterized rather than
configured.

### Memoization lives outside the document, in a per-call table

The reference stores four memo tables and four failure flags *on each document
node*, then walks the whole document afterwards clearing them, because a document
can be printed again with a different cost factory and the cached measures are
factory-specific.

The port instead allocates the memo table when resolution starts and drops it
when resolution ends, keyed by `eq?` on the document node.

*Alternative considered:* port the reference's scheme directly. Rejected on three
grounds. Documents stay immutable values, which is what makes them safe to share
and cache in a printer. The cleanup traversal disappears entirely, and with it
the class of bug where a stale table leaks a measure computed under a different
`limit` — a bug that would produce a *plausible wrong layout*, the worst failure
mode a formatter has. And the reference needs a weak hash to make cleanup
terminate on a shared DAG; an external table needs no such thing.

The cost is one hashtable indirection per lookup and re-resolution across calls,
neither of which matters at the sizes involved.

The two memoization *guards* are kept exactly: no memoization when `c > limit` or
`i > limit`, since those are the tainted paths whose results are lazy and
position-dependent in a way the key does not capture.

### Memoize every internal node; drop the weight-7 scheme

The reference memoizes only every seventh node, using a `memo-weight` computed at
construction, to trade hit rate for memory.

The port memoizes every internal node. The paper's complexity bound assumes full
memoization; the weight scheme is an engineering optimization layered on top, and
porting an empirically tuned constant we cannot re-tune is how a port acquires
cargo cult. It changes no answers, so the oracle stays valid either way.

Recorded as the first thing to try if a corpus run is slow.

### Documents are immutable; failure flags are per-call too

The reference caches "this document always fails" back onto the node. Since the
memo table is now external and per-call, the failure cache goes in it, as a
distinguished entry rather than a separate structure.

Static failure — a document built from `fail`, or `(concat (full d) (text "x"))`
with non-empty text — is still detected at *construction* time by the smart
constructors below, which is where the reference detects most of it too. What
the per-call cache adds is the dynamically discovered case, where resolution past
the limit turns out to have no layout.

### The smart constructors are ported, because two of them are semantics

`concat`, `alternatives`, `nest`, `align`, `reset`, `full` and `cost` each
partially evaluate at construction:

| Construction | Result | Why |
|---|---|---|
| `(concat d (text ""))`, `(concat (text "") d)` | `d` | identity |
| `(concat (full d) (text s))`, `s` non-empty | `fail` | **semantics**: nothing may follow a full line |
| `(concat (text a) (text b))` | `(text ab)` | fewer nodes, same measure |
| `(concat fail d)`, `(concat d fail)` | `fail` | strictness |
| `(alternatives fail d)` | `d`; symmetrically | `fail` is the unit of choice |
| `(alternatives d d)` | `d` | idempotence |
| `(nest n (nest m d))` | `(nest (+ n m) d)` | associativity |
| `(nest n d)`, `(align d)`, `(reset d)` where `d` is `text`, `align`, `reset` | `d` | indentation is unobservable there |
| `(full (full d))` | `(full d)` | idempotence |

These read like optimizations, and most are, but the `full`/`text` row is the
definition of `full` and the `text`/`text` row is what lets the resolver assume a
leaf never fails. They are ported as a set rather than cherry-picked, because
that assumption is what removes failure checks from the hot path.

**Consequence worth stating:** the constructors are not injective, so a caller
cannot pattern-match on the shape it built. Nothing in the engine's interface
exposes document structure, so this costs nothing here; it would matter to a
printer that wanted to inspect documents, and it will not.

### `text` rejects a line ending

`(text s)` raises when `s` contains a line ending. The reference does not check.

The immediate argument is arithmetic: `text` contributes `len` to the column and
`cost-text` prices it against the page width. A newline inside makes both wrong,
silently, everywhere downstream — the layout is not merely suboptimal but
mis-costed, and nothing catches it because the output still looks like output.

The specific argument is better. A line comment's token text *includes* the
newline that terminates it — this is already load-bearing elsewhere, it is why
`token-equivalence` has a trailing-line-ending rule at all. So a printer that
naively emits `(text (token-text tok))` for a comment gets a document containing
a newline, and the failure is exactly `docs/DESIGN.md` §6's "the single most
dangerous printer bug in any Lisp formatter". Rejecting it at `text` means the
printer *must* split the terminator off and say what follows, which is the
correct discipline, enforced one layer earlier than the printer assertion §6 asks
for. That assertion is still wanted — this makes it impossible to get wrong by
accident, not impossible to get wrong.

The recognized line endings are the reader's set, the same seven
`token-equivalence` names: line feed, carriage return, CR LF, CR NEL, next line,
line separator, paragraph separator. Sharing the list is deliberate. Two
definitions of "line ending" in one codebase is a divergence waiting to happen,
and this one would divide the losslessness guarantee from the layout engine.

*Alternative considered:* accept the string and split it into `text`/`hard-nl`
automatically. Rejected — it guesses. `CLAUDE.md` says malformed input is refused,
not repaired, and a document is input to this engine.

### The measure's token field is a difference list, not a port writer

The reference's measure holds a procedure that writes to an output port, and its
own comment says this is a workaround for a Racket performance bug.

The port holds `tokens : list-of-string -> list-of-string`, prepending strings in
reverse order; rendering is one `reverse` and one `string-append`. The engine
therefore has no I/O at all and returns a string. `(rnrs io ports)` never appears
in it.

*Alternative considered:* a string output port from `(rnrs io ports)`. Rejected
because measures are built speculatively and discarded — most measures never
reach the output — so a per-measure port is waste, and a shared port cannot work
when the winning measure is chosen after the losers were built.

`pretty-print`-to-a-port is not provided. A caller with a port can `display` the
string.

### `special` is omitted

Racket's `special` passes a non-string value through an output port with a
declared display width. It exists for Racket's structured output ports. Pitch
renders to a string; there is nothing to pass through. Omitted, and the oracle
corpus is specified to avoid it so the omission cannot cause a spurious
disagreement.

### Optional arguments are `case-lambda`, not parameters

The reference uses Racket parameters (`current-page-width`,
`current-computation-width`, `current-offset`, `current-special`) for defaults.
The port uses `case-lambda` arities.

Parameters are dynamically scoped mutable state, which would make the engine's
output depend on something other than its arguments — directly against the goal
of a pure function of `(document, factory, offset)`, and awkward to test, since a
leaked parameter in one test changes another's result. `case-lambda` gives real
optional arguments in R6RS with no such coupling.

### The surface uses the paper's names, and `newline` shadows

Core constructors keep the paper's names: `text`, `newline`, `concat`,
`alternatives`, `nest`, `align`, `reset`, `full`, `cost`, `fail`. Derived:
`nl`, `break`, `hard-nl`, `alt`, `group`, `flatten`, `empty-doc`, and the four
append/concat families (`u-` unaligned, `us-` unaligned with spaces, `v-`
vertical, `a-` aligned, `as-` aligned with spaces).

`newline` collides with `(rnrs io simple (6))`. This is fine and mildly good.
`(rnrs base (6))` does not export `newline`, so no library that only computes
documents has a conflict; only a file doing console I/O does, and R6RS makes that
a compile-time error with an obvious fix (`except` or `rename` on the import)
rather than a silent shadow. Renaming the constructor to avoid a collision that
the module system already reports precisely would trade a clear error for a name
that does not match the paper.

The Racket infix aliases (`<>`, `<$>`, `<+>`, `<s>`, `<+s>`) are **not** ported.
They read as operators in Racket and as line noise in Scheme, and the spelled-out
`u-append` family says which of the five it is.

### Failing to lay out raises; overflowing does not

Two distinct outcomes, kept distinct:

- **No layout exists** — the document is `fail`, or contains only failing
  alternatives. The engine raises. It does not emit a best-effort string, because
  there is no principled one, and a formatter that invents output is the failure
  mode `CLAUDE.md` prohibits.
- **Every layout overflows the computation width** — the engine returns a layout
  with `tainted?` true. The layout is valid and complete; what is lost is the
  optimality claim, since the search stopped comparing.

A caller must be able to tell these apart, and `tainted?` riding along with the
cost is how. A printer that ignores it silently ships lines past the page width
with no signal; that is the caller's decision to make, but only if it is offered.

### The default cost factory is ported exactly, including its arithmetic

Cost is `(badness height)`, compared lexicographically. A newline costs
`(0 1)`. Text of length `len` starting at column `pos`, with page width `w`,
costs `(b(2a + b), 0)` where `a = max(w, pos) - w` and `b = (pos + len) -
max(w, pos)`, and `(0 0)` when `pos + len <= w`.

That expression is the *incremental* squared overflow: when the text starts
already past the page width it is `(pos + len - w)² - (pos - w)²`, and when it
starts before, it is just `(pos + len - w)²`. Written that way it is obviously
the right thing — total badness telescopes to the sum of squared per-line
overflows — and not obviously the same as the reference's form, which is why it
is written out here. Squaring is what makes one line 20 columns over worse than
ten lines 2 columns over.

The default computation width is `floor(page-width * 1.2)`, also from the
reference.

This factory is not pitch's aesthetic. It ships because the paper specifies it
and the oracle needs both sides to agree on one. The dedented-closer reward and
whatever else `docs/DESIGN.md` §6 wants belong to the printer's change, where
there will be real documents to tune against.

### The oracle is driven by one shared corpus file

`tests/oracle/documents.scm` holds a corpus of *document descriptions* — a small
S-expression language mirroring the constructors, plus the page width, the
computation width and the offset to render each at. Two drivers read that one
file: a Scheme one building `(pitch doc)` documents, and a Racket one building
`pretty-expressive` documents. Each emits rendered text, cost and taint flag;
`make oracle-layout` diffs them.

*Alternative considered:* two hand-written parallel test programs. Rejected
because they drift. A case added on one side and forgotten on the other silently
reduces coverage, and nothing reports it. One corpus makes adding a case a
one-line edit that both sides pick up, which is the only version of this that
survives contact with a year of maintenance.

The corpus must include, at minimum: the paper's worked examples; every
constructor in isolation; `full` in both satisfiable and unsatisfiable positions;
documents that overflow, so taint is compared and not just text; deeply shared
DAGs from `group`, so memoization is exercised; and offsets other than zero.

`make oracle-layout` is **not** part of `make test`. `make test` runs on Chez
alone and must keep doing so. The target checks for Racket and for the
`pretty-expressive` package, and when either is missing prints how to install it
and skips — the same shape as `vendor-verify` when the laesare clone is absent.
A skipped oracle is honest; a failing one over a missing dependency trains people
to ignore it.

## Risks / Trade-offs

**The port is subtle and a wrong measure produces plausible output rather than a
crash.** This is the central risk: a formatter that lays out badly still emits
Scheme, and no safety layer catches it, because layers 0 through 3 all pass for
ugly-but-correct output. → The oracle is the mitigation and the reason it is in
this change rather than deferred. Written expectations confirm the cases we
thought of; only an independent implementation finds the ones we did not. Cost,
not just text, is compared, because two layouts can print identically at one page
width and diverge at another.

**Deviating from the reference on memoization weakens the oracle's authority.**
If the port disagrees, "we changed the memoization" is available as an excuse. →
The two deviations are chosen to be answer-preserving by construction: an
external table computes the same values as an internal one, and memoizing more
nodes changes hit rate, not results. Both are recorded here so that a
disagreement has to be argued against this list rather than hand-waved.

**`text` rejecting line endings will be hit by the first printer that emits a
comment.** → That is the point, and it will be hit during development rather than
in output. The error message names the offending string.

**`case-lambda` defaults are fixed at the call site, so a page width has to be
threaded from the CLI down to every call.** → Correct, and preferable to a
parameter. The threading is short: the CLI builds one cost factory and passes it.
Width is one of only two configuration knobs pitch is allowed to have.

**Omitting `special` diverges from the reference surface.** → It cannot be
exercised: pitch has no structured output port. The corpus excludes it, so the
divergence is invisible to the oracle rather than papered over in it.

**Memoizing every node could use noticeably more memory than the reference on
large files.** → Bounded by the number of document nodes times the number of
reachable `(c, i)` pairs below the limit, and the table is dropped when
resolution ends. If a corpus run shows it matters, the weight scheme is the known
fix and is described above.

**Deep recursion.** Resolution recurses on document structure, and a large file's
document is deep. Chez's stack handles this comfortably, but a portable claim
would need checking. → Not a portability promise this change makes; recorded so
that a future port to a shallower host knows where to look.

## Open Questions

- The concrete pitch cost objective. `docs/DESIGN.md` §6 names a dedented-closer
  reward; whether the cost algebra needs a third component to express it, or
  whether `cost` annotations on documents suffice, cannot be settled without
  documents built from real Scheme.
- Whether `pp-tab` and `pp-max-tab` from SRFI 272 (`docs/DESIGN.md` §5) are
  expressed as `nest` amounts by the translation, or want engine support. The
  former is very likely and needs no change here.
- Whether the memoization weight scheme is needed. Deferred to a profile against
  the corpora in `docs/DESIGN.md` §7.
- Whether the engine should expose a document pretty-printer for debugging — a
  way to see the choice tree rather than the chosen layout. Wanted the first time
  a printer produces a surprising result; not built on speculation.
