## MODIFIED Requirements

### Requirement: Data are compared by a named equivalence

The system SHALL provide a datum equivalence operation used by the layer 2
check, so that tests and future callers name one operation rather than reaching
for a host primitive directly.

The operation SHALL terminate on cyclic arguments. Two opaque Pitch numeric
values SHALL compare equal when they came from the same valid numeric lexeme.
Opaque numeric values SHALL compare unequal to every ordinary host datum.

#### Scenario: Structurally equal data compare equal

- **WHEN** the data projected from `(a (b c))` and from `(a (b c))` are compared
- **THEN** they compare equal

#### Scenario: Data differing in one element compare unequal

- **WHEN** the data projected from `(a b)` and from `(a c)` are compared
- **THEN** they compare unequal

#### Scenario: Equal cyclic data compare equal and terminate

- **WHEN** the data projected from `#0=(a . #0#)` and from `#0=(a . #0#)` are
  compared
- **THEN** they compare equal
- **AND** the comparison terminates

#### Scenario: Unequal cyclic data compare unequal and terminate

- **WHEN** the data projected from `#0=(a . #0#)` and from `#0=(b . #0#)` are
  compared
- **THEN** they compare unequal
- **AND** the comparison terminates

#### Scenario: Equal opaque numeric values compare equal

- **WHEN** two texts containing the same valid host-unrepresentable number are independently read and projected
- **THEN** their opaque numeric values compare equal

#### Scenario: Exactness is significant

- **WHEN** the data projected from `1` and from `1.0` are compared
- **THEN** they compare unequal

### Requirement: Layer 2 states its own weakness

The check SHALL be documented as strictly weaker than token equivalence, and its
value SHALL be stated as independence from that check rather than strength.

The following MUST be understood to pass datum equivalence, so that no consumer
mistakes it for a sufficient safety check on its own: a deleted comment, a
moved `#;` datum comment, a bracket rewritten from `[` to `(`, an abbreviation
expanded to its long form, a representable number rewritten in another radix,
and a string escape respelled.

Two different spellings of a host-unrepresentable number MAY compare unequal at
layer 2 because its opaque value retains the lexeme rather than implementing a
second arbitrary-precision numeric tower. Layer 1 compares the exact numeric
token text first and therefore continues to reject every numeric respelling.

#### Scenario: Deleting a comment passes datum equivalence

- **WHEN** `(a ; note\n b)` and `(a b)` are checked
- **THEN** the check reports equivalence, despite the comment having been lost

#### Scenario: Flipping bracket shape passes datum equivalence

- **WHEN** `[a b]` and `(a b)` are checked
- **THEN** the check reports equivalence

#### Scenario: Expanding an abbreviation passes datum equivalence

- **WHEN** `'x` and `(quote x)` are checked
- **THEN** the check reports equivalence

#### Scenario: Respelling a number passes datum equivalence

- **WHEN** `#xff` and `255` are checked
- **THEN** the check reports equivalence

#### Scenario: Layer 1 still rejects an opaque number respelling

- **WHEN** two valid host-unrepresentable numeric tokens denote the same value with different spellings
- **THEN** token equivalence reports non-equivalence
