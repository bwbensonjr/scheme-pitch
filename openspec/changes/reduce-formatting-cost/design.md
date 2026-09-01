## Context

See `proposal.md` — Why, for the measurements. What follows is what the codebase
already says about cost, and what is genuinely unknown.

`docs/DESIGN.md` §6 records that the engine is a port of Πe from *A Pretty
Expressive Printer*, whose resolver is designed to be near-linear in the
document, and it records two divergences from the reference that bear directly on
cost:

> memo tables are external and per-call rather than stored on document nodes and
> cleared afterwards, and every internal node is memoized rather than every
> seventh.

Both were made for correctness — the first is what stops a measure computed under
one cost factory from leaking into a layout under another — and neither has been
measured. "Every internal node rather than every seventh" is a deliberate
divergence from the reference's own tuning, and it is the first thing a profile
should be pointed at, without prejudging that it is the answer.

`layout-resolution` constrains what a fix may do here: memoization is per call and
does not outlive it, and the reason is stated as a correctness argument, not a
performance one. If the profile lands on memoization scope, that requirement is
what the fix has to argue with, and the argument goes in a delta before any code
moves.

The other candidate class is an accumulation that is quadratic in the number of
elements in one form: token vector growth in the reader, CST child sequence
construction in the parser, item sequences in the printer, or string
concatenation in `cst->text`. `char-data.scm` — 80 s per 1000 lines against 42
for code of the same size — is the observation that discriminates between the two
classes, because it varies form size while holding file size roughly constant.

What is **not** known: which of these it is. Nothing in the repository measures
it, and the issue's own two guesses are offered as starting points rather than
findings.

Constraints that bear:

- `CLAUDE.md`: `vendor/laesare/` is never edited, and the diff of
  `src/pitch/reader.sld` against it stays legible and minimal. A fix in the
  reader's token vector is allowed, and it costs a header change-list entry in
  the same commit.
- The cost factory and computation width are fixed by `make oracle-layout`.
- Both output checks re-read the formatter's output. That cost stays.

## Goals / Non-Goals

**Goals:**

- A number exists before an optimization does. The benchmark and the profile land
  first, in that order, and the profile names the term.
- The scaling shape is the contract, and it is measured on a fixed corpus so two
  runs are comparable.
- Output is provably unchanged. A performance change that alters a byte is a
  layout change and has to be proposed as one.

**Non-Goals:**

- Making pitch fast in absolute terms. The target is the shape of the curve; an
  absolute improvement follows from it and is recorded as evidence, not as a
  requirement.
- Parallelism, incrementality, a daemon, or caching across runs. See
  `proposal.md` — What Changes.
- Optimizing the two guesses in issue #15 because they are plausible. They are
  hypotheses to test, and a profile that refutes both is a good outcome.

## Decisions

### 1. Benchmark first, profile second, fix third — and the order is enforced by the task list

The tasks are sequenced so the benchmark exists before any profile is taken and
the profile is recorded before any optimization is written. This is not
ceremony. The failure mode it prevents is specific and common: optimizing the
plausible candidate, measuring an improvement caused by something else in the
same commit, and concluding the story was right.

A corollary: the profile is a deliverable and is written down, whatever it says.
If it refutes both of §6's guesses, that finding goes in `docs/DESIGN.md` §6
regardless of how the rest of the change turns out.

### 2. The contract is a ratio, not a wall-clock target

Per-line cost of the largest corpus member no more than 1.5× the smallest's, and
the data-dense member no more than 1.5× code of the same size. Both are stated in
`specs/formatting-performance/spec.md`.

*Why over the alternatives:*

- **Seconds against a named machine.** Rejected as a durable requirement: it
  ages, it is meaningless on a different host or a different Scheme, and it
  invites a green check on a fast laptop. It survives as *acceptance evidence*
  in tasks §5, against the exact baseline in issue #15, which is the right place
  for a number that is true of one machine on one day.
- **Big-O stated directly.** Rejected: unmeasurable from a build target, and it
  would be satisfied by an implementation with a linear term so large that
  nothing improves.
