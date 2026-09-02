# Measurements

The record this change is judged against. Written in the order it was taken:
baseline first, then the profile, then the effect of the fix. Nothing here is a
requirement — the requirements are ratios and live in
`specs/formatting-performance/spec.md`. These are the numbers from one machine
on one day, which is what makes them evidence rather than a contract.

Host for every number below unless stated otherwise:

```
Darwin 25.5.0 arm64, Apple M3
pitch 0.1.0, Emit ahead-of-time build at build/pitch
make bench, best of three
```

## 1. Baseline, before any optimization

Taken at `4ad63ec` plus the benchmark itself, with no change to `src/pitch/`.

| member | lines | seconds | s/1000 lines | peak MiB |
|---|---|---|---|---|
| `code-small` | 254 | 1.01 | 3.98 | 44.6 |
| `code-medium` | 995 | 4.80 | 4.82 | 179.5 |
| `code-large` | 2724 | 17.15 | 6.30 | 410.5 |
| `data-large` | 2486 | 36.04 | 14.50 | 686.1 |

```
size ratio   code-large / code-small   1.58  (bound 1.50)  OVER
shape ratio  data-large / code-large   2.30  (bound 1.50)  OVER
```

**The corpus reproduces the shape issue #15 reported.** Per-line cost rises
monotonically with size across three members whose composition is identical —
3.98, 4.82, 6.30 — so the rise is attributable to size and not to which modules
landed in which member. And the data-dense member is worse still, at 2.30 times
the per-line cost of hand-written code of comparable size. Issue #15 measured
about 3× and about 1.9× for the same two effects over Emit's sources; the
directions agree, and the shape effect is larger here because `data-large` is
five forms where `char-data.scm` is more.

Peak memory is recorded from the start so that a later fix trading space for
time is visible rather than discovered by a user.

## 2. The profile

Two profiles, on the discriminating pair: `code-large` (2724 lines of
hand-written code, several hundred small forms) and `data-large` (2486 lines,
five very large forms).

Method: the pipeline was cut into prefixes — read, tokenize+parse,
`cst->document`, `layout`, `check-output` — and each prefix built as its own
program, so a stage's cost is the difference between two whole-process
measurements. Emit has no `(scheme time)`, so there is no in-process clock to
read; differencing whole processes needs none. macOS `sample` supplied the
call-graph profiles.

### 2.1–2.2 Cost across the stages

| stage | `code-large` | `data-large` |
|---|---|---|
| read | 0.01 | 0.00 |
| tokenize + parse | 0.42 | 0.67 |
| `cst->document` | 7.00 | 1.09 |
| `layout` | 9.36 | 18.99 |
| `check-output` | 1.09 | 22.69 |

Tokenizing and parsing are a rounding error in both. The cost is in translation,
resolution and checking — and the split between them is completely different for
the two members, which is the first sign that one explanation will not cover
both.

`check-output` is the trap in this table. Measured on its own, from files, the
two check layers cost `data-large` 2.25 s and 2.79 s. Inside the pipeline they
cost 22.69 s. Nothing about the checking changed; what changed is that the
document and the resolver's memo tables are still live, so every allocation the
checks make is marked against a much larger heap. Reading 22.69 s as "the checks
are slow" would have sent the fix to the wrong library.

### 2.3 The size hypothesis: refuted

One file's content repeated, so form size is held constant and only file size
varies:

| copies | lines | s/1000 lines |
|---|---|---|
| 1 | 181 | 4.36 |
| 2 | 362 | 4.31 |
| 4 | 724 | 4.68 |
| 8 | 1448 | 5.39 |

Near-flat. **Cost is not driven by file size.** The rise `make bench` reports
across the graded corpus, and the rise issue #15 reported across Emit's sources,
are both real but neither is caused by the file being longer.

### 2.4 The shape hypothesis: confirmed, then explained away

A single form of N elements, `cst->document` only:

| N | flat list of distinct identifiers | quoted data, one repeated symbol |
|---|---|---|
| 1000 | 0.19 | 0.10 |
| 2000 | 0.73 | 0.23 |
| 4000 | 2.84 | 0.48 |
| 8000 | 11.02 | 0.40 (N=4000) |

