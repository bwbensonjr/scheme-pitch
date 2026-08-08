## ADDED Requirements

### Requirement: Layout is a pure function of document, factory and offset

The system SHALL provide a layout operation taking a document, a cost factory,
and a starting column offset, and returning the rendered text together with the
cost of that layout and whether it is tainted.

The offset SHALL default to zero when not supplied. Optional arguments SHALL be
expressed as arities rather than as dynamically scoped parameters, so that no
result depends on state outside the call.

The operation SHALL perform no input or output. It returns a string; a caller
that wants a port writes the string to one.

#### Scenario: The same arguments give the same result

- **WHEN** a document is laid out twice with the same factory and offset
- **THEN** the text, cost and taint flag are identical

#### Scenario: The offset shifts the starting column

- **WHEN** a document is laid out with an offset of 4
- **THEN** its first line is priced and broken as if it began at column 4
- **AND** no leading spaces are emitted for the offset

#### Scenario: No result depends on ambient state

- **WHEN** two layouts are performed with different page widths
- **THEN** neither affects the other

### Requirement: The layout returned is cost-minimal

For a document that has at least one layout, and a cost factory satisfying the
laws in `layout-cost`, the returned layout SHALL be one of minimum cost among all
layouts the document denotes.

This is what distinguishes the engine from a greedy printer: a choice is never
resolved by whether its flat form fits locally, but by the cost of the whole
document under each resolution.

#### Scenario: A choice is resolved by total cost, not local fit

- **WHEN** a document offers a flat alternative that fits on its own but forces
  overflow later, and a broken alternative that does not
- **THEN** the broken alternative is chosen

#### Scenario: The reported cost is the cost of the returned layout

- **WHEN** a document is laid out
- **THEN** the reported cost equals the factory's cost of the text returned

#### Scenario: The paper's worked examples are reproduced

- **WHEN** the examples from the reference implementation's documentation are
  laid out at their stated page widths
- **THEN** the output matches the published output for each

### Requirement: A document with no layout raises

When a document denotes no layout, the operation SHALL raise a condition
identifying the failure.

It MUST NOT return a best-effort rendering. There is no principled choice among
no candidates, and emitting one would be a repair of the kind pitch refuses
elsewhere.

#### Scenario: A failing document raises

- **WHEN** `fail` is laid out
- **THEN** a condition is raised

#### Scenario: An unsatisfiable full raises

- **WHEN** `(concat (full (text "a")) (text "b"))` is laid out
- **THEN** a condition is raised

#### Scenario: A failure is distinguishable from a taint

- **WHEN** a document with no layout is laid out, and separately a document all
  of whose layouts overflow
- **THEN** the first raises and the second returns a tainted layout

### Requirement: Overflow past the computation width taints rather than fails

When resolution passes the computation width, the resolver SHALL stop maintaining
a frontier of candidates and produce a single fallback layout, and SHALL report
the result as tainted.

A tainted layout SHALL be complete and valid text. What is withdrawn is the
minimality guarantee, not the output.

The taint flag SHALL be returned to the caller alongside the cost, so that a
caller can distinguish "this is the best layout" from "the search gave up here".

#### Scenario: An unavoidably long line still renders

- **WHEN** a document containing a single text longer than the computation width
  is laid out
- **THEN** the full text is returned
- **AND** the result is reported as tainted

#### Scenario: A layout within the computation width is not tainted

- **WHEN** a document whose optimal layout stays within the computation width is
  laid out
- **THEN** the result is not tainted

#### Scenario: Taint is reported, not raised

- **WHEN** a tainted layout is produced
- **THEN** no condition is raised

### Requirement: Resolution terminates on every document

The operation SHALL terminate for every document and every cost factory with a
finite limit. It MUST NOT diverge, and MUST NOT enumerate all layouts.

Termination follows from the frontier being pruned to a Pareto-optimal set below
the computation width and from the tainted fallback above it, together bounding
the number of candidates carried at any point.

