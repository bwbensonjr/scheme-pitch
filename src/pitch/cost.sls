;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The cost objective the layout engine minimizes.
;;
;; (pitch layout) is parameterized over a cost factory rather than configured by
;; one. The engine never inspects a cost by any means other than the five
;; operations below, so a caller may use whatever representation it likes.
;;
;; This library deliberately does not import (pitch layout). The cost factory is
;; the substitution point for style opinions -- it is where "penalize overflow,
;; penalize height, reward a dedented closing delimiter" gets encoded -- so it is
;; the piece most likely to be written by a caller, and writing one should not
;; require depending on the layout algorithm.
;;
;; The default factory here is the reference implementation's, not pitch's. It
;; ships because the paper specifies it and because the differential oracle needs
;; both sides to agree on one objective. The objective encoding pitch's taste is
;; a later change's work, and needs real Scheme documents to tune against.

#!r6rs

(library (pitch cost)
(export
  make-cost-factory cost-factory? cost-factory-cost<=? cost-factory-cost+
  cost-factory-cost-text cost-factory-cost-nl cost-factory-limit default-cost-factory
  default-computation-width)
(import (rnrs base (6)) (rnrs control (6)) (rnrs records syntactic (6)))

;;; The interface

;; A cost factory is five operations:
;;
;;   cost<=?    cost x cost -> boolean     a total order on costs
;;   cost+      cost x cost -> cost        combine two costs
;;   cost-text  column x length -> cost    text of that length at that column
;;   cost-nl    indentation -> cost        a line break followed by that indent
;;   limit      natural                    the computation width
;;
;; LAWS. These are the caller's obligation, not the engine's. They are not
;; checked, because checking them means quantifying over all costs, and a
;; factory that violates them still produces output -- it just produces output
;; the engine cannot promise is minimal.
;;
;;   1. cost<=? is a total preorder: reflexive, transitive, and total.
;;   2. cost+ is associative and commutative.
;;   3. cost+ is monotone with respect to cost<=?: if a <= b then a+c <= b+c.
;;
;; Law 3 is the load-bearing one. The resolver prunes a candidate the moment it
;; is dominated, on the reasoning that nothing appended later can rescue it. A
;; non-monotone combine makes that reasoning false and the pruning wrong, so the
;; optimality guarantee in the layout-resolution spec is conditional on it.
;;
;; The limit is what bounds the search. Past it the resolver stops comparing
;; candidates and produces a single tainted layout, which is what turns an
;; exponential choice space into a polynomial one.
(define-record-type cost-factory
  (fields cost<=? cost+ cost-text cost-nl limit)
  (sealed #t)
  (opaque #f)
  (nongenerative cost-factory-v0-596a9249-7c50-4039-8246-304daecd7080))

;;; The default factory

;; The computation width the reference uses when none is given: 20% past the
;; page width. Written as exact rational arithmetic rather than (* pw 1.2) so
;; that it is exact at every page width; floor of an exact non-negative ratio is
;; what `div` computes.
(define (default-computation-width page-width) (div (* page-width 6) 5))

;; A cost is a two-element list (badness height), compared lexicographically:
;; lower badness wins, and height breaks ties. The representation is the
;; reference's, so that the oracle can compare costs as written data without a
;; translation step that could itself be wrong.
;;
;; BADNESS. Text of length `len` starting at column `pos`, against page width
;; `w`, is charged the *increment* in squared overflow that it contributes:
;;
;;   a = max(w, pos) - w      how far past the page width the line already was
;;   b = (pos + len) - max(w, pos)    how much of this text lies past the page
;;   badness = b * (2a + b)
;;
;; That expression is (a+b)^2 - a^2. So when a line is built from several texts,
;; the charges telescope and the line's total badness is the square of its total
;; overflow -- which is the objective actually wanted, stated in a form the
;; engine can charge incrementally as it goes. Squaring is what makes one line
;; 20 columns over cost more than ten lines 2 columns over.
;;
;; A newline costs one unit of height and no badness, at every indentation.
(define (make-default-cost-text page-width)
  (lambda (pos len)
    (let ((stop (+ pos len)))
      (if (> stop page-width)
          (let* ((maxwc (if (> pos page-width) pos page-width)) (a (- maxwc page-width))
                                                                (b (- stop maxwc)))
            (list (* b (+ (* 2 a) b)) 0))
          (list 0 0)))))

(define (default-cost<=? c1 c2)
  (let ((b1 (car c1)) (h1 (cadr c1)) (b2 (car c2)) (h2 (cadr c2)))
    (if (= b1 b2) (<= h1 h2) (< b1 b2))))

(define (default-cost+ c1 c2) (list (+ (car c1) (car c2)) (+ (cadr c1) (cadr c2))))

(define (default-cost-nl i) (list 0 1))

(define default-cost-factory
  (case-lambda
    ((page-width)
      (default-cost-factory page-width (default-computation-width page-width)))
    ((page-width computation-width)
      (make-cost-factory default-cost<=?
                         default-cost+
                         (make-default-cost-text page-width)
                         default-cost-nl
                         computation-width)))))
