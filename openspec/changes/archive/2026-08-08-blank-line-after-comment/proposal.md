## Why

A blank line written after a comment does not survive formatting, and in one
case the formatter raises on valid input. Both come from the same arithmetic: a
whitespace run's blank-line count is taken as its line endings *less one*,
because normally the first ending terminates the preceding line. A line comment's
token text already carries the ending that terminated its own line, so after a
comment there is no such ending in the run to discount, and every ending in it is
a blank line.

`preserved-formatting` is one of the four things `README.md` promises pitch
preserves. Silently deleting a blank line the author wrote is the promise not
being kept.

## What Changes

- **The blank-line count discounts an ending only when the preceding token did
  not already carry one.** After an item that ends in a forced break — a line
  comment or a shebang — every line ending in the following whitespace run is a
  blank line. Everywhere else the count is unchanged.

- **A blank line opened by a comment's own break is emitted at indentation
  zero.** The resolver indents after every break, so the break that lands on a
  blank line must carry no indentation or the line holds the enclosing
  indentation as trailing whitespace and is not blank. `docs/DESIGN.md` §2
  already says this; it was true only for the break the joiner emitted, not for
  the one a comment emits itself. Whether a blank line follows is recorded on the
  item during the fold, so every emitter that materializes an item gets it
  right rather than each join having to remember.

- **The guard against a comment swallowing following code tests the branch it
  guards, not the document that branch returned.** `hard-breaks 1` reduces to
  exactly `hard-nl`, which is also the separator between top-level forms, so the
  identity comparison fired on a comment followed by one blank line — valid input
  the formatter then refused to lay out at all. The guarantee is unchanged and
  the assertion is now exact.

**These three are one change, not three.** The count bug currently masks the
emptiness bug: a blank line after a comment is dropped before anything can
indent it. Correcting the count alone would put trailing whitespace on blank
lines throughout, and correcting the count alone would also make the assertion
fire far more often. Landing them separately would ship a regression in between.

Explicitly not in scope:

- **The declared-normalizations list stays empty.** None of this respells a
  token; it changes which whitespace is emitted, which is the one thing pitch is
  allowed to change.
- **No change to what a blank line means, or to the caps.** One inside a form,
  two between top-level forms, as before.

## Capabilities

### Modified Capabilities

- `preserved-formatting`: the counting rule is corrected to discount an ending
  only where one was actually consumed by the preceding line, and a new
  requirement states that a preserved blank line contains no characters — which
  `docs/DESIGN.md` asserted and no requirement did.

No requirement in `comment-placement` changes. Its guarantee that a line comment
is always followed by a forced break, and that no separator is emitted after an
element ending in one, both still hold: the break is still unconditional, and the
assertion now tests exactly the condition that requirement states.

## Impact

- `src/pitch/print.sls` — `blank-count` replaces the inline arithmetic;
  `children->items` tracks whether the preceding child ended in a break and marks
  each item with whether a blank line follows; `leaf-doc` takes an optional flag
  to emit its forced break under `reset`; `item-doc` applies it to the item's
  last piece; the assertion in `gap` moves into the branch it guards.
- `tests/test-print.sps` — a section for blank lines after comments: the count at
  both caps, the absence of a blank where none was written, emptiness, and that
  the previously raising input does not raise.
- `tests/test-format.sps` — four idempotence cases covering comment-then-blank.
- `docs/DESIGN.md`, `README.md`: unchanged. §2 already described the intended
  behavior; this makes the code match it.