#### Scenario: A deeply nested choice terminates

- **WHEN** a document built from many nested groups is laid out
- **THEN** the operation returns

#### Scenario: A shared document is not re-resolved exponentially

- **WHEN** a document in which one sub-document is reachable by many paths is
  laid out
- **THEN** the operation returns in time consistent with resolving that
  sub-document a bounded number of times per position

### Requirement: Memoization is per call and does not outlive it

Memoized resolution results SHALL be scoped to a single layout call and SHALL NOT
be stored on document values.

A measure is valid only for the cost factory that produced it, so a table
surviving a call would let a layout computed under one factory be returned under
another. That would produce a plausible but wrong layout, which no downstream
safety check can detect.

#### Scenario: A document laid out under two factories gives two answers

- **WHEN** the same document is laid out with two factories whose page widths
  differ
- **THEN** each result reflects its own factory

#### Scenario: Order of calls does not matter

- **WHEN** the same pair of layout calls is performed in either order
- **THEN** each call's result is the same in both orderings

### Requirement: The port is differentially tested against the reference implementation

The engine SHALL be differentially tested against the Racket `pretty-expressive`
implementation over a corpus of documents. For each corpus entry, the rendered
text, the reported cost, and the taint flag SHALL agree.

Both sides SHALL be driven from a single corpus file describing the documents and
their page width, computation width, and offset, so that a case added on one side
cannot be missing on the other.

The corpus SHALL include: each core constructor in isolation; `full` in both
satisfiable and unsatisfiable positions; documents whose layouts overflow, so
taint is compared and not only text; documents with heavy structural sharing, so
memoization is exercised; and non-zero offsets. It SHALL exclude the reference's
`special` construct, which is not ported.

The comparison SHALL run as its own target and MUST NOT be part of the default
test target, which runs without Racket. When Racket or the reference package is
absent, the target SHALL report how to obtain it and skip, rather than fail.

#### Scenario: Both implementations agree on the corpus

- **WHEN** the corpus is rendered by both implementations with matching
  parameters
- **THEN** the text, cost and taint flag agree for every entry

#### Scenario: One corpus drives both sides

- **WHEN** an entry is added to the corpus file
- **THEN** both implementations render it without any other edit

### Requirement: The oracle proves how much it compared

Each driver SHALL refuse a corpus file containing anything after its single list
of entries, and SHALL report the number of entries it ran.

A malformed corpus is not a hypothetical. A stray closing parenthesis ends the
entry list early; both drivers then skip the same trailing entries, the diff
still passes, and the oracle silently attests to less than the file contains. An
oracle that agrees about nothing agrees. The count makes coverage visible in the
compared output itself, so a shrinking corpus shows up as a difference rather
than as continued success.

#### Scenario: Data after the entry list is refused

- **WHEN** a driver reads a corpus file with a datum following the entry list
- **THEN** it reports an error and does not render any entry

#### Scenario: The entry count is part of the compared output

- **WHEN** both drivers run
- **THEN** each reports how many entries it read
- **AND** that count is compared along with the entries

#### Scenario: The oracle skips when Racket is unavailable

- **WHEN** the target is run without Racket or without the reference package
  installed
- **THEN** it reports how to install what is missing and exits successfully

#### Scenario: The default test target does not require Racket

- **WHEN** the default test target is run on a machine without Racket
- **THEN** it passes

### Requirement: The oracle is evidence, not coverage

A passing differential run SHALL NOT be treated as full coverage. It covers only
the corpus, and only behavior both implementations share.

Behavior the port defines and the reference does not — the refusal of a line
ending inside `text`, and the raised condition for a document with no layout —
SHALL be asserted directly by written expectations.

#### Scenario: Port-specific behavior is tested directly

- **WHEN** behavior that the reference implementation does not exhibit is tested
- **THEN** its expected result is asserted directly rather than against the
  oracle
