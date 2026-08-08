## ADDED Requirements

### Requirement: Tokens carry their exact source text

The reader SHALL return, for each token, a token value exposing the token kind,
the exact source substring consumed to produce it, the absolute character offsets
of the start and end of that substring, and the parsed value that the underlying
lexer computed.

The raw text MUST be the verbatim source substring, preserving the original
spelling in every respect: radix and exponent notation, escape sequences,
character-name spelling, boolean spelling, identifier bars and inline hex
escapes, and internal whitespace.

#### Scenario: Token exposes both raw text and parsed value

- **WHEN** the reader reads the source `#xff`
- **THEN** the token's raw text is the string `#xff`
- **AND** the token's parsed value is the number `255`
- **AND** the token's start and end offsets delimit exactly those four characters

#### Scenario: Offsets delimit the raw text

- **WHEN** any token is read from a source string
- **THEN** the substring of the source between the token's start and end offsets
  is equal to the token's raw text

### Requirement: Concatenated token text reproduces the source

Concatenating the raw text of every token returned by the reader, in the order
returned, from the beginning of input through the end-of-file token, SHALL
reproduce the input byte for byte.

This MUST hold for tokens of every kind, including whitespace, line comments,
nested comments, datum comments, directives, and shebang lines, so that no input
character is attributable to no token.

#### Scenario: Round-trip of a whole source file

- **WHEN** the reader tokenizes a source file to end of input
- **AND** the raw text of all returned tokens is concatenated in order
- **THEN** the result is byte-for-byte identical to the file's contents

#### Scenario: Atmosphere is not dropped

- **WHEN** the reader reads source containing leading whitespace, a line comment,
  and a nested `#| ... |#` comment between two data
- **THEN** each of those is returned as its own token with its exact source text
- **AND** the concatenation of all token text reproduces the source

### Requirement: Spellings that the lexer normalizes are recoverable

For every construct whose parsed value discards the source spelling, the token's
raw text SHALL preserve the distinction, so that two inputs with equal parsed
values but different source text yield different raw text.

#### Scenario: Boolean spellings are distinguishable

- **WHEN** the reader reads `#t` and separately reads `#true`
- **THEN** both tokens have the parsed value `#t`
- **AND** their raw texts are `#t` and `#true` respectively

#### Scenario: Character-name spellings are distinguishable

- **WHEN** the reader reads `#\nul` and separately reads `#\null`
- **THEN** both tokens have the same parsed character value
- **AND** their raw texts are `#\nul` and `#\null` respectively
- **AND** the same holds for the `linefeed`/`newline` and `esc`/`escape` pairs

#### Scenario: String escapes are preserved

- **WHEN** the reader reads the source `"\x41;"`
- **THEN** the token's parsed value is the string `A`
- **AND** the token's raw text is the six characters `"\x41;"`

#### Scenario: Identifier spelling is preserved

- **WHEN** the reader reads `|foo|` and separately reads `foo`
- **THEN** both tokens have the parsed value of the symbol `foo`
- **AND** their raw texts are `|foo|` and `foo` respectively

#### Scenario: Bracket shape is preserved

- **WHEN** the reader reads a list written with square brackets
- **THEN** the opening and closing tokens report bracket kinds distinct from
  those reported for parentheses
- **AND** their raw texts are `[` and `]`

### Requirement: Datum comments retain their commented-out text

A datum comment introduced by `#;` SHALL be returned as a single token whose raw
text spans the `#;` marker, any intervening atmosphere, and the entire commented
datum as written in the source.

#### Scenario: Datum comment span covers the commented datum

- **WHEN** the reader reads the source `(a #;(b c) d)`
- **THEN** one returned token has the raw text `#;(b c)`
- **AND** the concatenation of all token text reproduces `(a #;(b c) d)`

### Requirement: The existing datum-reading API is unchanged

Adding source recording MUST NOT change the behavior of the reader's
datum-oriented entry points. `read-annotated`, `read-datum`, and
`detect-scheme-file-type` SHALL accept the same arguments, return the same
values, signal the same conditions, and enforce the same dialect gating as the
vendored reader at the pinned tag.

The two-value lexer that these entry points use SHALL remain available to callers
under a distinct name, so that recording is opt-in rather than imposed.

#### Scenario: Vendored reader test suite still passes

- **WHEN** the vendored `tests/test-reader.sps` suite is run against the derived
  reader, adapted only for the library name
- **THEN** every test passes with the same results as against the pristine
  vendored reader

#### Scenario: Recording does not alter dialect gating

- **WHEN** a construct restricted to one dialect is read in a mode that forbids
  it, such as `#vu8(` in `r7rs` mode
- **THEN** the reader signals the same error it signalled before this change
