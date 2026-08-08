#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the datum projection and the layer 2 datum-equivalence check.
;;
;; Two conventions worth knowing before editing this file.
;;
;; Cyclic data are asserted with test-assert over a boolean, never with
;; test-equal over the datum itself. The runner writes expected and actual on
;; failure, and writing a cyclic datum is not something to risk in a test that
;; is already failing.
;;
;; The layer 2 negative tests matter more than the positive ones. A comparator
;; that returns #t unconditionally passes every positive test in this file.
#!r6rs

(import
  (rnrs (6))
  (rnrs io simple (6))                  ;the host reader, as a test oracle only
  (pitch reader)
  (pitch cst)
  (pitch parse)
  (pitch datum)
  (pitch check)
  (tests runner))

;; The data of a source, ignoring diagnostics.
(define (proj source)
  (let-values (((document parse-diagnostics) (parse-source source "<test>")))
    (let-values (((data datum-diagnostics) (cst->datum document)))
      data)))

;; The single top-level datum, for the many sources that have exactly one.
(define (proj1 source) (car (proj source)))

;; Diagnostics from the projection alone, so a test can tell which layer
;; reported a defect.
(define (datum-diagnostics-of source)
  (let-values (((document parse-diagnostics) (parse-source source "<test>")))
    (let-values (((data datum-diagnostics) (cst->datum document)))
      datum-diagnostics)))

;; Diagnostics from both layers, which is what a caller actually sees.
(define (all-diagnostics-of source)
  (let-values (((document parse-diagnostics) (parse-source source "<test>")))
    (let-values (((data datum-diagnostics) (cst->datum document)))
      (append parse-diagnostics datum-diagnostics))))

(define (equivalent? a b)
  (let-values (((ok? diagnostics) (check-datum-equivalence a b))) ok?))

(define (check-diagnostics a b)
  (let-values (((ok? diagnostics) (check-datum-equivalence a b))) diagnostics))

;;; Projection

(test-begin "projection")

