## Why

Formatting cost grows faster than linearly in file size. Reported as issue #15,
measured with pitch 0.1.0 on an 8-core M-series laptop, one `--check` invocation
per file over Emit's sources:

| file | lines | seconds | s/1000 lines |
|---|---|---|---|
| `src/dump.ss` | 199 | 3 | 15 |
| `src/passes/expand.ss` | 685 | 19 | 28 |
| `src/parse.ss` | 985 | 21 | 21 |
| `src/repl-core.ss` | 1422 | 32 | 23 |
| `src/core.ss` | 1546 | 52 | 34 |
| `src/emit.ss` | 1837 | 78 | 42 |
| `src/prelude.scm` | 2477 | 112 | 45 |
| `lib/scheme/char-data.scm` | 2397 | 191 | 80 |

**Per-line cost roughly triples from 200 lines to 2,500.** That is the shape of
the number, and it is what makes this a specific defect rather than uniform
slowness: a formatter that were merely slow would show a flat s/1000-lines
column.

**`char-data.scm` is the informative outlier.** It is a generated Unicode table —
a small number of very large data forms rather than many small ones — and it
costs 80 s per 1000 lines against 42 s for hand-written code of the same size. A
per-*form* superlinearity fits that observation; general per-line overhead does
not.

**It is not a correctness problem and it is not, today, an adoption blocker.**
Every one of those files produced verified output and pitch refused nothing
across 38 files. It is a usability problem, and it changes what a project can
build on pitch:

- A pre-commit hook cannot check a tree. It has to check staged files, and
  staging `src/prelude.scm` still costs 112 s.
- `pitch --check` over a directory is a CI job, not a fast local gate: about
  442 s sequential for the 13,229-line set, about 150 s at `-P4`.
- Editor-on-save is fine for a small file and not viable for a 1,500-line one.

**Why now.** The measurements exist, they point somewhere specific, and there is
currently no benchmark in the repository that would notice if this got worse. The
two other changes filed from the same source (`fill-quoted-data-lists` and
`preserve-trailing-comment-alignment`) both add work to the pipeline — the second
adds a whole tokenization — and neither has a number to be judged against.

## What Changes

- **A size-graded benchmark, checked in and reproducible.** A `make bench`
  target over a corpus whose members span at least an order of magnitude in size
  and include a data-dense member alongside hand-written code. It reports
  per-file wall time, per-1000-line cost, and the ratio between the largest and
  smallest members — the ratio being the number this change is actually about.

- **A recorded profile that names the dominant term before anything is
  optimized.** `docs/DESIGN.md` §6 already names two candidates and offers them
  as guesses: the layout engine's document construction or memoization, and a
  quadratic in an accumulation — token vector growth, CST child sequences, or
  string concatenation in `cst->text`. The `char-data.scm` result fits the second
  better than the first. This change requires the profile to settle it rather
  than optimizing on the strength of a plausible story.

- **The fix, whatever the profile names**, together with the requirement it has
  to satisfy: per-line cost roughly flat across the graded corpus, and data-dense
  input no more expensive per line than code.

- **Output is byte-identical before and after.** A performance change that
  altered a single byte of output would be a layout change wearing a disguise. It
  is stated as a requirement so it is checked rather than assumed.

Deliberately out of scope:

- **Parallelism, incremental formatting, or a daemon.** All of them make a
  superlinear cost cheaper to live with rather than making it linear, and each is
  a large change that this one would prejudge.
- **Changing the cost objective or the computation width to buy speed.** The
  shipped factory is the reference's and `make oracle-layout` requires both sides
  to agree on it. A faster formatter that resolves a different layout is a
  different formatter.
- **Weakening a safety check.** Both layers re-read the output, and one of them
  tokenizes it. That cost is deliberate and is not the fat here.
- **A target expressed in absolute seconds in the specification.** Wall time
  depends on the host and the Scheme implementation. The durable contract is the
  scaling shape; the absolute improvement is recorded as acceptance evidence
  against a named baseline instead.

## Capabilities

### New Capabilities

- `formatting-performance`: what pitch guarantees about how formatting cost
  scales with input size and shape, and the benchmark that measures it. This is
  the first capability in the project to be about cost rather than about output,
  and it is deliberately separate from `layout-cost`, which is the objective the
  engine minimizes and has nothing to do with how long minimizing it takes.

### Modified Capabilities

None yet. The diagnosis may require one: if the dominant term turns out to be
memoization scope, `layout-resolution`'s "Memoization is per call and does not
outlive it" is the requirement that constrains the fix, and a delta against it
must be added to this change *before* the fix is implemented rather than
discovered afterwards.

## Impact

- A new benchmark corpus and a `make bench` target. The corpus is fixed and
  checked in, since a benchmark over whatever files happen to be present measures
  the wrong thing on every machine.
- `src/pitch/` — where the fix lands is what the profile decides. The named
  candidates are `layout.sld`, `doc.sld`, `print.sld`, `parse.sld`, `cst.sld`
  and the token vector in `reader.sld`; a change to the last of these has to keep
  `make vendor-diff` legible, per `CLAUDE.md`.
- `make test` — unchanged. Timings are flaky under load and do not belong in a
  correctness suite; `make bench` is a separate target and is not run by it.
- `docs/DESIGN.md` §6 — the cost note currently says the shipped objective is the
  reference implementation's and says nothing about resolution *time*. The
  profile's finding belongs there, whichever way it goes.
- Issue #15 — the profile and the measured before/after are the reply.