The left column quadruples per doubling — a clean quadratic. The right column
doubles. **The two differ in nothing but how many *distinct identifiers* the
form contains.** The node count, the item count, the document size and the
number of calls into every library are identical.

Holding the work exactly constant at 8000 elements and varying only how many of
the identifiers are distinct:

| distinct identifiers | `cst->document` |
|---|---|
| 1 | 0.38 |
| 500 | 0.91 |
| 1000 | 1.57 |
| 2000 | 2.89 |
| 4000 | 5.87 |
| 8000 | 10.80 |

Straight-line in the number of distinct identifiers. Cost is the product of two
factors — how much work there is, and how many distinct symbols the run has
interned — and both grow with the input. That product is the quadratic.

### 2.5 The finding: `rt_intern` is a linear scan

`sample` on the translation stage puts `rt_intern` and `strcmp` at the top of
every hot stack, reached from `doc-full?`, `doc-align?`, `doc-nest?`,
`doc-reset?`, `doc-concat?` and `make-doc-concat` — that is, from ordinary
record predicates and constructors in `(pitch doc)`.

Emit's runtime interns symbols by walking its whole symbol table and `strcmp`ing
each entry (`src/runtime/runtime.c`, `rt_intern`). Emit's compiled record
operations intern their type name on each call. So every record predicate costs
O(symbols interned so far), and pitch's reader interns a symbol for every
identifier token it lexes (`src/pitch/reader.sld`, `string->symbol` at the
identifier cases, inherited from laesare). Both factors are linear in the input;
the cost is their product.

How much of pitch's measured cost this is, on real input rather than a
synthetic: prepending K unused distinct identifiers to `code-large` and
subtracting both the unprepended cost and the prefix's own cost leaves the pure
interference term.

| K unused symbols added | `code-large` + prefix | prefix alone | interference |
|---|---|---|---|
| 0 | 6.92 | — | 0.00 |
| 2000 | 43.37 | 1.81 | 34.64 |
| 4000 | 81.95 | 7.09 | 67.94 |
| 8000 | 173.09 | 27.56 | 138.61 |

About 17 s per thousand symbols, and `code-large`'s own translation is 6.92 s.
Its own symbol count accounts for essentially all of it: **translation is not
doing arithmetic on documents, it is doing string comparison in the runtime.**

### The two candidates `docs/DESIGN.md` §6 named

**Memoization scope and granularity in `layout.sld` — refuted as the dominant
term, implicated as a secondary one.** No memo-table operation appears near the
top of either profile. It is not free, though: with symbol count held at one,
`layout` still grows superlinearly (0.44, 1.19, 4.70 for N = 1000, 2000, 4000),
and the layout profile is dominated by `GC_mark_from`. Boehm's mark cost is
proportional to the live heap, and per-call memo tables over every internal node
are a large part of what is live. That is a memory-retention effect, not an
algorithmic one, and it is second by a wide margin.

**Quadratic accumulation in the token vector, the CST child sequences, or
`cst->text` — refuted.** Tokenizing and parsing are linear in every measurement
taken (0.02 s at N=1000 to 0.26 s at N=8000, over a 16× span at 8× the size).
`cst->text` does not appear in either profile at all.

### 2.6 Stated plainly

Neither guess was right. The dominant term is not in any of the places this
change expected to look, and it is not in `src/pitch/` at all: it is
`rt_intern`'s linear scan in the Emit runtime, amplified by pitch's reader
interning every identifier it sees. Formatting cost is approximately

    work done  ×  distinct symbols interned

and pitch makes both factors grow with the input.

## 3. The fix

### 3.1 The term, and what is predicted of it, before any code moves

The mechanism, isolated: two million `eq?` comparisons of a symbol against a
constant, with the intern table pre-loaded to a given size.

| interned symbols | `(eq? x 'concat)` | `(eq? x kind-concat)` |
|---|---|---|
| 500 | 2.19 | 0.00 |
| 4000 | 15.39 | 0.02 |
| 8000 | 30.59 | 0.07 |

