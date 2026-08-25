#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for inert configuration parsing, validation and composition.
#!r6rs

(import
  (rnrs (6))
  (rnrs hashtables (6))
  (pitch config)
  (pitch style)
  (tests config)
  (tests runner))

;;; Helpers

(define shipped-overlay (parse-config default-config-text "src/pitch/default-config.scm"))

(define (resolve-user text . overrides)
  (resolve-config shipped-overlay
                  (and text (parse-config text "project/pitch.scm"))
                  (if (null? overrides) #f (car overrides))
                  (if (or (null? overrides) (null? (cdr overrides)))
                      #f
                      (cadr overrides))))

(define (config-error? thunk)
  (guard (con
           ((config-condition? con) #t)
           (else #f))
    (thunk)
    #f))

(define (config-error-path-of thunk)
  (guard (con
           ((config-condition? con) (config-condition-path con))
           (else #f))
    (thunk)
    #f))

(define (raises? thunk)
  (guard (con (#t #t))
    (thunk)
    #f))

(define (element-signature style)
  (cond
    ((symbol? style) style)
    ((nested-style? style) (list 'nested (shape-signature (nested-style-shape style))))
    (else 'unknown)))

(define (slot-signature slot)
  (list (element-signature (slot-style slot))
        (slot-optional-id? slot)
        (slot-requires-list? slot)))

(define (shape-signature shape)
  (list (map slot-signature (styled-slots shape))
        (element-signature (tail-style (styled-tail shape)))
        (tail-fill? (styled-tail shape))
        (tail-indent (styled-tail shape))))

(define (same-style? a b)
  (equal? (and a (shape-signature a)) (and b (shape-signature b))))

(define common-entries
  '(((define) (_ h . body))
    ((define-syntax) (_ i . body))
    ((lambda) (_ f . body))
    ((case-lambda) (_ . fc*))
    ((let) (_ i? fc* . body))
    ((let* letrec letrec* let-values let*-values let-syntax letrec-syntax)
     (_ fc* . body))
    ((when unless) (_ e . body))
    ((cond) (_ . ec*))
    ((case) (_ e . lc*))
    ((begin) (_ . body))
    ((do) (_ fc* ec . body))
    ((guard) (_ (i . ec*) . body))
    ((set!) (_ i . body))
    ((syntax-rules) (_ l . dc*))
    ((import) (_ . body))
    ((export) (_ . fill))))

(define r7rs-entries
  '(((define-values) (_ f . body))
    ((define-record-type) (_ i h i . body))
    ((parameterize) (_ fc* . body))
    ((delay delay-force make-promise) (_ . body))
    ((define-library) (_ d . body0))
    ((cond-expand) (_ . ec*))))

(define r6rs-entries
  '(((define-record-type) (_ i . body))
    ((library) (_ d . body0))
    ((syntax-case) (_ e l . dc*))
    ((with-syntax) (_ fc* . body))
    ((assert) (_ . body))))

(define (heads entries) (apply append (map car entries)))

(define (table-matches? actual entries)
  (let ((expected (make-style-table entries)))
    (and (= (vector-length (hashtable-keys actual)) (length (heads entries)))
         (for-all (lambda (head)
                    (same-style? (style-table-ref actual head)
                                 (style-table-ref expected head)))
                  (heads entries)))))

;;; The shipped data

(test-begin "the shipped file contains every former compiled default")

(test-equal 88 (config-width default-config))
(test-equal 'common (config-dialect default-config))
(test-assert (table-matches? (config-style-table default-config 'common)
                             common-entries))
(test-assert (table-matches? (config-style-table default-config 'r6rs)
                             (append common-entries r6rs-entries)))
(test-assert (table-matches? (config-style-table default-config 'r7rs)
                             (append common-entries r7rs-entries)))

;; Shared entries are compiled once and inherited by both dialects.
(test-assert (eq? (style-table-ref (config-style-table default-config 'r6rs) 'cond)
                  (style-table-ref (config-style-table default-config 'r7rs) 'cond)))

(test-end)

;;; Parsing and validation

(test-begin "configuration is one inert versioned datum")

(test-equal 100
            (config-width
              (resolve-user "; comment\n(pitch-config 1 #| block |# (width 100))\n")))

(for-each
  (lambda (text) (test-assert (config-error? (lambda () (parse-config text "bad.scm")))))
  (list ""
        "(pitch-config 1) (pitch-config 1)"
        "(pitch-config 1"
        "(pitch-config 2)"
        "(pitch-config 1 (unknown #t))"
        "(pitch-config 1 (width 0))"
        "(pitch-config 1 (width 10) (width 20))"
        "(pitch-config 1 (dialect r5rs))"
        "(pitch-config 1 (dialect common) (dialect r6rs))"
        "(pitch-config 1 (styles r5rs))"
        "(pitch-config 1 (styles common) (styles common))"
        "(pitch-config 1 (styles common (() (_ . body))))"
        "(pitch-config 1 (styles common ((x x) (_ . body))))"
        "(pitch-config 1 (styles common ((1) (_ . body))))"
        "(pitch-config 1 (styles common ((x) (_ . body)) ((x) (_ . fill))))"
        "(pitch-config 1 (styles common ((x) (_ q . body))))"
        "(begin (display \"must not run\"))"))

;; A partial overlay is valid, but it cannot stand in for the required shipped
;; layer because it has no width or dialect.
(test-assert
  (config-error?
    (lambda ()
      (let ((empty (parse-config "(pitch-config 1)" "empty.scm")))
        (resolve-config empty #f #f #f)))))

;; Style failures retain the file they came from.
(test-equal "project/pitch.scm"
            (config-error-path-of
              (lambda ()
                (parse-config
                  "(pitch-config 1 (styles common ((x) (_ q . body))))"
                  "project/pitch.scm"))))

(test-end)

;;; Composition

(test-begin "configuration layers compose deterministically")

(define scalar-config
  (resolve-user "(pitch-config 1 (width 100) (dialect r7rs))"))
(test-equal 100 (config-width scalar-config))
(test-equal 'r7rs (config-dialect scalar-config))

(define overridden
  (resolve-user "(pitch-config 1 (width 100) (dialect r7rs))" 72 'r6rs))
(test-equal 72 (config-width overridden))
(test-equal 'r6rs (config-dialect overridden))

(define added
  (resolve-user
    "(pitch-config 1 (styles common ((my-let) (_ i? fc* . body))))"))
(for-each
  (lambda (dialect)
    (test-assert (styled? (style-table-ref (config-style-table added dialect) 'my-let))))
  '(common r6rs r7rs))

(define replaced
  (resolve-user "(pitch-config 1 (styles common ((when) (_ . fill))))"))
(test-equal 0
            (length
              (styled-slots
                (style-table-ref (config-style-table replaced 'common) 'when))))

(define removed-common
  (resolve-user "(pitch-config 1 (styles common ((when) remove)))"))
(for-each
  (lambda (dialect)
    (test-equal #f (style-table-ref (config-style-table removed-common dialect) 'when)))
  '(common r6rs r7rs))

(define removed-r6rs
  (resolve-user "(pitch-config 1 (styles r6rs ((when) remove)))"))
(test-assert (styled? (style-table-ref (config-style-table removed-r6rs 'common) 'when)))
(test-equal #f (style-table-ref (config-style-table removed-r6rs 'r6rs) 'when))
(test-assert (styled? (style-table-ref (config-style-table removed-r6rs 'r7rs) 'when)))

;; Section order is semantically irrelevant.
(define ordered-a
  (resolve-user
    "(pitch-config 1 (styles common ((x) (_ . body))) (styles r6rs ((x) remove)))"))
(define ordered-b
  (resolve-user
    "(pitch-config 1 (styles r6rs ((x) remove)) (styles common ((x) (_ . body))))"))
(for-each
  (lambda (dialect)
    (test-assert
      (same-style? (style-table-ref (config-style-table ordered-a dialect) 'x)
                   (style-table-ref (config-style-table ordered-b dialect) 'x))))
  '(common r6rs r7rs))

(test-assert (raises? (lambda () (config-style-table default-config 'r5rs))))

(test-end)

(test-exit)
