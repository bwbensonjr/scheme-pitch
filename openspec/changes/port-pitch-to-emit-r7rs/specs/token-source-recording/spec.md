## MODIFIED Requirements

### Requirement: Tokens carry their exact source text

The reader SHALL return, for each token, a token value exposing the token kind,
the exact source substring consumed to produce it, the absolute character offsets
of the start and end of that substring, the line and column of both ends of that
substring, and the parsed value that the lexer computed.

The raw text MUST be the verbatim source substring, preserving the original
spelling in every respect: radix and exponent notation, escape sequences,
character-name spelling, boolean spelling, identifier bars and inline hex
escapes, and internal whitespace.

Where a numeric lexeme is valid R6RS or R7RS syntax but the host cannot represent
its value, the token's parsed value SHALL be an opaque Pitch numeric value rather
than a symbol, a guessed number, or a diagnostic. The opaque value SHALL retain
the numeric lexeme needed to compare a fresh read of the same source, but SHALL
NOT be exposed as a host number. A numeric value the host can represent SHALL
continue to use the corresponding host number.

#### Scenario: Token exposes both raw text and parsed value

- **WHEN** the reader reads the source `#xff`
- **THEN** the token's raw text is the string `#xff`
- **AND** the token's parsed value is the number `255`
- **AND** the token's start and end offsets delimit exactly those four characters

#### Scenario: Valid unrepresentable number remains numeric

- **WHEN** the reader on a bounded host reads a valid exact integer larger than the host's range
- **THEN** the token retains its exact source text and span
- **AND** its parsed value is an opaque Pitch numeric value
- **AND** no invalid-syntax diagnostic is produced

#### Scenario: Invalid numeric syntax is still refused

- **WHEN** the reader encounters text that begins as a number but is not valid R6RS or R7RS numeric syntax
- **THEN** it reports invalid numeric syntax rather than constructing an opaque numeric value

#### Scenario: Offsets delimit the raw text

- **WHEN** any token is read from a source string
- **THEN** the substring of the source between the token's start and end offsets
  is equal to the token's raw text
