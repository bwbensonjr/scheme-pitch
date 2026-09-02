# Benchmark corpus

The fixed corpus behind `make bench`. It measures how formatting cost scales
with the size and the shape of the input; it says nothing about whether the
output is correct. That is `make test`'s job, and `make bench` is deliberately
not reachable from it — a timing taken under machine load is flaky, and a flaky
check in a correctness suite trains people to ignore failures.

## Members

| member | lines | what it is |
|---|---|---|
| `code-small.scm` | 254 | one copy of the unit |
| `code-medium.scm` | 995 | four copies |
| `code-large.scm` | 2724 | eleven copies |
| `data-large.scm` | 2486 | five very large quoted data forms |

The unit is `src/pitch/cst.sld` plus `src/pitch/table.sld`, taken by `git show`
from a pinned revision rather than from the working tree, so editing `src/`
cannot move the corpus.

**The three code members are the same content at three sizes.** That is the
point of them. A ladder assembled from different modules would report which
modules are in which member, not how cost grows with size; because composition
is held fixed, the largest-to-smallest per-line ratio is attributable to size
alone.

**`data-large.scm` holds size roughly constant and varies shape.** It is
comparable in size to `code-large.scm` and consists of five forms rather than
several hundred. That pairing is what separates a per-form superlinearity from
general per-line overhead: the two members differ in shape and in nothing else
that matters.

## Rebuilding

```
make bench-corpus          # rewrite the members
make bench-corpus-verify   # fail if they no longer match the recipe
```

`tools/generate-bench-corpus.sh` is the whole recipe. The data member is
generated from a fixed linear congruential sequence — no clock, no locale, no
randomness — so it rebuilds byte for byte. The corpus can be reviewed rather
than trusted.

Changing the pinned revision or the copy counts invalidates every recorded
baseline. It is a deliberate act, not maintenance.

## Running

```
make bench                 # best of three
BENCH_REPEATS=1 make bench # one sample per member, about a third of the time
```

The minimum across repeats is reported because load from elsewhere on the
machine can only add time, never remove it.

## What this does not cover

A green pair of ratios is a narrow claim. It does not say:

- **that pitch is fast.** The contract is the shape of the curve. Absolute
  seconds depend on the host and on the Scheme implementation, and they are
  recorded as evidence against a named machine, never as a requirement.
- **anything about startup.** Every measurement is one process over one file,
  so process start, library load and configuration parsing are inside every
  number and are amortized differently at 254 lines than at 2724. A fixed cost
  that grew would show up as the smallest member getting slower, which flatters
  the ratio rather than failing it.
- **anything about a multi-file invocation.** Formatting a directory, a tree,
  or a staged set is not measured. Per-file cost times file count is a guess.
- **memory as a contract.** Peak resident set is reported so that a fix trading
  space for time is visible rather than discovered by a user. No bound is
  stated on it.
- **any input shape outside these four files.** Deep nesting, very long lines,
  pathological comment density and files that refuse are all unmeasured.
- **the cost of the safety checks separately.** Both output checks run inside
  every measurement, which is deliberate: that is what a user pays.
