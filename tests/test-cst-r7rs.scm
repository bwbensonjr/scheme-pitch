;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the CST layer: the node representation, the parser, and the
;; layer 0 round-trip check.
;;
;; The round-trip tests compare against the text that was parsed, never
;; against anything derived from the tree. Serializing a tree and comparing it
;; to something that tree produced passes no matter what the serializer did,
;; and is the single easiest mistake to make here.
(import
  (scheme base)
  (scheme file)
  (pitch reader)
  (pitch cst)
  (pitch diagnostic)
  (pitch parse)
  (pitch sequence)
  (tests runner))

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

(define (parse s)
  (let-values (((document diagnostics) (parse-source s "<test>")))
    document))

(define (diagnostics-of s)
  (let-values (((document diagnostics) (parse-source s "<test>")))
    diagnostics))

(define (diagnostic-count s) (length (diagnostics-of s)))

(define (round-trip s) (cst->text (parse s)))

;; The data children of the document, skipping top-level trivia.
(define (top-data s) (datum-children (parse s)))

;; The single top-level form, for the many inputs that have exactly one.
(define (only-form s) (car (top-data s)))

(define (child-texts node) (map cst->text (node-children node)))

;;; Leaf text

(test-begin "leaf-text")

;; The token is the authority; the parsed value never is.
(test-equal "#xff" (cst->text (only-form "#xff")))
(test-equal "#true" (cst->text (only-form "#true")))
(test-equal "#\\nul" (cst->text (only-form "#\\nul")))
(test-equal "|foo bar|" (cst->text (only-form "|foo bar|")))
(test-equal "\"\\x41;\"" (cst->text (only-form "\"\\x41;\"")))

;; leaf-text and the token agree by construction, not by copying.
(test-assert (let ((l (only-form "#xff")))
               (and (leaf? l)
                    (string=? (leaf-text l) (token-text (leaf-token l))))))

;; Case folding changes token values, not token text, so it cannot damage
;; losslessness.
(test-equal "A" (cst->text (car (datum-children
                                 (only-form "#!fold-case\n(A)")))))

(test-end)

;;; Trivia are ordinary children

(test-begin "trivia")

;; A comment between two elements is a sibling of both, in source order.
(test-equal '("a" " " "; note\n" " " "b")
            (child-texts (only-form "(a ; note\n b)")))

;; Trivia before a closing delimiter are retained and the list still closes.
(test-equal '("a" " " "; trailing\n" " ")
            (child-texts (only-form "(a ; trailing\n )")))
(test-assert (compound-close (only-form "(a ; trailing\n )")))

;; Nested comments and datum comments are children like any other trivia.
(test-equal '("a" " " "#| block |#" " " "b")
            (child-texts (only-form "(a #| block |# b)")))

;; The trivia predicate separates them from data without inspecting kinds.
(test-equal '(#f #t #t #t #f)
            (map trivia? (node-children (only-form "(a ; note\n b)"))))
(test-equal '("a" "b")
            (map cst->text (datum-children (only-form "(a ; note\n b)"))))

(test-end)

;;; Delimiters

(test-begin "delimiters")

