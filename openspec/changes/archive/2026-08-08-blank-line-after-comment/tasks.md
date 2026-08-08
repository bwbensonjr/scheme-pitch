## 1. The count

- [x] 1.1 Extract `blank-count`: discount the terminating ending only when the
      preceding element did not already carry one in its own text
- [x] 1.2 Track the preceding non-whitespace child's forced-break state through
      `children->items` and pass it to `blank-count`

## 2. Emptiness

- [x] 2.1 Give `leaf-doc` an optional flag emitting its forced break under
      `reset`, with both branches still emitting a break unconditionally
- [x] 2.2 Add `blank-after?` to the item record and set it in a pass at the end
      of the fold, from the next item's blank count
- [x] 2.3 Apply the flag in `item-doc` to the item's last piece, so all five
      emitters inherit the decision rather than each looking ahead

## 3. The assertion

- [x] 3.1 Move the guard in `gap` into the `sep` branch and test
      `(not (item-broken? prev))` rather than comparing documents

## 4. Tests

- [x] 4.1 `tests/test-print.sps`: a blank line after a comment survives at top
      level and inside a form, at both caps, and none appears where none was
      written
- [x] 4.2 `tests/test-print.sps`: the blank line is empty, including inside a
      nested form where the enclosing indentation is non-zero
- [x] 4.3 `tests/test-print.sps`: the previously raising inputs do not raise
- [x] 4.4 `tests/test-format.sps`: idempotence cases for comment-then-blank
- [x] 4.5 Confirm no blank line in the formatted repository carries trailing
      whitespace, which the checks cannot catch because they filter whitespace
- [x] 4.6 `make test`, `make vendor-verify` and `make oracle-layout` green
