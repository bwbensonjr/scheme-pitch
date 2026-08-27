#lang racket/base
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The reference side of the differential oracle.
;;
;; Reads tests/oracle/documents.scm -- the same file tests/oracle/oracle-emit.scm
;; reads -- builds each entry with Racket's pretty-expressive, and writes one
;; line per entry in the same format. `make oracle-layout` diffs this against
;; the pitch side.
;;
;; This file must stay a thin interpreter of the corpus. Any cleverness here is
;; cleverness the two sides do not share, which is exactly what an oracle is
;; supposed to rule out.
;;
;; Run from the repository root; the corpus path is relative.

;; racket/list is imported by name: it also exports `flatten`, and a bare
;; require would collide with pretty-expressive's.
(require pretty-expressive
         (only-in racket/list first second third fourth fifth))

(define corpus-path "tests/oracle/documents.scm")

(define (build e)
  (cond
    [(symbol? e)
     (case e
       [(nl) nl]
       [(break) break]
       [(hard-nl) hard-nl]
       [(empty-doc) empty-doc]
       [(fail) fail]
       [else (error 'build "unknown document atom: ~s" e)])]
    [(pair? e)
     (define head (car e))
     (define args (cdr e))
     (case head
       [(text) (text (car args))]
       [(newline) (newline (car args))]
       [(concat) (u-append (build (car args)) (build (cadr args)))]
       [(alternatives) (alt (build (car args)) (build (cadr args)))]
       [(alt) (apply alt (map build args))]
       [(nest) (nest (car args) (build (cadr args)))]
       [(align) (align (build (car args)))]
       [(reset) (reset (build (car args)))]
       [(full) (full (build (car args)))]
       [(cost) (cost (car args) (build (cadr args)))]
       [(group) (group (build (car args)))]
       [(flatten) (flatten (build (car args)))]
       [(u-append) (apply u-append (map build args))]
       [(us-append) (apply us-append (map build args))]
       [(v-append) (apply v-append (map build args))]
       [(a-append) (apply a-append (map build args))]
       [(as-append) (apply as-append (map build args))]
       [else (error 'build "unknown document form: ~s" e)])]
    [else (error 'build "not a document expression: ~s" e)]))

;; See the matching comment in oracle-emit.scm: a stray paren would put some entries
;; outside the list, both drivers would skip them identically, and the diff
;; would still pass on a corpus smaller than the file.
(define (read-corpus path)
  (call-with-input-file path
    (lambda (port)
      (define entries (read port))
      (define trailing (read port))
      (unless (eof-object? trailing)
        (error 'read-corpus
               "the corpus file must hold exactly one list of entries; found data after it: ~s"
               trailing))
      (unless (list? entries)
        (error 'read-corpus "the corpus is not a list"))
      entries)))

(define (run-entry entry)
  (define name (first entry))
  (define page-width (second entry))
  (define computation-width (third entry))
  (define offset (fourth entry))
  (define document (fifth entry))
  (define factory
    (default-cost-factory #:page-width page-width
                          #:computation-width computation-width))
  (display name)
  (display " ")
  (with-handlers ([exn:fail? (lambda (e) (display "NO-LAYOUT"))])
    (define-values (rendered inf)
      (pretty-format/factory/info (build document) factory #:offset offset))
    (write (info-tainted? inf))
    (display " ")
    (write (info-cost inf))
    (display " ")
    (write rendered))
  ;; pretty-expressive's `newline` shadows the console one here.
  (display "\n"))

(let ([entries (read-corpus corpus-path)])
  (display "entries ") (write (length entries)) (display "\n")
  (for-each run-entry entries))
