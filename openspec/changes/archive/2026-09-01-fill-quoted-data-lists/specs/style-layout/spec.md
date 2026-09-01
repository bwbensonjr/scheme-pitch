## ADDED Requirements

### Requirement: A quoted datum falls back to filling rather than to the generic shape

The datum of a `'` (quote) abbreviation SHALL be a *quoted position*, and so SHALL
every compound nested anywhere within it, to any depth.

In a quoted position, a compound for which no style applies SHALL be laid out by
packing — its elements joined by a separator that renders as a single space or as
a line break, chosen independently at each gap — rather than by the generic shape.
This is the same rendering `f`, `l`, `h` and a bytevector already receive.

"No style applies" SHALL mean what it means everywhere else: the compound is not a
list, or its head is not an identifier leaf, or its head's value has no entry in
the style table. A vector in a quoted position therefore packs, having no head to
look up.

The property SHALL be carried by position alone. The system MUST NOT decide it by
examining a head symbol, and a compound that is not in a quoted position SHALL be
unaffected by this requirement.

A quoted compound whose elements are separated by a dot SHALL fall back to the
generic shape, where the dot is preserved. Packing has no rendering for an
improper tail and MUST NOT invent one.

#### Scenario: An overflowing quoted symbol list packs

- **WHEN** `'(car cdr cons null? pair? eq? eqv? equal? not vector? string?
  symbol? char? number? list?)` is laid out at a width too narrow for one line
- **THEN** it occupies more than one line
- **AND** at least one of its lines holds more than one symbol

#### Scenario: A quoted list that fits is unchanged

- **WHEN** `'(a b c)` is laid out at a width that accommodates it
- **THEN** the output is `'(a b c)` on one line

#### Scenario: A quoted list is never staircased off its second element

- **WHEN** a quoted list with no styled head, too wide for the page, is laid out
- **THEN** no element begins at the column of the list's second element by virtue
  of the second element having shared the opening line with the first

#### Scenario: A quoted list whose head is a compound packs

- **WHEN** `'((alpha 1) (beta 2) (gamma 3) (delta 4) (epsilon 5) (zeta 6))` is
  laid out at a width that forces breaking
- **THEN** at least one of its lines holds more than one element

#### Scenario: A vector inside a quoted list packs

- **WHEN** a quoted list containing a vector too wide for the page is laid out
- **THEN** the vector's elements pack
- **AND** at least one of its lines holds more than one element

#### Scenario: A dotted quoted list keeps the generic shape

- **WHEN** `'(a b . c)` is laid out
- **THEN** it is emitted by the generic shape with the dot preserved

#### Scenario: An unquoted list spelling the same elements is unaffected

- **WHEN** a list identical to a quoted one but written without the `'` is laid
  out at the same width
- **THEN** it takes the shape it took before this requirement existed

### Requirement: A quoted position does not suppress style lookup

A compound in a quoted position whose head has a style entry SHALL be laid out by
that style, exactly as it would outside a quote. Quoting SHALL NOT suppress
lookup, at any depth.

Quoted code goes on looking like code. A quoted datum holds whatever the source
quoted, which is frequently a form — a macro expansion under test, an example in
a table, a term to be evaluated later — and laying it out by its style is what
makes it readable as the thing it spells.

This is deliberately distinct from a *terminal-established* data position. A
terminal that names data says something specific about one argument of one form:
`(syntax-rules (let) ...)` declares that `(let)` is a list of names. A quote says
only that evaluation is deferred, which is not a claim about shape.

#### Scenario: A quoted definition keeps its style

- **WHEN** `'(define (f x) (+ x 1) (list x x))` is laid out at a width that
  forces breaking
- **THEN** it is laid out as a `define` form

#### Scenario: A quoted binding form keeps its style

- **WHEN** `'(let ((a 1) (b 2)) (body a) (body b))` is laid out at a width that
  forces breaking
- **THEN** it is laid out as a `let` form
- **AND** its binding list is laid out as a list of peers

#### Scenario: A styled head deep inside a quoted datum keeps its style

- **WHEN** `'((a (b (cond (c d) (else e)))))` is laid out at a width that forces
  breaking
- **THEN** the innermost `(cond ...)` is laid out as a `cond` form

#### Scenario: A literals list inside a quote is still a literals list

