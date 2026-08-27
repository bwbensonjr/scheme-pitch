#!/usr/bin/env scheme-script
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT
#!r6rs

;; Independent host-reader side of the datum oracle. It imports no Pitch
;; library: every value comes directly from Chez's read over serialized text.
(import
  (rnrs (6))
  (rnrs io simple (6)))

(define corpus
  '("src/pitch/reader.sls"
    "vendor/laesare/reader.sls"
    "vendor/laesare/writer.sls"
    "tests/runner.sls"))

(define targeted
  '("'x" "`x" ",x" ",@x"
    "(a . b)" "(a b . c)" "(a (b (c)))" "()"
    "#(1 2 3)" "#vu8(1 2 3)"
    "#xff"
    "\"\\x41;\"" "#\\nul" "#\\space" "|foo bar|"
    "#t" "#f" "#true"
    "(define (f x) (if (null? x) '() (cons 1 x)))"))

(define (emit-text tag text)
  (display tag)
  (display (string-length text))
  (display ":")
  (let loop ((index 0))
    (unless (= index (string-length text))
      (display (char->integer (string-ref text index)))
      (display ",")
      (loop (+ index 1))))
  (display ";"))

;; A host-neutral serializer: writer spellings for characters, bytevectors,
;; identifiers, and inexact numbers differ legitimately between Chez and Emit.
(define (emit-value datum)
  (cond
    ((null? datum) (display "N"))
    ((eq? datum #t) (display "T"))
    ((eq? datum #f) (display "F"))
    ((char? datum) (display "C") (display (char->integer datum)) (display ";"))
    ((string? datum) (emit-text "S" datum))
    ((symbol? datum) (emit-text "Y" (symbol->string datum)))
    ((and (number? datum) (exact? datum) (integer? datum))
     (display "I") (display (number->string datum)) (display ";"))
    ((pair? datum) (display "P") (emit-value (car datum)) (emit-value (cdr datum)))
    ((vector? datum)
     (display "V") (display (vector-length datum)) (display ":")
     (let loop ((index 0))
       (unless (= index (vector-length datum))
         (emit-value (vector-ref datum index))
         (loop (+ index 1))))
     (display ";"))
    ((bytevector? datum)
     (display "B") (display (bytevector-length datum)) (display ":")
     (let loop ((index 0))
       (unless (= index (bytevector-length datum))
         (display (bytevector-u8-ref datum index))
         (display ",")
         (loop (+ index 1))))
     (display ";"))
    (else (assertion-violation 'datum-oracle "unsupported oracle datum" datum))))

(define (emit datum)
  (emit-value datum)
  (newline))

(for-each
 (lambda (path)
   (display "file ") (emit path)
   (let ((port (open-input-file path)))
     (let loop ()
       (let ((datum (read port)))
         (if (eof-object? datum)
             (close-port port)
             (begin (emit datum) (loop)))))))
 corpus)

(for-each
 (lambda (source)
   (display "source ") (emit source)
   (emit (read (open-string-input-port source))))
 targeted)
