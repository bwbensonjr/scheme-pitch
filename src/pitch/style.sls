;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Style tables: which shape each form takes, as data.
;;
;; The notation is SRFI 272's style grammar and nothing else is borrowed from
;; it. SRFI 272 is a datum printer that explicitly leaves its layout algorithm
;; unspecified, which is the one property pitch sells, so what a terminal
;; *renders as* is decided in (pitch print) and specified in style-layout. What
;; lives here is the grammar, its validation, and the tables:
;;
;;   ⟨style⟩    ⟶ (⟨_⟩ . ⟨fmt-tail⟩)
;;   ⟨fmt-tail⟩ ⟶ body | body0 | fill | dc* | ec* | fc* | lc*
;;                | (i? . ⟨fmt-tail⟩) | (⟨fmt⟩ . ⟨fmt-tail⟩)
;;   ⟨fmt⟩      ⟶ i | d | e | f | l | h | dc | ec | fc | lc | ⟨fmt-tail⟩
;;
;; ONE TERMINAL ABOVE IS NOT SRFI 272'S: `body0`, which is `body` laid out with
;; no indent. Everything else is SRFI 272's, spelled as SRFI 272 spells it, and
;; the grammar stays closed either way -- the terminals are a finite enumeration
;; and anything outside it is refused where the table is built.
;;
;; It is here because a rule about how a particular form is laid out has to be
;; expressible as *data*. CLAUDE.md prohibits per-form layout rules that branch
;; on a head symbol, so given a form whose body is not indented, the notation is
;; the only place that rule can live; the choice was never "extend SRFI 272 or
;; don't" but "extend the notation or violate the layering invariant". The cost
;; is small because SRFI 272 leaves layout unspecified anyway: every terminal's
;; meaning is already pitch's own, and this one differs from `body` in a single
;; integer. No further extension follows from the precedent -- a third terminal
;; needs its own argument.
;;
;; THE TERMINALS COLLAPSE ONTO TWO FACTS, and stating them that way is what
;; keeps the semantics small enough to check. The first is whether a subform is
;; *code* or *data*: `e`, and every element of a `body` or `fill` tail, is an
;; expression and is laid out by the ordinary rules, so a list among them
;; consults this table for its own head. Every other terminal names data, and
;; data is never looked up. That is not decoration -- `(syntax-rules (let) ...)`
;; has a literals list whose head is the symbol `let`, and `(let ((if 1)) ...)`
;; has a binding whose head is the symbol `if`. Laying either out as the form it
;; spells would be a visible defect, and the terminal in that position is
;; exactly what says it is not one. It is also why `ec*` is not a synonym for
;; `body` even though both put one element per line: `body` looks its elements
;; up and `ec*` refuses to.
;;
;; The second is the subform's own shape. `i` and `d` impose nothing. `f`, `l`
;; and `h` name lists of names or literals and are *filled*. The clause
;; terminals say the element is a list read as (first . body), whose first
;; element takes the style `d`, `e`, `f` or `l` respectively. `fc` and `lc`
;; therefore compile to the same descriptor, since formals and literals are both
;; filled; that is recorded rather than hidden, because pretending they differ
;; would mean two code paths that have to be kept agreeing.
;;
;; DATA, NOT CODE, STRUCTURALLY. This library imports neither (pitch cst),
;; (pitch doc) nor (pitch reader). It maps a symbol to an inert descriptor and
;; knows about neither trees nor documents, so a table cannot contain a document
;; or a procedure -- it cannot name one. Adding, changing or removing a per-form
;; rule is an edit to an entry below and touches no emitter.
;;
;; A malformed style raises where the table is built, at library
;; initialization. That is a programmer error in pitch's own data rather than a
;; property of anyone's input, so it must surface where the mistake is, and
;; validating at load means every entry is exercised on every run whatever
;; source is being formatted.

#!r6rs

