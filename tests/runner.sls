;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; A minimal stand-in for the subset of SRFI 64 that the vendored laesare
;; test suite uses: test-begin, test-end, test-equal, test-assert, test-exit.
;;
;; Upstream's tests/runner.sls wraps a real SRFI 64 implementation, which
;; laesare obtains through Akku. Pitch has no package manager and needs only
;; five forms, so this replaces that runner outright rather than taking on
;; chez-srfi as a dependency. It is not SRFI 64 and does not aim to be.
;;
;; Failing and raising expressions are both recorded and execution continues,
;; so a run always reports a complete tally instead of aborting on the first
;; problem.
#!r6rs

(library (tests runner)
  (export
    test-begin test-end test-equal test-assert test-exit)
  (import
    (rnrs (6))
    (rnrs programs (6)))

(define groups '())
(define passes 0)
(define failures 0)

(define (test-begin name)
  (set! groups (cons name groups))
  (display ";; ") (display name) (newline))

(define (test-end)
  (when (null? groups)
    (assertion-violation 'test-end "No matching test-begin"))
  (set! groups (cdr groups)))

(define (current-group)
  (if (null? groups) "<toplevel>" (car groups)))

(define (report-failure form expected actual)
  (set! failures (+ failures 1))
  (display "FAIL [") (display (current-group)) (display "] ")
  (write form) (newline)
  (display "  expected: ") (write expected) (newline)
  (display "  actual:   ") (write actual) (newline))

(define (report-raise form con)
  (set! failures (+ failures 1))
  (display "ERROR [") (display (current-group)) (display "] ")
  (write form) (newline)
  (display "  condition: ")
  (if (message-condition? con)
      (display (condition-message con))
      (write con))
  (newline))

;; Run thunk, returning either (values #t result) or (values #f condition).
(define (attempt thunk)
  (guard (con (#t (values #f con)))
    (values #t (thunk))))

(define (check-equal form expected thunk)
  (let-values (((ok? result) (attempt thunk)))
    (cond ((not ok?) (report-raise form result))
          ((equal? expected result) (set! passes (+ passes 1)))
          (else (report-failure form expected result)))))

(define (check-assert form thunk)
  (let-values (((ok? result) (attempt thunk)))
    (cond ((not ok?) (report-raise form result))
          (result (set! passes (+ passes 1)))
          (else (report-failure form "a true value" result)))))

(define-syntax test-equal
  (syntax-rules ()
    ((_ expected expr)
     (check-equal 'expr expected (lambda () expr)))))

(define-syntax test-assert
  (syntax-rules ()
    ((_ expr)
     (check-assert 'expr (lambda () expr)))))

(define (test-exit)
  (newline)
  (display (if (zero? failures) "PASS" "FAIL"))
  (display ": ") (display passes) (display " passed, ")
  (display failures) (display " failed") (newline)
  (exit (if (zero? failures) 0 1))))
