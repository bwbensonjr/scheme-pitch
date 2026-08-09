## 1. The tests first, since their absence is why this shipped

- [x] 1.1 In `tests/test-print.sps`, add a group for peer lists and write the
      failing cases before touching `print.sls`: a multi-binding `let` at a width
      that forces breaking, asserting one binding per line and every binding —
      the first included — at the column after the binding list's opening
      delimiter
- [x] 1.2 The same for `let*`, `letrec`, `let-values` and `do`, so the shared
      table entry is covered by more than its first member
- [x] 1.3 `parameterize` under R7RS and `with-syntax` under R6RS, the two
      dialect-specific entries in scope
- [x] 1.4 A binding list that fits stays flat, and `(let () ...)` emits `()`
- [x] 1.5 Pin the cases that MUST NOT move: a `cond` clause keeping the generic
      aligned rendering with its test as head, a `cond` and a `case-lambda` whose
      starred *tail* still puts one clause per line at the body indent, a `guard`
      whose `(i . ec*)` slot is still a clause, a `lambda` whose formals still
      fill, and a plain call still pairing head with first argument
- [x] 1.6 Confirm these fail before the fix and for the right reason — the
      staircase, not an unrelated error. A test that would pass either way is
      worse than no test here, because the suite already passed with the bug

## 2. The fix

- [x] 2.1 Turn `headless-doc`'s `if` into a three-way `cond`: bytevector or
      filling-peer to `fill-body`; peer with a non-filling tail to `peer-body`;
      everything else to `generic-body`
- [x] 2.2 Add `peer-body` beside `fill-body`: empty list emits its delimiters,
      otherwise `(group (whole node (align (join-items items nl tbl))))`
- [x] 2.3 Comment why there are two layouts and not three — hanging separates a
      head from its arguments and a peer list has no head — and why `align` sits
      immediately inside `whole`, which is the same argument `fill-body` relies
      on for a comment-forced break
- [x] 2.4 Correct `headless-doc`'s header comment: "its first element plays that
      part" is true of a clause and false of a binding list, and that sentence is
      the assumption the bug was made of
- [x] 2.5 Confirm no head symbol is examined anywhere in the new code and
      `compound-shape` is untouched

## 3. Verification of the fix in isolation

- [x] 3.1 The tests from section 1 now pass
- [x] 3.2 `make test` passes in full
- [x] 3.3 `make oracle-layout` still reports all entries agreeing — the layout
      engine is untouched and this is the check that says so
- [x] 3.4 Re-format the reported case from the outside project and confirm it
      reproduces the hand-written original byte for byte:
      `(let ([s0 ...] [s1 ...] [sme ...] [sk ...] [sn ...]) ...)`
- [x] 3.5 Confirm both safety checks still pass and idempotence holds for a
      source containing multi-binding `let`s at several widths

## 4. Reformat pitch's own sources

- [x] 4.1 Snapshot whitespace-collapsed copies of the files in `FORMAT_SOURCES`
      so the next task can be checked exactly
- [x] 4.2 Run `make format`; expect `check`, `cli`, `cost`, `datum`, `layout`,
      `parse` and `print` to change and the other six not to
- [x] 4.3 `make format-check` is a no-op afterwards
- [x] 4.4 Confirm every reformatted file is identical to its previous contents
      modulo whitespace
- [x] 4.5 Confirm `src/pitch/reader.sls`, `tests/` and `vendor/` are untouched,
      and that `make vendor-verify` is clean with `make vendor-diff` still
      exactly 337 lines

## 5. Bootstrap

- [x] 5.1 Compare pitch built from this tree against pitch built from the
      previous commit over files that contain no peer list, at several widths:
      they must agree byte for byte, which is what shows the reformat and the
      dispatch change altered nothing else
- [x] 5.2 Over a file that does contain one, confirm the outputs differ only in
      the layout of peer lists, and account for the difference rather than
      asserting it away

## 6. Documentation

- [x] 6.1 Check whether `docs/DESIGN.md` §5 describes the headless-list dispatch
      or claims the first element plays the head; correct it if so
- [ ] 6.2 At sync, confirm the new requirement reads coherently beside the
      existing clause and fill requirements, which it is deliberately contrasted
      with
- [x] 6.3 Leave `README.md` alone — no configuration surface changes
