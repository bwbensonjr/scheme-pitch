## Why

Pitch is currently an R6RS application launched through Chez Scheme, so Emit cannot compile its libraries or deliver its executable even though Emit now implements the R7RS-small facilities used by most of Pitch's core. Porting Pitch to one R7RS-small application target avoids maintaining two library systems and makes Pitch a real integration workload for Emit.

## What Changes

- **BREAKING**: Make the maintained Pitch application target Emit's R7RS-small subset, using `define-library` units and an R7RS program entry; stop supporting Chez as a runtime or installation target for the complete application.
- Retain Chez only where it is an independent development oracle: the pristine laesare reader regression, differential reader/datum checks, and other explicitly host-oracle tests.
- Add an Emit manifest and build, run, test, and install paths that compile Pitch's library closure once, run it through `emit run`, and produce a standalone `pitch` executable through `emit build`.
- Preserve the existing CLI contract, including directory traversal, symlink avoidance, unchanged-file suppression, refusal without writes, and same-directory atomic replacement. The Emit entry adapter will use a narrow external filesystem capability supplied by a prerequisite Emit change rather than moving operating-system policy into the formatter core.
- Replace R6RS-only condition, record, hash-table, sorting, list-helper, bitwise, fixnum, and port spellings with R7RS-small facilities or small Pitch-owned modules whose interfaces express the operation Pitch needs.
- Keep `src/pitch/reader.sls` as the authoritative derived laesare reader and keep its upstream diff reviewable. Generate the Emit library form from that source through a checked, deterministic adapter rather than maintaining a second reader implementation or editing `vendor/laesare/`.
- Make numeric tokenization independent of the host numeric tower. Valid R6RS/R7RS numeric lexemes that Emit cannot represent remain accepted and lossless through an opaque Pitch numeric value, while representable numbers continue to project to host numbers.
- Port Pitch-specific tests to the Emit target, add development-run/AOT parity coverage, and retain the required vendor integrity and reader-baseline gates.

## Capabilities

### New Capabilities

- `emit-application`: Building, running, testing, packaging, and installing the complete Pitch application with Emit while preserving the command-line and safety contracts.

### Modified Capabilities

- `token-source-recording`: Numeric tokens may carry a Pitch-owned opaque value when a valid source number is outside the host numeric tower, without changing their kind, text, or span.
- `cst-datum`: Projection admits the opaque numeric value only for valid numbers the host cannot represent, while retaining host values for every representable datum.
- `datum-equivalence`: Layer 2 compares independently re-read projections containing opaque numeric values and remains cycle-safe without relying on Chez's numeric tower.

## Impact

The change affects all application library declarations and imports, the derived-reader build adapter, numeric lexing and projection, exception and collection utilities, the real filesystem host, tests, the Makefile, installation layout, and documentation. It adds a build-time/runtime dependency on Emit and on a separately specified Emit filesystem extension for directory inspection and atomic replacement; it does not modify Emit or vendored laesare in this repository. Existing R6RS consumers of Pitch libraries and the Chez-based executable/install path must migrate to the Emit-built program.
