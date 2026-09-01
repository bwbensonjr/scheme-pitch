## Why

A quoted data list that exceeds the page width is exploded one element per line,
staircased off its *second* element. Reported as issue #13, from the outside:

```scheme
;; written
(define *prims*
  '(car cdr cons null? pair? eq? eqv? equal? not vector? string? symbol? char? number? list?))

;; what pitch 0.1.0 produces
(define *prims*
  '(car cdr
        cons
        null?
        pair?
        ...
        list?))
```

**The defect is the fallback shape, not the lookup.** `car` has no style entry —
pitch's tables hold syntactic keywords only — so the list falls to the generic
shape. The generic shape's aligned rendering welds the second element to the
first with a space at which no break may be taken, then staircases the rest off
the second element's column. That is exactly right for `(some-function a b c)`,
where the head is genuinely distinguished, and it is the same defect the
peer-list change fixed for binding lists: a quoted data list distinguishes
nothing at all.

**Configuration cannot reach it, and cannot be made to without a grammar
addition.** The obvious entry does nothing:

```scheme
(pitch-config 1 (width 88) (dialect common)
  (styles common ((quote) (_ . fill))))
```

byte-identical output, because the `'` abbreviation is a prefix node and has no
head symbol to key on. Nor can the style grammar express what is wanted even if
it did: a style must end in a tail terminal, so `(_ l)` is refused, and the only
tails available either look their elements up (`fill`, `body`) or read them as
clauses (`lc*`). The grammar is closed, and `style-grammar` requires an argument
of its own before it is opened.

**Impact, measured.** Over Emit's 32 hand-authored sources (13,229 lines) this is
the single largest source of diff — `src/prelude-surface.scm` grows 563 → 784
lines, `src/emit.ss` 1837 → 2176 — and it is what currently blocks Emit from
adopting pitch at all.

### What the prior art says

Reproduced locally except where noted. The evidence is recorded here because it
decided the rule, and because the first finding is the one most likely to be
raised against this change.

**`raco fmt` produces pitch's exact output, and fills nothing anywhere.** On
issue #13's repro it emits the same staircase byte for byte, at every width. Its
`require`, `provide`, lambda formals, `case` literals and `#(...)` vectors all go
one element per line; there is no fill combinator in its source, and its reader
treats `'` as a bare prefix with no special handling. This matters twice: pitch's
current behavior is inherited rather than accidental, and pitch already goes
*beyond* `raco fmt` by filling `f`, `l`, `h` and bytevectors. `raco fmt` is by
the Πe paper's first author, so it is the reference Lisp formatter on this
engine.

**The paper supplies the mechanism and takes no position on quoted data.**
`fillSep` is a first-class construct in its benchmark suite — "FillSep benchmarks
test the fillSep construct (also known as fill), which performs word wrapping" —
and Πe handles it in 0.010 s and 0.190 s where Bernardy's printer fails outright.
Filling is a case this engine is specifically good at. But §8.2, on the Racket
formatter, says nothing about quoted data or a code/data distinction; it notes
only that each function application has three styles. The `pretty-expressive`
library ships no fill combinator, and its S-expression example is exactly the
three alternatives pitch's generic shape already offers.

**ANSI Common Lisp fills quoted data and keeps code styles inside a quote.**
SBCL at margin 50:

```lisp
'(zeta-one zeta-two zeta-three zeta-four        ; quoted data: filled
  zeta-five zeta-six zeta-seven zeta-eight)

'(defun my-function (alpha beta)                ; quoted code: styled as code
   (list alpha beta)
   (list beta alpha))
```

`pprint-fill` is the standard default for a list with no dispatch entry. So CL's
rule is **not** "quoting suppresses lookup"; it is "lookup happens regardless of
quoting, and the fallback for an unstyled list is fill". A backquote template is
styled as code too.

**zprint suppresses lookup deeply and does not fill.** Its `:quote` entry means
quoted lists' "first elements (and all contained first elements) will not be
looked up in the `:fn-map`", on by default — but "the default for quoted lists
will format them on a single line if possible, and will format them without a
hang if multiple lines are necessary", which is one element per line, not packed.
(Not reproduced locally; from the 1.2.8 and 1.3.0 references.)

| | Lookup suppressed in a quote? | Unstyled list filled? |
|---|---|---|
| `raco fmt`, pitch 0.1.0 | no | no |
| ANSI CL | no | **yes** |
| zprint | **yes, deep** | no |

The two properties are independent, and each has a shipping precedent. The
conjunction — suppress *and* fill — has none, and an earlier draft of this
proposal chose it. Filling is what fixes issue #13; suppression is what would
have packed quoted code into a paragraph. This change takes the first and not the
second.

