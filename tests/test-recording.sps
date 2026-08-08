#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for what pitch adds to the vendored laesare reader: absolute offset
;; tracking, line counting for every line ending the grammar recognizes, and
;; source-text recording on tokens.
;;
;; The upstream suite in tests/test-reader.sps is the regression baseline and
;; is kept unmodified; everything pitch-specific belongs here.
#!r6rs

(import
  (rnrs (6))
  (pitch reader)
  (tests runner))

(define (make-string-reader input)
  (make-reader (open-string-input-port input) "<test>"))

;; Read every datum in input, then report the reader's final state.
(define (drain input select)
  (let ((r (make-string-reader input)))
    (let lp ()
      (unless (eof-object? (read-datum r))
        (lp)))
    (select r)))

(define (final-line input) (drain input reader-line))
(define (final-offset input) (drain input reader-offset))

;; Line endings
(test-begin "line-endings")

;; Linefeed is the case upstream already handled.
(test-equal 2 (final-line "a\nb"))

;; Carriage return alone. Upstream left the line counter at 1 here.
(test-equal 2 (final-line "a\rb"))

;; CRLF is one line ending, not two.
(test-equal 2 (final-line "a\r\nb"))

;; Carriage return followed by next-line is likewise one ending.
(test-equal 2 (final-line "a\r\x85;b"))

;; The remaining separators the grammar and get-comment recognize.
(test-equal 2 (final-line "a\x85;b"))
(test-equal 2 (final-line "a\x2028;b"))
(test-equal 2 (final-line "a\x2029;b"))

;; Several endings in sequence, mixing forms.
(test-equal 3 (final-line "a\r\nb\rc"))
(test-equal 4 (final-line "a\nb\r\nc\rd"))

;; No line ending at all.
(test-equal 1 (final-line "a b"))

;; A bare carriage return at end of input still ends its line.
(test-equal 2 (final-line "a\r"))

;; Positions after a comment must agree with the comment lexer, which consumes
;; the terminator itself.
(test-equal 2 (final-line "; comment\ra"))
(test-equal 2 (final-line "; comment\r\na"))
(test-equal 2 (final-line "; comment\x2028;a"))
(test-end)

;; Absolute offset
(test-begin "offset")

;; Nothing consumed yet.
(test-equal 0 (reader-offset (make-string-reader "(abc def)")))

;; Offset counts characters, and every character of the input is consumed by
;; the time the reader reports end of file.
(test-equal 9 (final-offset "(abc def)"))
(test-equal 0 (final-offset ""))
(test-equal 3 (final-offset "abc"))

;; Atmosphere counts too.
(test-equal 12 (final-offset "  a ; hi\n  b"))

;; Multi-byte characters count once each, not once per byte.
(test-equal 3 (final-offset "\x3bb;\x3bb;\x3bb;"))
(test-end)

;;; Source-text recording

