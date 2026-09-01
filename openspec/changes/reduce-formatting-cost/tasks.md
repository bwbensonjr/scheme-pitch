## 1. The benchmark, before anything is profiled

- [ ] 1.1 Assemble the corpus under `tests/bench/`: a ~200-line member, one of
      ~1,000, one of ~2,500 of hand-written code, and a data-dense member of
      ~2,500 lines that is a handful of very large forms. Check them in
- [ ] 1.2 Any generated member is produced by a checked-in script, so the corpus
      can be rebuilt and reviewed rather than trusted
- [ ] 1.3 Add `make bench`: format each member, report line count, wall time and
      cost per thousand lines, plus the host and Scheme implementation
- [ ] 1.4 Report the two derived ratios directly — largest to smallest per-line
      cost, and data-dense to comparable code — since those are what the
      requirements are stated in
- [ ] 1.5 Report peak memory per member alongside wall time, so a time-for-space
      trade later is visible rather than discovered by a user
- [ ] 1.6 Confirm `make bench` is not invoked by `make test`, directly or through
      any target it depends on
- [ ] 1.7 Run it and record the baseline. Confirm it reproduces the shape issue
      #15 reported — per-line cost rising with size, and the data-dense member
      worse still. If it does not reproduce, the corpus is wrong and this section
      is not done
- [ ] 1.8 Note the baseline in the change record before either of the other two
      changes filed from this source lands, so their added cost is measurable
      against it

## 2. The profile

- [ ] 2.1 Profile the largest hand-written member and the data-dense member
      separately. Two profiles, because the two are the discriminating pair
- [ ] 2.2 Attribute cost across the pipeline stages — tokenize, parse, translate,
      layout, check — before attributing it within any one of them
- [ ] 2.3 Test the size hypothesis: vary file size with form size held roughly
      constant, and record how cost grows
- [ ] 2.4 Test the shape hypothesis: format a single form of N elements for N,
      2N and 4N, and record the curve. This is the measurement that separates a
      per-form quadratic from general overhead
- [ ] 2.5 Check the two candidates `docs/DESIGN.md` §6 names — memoization scope
      and granularity in `layout.sld`, and quadratic accumulation in the token
      vector, the CST child sequences, or `cst->text` — and record for each
      whether it is supported or refuted
- [ ] 2.6 Write the finding down, whatever it is, including "neither guess was
      right". This is a deliverable of this change and not a step toward one

## 3. The fix

- [ ] 3.1 State the term the profile named and the expected effect on each of the
      two ratios *before* writing the fix, so the result can be compared against
      a prediction rather than rationalized after
- [ ] 3.2 If the fix touches memoization scope, write the delta against
      `layout-resolution`'s "Memoization is per call and does not outlive it" and
      its correctness argument first, and add it to this change. Do not implement
      ahead of that delta
- [ ] 3.3 If the fix touches `src/pitch/reader.sld`, update its header change list
      in the same commit and confirm `make vendor-diff` stays legible and
      `make vendor-verify` clean
- [ ] 3.4 Implement the fix. One term at a time, each measured separately, so a
      second change cannot be credited with the first one's improvement
- [ ] 3.5 If the profile is inconclusive, stop here. Land the benchmark and the
      recorded finding, report that the fix is deferred and why, and do not
      optimize a candidate on the strength of a plausible story. This is a
      legitimate outcome of this change

## 4. Verification that nothing else moved

- [ ] 4.1 `make test` passes in full
- [ ] 4.2 Format the whole corpus with the build from before the fix and the build
      after, at every page width the suite exercises: byte identical
- [ ] 4.3 `make oracle-layout` reports every entry agreeing on text, cost and
      taint — the objective and the computation width are untouched
- [ ] 4.4 Confirm both output checks still run on every file, that no refusal was
      relaxed, and that no verification became conditional
- [ ] 4.5 Idempotence still holds across the corpus
- [ ] 4.6 Record peak memory before and after. If the fix trades space for time,
      say so with the number

## 5. Acceptance against the reported measurements

- [ ] 5.1 `make bench` reports a largest-to-smallest per-line ratio of 1.5 or
      less, and no intermediate member above that bound
- [ ] 5.2 The data-dense member is within 1.5× of comparable code, against the
      measured baseline of about 1.9
- [ ] 5.3 Re-run issue #15's exact measurement — Emit's eight named files,
      `--check`, one invocation per file — on a comparable host, and put the new
      seconds beside the reported ones. Like-for-like, or say where it differs
- [ ] 5.4 Report the aggregate for the 32-file, 13,229-line set against the
      reported 442 s sequential and 150 s at `-P4`
- [ ] 5.5 State plainly whether a pre-commit hook over a tree, and editor-on-save
      for a 1,500-line file, are now viable. Those are the three uses the issue
      says are shaped by this number, and the answer is the point of the change

## 6. Documentation

- [ ] 6.1 `docs/DESIGN.md` §6: it records the objective and says nothing about
      resolution *time*. Add the finding, and update the two divergences noted in
      `layout.sld`'s header if the fix touched either
- [ ] 6.2 Document `make bench` in `make help` and in the testing section of
      `CLAUDE.md`, next to `make test` and `make oracle-layout`
- [ ] 6.3 Record what the benchmark does not cover, so a later reader does not
      over-read a green ratio: startup cost, multi-file invocation, and memory
- [ ] 6.4 Reply on issue #15 with the profile finding and the before/after table,
      including the case where the fix was deferred
