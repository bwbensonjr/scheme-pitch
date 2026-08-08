# layout-cost Specification

## Purpose

The objective the layout engine minimizes, and the seam at which style opinions
are substituted. A cost factory is five operations - a total order on costs, a
combine, the cost of text of a given length at a given column, the cost of a
newline at a given indentation, and the computation width - over a cost
representation the engine never inspects directly. Three algebraic laws are the
caller's obligation and the optimality guarantee is conditional on them. The
default factory minimizes squared overflow past the page width and then line
count; it is the reference implementation's objective, kept so that the
differential oracle compares like with like, and is explicitly not pitch's
aesthetic.
## Requirements

### Requirement: The resolver is parameterized over a cost factory

The system SHALL provide a cost factory type with exactly five components:

| Component | Signature | Meaning |
|---|---|---|
| `cost<=?` | cost, cost → boolean | a total order on costs |
| `cost+` | cost, cost → cost | combine two costs |
| `cost-text` | column, length → cost | cost of text of that length starting at that column |
| `cost-nl` | indentation → cost | cost of a line break followed by that indentation |
| `limit` | natural | the computation width |

A cost is any value the factory's own operations accept. The resolver SHALL NOT
inspect a cost by any means other than these operations.

The factory SHALL live in a library that does not import the resolver, so that a
caller can build one without depending on the layout algorithm.

#### Scenario: A factory is built from five components

- **WHEN** a cost factory is constructed from an order, a combine, a text cost, a
  newline cost, and a limit
- **THEN** each is retrievable from it

#### Scenario: The resolver uses only the factory's operations

- **WHEN** a factory whose costs are values of a caller-defined type is supplied
- **THEN** layout succeeds without the resolver inspecting those values directly

### Requirement: The cost algebra's laws

A cost factory supplied by a caller MUST satisfy the following, and the
optimality guarantee in `layout-resolution` holds only when it does:

- `cost<=?` is a total preorder: reflexive, transitive, and total.
- `cost+` is associative and commutative.
- `cost+` is monotone with respect to `cost<=?`: if `a` is no greater than `b`,
  then `a + c` is no greater than `b + c`.

These are obligations on the caller. The system MAY leave them unchecked, since
checking them requires quantifying over all costs, but they SHALL be documented
at the interface.

#### Scenario: The default factory satisfies the laws

- **WHEN** the default factory's operations are exercised over a range of costs
- **THEN** the order is reflexive, transitive and total, and the combine is
  associative, commutative and monotone

#### Scenario: A caller factory violating monotonicity is not the engine's fault

- **WHEN** a factory whose combine is not monotone is supplied
- **THEN** the engine still returns a layout
- **AND** that layout is not guaranteed to be cost-minimal

### Requirement: The default cost factory minimizes squared overflow, then height

The system SHALL provide a default cost factory parameterized by a page width and
optionally a computation width.

Its cost SHALL be a pair of a badness and a height, compared lexicographically:
lower badness wins, and height breaks ties.

- `cost-nl` SHALL be badness 0 and height 1, for every indentation.
- `cost-text` at column `pos` with length `len`, against page width `w`, SHALL be
  badness 0 when `pos + len` does not exceed `w`. Otherwise, with
  `a = max(w, pos) - w` and `b = (pos + len) - max(w, pos)`, it SHALL be badness
  `b * (2a + b)` and height 0.
- `cost+` SHALL add both components.

That badness expression is the increment in squared overflow contributed by the
text: the total badness of a layout is the sum over its lines of the square of
the amount by which each line exceeds the page width. Squaring is what makes one
badly overflowing line worse than several slightly overflowing ones.

When no computation width is supplied, `limit` SHALL be the floor of the page
width multiplied by 1.2.

#### Scenario: Text within the page width is free

- **WHEN** text of length 5 starting at column 10 is priced against a page width
  of 80
- **THEN** its cost is badness 0, height 0

#### Scenario: Overflow from within the page width is squared

- **WHEN** text of length 10 starting at column 75 is priced against a page width
  of 80
- **THEN** its badness is 25, the square of the 5 columns of overflow

#### Scenario: Overflow beyond an already overflowing column is incremental

- **WHEN** text starting at column 85 is priced against a page width of 80, and
  the text ending at that column was already priced
- **THEN** the sum of the two badnesses equals the square of the total overflow
  of the line

#### Scenario: Badness dominates height

- **WHEN** a layout with badness 1 and height 2 is compared with one of badness 2
  and height 1
- **THEN** the first is preferred

#### Scenario: Height breaks ties

- **WHEN** two layouts have equal badness
- **THEN** the one with fewer line breaks is preferred

#### Scenario: The default computation width follows the page width

- **WHEN** a default factory is built with a page width of 80 and no computation
  width
- **THEN** its limit is 96

#### Scenario: An explicit computation width is used as given

- **WHEN** a default factory is built with an explicit computation width
- **THEN** its limit is that value

### Requirement: The default factory is not pitch's aesthetic

The default factory SHALL be the one the reference implementation specifies, so
that the differential oracle in `layout-resolution` compares like with like.

It MUST NOT be treated as pitch's style objective. The objective encoding pitch's
preferences is defined by a later change, against real Scheme documents.

#### Scenario: The oracle uses the default factory

- **WHEN** the differential comparison against the reference implementation runs
- **THEN** both sides use the default factory with the same page width and
  computation width
