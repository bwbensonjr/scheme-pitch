## Context

See `proposal.md` for motivation. Today `(pitch style)` embeds and constructs
three process-global tables at library initialization, `(pitch format)` embeds
width 88 and dialect `common` as optional-argument defaults, and the CLI passes
those two scalar values to every source. The style grammar is already a pure,
closed data language, but there is no operation that reads its advertised
on-disk form.

The change crosses the CLI, pure formatting API, style table construction,
installation, and project doctrine. It must preserve the stronger existing
boundaries: only the CLI performs file I/O; no runtime path calls a host Scheme
reader; `(pitch style)` can name neither CSTs nor documents; configuration is
resolved before source processing; and neither the CST nor layout engine can
observe a dialect.

## Goals / Non-Goals

**Goals:**

- Make all current user-facing defaults and head-to-style mappings installed
  data that can be inspected and overlaid without rebuilding Pitch.
- Give library and CLI paths one immutable resolved configuration value.
- Keep validation eager and diagnostics attributable to a configuration path.
- Preserve Pitch's output byte for byte when no user configuration is supplied.
- Make the new bounded configuration principle precise enough for `AGENTS.md`
  to remain an enforceable invariant rather than a slogan.

**Non-Goals:**

- Implicit project, parent-directory, home-directory, or XDG discovery.
- SRFI 272's registry or `;; * pp-styles:` magic comments.
- Arbitrary Scheme expressions, includes, inheritance between files, or plugins.
- Configuration of safety checks, declared normalizations, token spelling,
  comment contents, ordering, the cost function, computation width, or terminal
  indent values.
- Changing any style terminal's rendering semantics or adding another terminal.

## Decisions

### Use one versioned datum, not executable Scheme

Both the shipped defaults and a user overlay use this shape:

```scheme
(pitch-config 1
  (width 88)
  (dialect common)
  (styles common
    ((define) (_ h . body))
    ((project-let) (_ i? fc* . body))
    ((unwanted-default) remove))
  (styles r6rs ...)
  (styles r7rs ...))
```

`pitch-config` identifies the file and the integer versions the schema. Repeated
top-level `styles` fields are permitted only for different dialects; every other
field is unique. Head groups retain the current table notation, so the shipped
data is mostly a mechanical move from `style.sls`. `remove` belongs to the
overlay language, not to the style grammar, and is consumed before
`style->shape` sees a value.

The configuration library takes text plus a diagnostic filename. It tokenizes
and parses with Pitch, refuses diagnostics, projects the one top-level CST datum
with `cst->datum`, validates the closed schema, and then invokes the style
compiler. It does not import a host reader and never evaluates a datum. This is
more work than using R6RS `read`, but using `read` would violate a repository
invariant and make reader behavior depend on the implementation running Pitch.

Alternatives rejected:

- R6RS source defining variables would make configuration executable and would
  require `load` or `eval`.
- JSON/TOML would add a parser and discard the already selected Scheme-native
  style notation.
- An unversioned association list would leave no clean way to reject a future
  incompatible schema.

### Separate raw overlays from resolved configuration

`(pitch config)` owns two concepts:

- A parsed overlay has optional width and dialect values and ordered style
  operations for `common`, `r6rs`, and `r7rs`.
- A resolved configuration has a required positive width, a valid dialect, and
  three immutable compiled style tables.

The constructors and fields of a resolved configuration are not independently
public; callers obtain one by resolving validated overlays. That makes an
invalid dialect or missing table unrepresentable at the formatting boundary.
The library API accepts configuration *text*, not paths or ports. The CLI reads
files through its host and passes their strings inward, preserving the rule that
only the CLI does I/O and keeping all parsing/composition tests in memory.

Resolution applies the shipped overlay, the optional user overlay, and finally
the explicit scalar CLI overrides. The shipped overlay is required to provide
width and dialect. A user overlay may omit either. CLI argument parsing records
whether width and dialect were explicitly present instead of filling them with
constants before resolution.

Alternatives rejected:

- Passing width, dialect, and tables separately would allow combinations that
  never passed configuration validation.
- Letting `(pitch config)` open paths would hide I/O below the existing host
  boundary and make fail-before-write behavior harder to observe.

### Compose table operations before formatting

Each style section becomes an ordered mapping from head to either a validated
style datum or a removal marker. Duplicate heads within one section are errors;
later *layers*, not later lines, have precedence.

Resolution compiles the final common mappings once. It constructs each dialect
table from those common bindings and then applies the default and user
dialect-specific operations in layer order. A removal deletes the current
binding even when it was inherited from common. Consequently a common
descriptor not overridden by a dialect is the same object reachable from both
dialect tables, preserving the existing sharing requirement.

