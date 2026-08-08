## 1. Reference material

- [x] 1.1 Vendor nothing, but record the reference. Add a comment block at the
      top of `src/pitch/layout.sls` naming the paper (Porncharoenwase, Pombrio,
      Torlak, *A Pretty Expressive Printer*, OOPSLA 2023), the implementation
      (`sorawee/pretty-expressive`), the commit or version read, and the list of
      deliberate divergences from `design.md`: external per-call memoization,
      memoizing every internal node, difference-list output, no `special`, no
      parameters, `text` rejecting line endings.
- [x] 1.2 Install the Racket reference for the oracle: `raco pkg install
      pretty-expressive`. Confirm `racket -l pretty-expressive` loads.

## 2. The cost factory

- [x] 2.1 Create `src/pitch/cost.sls`. Define the cost factory record with the
      five fields `cost<=?`, `cost+`, `cost-text`, `cost-nl`, `limit`, plus a
      predicate and accessors.
- [x] 2.2 Document the algebraic laws at the interface: total preorder,
      associative and commutative combine, and monotonicity of combine with
      respect to the order. State that they are the caller's obligation and that
      the optimality guarantee depends on them.
- [x] 2.3 Implement `default-cost-factory` as a `case-lambda` over page width,
      and page width with computation width. Cost is a badness/height pair
      compared lexicographically; newline costs `(0 1)`; text at column `pos` of
      length `len` costs badness `b*(2a+b)` where `a = max(w,pos) - w` and
      `b = pos+len - max(w,pos)`, or zero when `pos+len <= w`.
- [x] 2.4 Default the computation width to the floor of page width times 1.2.
- [x] 2.5 Add a comment deriving the badness expression as the increment in
      squared overflow, so a reader can see that total badness telescopes to the
      sum of squared per-line overflows.

## 3. The document algebra

- [x] 3.1 Create `src/pitch/doc.sls`. Define the document record variants:
      `text`, `newline`, `concat`, `alternatives`, `nest`, `align`, `reset`,
      `full`, `cost`, `fail`. Documents are immutable and carry no memo state.
- [x] 3.2 Store on each node the two facts construction can compute cheaply and
      resolution needs: the newline-count overapproximation, and the four static
      failure flags indexed by begin-full and end-full.
- [x] 3.3 Implement the line-ending check for `text`, recognizing the same seven
      endings as `token-equivalence`: LF, CR, CR+LF, CR+NEL, NEL, line
      separator, paragraph separator. Raise on any occurrence, naming the
      offending string. Do not split, do not repair.
- [x] 3.4 Implement the smart constructors per the table in `design.md`:
      empty-text identity, adjacent-text merge, `full`+non-empty-text to `fail`,
      `fail` strictness in concat, `fail` as choice unit, choice idempotence,
      nest combining, and indentation dropped on `text`, `align`, `reset`.
- [x] 3.5 Implement the derived combinators: `empty-doc`, `nl`, `break`,
      `hard-nl`, `alt`, `flatten`, `group`.
- [x] 3.6 Implement the five append families, each with an `-append` variadic and
      a `-concat` list form: `u-`, `us-`, `v-`, `a-`, `as-`. Do not provide the
      Racket infix aliases.
- [x] 3.7 `flatten` must memoize on document identity within a call so that a
      shared DAG is not re-flattened exponentially, and must discard `nest`,
      `align`, and `reset`.
- [x] 3.8 Export the surface. Note in the header that `newline` shadows
      `(rnrs io simple (6))`, that `(rnrs base (6))` does not export it so
      document-building libraries are unaffected, and that a file doing console
      I/O should `except` or `rename` on import.

## 4. The resolver

- [x] 4.1 Create `src/pitch/layout.sls`. Define the measure record: last column,
      cost, and a tokens procedure taking a reversed string list and returning
      one.
- [x] 4.2 Define the lazy tainted-measure record: a thunk, a memoized value, a
      forced flag, and the newline count used to choose between two tainted
      candidates. This replaces Racket's `delay #:nl` promise.
- [x] 4.3 Implement the measure set as a list ordered by decreasing last column
      and increasing cost, with the domination test `last1 <= last2` and
      `cost1 <= cost2`.
- [x] 4.4 Implement `merge` over measure sets, including the four cases where one
      or both sides are tainted, and the prunable flag that lets concat keep a
      single tainted candidate.
- [x] 4.5 Implement the per-call memo table: an `eq?` hashtable from document to
      a table keyed by the begin-full/end-full pair and the packed `(i, c)` key.
      Skip memoization when `c > limit` or `i > limit`.
- [x] 4.6 Implement `resolve` for each form: `text`, `newline`, `concat`
      (resolving the right operand once per surviving left measure, merging with
      pruning), `alternatives`, `align`, `reset`, `nest`, `cost`, `full`, `fail`.