**A quoted symbol literal is re-interned every time it is evaluated**, and
interning is a linear scan. Bound to a variable once, the same comparison is
free. Emit does not hoist the literal, and `rt_intern` does not hash.

`(pitch doc)` discriminates every document node this way — `doc-concat?`,
`doc-nest?`, `doc-align?`, `doc-reset?`, `doc-full?` and their siblings are each
`(eq? (doc-kind d) 'literal)` — and those predicates are the inner loop of
`flatten`, `doc-map-children` and the resolver. They are the five names at the
top of the translation profile.

**The fix: bind each document kind to a variable once, and compare against the
variable.** Nothing else changes — same symbols, same record layout, same
documents, same layouts, same output.

**Predicted effect, written before the change is made:**

- Translation and resolution both fall substantially; translation is nearly all
  intern scan on `code-large`, and the resolver runs the same predicates.
- The size ratio improves, because the term removed is one that grows with the
  input on both factors.
- The shape ratio improves less. `data-large`'s cost is more in the resolver and
  in GC than in translation, and GC is untouched by this.
- **Neither ratio is predicted to reach 1.5 on this change alone.** The same
  literal-symbol pattern remains in `print.sld`, `cst.sld`, `layout.sld` and the
  reader, and the intern table still grows with every distinct identifier the
  reader sees. This is one term of several, measured on its own as required.

### 3.4 Term 1: document kinds in `(pitch doc)`

Ten quoted symbol literals bound to variables. `make bench`, best of three:

| member | before | after | change |
|---|---|---|---|
| `code-small` | 1.01 | 0.61 | 1.7× faster |
| `code-medium` | 4.80 | 3.06 | 1.6× faster |
| `code-large` | 17.15 | 12.08 | 1.4× faster |
| `data-large` | 36.04 | 41.05 | within its noise band |

Translation of `code-large` fell from 7.00 s to 2.49 s, and the synthetic
sensitivity to distinct identifiers fell from 28× to 6× across the same 8000-symbol
span. As predicted, the resolver barely moved: the same literal pattern was
still in its inner loop, one library further down.

### 3.4 Term 2: table kinds in `(pitch table)`

`check-key` ran `(case (table-kind table) ((symbol) ...) ((integer) ...))` on
every table operation, and the resolver's memo tables are read constantly. `case`
over symbols is the same defect as `eq?` against a literal. Three bindings, and
`case` replaced by `cond` over them:

| member | baseline | term 1 | term 2 | total |
|---|---|---|---|---|
| `code-small` | 1.01 | 0.61 | 0.24 | **4.2× faster** |
| `code-medium` | 4.80 | 3.06 | 1.55 | **3.1× faster** |
| `code-large` | 17.15 | 12.08 | 7.88 | **2.2× faster** |
| `data-large` | 36.04 | 41.05 | 56.53 | **1.6× slower** |

```
size ratio   code-large / code-small   3.06  (bound 1.50)  OVER
shape ratio  data-large / code-large   7.86  (bound 1.50)  OVER
```

**Both ratios got worse, and the data-dense member got slower.** Neither is a
reason to revert: the numerator and denominator of both ratios are now measuring
something else. Removing a cost that was flat-ish per line unmasked the terms
that are not.

### The data-dense member's regression, and what is under it

`data-large` is now consistently 58–65 s where it was 36–42 s. Two mechanisms,
both measured:

**Boehm's heap sizing.** Peak resident fell from 686 MiB to 561 MiB as the
program got faster, and the collector runs more often against a large live set.
Forcing a large heap recovers a third of it:

| | seconds | peak |
|---|---|---|
| default | 60.39 | 561 MiB |
| `GC_FREE_SPACE_DIVISOR=1` | 60.75 | 660 MiB |
| `GC_INITIAL_HEAP_SIZE=2e9` | 44.61 | 2205 MiB |