;; All tokens of input, up to but not including the eof token.
(define (tokens input . mode*)
  (let ((r (make-string-reader input)))
    (unless (null? mode*)
      (reader-mode-set! r (car mode*)))
    (let lp ((acc '()))
      (let ((t (get-token r)))
        (if (eq? (token-kind t) 'eof)
            (reverse acc)
            (lp (cons t acc)))))))

;; Tokenize and glue the raw text back together. Every scenario in the
;; token-source-recording spec ultimately reduces to this being the identity.
(define (round-trip input . mode*)
  (apply string-append (map token-text (apply tokens input mode*))))

;; The text of the first token, for checking a single construct's spelling.
(define (text-of input . mode*)
  (token-text (car (apply tokens input mode*))))

;; The parsed value of the first token, for checking that recording did not
;; displace parsing.
(define (value-of input . mode*)
  (token-value (car (apply tokens input mode*))))

(define (kind-of input . mode*)
  (token-kind (car (apply tokens input mode*))))

;; Does every token's span index back to its own text?
(define (spans-consistent? input . mode*)
  (for-all (lambda (t)
             (string=? (token-text t)
                       (substring input (token-start t) (token-end t))))
           (apply tokens input mode*)))

(test-begin "round-trip")
(test-equal "" (round-trip ""))
(test-equal "(a b)" (round-trip "(a b)"))
(test-equal "  (a  b )  " (round-trip "  (a  b )  "))
(test-equal "(a\n  b)\n" (round-trip "(a\n  b)\n"))
(test-equal "#(1 2 3)" (round-trip "#(1 2 3)"))
(test-equal "#vu8(1 2)" (round-trip "#vu8(1 2)"))
(test-equal "'(a . b)" (round-trip "'(a . b)"))
(test-equal "`(a ,b ,@c)" (round-trip "`(a ,b ,@c)"))
(test-end)

(test-begin "spans")
(test-assert (spans-consistent? "(a b)"))
(test-assert (spans-consistent? "  (a #;(b c) d) ; hi\n"))
(test-assert (spans-consistent? "#xff #true #\\null |foo|"))
(test-end)

;; Constructs whose parsed value discards the source spelling. Each case
;; asserts both halves: the text preserves the spelling, and the value is
;; still what the vendored reader produced.
(test-begin "recovered-spellings")

;; Radix and exponent notation.
(test-equal "#xff" (text-of "#xff"))
(test-equal 255 (value-of "#xff"))
(test-equal "#b1010" (text-of "#b1010"))
(test-equal 10 (value-of "#b1010"))
(test-equal "#e1.5" (text-of "#e1.5"))
(test-equal 3/2 (value-of "#e1.5"))
(test-equal "1e3" (text-of "1e3"))
(test-equal 1e3 (value-of "1e3"))

;; String escapes.
(test-equal "\"\\x41;\"" (text-of "\"\\x41;\""))
(test-equal "A" (value-of "\"\\x41;\""))
(test-equal "\"a\\nb\"" (text-of "\"a\\nb\""))
(test-equal "a\nb" (value-of "\"a\\nb\""))

;; Character names that the char-name table collapses.
(test-equal "#\\nul" (text-of "#\\nul" 'r6rs))
(test-equal "#\\null" (text-of "#\\null" 'r7rs))
(test-equal (value-of "#\\nul" 'r6rs) (value-of "#\\null" 'r7rs))
(test-equal "#\\linefeed" (text-of "#\\linefeed" 'r6rs))
(test-equal "#\\newline" (text-of "#\\newline" 'r6rs))
(test-equal (value-of "#\\linefeed" 'r6rs) (value-of "#\\newline" 'r6rs))
(test-equal "#\\esc" (text-of "#\\esc" 'r6rs))
(test-equal "#\\escape" (text-of "#\\escape" 'r7rs))
(test-equal (value-of "#\\esc" 'r6rs) (value-of "#\\escape" 'r7rs))

;; Boolean spellings.
(test-equal "#t" (text-of "#t"))
(test-equal "#true" (text-of "#true" 'r7rs))
(test-equal #t (value-of "#t"))
(test-equal #t (value-of "#true" 'r7rs))
(test-equal "#f" (text-of "#f"))
(test-equal "#false" (text-of "#false" 'r7rs))
(test-equal #f (value-of "#f"))
(test-equal #f (value-of "#false" 'r7rs))

;; Identifier spelling, including inline hex escapes.
(test-equal "|foo|" (text-of "|foo|"))
(test-equal 'foo (value-of "|foo|"))
(test-equal "foo" (text-of "foo"))
(test-equal 'foo (value-of "foo"))
(test-equal "a\\x62;c" (text-of "a\\x62;c"))
(test-equal 'abc (value-of "a\\x62;c"))

;; Bracket shape.
(test-equal 'openp (kind-of "(a)"))
(test-equal 'openb (kind-of "[a]"))
(test-equal "[" (text-of "[a]"))
(test-equal "[a]" (round-trip "[a]"))
(test-equal "(a [b] c)" (round-trip "(a [b] c)"))
(test-end)

;; Atmosphere must all be attributable, or concatenation loses characters.
(test-begin "atmosphere")
(test-equal "; a comment\n" (round-trip "; a comment\n"))
(test-equal "#| nested #| deeper |# |#" (round-trip "#| nested #| deeper |# |#"))
(test-equal "(a #;(b c) d)" (round-trip "(a #;(b c) d)"))
(test-equal "#;(b c)" (text-of "#;(b c)"))
(test-equal "#; (b c)" (text-of "#; (b c)"))
(test-equal "#;#;(a)(b)" (text-of "#;#;(a)(b)"))
(test-equal "(a #;b c)" (round-trip "(a #;b c)"))
(test-equal "#!r6rs (a)" (round-trip "#!r6rs (a)"))
(test-equal "#!fold-case (A)" (round-trip "#!fold-case (A)"))
(test-equal "#!r6rs" (text-of "#!r6rs (a)"))
(test-equal "#!/usr/bin/env scheme-script\n(a)"
            (round-trip "#!/usr/bin/env scheme-script\n(a)"))
(test-equal "#! guile comment !#\n(a)"
            (round-trip "#! guile comment !#\n(a)"))
(test-end)

;; Malformed input in tolerant mode. The discarded prefix is attributed to the
;; token that follows rather than dropped, so nothing is lost.
(test-begin "tolerant-round-trip")
(letrec ((tolerant-round-trip
          (lambda (input)
            (with-exception-handler
              (lambda (con)
                (unless (warning? con)
                  (raise con)))
              (lambda ()
                (let ((r (make-string-reader input)))
                  (reader-mode-set! r 'r7rs)
                  (reader-tolerant?-set! r #t)
                  (let lp ((acc '()))
                    (let ((t (get-token r)))
                      (if (eq? (token-kind t) 'eof)
                          (apply string-append (reverse acc))
                          (lp (cons (token-text t) acc)))))))))))
  (test-equal "(#1#)" (tolerant-round-trip "(#1#)"))
  (test-equal "#0= (#1#)" (tolerant-round-trip "#0= (#1#)"))
  (test-equal "#u8(#0=1 #0#)" (tolerant-round-trip "#u8(#0=1 #0#)"))
  (test-equal "(a #z b)" (tolerant-round-trip "(a #z b)"))
  (test-equal "#!bogus (a)" (tolerant-round-trip "#!bogus (a)")))
(test-end)

;; Whole files, as the most convincing evidence available.
(test-begin "round-trip-files")
(letrec ((file-contents
          (lambda (path)
            (let ((p (open-input-file path)))
              (let lp ((acc '()))
                (let ((c (get-char p)))
                  (if (eof-object? c)
                      (begin (close-port p)
                             (list->string (reverse acc)))
                      (lp (cons c acc)))))))))
  (for-each
   (lambda (path)
     (let ((source (file-contents path)))
       (test-equal source (round-trip source))
       (test-assert (spans-consistent? source))))
   '("src/pitch/reader.sls"
     "vendor/laesare/reader.sls"
     "vendor/laesare/writer.sls"
     "vendor/laesare/tests/test-reader.sps"
     "tests/runner.sls")))
(test-end)

;; Dialect gating must be exactly as before.
(test-begin "dialect-gating")
(letrec ((rejects?
          (lambda (input mode)
            (guard (con ((lexical-violation? con) #t))
              (tokens input mode)
              #f))))
  (test-assert (rejects? "#vu8(1)" 'r7rs))
  (test-assert (rejects? "#u8(1)" 'r6rs))
  (test-assert (not (rejects? "#vu8(1)" 'r6rs)))
  (test-assert (not (rejects? "#u8(1)" 'r7rs)))
  (test-assert (rejects? "#true" 'r6rs))
  (test-assert (not (rejects? "#true" 'r7rs))))
(test-end)

(test-exit)