(library (pitch style)
(export
  ;; the grammar
  style->shape
  ;; the descriptor
  styled? styled-slots styled-tail slot? slot-style slot-optional-id?
  slot-requires-list? tail? tail-style tail-fill? tail-indent nested-style?
  nested-style-shape
  ;; the indents a tail terminal selects between
  hanging-indent flush-indent
  ;; tables
  make-style-table style-table? style-table-ref dialect-style-table core-style-table
  r6rs-style-table r7rs-style-table)
(import
  (rnrs base (6))
  (rnrs control (6))
  (rnrs lists (6))
  (rnrs hashtables (6))
  (rnrs records syntactic (6)))

;;; The descriptor
;;
;; A compiled style is a slot list and a tail rule. An *element style* -- what
;; one subform is laid out as -- is one of:
;;
;;   expression      laid out by the ordinary rules; a list here is looked up
;;   datum           never looked up; a list here takes the generic shape
;;   (nested shape)  never looked up; a list here is laid out headless by shape
;;
;; Three cases rather than eleven. `f`, `l` and `h` are a nested shape with a
;; fill tail; a clause terminal is a nested shape with one slot and a body.

(define-record-type styled
  (fields slots tail)
  (sealed #t)
  (opaque #f)
  (nongenerative styled-v0-6b1c4f92-08ad-4d31-95e7-3c2b7a41d6f0))

;; optional-id?   consumes its element only if that element is an identifier
;; requires-list? the style does not apply unless the element is a list
(define-record-type slot
  (fields style optional-id? requires-list?)
  (sealed #t)
  (opaque #f)
  (nongenerative slot-v0-2f7d8e13-c45a-4b66-9e02-71a3d5c8b4ef))

;; fill?  packs the remaining elements instead of giving each its own line
;; indent how far the broken tail sits from the form's opening delimiter
;;
;; The indent is on the tail rather than on the styled shape deliberately. It
;; is a property of what the terminal means, and a shape that could carry an
;; indent of its own would be the general indent-by-N mechanism this notation
;; declines to offer: two indents exist because two are motivated, and a third
;; should have to argue for itself rather than being expressible by accident.
(define-record-type tail
  (fields style fill? indent)
  (sealed #t)
  (opaque #f)
  ;; v1: the indent field. A nongenerative UID must mean one field set, so
  ;; adding one takes a new UID rather than reusing v0's.
  (nongenerative tail-v1-ae33b888-4baa-4f65-aa8f-3a64395af1a7))

(define-record-type nested-style
  (fields shape)
  (sealed #t)
  (opaque #f)
  (nongenerative nested-style-v0-c58e1a7f-42b0-4d93-a6e5-08f37c14be29))

;;; The indents
;;
;; How far a broken tail is indented from its opening delimiter. SRFI 272 calls
;; this pp-tab and measures it from the start of the form's keyword; measuring
;; from the delimiter instead is what every Scheme community actually writes,
;; and it is also why SRFI 272's pp-max-tab has no referent here -- there is no
;; keyword-relative drift to cap. Both are constants rather than configuration:
;; README.md says the configuration surface is width and dialect, and neither
;; of these is either.
;;
;; There are two, and the tail terminal selects between them; nothing else
;; does. flush-indent exists for forms that wrap a whole compilation unit,
;; where indenting the body costs two columns on every line of a file to mark
;; a nesting level that ends at the last line and nobody can forget.
;;
;; They live here rather than in (pitch print) because terminal-tail needs
;; them and (pitch style) imports nothing. (pitch print) imports hanging-indent
;; back for the generic shape, so the value 2 is still written down once.
(define hanging-indent 2)

(define flush-indent 0)

;;; Terminals

;; A list of names or literals: no lookup, and packed rather than one per line.
(define fill-shape (make-styled '() (make-tail 'datum #t hanging-indent)))

(define fill-element (make-nested-style fill-shape))

;; A clause is (first . body): the first element takes the terminal's style and
;; everything after it is an expression. It renders by the generic shape with
;; the first element as the head, so a clause introduces no emitter of its own.
(define (clause-element first-style)
  (make-nested-style (make-styled (list (make-slot first-style #f #f))
                                  (make-tail 'expression #f hanging-indent))))

;; The slot terminals. `fc` and `lc` coincide: formals and literals are both
;; filled, and there is nothing further to distinguish at the layout level.
(define (terminal-slot name)
  (case name
    ((i d) (make-slot 'datum #f #f))
    ((e) (make-slot 'expression #f #f))
    ((f l h) (make-slot fill-element #f #f))
    ((i?) (make-slot 'datum #t #f))
    ((dc) (make-slot (clause-element 'datum) #f #t))
    ((ec) (make-slot (clause-element 'expression) #f #t))
    ((fc lc) (make-slot (clause-element fill-element) #f #t))
    (else #f)))

;; The tail rules. A starred terminal reads every remaining element as a clause
;; of that kind, which is what stops those elements being looked up as forms.
;;
;; body0 is the one terminal here that is not SRFI 272's. It is body with the
;; other indent, and it exists because a rule about how a form is laid out has
;; to be expressible as data: CLAUDE.md prohibits per-form layout rules that
;; branch on a head symbol, so "this form's body is not indented" has nowhere
;; else to live. See the grammar note in the library header.
(define (terminal-tail name)
  (case name
    ((body) (make-tail 'expression #f hanging-indent))
    ((body0) (make-tail 'expression #f flush-indent))
    ((fill) (make-tail 'expression #t hanging-indent))
    ((dc*) (make-tail (clause-element 'datum) #f hanging-indent))
    ((ec*) (make-tail (clause-element 'expression) #f hanging-indent))
    ((fc* lc*) (make-tail (clause-element fill-element) #f hanging-indent))
    (else #f)))

;;; The grammar reader

(define (bad msg what whole) (assertion-violation 'style->shape msg what whole))

(define (style->shape datum)
  (unless (and (pair? datum) (eq? (car datum) '_))
    (bad "A style is (_ . fmt-tail)" datum datum))
  (parse-fmt-tail (cdr datum) datum))

;; ⟨fmt-tail⟩. Returns a styled shape: the slots gathered so far and the rule
;; that covers everything after them.
(define (parse-fmt-tail t whole)
  (cond
    ((symbol? t) (let ((tl (terminal-tail t)))
                   (if tl (make-styled '() tl) (bad "Not a tail rule" t whole))))
    ((pair? t)
      (let* ((s (parse-fmt (car t) whole)) (rest (parse-fmt-tail (cdr t) whole)))
        (make-styled (cons s (styled-slots rest)) (styled-tail rest))))
    (else (bad "A style must end in a tail rule" t whole))))

;; ⟨fmt⟩. Returns a slot. A fmt that is itself a fmt-tail describes a subform
;; that is a list -- `fc*` for a binding list, `(i . ec*)` for a guard's
;; handler -- and such a subform must be a list for the style to apply.
(define (parse-fmt f whole)
  (cond
    ((and (symbol? f) (terminal-slot f)))
    ((or (symbol? f) (pair? f))
      (make-slot (make-nested-style (parse-fmt-tail f whole)) #f #t))
    (else (bad "Not a fmt" f whole))))

;;; Tables

;; Entries are ((head ...) style), so heads sharing a shape are written once.
;; Compiling happens here, which is what makes a defective entry a load-time
;; failure.
;;
;; The two steps are separate so that a dialect table can share the core's
;; *compiled* shapes rather than recompiling the same notation. An entry common
;; to both standards is then one descriptor reachable from both tables, which is
;; what "a shared entry is written exactly once" has to mean if it is to be
;; checkable.
(define (compile-entries entries)
  (apply append
         (map (lambda (entry)
                (let ((shape (style->shape (cadr entry))))
                  (map (lambda (head) (cons head shape)) (car entry))))
              entries)))

;; Later bindings win, so a dialect entry may override a core one.
(define (bindings->table bindings)
  (let ((h (make-eq-hashtable)))
    (for-each (lambda (b) (hashtable-set! h (car b) (cdr b))) bindings)
    (hashtable-copy h))) ;immutable

(define (make-style-table entries) (bindings->table (compile-entries entries)))

(define (style-table? x) (hashtable? x))

(define (style-table-ref tbl head) (hashtable-ref tbl head #f))

;;; The entries
;;
;; `if`, `and` and `or` are deliberately absent. What everyone writes for all
;; three is the first argument on the opening line with the rest aligned under
;; it, and that is precisely the generic shape, so an entry would make their
;; output worse rather than better.

(define core-entries
  '(;; binding
     ((define) (_ h . body))
     ((define-syntax) (_ i . body))
     ((lambda) (_ f . body))
     ((case-lambda) (_ . fc*))
     ((let) (_ i? fc* . body))
     ((let* letrec letrec* let-values let*-values let-syntax letrec-syntax)
       (_ fc* . body))
     ;; control
     ((when unless) (_ e . body))
     ((cond) (_ . ec*))
     ((case) (_ e . lc*))
     ((begin) (_ . body))
     ((do) (_ fc* ec . body))
     ((guard) (_ (i . ec*) . body))
     ((set!) (_ i . body))
     ;; macro and library
     ((syntax-rules) (_ l . dc*))
     ((import) (_ . body))
     ((export) (_ . fill))))

(define r7rs-entries
  '(((define-values) (_ f . body)) ((define-record-type) (_ i h i . body))
                                   ((parameterize) (_ fc* . body))
                                   ((delay delay-force make-promise) (_ . body))
                                   ((define-library) (_ d . body0))
                                   ((cond-expand) (_ . ec*))))

(define r6rs-entries
  '(((define-record-type) (_ i . body)) ((library) (_ d . body0))
                                        ((syntax-case) (_ e l . dc*))
                                        ((with-syntax) (_ fc* . body))
                                        ((assert) (_ . body))))

(define core-bindings (compile-entries core-entries))

(define core-style-table (bindings->table core-bindings))
(define r7rs-style-table
  (bindings->table (append core-bindings (compile-entries r7rs-entries))))
(define r6rs-style-table
  (bindings->table (append core-bindings (compile-entries r6rs-entries))))

;; A dialect at this layer selects a style table and nothing else. An unknown
;; symbol comes from a caller rather than from a file, so it raises.
(define (dialect-style-table dialect)
  (case dialect
    ((common) core-style-table)
    ((r7rs) r7rs-style-table)
    ((r6rs) r6rs-style-table)
    (else (assertion-violation 'dialect-style-table "Not a dialect" dialect)))))