**A third quadratic, previously hidden under the first.** With interning gone,
the top of `data-large`'s profile is `open-output-string` →
`rt_port_open_output_string` → `open_memstream` → `funopen` → `__sfp`, at 8721
of 15490 samples. `__sfp` walks libc's list of `FILE` objects looking for a free
slot. Pitch's reader allocates a string port per token through
`call-with-string-output-port`, and nothing closes them, so the list grows
monotonically and every later token pays for every earlier one. Cost is again
quadratic, this time in token count rather than symbol count — which is why the
data-dense member, with its enormous token count in few forms, is where it shows.

### Where this leaves the diagnosis

Three distinct superlinear terms have now been measured, and **not one of them is
in pitch's algorithms**:

1. `rt_intern` is a linear scan and Emit does not hoist quoted symbol literals,
   so a symbol comparison costs O(symbols interned).
2. `open-output-string` goes through libc `funopen`, whose `__sfp` is a linear
   scan of a list nothing prunes, so a string port costs O(ports created).
3. Boehm's heap-growth heuristic sizes the heap from the mutator/collector time
   ratio, so making the mutator faster makes the collector run more often
   against the same live set.

Pitch's own pipeline — tokenize, parse, translate, resolve, check — has been
linear in every controlled measurement taken. The two terms fixed so far were
fixed by *not writing a symbol literal*, which is a workaround for (1) rather
than a repair of it.

### Interim verification of the two terms landed so far

Not section 4 — the fix is not finished — but the two changes made were checked
before the work paused:

- Every Emit application suite passes: 19 programs, including `test-doc-r7rs`
  (118), `test-layout-r7rs` (79), `test-print-r7rs` (234), `test-format-r7rs`
  (204), `test-check-r7rs` (115), `test-cli-r7rs` (207). Zero failures.
- The whole corpus formatted by a build from before the two changes and a build
  from after, at widths 40, 60, 80, 100 and 120: **byte identical**, and the same
  exit status, at every width.
- `make oracle-layout`: 82 entries, all agreeing on text, cost and taint.
- `make self-check`: clean.
- Idempotence holds on all four corpus members.
- `check.sld` and `format.sld` are untouched, so both output checks still run
  over text re-read from the formatter's output, and no refusal was relaxed.

`make test` could not be run end to end in this environment: `tools/audit-r7rs.sh`
requires `rg`, which is not installed here. Everything downstream of that gate was
run directly, as listed above.

### 3.4 Term 3: `rt_intern`'s linear scan, in the Emit runtime

The root of terms 1 and 2 rather than another instance of them.
`src/runtime/runtime.c`, `rt_intern`, replaced the flat array and its `strcmp`
against every entry with an open-addressed hash set. The comment on the function
records why a symbol lookup is hot at all: the code generator emits a call for
every *evaluation* of a quoted symbol literal, so the table is walked from inner
loops that never mention symbols in the source.

| member | baseline | terms 1+2 | + term 3 |
|---|---|---|---|
| `code-small` | 1.01 | 0.24 | 0.16 |
| `code-medium` | 4.80 | 1.55 | 1.20 |
| `code-large` | 17.15 | 7.88 | 6.53 |
| `data-large` | 36.04 | 56.53 | 30.43 |

`data-large`'s regression is gone, and it is now below its baseline.

### 3.4 Term 4: `string-set!` reallocated the whole string

`rt_string_set` located the codepoint by scanning from byte 0, then built an
entirely new byte buffer and copied prefix, replacement and suffix into it — on
every call, including the ASCII-for-ASCII case where the replacement is one byte
wide and the old one is too. Filling an n-character buffer a character at a time
was therefore O(n²) in time and in allocation, and `(pitch layout)`'s
`concatenate` — which assembles the entire formatted output that way — was the
program's single hottest procedure after interning was fixed.

Two changes, both in `rt_string_set`: find the codepoint the way `string-ref`
already does (byte index when the string is all-ASCII, breadcrumb index
otherwise), and when the replacement encodes to the same width, write it in
place. Every string's bytes are uniquely owned — `rt_make_string` is the only
other place a buffer pointer is installed, and it copies — so in-place is safe,
and a literal is a fresh copy like any other.

