#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the layout engine and the default cost objective.
;;
;; These are the written expectations. They confirm the cases we thought of;
;; `make oracle-layout` is what covers the ones we did not, by rendering
;; tests/oracle/documents.scm through Racket's pretty-expressive as well and
;; requiring the text, the cost and the taint flag to agree. Neither replaces
;; the other, and the oracle is deliberately blind to the two places pitch
;; departs from the reference on purpose -- those are asserted in
;; tests/test-doc.sps.
;;
;; The worked examples below are the paper's own, transcribed from the
;; reference's tests/examples.rkt with its published expected output. They are
;; the closest thing to an acceptance test the port has: three documents
;; expressing the same layout problem three ways, at the two page widths where
;; the answers differ.
#!r6rs

(import
  (except (rnrs (6)) newline)
  (pitch doc)
  (pitch cost)
  (pitch layout)
  (tests runner))

;;; Helpers

(define (fmt d width)
  (let-values (((rendered result) (layout d (default-cost-factory width))))
    rendered))

(define (fmt/offset d width offset)
  (let-values (((rendered result) (layout d (default-cost-factory width) offset)))
    rendered))

(define (info d width)
  (let-values (((rendered result) (layout d (default-cost-factory width))))
    result))

(define (tainted? d width) (layout-result-tainted? (info d width)))
(define (cost-of d width) (layout-result-cost (info d width)))