- **WHEN** `'(syntax-rules (let) ((_ x) x))` is laid out at a width that forces
  breaking
- **THEN** the literals list `(let)` is not laid out as a `let` form

### Requirement: The quoted property overrides an expression terminal and yields to a data terminal

Within a quoted subtree, an element that a style assigns the terminal `e`, or an
element of a `body` or `fill` tail, SHALL remain a quoted position. The fill
fallback therefore survives into the body of a styled form that is itself quoted.

Within a quoted subtree, a terminal that names data — `i`, `d`, `f`, `l`, `h`, and
the first element of any clause other than an `ec` clause — SHALL keep its
meaning, and the compound in that position SHALL NOT be looked up. A terminal
naming data is the more specific statement and wins.

The elements of a `dc*`, `ec*`, `fc*`, or `lc*` tail inside a quoted subtree SHALL
be read as clauses, as they are anywhere else, and each clause's own elements
SHALL remain quoted positions where the clause's terminals name expressions.

#### Scenario: The fallback survives into a quoted styled form's body

- **WHEN** `'(begin (alpha one two three four five six seven eight nine ten))` is
  laid out at a width that forces the inner list to break
- **THEN** `begin`'s style applies to the outer form
- **AND** the inner list, whose head has no entry, packs rather than staircasing

#### Scenario: A data terminal inside a quote still suppresses lookup

- **WHEN** `'(lambda (let cond) (body))` is laid out at a width that forces
  breaking
- **THEN** the formals list `(let cond)` is not laid out as a `let` form

#### Scenario: A clause inside a quoted form is still a clause

- **WHEN** `'(cond (test-expression consequent) (else other))` is laid out at a
  width that forces breaking
- **THEN** each clause takes the generic shape with its first element as the head

### Requirement: Only the quote abbreviation establishes a quoted position

Of the prefix abbreviations the reader accepts, only `'` SHALL establish a quoted
position. `` ` ``, `,`, `,@`, `#'`, `` #` ``, `#,` and `#,@` SHALL NOT, and a
compound under one of them SHALL be laid out exactly as it is today.

A quasiquoted or syntax-template datum holds expression positions — its unquotes —
so "everything below defers evaluation" is not true of it, and extending the
property to it would require a rule for what an unquote does to the property and
what a nested quasiquote does to that.

The list spelling `(quote datum)` SHALL likewise be unaffected. Reaching it would
require the layout to branch on a head symbol, which is prohibited.

#### Scenario: A quasiquoted template is unaffected

- **WHEN** `` `(alpha one two three four five six seven eight nine ten) `` is
  laid out at a width that forces breaking
- **THEN** it takes the shape it took before this requirement existed

#### Scenario: A syntax template is unaffected

- **WHEN** `#'(alpha one two three four five six seven eight nine ten)` is laid
  out at a width that forces breaking
- **THEN** it takes the shape it took before this requirement existed

#### Scenario: The list spelling of quote is unaffected

- **WHEN** `(quote (car cdr cons))` is laid out
- **THEN** it takes the shape it took before this requirement existed

### Requirement: A break forced inside a filled quoted list does not move the packing

Where a comment or a preserved blank line inside a packed quoted compound forces a
line break, the compound SHALL still pack the elements on either side of that
break, and every one of its lines SHALL begin at the column immediately after its
opening delimiter.

A line comment written inside a quoted list SHALL keep its position relative to
the elements around it, and SHALL still be followed by a line break, exactly as it
is anywhere else.

This is what makes a hand-grouped table survive: grouping expressed by a blank
line or by an interleaved comment forces a break and is preserved, while grouping
expressed by a line break alone is not, because a line break the layout did not
choose is discarded everywhere in pitch.

#### Scenario: A comment inside a quoted list keeps its place

- **WHEN** a quoted list written with a line comment between two of its elements
  is laid out
- **THEN** the comment appears between those two elements
- **AND** it is followed by a line break
- **AND** the elements before and after it still pack

#### Scenario: A blank line inside a quoted list survives

- **WHEN** a quoted list written with a blank line between two groups of elements
  is laid out
- **THEN** the output has one blank line between those groups
- **AND** each group packs

#### Scenario: Every line of a broken quoted list is aligned

- **WHEN** a quoted list with no styled head, too wide for the page, is laid out
  at an indentation greater than zero
- **THEN** every line of it begins at the column immediately after its opening
  delimiter