| member | terms 1–3 | + term 4 |
|---|---|---|
| `code-small` | 0.16 | 0.13 |
| `code-medium` | 1.20 | 0.69 |
| `code-large` | 6.53 | 2.48 |
| `data-large` | 30.43 | 19.86 |

### 3.4 Term 5: string output ports were never closed

With the first four gone, 86% of `data-large`'s remaining samples were in libc's
`__sfp`, reached from `open-output-string` → `open_memstream` → `funopen`.
`__sfp` walks libc's list of `FILE` objects looking for a free slot, and a stream
that is never closed is never a free slot. Isolated, opening N string ports and
taking their text:

| ports | left open | closed |
|---|---|---|
| 20,000 | 0.68 | 0.49 |
| 40,000 | 1.19 | 0.50 |
| 80,000 | 7.09 | 0.52 |

Quadratic against flat. The reader allocates a string port per accumulated token
and pitch's `cst->text` allocates one per safety check, and neither closed it.
Both now do: the port is created locally, cannot escape, and its text has already
been taken, so closing it is ordinary hygiene that happens to be the difference
between linear and quadratic. The fix is in `tools/generate-reader.sps` — the
R6RS→R7RS shim for `call-with-string-output-port`, not the derived reader, so the
`vendor-diff` against laesare is untouched — and in `src/pitch/cst.sld`.

| member | terms 1–4 | + term 5 |
|---|---|---|
| `code-small` | 0.13 | 0.14 |
| `code-medium` | 0.69 | 0.71 |
| `code-large` | 2.48 | 2.16 |
| `data-large` | 19.86 | **2.28** |

## 4. Verification that nothing else moved

- **Output is byte identical.** The whole corpus formatted by a build from
  before any of the five terms and by the build after all of them, at widths 40,
  60, 80, 100 and 120 — 20 comparisons — identical bytes and identical exit
  status in every one.
- **`make oracle-layout`**: 82 entries, all agreeing on text, cost and taint. The
  objective and the computation width are untouched.
- **Every pitch suite passes**: 21 programs, 0 failures, including
  `test-print-r7rs` (234), `test-cli-r7rs` (207), `test-format-r7rs` (204),
  `test-cst-r7rs` (184), `test-recording-r7rs` (142), `test-check-r7rs` (115),
  `test-doc-r7rs` (118), and `tests/test-text-files.sh` (9).
- **Every Emit suite passes.** `./run-all-tests.sh`: 38 suites, 0 failed, 675 s.
  `./run-dev-tests.sh`: 22 suites, 0 failed, 851 s — including the anti-stale
  trust-check, which confirms the runtime change needs no regeneration because
  `runtime.c` is not compiler source.
- **`make reader-check`** clean and **`make vendor-verify`** clean: the derived
  reader matches its generator, and `vendor/laesare/` is unmodified.
- **`make self-check`** clean.
- **Idempotence** holds on all four corpus members.
- **Both output checks still run on every file.** `check.sld` and `format.sld`
  are untouched. No refusal was relaxed and no verification became conditional.
- **Peak memory fell**, so nothing here traded space for time:

| member | before | after |
|---|---|---|
| `code-small` | 44.6 MiB | 39.4 MiB |
| `code-medium` | 179.5 MiB | 142.2 MiB |
| `code-large` | 410.5 MiB | 334.8 MiB |
| `data-large` | 686.1 MiB | 388.2 MiB |

**`make test` passes in full**, exit 0, as one command: both audits,
`reader-check`, all 21 Emit test programs, the three Chez-hosted reader suites,
reader parity, the datum oracle ("serialized outputs agree"), real-host,
door-parity across its ten cases, no-chez, install, `self-check` and
`vendor-verify`. (An earlier note here said it could not be run end to end
because `rg` was missing; `rg` was installed and it does.)

## 5. Acceptance

### 5.1 / 5.2 The two ratios

```
member           lines    seconds    s/1000lines    peakMiB
code-small         254       0.12           0.47       30.5
code-medium        995       0.61           0.61      107.7
code-large        2724       2.01           0.74      283.6
data-large        2486       2.18           0.88      359.8

shape ratio  data-large / code-large   1.19  (bound 1.50)  ok
size ratio   code-large / code-small   1.56  (bound 1.50)  OVER
```

