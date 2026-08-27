## MODIFIED Requirements

### Requirement: A CST projects to host Scheme data

The system SHALL provide an operation projecting a CST to ordinary values of the
host: pairs, vectors, bytevectors, symbols, strings, characters, representable
numbers, booleans, and the empty list. A valid numeric datum outside the host's
numeric tower SHALL project to the opaque Pitch numeric value carried by its
token, so the projection remains total over every valid R6RS and R7RS number.

The operation SHALL return two values: the top-level data in source order, and a
list of diagnostics.

It MUST NOT introduce a representation of its own for any datum that the host
already has a type for. The opaque numeric value SHALL be private, distinguishable
from every datum source text can construct, and used only where the host has no
corresponding number.

#### Scenario: A list projects to a pair chain

- **WHEN** the source `(a b c)` is projected
- **THEN** the result is a list of the symbols `a`, `b`, and `c`

#### Scenario: Each datum kind projects to its host type

- **WHEN** a source containing a list, a vector, a bytevector, a symbol, a
  string, a character, a representable number, a boolean, and `()` is projected
- **THEN** each is a value of the corresponding host type

#### Scenario: An unrepresentable number projects without a diagnostic

- **WHEN** a valid numeric datum is outside the host's numeric tower
- **THEN** it projects to an opaque Pitch numeric value
- **AND** the projection diagnostics are empty

#### Scenario: Several top-level data are returned in order

- **WHEN** the source `(a) (b)` is projected
- **THEN** two data are returned, the first for `(a)` and the second for `(b)`
