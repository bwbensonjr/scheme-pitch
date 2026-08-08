## Context

Everything this change consumes already exists and was read before this document
was written. `(pitch cst)` gives a tree whose leaves are exactly the token vector
and whose trivia are ordinary children. `(pitch doc)` gives the Πe algebra, in
which `text` refuses a line ending, `hard-nl` is `(newline #f)` and so fails when
flattened, and `flatten` reaches a newline under `align`, `nest` and `reset`
(the reference's bug, fixed). `(pitch layout)` resolves a document to the layout
minimizing a cost objective and reports the cost and whether the search proved
minimality. `(pitch check)` compares two source *texts*.

The shape of the problem is set by that inheritance. A CST child sequence
interleaves data with whitespace and comments, and the translation's whole job is
to decide, for each trivia child, what it becomes: a separator that the layout
engine may choose to render as a space or a break, a forced break, a blank line,
or nothing at all.

Constraints from `CLAUDE.md` and `docs/DESIGN.md` that bear directly:

- Style tables are data, not code. Per-form layout rules go in the style grammar,
  not in `cond` branches on head symbols. This change ships no table, so the
  binding constraint is that it must not acquire one accidentally: there must be
  exactly one place a head symbol could ever be consulted, and today that place
  returns the same answer for every form.
- The declared-normalizations list is empty. Output tokens must match input
  tokens exactly, modulo whitespace. The translation therefore has no license to
  respell anything, and the emitter for a leaf is `verbatim` of its token text —
  not a re-print of its value.
- Every check compares against text re-read from the formatter's output. The
  pipeline must hand `check-output` the string it produced, never the tree it
  walked.
- Malformed input is refused, not guessed at.

## Goals / Non-Goals

**Goals:**

- A translation that is a pure function of the tree, total over the node kinds,
  and correct on malformed trees even though the pipeline will not format them.
- Comment placement specified as behavior, not as an emergent property of the
  cost objective. Where a comment goes must be predictable from the source, and
  must be the same on the second run as on the first.
- Idempotence argued at the document level rather than checked by comparing two
  strings and hoping. A fixpoint argument is a design property; a passing test is
  evidence for one.
- A seam for the style table that costs nothing to add later, and no per-form
  knowledge now.
- Enough observability to debug a bad layout: the pipeline reports what it ran,
  what failed, and whether the layout was tainted.

**Non-Goals:**

- Beautiful output for every form. With one generic shape, `cond` and `let` will
  look wrong. That is expected and is the table's job; what must be right here is
  that no comment moves, no token changes, and nothing crashes.
- A tuned cost objective. The default factory ships unchanged.
- Anything about dialects, files, or command lines.

## Decisions

### The translation reads token text and whitespace, never a token position

Classifying a comment as trailing-a-line or standing-on-its-own is a question
about whether a line ending separates it from the preceding datum. Two sources
answer it: the tokens' recorded line numbers, or the text of the whitespace leaf
between them. The whitespace leaf is chosen.

It is the more direct answer — whitespace is an ordinary child, so the fact is
sitting in the child sequence rather than needing arithmetic across two tokens.
It also keeps this layer independent of position correctness entirely: `(pitch
print)` imports nothing from `reader-source-position`, so a bug in the recorded
line numbers cannot produce a misplaced comment. And it dodges a real trap —
`docs/DESIGN.md` §3 warns that `token-end-line` is not "the last line the token
occupies" for a token whose text ends with a line ending, which is every line
comment, exactly the tokens this classification is about.

The consequence to accept: two data with no whitespace between them, as in
`(a)(b)` at top level, are adjacent, and the translation must not merge them into
`(a)(b)` — it must emit a separator anyway. That is handled by the separator
rules below, which derive the separator from the item sequence rather than from
the whitespace, and use whitespace only for the two questions it answers.

### Every leaf is emitted with `verbatim`, and `verbatim` goes in `(pitch doc)`

A leaf becomes `(verbatim (leaf-text l))`, where `verbatim` splits the string at
line endings and joins the pieces with `hard-nl` under `reset`. For the
overwhelming majority of tokens the string contains no ending and `verbatim` is
`text`.

Three token kinds can legally carry an interior line ending: a string literal
written across lines, a `#|...|#` block comment, and a `#;` datum comment eliding
a multi-line datum. For all three, the continuation lines must be emitted with no
added indentation, which is what `reset` gives. Indenting inside a string would
change the string's value — a meaning change, not a layout one. Indenting inside
a comment would rewrite comment contents, which `README.md` lists as a
prohibition rather than a preference. So the rule is the same for all three and
needs no discrimination: pitch reproduces the interior of a multi-line token and
re-derives nothing inside it.

**Why in `(pitch doc)` rather than in the printer.** `verbatim` is
Scheme-agnostic, is defined in terms of the core like every other derived
combinator, and is the sanctioned answer to a restriction the algebra itself
imposes — so it belongs where the restriction is. The alternative considered was
exporting the ending predicate and letting the printer build the document; that
exports the mechanism rather than the meaning, and two callers would then write
the same fold.

**A new library, `(pitch lines)`, came out of this.** The line-ending set turned
out to have four consumers, not two: `text` refuses one, `verbatim` splits at
one, layer 1 trims a trailing one before comparing token text, the printer splits
a line comment's terminator off, and the pipeline screens for an interior one it
cannot reproduce. `doc.sls` and `check.sls` each already carried a private copy,
with a comment in `doc.sls` noting that two definitions of "line ending" in one
codebase is a divergence waiting to happen. Adding a third for the printer would
have been the copy that drifts, since it is the one nothing else exercises.

The obvious home would have been `(pitch doc)`, which both new callers import
anyway — but `check` must not import the layout algebra, and that constraint is
what says the set does not belong to any of the four. So there is one definition,
in a library of its own, and `doc.sls` and `check.sls` now import it instead of
defining it. That is a pure refactor with no behavior change, and the whole
existing suite plus the differential oracle confirm it.

**What it does not preserve.** The engine renders a break as `#\linefeed` and
indentation as spaces. So a multi-line token whose interior endings are CR, CRLF,
NEL, LS or PS comes back with linefeeds, and its text no longer matches the
input's. This is real and is handled by refusing rather than by shipping a
normalization — see the pipeline decision below.

### A line comment is `verbatim` of its text minus one ending, then `hard-nl`

`comment-doc` strips exactly one trailing line ending — the same one-ending rule
layer 1 applies, with the two-character forms counting as one — and returns
`(concat (verbatim stripped) hard-nl)`. There is no branch that omits the break,
and a comment at end of file with no terminating ending gets one anyway, which is
also what makes a formatted file end in a newline.

This discharges `docs/DESIGN.md` §6's owed assertion, and it discharges it by
construction rather than by an `assert`, which is stronger. The assertion is
still written, at the one place where a caller could defeat the construction: the
item sequencer asserts that no separator is emitted after an item that ends in a
forced break. Both guards are cheap and they fail in different places, which is
the point of having two.

A consequence worth stating because it is load-bearing and free: `hard-nl` fails
under `flatten`, so a compound node containing a line comment anywhere in its
children has no flat alternative at all. `(a ; note⏎ b)` cannot be laid out on
one line — not because a rule forbids it, but because the document denotes no
such layout. The most dangerous bug in a Lisp formatter is unrepresentable in
the algebra rather than merely prohibited by a check.

### Items and separators: the child sequence becomes a list of items

The sequencer folds a child list into items. An item carries a document, the
number of blank lines that preceded it, and whether it ends in a forced break.

- A **datum child** starts a new item.
- A **whitespace child** never becomes an item. It contributes two facts: whether
  it contains a line ending, and how many blank lines it represents.
- A **comment child** — line comment, block comment, `#;`, or directive — with no
  line ending between it and the preceding datum is *attached to that item*,
  separated by a single non-breakable space. It stays where it was written, on
  the same line as the code it annotates.
- A **comment child** with a line ending before it, or with no preceding datum in
  this node, becomes an item of its own.

Items are then joined by a separator that is `nl` — a soft newline, rendered as a
space when flat and a break when not — except that after an item ending in a
forced break the separator is nothing, because the break has already been
emitted. Blank lines are emitted as additional `hard-nl`s before the item that
follows them.

The alternative considered was attaching comments to the *following* datum, as
Roslyn-style leading trivia would. It was rejected for the same reason the CST
rejected trivia attachment altogether: `; a trailing note` after code on the same
line belongs to the code before it, and every reader of the file believes so.
Attaching by direction rather than by observed line placement gets one of the two
cases wrong always.

### The default compound shape is three alternatives, priced apart

A compound node `(head a b c)` denotes:

1. **flat** — everything on one line, single spaces.
2. **aligned** — `head` and the first argument on the opening line, remaining
   arguments aligned under the first argument's column.
3. **hanging** — `head` on the opening line, every argument on its own line
   indented from the opening delimiter by `pp-tab`, taken as 2.

`(alt flat aligned hanging)` and let the cost objective choose is the whole
reason Πe was ported: Wadler-style `group` commits greedily and cannot see the
cost it imposes downstream, and this is the first place that difference shows up
on real input. A long head symbol pushes the aligned form deep into the right
margin, and only a global comparison notices that hanging is cheaper.

**Determinism is not free here, but it turns out not to need buying.** The
default objective is squared overflow, then line count, compared
lexicographically. The worry was that aligned and hanging would frequently tie
and the choice would fall to whatever order the resolver's frontier happens to
have — a stable function of the implementation, but not a fact anyone should
rely on, since it changes the moment the resolver is optimized.

They cannot tie. A `newline` is a break, not a choice; only `group` produces the
flat variant, and it flattens every separator at once. So a compound denotes
exactly three renderings, and hanging is aligned plus one break — the one before
the first argument — with the same breaks everywhere else. Hanging is therefore
always exactly one line taller and never wider, so under an objective ranking
overflow before height it wins only when it strictly reduces overflow. Equal
cost happens only where the two render identically anyway.

**The `cost` penalty this design originally called for is not merely unnecessary
but wrong.** `(cost n d)` takes `n` in the *cost factory's own representation* —
`(badness height)` for the default factory. A penalty in the printer would have
hard-coded that representation, coupling the translation to one factory and
breaking the parameterization `layout-cost` exists to provide. The translation
must not know what a cost looks like.

A compound with no children is its delimiters concatenated. A compound with one
child has no separator to break at, so all three alternatives coincide and the
constructors' simplification collapses them.

**No `fill`.** A long quoted data list will get one element per line, which is
not what anyone wants for `'(1 2 3 ... 100)`. `fill` is an SRFI 272 terminal and
arrives with the table; adding it here would mean deciding *which* forms are
filled, which is precisely the per-form knowledge this change must not acquire.

### Delimiters, and where the closing one goes

The opening delimiter's text is emitted from its token, so `(`, `[`, `#(`,
`#vu8(` and `#u8(` are reproduced with no dialect knowledge anywhere. The closing
delimiter is concatenated directly after the last item with no break opportunity,
so it trails the last element rather than sitting on a line of its own — black's
shape, and the one the eventual dedented-closer reward will have to argue with.

An absent closing delimiter is emitted as nothing. This only arises on a
malformed tree, which the pipeline refuses, but the translation must remain
total.

The exception is forced: when the last item ends in a forced break — a trailing
line comment before the close — the closing delimiter necessarily starts a new
line, indented to the compound's own indentation. `(a ; note⏎)` is the smallest
case, and it is the reason the close is emitted outside the `align`.

### A prefix binds tightly; the dot binds to what follows it

`'x` is `(concat marker datum)` with no separator, so a break can never appear
between an abbreviation and the datum it abbreviates. `#0=` is the same node kind
and gets the same treatment. When trivia sit between the marker and the datum,
they are sequenced by the ordinary item rules, which means `' ; why⏎ x` forces a
break — the only shape in which a prefix and its datum are on different lines, and
it is forced by the comment, not chosen.

The `.` of an improper list is an ordinary child of the list node, and the
sequencer binds it to the item that follows it, so `. b` is one item. Left as its
own item, `(a . b)` broken would render as `(a⏎.⏎b)`, and a dot alone on a line is
worse than useless. Binding forward also removes any path by which a break could
be placed between `.` and the datum in a way that changed the parse.

The dot is never emitted adjacent to its neighbours without a space. `(a .b)` and
`(a. b)` lex differently from `(a . b)`, which is exactly the class of defect
layer 2 exists to catch, and there is no reason to rely on the catch.

### The style seam is one function that ignores its argument

`(compound-shape node)` returns a shape descriptor, and the emitter dispatches on
the descriptor. Today it returns the same generic descriptor for every node
without examining it. When the table arrives, its body looks up the head symbol
and returns a richer descriptor; no other function in `print.sls` changes, and no
other function in `print.sls` may examine a head symbol.

This is `CLAUDE.md`'s "style tables are data, not code" made checkable rather
than aspirational: the question "does pitch branch on a head symbol anywhere it
should not" has a one-function answer.

### The pipeline refuses more than it formats

`format-source` returns two values — the formatted text, or `#f`, and a
`format-result` record carrying status, detail, and whether the layout was
tainted. Two values with a record for the details is `layout`'s existing shape,
and following it is worth more than any freshly designed signature.

The stages, in order, each with its own refusal:

1. **Tokenize and parse.** A non-empty diagnostics list is `unclean-parse`, text
   `#f`. `docs/DESIGN.md` §3: tolerant parsing is required, tolerant output is
   not.
2. **Screen for a foreign interior line ending.** A token whose text contains an
   interior CR, NEL, LS or PS is `unsupported-line-ending`, text `#f`. See below.
3. **Translate and lay out.** A document with no layout raises out of
   `(pitch layout)`; that is a bug in the translation, not a property of the
   input, so it is not caught and converted into a status. Taint is recorded and
   returned, not treated as a failure: the text is valid, and only the minimality
   claim was withdrawn.
4. **Check.** `check-output` over the input text and the produced text. A failure
   is `check-failed` with the mismatch or diagnostics as detail, and **text `#f`**
   — pitch does not return output it could not verify.

The check takes the string the printer produced. It is handed `output-text`, and
`output-text` is the value returned by `layout`, so there is no in-memory tree
anywhere on that path. The vacuousness trap `docs/DESIGN.md` §1 warns about is
avoided structurally: `(pitch format)` has no way to pass a tree to
`check-output`, because `check-output` does not accept one.

### Foreign interior line endings are refused, not normalized

Step 2 exists because of the `verbatim` limitation above. A file whose *inter-token*
line endings are CRLF is fine: those live in whitespace tokens, layer 1 filters
whitespace, and re-deriving them as linefeeds is a whitespace change, which is
the one thing pitch is allowed to do. But a CRLF *inside* a multi-line string or
block comment is part of a compared token's text, and emitting it as a linefeed
would change that text — a real divergence that layer 1 would catch after the
fact.

Three ways out were considered. Normalizing is out: it is a declared
normalization, the list is empty, and `CLAUDE.md` requires a proposal arguing for
each entry. Letting layer 1 catch it is out: the check would fire, so the file
would be refused anyway, but with `check-failed` — reporting a printer bug for
something that is a known unsupported input. Refusing up front is what ships,
because it names the actual reason and can be lifted cleanly later by teaching
`(pitch doc)` which ending to render, which is a change to the algebra and wants
its own proposal.

The scope is narrow enough to be worth stating: a CRLF file with no multi-line
string and no multi-line block comment formats normally.

### Blank lines survive at the caps, and everything else is re-derived

A whitespace leaf's blank-line count is its line-ending count minus one, floored
at zero. The cap is one inside a compound and two between top-level forms — the
`README.md` rule, which is black's. Leading blank lines at the start of a
document, and trailing ones before end of file, are dropped; a formatted file
ends with exactly one newline.

Preserving blank lines means emitting `hard-nl`, which removes the flat
alternative from any compound containing one. That is correct rather than
incidental: a form the author spaced out internally is a form that was not on one
line, and putting it on one line would delete the blank line we just promised to
keep.

### Idempotence is a fixpoint argument, not a hope

The document depends on exactly three properties of its input: each token's text,
whether a line ending separates two children, and how many blank lines a
whitespace run holds. Run the formatter on its own output and each is already at
its fixed point — texts are unchanged by construction, an attached trailing
comment is still emitted with no ending before it and so is still attached, an
own-line comment is still preceded by a break and so is still own-line, and blank
runs are already at or under the caps. The second run therefore builds *the same
document*, and the same document under the same factory lays out to the same
text, which `layout-resolution` already requires.

This is why layer 3 lands here rather than with the corpus work: the argument is
part of the design, and the test is evidence for the argument rather than the
whole of it. The place it could break is any future rule that moves a comment
relative to code — which layer 1 forbids anyway.

## Risks / Trade-offs

**A whole file is one document, and Πe's cost is polynomial, not linear.** →
Measured, and the mitigation this section originally proposed does not exist.
`src/pitch/reader.sls`, the largest file in the repository at 47KB: parse 1ms,
translate 33ms, layout 2027ms, check 29ms. Layout is essentially all of it, and
it scales roughly linearly at about 20KB of source per second — so the search is
not blowing up, it is simply not fast.

The proposed fallback — lay out each top-level form separately and join the
strings — was measured and saves nothing, because **an R6RS library is a single
top-level form**. `reader.sls` has exactly one, and so does every other library
in the repository, which is to say every file pitch is actually for. The forced
`hard-nl` between top-level forms is still worth having for the frontier, but it
is not a performance escape hatch.

So the figure is recorded and not acted on. The layout engine's own design
already put correctness and legibility ahead of performance parity with the
Racket original, which uses unsafe operations and a tuned memoization weight;
this is the profiling it said would come later. Two seconds on the worst file in
the repository is tolerable for a formatter that has no CLI yet, and optimizing
the resolver is a change to `layout-resolution`, not to the printer.

**One generic shape produces output nobody would accept for `cond` or `let`.** →
Accepted deliberately. It is the graceful-degradation behavior `docs/DESIGN.md`
§5 requires regardless, so it must exist and be correct; the table change makes
it rare rather than making it unnecessary. The tests assert on losslessness and
placement, not on beauty, so the table's arrival will not invalidate them.

**The three-way alternative could make output feel unpredictable.** → The cost
penalty on hanging makes the tie-break explicit rather than emergent, and the
tests pin the specific inputs at which the choice flips. If it still feels
unstable in practice, the remedy is dropping to two alternatives, which is a
one-line change and no spec change.

**Attaching a trailing comment with a non-breakable space can overflow the page
width.** → It can, and it must: moving the comment to the next line would change
which code it documents, which layer 1 refuses. The overflow is priced by the
cost objective, so the rest of the form breaks to make room, and the result is
tainted only if nothing fits. Reporting taint rather than hiding it is why
`format-result` carries it.

**`format-source` returning `#f` on a check failure loses the output a developer
would want to look at.** → The status and the mismatch index say where it went
wrong, which is what layer 1 was built to report. Returning unverified text under
any name invites a caller to write it to a file, and that is the failure mode the
whole check apparatus exists to prevent. A debugging entry point that returns the
unchecked text can be added later if it turns out to be needed; it is not the
one the pipeline exposes.

## Open Questions

- Whether output should reproduce the input's line ending rather than always
  emitting a linefeed. Answering it means `(pitch doc)` carrying a line ending,
  which is an algebra change with its own proposal. Until then, step 2 refuses
  the inputs where the difference is observable.
- Whether the closing delimiter should ever be dedented onto its own line. The
  dedented-closer reward `docs/DESIGN.md` §6 anticipates is a cost-objective
  question, and tuning the objective needs a corpus.
- Whether `pp-tab` and `pp-max-tab` become real configuration or stay constants.
  `README.md` says the configuration surface is width and dialect; the hanging
  indent is 2 here and is not exposed.
- Whether a `#;` should bind to the datum that follows it the way a prefix does.
  Today it is an ordinary item, which is right when it stands alone on a line and
  arguable when it elides the next form on the same line. Real input should
  settle it.
