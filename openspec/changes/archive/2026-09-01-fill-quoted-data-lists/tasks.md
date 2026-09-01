## 1. The tests first, and the composition cases with them

- [x] 1.1 In `tests/test-print-r7rs.scm`, add a group for quoted data and write
      issue #13's repro as a failing case: the 94-column `'(car cdr cons ...)`
      list at a width that forces breaking, asserting more than one element on at
      least one line and no element beginning at the second element's column
- [x] 1.2 A quoted list that fits stays flat and byte-identical, at several
      widths, so the fix cannot be shown by output that merely changed
- [x] 1.3 A quoted list whose head is a compound — `'((alpha 1) (beta 2) ...)` —
      packs; a vector inside a quoted list packs
- [x] 1.4 Lookup is **not** suppressed: `'(define (f x) (+ x 1) (list x x))`
      keeps `define`'s shape, `'(let ((a 1) (b 2)) (body a) (body b))` keeps
      `let`'s with its binding list as peers, and `'((a (b (cond (c d) (else
      e))))) ` styles the innermost `cond`. These are the cases the earlier draft
      of this change would have got wrong
- [x] 1.5 The composition ordering, which is the part most likely to be built
      backwards: `'(begin (alpha one two ... ))` styles `begin` *and* packs the
      inner unstyled list; `'(lambda (let cond) (body))` does **not** style its
      formals as a `let` form; `'(syntax-rules (let) ((_ x) x))` does not style
      its literals list; `'(cond (test consequent) (else other))` still reads its
      clauses as clauses
- [x] 1.6 The negative pins: `` `(alpha one two ...) ``, `#'(alpha one two ...)`,
      `(quote (car cdr cons))` written out, and an unquoted list identical to a
      quoted one are all unchanged from before this change
- [x] 1.7 A quoted list in each of the three enclosing positions — a style slot,
      a `body` tail, and a clause — so a slot assignment above cannot lose the
      quoted property
- [x] 1.8 `'(a b . c)` keeps the generic shape with the dot preserved, at a width
      that forces breaking
- [x] 1.9 Confirm 1.1, 1.3 and 1.5 fail before the change and for the right
      reason — the staircase and the lost property, not an unrelated error — and
      confirm 1.4 and 1.6 pass *before* the change, since they pin behavior this
      change must not move

## 2. Comments and blank lines inside a packed quoted list

- [x] 2.1 A quoted list with a line comment between two elements: the comment
      stays between them, is followed by a line break, and the elements on either
      side still pack
- [x] 2.2 A quoted list with a preserved blank line between two groups: one blank
      line survives, each group packs, and the blank line holds no characters
- [x] 2.3 Every line of a broken quoted list begins at the column immediately
      after its opening delimiter, checked at an indentation greater than zero
- [x] 2.4 A comment ending a quoted list still puts the closing delimiter on a
      new line, per `comment-placement`

## 3. The change

- [x] 3.1 Add the `quoted` element style beside `expression`, `datum` and
      `(nested s)`, with its constructor and predicate next to theirs
- [x] 3.2 `prefix-doc`: when the marker is the `'` abbreviation, give the datum
      item the `quoted` style. Confirm the test is on the marker's token text and
      covers `'` alone
- [x] 3.3 `compound-shape`: take the quoted property and return `fill` where it
      returns `generic` today, in **both** fallback positions — the non-list case
      and the no-entry case. Do not add any other way of finding a style
- [x] 3.4 Propagation: a compound in a quoted position assigns `quoted` to each
      of its datum items, including through `assign-styles`, where `quoted`
      replaces what would have been `expression` and leaves `i`, `d`, `f`, `l`,
      `h`, clause-first and the nested styles alone
- [x] 3.5 The dotted case: `has-dot?` on the quoted fallback path routes to
      `generic-body`, and `headless-doc` is left alone
- [x] 3.6 Amend the element-style comment above `styled-node-doc` to describe
      `quoted` in the terms Decision 2 uses — overrides `expression`, yields to a
      data terminal — since that ordering is the part a later edit is most likely
      to get wrong
