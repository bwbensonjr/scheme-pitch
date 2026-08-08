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

;; Reading past the end of input must not move the reported position. The
;; reader used to advance the column for the end-of-file object, which put the
;; position one past the last character.
(test-begin "end-of-input")
(let ((r (make-string-reader "ab\ncd")))
  (let lp () (unless (eof-object? (read-datum r)) (lp)))
  (let ((line (reader-line r))
        (column (reader-column r))
        (offset (reader-offset r)))
    (test-equal 2 line)
    (test-equal 2 column)
    (test-equal 5 offset)
    ;; Keep reading well past the end; nothing may move.
    (read-datum r)
    (read-datum r)
    (test-equal line (reader-line r))
    (test-equal column (reader-column r))
    (test-equal offset (reader-offset r))))
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

;;; Positions

;; Walk the source to an offset and return (line column), independently of the
;; reader. If this and the reader ever disagree, one of them is wrong; the point
;; is that they are not the same code.
(define (offset->position src offset)
  (let lp ((i 0) (line 1) (column 0))
    (if (>= i offset)
        (list line column)
        (let ((c (string-ref src i)))
          (cond ((memv c '(#\linefeed #\x85 #\x2028 #\x2029))
                 (lp (+ i 1) (+ line 1) 0))
                ((char=? c #\return)
                 (if (and (< (+ i 1) (string-length src))
                          (memv (string-ref src (+ i 1)) '(#\linefeed #\x85)))
                     (lp (+ i 1) line (+ column 1))
                     (lp (+ i 1) (+ line 1) 0)))
                (else
                 (lp (+ i 1) line (+ column 1))))))))

(define (token-start-position t)
  (list (token-start-line t) (token-start-column t)))

(define (token-end-position t)
  (list (token-end-line t) (token-end-column t)))

;; Every token's recorded positions must agree with the reference walk.
(define (positions-agree? input . mode*)
  (for-all (lambda (t)
             (and (equal? (token-start-position t)
                          (offset->position input (token-start t)))
                  (equal? (token-end-position t)
                          (offset->position input (token-end t)))))
           (apply tokens input mode*)))

;; Half-openness: each token's end position is the next token's start position.
(define (positions-contiguous? input . mode*)
  (let lp ((ts (apply tokens input mode*)))
    (cond ((or (null? ts) (null? (cdr ts))) #t)
          ((equal? (token-end-position (car ts))
                   (token-start-position (cadr ts)))
           (lp (cdr ts)))
          (else #f))))

(define (nth-token input n . mode*)
  (list-ref (apply tokens input mode*) n))

(test-begin "positions")

;; Agreement with an independent walk of the source, over inputs exercising
;; multi-line tokens, atmosphere and every line-ending form.
(test-assert (positions-agree? "(a b)"))
(test-assert (positions-agree? "(a\n  #;(b\n     c)\n  d)"))
(test-assert (positions-agree? "x\r\ny #| m\nn |# z"))
(test-assert (positions-agree? "a ; hi\nb"))
(test-assert (positions-agree? "a\rb\r\nc\x85;d\x2028;e\x2029;f"))
(test-assert (positions-agree? "#!r6rs\n(a)"))
(test-assert (positions-agree? "#!/usr/bin/env scheme-script\n(a)"))

;; Contiguity, which is what half-open means operationally.
(test-assert (positions-contiguous? "(a\n  #;(b\n     c)\n  d)"))
(test-assert (positions-contiguous? "a ; hi\nb"))
(test-assert (positions-contiguous? "x\r\ny #| m\nn |# z"))
(test-end)

(test-begin "position-origin")
;; The first token of a source starts at the origin.
(test-equal '(1 0) (token-start-position (nth-token "(a)" 0)))
(test-equal '(1 0) (token-start-position (nth-token "   x" 0)))
(test-equal '(1 0) (token-start-position (nth-token "; c\nx" 0)))
(test-end)

(test-begin "position-extent")
;; A token confined to one line: same line, column advanced by its length.
(let ((t (nth-token "\n\n    abc" 1)))       ;the identifier, after whitespace
  (test-equal '(3 4) (token-start-position t))
  (test-equal '(3 7) (token-end-position t))
  (test-equal "abc" (token-text t)))

;; A token spanning lines: end column is measured from its final line.
(let ((t (nth-token "x #| m\nn |# z" 2)))    ;the nested comment
  (test-equal "#| m\nn |#" (token-text t))
  (test-equal '(1 2) (token-start-position t))
  (test-equal '(2 4) (token-end-position t)))

;; A token whose text ends with a line ending reports the following line.
(let ((t (nth-token "a ; hi\nb" 2)))         ;the line comment
  (test-equal "; hi\n" (token-text t))
  (test-equal '(1 2) (token-start-position t))
  (test-equal '(2 0) (token-end-position t)))
(test-end)

;; The recursive lexer paths, where reader-saved-line and reader-saved-column
;; describe the innermost entry rather than the token returned.
(test-begin "position-recursive-paths")

;; The datum comment starts at its own #;, not at the datum inside it. The
;; reader's saved position reports 3/6 here.
(let ((t (nth-token "(a\n  #;(b\n     c)\n  d)" 3)))
  (test-equal "#;(b\n     c)" (token-text t))
  (test-equal '(2 2) (token-start-position t))
  (test-equal '(3 7) (token-end-position t)))

;; A directive that is not at the start of the source.
(let ((t (nth-token "(a)\n#!fold-case\n(B)" 4)))
  (test-equal "#!fold-case" (token-text t))
  (test-equal '(2 0) (token-start-position t)))

;; Malformed input recovered in tolerant mode.
(with-exception-handler
  (lambda (con) (unless (warning? con) (raise con)))
  (lambda ()
    (let ((r (make-string-reader "(a\n #z b)")))
      (reader-mode-set! r 'r7rs)
      (reader-tolerant?-set! r #t)
      (let lp ((acc '()))
        (let ((t (get-token r)))
          (if (eq? (token-kind t) 'eof)
              (let ((ts (reverse acc)))
                ;; Whatever the recovery produced, positions stay consistent
                ;; with the offsets and remain contiguous.
                (test-assert
                 (for-all (lambda (t)
                            (equal? (token-start-position t)
                                    (offset->position "(a\n #z b)"
                                                      (token-start t))))
                          ts)))
              (lp (cons t acc))))))))
(test-end)

(test-begin "position-end-of-file")
;; The eof token is zero-width, so its start and end positions coincide and
;; match its offsets.
(let* ((ts (let ((r (make-string-reader "ab\ncd")))
             (let lp ((acc '()))
               (let ((t (get-token r)))
                 (if (eq? (token-kind t) 'eof)
                     (reverse (cons t acc))
                     (lp (cons t acc)))))))
       (eof (list-ref ts (- (length ts) 1))))
  (test-equal 'eof (token-kind eof))
  (test-equal (token-start eof) (token-end eof))
  (test-equal (token-start-position eof) (token-end-position eof))
  (test-equal '(2 2) (token-start-position eof)))
(test-end)

(test-exit)