## What Changes

- **A quoted position changes the fallback shape, and nothing else.** The datum
  of a `'` prefix, and every compound nested anywhere within it, is a quoted
  position. A compound in one whose head has a style entry keeps that style,
  exactly as today. A compound in one with **no** entry — no head symbol, or a
  head symbol the table does not hold — is filled rather than taking the generic
  shape. This is ANSI CL's rule, and it fixes issue #13's repro, whose head is
  `car`.

- **Style lookup is not suppressed, at any depth.** `'(define (f x) (+ x 1))`
  keeps `define`'s shape; `'(let ((a 1)) b)` keeps `let`'s. Quoted code goes on
  looking like code, which is the behavior CL ships and the loss the earlier
  draft would have taken.

- **The fallback propagates through the whole quoted subtree**, so a sublist of a
  quoted list fills too. Without propagation `'((a b c ...) (d e f ...))` would
  fill at the top and staircase one level down.

- **A quoted position overrides an expression terminal and yields to a data
  terminal.** Inside a quoted subtree an `e` or `body` element is still quoted,
  so the fill fallback survives into a styled form's body. A terminal that
  already names data — `i`, `d`, `f`, `l`, `h`, and a clause's first element —
  keeps its meaning, because it is the more specific statement: a literals list
  inside a quote is still a literals list.

- **A quoted list containing a dot keeps the generic shape**, which is where the
  dot is already preserved. Fill has no rendering for an improper tail and must
  not invent one.

- **BREAKING (output only).** Any project formatting a source with an overflowing
  unstyled quoted list gets different output. No token spelling, no comment
  content, and no declared normalization changes; the declared-normalizations
  list stays empty.

Deliberately out of scope, each for a reason:

- **The `(quote datum)` list spelling.** Reaching it requires either a `cond`
  branch on the head symbol `quote`, which is prohibited, or a grammar addition,
  which needs its own proposal. Hand-written source writes the abbreviation; this
  is a gap, and it is recorded as one rather than closed by the means available.
- **`` ` ``, `,`, `,@`, `#'`, `` #` ``, `#,`, `#,@`.** A quasiquoted or syntax
  template is data with expression holes and is routinely used to spell code. CL
  styles a backquote template as code and so does pitch today; extending the fill
  fallback to it would also need a rule for what an unquote does to the property.
  `'` is the one abbreviation with no holes.
- **Filling ordinary function calls.** CL fills `(some-function a b c)` too.
  Scheme and Racket house style aligns arguments under the first, `raco fmt` and
  pitch both do, and changing it is a far larger proposal than this one.
- **A bare `#(...)` vector outside a quote.** Data by the same argument, and
  probably wants the same treatment, but it is separable and wants its own corpus
  evidence.
- **Preserving the author's hand-grouping.** Filling re-packs, so grouping
  expressed by line breaks alone is lost. Grouping expressed by blank lines or by
  interleaved comments survives, because both already force breaks. Emit's tables
  use comments; this change must show that they still do.

## Capabilities

### New Capabilities

None. This specifies a case an existing capability left uncovered.

### Modified Capabilities

- `style-layout`: gains a requirement that a quoted datum is a position in which
  the fallback shape is fill rather than the generic shape, that the property
  propagates through the whole subtree, that it does not suppress style lookup,
  how it composes with expression and data terminals, and that a quoted list with
  a dot keeps the generic shape.

## Impact

- `src/pitch/print.sld` — `compound-shape` takes the quoted property and returns
  `fill` instead of `generic` when no entry matches; the property is threaded
  through the element-style channel so it propagates into children. `fill-body`
  is reused unchanged, and `head-symbol` and the table lookup are untouched.
- `src/pitch/style.sld`, `src/pitch/default-config.scm` — untouched. No table
  entry is added, no grammar terminal is added.
- `src/pitch/doc.sld`, `src/pitch/layout.sld`, `src/pitch/cost.sld` — untouched;
  `make oracle-layout` is the check that says so.
- `tests/` — new cases for the repro, for nested quoted lists, for a styled head
  inside a quote *keeping* its style, for comment- and blank-line-forced breaks
  inside a filled quoted list, for the dotted fallback, and pins that `` ` `` and
  `#'` are unaffected.
- `openspec/specs/style-layout/spec.md` — the new requirement, at sync.
- `docs/DESIGN.md` §5 — "What a terminal means" states the code/data split in
  terms of terminals; it gains the quoted fallback and a note that quoting does
  not suppress lookup. §6's account of the generic shape's three alternatives is
  where the fallback change belongs.
- Emit — unblocks the `pitch-source-formatting` one-time reformat; the two files
  named in issue #13 are the acceptance evidence.
