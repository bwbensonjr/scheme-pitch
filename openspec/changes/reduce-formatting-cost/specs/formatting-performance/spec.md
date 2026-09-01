## Purpose

What pitch guarantees about how long formatting takes as a function of input size
and input shape, and the benchmark that measures it. Distinct from `layout-cost`,
which is the objective the engine minimizes: that is what the output looks like,
this is what it costs to get there. The guarantee is expressed as a scaling shape
rather than in seconds, because seconds depend on the host and the Scheme
implementation while the shape does not.

## ADDED Requirements

### Requirement: A size-graded benchmark is part of the repository

The system SHALL provide a benchmark over a fixed, checked-in corpus, invoked by
a named build target, reporting for each member: its line count, the wall time to
format it, and its cost per thousand lines.

The corpus SHALL span at least an order of magnitude in size, from a member of
roughly 200 lines to a member of at least 2,000, and SHALL include at least one
data-dense member — a small number of very large data forms — alongside
hand-written code of comparable size.

The corpus SHALL be fixed and checked in. A benchmark over whatever files happen
to be present measures a different thing on every machine and cannot be compared
across runs.

The benchmark SHALL report the derived ratios the requirements below are stated
in terms of, so that a reader is not left to compute them, and SHALL report
enough about the host and implementation to make a number attributable.

The benchmark SHALL NOT be part of the correctness suite. Timings vary with load,
and a flaky timing in a correctness suite trains people to ignore failures.

#### Scenario: The benchmark runs from a clean checkout

- **WHEN** the benchmark target is invoked in a clean checkout
- **THEN** it formats every corpus member and reports each member's line count,
  wall time, and cost per thousand lines

#### Scenario: The corpus spans an order of magnitude

- **WHEN** the corpus is inspected
- **THEN** its smallest member is roughly 200 lines and its largest at least
  2,000
- **AND** it contains at least one data-dense member and one hand-written code
  member of comparable size

#### Scenario: The ratios are reported, not left to be computed

- **WHEN** the benchmark completes
- **THEN** it reports the ratio of the largest member's per-line cost to the
  smallest's, and the ratio of the data-dense member's per-line cost to that of
  code of comparable size

#### Scenario: The correctness suite does not run the benchmark

- **WHEN** the correctness suite is run
- **THEN** no benchmark timing is measured and no timing can fail it

### Requirement: Per-line cost does not grow materially with file size

Formatting cost SHALL be near-linear in input size. Over the graded corpus, the
per-line cost of the largest member SHALL NOT exceed 1.5 times the per-line cost
of the smallest.

The measured baseline this replaces is a factor of about 3 for hand-written code
between 199 and 2,477 lines, and about 5 including the data-dense member.

The bound is stated as a ratio rather than in seconds deliberately: it is the
property that determines whether a whole-tree check is an editor-sized or a
suite-sized operation, and unlike a wall-clock target it means the same thing on
every host.

#### Scenario: Per-line cost is flat across the corpus

- **WHEN** the benchmark runs over the graded corpus
- **THEN** the largest member's cost per thousand lines is no more than 1.5 times
  the smallest member's

#### Scenario: The bound holds at each intermediate size

- **WHEN** the corpus members are ordered by line count
- **THEN** no member's cost per thousand lines exceeds 1.5 times the smallest
  member's

### Requirement: A large data form costs no more per line than small forms

Cost SHALL be near-linear in the *shape* of the input as well as its size. The
data-dense corpus member's cost per thousand lines SHALL NOT exceed 1.5 times
that of hand-written code of comparable size.

A few enormous forms costing markedly more per line than many small ones is the
signature of a per-form superlinearity, and it is the specific defect this
requirement exists to keep out. The measured baseline is a factor of about 1.9 —
80 s per 1000 lines against 42.

#### Scenario: A generated table costs like code of the same size

- **WHEN** the benchmark runs
- **THEN** the data-dense member's cost per thousand lines is no more than 1.5
  times that of the hand-written member of comparable size

#### Scenario: One very large form does not dominate

- **WHEN** a source consisting of a single form of N elements is formatted, for
  N and for 4N
- **THEN** the cost of the second is no more than roughly four times the cost of
  the first

### Requirement: Performance work does not change output or weaken a check

A change made for performance SHALL leave output byte-identical over the whole
corpus at every page width the suite exercises, and SHALL leave both output
checks running over text re-read from the formatter's output.

Neither the cost objective nor the computation width SHALL be altered to reduce
formatting time. A formatter that resolves a different layout is a different
formatter, and the differential oracle requires both sides to minimize the same
objective.

No refusal SHALL be relaxed and no verification SHALL be skipped, conditionally
or otherwise, to reduce cost. Verification cost is deliberate.

#### Scenario: Output is unchanged before and after

- **WHEN** the corpus is formatted by the build from before a performance change
  and by the build after it, at each page width the suite exercises
- **THEN** the outputs are byte identical

#### Scenario: The objective is untouched

- **WHEN** the differential layout oracle runs after a performance change
- **THEN** every entry agrees on text, cost and taint

#### Scenario: Verification still runs on every file

- **WHEN** a file is formatted after a performance change
- **THEN** both output checks run against text re-read from the produced output
