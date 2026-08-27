;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Pitch side of the external datum oracle. Serialized source text is re-read
;; through the shipped Emit parser/projection before values are serialized for
;; comparison with tests/oracle/datum-host.sps.
(import
  (scheme base)
  (scheme file)
  (pitch parse)
  (pitch datum))

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

(define corpus
  '("src/pitch/reader.sls"
    "vendor/laesare/reader.sls"
    "vendor/laesare/writer.sls"
    "tests/runner.sls"))

;; This oracle covers only values both hosts represent. Emit's opaque numeric
;; path has direct written expectations in test-datum-r7rs.scm instead.
(define targeted
  '("'x" "`x" ",x" ",@x"
    "(a . b)" "(a b . c)" "(a (b (c)))" "()"
    "#(1 2 3)" "#vu8(1 2 3)"
    "#xff"
    "\"\\x41;\"" "#\\nul" "#\\space" "|foo bar|"
    "#t" "#f" "#true"
    "(define (f x) (if (null? x) '() (cons 1 x)))"))

(define (read-text path)
  (let ((port (open-input-file path)))
    (let loop ((characters '()))
      (let ((character (read-char port)))
        (if (eof-object? character)
            (begin (close-port port) (list->string (reverse characters)))
            (loop (cons character characters)))))))

(define (project source filename)
  (let-values (((document parse-diagnostics) (parse-source source filename)))
    (let-values (((data datum-diagnostics) (cst->datum document)))
      (let ((diagnostics (append parse-diagnostics datum-diagnostics)))
        (if (null? diagnostics)
            data
            (error 'datum-oracle "Pitch diagnostics" filename diagnostics))))))

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
    (else (error 'datum-oracle "unsupported oracle datum" datum))))

(define (emit datum)
  (emit-value datum)
  (newline))

(for-each
 (lambda (path)
   (display "file ") (emit path)
   (for-each emit (project (read-text path) path)))
 corpus)

(for-each
 (lambda (source)
   (display "source ") (emit source)
   (emit (car (project source "<oracle>"))))
 targeted)