- [x] 3.7 Confirm `head-symbol`, `style-table-ref`, `style.sld` and
      `default-config.scm` are untouched, that the grammar gained no terminal and
      the tables gained no entry, and that no head symbol is compared to `quote`
      anywhere

## 4. Verification of the change in isolation

- [x] 4.1 The tests from sections 1 and 2 pass
- [x] 4.2 `make test` passes in full
- [x] 4.3 `make oracle-layout` reports every entry agreeing — the engine, the
      algebra and the cost factory are untouched and this is the check that says
      so
- [x] 4.4 Both safety layers pass and idempotence holds over a corpus containing
      quoted lists, at several widths: format twice and compare, since a filled
      layout re-read as input is where a fixed point is most likely to be lost
- [x] 4.5 Format a file containing no quoted list with pitch built from this tree
      and from the previous commit: byte-identical
- [x] 4.6 `make vendor-verify` is clean and `tests/`, `vendor/` and
      `src/pitch/reader.sld` are untouched

## 5. Acceptance against the reported case and against the prior art

- [x] 5.1 Reformat issue #13's `repro.scm` and confirm the quoted list packs
- [x] 5.2 Reformat Emit's `src/prelude-surface.scm` and `src/emit.ss` — the two
      files the issue measured — and record the new line counts against the
      reported 563 → 784 and 1837 → 2176
- [x] 5.3 Read the diff for the hand-grouped tables specifically: confirm groups
      separated by a comment or a blank line survive, and record what happens to
      groups separated by a line break alone rather than asserting it is fine
- [x] 5.4 Find every quoted form in the Emit corpus whose head *does* have a style
      entry and confirm it did not move. That set is what the earlier draft would
      have repacked, and it is the evidence that Decision 3 was the right half to
      take
- [x] 5.5 Look for a case where table-sensitivity reads badly — a data list whose
      first element happens to spell a styled keyword and is now laid out as that
      form. Decision 3 accepts this cost; this task is what finds out how often it
      is actually paid, and a bad enough result reopens the decision
- [x] 5.6 Re-run the `raco fmt` and SBCL comparisons from the proposal's survey
      against the new output, so the change's own claim about the prior art is
      checked rather than remembered
- [x] 5.7 Confirm pitch refuses nothing across the corpus and every file verifies

## 6. Reformat pitch's own sources

- [x] 6.1 Run `make format` over `PITCH_FORMAT_SOURCES`; record which files move
      and confirm each moved only where an unstyled quoted compound overflows
- [x] 6.2 `make format-check` is a no-op afterwards
- [x] 6.3 Confirm every reformatted file is identical to its previous contents
      modulo whitespace

## 7. Documentation

- [x] 7.1 `docs/DESIGN.md` §5 "What a terminal means": add the quoted fallback,
      and state explicitly that quoting does **not** suppress lookup, next to the
      `(syntax-rules (let) ...)` argument it is deliberately contrasted with
- [x] 7.2 `docs/DESIGN.md` §6: the generic shape's three alternatives are
      described there; record that a quoted position substitutes the filled
      rendering for the generic one when no style applies
- [x] 7.3 Record the prior-art survey somewhere durable — `raco fmt` producing
      pitch's exact output, CL's fill-and-style rule, zprint's suppress-and-don't-
      fill rule, and the paper's `fillSep` benchmark. It is the argument for this
      rule and it should not have to be rediscovered
- [x] 7.4 Record the two known gaps where a reader will look for them: the
      `(quote datum)` list spelling, and the other abbreviations
- [x] 7.5 Check whether `README.md`'s formatting description promises anything
      about quoted data; leave the configuration section alone
- [x] 7.6 At sync, confirm the new requirements read coherently beside the
      formals/literals fill requirement, the peer-list requirement, and
      "Expression positions are looked up and data positions are not", which this
      change deliberately does *not* modify
- [x] 7.7 Comment on issue #13 with the resolution, the measured line counts, and
      the prior-art finding — the reporter proposed suppression as option 1, and
      the reply should say why the fallback-only rule was taken instead
