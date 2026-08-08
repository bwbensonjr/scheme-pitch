## 1. The projection

- [x] 1.1 Create `src/pitch/datum.sls` as library `(pitch datum)` importing
      `(pitch cst)`, `(pitch diagnostic)` and `(rnrs mutable-pairs (6))`, with a
      header stating that the projection reads `token-value` and never
      re-parses `token-text`. The diagnostic record was extracted from
      `(pitch parse)` into a new `(pitch diagnostic)` rather than exported from
      the parser: the spec requires both layers to use one representation, and
      the projection has no other reason to depend on the parser. `(pitch parse)`
      re-exports the accessors it exported before, so no caller changes.
- [x] 1.2 Implement leaf projection: an atom's datum is its token's value.
      Assert that no number parser, string unescaper, or character-name table is
      written here.
- [x] 1.3 Implement list projection, building a pair chain from the datum
      children and skipping trivia.
- [x] 1.4 Implement improper tails: when `list-improper?` holds, the datum after
      the dot becomes the final cdr.
- [x] 1.5 Implement vector and bytevector projection. For bytevectors, validate
      each element is an exact integer in 0 to 255; diagnose and omit otherwise.
- [x] 1.6 Implement prefix projection for abbreviations: a two-element list of
      the marker token's value and the prefixed datum. Diagnose and omit a
      prefix whose datum is absent.
- [x] 1.7 Implement the document walk, returning the top-level data in order,
      with a fresh label table per top-level datum.

## 2. Datum labels

- [x] 2.1 Implement the label table: bind a label number to its datum, and
      diagnose a number bound more than once within one top-level datum, keeping
      the first binding.
- [x] 2.2 Implement reference registration as a patcher callback, mirroring the
      vendored reader: `set-car!`/`set-cdr!` for pairs and `vector-set!` for
      vectors.
- [x] 2.3 Run the patchers after each top-level datum is built, so a reference
      to the datum that contains it resolves and cyclic structure is tied.
- [x] 2.4 Diagnose a reference that resolves against no binding, and a reference
      inside a bytevector, where no element slot can be patched.
- [x] 2.5 Confirm label scope does not leak between top-level data.

## 3. Diagnostics and total behavior

- [x] 3.1 Return `(values data diagnostics)`, reusing the parser's diagnostic
      record so callers merge one kind of list.
- [x] 3.2 Confirm no path raises: project the malformed trees from the CST
      suite — unclosed delimiter, unexpected close, dangling prefix, misplaced
      dot, lexical error — and check each returns.
- [x] 3.3 Sort merged diagnostics into source order by token start offset,
      matching `parse-source`.

## 4. Layer 2

- [x] 4.1 Create `src/pitch/check.sls` as library `(pitch check)`.
- [x] 4.2 Implement `datum=?` as a named wrapper over `equal?`, documenting that
      it is `equal?` today and why the name exists.
- [x] 4.3 Implement the layer 2 check taking two source **texts**, parsing and
      projecting each independently, and reporting equivalence. The signature
      must not accept trees or data.
- [x] 4.4 Report failure, not equivalence, when either side produced a
      diagnostic, and make those diagnostics available to the caller.

## 5. Tests

- [x] 5.1 Create `tests/test-datum.sps` using `(tests runner)`, following the
      structure of `tests/test-cst.sps`.
- [x] 5.2 Projection tests: each datum kind to its host type, several top-level
      data in order, spelling discarded (`#xff` and `255`, `"\x41;"` and `"A"`),
      fold-case inherited, trivia contributing nothing, `#;` eliding its datum.
- [x] 5.3 Abbreviation tests: all eight expansions, and nesting.
- [x] 5.4 Improper-list tests: `(a . b)` and `(a b . c)`.
- [x] 5.5 Label tests: shared reference is the same object under `eq?`, cyclic
      list, cyclic vector, and no leaking between top-level data.
- [x] 5.6 Diagnostic tests, one per case in the spec: unresolvable reference,
      duplicate label, non-octet bytevector element, reference in a bytevector,
      dangling prefix. Each asserts a non-empty diagnostics list and a token
      position matching the token concerned.
- [x] 5.7 Totality tests: every malformed source from the CST suite projects
      without raising.
- [x] 5.8 Dialect tests: `#vu8(1 2)` and `#u8(1 2)` project alike, `#t` and
      `#true` project alike.
- [x] 5.9 `datum=?` tests including the four cyclic cases and exactness. Assert
      termination by the test completing.
- [x] 5.10 Layer 2 positive tests: texts differing only in whitespace, only in
      comments.
- [x] 5.11 Layer 2 negative tests: differing datum, dropped form, changed
      nesting. These matter most — a comparator returning `#t` unconditionally
      passes every positive test.
- [x] 5.12 Layer 2 failure tests: malformed input on both sides fails rather
      than reporting equivalence; unresolvable label fails.
- [x] 5.13 Known-weakness tests asserting that a deleted comment, a flipped
      bracket, an expanded abbreviation, and a respelled number all *pass* datum
      equivalence, so the weakness is pinned by tests rather than only described.
- [x] 5.14 Number edge cases: `1` versus `1.0`, `0.0` versus `-0.0`, and
      `+nan.0` against itself. Record Chez's actual answers rather than working
      around them.
- [x] 5.15 Add `tests/test-datum.sps` to the `test` target in the `Makefile`.

## 6. Differential oracle

- [x] 6.1 Create the differential test comparing `cst->datum` against Chez's own
      `read` over the in-repo corpus files, datum for datum.
- [x] 6.2 Add targeted differential cases for constructs Chez accepts:
      abbreviations, improper lists, vectors, `#vu8(`, nested structures.
- [x] 6.3 Cover what Chez rejects with written expectations instead, and state
      in the test that the differential pass is not full coverage. Measured
      rather than assumed: Chez rejects `#u8(` and, more importantly, **datum
      labels** (`#0=`/`#0#`), so label resolution — the most intricate part of
      the projection — gets no oracle coverage at all. It does accept `#true`,
      contrary to this task's original guess.
- [x] 6.4 Confirm no shipped library calls a host reader: grep the `src/pitch/`
      libraries for `read` and check every hit is ours.
- [x] 6.5 Run `make test` and confirm the 196-test baseline is unchanged, the
      CST suite still passes, and `make vendor-verify` passes.

## 7. Documentation

- [x] 7.1 `docs/DESIGN.md` §1 "Comparator details": the claim that a
      hand-written comparator will not terminate on cycles unless written to no
      longer applies once the representation is host data. Record the decision,
      the measurement on Chez, and that the obligation now rests on the
      implementation's `equal?`.
- [x] 7.2 `docs/DESIGN.md` §1: record that layer 2 diagnoses defects the parser
      cannot see, which is a second reason to keep it beyond independence.
- [x] 7.3 `README.md`: the layer 2 row names `cst->datum` as shipped; note that
      layer 2 is not yet wired end to end because there is no printer.
- [x] 7.4 Record the carried-forward open questions in `docs/DESIGN.md`: whether
      `datum=?` should ever diverge from `equal?`, whether datum-to-node
      provenance is wanted, and whether the check should report the first
      differing subtree rather than a boolean.
