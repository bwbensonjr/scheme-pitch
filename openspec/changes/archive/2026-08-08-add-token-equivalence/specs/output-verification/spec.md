## ADDED Requirements

### Requirement: A combined check runs the text-comparing layers over one pair of texts

The system SHALL provide a single operation accepting two source texts and
running the checks that compare two texts — token equivalence and datum
equivalence — reporting whether the pair passed.

The operation SHALL report which layer failed, so a caller need not re-run the
individual checks to find out.

#### Scenario: A layout-only difference passes every layer

- **WHEN** `(define (f x)\n  (g x))` and `(define (f x) (g x))` are checked
- **THEN** the combined check reports success
- **AND** no layer is reported as having failed

#### Scenario: A difference only token equivalence sees

- **WHEN** `(a ; note\n b)` and `(a b)` are checked
- **THEN** the combined check reports failure
- **AND** the layer reported is token equivalence

#### Scenario: A difference both layers see

- **WHEN** `(a b)` and `(a c)` are checked
- **THEN** the combined check reports failure

### Requirement: Token equivalence runs first

The combined check SHALL run token equivalence before datum equivalence.

Token equivalence is strictly stronger and reports where it failed, so when both
would fail, the layer reported MUST be token equivalence.

#### Scenario: The stronger layer is blamed when both fail

- **WHEN** two texts differing in a datum, such as `(a b)` and `(a c)`, are
  checked
- **THEN** the layer reported is token equivalence, not datum equivalence

#### Scenario: Detail from the failing layer is available

- **WHEN** the combined check fails at token equivalence
- **THEN** the first differing position is available to the caller

### Requirement: An unusable text fails before any layer runs

If either text produces a diagnostic when tokenized, parsed, or projected, the
combined check SHALL report failure without attributing it to a layer, and SHALL
make the diagnostics available.

#### Scenario: A malformed text is not blamed on a layer

- **WHEN** `(a (b` and `(a (b` are checked
- **THEN** the combined check reports failure
- **AND** the diagnostics are available
- **AND** no layer is reported as having failed, because none was reached

### Requirement: The combined check is not yet the whole verification pipeline

The operation SHALL be documented as covering only the layers that compare two
texts.

Round-trip and idempotence are outside it: round-trip compares a tree against
the input it was parsed from rather than comparing two texts, and idempotence
requires running the formatter more than once. Both join the pipeline with the
formatter, and this operation is expected to be revised then.

#### Scenario: The operation states what it does not cover

- **WHEN** the combined check is consulted for a complete verification of a
  formatting run
- **THEN** its documentation states that round-trip and idempotence are not
  included
