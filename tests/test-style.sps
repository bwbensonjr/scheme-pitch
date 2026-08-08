#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the style grammar and the tables.
;;
;; No CST, no document and no source text appears in this file, and that is the
;; point: a style table is data, and if testing one needed a tree or a printer
;; it would not be. What each terminal *renders as* is tested in
;; tests/test-print.sps, against real output.
#!r6rs

(import
  (rnrs (6))
  (pitch style)
  (tests runner))

;;; Helpers

(define (raises? thunk)
  (guard (e (#t #t))
    (thunk)
    #f))

(define (slots-of style) (styled-slots (style->shape style)))
(define (tail-of style) (styled-tail (style->shape style)))

(define (nth-slot style n) (list-ref (slots-of style) n))

;; The element style of a slot, reduced to a name a test can compare.
(define (classify style)
  (cond ((eq? style 'expression) 'expression)
        ((eq? style 'datum) 'datum)
        ((nested-style? style)
         (let ((s (nested-style-shape style)))
           (cond ((tail-fill? (styled-tail s)) 'fill)
                 ((pair? (styled-slots s)) 'clause)
                 (else 'nested))))
        (else 'unknown)))

(define (slot-class style n) (classify (slot-style (nth-slot style n))))
(define (tail-class style) (classify (tail-style (tail-of style))))

;;; The notation

(test-begin "the grammar accepts every terminal")

;; A style with slots and a body tail.
(test-assert (styled? (style->shape '(_ i? fc* . body))))

;; Each slot terminal, in a slot position.
(test-assert (for-all (lambda (t) (styled? (style->shape (cons '_ (cons t 'body)))))
                      '(i d e f l h dc ec fc lc)))
;; i? is a slot terminal too, and needs something after it.
(test-assert (styled? (style->shape '(_ i? . body))))

;; Each tail rule, in tail position.
(test-assert (for-all (lambda (t) (styled? (style->shape (cons '_ t))))
                      '(body fill dc* ec* fc* lc*)))

;; A fmt-tail in a slot position: the subform is itself a list.
(test-assert (= 1 (length (slots-of '(_ (i . ec*) . body)))))
(test-assert (= 1 (length (slots-of '(_ fc* . body)))))

;; The slot count is what the notation says it is.
(test-equal 0 (length (slots-of '(_ . body))))
(test-equal 2 (length (slots-of '(_ e l . dc*))))
(test-equal 3 (length (slots-of '(_ i h i . body))))

(test-end)

(test-begin "a malformed style is refused")

(test-assert (raises? (lambda () (style->shape '(x . body)))))
(test-assert (raises? (lambda () (style->shape '(_ q . body)))))
(test-assert (raises? (lambda () (style->shape '(_ i e)))))     ;no tail
(test-assert (raises? (lambda () (style->shape '(_)))))
(test-assert (raises? (lambda () (style->shape '_))))
(test-assert (raises? (lambda () (style->shape '(_ . i?)))))    ;i? is not a tail
(test-assert (raises? (lambda () (style->shape '(_ . 3)))))
(test-assert (raises? (lambda () (style->shape '(_ 3 . body)))))

;; A defective entry fails where the table is built, with no source involved.
(test-assert (raises? (lambda () (make-style-table '(((foo) (_ q . body)))))))

(test-end)

;;; The terminal semantics

(test-begin "a terminal says whether its position is code or data")

;; `e` and the elements of a body or fill tail are expressions: a list in one of
;; those positions is looked up in the table.
(test-equal 'expression (slot-class '(_ e . body) 0))
(test-equal 'expression (tail-class '(_ . body)))
(test-equal 'expression (tail-class '(_ . fill)))

;; Everything else is data and is never looked up. This is what stops
;; `(syntax-rules (let) ...)` styling its literals list as a `let`.
(test-equal 'datum (slot-class '(_ i . body) 0))
(test-equal 'datum (slot-class '(_ d . body) 0))
(test-equal 'datum (slot-class '(_ i? . body) 0))
(test-equal 'fill (slot-class '(_ f . body) 0))
(test-equal 'fill (slot-class '(_ l . body) 0))
(test-equal 'fill (slot-class '(_ h . body) 0))

;; A starred tail reads its elements as clauses, which is why it is not a
;; synonym for `body` even though both give each element a line.
(test-equal 'clause (tail-class '(_ . dc*)))
(test-equal 'clause (tail-class '(_ . ec*)))
(test-equal 'clause (tail-class '(_ . fc*)))
(test-equal 'clause (tail-class '(_ . lc*)))

(test-end)

(test-begin "a terminal says what its subform's own shape is")

;; Only `fill` packs.
(test-assert (tail-fill? (tail-of '(_ . fill))))
(test-assert (not (tail-fill? (tail-of '(_ . body)))))
(test-assert (not (tail-fill? (tail-of '(_ . ec*)))))

;; A clause is one slot and a body of expressions: the generic shape with its
;; first element's style overridden.
(define ec-clause (nested-style-shape (tail-style (tail-of '(_ . ec*)))))
(test-equal 1 (length (styled-slots ec-clause)))
(test-equal 'expression (classify (slot-style (car (styled-slots ec-clause)))))
(test-equal 'expression (classify (tail-style (styled-tail ec-clause))))

;; A `dc` clause differs from an `ec` clause only in its first element.
(define dc-clause (nested-style-shape (tail-style (tail-of '(_ . dc*)))))
(test-equal 'datum (classify (slot-style (car (styled-slots dc-clause)))))

;; `fc` and `lc` coincide: formals and literals are both filled, and nothing at
;; the layout level distinguishes them.
(define fc-clause (nested-style-shape (tail-style (tail-of '(_ . fc*)))))
(define lc-clause (nested-style-shape (tail-style (tail-of '(_ . lc*)))))
(test-equal 'fill (classify (slot-style (car (styled-slots fc-clause)))))
(test-equal 'fill (classify (slot-style (car (styled-slots lc-clause)))))

(test-end)

(test-begin "a slot records how it matches")

;; i? consumes its element only if that element is an identifier.
(test-assert (slot-optional-id? (nth-slot '(_ i? . body) 0)))
(test-assert (not (slot-optional-id? (nth-slot '(_ i . body) 0))))

;; A clause terminal and a nested fmt-tail need a list; `f`, `l` and `h` do
;; not, because `(lambda x body)` and `(define x 1)` are ordinary.
(test-assert (slot-requires-list? (nth-slot '(_ ec . body) 0)))
(test-assert (slot-requires-list? (nth-slot '(_ fc* . body) 0)))
(test-assert (slot-requires-list? (nth-slot '(_ (i . ec*) . body) 0)))
(test-assert (not (slot-requires-list? (nth-slot '(_ f . body) 0))))
(test-assert (not (slot-requires-list? (nth-slot '(_ h . body) 0))))
(test-assert (not (slot-requires-list? (nth-slot '(_ i . body) 0))))

(test-end)

;;; The tables

(test-begin "a table maps a head to a style")

(test-assert (style-table? core-style-table))
(test-assert (styled? (style-table-ref core-style-table 'cond)))

;; A head with no entry is reported absent rather than raising. `if`, `and` and
;; `or` are absent deliberately: the generic shape is already what they want.
(test-equal #f (style-table-ref core-style-table 'if))
(test-equal #f (style-table-ref core-style-table 'and))
(test-equal #f (style-table-ref core-style-table 'or))
(test-equal #f (style-table-ref core-style-table 'no-such-form))

;; Heads sharing a shape share a descriptor, since the entry is written once.
(test-assert (eq? (style-table-ref core-style-table 'when)
                  (style-table-ref core-style-table 'unless)))

(test-end)

(test-begin "a dialect selects a table")

;; A shared entry is the same descriptor in both dialect tables.
(test-assert (eq? (style-table-ref r6rs-style-table 'cond)
                  (style-table-ref r7rs-style-table 'cond)))
(test-assert (eq? (style-table-ref r6rs-style-table 'let)
                  (style-table-ref r7rs-style-table 'let)))

;; The collision: same head, incompatible shapes, and absent from the core, so
;; the default dialect degrades it rather than guessing.
(test-assert (not (eq? (style-table-ref r6rs-style-table 'define-record-type)
                       (style-table-ref r7rs-style-table 'define-record-type))))
(test-equal 1 (length (styled-slots
                        (style-table-ref r6rs-style-table 'define-record-type))))
(test-equal 3 (length (styled-slots
                        (style-table-ref r7rs-style-table 'define-record-type))))
(test-equal #f (style-table-ref core-style-table 'define-record-type))

;; Each dialect's own entries are absent from the other and from the core.
(test-assert (styled? (style-table-ref r6rs-style-table 'library)))
(test-equal #f (style-table-ref r7rs-style-table 'library))
(test-assert (styled? (style-table-ref r7rs-style-table 'define-library)))
(test-equal #f (style-table-ref r6rs-style-table 'define-library))
(test-equal #f (style-table-ref core-style-table 'library))

(test-assert (eq? core-style-table (dialect-style-table 'common)))
(test-assert (eq? r6rs-style-table (dialect-style-table 'r6rs)))
(test-assert (eq? r7rs-style-table (dialect-style-table 'r7rs)))
(test-assert (raises? (lambda () (dialect-style-table 'r5rs))))

(test-end)

(test-exit)
