## MODIFIED Requirements

### Requirement: A style is written in the SRFI 272 style notation

A style SHALL be a Scheme datum of the form `(_ . fmt-tail)`, where:

```
fmt-tail ::= body | body0 | fill | dc* | ec* | fc* | lc*
           | (i? . fmt-tail) | (fmt . fmt-tail)
fmt      ::= i | d | e | f | l | h | dc | ec | fc | lc | fmt-tail
```

The system SHALL accept every terminal in that grammar. No terminal outside it
SHALL be accepted.

The grammar is SRFI 272's, with one addition. `body0` is pitch's own and is not
an SRFI 272 terminal; every other terminal above is SRFI 272's, spelled as SRFI
272 spells it. The grammar SHALL remain closed: the terminals are a finite
enumeration, and a datum naming anything outside it is refused rather than
interpreted.

The addition is admitted for one reason and its scope is bounded by it. A rule
about how a particular form is laid out has to be expressible as data, because
per-form layout rules are prohibited from appearing as code that branches on a
head symbol. A form whose body is not indented is such a rule, so the notation
is where it has to live. No further extension SHALL be made on this precedent
without its own argument.

The system MUST NOT depend on SRFI 272 for the layout of any form, because SRFI
272 leaves the layout algorithm unspecified. Every terminal's layout semantics,
`body0`'s included, is pitch's own and is stated in `style-layout`.

#### Scenario: A style with slots and a body tail is accepted

- **WHEN** the style `(_ i? fc* . body)` is read
- **THEN** it is accepted

#### Scenario: Every terminal is accepted somewhere

- **WHEN** styles exercising each of `i`, `d`, `e`, `f`, `l`, `h`, `i?`, `dc`,
  `ec`, `fc`, `lc`, `dc*`, `ec*`, `fc*`, `lc*`, `body`, `body0`, and `fill` are
  read
- **THEN** each is accepted

#### Scenario: A nested tail is accepted in a slot position

- **WHEN** the style `(_ (i . ec*) . body)` is read
- **THEN** it is accepted
- **AND** the first slot describes a subform that is itself a list

#### Scenario: A zero-indent body tail is accepted

- **WHEN** the style `(_ d . body0)` is read
- **THEN** it is accepted
- **AND** its tail is the zero-indent body terminal

#### Scenario: The grammar stays closed

- **WHEN** a style naming a terminal that is neither SRFI 272's nor `body0` is
  read
- **THEN** it is refused where the table is built
