## 1. The terminal in the grammar

- [x] 1.1 Add an `indent` field to the `tail` record in `src/pitch/style.sls`,
      holding a number of columns; note beside it that the value lives on the
      tail rather than on the styled shape because the indent is a property of
      what the terminal means, and putting it on the shape would be the
      general indent-by-N mechanism this change declines to build
- [x] 1.2 Export a `tail-indent` accessor
- [x] 1.3 Add `body0` to `terminal-tail`, indent 0; give `body`, `fill` and the
      four starred clause terminals indent 2. Keep the numbers named rather than
      literal at each site if that reads better, but they stay constants
- [x] 1.4 Update the grammar comment at the head of the library: the `fmt-tail`
      production gains `body0`, and the note about which parts are SRFI 272's
      says plainly that `body0` is pitch's own, why a terminal was the only
      place the rule could live given that head-symbol branches are prohibited,
      and that no further extension follows from this precedent
- [x] 1.5 Confirm the grammar reader still refuses an unknown terminal, and that
      the refusal still happens where the table is built rather than at layout

## 2. The layout

- [x] 2.1 In `src/pitch/print.sls`, have `styled-body` take its nesting amount
      from `(tail-indent (styled-tail shape))` instead of the `hanging-indent`
      constant; no branch, no head symbol, one substitution
- [x] 2.2 Leave `hanging-indent` as the named constant the indented terminals
      are given, so there is still one place the value 2 is written down
- [x] 2.3 Confirm nothing else in the printer reads `hanging-indent` in a way
      that should now vary, and that the generic shape's hanging alternative is
      deliberately unchanged
- [x] 2.4 Confirm `(nest 0 ...)` needs no addition to `(pitch doc)` and leaves
      the differential oracle untouched

## 3. The table entries

- [x] 3.1 R6RS table: `((library) (_ d . body))` becomes `(_ d . body0)`
- [x] 3.2 R7RS table: `((define-library) (_ d . body))` becomes `(_ d . body0)`
- [x] 3.3 Leave `import`, `export`, and every other entry alone

## 4. Tests

- [x] 4.1 `tests/test-style.sps`: `(_ d . body0)` is accepted; `body0` appears in
      the every-terminal-accepted case; an unknown terminal is still refused
      where the table is built
- [x] 4.2 `tests/test-style.sps`: the R6RS `library` entry and the R7RS
      `define-library` entry both carry a tail whose indent is 0
- [x] 4.3 `tests/test-print.sps`: a `library` broken across lines has its body at
      the opening delimiter's column, under the R6RS dialect
- [x] 4.4 `tests/test-print.sps`: a `define-library` likewise, under R7RS
- [x] 4.5 `tests/test-print.sps`: a `when` or `define` in the same file still
      indents two, so the change is shown confined to the new terminal
- [x] 4.6 `tests/test-print.sps`: a `body0` form broken with its opening
      delimiter at a column other than 0 puts its tail at that column, which is
      what distinguishes "zero from the delimiter" from "column 0 of the file"
- [x] 4.7 `tests/test-print.sps`: a `define` nested inside a library body still
      indents its own body two columns
- [x] 4.8 Confirm both safety checks pass and idempotence holds for a source
      containing a library, at more than one width

## 5. Reformat pitch under the new style

- [x] 5.1 Run `make format`
- [x] 5.2 `make format-check` is a no-op afterwards
- [x] 5.3 Confirm the diff is indentation only — no token moved to a different
      line for any reason other than its indent changing, and no file outside
      `FORMAT_SOURCES` touched

## 6. Verification

- [x] 6.1 `make test` passes
- [x] 6.2 `make oracle-layout` still reports all entries agreeing
- [x] 6.3 `make vendor-verify` clean, and `make vendor-diff` still exactly 337
      lines — `src/pitch/reader.sls` is outside `FORMAT_SOURCES` and must not
      have moved
- [x] 6.4 Bootstrap check: pitch built from the reformatted source and pitch
      built from the previous commit produce byte-identical output over files
      neither reformatted, at several widths. This is what shows the mechanical
      step changed nothing but whitespace, which the per-file safety checks
      cannot show because they compare each file against itself
- [x] 6.5 Confirm the declared-normalizations list is still empty and no new
      entry was needed

## 7. Documentation

- [x] 7.1 When the deltas are synced, correct the Purpose paragraph of
      `openspec/specs/style-layout/spec.md`: it states the two-column rule
      unconditionally and no delta carries it, so it goes stale silently
- [x] 7.2 Check whether `docs/DESIGN.md` §5 describes the tail terminals or the
      indent, and update it if so
- [x] 7.3 Leave `README.md` alone — it documents width and dialect, and neither
      moves