**The shape requirement is met, with room: 1.19 against a bound of 1.50 and a
baseline of 2.30.** That is the requirement this change was really about — the
per-form superlinearity `char-data.scm` exposed — and it is gone.

**The size requirement is not reliably met.** On an idle machine, best of five,
three consecutive runs reported 1.51, 1.45 and 1.56. It straddles the bound. The
baseline was 1.58, so on this ratio alone the change has moved almost nothing —
even while absolute cost fell by 7–9×.

That is not noise hiding a pass, and it is worth being precise about why.

**The residual is the garbage collector.** Boehm's mark cost is proportional to
the live heap, and the live heap grows with the document. Forcing a heap large
enough that collection barely runs:

| | `code-small` | `code-large` | ratio |
|---|---|---|---|
| default | 0.47 s/1000 | 0.72 s/1000 | **1.53** |
| `GC_INITIAL_HEAP_SIZE=1e9` | 0.39 s/1000 | 0.48 s/1000 | **1.23** |

With the collector out of the way the ratio is comfortably inside the bound. What
is left is not an algorithm that scales badly; it is that a bigger document keeps
more alive, and keeping more alive costs collector time in proportion.

**One attempt was made to shrink it, and it did not move the ratio.** §6 names
"every internal node is memoized rather than every seventh" as the first thing to
revisit if a corpus run is slow, so the memo was made cheaper per node: a node's
entries are now an alist rather than a hash table, since almost every node holds
two or three of them and a hash table per node costs a record, a spine and an
eight-slot bucket vector to hold them. Peak memory fell 15–34% and every member
got slightly faster —

| member | before | after | peak before | peak after |
|---|---|---|---|---|
| `code-small` | 0.13 s | 0.12 s | 39.4 MiB | 30.5 MiB |
| `code-medium` | 0.71 s | 0.61 s | 142.2 MiB | 107.7 MiB |
| `code-large` | 2.15 s | 2.01 s | 334.6 MiB | 283.6 MiB |
| `data-large` | 2.37 s | 2.18 s | 388.2 MiB | 359.8 MiB |

— but the ratio did not improve, because the small member benefits in the same
proportion. The change is kept on its own merits (less memory, slightly faster,
and a simpler structure than a table of tables), not as a fix for this ratio.
Output is byte identical and `make oracle-layout` agrees, so it is answer-
preserving as design decision 4 requires of a granularity change; no delta
against `layout-resolution` is needed, since memo *scope* is untouched.

**Two ways to close it, neither taken here.** Reduce allocation further so the
collector has less to mark — the real fix, and open-ended. Or accept that a
254-line, 0.12-second member is too small to be the denominator of a gate: a
20 ms disturbance moves the ratio by 0.2, and the requirement was written to
catch a 3× effect, not to discriminate 1.45 from 1.55. Changing the bound or the
corpus is a specification change and belongs in a proposal, not in this one.

### 5.3 Issue #15's own measurement, re-run

Emit's eight named files, `--check`, one invocation per file, on this host. The
"before" column is a build of pitch from before any of the five terms, on the
same machine on the same day, so the comparison is like-for-like rather than
against the seconds in the issue, which were taken on a different day.

| file | lines | before | after | | s/1000 after |
|---|---|---|---|---|---|
| `src/dump.ss` | 199 | 1.4 s | 0.20 s | 7.2× | 1.01 |
| `src/passes/expand.ss` | 685 | 14.6 s | 2.02 s | 7.2× | 2.95 |
| `src/parse.ss` | 985 | 16.4 s | 1.99 s | 8.2× | 2.02 |
| `src/repl-core.ss` | 1422 | 23.8 s | 2.74 s | 8.7× | 1.93 |
| `src/core.ss` | 1546 | 37.2 s | 4.25 s | 8.7× | 2.75 |
| `src/emit.ss` | 1837 | 56.7 s | 6.15 s | 9.2× | 3.35 |
| `src/prelude.scm` | 2477 | 83.0 s | 8.78 s | 9.5× | 3.54 |
| `lib/scheme/char-data.scm` | 2397 | 84.2 s | **2.58 s** | **32.6×** | **1.08** |