(test-equal '(a b c) (proj1 "(a b c)"))
(test-equal '() (proj1 "()"))
(test-equal 'a (proj1 "a"))
(test-equal "s" (proj1 "\"s\""))
(test-equal #\a (proj1 "#\\a"))
(test-equal 42 (proj1 "42"))
(test-equal #t (proj1 "#t"))
(test-equal #f (proj1 "#f"))
(test-assert (vector? (proj1 "#(1 2)")))
(test-equal '#(1 2) (proj1 "#(1 2)"))
(test-assert (bytevector? (proj1 "#vu8(1 2)")))
(test-equal '#vu8(1 2) (proj1 "#vu8(1 2)"))
(test-equal '(1 (2 (3))) (proj1 "(1 (2 (3)))"))

;; Several top-level data, in source order.
(test-equal '((a) (b)) (proj "(a) (b)"))
(test-equal 2 (length (proj "(a) (b)")))

(test-end)

;;; Spelling is discarded, exactly as the lexer discarded it

(test-begin "spelling-discarded")

(test-equal (proj1 "255") (proj1 "#xff"))
(test-equal 255 (proj1 "#xff"))
(test-equal (proj1 "\"A\"") (proj1 "\"\\x41;\""))
(test-equal "A" (proj1 "\"\\x41;\""))
(test-equal (proj1 "#\\null") (proj1 "#\\nul"))
(test-equal (proj1 "10000000000.0") (proj1 "1E10"))
(test-equal (proj1 "foo") (proj1 "|foo|"))
(test-equal (proj1 "(a b)") (proj1 "[a b]"))

;; Folding happened at lex time, so the projection inherits it rather than
;; implementing it.
(test-equal '(foo) (proj1 "#!fold-case\n(Foo)"))
(test-equal '(Foo) (proj1 "(Foo)"))

(test-end)

;;; Trivia contribute nothing

(test-begin "trivia")

(test-equal '(a b) (proj1 "(a ; note\n b)"))
(test-equal '(a b) (proj1 "(a #| block |# b)"))
(test-equal '(a d) (proj1 "(a #;(b c) d)"))
(test-equal '(a) (proj1 "#!r6rs (a)"))
(test-equal '() (proj "; just a comment\n"))
(test-equal '() (proj ""))
(test-equal 0 (length (all-diagnostics-of "; just a comment\n")))

(test-end)

;;; Abbreviations

(test-begin "abbreviations")

(test-equal '(quote x) (proj1 "'x"))
(test-equal '(quasiquote x) (proj1 "`x"))
(test-equal '(unquote x) (proj1 ",x"))
(test-equal '(unquote-splicing x) (proj1 ",@x"))
(test-equal '(syntax x) (proj1 "#'x"))
(test-equal '(quasisyntax x) (proj1 "#`x"))
(test-equal '(unsyntax x) (proj1 "#,x"))
(test-equal '(unsyntax-splicing x) (proj1 "#,@x"))

(test-equal '(quote (quote x)) (proj1 "''x"))
(test-equal '(a (quote b)) (proj1 "(a 'b)"))
(test-equal '(quote (a b)) (proj1 "'(a b)"))

;; Trivia between the marker and its datum do not survive into the datum.
(test-equal '(quote x) (proj1 "' ; why\n x"))

(test-end)

;;; Improper lists

(test-begin "improper-lists")

(test-equal '(a . b) (proj1 "(a . b)"))
(test-equal '(a b . c) (proj1 "(a b . c)"))
(test-equal '(a . b) (proj1 "(a . ; why\n b)"))
(test-assert (not (list? (proj1 "(a . b)"))))
(test-equal 'b (cdr (proj1 "(a . b)")))

(test-end)

;;; Datum labels

(test-begin "datum-labels")

;; A reference is the same object, not merely an equal one.
(test-assert (let ((d (proj1 "(#0=(a) #0#)")))
               (eq? (car d) (cadr d))))
(test-equal 0 (length (all-diagnostics-of "(#0=(a) #0#)")))

;; Cyclic structure. Asserted as booleans; see the header.
(test-assert (let ((d (proj1 "#0=(a . #0#)"))) (eq? (cdr d) d)))
(test-assert (let ((d (proj1 "#0=(a . #0#)"))) (eq? (car d) 'a)))
(test-equal 0 (length (all-diagnostics-of "#0=(a . #0#)")))

(test-assert (let ((d (proj1 "#0=#(a #0#)"))) (eq? (vector-ref d 1) d)))
(test-assert (let ((d (proj1 "#0=#(a #0#)"))) (eq? (vector-ref d 0) 'a)))

;; A label deeper than the top of the datum.
(test-assert (let ((d (proj1 "(x #0=(a) (y #0#))")))
               (eq? (cadr d) (cadr (caddr d)))))

;; Labels are scoped per top-level datum, so this reference resolves against
;; nothing even though the spelling matches the preceding label.
(test-assert (positive? (length (all-diagnostics-of "#0=1 #0#"))))

(test-end)

;;; Defects the parser cannot see

(test-begin "projection-diagnostics")

(letrec ((parse-clean?
          (lambda (source)
            (let-values (((document parse-diagnostics)
                          (parse-source source "<test>")))
              (null? parse-diagnostics)))))
  ;; The premise of this whole group: structure says these are fine.
  (test-assert (parse-clean? "(#1#)"))
  (test-assert (parse-clean? "#0=#0=1"))
  (test-assert (parse-clean? "#vu8(300)"))
  (test-assert (parse-clean? "#0=1 #vu8(#0#)")))

(test-assert (positive? (length (datum-diagnostics-of "(#1#)"))))
(test-assert (positive? (length (datum-diagnostics-of "#0=#0=1"))))
(test-assert (positive? (length (datum-diagnostics-of "#vu8(300)"))))
(test-assert (positive? (length (datum-diagnostics-of "#0=1 #vu8(#0#)"))))
(test-assert (positive? (length (datum-diagnostics-of "#vu8(a)"))))
(test-assert (positive? (length (datum-diagnostics-of "'"))))

;; The first binding is kept.
(test-equal 1 (proj1 "#0=#0=1"))

;; A diagnostic reports the start of the token it concerns.
(let ((d (car (datum-diagnostics-of "(#1#)"))))
  (test-equal 1 (diagnostic-line d))
  (test-equal 1 (diagnostic-column d))
  (test-equal (token-start-line (diagnostic-token d)) (diagnostic-line d))
  (test-equal (token-start-column (diagnostic-token d)) (diagnostic-column d)))

(let ((d (car (datum-diagnostics-of "(a\n b\n #vu8(300))"))))
  (test-equal 3 (diagnostic-line d)))

(test-end)

;;; The projection never raises

(test-begin "totality")

;; Every malformed source from the CST suite must project, not raise. If any
;; of these raised, the runner would report it as an error rather than a fail.
(for-each (lambda (source)
            (test-assert (begin (proj source) #t)))
          '("(a (b" "a)" "'" "(. a)" "(a]" "(a #z b)" "(a . b c)" "(a . . b)"
            "#(a . b)" "(')" "#!bogus (a)" "(#1#)" "#vu8(300)" ""))

(test-end)

;;; No branching on dialect

(test-begin "dialect")

(test-equal (proj1 "#vu8(1 2)") (proj1 "#u8(1 2)"))
(test-equal (proj1 "#t") (proj1 "#true"))
(test-equal (proj1 "#f") (proj1 "#false"))
(test-equal 0 (length (all-diagnostics-of "#u8(1 2)")))

(test-end)

;;; datum=?

(test-begin "datum-equivalence-operation")

(test-assert (datum=? (proj "(a (b c))") (proj "(a (b c))")))
(test-assert (not (datum=? (proj "(a b)") (proj "(a c)"))))

;; Cyclic arguments must terminate. The test completing is the assertion.
(test-assert (datum=? (proj "#0=(a . #0#)") (proj "#0=(a . #0#)")))
(test-assert (not (datum=? (proj "#0=(a . #0#)") (proj "#0=(b . #0#)"))))
(test-assert (datum=? (proj "#0=#(a #0#)") (proj "#0=#(a #0#)")))
(test-assert (not (datum=? (proj "#0=#(a #0#)") (proj "#0=#(b #0#)"))))

(test-end)

;;; Number edge cases
;;
;; These record what Chez actually answers rather than what would be
;; convenient. Layer 2 needs only that both sides of a comparison are treated
;; the same way, which any of these answers satisfies.

(test-begin "number-edge-cases")

(test-assert (not (datum=? (proj "1") (proj "1.0"))))   ;exactness is significant
(test-assert (not (datum=? (proj "0.0") (proj "-0.0"))))
(test-assert (datum=? (proj "+nan.0") (proj "+nan.0")))
(test-assert (datum=? (proj "1/2") (proj "1/2")))
(test-assert (not (datum=? (proj "1/2") (proj "0.5"))))

(test-end)

;;; Layer 2: sources that differ only in layout

(test-begin "layer2-equivalent")

(test-assert (equivalent? "(define (f x)\n  (g x))" "(define (f x) (g x))"))
(test-assert (equivalent? "(a b)" "(a ; note\n b)"))
(test-assert (equivalent? "(a\n\n  b)" "(a b)"))
(test-assert (equivalent? "  (a b)  " "(a b)"))
(test-assert (equivalent? "(a #| c |# b)" "(a b)"))
(test-assert (equivalent? "(a)\n(b)" "(a) (b)"))

(test-end)

;;; Layer 2: sources that differ in meaning
;;
;; The load-bearing group. A comparator returning #t unconditionally passes
;; every test above and fails every test here.

(test-begin "layer2-not-equivalent")

(test-assert (not (equivalent? "(a b)" "(a c)")))
(test-assert (not (equivalent? "(a) (b)" "(a)")))
(test-assert (not (equivalent? "(a (b c))" "(a b c)")))
(test-assert (not (equivalent? "(a b)" "(a b c)")))
(test-assert (not (equivalent? "(a . b)" "(a b)")))
(test-assert (not (equivalent? "(a b)" "(b a)")))
(test-assert (not (equivalent? "#(1 2)" "(1 2)")))
(test-assert (not (equivalent? "1" "1.0")))
(test-assert (not (equivalent? "\"a\"" "a")))
(test-assert (not (equivalent? "(a)" "()")))

(test-end)

;;; Layer 2: defects fail rather than compare

(test-begin "layer2-failure")

;; Identical texts, but neither is usable, so this is a failure and not an
;; equivalence.
(test-assert (not (equivalent? "(a (b" "(a (b")))
(test-assert (positive? (length (check-diagnostics "(a (b" "(a (b"))))
(test-assert (not (equivalent? "(#1#)" "(#1#)")))
(test-assert (positive? (length (check-diagnostics "(#1#)" "(#1#)"))))
(test-assert (not (equivalent? "(a b)" "(a b")))
(test-assert (not (equivalent? "#vu8(300)" "#vu8(300)")))

;; A clean pair reports no diagnostics at all.
(test-equal '() (check-diagnostics "(a b)" "(a  b)"))

(test-end)

;;; Layer 2: the known weaknesses, pinned
;;
;; Each of these PASSES datum equivalence. That is the documented weakness,
;; and layer 1 exists to catch every one of them. Pinning them as tests keeps
;; the weakness visible to whoever reads this file next.

(test-begin "layer2-known-weaknesses")

(test-assert (equivalent? "(a ; note\n b)" "(a b)"))          ;comment deleted
(test-assert (equivalent? "(a #;(x) b)" "(a b)"))             ;#; elision moved
(test-assert (equivalent? "[a b]" "(a b)"))                   ;bracket flipped
(test-assert (equivalent? "'x" "(quote x)"))                  ;abbrev expanded
(test-assert (equivalent? "#xff" "255"))                      ;radix changed
(test-assert (equivalent? "\"\\x41;\"" "\"A\""))              ;escape respelled
(test-assert (equivalent? "#\\nul" "#\\null"))                ;char name changed
(test-assert (equivalent? "#vu8(1)" "#u8(1)"))                ;dialect spelling

(test-end)

;;; Differential oracle: the host reader
;;
;; A test oracle only. No shipped library calls the host reader, and
;; tests/test-datum.sps is the only place this import appears.
;;
;; Coverage is bounded by what the oracle accepts. Chez's read rejects datum
;; labels (#0= and #0#) and R7RS bytevectors (#u8), so those -- including the
;; most intricate part of the projection, label resolution -- are covered by
;; the written expectations above and NOT by this group. A passing run here is
;; not full coverage.

(test-begin "differential-oracle")

(letrec ((file-contents
          (lambda (path)
            (let ((p (open-input-file path)))
              (let lp ((acc '()))
                (let ((c (get-char p)))
                  (if (eof-object? c)
                      (begin (close-port p) (list->string (reverse acc)))
                      (lp (cons c acc))))))))
         (host-read-all
          (lambda (path)
            (let ((p (open-input-file path)))
              (let lp ((acc '()))
                (let ((d (read p)))
                  (if (eof-object? d)
                      (begin (close-port p) (reverse acc))
                      (lp (cons d acc)))))))))
  (for-each
   (lambda (path)
     (test-equal (host-read-all path) (proj (file-contents path))))
   '("src/pitch/reader.sls"
     "src/pitch/cst.sls"
     "src/pitch/parse.sls"
     "src/pitch/datum.sls"
     "src/pitch/check.sls"
     "src/pitch/diagnostic.sls"
     "vendor/laesare/reader.sls"
     "vendor/laesare/writer.sls"
     "tests/runner.sls")))

;; Targeted constructs the oracle does accept.
(letrec ((host (lambda (s) (read (open-string-input-port s)))))
  (for-each
   (lambda (source) (test-equal (host source) (proj1 source)))
   '("'x" "`x" ",x" ",@x"
     "(a . b)" "(a b . c)" "(a (b (c)))" "()"
     "#(1 2 3)" "#vu8(1 2 3)"
     "#xff" "1E10" "1/2" "-0.0"
     "\"\\x41;\"" "#\\nul" "#\\space" "|foo bar|"
     "#t" "#f" "#true"
     "(define (f x) (if (null? x) '() (cons 1 x)))")))

(test-end)

(test-exit)