- [x] 4.7 Implement the taint boundary: when the resulting column or the
      indentation exceeds the limit, return a lazy tainted measure wrapping the
      core computation, and record static failure when forcing yields nothing.
- [x] 4.8 Implement the top level: merge the resolutions with end-full false and
      true, taint the result if it is lazy, force it, and raise a condition when
      there is no measure.
- [x] 4.9 Render the winning measure by applying its tokens procedure to the
      empty list, reversing, and concatenating.
- [x] 4.10 Define the result record carrying the taint flag and the cost, and the
      layout entry point as a `case-lambda` over `(doc factory)` and
      `(doc factory offset)`, returning the text and the result record.
- [x] 4.11 Add a `pretty-format` convenience returning only the string, as a
      `case-lambda` over `(doc)` and `(doc page-width)`.
- [x] 4.12 Define the layout-failure condition type and export its predicate, so
      a caller can distinguish it from any other error.

## 5. Tests

- [x] 5.1 Create `tests/test-doc.sps` using `(tests runner)`, following the
      structure of `tests/test-check.sps`.
- [x] 5.2 Test the line-ending rejection: each of the seven endings individually,
      a real line comment's token text, and a comment body without its
      terminator accepted.
- [x] 5.3 Test each smart constructor by laying out the simplified and
      unsimplified forms and asserting identical text and cost.
- [x] 5.4 Test the derived combinators: `flatten` over soft and hard newlines,
      `flatten` discarding indentation, `group` choosing flat when it fits and
      broken when it does not, each append family at zero, one, and several
      arguments.
- [x] 5.5 Create `tests/test-layout.sps`. Test each core constructor's layout in
      isolation, including `align` and `reset` under an enclosing `nest`.
- [x] 5.6 Test the paper's and the reference documentation's worked examples at
      their stated page widths.
- [x] 5.7 Test that a choice is resolved by total cost rather than local fit: a
      document whose flat alternative fits locally but forces later overflow
      must break.
- [x] 5.8 Test the failure/taint split: `fail` raises, `(concat (full (text "a"))
      (text "b"))` raises, an over-long text returns tainted, and a fitting
      document returns untainted.
- [x] 5.9 Test purity: the same document under two factories with different page
      widths gives each factory's own answer, in either call order.
- [x] 5.10 Test the offset: a non-zero offset prices and breaks the first line as
      if it started there, and emits no leading spaces.
- [x] 5.11 Test the default factory's laws over a range of costs, and its
      arithmetic at the boundary cases: text ending exactly at the page width,
      starting exactly at it, and spanning it.
- [x] 5.12 Add both files to the `test` target in the `Makefile`.

## 6. The differential oracle

- [x] 6.1 Create `tests/oracle/documents.scm`: a corpus of entries, each naming
      a document in a small S-expression description language mirroring the
      constructors, plus page width, computation width, and offset.
- [x] 6.2 Populate the corpus per the spec: every core constructor in isolation,
      `full` satisfiable and unsatisfiable, overflowing documents so taint is
      compared, heavily shared DAGs from `group`, and non-zero offsets. Exclude
      `special`.
- [x] 6.3 Write `tests/oracle/oracle.sps`: read the corpus, build `(pitch doc)`
      documents, and emit one record per entry with text, cost, and taint in a
      fixed, diffable format.
- [x] 6.4 Write `tests/oracle/oracle.rkt`: read the same corpus, build
      `pretty-expressive` documents, and emit the same format. Handle the
      unsatisfiable entries by emitting a failure marker on both sides rather
      than crashing.
- [x] 6.5 Add the `oracle-layout` target to the `Makefile`: run both drivers,
      diff their output, and fail on any difference.
- [x] 6.6 Make the target check for `racket` and for the `pretty-expressive`
      package, and when either is missing print the install command and exit
      zero, following `vendor-verify`'s handling of a missing laesare clone.
- [x] 6.7 Confirm `make test` still passes on a path with no Racket, and that
      `oracle-layout` is not reachable from it.
- [x] 6.8 Run `make oracle-layout` and drive the diff to empty.

## 7. Documentation

- [x] 7.1 Update `docs/DESIGN.md` §6: answer the open question about porting
      `pretty-expressive`, record the settled surface, the omission of `special`
      and the parameters, the taint-versus-failure split, and the `text`
      line-ending rule with its connection to the line-comment invariant.
- [x] 7.2 Note in `docs/DESIGN.md` §6 that the printer-time assertion about line
      comments is still owed, and that `text` rejecting line endings makes it
      hard to violate by accident rather than replacing it.
- [x] 7.3 Update `README.md`: the layout engine is shipped, with the
      qualification that nothing calls it yet and that the shipped cost factory
      is the reference's rather than pitch's.
- [x] 7.4 Confirm `make vendor-verify` still passes and that
      `src/pitch/reader.sls` and `vendor/laesare/` are untouched by this change.