Two things to read here, and it is worth separating them.

**The data-dense outlier is gone.** `char-data.scm` was the most expensive file
per line in the issue's table — 80 s/1000 against 42 for code of the same size —
and it is now the *cheapest*. That is the shape defect, and it is fixed.

**Per-line cost still varies about 3.5× across Emit's hand-written files**, from
1.01 to 3.54 s/1000. That is not the size term. Those eight files differ in
content as well as in length, and the controlled corpus — where composition is
held fixed and only size varies — reports 1.44. The requirement is about size,
which is why the corpus is built to vary only that. What is left here is that
some code is denser than other code, which no requirement in this change forbids.

Where this differs from the issue: same files, same flag, same
one-invocation-per-file method, different day — and, importantly, the `before`
column is a build of HEAD from immediately before this change rather than the
0.1.0 build the issue measured. Over these eight files that baseline already
totals 317 s against the reported 508 s, so it carries a 1.6× head start earned
by the Emit port and `fill-quoted-data-lists`. The speedups in the table are
therefore this change's alone, and the improvement over the seconds originally
reported is larger.

### Two conditional tasks whose conditions did not fire

**Task 3.2 — a delta against `layout-resolution`'s per-call memoization.** Not
needed and not written: no fix touched memoization scope or granularity. The
profile refuted that candidate before any code moved, which is the order the task
list exists to enforce. `layout-resolution` is unchanged, and no capability in
`openspec/specs/` is modified by this change.

**Task 3.5 — stop if the profile is inconclusive.** It was conclusive: five terms
named, each measured on its own, each with a controlled experiment separating it
from the others. The stopping rule was not reached.

### 5.4 The whole-tree aggregate

Emit's `src/*.ss`, `src/*.scm`, `src/passes/*.ss`, `lib/scheme/*.sld` and
`lib/emit/*.sld` — 32 files, 12,850 lines. Issue #15 reported 442 s sequential
and about 150 s at `-P4` over a 32-file, 13,229-line set; the repository has
changed by a few hundred lines since, so this is the same shape of set rather
than provably the same files.

| | before | after | |
|---|---|---|---|
| sequential, one invocation per file | 480.5 s | 78.3 s | 6.1× |
| `xargs -P4` | 146.3 s | 31.5 s | 4.6× |

**The closeness of 480 s to the reported 442 s is a coincidence, not a
validation.** Over the eight files of §5.3 the pre-change binary totals 317 s
against the 508 s reported in the issue: it is already 1.6× faster than the 0.1.0
build measured there, because the Emit port and `fill-quoted-data-lists` landed
in between. The aggregate lands near the reported figure anyway because the file
set is not the same one — the exact 13,229-line set could not be reconstructed,
and the substitute leans on denser files, which cancels the head start. The
honest comparison is 480 s → 78 s within this change; the improvement over what
the issue originally reported is larger than that.

### 5.5 The three uses the issue says are shaped by this number

- **A pre-commit hook over a tree: yes.** 78 s sequential and 32 s at `-P4` over
  12,850 lines. A hook checks *staged* files, and the case the issue called out —
  staging `src/prelude.scm` — went from 83 s to 8.8 s.
- **`pitch --check` over a directory as a local gate: yes, with a caveat.** 32 s
  at `-P4` is something a person waits through; 442 s was a CI job. It is not
  instant.
- **Editor-on-save: yes for ordinary files, no for the largest.** 0.20 s at 200
  lines and about 2 s at 1,000. A 1,500-line file is around 4 s and a 2,500-line
  file 8.8 s, which is still not save-time.

The honest summary of that last one: it is no longer a *scaling* defect. Per-line
cost is flat across the graded corpus and the data-dense outlier is gone, so what
remains between a 2,500-line file and an editor is a constant factor, and
constant factors are a different kind of work from the one this change did.
