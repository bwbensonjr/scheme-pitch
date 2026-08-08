## ADDED Requirements

### Requirement: A tree serializes to text by concatenating its leaves

The system SHALL provide an operation that serializes a CST to text by emitting
the text of every leaf in source order, including opening and closing
delimiters, prefix markers, whitespace, and comments.

The operation MUST NOT reflow, reindent, insert, or remove any character. It
reproduces; it does not format.

#### Scenario: Serializing emits leaves in order

- **WHEN** a tree is serialized
- **THEN** the result is the concatenation of the text of its leaves, walked in
  order

#### Scenario: Serializing does not normalize spelling

- **WHEN** a source containing `#xff`, `#true`, `[a]`, `'x`, and `"\x41;"` is
  parsed and serialized
- **THEN** each of those appears in the output exactly as written in the input

### Requirement: Serializing a parsed tree reproduces its source byte for byte

For any input, serializing the tree parsed from that input SHALL produce text
identical to the input, byte for byte.

This SHALL hold for every construct the reader accepts, including whitespace,
line comments, nested comments, datum comments, directives, shebang lines,
bracketed lists, vectors, bytevectors, abbreviations, datum labels, and improper
lists.

#### Scenario: Round-trip of a source containing every kind of trivia

- **WHEN** a source containing leading whitespace, a line comment, a nested
  `#| ... |#` comment, a `#;` datum comment, and a directive is parsed and
  serialized
- **THEN** the result is identical to the source

#### Scenario: Round-trip preserves bracket shape and abbreviations

- **WHEN** a source containing `[a b]`, `'x`, `` `y ``, `,z`, and `,@w` is parsed
  and serialized
- **THEN** the result is identical to the source

#### Scenario: Round-trip preserves numeric and string spelling

- **WHEN** a source containing `#xff`, `1E10`, and `"\x41;"` is parsed and
  serialized
- **THEN** the result is identical to the source

#### Scenario: Round-trip of real source files

- **WHEN** each of the repository's own Scheme source files is read into a
  string, parsed, and serialized
- **THEN** the result is identical to that string for every file

### Requirement: Round-trip holds for malformed input

Serializing the tree parsed from a malformed input SHALL reproduce that input
byte for byte, even though the tree is not clean.

#### Scenario: Round-trip of an unclosed delimiter

- **WHEN** the source `(a (b` is parsed and serialized
- **THEN** the result is identical to the source

#### Scenario: Round-trip of an unexpected closing delimiter

- **WHEN** the source `a)` is parsed and serialized
- **THEN** the result is identical to the source

#### Scenario: Round-trip of a source with a lexical error

- **WHEN** a source containing a malformed lexeme is parsed and serialized
- **THEN** the result is identical to the source

### Requirement: The round-trip check compares against the original input text

The round-trip check SHALL compare the serialized output against the text that
was parsed. It MUST NOT compare a tree against another artifact derived from
that same tree, which would pass regardless of what the serializer did.

#### Scenario: The check reads its expected value from the input

- **WHEN** the round-trip check runs on a file
- **THEN** the expected value is the file's contents as read from disk
- **AND** the actual value is produced by serializing the tree parsed from those
  contents

#### Scenario: A serializer that drops a comment fails the check

- **WHEN** the serializer omits a comment leaf
- **THEN** the round-trip check fails