This algorithm deliberately distinguishes an absent operation from `remove`.
Treating both as false would make it impossible for an R6RS overlay to request
generic formatting for a form inherited from common. Building the tables once
during resolution also keeps malformed or expensive configuration work out of
the per-form and per-file paths.

### Move default data beside the program entry point

The repository adds `src/pitch/default-config.scm`. Installation copies it next
to the installed `main.sps`; the checkout wrapper and installed wrapper already
invoke `main.sps` by a concrete path. `main.sps` derives the sibling default path
from its program pathname and supplies it to `run-cli`. The test entry point
supplies a synthetic path backed by the in-memory host.

This avoids compiling an installation prefix into a library, inventing an
environment variable, or exposing a private default-file option. A missing data
file is an installation/configuration error, never a reason to fall back to
embedded defaults. `make install` and `make uninstall` handle the file with the
other Pitch runtime assets.

### Parse arguments completely before loading configuration

Argument parsing remains pure and completes first. Help, version, unknown
options, missing option values, a repeated `--config`, incompatible
dispositions, and no-input invocations return before any configuration read.
For an operational invocation, the CLI reads and resolves the shipped default
and optional user file exactly once, then expands directory operands and reads
sources. An unreadable or invalid configuration reports status 2 and leaves the
source read/write log empty.

Explicit `--width` and `--dialect` values override the user file regardless of
argument order. `--config` is singular, and no file is discovered implicitly.
Supporting several overlay files would add ordering behavior without serving
the basic project-configuration use case.

### Pass tables at the edge, not dialect through lower layers

`format-source` takes the resolved configuration. It selects the configured
dialect table and passes width to layout and the table to CST translation.
`cst->document` and its recursive helpers take a table directly; they do not
receive a dialect or the configuration record. `(pitch print)` therefore loses
its dependency on process-global `dialect-style-table`, and `(pitch style)`
retains only grammar, descriptor, and table-construction operations.

This sharpens the existing dialect layering: configuration and dialect are
edge-level choices, translation sees only the data interface it needs, and the
CST and layout engine still cannot branch on either.

### Replace the anti-configuration precept with a bounded one

Documentation changes are part of the behavior migration:

- `README.md` continues to call Pitch opinionated and may cite Black as an
  influence, but removes “width and dialect is the whole surface” and “never
  grows configuration.” It documents the file schema, precedence, explicit
  `--config`, external defaults, and a project-macro example.
- `docs/DESIGN.md` revises the settled decisions in the dialect, style-table,
  numeric-knob, and CLI discussions. The SRFI 272 on-disk format now has a real
  loader; the registry and magic comment remain excluded.
- `AGENTS.md` removes the prohibition on configuration beyond width and dialect.
  Its replacement permits only width, dialect, and declarative per-form style
  data, requires configuration to be inert and validated before source I/O, and
  explicitly keeps safety, normalization, ordering, and comment contents
  non-configurable.

This changes one project precept at the user's direction without relaxing the
losslessness, safety-check, reader, malformed-input, or vendoring invariants.

## Risks / Trade-offs

- **[Every run now depends on an installed data file]** → Keep it beside
  `main.sps`, cover checkout and staged-install layouts, and fail with the exact
  path rather than silently changing output.
- **[Configuration parsing adds startup work]** → Read and compile both layers
  once per invocation, before walking operands; do no work per source beyond
  selecting an already-built table.
- **[A custom table can create surprising whitespace]** → Keep token and datum
  safety checks mandatory and unchanged; configuration can select only the
  existing closed style grammar, and unmatched forms still degrade generically.
- **[External data can drift from current output]** → Move the existing entries
  mechanically and run the whole corpus under the external defaults before
  adding customization tests.
- **[The direct library API breaks]** → Make the break explicit, provide a pure
  loader/resolver for callers, and update every repository caller in one change;
  this project has not promised a stable library ABI.
- **[Path derivation varies by invocation form]** → Test absolute, relative,
  checkout-wrapper, and staged-install program paths; normalize only enough to
  obtain the program's containing directory.

## Migration Plan

1. Add the pure configuration parser/resolver and move the current scalar and
   style defaults, unchanged, to `default-config.scm`.
2. Change style construction and the pure pipeline to consume resolved values,
   then prove default output and all safety checks are unchanged.
3. Add CLI loading, precedence, diagnostics, and `--config`, with negative host
   assertions before enabling installation use.
4. Update wrappers/install rules and verify a staged installation finds its
   external defaults.
5. Revise `README.md`, `docs/DESIGN.md`, and `AGENTS.md` together so no obsolete
   anti-configuration instruction remains.

Rollback is a normal code revert: the old embedded tables and optional format
arguments are restored together with the old wrappers. No user source or
configuration migration is destructive, and default-format output must be
identical on either side of the change.
