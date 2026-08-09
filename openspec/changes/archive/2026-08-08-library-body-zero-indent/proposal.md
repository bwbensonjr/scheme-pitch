## Why

Pitch was run over its own source for the first time, and the most visible thing
it did was indent every library body two columns. This codebase — like most R6RS
code — was written with library bodies flush at column 0, because a library wraps
an entire file and indenting it costs two columns on every line of the project in
exchange for marking a nesting level nobody can forget: there is exactly one
library per file and it ends at the last line.

That is a style decision, and pitch has a place for style decisions. It is the
style table, and today the table cannot express this one. `body` means "beneath
the head, indented two", and it is the only tail terminal a form like `library`
can use.

## What Changes

- **A new tail terminal in the style grammar, `body0`.** It denotes the same
  thing as `body` — one element per line, each looked up as an expression —
  except that the tail is indented **zero** columns from the opening delimiter
  rather than two. It is a terminal in the notation, available to any entry in
  any table, not a property of any particular form.

- **`library` and `define-library` use it.** The R6RS `((library) (_ d . body))`
  becomes `(_ d . body0)`, and the R7RS `((define-library) (_ d . body))` the
  same. They are one construct under two spellings, both wrap a whole file, and
  styling one flush and the other indented would be an inconsistency nobody
  chose.

- **BREAKING for output, in the only sense pitch has one.** Every library in
  every file re-indents. This is whitespace, which is the one thing pitch is
  permitted to change, so no safety check is affected and the declared-
  normalizations list stays empty — but every project formatted by the previous
  version will produce a large diff on its next run. That is the point of the
  change rather than a side effect of it.

- **Pitch's own sources are reformatted under the new style**, because `make
  format` covers exactly the files whose libraries are about to move.

**The honest part: this extends SRFI 272's notation, and `style-grammar`
currently forbids that.** The existing requirement says the system "MUST NOT
introduce a notation of pitch's own alongside it", and this change amends that
sentence. It is worth doing rather than working around for one reason: the
alternative is a printer that asks "is this head `library`?", and `CLAUDE.md`
prohibits that outright — style tables are data, not code, and per-form layout
rules go in the grammar, not in `cond` branches on head symbols. Given a rule
that some form's body is not indented, the only place it can live *is* the
notation. So the choice is not "extend SRFI 272 or don't"; it is "extend the
notation, or violate the layering invariant". The amended requirement keeps the
constraint that matters — the grammar is closed, every terminal is enumerated,
and nothing outside the enumeration is accepted — and gives up only the claim
that the enumeration is precisely SRFI 272's.

SRFI 272 is explicit that its layout algorithm is unspecified, so it was never
going to answer this question; pitch already supplies every terminal's layout
semantics itself. Adding a terminal whose meaning differs only in an indent is a
smaller departure than it sounds.

Explicitly not in scope:

- **`import` and `export`.** They sit inside a library body and are ordinary
  forms; nothing about them changes.
- **Making the indent configurable.** `CLAUDE.md` bounds configuration at width
  and dialect. `body0` is a second constant in the table, not a knob.
- **A general "indent by N" terminal.** Two indents exist because two are
  motivated. A parameterized one invites a third with no argument behind it.
- **Any change to the generic shape.** A form with no table entry is unaffected.

## Capabilities

### Modified Capabilities

- `style-grammar`: the notation gains the `body0` terminal, and the requirement
  that the grammar is exactly SRFI 272's — introducing no notation of pitch's own
  — is amended to allow this one enumerated extension while keeping the grammar
  closed and every terminal accepted-or-rejected by enumeration.
- `style-layout`: the requirement that a broken tail is indented two columns
  becomes a requirement that the indent is determined by the tail terminal — two
  for `body` and the clause terminals, zero for `body0` — still measured from the
  opening delimiter, still never from the head, still a constant of the
  implementation rather than configuration. The table entries for `library` and
  `define-library` are named as using it.

### New Capabilities

None. This is a change to what two existing capabilities require, not a new one.

## Impact

- `src/pitch/style.sls` — `terminal-tail` gains `body0`; the `tail` record gains
  the property distinguishing the two indents; the R6RS `library` and R7RS
  `define-library` entries change their tail. The grammar comment at the top of
  the library is updated, including the note about which parts are SRFI 272's.
- `src/pitch/print.sls` — `styled-body` reads the indent off the tail rather than
  using the `hanging-indent` constant unconditionally. No head symbol appears.
- `tests/test-style.sps` — `body0` accepted by the grammar, rejected spellings
  still rejected, and the two library entries carrying it.
- `tests/test-print.sps` — a `library` and a `define-library` broken across lines
  with their bodies at the opening delimiter's column, and a `when` or `define`
  still at two, so the change is shown to be confined to the new terminal.
- `src/pitch/*.sls`, `src/pitch/main.sps` — reformatted by `make format` under
  the new style. Mechanical, and verified by the safety checks per file.
- `openspec/specs/style-layout/spec.md` — its Purpose paragraph states the
  two-column rule as unconditional and goes stale with this change; it is
  corrected when the deltas are synced.
- `src/pitch/reader.sls`, `tests/`, `vendor/laesare/` — untouched, per
  `FORMAT_SOURCES`.
- `README.md` — no change; it documents width and dialect, and neither moves.
