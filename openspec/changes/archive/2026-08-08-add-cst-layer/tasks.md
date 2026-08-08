## 1. Node representation

- [x] 1.1 Create `src/pitch/cst.sls` as library `(pitch cst)` importing
      `(pitch reader)`, with a header stating that the CST is dialect-agnostic
      and that leaf text is the token's text.
- [x] 1.2 Define the leaf record: holds one token, sealed, non-opaque, with a
      fresh nongenerative UID. Add `leaf-text` delegating to `token-text`.
- [x] 1.3 Define the interior node records: `document` (children, eof leaf),
      `compound` (open leaf, children, close leaf where close may be `#f`),
      `prefix` (marker leaf, children, datum where datum may be `#f`), and
      `error-node` (anchor token, message, children). List, vector and
      bytevector share the `compound` record and are told apart by
      `compound-kind`, which reads the opening token rather than storing the
      kind — the same "no second source of truth" rule the design applies to
      bracket shape. Record names `list` and `vector` would also shadow
      `(rnrs base)` bindings.
- [x] 1.4 Add the generic accessors: `cst-node?`, `node-kind`, `node-children`,
      and the per-kind predicates.
- [x] 1.5 Add `trivia?`, true for leaves whose token kind is whitespace, comment,
      nested comment, inline comment, directive, or shebang. Add a datum-child
      accessor that filters trivia.
- [x] 1.6 Add `list-improper?`, true when a list node's children contain a `dot`
      leaf in a valid tail position.
- [x] 1.7 Add `cst-leaves`, the in-order leaf walk, covering open, children, and
      close for interior nodes and marker, children, and datum for prefixes.
- [x] 1.8 Add `cst->text` and `write-cst`, emitting `token-text` for each leaf of
      the in-order walk into a string output port.

## 2. Tokenizing

- [x] 2.1 Create `src/pitch/parse.sls` as library `(pitch parse)` importing
      `(pitch reader)` and `(pitch cst)`.
- [x] 2.2 Define the diagnostic record: message, token, with line and column read
      from the token rather than from any condition's source information.
- [x] 2.3 Implement `tokenize`, driving `get-token` to the eof token and
      returning the token vector and the diagnostics list. Create the reader in
      `rnrs` mode with `reader-tolerant?` set to `#t`.
- [x] 2.4 Install the `with-exception-handler` that catches the continuable
      warnings `reader-warning` raises in tolerant mode, records a diagnostic
      anchored to the token being read, and continues.
- [x] 2.5 Add `parse-source`, the convenience that tokenizes a string and parses
      the result.

## 3. Parsing

- [x] 3.1 Implement `parse-tokens` over the token vector, returning the document
      node and the diagnostics list, with the eof leaf held by the document.
- [x] 3.2 Handle atoms and trivia: every token that is not a delimiter, prefix
      marker, or dot becomes a leaf appended to the current child sequence.
- [x] 3.3 Handle `openp`, `openb`, `vector`, and `bytevector` by descending; on
      the matching close, build the node with both delimiter leaves.
- [x] 3.4 Enforce delimiter matching: `openp` and the `#(`/`#vu8(`/`#u8(` opens
      close with `closep`, `openb` closes with `closeb`. On a mismatch, close the
      node with the mismatched leaf and record a diagnostic.
- [x] 3.5 Handle end of input inside an open node: build the node with `close` of
      `#f` and record a diagnostic, once per unclosed node.
- [x] 3.6 Handle an unmatched close token at the current level by building an
      error node holding that leaf and recording a diagnostic.
- [x] 3.7 Handle `abbrev` and `label` tokens as prefix markers: consume trivia
      into the prefix node's children, then take the next datum as `datum`. If
      end of input or a close delimiter arrives first, set `datum` to `#f` and
      record a diagnostic.
- [x] 3.8 Handle `dot`: append it as a leaf, then validate that it is preceded by
      at least one datum, followed by exactly one datum, and is the only dot in
      the list. Record a diagnostic for each violation without removing the leaf.
- [x] 3.9 Confirm no path inserts, drops, or substitutes a token: every token in
      the input vector reaches exactly one leaf on every branch, including the
      error branches.

## 4. Tests

- [x] 4.1 Create `tests/test-cst.sps` using `(tests runner)`, following the
      structure of `tests/test-recording.sps`.
- [x] 4.2 Representation tests: leaf text equals token text, trivia are siblings
      in source order, delimiters are named and not in the child sequence,
      bracket shape comes from the tokens, `#vu8(` and `#u8(` give the same node
      kind, `#;` is one opaque leaf, abbreviations and `#0=` are prefix nodes,
      the dot stays a flat child.
- [x] 4.3 Leaf-sequence tests: the in-order leaf walk equals the token vector,
      for well-formed and for malformed input.
- [x] 4.4 Construction tests: multiple top-level forms, leading shebang, empty
      source, clean input yields no diagnostics.
- [x] 4.5 Malformed-input tests, one per case in the specs: unclosed delimiter,
      unexpected close, mismatched bracket shape, prefix with no datum, dot in an
      invalid position, more than one datum after a dot. Each asserts both the
      tree shape and a non-empty diagnostics list.
- [x] 4.6 Diagnostic-position tests: a diagnostic's line and column are its
      token's start line and column, including on a recursive lexer path such as
      a `#;` datum comment, where the reader's saved position disagrees.
- [x] 4.7 Round-trip tests over targeted sources: every kind of trivia, bracket
      shapes and abbreviations, numeric and string spelling, and each malformed
      case from 4.5.
- [x] 4.8 Round-trip test over the five in-repo files `tests/test-recording.sps`
      already uses, plus the two new source files, for seven in total. Read each
      file into a string, parse that string, and compare `cst->text` against the
      string — not against anything derived from the tree.
- [x] 4.9 Add `tests/test-cst.sps` to the `test` target in the `Makefile`.
- [x] 4.10 Run `make test` and confirm the 196-test baseline in
      `tests/test-reader.sps` is unchanged and `make vendor-verify` passes.

## 5. Documentation

- [x] 5.1 `docs/DESIGN.md` §3: replace the open "Text ownership" question with
      the settled decision and its rationale.
- [x] 5.2 `docs/DESIGN.md` §3: amend "Node kinds needed" and "Malformed input" to
      match what the specs settle, including the leaf-sequence invariant and the
      diagnostics-list representation of cleanliness.
- [x] 5.3 `docs/DESIGN.md` §3: record the `#;` opacity decision as a decision, as
      that subsection asks.
- [x] 5.4 `README.md`: update the architecture block's CST line and the
      repository layout list to mention `src/pitch/cst.sls` and
      `src/pitch/parse.sls`.
- [x] 5.5 Record the two carried-forward open questions — reader mode narrowing
      on `#!r6rs`/`#!r7rs`, and whether `tokenize` should expose strict mode — in
      `docs/DESIGN.md` rather than leaving them only in this change's design.