(define (no-layout? d)
  (guard (e ((layout-failure? e) #t))
    (fmt d 80)
    #f))

;;; Each core constructor in isolation

(test-begin "core constructors")

(test-equal "abc" (fmt (text "abc") 80))
(test-equal "" (fmt (text "") 80))
(test-equal "a\nb" (fmt (u-append (text "a") hard-nl (text "b")) 80))
(test-equal "ab" (fmt (concat (text "a") (text "b")) 80))

;; A newline emits the current indentation after the break.
(test-equal "a\n    b" (fmt (nest 4 (u-append (text "a") hard-nl (text "b"))) 80))
(test-equal "a\nb" (fmt (nest 0 (u-append (text "a") hard-nl (text "b"))) 80))

;; align sets the indentation to the column where it starts.
(test-equal "abc\n  d"
            (fmt (u-append (text "ab") (align (u-append (text "c") hard-nl (text "d")))) 80))
(test-equal "abcde\n     f"
            (fmt (u-append (text "abcde") (align (u-append (text "") hard-nl (text "f")))) 80))

;; reset returns the indentation to zero, including under an enclosing nest.
(test-equal "a\n      b\nc"
            (fmt (nest 6 (u-append (text "a") hard-nl
                                   (reset (u-append (text "b") hard-nl (text "c")))))
                 80))
;; and under an enclosing align.
(test-equal "xxa\nb"
            (fmt (u-append (text "xx")
                           (align (u-append (text "a") (reset (u-append (text "") hard-nl (text "b"))))))
                 80))

;; align nested inside nest wins, since it is inner. The indentation it sets is
;; the column where the align begins -- 5, just after "b" -- not the column
;; reached inside it.
(test-equal "a\n    bc\n     d"
            (fmt (nest 4 (u-append (text "a") hard-nl (text "b")
                                   (align (u-append (text "c") hard-nl (text "d")))))
                 80))

;; A choice picks the cheaper branch.
(test-equal "b" (fmt (alternatives (text "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") (text "b")) 20))
(test-equal "c" (fmt (alt (text "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa") (text "bb") (text "c")) 20))

;; cost adds to a branch, and enough of it flips the choice.
(define two-ways
  (lambda (penalty)
    (alt (cost (list 0 penalty) (text "aa bb"))
         (u-append (text "aa") hard-nl (text "bb")))))
(test-equal "aa bb" (fmt (two-ways 0) 20))
(test-equal "aa\nbb" (fmt (two-ways 5) 20))

(test-end)

;;; The paper's worked examples

(test-begin "worked examples")

(define f (text "first +"))
(define s (text "second +"))
(define t (text "third"))
(define sp (text " "))
(define indentation (text "    "))
(define ret (text "return "))
(define header (text "function append(first,second,third){"))
(define closer (text "}"))

;; Wadler/Leijen-style: one group over the whole argument list.
(define d-traditional
  (u-append header
            (nest 4 (u-append nl ret (group (nest 4 (u-append f nl s nl t)))))
            nl closer))

;; The same problem written with an arbitrary choice between two whole layouts.
(define d-arbitrary
  (v-append header
            (a-append indentation
                      (alt (v-append (a-append ret (text "("))
                                     (a-append indentation (v-append f s t))
                                     (text ")"))
                           (a-append ret f sp s sp t)))
            closer))

;; And in the style the paper advocates.
(define d-pretty-expressive
  (u-append header
            (nest 4 (u-append nl ret
                              (alt (u-append (text "(")
                                             (nest 4 (u-append nl f nl s nl t))
                                             nl
                                             (text ")"))
                                   (u-append f sp s sp t))))
            nl
            closer))

(define horz-layout
  (string-append
   "function append(first,second,third){\n"
   "    return first + second + third\n"
   "}"))

(define vert-layout/no-paren
  (string-append
   "function append(first,second,third){\n"
   "    return first +\n"
   "        second +\n"
   "        third\n"
   "}"))

(define vert-layout/paren
  (string-append
   "function append(first,second,third){\n"
   "    return (\n"
   "        first +\n"
   "        second +\n"
   "        third\n"
   "    )\n"
   "}"))

;; At 36 columns all three agree on the one-line body.
(test-equal horz-layout (fmt d-traditional 36))
(test-equal horz-layout (fmt d-arbitrary 36))
(test-equal horz-layout (fmt d-pretty-expressive 36))

;; At 22 the traditional encoding cannot express the parenthesized layout, so
;; it produces the worse one. That difference is the paper's point.
(test-equal vert-layout/no-paren (fmt d-traditional 22))
(test-equal vert-layout/paren (fmt d-arbitrary 22))
(test-equal vert-layout/paren (fmt d-pretty-expressive 22))

(test-end)

;;; A choice is resolved by total cost, not local fit

(test-begin "not greedy")

;; The group's flat rendering is "aaaa bbbb", nine columns, which fits a page of
;; twelve on its own. A greedy printer takes it and then overflows on the text
;; that follows. Breaking early costs one line and no overflow, so it wins.
(define early-break
  (u-append (group (u-append (text "aaaa") nl (text "bbbb")))
            (text "cccccccc")))
(test-equal "aaaa\nbbbbcccccccc" (fmt early-break 12))
(test-equal '(0 1) (cost-of early-break 12))

;; Given room, the same document stays flat.
(test-equal "aaaa bbbbcccccccc" (fmt early-break 40))
(test-equal '(0 0) (cost-of early-break 40))

;; Two groups, where the first must break to make room for the second.
(define two-groups
  (u-append (group (u-append (text "aa") nl (text "bb")))
            (group (u-append (text "cc") nl (text "dddddddddd")))))
(test-equal '(0 1) (cost-of two-groups 16))

(test-end)

;;; Failure and taint are different outcomes

(test-begin "failure and taint")

;; No layout at all: raises, and does not invent a best effort.
(test-assert (no-layout? fail))
(test-assert (no-layout? (concat (full (text "a")) (text "b"))))
(test-assert (no-layout? (alternatives fail fail)))

;; Overflow past the computation width: renders, and says the search gave up.
(define over-long (text "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"))
(test-equal "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx" (fmt over-long 20))
(test-assert (tainted? over-long 20))

;; A document that fits is not tainted.
(test-equal #f (tainted? (text "short") 20))
(test-equal #f (tainted? (group (u-append (text "aa") nl (text "bb"))) 20))

;; Overflow within the computation width is priced but not tainted: the default
;; computation width is 20% past the page width, so 22 columns on a page of 20
;; is still inside the search.
(test-equal #f (tainted? (text "xxxxxxxxxxxxxxxxxxxxxx") 20))
(test-equal '(4 0) (cost-of (text "xxxxxxxxxxxxxxxxxxxxxx") 20))

;; Taint does not raise.
(test-assert (string? (fmt over-long 20)))

(test-end)

;;; Layout is a pure function of its arguments

(test-begin "purity")

(define shared (group (u-append (text "aaaa") nl (text "bbbb"))))

;; The same arguments give the same answer, every time.
(test-equal (fmt shared 80) (fmt shared 80))
(test-equal (cost-of shared 80) (cost-of shared 80))

;; Two factories over one document, in both orders. A memo table that outlived
;; a call would make one of these four disagree with its twin.
(define wide-first-a (fmt shared 80))
(define narrow-after (fmt shared 6))
(define narrow-first-b (fmt shared 6))
(define wide-after (fmt shared 80))
(test-equal "aaaa bbbb" wide-first-a)
(test-equal "aaaa\nbbbb" narrow-after)
(test-equal wide-first-a wide-after)
(test-equal narrow-after narrow-first-b)

;; A caller-supplied factory reaches the same answer as the default one built
;; with the same page width, and its costs are never inspected directly.
(define hand-built (default-cost-factory 6 (default-computation-width 6)))
(test-equal (fmt shared 6)
            (let-values (((rendered result) (layout shared hand-built))) rendered))

(test-end)

;;; The offset

(test-begin "offset")

;; An offset prices and breaks the first line as if it started there.
(test-equal "aaaa bbbb" (fmt/offset shared 12 0))
(test-equal "aaaa\nbbbb" (fmt/offset shared 12 8))

;; It emits no leading spaces of its own; the caller has already printed them.
(test-equal "abc" (fmt/offset (text "abc") 80 10))

;; The default offset is zero.
(test-equal (fmt shared 12) (fmt/offset shared 12 0))

;; An offset shifts what align sees, since align reads the current column.
(test-equal "ab\n    cd"
            (fmt/offset (u-append (text "ab")
                                  (align (u-append (text "") hard-nl (text "cd"))))
                        80 2))

(test-end)

;;; The default cost objective

(test-begin "default cost factory")

(define factory (default-cost-factory 80))
(define cost-text (cost-factory-cost-text factory))
(define cost-nl (cost-factory-cost-nl factory))
(define cost+ (cost-factory-cost+ factory))
(define cost<=? (cost-factory-cost<=? factory))

;; Text inside the page width is free, at the boundary too.
(test-equal '(0 0) (cost-text 0 80))
(test-equal '(0 0) (cost-text 75 5))
(test-equal '(0 0) (cost-text 10 5))
(test-equal '(0 0) (cost-text 80 0))

;; Overflow is squared.
(test-equal '(1 0) (cost-text 0 81))
(test-equal '(25 0) (cost-text 75 10))
(test-equal '(100 0) (cost-text 0 90))

;; Charging incrementally telescopes to the square of the line's total
;; overflow. This is the property the whole objective rests on.
(test-equal (cost-text 75 10) (cost+ (cost-text 75 5) (cost-text 80 5)))
(test-equal (cost-text 0 90)
            (cost+ (cost+ (cost-text 0 80) (cost-text 80 5)) (cost-text 85 5)))
(test-equal (cost-text 70 25)
            (cost+ (cost+ (cost-text 70 10) (cost-text 80 10)) (cost-text 90 5)))

;; A newline is one unit of height at any indentation.
(test-equal '(0 1) (cost-nl 0))
(test-equal '(0 1) (cost-nl 40))

;; Badness dominates, height breaks ties.
(test-equal #t (cost<=? '(1 2) '(2 1)))
(test-equal #f (cost<=? '(2 1) '(1 2)))
(test-equal #t (cost<=? '(1 1) '(1 2)))
(test-equal #f (cost<=? '(1 2) '(1 1)))

;; Reflexive, total, transitive over a spread of costs.
(define costs '((0 0) (0 1) (0 5) (1 0) (1 1) (3 2) (25 0) (100 7)))
(test-assert (for-all (lambda (c) (cost<=? c c)) costs))
(test-assert (for-all (lambda (a)
                        (for-all (lambda (b) (or (cost<=? a b) (cost<=? b a))) costs))
                      costs))
(test-assert (for-all (lambda (a)
                        (for-all (lambda (b)
                                   (for-all (lambda (c)
                                              (or (not (cost<=? a b))
                                                  (not (cost<=? b c))
                                                  (cost<=? a c)))
                                            costs))
                                 costs))
                      costs))

;; Combine is associative, commutative, and monotone.
(test-assert (for-all (lambda (a)
                        (for-all (lambda (b)
                                   (for-all (lambda (c)
                                              (equal? (cost+ a (cost+ b c))
                                                      (cost+ (cost+ a b) c)))
                                            costs))
                                 costs))
                      costs))
(test-assert (for-all (lambda (a)
                        (for-all (lambda (b) (equal? (cost+ a b) (cost+ b a))) costs))
                      costs))
(test-assert (for-all (lambda (a)
                        (for-all (lambda (b)
                                   (for-all (lambda (c)
                                              (or (not (cost<=? a b))
                                                  (cost<=? (cost+ a c) (cost+ b c))))
                                            costs))
                                 costs))
                      costs))

;; The computation width defaults to 20% past the page width and is used as
;; given when supplied.
(test-equal 96 (cost-factory-limit (default-cost-factory 80)))
(test-equal 96 (default-computation-width 80))
(test-equal 120 (default-computation-width 100))
(test-equal 15 (default-computation-width 13))
(test-equal 0 (default-computation-width 0))
(test-equal 100 (cost-factory-limit (default-cost-factory 80 100)))

(test-end)

;;; pretty-format, the convenience entry point

(test-begin "pretty-format")

(test-equal "aaaa bbbb" (pretty-format shared))
(test-equal "aaaa\nbbbb" (pretty-format shared 6))
;; Its default page width is 80.
(test-equal (pretty-format shared) (pretty-format shared 80))

(test-end)

(test-exit)
