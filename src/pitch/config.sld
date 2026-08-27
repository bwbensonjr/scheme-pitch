;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Bounded, inert configuration. This library accepts source text, not a path
;; or port: opening files remains the CLI's responsibility. The text is parsed
;; through pitch's own reader and CST projection and is never handed to the host
;; Scheme reader, loader or evaluator.

(define-library (pitch config)
(export
  parse-config resolve-config resolved-config? config-width config-dialect
  config-style-table config-condition? config-condition-path)
(import
  (scheme base)
  (pitch datum)
  (pitch diagnostic)
  (pitch error)
  (pitch parse)
  (pitch sequence)
  (pitch style))
(begin

  (define-syntax let-values
    (syntax-rules ()
      ((_ (((name ...) producer)) body ...)
        (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

  ;;; Errors

  (define config-condition? config-error?)
  (define config-condition-path config-error-path)

  (define (bad path message . irritants)
    (raise (make-config-error path message irritants)))

  (define (diagnostic-text d)
    (string-append (number->string (diagnostic-line d))
                   ":"
                   (number->string (diagnostic-column d))
                   ": "
                   (diagnostic-message d)))

  ;;; Parsed and resolved values

  ;; Each dialect field holds validated entries in source order. An entry is
  ;; ((head ...) style-or-remove). Width and dialect are #f when absent.
  (define-record-type <config-overlay> (make-config-overlay path width dialect common
                                        r6rs r7rs) config-overlay?
    (path config-overlay-path)
    (width config-overlay-width)
    (dialect config-overlay-dialect)
    (common config-overlay-common)
    (r6rs config-overlay-r6rs)
    (r7rs config-overlay-r7rs))

  ;; Construction is private, so an invalid width, dialect or missing table
  ;; cannot cross the formatting boundary.
  (define-record-type <resolved-config> (make-resolved-config width dialect common r6rs
                                         r7rs) resolved-config?
    (width resolved-config-width)
    (dialect resolved-config-dialect)
    (common resolved-config-common)
    (r6rs resolved-config-r6rs)
    (r7rs resolved-config-r7rs))

  (define (config-width config) (resolved-config-width config))
  (define (config-dialect config) (resolved-config-dialect config))

  (define (config-style-table config dialect)
    (case dialect
      ((common) (resolved-config-common config))
      ((r6rs) (resolved-config-r6rs config))
      ((r7rs) (resolved-config-r7rs config))
      (else (error 'config-style-table "Not a dialect" dialect))))

  ;;; Schema validation

  (define (valid-dialect? x) (and (symbol? x) (memq x '(common r6rs r7rs)) #t))

  (define (valid-width? x) (and (integer? x) (exact? x) (positive? x)))

  (define (proper-length? x n) (and (list? x) (= (length x) n)))

  (define (all-distinct-symbols? xs)
    (let loop ((xs xs) (seen '()))
      (cond
        ((null? xs) #t)
        ((or (not (symbol? (car xs))) (memq (car xs) seen)) #f)
        (else (loop (cdr xs) (cons (car xs) seen))))))

  (define (validate-style path style entry)
    (unless (eq? style 'remove)
      (guard (con ((config-condition? con) (raise con))
                  (else (bad path "invalid style" entry)))
        (style->shape style))))

  (define (validate-style-section path entries)
    (let loop ((entries entries) (seen '()) (acc '()))
      (if
        (null? entries)
        (reverse acc)
        (let ((entry (car entries)))
          (unless (proper-length? entry 2)
            (bad path "a style entry must be ((head ...) style-or-remove)" entry))
          (let ((heads (car entry)) (style (cadr entry)))
            (unless (and (pair? heads) (list? heads) (all-distinct-symbols? heads))
              (bad path
                   "style heads must be a non-empty list of distinct symbols"
                   heads))
            (for-each
              (lambda (head)
                (when (memq head seen)
                  (bad path "a style head occurs more than once in one section" head)))
              heads)
            (validate-style path style entry)
            (loop (cdr entries) (append heads seen) (cons entry acc)))))))

  (define (parse-root datum path)
    (unless (and (list? datum)
                 (pair? datum)
                 (eq? (car datum) 'pitch-config)
                 (pair? (cdr datum)))
      (bad path "configuration must be one (pitch-config VERSION ...) datum" datum))
    (unless (and (integer? (cadr datum)) (exact? (cadr datum)) (= (cadr datum) 1))
      (bad path "unsupported pitch-config version" (cadr datum)))
    (let loop ((fields (cddr datum))
               (seen '())
               (width #f)
               (dialect #f)
               (common '())
               (r6rs '())
               (r7rs '()))
      (if
        (null? fields)
        (make-config-overlay path width dialect common r6rs r7rs)
        (let ((field (car fields)))
          (unless (and (pair? field) (list? field) (symbol? (car field)))
            (bad path
                 "configuration fields must be proper lists beginning with a symbol"
                 field))
          (case (car field)
            ((width) (when (memq 'width seen) (bad path "duplicate width field" field))
                     (unless (and (proper-length? field 2) (valid-width? (cadr field)))
                       (bad path "width must be a positive exact integer" field))
                     (loop (cdr fields)
                           (cons 'width seen)
                           (cadr field)
                           dialect
                           common
                           r6rs
                           r7rs))
            ((dialect)
              (when (memq 'dialect seen) (bad path "duplicate dialect field" field))
              (unless (and (proper-length? field 2) (valid-dialect? (cadr field)))
                (bad path "dialect must be common, r6rs, or r7rs" field))
              (loop (cdr fields)
                    (cons 'dialect seen)
                    width
                    (cadr field)
                    common
                    r6rs
                    r7rs))
            ((styles) (unless (and (pair? (cdr field)) (valid-dialect? (cadr field)))
                        (bad path "styles must name common, r6rs, or r7rs" field))
                      (let* ((which (cadr field))
                             (key (cons 'styles which))
                             (entries (validate-style-section path (cddr field))))
                        (when (member key seen)
                          (bad path "duplicate styles field for dialect" which))
                        (loop (cdr fields)
                              (cons key seen)
                              width
                              dialect
                              (if (eq? which 'common) entries common)
                              (if (eq? which 'r6rs) entries r6rs)
                              (if (eq? which 'r7rs) entries r7rs))))
            (else (bad path "unknown configuration field" (car field))))))))

  ;; Parse exactly one top-level datum. Parser and projection diagnostics are
  ;; configuration errors; neither stage raises for malformed source.
  (define (parse-config text path)
    (let-values (((tree parse-diagnostics) (parse-source text path)))
      (unless (null? parse-diagnostics)
        (bad path (diagnostic-text (car parse-diagnostics))))
      (let-values (((data datum-diagnostics) (cst->datum tree)))
        (unless (null? datum-diagnostics)
          (bad path (diagnostic-text (car datum-diagnostics))))
        (unless (= (length data) 1)
          (bad path "configuration must contain exactly one top-level datum" data))
        (parse-root (car data) path))))

  ;;; Composition

  (define (entry-removals entries)
    (apply append
           (map (lambda (entry) (if (eq? (cadr entry) 'remove) (car entry) '()))
                entries)))

  (define (entry-additions entries)
    (filter (lambda (entry) (not (eq? (cadr entry) 'remove))) entries))

  (define (apply-entries table entries)
    (extend-style-table table (entry-additions entries) (entry-removals entries)))

  (define (overlay-entries overlay dialect)
    (case dialect
      ((common) (config-overlay-common overlay))
      ((r6rs) (config-overlay-r6rs overlay))
      ((r7rs) (config-overlay-r7rs overlay))))

  (define (resolve-config defaults user width-override dialect-override)
    (let* ((path (config-overlay-path defaults))
           (width (or width-override
                      (and user (config-overlay-width user))
                      (config-overlay-width defaults)))
           (dialect (or dialect-override
                        (and user (config-overlay-dialect user))
                        (config-overlay-dialect defaults))))
      (unless (valid-width? width)
        (bad path "the shipped default configuration must provide a valid width" width))
      (unless (valid-dialect? dialect)
        (bad path
             "the shipped default configuration must provide a valid dialect"
             dialect))
      (let* ((empty (make-style-table '()))
             (common-default (apply-entries empty (overlay-entries defaults 'common)))
             (common (if user
                         (apply-entries common-default (overlay-entries user 'common))
                         common-default))
             (r6rs-default (apply-entries common (overlay-entries defaults 'r6rs)))
             (r7rs-default (apply-entries common (overlay-entries defaults 'r7rs)))
             (r6rs (if user
                       (apply-entries r6rs-default (overlay-entries user 'r6rs))
                       r6rs-default))
             (r7rs (if user
                       (apply-entries r7rs-default (overlay-entries user 'r7rs))
                       r7rs-default)))
        (make-resolved-config width dialect common r6rs r7rs))))))
