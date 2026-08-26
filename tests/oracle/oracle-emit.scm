;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The pitch side of the differential oracle.
;;
;; Reads tests/oracle/documents.scm, builds each entry with (pitch doc), renders
;; it with (pitch layout), and writes one line per entry. tests/oracle/oracle.rkt
;; does the same with Racket's pretty-expressive and must produce byte-identical
;; output; `make oracle-layout` diffs the two.
;;
;; The line format is deliberately boring, so that a diff points at the entry
;; that disagrees rather than at a formatting artifact:
;;
;;   <name> <tainted?> <cost> <text written as a Scheme string>
;;
;; and, for a document with no layout,
;;
;;   <name> NO-LAYOUT
;;
;; Run from the repository root; the corpus path is relative.

(import
  (scheme base)
  (scheme file)
  (scheme read)
  (scheme write)
  (pitch doc)
  (pitch cost)
  (pitch layout))

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

(define corpus-path "tests/oracle/documents.scm")

;; The description language. Kept in one place so that a new form has to be
;; taught to both drivers or to neither.
(define (build e)
  (cond
    ((symbol? e)
     (case e
       ((nl) nl)
       ((break) break)
       ((hard-nl) hard-nl)
       ((empty-doc) empty-doc)
       ((fail) fail)
       (else (error 'build "unknown document atom" e))))
    ((pair? e)
     (let ((head (car e)) (args (cdr e)))
       (case head
         ((text) (text (car args)))
         ((newline) (newline (car args)))
         ((concat) (concat (build (car args)) (build (cadr args))))
         ((alternatives) (alternatives (build (car args)) (build (cadr args))))
         ((alt) (apply alt (map build args)))
         ((nest) (nest (car args) (build (cadr args))))
         ((align) (align (build (car args))))
         ((reset) (reset (build (car args))))
         ((full) (full (build (car args))))
         ((cost) (cost (car args) (build (cadr args))))
         ((group) (group (build (car args))))
         ((flatten) (flatten (build (car args))))
         ((u-append) (apply u-append (map build args)))
         ((us-append) (apply us-append (map build args)))
         ((v-append) (apply v-append (map build args)))
         ((a-append) (apply a-append (map build args)))
         ((as-append) (apply as-append (map build args)))
         (else (error 'build "unknown document form" e)))))
    (else (error 'build "not a document expression" e))))

;; The file holds exactly one datum: the list of entries. Anything after it
;; means a paren went astray and some entries fell outside the list -- which
;; both drivers would then skip identically, so the diff would still pass while
;; testing less than the corpus contains. Refuse instead. The entry count is
;; printed as the first line so that a truncation is visible in the diff even
;; if this check is ever wrong.
(define (read-corpus path)
  (let* ((port (open-input-file path))
         (entries (read port))
         (trailing (read port)))
    (close-port port)
    (unless (eof-object? trailing)
      (error 'read-corpus
        "the corpus file must hold exactly one list of entries; found data after it"
        path trailing))
    (unless (list? entries)
      (error 'read-corpus "the corpus is not a list" path))
    entries))

(define (run-entry entry)
  (let* ((name (car entry))
         (page-width (cadr entry))
         (computation-width (list-ref entry 2))
         (offset (list-ref entry 3))
         (document (list-ref entry 4))
         (factory (if computation-width
                      (default-cost-factory page-width computation-width)
                      (default-cost-factory page-width))))
    (display name)
    (display " ")
    (guard (e ((layout-failure? e) (display "NO-LAYOUT")))
      (let-values (((rendered result) (layout (build document) factory offset)))
        (write (layout-result-tainted? result))
        (display " ")
        (write (layout-result-cost result))
        (display " ")
        (write rendered)))
    (display "\n")))

(let ((entries (read-corpus corpus-path)))
  (display "entries ") (write (length entries)) (display "\n")
  (for-each run-entry entries))