- **A regression bound against a checked-in baseline table.** Rejected as the
  primary contract because a baseline in seconds has the same host problem, and
  regenerating it on each machine makes it guard nothing. The ratios are
  self-normalizing, which is the property that makes them checkable anywhere.

1.5 is chosen as clearly separating fixed from the measured 3× and 5×, while
leaving room for genuine constant-factor effects at small sizes — cache behavior,
process startup amortized over fewer lines, and the fixed cost of loading a
configuration. A bound of 1.0 would be measuring noise.

### 3. Two ratios, because size and shape are different failures

The size ratio catches a term that grows with the document; the shape ratio
catches a term that grows with the number of children of one node. A single
whole-corpus number would let one hide behind the other, and `char-data.scm` is
evidence that the second exists independently.

The shape ratio is also the cheaper one to test synthetically, which is why the
spec carries a scenario for a single form of N and 4N elements: it isolates
per-form cost from everything else in the pipeline and can be run at several N to
show the curve rather than one point on it.

### 4. Where the fix may land, and what each place costs

The profile decides. Recording the constraints now so the decision is not made
under time pressure later:

| Candidate | Constraint on a fix there |
|---|---|
| Memoization scope in `layout.sld` | `layout-resolution` requires per-call scope for a correctness reason. A change needs a delta on that requirement first, and must show a measure cannot cross factories. |
| Memoizing every node vs. every seventh | A tuning knob the reference already has. Changing it is answer-preserving and belongs in the divergence list in `layout.sld`'s header. |
| Document construction in `print.sld` | Must not change the document's denotation. `make oracle-layout` is the check. |
| Token vector growth in `reader.sld` | `make vendor-diff` stays legible; the header change list is updated in the same commit. |
| CST child sequences in `parse.sld`/`cst.sld` | The leaf sequence invariant and losslessness hold; `cst->text` must still reproduce the input byte for byte. |
| String concatenation in `cst->text` | Same, and it is on the safety-check path, so it must stay obviously correct. |

### 5. The benchmark corpus is checked in, and is not Emit

Emit's sources are the motivating measurement but they are another project's
files. The corpus is a small fixed set in this repository, chosen to reproduce the
reported shape: a ~200-line member, one of ~1,000, one of ~2,500, and a
data-dense member of ~2,500 lines that is a handful of very large forms.
Generated members are generated by a checked-in script so the corpus can be
rebuilt and reviewed rather than trusted.

Emit's files remain the acceptance evidence in tasks §5, where the reported
numbers came from and where the comparison has to be like-for-like.

## Risks / Trade-offs

- **The profile finds nothing conclusive.** The likeliest bad outcome. → Then the
  benchmark still lands, the finding is recorded, and the fix is deferred rather
  than guessed at. Tasks §3 says this explicitly so that reaching it is a
  legitimate stopping point and not a failure to be papered over.
- **Optimizing changes output.** The worst outcome, because output is what pitch
  sells. → The spec requires byte-identical output; tasks §4 compares the whole
  corpus at every width the suite exercises, before and after, and runs the
  layout oracle.
- **A fix that trades memory for time.** Memoizing more, or holding the whole
  token vector longer, can turn a time problem into a footprint problem on a
  large file. → Tasks §4 records peak memory alongside wall time, so the trade is
  visible rather than discovered by a user.
- **Benchmark flakiness.** → It is not in `make test`, it reports host details,
  and the contract is a ratio between two measurements taken in the same run,
  which cancels most machine-level variance.
- **The other two changes filed from issue #15's source add work.**
  `preserve-trailing-comment-alignment` adds a tokenization of the output. → That
  is why the benchmark should land first if the three are sequenced; tasks §1
  notes it, and that change's own task list measures its addition against this
  baseline.

## Open Questions

- Whether the shape ratio should be measured on a synthetic single-form corpus
  member as well as on the real generated table. The spec admits both; which one
  the build target reports can be settled when the profile shows how noisy the
  synthetic case is. It changes neither the contract nor the task breakdown.
