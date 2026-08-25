## Why

Pitch currently treats resemblance to Black's closed configuration surface as a
design goal, even though its per-form style table is already declarative data and
is the part users most need to adapt for project and library macros. Keeping that
data compiled into `(pitch style)` makes ordinary customization require a source
edit and rebuild, so configuration should become an explicit, bounded input to
the formatter instead.

## What Changes

- Add a Scheme-native configuration file for page width, dialect, and
  dialect-aware SRFI 272 style-table entries, with optional entries able to add,
  replace, or remove a default form style.
- Ship Pitch's current defaults as an external data file that is parsed and
  validated at startup rather than embedding the defaults and style entries in
  the tool's Scheme libraries.
- Add `--config PATH`; resolve settings from the shipped defaults, then the
  named configuration, then explicit `--width` and `--dialect` overrides. Do not
  add implicit directory or home-directory discovery.
- Parse configuration as data with Pitch's own reader path, never with host
  `read`, `load`, or `eval`, and reject an unreadable or malformed configuration
  before reading or writing any source input.
- Pass an explicit resolved configuration through the CLI, formatting pipeline,
  and CST translation boundary while keeping the CST and layout engine unaware
  of dialect and configuration.
- **BREAKING**: library callers must provide a resolved configuration (or load
  the shipped default) instead of relying on page-width, dialect, and style-table
  defaults compiled into the formatting libraries.
- Revise `README.md`, `docs/DESIGN.md`, and `AGENTS.md` to replace the
  Black-inspired prohibition on configuration with a bounded declarative
  configuration principle. Safety checks, token preservation, normalization,
  comment contents, and code ordering remain non-configurable.

## Capabilities

### New Capabilities

- `configuration-loading`: The configuration data model, external default and
  user-file loading, validation, composition, and precedence rules.

### Modified Capabilities

- `cli-invocation`: Add `--config`, configuration-derived defaults, CLI
  overrides, and fail-before-source behavior for configuration errors.
- `style-grammar`: Construct dialect tables from external configuration and
  support declarative replacement and removal without weakening the closed
  style grammar or data-only layering.
- `format-pipeline`: Consume an explicit resolved configuration and selected
  style table rather than compiled-in width, dialect, and table defaults.

## Impact

- Affects `src/pitch/style.sls`, `src/pitch/format.sls`, `src/pitch/print.sls`,
  `src/pitch/cli.sls`, `src/pitch/main.sps`, installation/wrapper rules, and a
  new configuration library and shipped default data file.
- Expands the CLI host boundary to read configuration while preserving the
  in-memory host test seam and the rule that only the CLI performs file I/O.
- Requires configuration, style, format, CLI, install, and end-to-end tests,
  including proof that every configuration error leaves all source files
  untouched.
- Changes the public library API and the project's documented design precepts;
  it adds no third-party dependency and does not touch `vendor/laesare/`.
