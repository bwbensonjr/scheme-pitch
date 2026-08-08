Each numbered group is intended to land as one named commit, so the series stays
legible enough to port to the `recording-tokens` branch of the GitHub mirror.
Run `make vendor-verify` before and after the series; `vendor/laesare/` must stay
untouched throughout.

## 1. Regression baseline

Two deviations from the plan, found while porting:

- The suite imports `(srfi :64 testing)`, which upstream resolves through Akku.
  Neither Akku nor chez-srfi is available, and the suite uses only five SRFI 64
  forms. `tests/runner.sls` is therefore a purpose-written harness providing
  exactly those forms, not a port of upstream's runner. It records failures and
  raised conditions and continues, so a run always yields a full tally.
- The `read-files` test hardcodes `"reader.sls"` relative to the working
  directory. It now opens `src/pitch/reader.sls`, so `make test` must be run
  from the repo root.

- [x] 1.1 Copy `vendor/laesare/tests/test-reader.sps` into `tests/`, changing
      the library imports to `(pitch reader)` and `(tests runner)` and the
      `read-files` path; write `tests/runner.sls` as a minimal SRFI 64 subset
- [x] 1.2 Add a `make test` target that runs the suite under `chez --libdirs`
- [x] 1.3 Confirm the suite passes green against the unmodified derived reader,
      and record the pass count as the baseline to regress against:
      **196 passed, 0 failed**
- [x] 1.4 Confirm `make vendor-verify` passes and `make vendor-diff` still shows
      only the header and library rename

## 2. Reader state for recording

- [x] 2.1 Add an absolute character offset field and a per-token text accumulator
      field to the reader record at `src/pitch/reader.sls:113`
- [x] 2.2 Bump the `nongenerative` UID to a fresh value in the same edit, so a
      stale compiled library cannot load against the new field layout
      (now `reader-v0-5bc24d56-39f5-4d48-bfa8-0f7c48f706f6`)
- [x] 2.3 Extend the record protocol to initialize offset to 0 and the
      accumulator to empty
- [x] 2.4 Export an accessor for the current offset
- [x] 2.5 Update `get-char` to increment the offset and append the consumed
      character to the accumulator, guarded on the value being a character so
      the end-of-file object is not recorded
- [x] 2.6 Re-run the baseline suite; it must still pass, since nothing observable
      has changed yet: **196 passed, 0 failed**

## 3. Line and column correctness

- [x] 3.1 Extend `get-char` to treat `#\return`, U+0085, U+2028, and U+2029 as
      line endings, advancing the line and resetting the column
- [x] 3.2 Handle CRLF as a single line ending using lookahead, without consuming
      the line feed twice. Implemented without extra reader state: when a
      carriage return is followed by linefeed or next-line, the increment is
      deferred to the second character rather than remembering the first.
      Carriage-return-plus-next-line is covered too, matching `get-comment`
      and the RnRS grammar.
- [x] 3.3 Add tests for each line-ending form, including CRLF counting once and
      positions reported after a comment containing non-line-feed separators.
      Added as `tests/test-recording.sps` so the upstream baseline stays
      unmodified; wired into `make test`. Verified the new tests fail against
      the previous `get-char` (10 of 20 failed), so they are not vacuous.
- [x] 3.4 Re-run the baseline suite: **196 passed, 0 failed**, plus 20 new

## 4. Token record and the get-token split

The accumulator is now `#f` when no `get-token` call is in progress, rather than
always a list. Without this the datum path would accumulate every character of
the input with nothing to reset it, since `get-lexeme` deliberately does not go
through the wrapper. Holding `#f` means the datum path allocates nothing and
matches upstream exactly. The reader record's field layout is unchanged, so the
UID from group 2 still stands. `read-annotated` and `read-datum` disarm on entry
to cover a `get-token` call that escaped by raising.

- [x] 4.1 Define a token record type with kind, raw text, start offset, end
      offset, and parsed value, plus its accessors, and export them
- [x] 4.2 Rename the existing `get-token` to `get-token*` and repoint all 11
      internal recursive tail-calls at `get-token*`
- [x] 4.3 Point `get-lexeme` at `get-token*`, not at the new wrapper; this is
      required both to keep the datum path unchanged and to stop the accumulator
      being reset partway through a `#;` token
- [x] 4.4 Define the new `get-token` wrapper: note the start offset, reset the
      accumulator, call `get-token*`, materialize the raw text, note the end
      offset, and return a token record
- [x] 4.5 Verify no remaining call site inside the library reaches the wrapper by
      accident: the only occurrences of bare `get-token` are its own definition
      and three comments
- [x] 4.6 Re-run the baseline suite; `read-annotated`, `read-datum`, and
      `detect-scheme-file-type` must be unaffected: **196 passed, 0 failed**.
      The two lexing helpers in the baseline had to be repointed at
      `get-token*`, since they are direct callers of the exported `get-token`
      and this change is breaking for those by design.

## 5. Round-trip tests

- [ ] 5.1 Add a helper that tokenizes a string to end of input and concatenates
      the raw text of every token
- [ ] 5.2 Assert the offset span of every token indexes back to its own raw text
- [ ] 5.3 Round-trip the collapse cases individually: radix prefixes (`#xff`),
      string escapes (`"\x41;"`), char-name spellings (`nul`/`null`,
      `linefeed`/`newline`, `esc`/`escape`), `#t`/`#true` and `#f`/`#false`,
      `|foo|` versus `foo`, and bracket shapes
- [ ] 5.4 Assert that in each collapse case the parsed value is still the value
      the vendored reader produced, so recording did not displace parsing
- [ ] 5.5 Round-trip atmosphere: leading and trailing whitespace, line comments,
      nested `#| |#` comments, `#;` datum comments including the full commented
      span, `#!r6rs` and `#!fold-case` directives, shebang lines, and Guile
      `#! !#` comments in permissive mode
- [ ] 5.6 Round-trip malformed input in tolerant mode, confirming the discarded
      prefix is attributed to the following token and nothing is lost
- [ ] 5.7 Round-trip whole files: the vendored reader sources themselves are
      convenient real-world inputs
- [ ] 5.8 Assert dialect gating is unchanged, for example `#vu8(` rejected in
      `r7rs` mode

## 6. Documentation and provenance

- [ ] 6.1 Update the change list in the `src/pitch/reader.sls` header to describe
      the recording change, replacing the "not implemented yet" placeholder
- [ ] 6.2 Review `make vendor-diff` output end to end and confirm it reads as a
      reviewable changeset rather than an incidental rewrite
- [ ] 6.3 Note in `vendor/laesare/VENDOR.md` that the diff is now the candidate
      upstream patch
- [ ] 6.4 Confirm `make vendor-verify` still passes