;; Delimiters are named, not positional, and are not in the child sequence.
(test-equal "(" (cst->text (compound-open (only-form "(a)"))))
(test-equal ")" (cst->text (compound-close (only-form "(a)"))))
(test-equal '("a") (child-texts (only-form "(a)")))

;; An unclosed delimiter is represented by an absent close, not by a
;; synthesized one.
(test-equal #f (compound-close (only-form "(a")))
(test-equal "(" (cst->text (compound-open (only-form "(a"))))
(test-equal '("a") (child-texts (only-form "(a")))

;; Bracket shape lives in the tokens; both shapes give the same node kind.
(test-equal 'list (node-kind (only-form "(a)")))
(test-equal 'list (node-kind (only-form "[a]")))
(test-equal "[" (cst->text (compound-open (only-form "[a]"))))
(test-equal "]" (cst->text (compound-close (only-form "[a]"))))

(test-end)

;;; Node kinds

(test-begin "node-kinds")

(test-equal 'document (node-kind (parse "(a)")))
(test-equal 'list (node-kind (only-form "(a)")))
(test-equal 'vector (node-kind (only-form "#(a)")))
(test-equal 'bytevector (node-kind (only-form "#vu8(1)")))
(test-equal 'prefix (node-kind (only-form "'a")))
(test-equal 'leaf (node-kind (only-form "a")))

;; Vectors are list-like: their contents are parsed and their comments are
;; ordinary children, not text inside an opaque node.
(test-equal '("a" " " "; note\n" " " "b")
            (child-texts (only-form "#(a ; note\n b)")))
(test-equal '("1" " " "2" " " "3") (child-texts (only-form "#vu8(1 2 3)")))
(test-equal "#vu8(" (cst->text (compound-open (only-form "#vu8(1)"))))

;; The representation does not branch on dialect: the same node kind, with the
;; spelling difference carried by the opening token's text.
(test-equal (node-kind (only-form "#vu8(1)")) (node-kind (only-form "#u8(1)")))
(test-equal "#u8(" (cst->text (compound-open (only-form "#u8(1)"))))
(test-equal (node-kind (only-form "#t")) (node-kind (only-form "#true")))

(test-end)

;;; Datum comments

(test-begin "datum-comments")

;; One opaque leaf spanning the marker and the commented datum. No list node
;; is built for the elided form.
(test-equal '("a" " " "#;(b c)" " " "d")
            (child-texts (only-form "(a #;(b c) d)")))
(test-assert (let ((c (cadr (cdr (node-children (only-form "(a #;(b c) d)"))))))
               (and (leaf? c) (trivia? c))))
(test-equal '("a" "d")
            (map cst->text (datum-children (only-form "(a #;(b c) d)"))))

;; Whatever the atmosphere inside it, it stays one leaf. A #; at top level is
;; trivia and so is not a datum child of the document at all.
(test-equal '() (top-data "#; (b c)"))
(test-equal '("#; (b c)") (child-texts (parse "#; (b c)")))
(test-equal '("#;#;(a)(b)") (child-texts (parse "#;#;(a)(b)")))
(test-assert (leaf? (car (node-children (parse "#;#;(a)(b)")))))

(test-end)

;;; Prefixes

(test-begin "prefixes")

;; An abbreviation is never rewritten to its expansion.
(test-equal "'" (cst->text (prefix-marker (only-form "'x"))))
(test-equal "x" (cst->text (prefix-datum (only-form "'x"))))
(test-assert (not (string=? "quote" (cst->text (only-form "'x")))))

(test-equal ",@" (cst->text (prefix-marker (only-form ",@x"))))
(test-equal "x" (cst->text (prefix-datum (only-form ",@x"))))
(test-equal "`" (cst->text (prefix-marker (only-form "`x"))))
(test-equal "#'" (cst->text (prefix-marker (only-form "#'x"))))

;; Abbreviations nest as prefixes.
(test-equal 'prefix (node-kind (prefix-datum (only-form "''x"))))

;; Trivia between the marker and its datum belong to the prefix.
(test-equal '(" " "; why\n" " ") (child-texts (only-form "' ; why\n x")))
(test-equal "x" (cst->text (prefix-datum (only-form "' ; why\n x"))))

;; A datum label is a prefix; a reference is a leaf.
(test-equal 'prefix (node-kind (only-form "#0=(a . #0#)")))
(test-equal "#0=" (cst->text (prefix-marker (only-form "#0=(a . #0#)"))))
(test-equal 'list (node-kind (prefix-datum (only-form "#0=(a . #0#)"))))
(test-equal 'leaf
            (node-kind (list-ref (datum-children
                                  (prefix-datum (only-form "#0=(a . #0#)")))
                                 2)))

(test-end)

;;; Improper lists

(test-begin "improper-lists")

;; The dot is an ordinary child, with no node or field of its own.
(test-equal '("a" " " "." " " "b") (child-texts (only-form "(a . b)")))
(test-assert (list-improper? (only-form "(a . b)")))
(test-assert (not (list-improper? (only-form "(a b)"))))

;; Trivia around the dot are retained and do not disturb the predicate.
(test-assert (list-improper? (only-form "(a . ; why\n b)")))
(test-equal '("a" " " "." " " "; why\n" " " "b")
            (child-texts (only-form "(a . ; why\n b)")))

;; Invalid dot positions are not improper lists.
(test-assert (not (list-improper? (only-form "(. a)"))))
(test-assert (not (list-improper? (only-form "(a . b c)"))))
(test-assert (not (list-improper? (only-form "(a . . b)"))))

(test-end)

;;; The leaf sequence is the token sequence

(test-begin "leaf-sequence")

(letrec ((leaves-match-tokens?
          (lambda (source)
            (let-values (((tokens lex-diagnostics) (tokenize source "<test>")))
              (let-values (((document parse-diagnostics)
                            (parse-tokens tokens)))
                (equal? (cst-tokens document) (vector->list tokens)))))))
  ;; Well-formed input.
  (test-assert (leaves-match-tokens? "(a b)"))
  (test-assert (leaves-match-tokens? "#(1 #;(x) 2) '[a . b] #0=#(#0#)"))
  (test-assert (leaves-match-tokens? "#!r6rs\n;; c\n(a #| b |# . c)\n"))
  ;; Malformed input: nothing is swallowed by an error node either.
  (test-assert (leaves-match-tokens? "(a (b"))
  (test-assert (leaves-match-tokens? "a)"))
  (test-assert (leaves-match-tokens? "'"))
  (test-assert (leaves-match-tokens? "(. a)"))
  (test-assert (leaves-match-tokens? "(a]"))
  (test-assert (leaves-match-tokens? "(a #z b)")))

(test-end)

;;; The document

(test-begin "document")

(test-equal '("(a)" "\n\n" "(b)") (child-texts (parse "(a)\n\n(b)")))
(test-equal 2 (length (top-data "(a)\n\n(b)")))

;; Leading trivia are children of the document, in place.
(test-equal "#!/usr/bin/env scheme-script\n"
            (cst->text (car (node-children
                             (parse "#!/usr/bin/env scheme-script\n(a)")))))

;; An empty source parses to an empty, clean document.
(test-equal '() (node-children (parse "")))
(test-equal '() (top-data ""))
(test-equal 0 (diagnostic-count ""))

;; The end-of-file leaf is held, and contributes nothing to the text.
(test-assert (leaf? (document-eof (parse "(a)"))))
(test-equal "" (leaf-text (document-eof (parse "(a)"))))

(test-end)

;;; Cleanliness

(test-begin "clean-input")

(test-equal 0 (diagnostic-count "(a b)"))
(test-equal 0 (diagnostic-count "[a b]"))
(test-equal 0 (diagnostic-count "(a . b)"))
(test-equal 0 (diagnostic-count "#(1 2) #vu8(3) #u8(4)"))
(test-equal 0 (diagnostic-count "'x `y ,z ,@w"))
(test-equal 0 (diagnostic-count "#0=(a . #0#)"))
(test-equal 0 (diagnostic-count "#!r6rs ;; c\n(a #| b |# #;(c) d)\n"))

;; Both dialects' spellings are accepted; the reader is a permissive union.
(test-equal 0 (diagnostic-count "#vu8(1)"))
(test-equal 0 (diagnostic-count "#u8(1)"))
(test-equal 0 (diagnostic-count "#true"))

(test-end)

;;; Malformed input

(test-begin "malformed")

;; An unclosed delimiter, once per unclosed node.
(test-equal 2 (diagnostic-count "(a (b"))
(test-assert (not (compound-close (only-form "(a (b"))))
(test-assert (not (compound-close (cadr (datum-children (only-form "(a (b"))))))

;; An unexpected closing delimiter becomes an error node holding that token.
(test-equal 1 (diagnostic-count "a)"))
(test-equal '(leaf error) (map node-kind (top-data "a)")))
(test-equal ")" (cst->text (cadr (top-data "a)"))))

;; A mismatched shape closes the node, keeping the delimiter that closed it.
(test-equal 1 (diagnostic-count "(a]"))
(test-equal "(" (cst->text (compound-open (only-form "(a]"))))
(test-equal "]" (cst->text (compound-close (only-form "(a]"))))

;; A prefix marker with nothing to prefix.
(test-equal 1 (diagnostic-count "'"))
(test-equal 'prefix (node-kind (only-form "'")))
(test-equal "'" (cst->text (prefix-marker (only-form "'"))))
(test-equal #f (prefix-datum (only-form "'")))
(test-equal 1 (diagnostic-count "(')"))
(test-equal #f (prefix-datum (car (datum-children (only-form "(')")))))

;; Dots in invalid positions keep their leaf.
(test-equal 1 (diagnostic-count "(. a)"))
(test-equal '("." " " "a") (child-texts (only-form "(. a)")))
(test-equal 1 (diagnostic-count "(a . b c)"))
(test-equal '("a" " " "." " " "b" " " "c") (child-texts (only-form "(a . b c)")))
(test-equal 2 (diagnostic-count "(a . . b)"))

;; A dot is not a tail in a vector.
(test-equal 1 (diagnostic-count "#(a . b)"))

;; A lexical error is recovered from, not raised.
(test-equal 1 (diagnostic-count "(a #z b)"))
(test-assert (positive? (diagnostic-count "#!bogus (a)")))

;; No token is invented and none is dropped, on any of these paths.
(letrec ((token-count
          (lambda (source)
            (let-values (((tokens lex-diagnostics) (tokenize source "<test>")))
              (vector-length tokens))))
         (leaf-count
          (lambda (source) (length (cst-leaves (parse source))))))
  (for-each (lambda (source)
              (test-equal (token-count source) (leaf-count source)))
            '("(a (b" "a)" "'" "(. a)" "(a]" "(a #z b)" "(a . b c)")))

(test-end)

;;; Diagnostic positions

(test-begin "diagnostic-positions")

;; A diagnostic reports its token's start, 1-based line and 0-based column.
(test-equal 1 (diagnostic-line (car (diagnostics-of "a)"))))
(test-equal 1 (diagnostic-column (car (diagnostics-of "a)"))))
(test-equal 3 (diagnostic-line (car (diagnostics-of "x\ny\n)"))))
(test-equal 0 (diagnostic-column (car (diagnostics-of "x\ny\n)"))))

;; The position comes from the token, not from the condition's source
;; information. Inside a #; datum comment the reader's saved line and column
;; describe the innermost recursive entry, which here is the malformed lexeme
;; on line 3; the datum-comment token itself starts at line 2, column 2.
(let ((d (car (diagnostics-of "(a\n  #;(b\n     #z c)\n  d)"))))
  (test-equal 2 (diagnostic-line d))
  (test-equal 2 (diagnostic-column d)))

;; A diagnostic's position agrees with its own token, always.
(letrec ((positions-agree?
          (lambda (source)
            (for-all (lambda (d)
                       (and (= (diagnostic-line d)
                               (token-start-line (diagnostic-token d)))
                            (= (diagnostic-column d)
                               (token-start-column (diagnostic-token d)))))
                     (diagnostics-of source)))))
  (test-assert (positions-agree? "(a (b"))
  (test-assert (positions-agree? "(a]\n(. b)\n'"))
  (test-assert (positions-agree? "(a #z b)")))

(test-end)

;;; Round-trip

(test-begin "round-trip")

;; Every kind of trivia.
(test-equal "  ;; line\n#| nested\n   comment |# #;(datum) #!r6rs (a)"
            (round-trip "  ;; line\n#| nested\n   comment |# #;(datum) #!r6rs (a)"))
(test-equal "#!/usr/bin/env scheme-script\n(a)"
            (round-trip "#!/usr/bin/env scheme-script\n(a)"))
(test-equal "#! guile comment !#\n(a)" (round-trip "#! guile comment !#\n(a)"))

;; Bracket shape and abbreviations.
(test-equal "[a b]" (round-trip "[a b]"))
(test-equal "(let ([x 1]) x)" (round-trip "(let ([x 1]) x)"))
(test-equal "'x `y ,z ,@w" (round-trip "'x `y ,z ,@w"))
(test-equal "#'x #`y #,z #,@w" (round-trip "#'x #`y #,z #,@w"))

;; Numeric, character, boolean, string and identifier spelling.
(test-equal "#xff 1E10 255 10000000000.0"
            (round-trip "#xff 1E10 255 10000000000.0"))
(test-equal "\"\\x41;\" \"A\"" (round-trip "\"\\x41;\" \"A\""))
(test-equal "#t #true #f #false" (round-trip "#t #true #f #false"))
(test-equal "#\\nul #\\null #\\linefeed #\\newline #\\esc #\\escape"
            (round-trip "#\\nul #\\null #\\linefeed #\\newline #\\esc #\\escape"))
(test-equal "|foo bar| foo" (round-trip "|foo bar| foo"))

;; Compound shapes.
(test-equal "#(1 2) #vu8(3 4) #u8(5 6)" (round-trip "#(1 2) #vu8(3 4) #u8(5 6)"))
(test-equal "#0=(a . #0#)" (round-trip "#0=(a . #0#)"))
(test-equal "(a . ; why\n b)" (round-trip "(a . ; why\n b)"))
(test-equal "" (round-trip ""))
(test-equal "\n\n" (round-trip "\n\n"))

;; Malformed input round-trips too. The property least allowed to depend on
;; the input being good.
(test-equal "(a (b" (round-trip "(a (b"))
(test-equal "a)" (round-trip "a)"))
(test-equal "'" (round-trip "'"))
(test-equal "(. a)" (round-trip "(. a)"))
(test-equal "(a . b c)" (round-trip "(a . b c)"))
(test-equal "(a]" (round-trip "(a]"))
(test-equal "(a #z b)" (round-trip "(a #z b)"))
(test-equal "#!bogus (a)" (round-trip "#!bogus (a)"))
(test-equal "(#1#)" (round-trip "(#1#)"))

(test-end)

;;; Whole files

;; The expected value is read from disk, so the comparison is against
;; something the tree did not produce.
(test-begin "round-trip-files")

(letrec ((file-contents
          (lambda (path)
            (let ((p (open-input-file path)))
              (let lp ((acc '()))
                (let ((c (read-char p)))
                  (if (eof-object? c)
                      (begin (close-port p) (list->string (reverse acc)))
                      (lp (cons c acc)))))))))
  (for-each
   (lambda (path)
     (let ((source (file-contents path)))
       (let-values (((tokens lex-diagnostics) (tokenize source path)))
         (let-values (((document parse-diagnostics) (parse-tokens tokens)))
           (test-equal source (cst->text document))
           (test-equal '() lex-diagnostics)
           (test-equal '() parse-diagnostics)
           (test-equal (vector->list tokens) (cst-tokens document))))))
   '("src/pitch/reader.sls"
     "src/pitch/cst.sld"
     "src/pitch/parse.sld"
     "vendor/laesare/reader.sls"
     "vendor/laesare/writer.sls"
     "vendor/laesare/tests/test-reader.sps"
     "tests/runner.sls")))

(test-end)

(test-exit)
