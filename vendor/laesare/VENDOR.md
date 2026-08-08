# laesare

Upstream:  https://gitlab.com/weinholt/laesare
Mirror:    https://github.com/bwbensonjr/laesare
Author:    Gwen Weinholt
License:   MIT (see LICENSE.txt)
Vendored:  tag v1.0.3, commit 15a75835dca64319be607d9d5285ab2c1db9a003

Every file in this directory except this one is an unmodified copy of the
upstream tree at the tag above, extracted with `git archive`. Nothing here
is edited. The derived reader used by pitch lives at `src/pitch/reader.sls`;
see its header for the list of changes.

`make vendor-diff` diffs the pristine reader against the derived one, which
is the authoritative statement of what pitch changed.

## Where changes are made

Develop directly in `src/pitch/reader.sls`. The `recording-tokens` branch in
the mirror is not kept in sync commit-by-commit; port the finished change to
it when there is something worth proposing upstream, using `make vendor-diff`
as the patch.

`make vendor-diff` is now that candidate patch. It carries source-text
recording on tokens and a fix for line counting on non-linefeed line endings,
against `v1.0.3`. Two thirds of the removed lines are the mechanical rename of
`get-token` to `get-token*`; the datum-reading path is untouched, evidenced by
the upstream test suite passing unmodified apart from library names.

Both are plausibly useful to anyone building tooling on laesare rather than
feeding psyntax, so the diff is kept legible with that in mind.

## Refreshing the pin

    git -C ../laesare fetch upstream
    git -C ../laesare merge upstream/master        # on master
    git -C ../laesare archive <new-tag> reader.sls writer.sls LICENSE.txt tests \
      | tar -x -C vendor/laesare

Then re-run `make vendor-diff` and reapply the changes to `src/pitch/reader.sls`
by hand. Update the tag and commit recorded above, and in the derived file's
header.
