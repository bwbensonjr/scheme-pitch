;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Layer 2: datum equivalence.
;;
;; The check takes two source *texts*. That is the whole design of the
;; signature: the call site is check(input, formatted-output), and accepting
;; trees or data would let a caller pass the tree the printer walked. A
;; formatter changes only layout and trivia, so a projection of the printer's
;; own tree is identical by construction and would pass no matter how badly the
;; printer misbehaved. Black's --safe does not reuse its in-memory tree either;
;; it reparses the string it printed.
;;
;; This check is strictly weaker than token equivalence and is kept anyway,
;; because it runs through a different code path: if the token comparator is
;; itself wrong, this is an independent witness. All of the following PASS it,
;; and tests pin each one so the weakness stays visible:
;;
;;   a deleted comment, a moved #; datum comment, [ rewritten to (,
;;   'x expanded to (quote x), #xff rewritten as 255, "\x41;" as "A"
;;
;; Layer 1 exists to catch exactly those.
;;
;; Nothing here is wired to a formatter yet, because there is no printer. What
;; is testable now is the mechanism, on text pairs differing only in whitespace.

#!r6rs

(library (pitch check)
  (export datum=? check-datum-equivalence)
  (import
    (rnrs base (6))
    (pitch diagnostic)
    (pitch parse)
    (pitch datum))

;; Named so tests and callers have one operation to reach for, and so a future
;; divergence has somewhere to live. Today it is equal?, which R6RS requires to
;; terminate on circular arguments -- which is why the projection produces host
;; data rather than a representation whose comparator we would have to write.
(define (datum=? a b) (equal? a b))

;; The two layers each report in source order; merging them keeps that, so a
;; reader of the list is not asked to interleave two orderings mentally.
(define (source->data text filename)
  (let-values (((document parse-diagnostics) (parse-source text filename)))
    (let-values (((data datum-diagnostics) (cst->datum document)))
      (values data
              (sort-diagnostics (append parse-diagnostics datum-diagnostics))))))

;; Returns two values: whether the two texts are datum-equivalent, and the
;; diagnostics found in either. A defect on either side is a failure, not a
;; comparison: there is no useful sense in which two unusable inputs agree.
(define (check-datum-equivalence input-text output-text)
  (let-values (((input-data input-diagnostics)
                (source->data input-text "<input>"))
               ((output-data output-diagnostics)
                (source->data output-text "<output>")))
    (let ((diagnostics (append input-diagnostics output-diagnostics)))
      (if (null? diagnostics)
          (values (datum=? input-data output-data) '())
          (values #f diagnostics))))))
