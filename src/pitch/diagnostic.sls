;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; A diagnostic: one defect in the input, anchored to the token it concerns.
;;
;; Shared vocabulary between every layer that can find a defect. Parsing finds
;; structural ones; the datum projection finds the ones structure cannot show,
;; such as an unresolvable label or a bytevector element that is not an octet.
;; A caller merges the lists rather than handling two mechanisms, so cleanliness
;; is one question with one answer: is the merged list empty.
;;
;; The position comes from the token, never from the &source-information on the
;; reader's conditions. That is built from reader-saved-line and
;; reader-saved-column, which describe the innermost recursive lexer entry
;; rather than the token returned, and are right often enough to be dangerous.
;;
;; The record type is the one that lived in (pitch parse); it keeps that UID, so
;; this extraction changes where the definition sits and nothing else.

#!r6rs

(library (pitch diagnostic)
  (export
    make-diagnostic diagnostic? diagnostic-message diagnostic-token diagnostic-line
    diagnostic-column sort-diagnostics)
  (import
    (rnrs base (6))
    (rnrs records syntactic (6))
    (rnrs sorting (6))
    (only (pitch reader) token-start token-start-line token-start-column))

  (define-record-type diagnostic
    (fields message token)
    (sealed #t)
    (opaque #f)
    (nongenerative diagnostic-v0-1f852e10-4345-44ca-b2df-b8bb8df8fced))

  (define (diagnostic-line d) (token-start-line (diagnostic-token d)))
  (define (diagnostic-column d) (token-start-column (diagnostic-token d)))

  ;; Source order. Every diagnostic is anchored to a token, and token start
  ;; offsets are strictly increasing, so this is a total order.
  (define (sort-diagnostics ds)
    (list-sort
      (lambda (a b)
        (< (token-start (diagnostic-token a)) (token-start (diagnostic-token b))))
      ds)))
