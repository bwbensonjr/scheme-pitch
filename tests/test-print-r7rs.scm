;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the CST-to-document translation.
;;
;; Most of these assert on *placement and losslessness*, not on beauty: no
;; token changes, no comment moves, nothing crashes. The sections that do pin an
;; appearance say which shape they are pinning, so that a taste revision to the
;; style table identifies exactly which expectations it is allowed to change.
;;
;; The style table has a positive case per entry. An entry that no test
;; exercises is indistinguishable from a head with no entry at all -- both
;; degrade silently to the generic shape -- so an untested entry is one nobody
;; has seen work.
(import
  (scheme base)
  (pitch parse)
  (pitch print)
  (pitch cst)
  (pitch doc)
  (pitch cost)
  (pitch layout)
  (pitch style)
  (pitch config)
  (tests config)
  (tests runner))

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

;;; Helpers

(define core-style-table (config-style-table default-config 'common))
(define r6rs-style-table (config-style-table default-config 'r6rs))
(define r7rs-style-table (config-style-table default-config 'r7rs))

(define (table-for dialect)
  (config-style-table default-config (if (null? dialect) 'common (car dialect))))

(define (doc-of src . dialect)
  (let-values (((tree diagnostics) (parse-source src "test")))
    (cst->document tree (table-for dialect))))

;; The first datum of a source, for testing the seam directly.
(define (first-form src)
  (let-values (((tree diagnostics) (parse-source src "test")))
    (car (datum-children tree))))

(define (fmt src width . dialect)
  (let-values (((text result)
                (layout (apply doc-of src dialect) (default-cost-factory width))))
    text))

(define (fmt-with-table src width table)
  (let-values (((tree diagnostics) (parse-source src "test")))
    (let-values (((text result)
                  (layout (cst->document tree table) (default-cost-factory width))))
      text)))

;; Formatting is defined to end a file with exactly one newline. For the small
;; cases below that trailing newline is noise, so most tests compare without it.
(define (fmt* src width . dialect)
  (let* ((s (apply fmt src width dialect))
         (n (string-length s)))
    (if (and (> n 0) (char=? (string-ref s (- n 1)) #\x0a))
        (substring s 0 (- n 1))
        s)))

(define (contains? haystack needle)
  (let ((hn (string-length haystack)) (nn (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nn) hn) #f)
            ((string=? (substring haystack i (+ i nn)) needle) #t)
            (else (loop (+ i 1)))))))

(define (line-count s)
  (let loop ((i 0) (n 1))
    (cond ((= i (string-length s)) n)
          ((char=? (string-ref s i) #\x0a) (loop (+ i 1) (+ n 1)))
          (else (loop (+ i 1) n)))))

(define (raises? thunk)
  (guard (e (else #t))
    (thunk)
    #f))

;;; A CST node translates to a document

(test-begin "translation is total and pure")

;; The same document laid out twice gives the same answer.
(define shared (doc-of "(define (f x) (g x) (h x))\n"))
(test-equal (let-values (((t r) (layout shared (default-cost-factory 20)))) t)
            (let-values (((t r) (layout shared (default-cost-factory 20)))) t))

;; Every node kind translates without raising.
(test-assert (not (raises? (lambda () (doc-of "(a) #(b) #vu8(1) 'c #0=(d) #0#\n")))))
(test-assert (not (raises? (lambda () (doc-of "#!r6rs #!fold-case #| b |# #;(x) ; c\n")))))

;; Malformed trees still translate; the pipeline refuses to format them, but the
;; translation is total over the node kinds.
(test-assert (not (raises? (lambda () (doc-of "(a")))))
(test-assert (not (raises? (lambda () (doc-of "(a))")))))
(test-assert (not (raises? (lambda () (doc-of "'")))))
(test-equal "(a" (fmt* "(a" 80))
;; The stray closer is an error node, and error nodes are top-level items like
;; any other, so it lands on its own line rather than being discarded.
(test-equal "(a)\n)" (fmt* "(a))" 80))

(test-end)

;;; A token's text is emitted verbatim, once, in order

(test-begin "tokens survive verbatim")

;; The declared-normalizations list is empty, so none of these is respelled.
(test-equal "#xff" (fmt* "#xff\n" 80))
(test-equal "1E10" (fmt* "1E10\n" 80))
(test-equal "[a b]" (fmt* "[a b]\n" 80))
(test-equal "'x" (fmt* "'x\n" 80))
(test-equal "`(a ,b ,@c)" (fmt* "`(a ,b ,@c)\n" 80))
(test-equal "#'(a #`b #,c #,@d)" (fmt* "#'(a #`b #,c #,@d)\n" 80))
(test-equal "\"\\x41;\"" (fmt* "\"\\x41;\"\n" 80))
(test-equal "#\\nul" (fmt* "#\\nul\n" 80))
(test-equal "#true" (fmt* "#true\n" 80))
(test-equal "#vu8(1 2)" (fmt* "#vu8(1 2)\n" 80))
(test-equal "#u8(1 2)" (fmt* "#u8(1 2)\n" 80))
(test-equal "#(a b)" (fmt* "#(a b)\n" 80))
(test-equal "#0=(a . #0#)" (fmt* "#0=(a . #0#)\n" 80))

;; An abbreviation is never expanded.
(test-assert (not (contains? (fmt "'x\n" 80) "quote")))

;; The value is not what is printed: a symbol under fold-case keeps its
;; spelling, because the leaf is emitted from the token's text.
(test-equal "#!fold-case\nFoo" (fmt* "#!fold-case\nFoo\n" 80))

(test-end)

;;; A token spanning lines keeps its interior exactly

(test-begin "multi-line tokens")

;; No indentation is added to a continuation line: inside a string literal that
;; would change the value denoted, and inside a comment it would rewrite the
;; comment's contents.
(test-equal "(f \"a\nb\")" (fmt* "(f \"a\nb\")\n" 80))
(test-equal "(f (g \"a\nb\"))" (fmt* "(f (g \"a\nb\"))\n" 80))
(test-equal "(a #| one\n   two |# b)" (fmt* "(a #| one\n   two |# b)\n" 80))

;; A datum comment eliding a datum written across lines is one opaque token and
;; is reproduced as written, interior spacing included.
(test-equal "(a #;(b\n  c) d)" (fmt* "(a #;(b\n  c) d)\n" 80))

;; And such a token has no flat layout, so nothing folds it onto one line.
(test-assert (> (line-count (fmt "(f \"a\nb\")\n" 200)) 2))

(test-end)

;;; The default compound shape
;;
;; THIS SECTION PINS THE GENERIC SHAPE. A per-form style table is entitled to
;; change these expectations; nothing else in this file is.

(test-begin "the generic shape")

;; Flat when it fits.
(test-equal "(f a b)" (fmt* "(f a b)\n" 80))
(test-equal "()" (fmt* "()\n" 80))
(test-equal "#()" (fmt* "#()\n" 80))
(test-equal "(a)" (fmt* "(a)\n" 80))

;; Aligned when it does not: the head and the first argument share the opening
;; line and the rest begin at the first argument's column.
(test-equal "(f aaaa\n   bbbb)" (fmt* "(f aaaa bbbb)\n" 10))
(test-equal "(f (g 1 2)\n   (h 3 4)\n   (i 5 6))" (fmt* "(f (g 1 2) (h 3 4) (i 5 6))\n" 15))

;; Aligned is preferred to hanging whenever it does not overflow, because
;; hanging is always exactly one line taller and the objective ranks overflow
;; before height. No cost penalty arranges this; the shapes do.
(test-assert (not (contains? (fmt "(f aaaa bbbb)\n" 10) "(f\n")))

;; Hanging when it strictly reduces overflow: a head too long to leave room for
;; an aligned argument.
(test-equal "(averyveryverylongheadsymbol\n  arg)"
            (fmt* "(averyveryverylongheadsymbol arg)\n" 20))

;; Every element appears exactly once however it breaks.
(test-assert (contains? (fmt "(f (g 1 2) (h 3 4) (i 5 6))\n" 15) "(i 5 6)"))

;; Structurally identical forms with no entry lay out identically. `if` is
;; absent from the table deliberately -- what everyone writes for it is the
;; first argument on the opening line with the rest aligned under it, which is
;; precisely this shape, so an entry would make its output worse.
(test-equal "(if a\n    b\n    c)" (fmt* "(if a b c)\n" 8))
(test-equal "(xy a\n    b\n    c)" (fmt* "(xy a b c)\n" 8))
(test-equal "(and a\n     b\n     c)" (fmt* "(and a b c)\n" 8))
(test-equal "(or a\n    b\n    c)" (fmt* "(or a b c)\n" 8))

(test-end)

;;; The seam

(test-begin "a per-form rule is consulted at exactly one point")

;; A head with no entry, and one with an entry.
(test-equal 'generic (compound-shape (first-form "(if a b c)\n") core-style-table))
(test-equal 'generic (compound-shape (first-form "(xy a b c)\n") core-style-table))
(test-assert (styled? (compound-shape (first-form "(let ((x 1)) x)\n")
                                      core-style-table)))

;; A head that is not an identifier leaf keys nothing.
(test-equal 'generic (compound-shape (first-form "((f) a b)\n") core-style-table))
(test-equal 'generic (compound-shape (first-form "(\"s\" a)\n") core-style-table))
(test-equal 'generic (compound-shape (first-form "()\n") core-style-table))

;; A vector is generic and a bytevector fills, neither by consulting a table.
(test-equal 'generic (compound-shape (first-form "#(a b)\n") core-style-table))
(test-equal 'fill (compound-shape (first-form "#vu8(1 2)\n") core-style-table))

;; The lookup key is the token's *value*, so spellings the reader resolves to
;; the same symbol take the same shape. The emitted text keeps its spelling.
(test-equal "(when a\n  b)" (fmt* "(when a b)\n" 8))
(test-equal "(|when| a\n  b)" (fmt* "(|when| a b)\n" 10))
(test-equal "#!fold-case\n(WHEN a\n  b)" (fmt* "#!fold-case\n(WHEN a b)\n" 8))

;; The dialect selects the table and nothing else.
(test-assert (styled? (compound-shape (first-form "(library (a) b)\n")
                                      r6rs-style-table)))
(test-equal 'generic (compound-shape (first-form "(library (a) b)\n")
                                     r7rs-style-table))

(test-end)

(test-begin "configured styles add replace and remove per-form rules")

(define configured-table
  (config-style-table
    (make-test-config-with
      "(pitch-config 1
         (styles common
           ((project-let) (_ fc* . body))
           ((when) (_ . fill))
           ((cond) remove)))"
      20
      'common)
    'common))

(test-assert (styled? (compound-shape (first-form "(project-let ((x 1)) x)\n")
                                      configured-table)))
(test-equal 'generic
            (compound-shape (first-form "(cond (a b) (else c))\n")
                            configured-table))
(test-assert
  (not (string=? (fmt-with-table "(when a b c d)\n" 10 configured-table)
                 (fmt "(when a b c d)\n" 10))))

(test-end)

;;; Delimiters

(test-begin "delimiters")

;; Taken from their tokens, so no dialect knowledge is needed anywhere.
(test-assert (contains? (fmt "#vu8(1 2)\n" 80) "#vu8("))
(test-assert (contains? (fmt "#u8(1 2)\n" 80) "#u8("))
(test-assert (contains? (fmt "[a b]\n" 80) "]"))

;; The closer trails the last element rather than taking a line of its own.
(test-equal "(f aaaa\n   bbbb)" (fmt* "(f aaaa bbbb)\n" 10))

;; An absent closer emits nothing.
(test-equal "(a" (fmt* "(a" 80))

(test-end)

;;; Prefixes and the dot

(test-begin "prefixes and the dot")

;; A prefix never breaks from its datum, however narrow the page.
(test-assert (not (contains? (fmt "'(aaaa bbbb cccc)\n" 5) "'\n")))
(test-assert (not (contains? (fmt "#0=(aaaa bbbb)\n" 5) "#0=\n")))
(test-equal "'x" (fmt* "'  x\n" 80))

;; A marker with no datum is the marker alone.
(test-equal "'" (fmt* "'" 80))

;; Trivia between a marker and its datum are kept, and a line comment there is
;; the one thing that can put the two on different lines.
(test-assert (contains? (fmt "' ; why\n x\n" 80) "; why"))
(test-assert (contains? (fmt "' ; why\n x\n" 80) "x"))

;; The dot keeps a space on both sides -- `(a .b)` and `(a. b)` lex differently
;; -- and binds to the tail so it is never alone on a line.
(test-equal "(a . b)" (fmt* "(a . b)\n" 80))
(test-assert (not (contains? (fmt "(aaaa . bbbb)\n" 5) ".\n")))
(test-assert (not (contains? (fmt "(aaaa . bbbb)\n" 5) "\n.")))

(test-end)

;;; Comment placement

(test-begin "a line comment is followed by a break")

;; The comment does not swallow what follows it.
(test-equal "(a ; c\n  b)" (fmt* "(a ; c\n b)\n" 80))

;; A comment ending the source with no terminator still gets a break, which is
;; also what makes the file end with a newline.
(test-equal "; last\n" (fmt "; last" 80))

;; A form containing a line comment has no flat layout, at any width. This is
;; not a rule the printer enforces -- the document denotes no such layout,
;; because a hard break fails when flattened.
(test-assert (> (line-count (fmt "(a ; c\n b)\n" 10000)) 2))

(test-end)

(test-begin "comments stay where they were written")

;; Written after code on its line, it stays on that line.
(test-assert (contains? (fmt "(a ; note\n b)\n" 80) "(a ; note\n"))

;; Including when the form breaks around it.
(test-assert (contains? (fmt "(let ((x 1)) (f x) ; note\n (g x))\n" 80) "(f x) ; note\n"))

;; Written on its own line, it stays on its own line.
(test-assert (contains? (fmt "(a\n ; note\n b)\n" 80) "\n  ; note\n"))

;; A comment before the first element stays first.
(test-equal "(; note\n  a\n  b)" (fmt* "(; note\n a b)\n" 80))

;; Two adjacent line comments do not merge onto one line. There is no
;; whitespace token between them -- the first comment's text swallowed the line
;; ending -- so only the first one's forced break keeps them apart.
(test-equal "; one\n; two\n" (fmt "; one\n; two\n" 80))

;; A trailing comment is still attached when attaching it overflows the width.
(test-assert (contains? (fmt "(a ; a very long trailing note indeed\n b)\n" 20)
                        "(a ; a very long trailing note indeed\n"))

(test-end)

(test-begin "a comment before a closer puts the closer on a new line")

(test-equal "(a ; note\n)" (fmt* "(a ; note\n )\n" 80))

;; And the closer returns to the column its opening delimiter was laid out at.
(test-equal "(f aaaa\n   (b ; note\n   ))"
            (fmt* "(f aaaa (b ; note\n ))\n" 12))

(test-end)

(test-begin "inline-capable trivia")

;; A datum comment, a block comment and a directive impose no break.
(test-equal "(a #;(b c) d)" (fmt* "(a #;(b c) d)\n" 80))
(test-equal "(a #| note |# b)" (fmt* "(a #| note |# b)\n" 80))
(test-equal "(a #;(b    c) d)" (fmt* "(a #;(b    c) d)\n" 80))

;; A shebang leads the file and is followed by a break.
(test-equal "#!/usr/bin/env scheme-script\n(a)\n"
            (fmt "#!/usr/bin/env scheme-script\n(a)\n" 80))

(test-end)

;;; Preserved formatting

(test-begin "blank lines survive, capped")

;; One blank line inside a form is kept; two become one. The blank line is
;; empty -- the break that opens it carries no indentation, so it holds no
;; trailing whitespace. (The surviving element is at the hanging indent, since a
;; blank line after the head forces the break that the aligned shape's
;; head-to-first-argument space cannot represent.)
(test-equal "(a\n\n  b)" (fmt* "(a\n\nb)\n" 80))
(test-equal "(a\n\n  b)" (fmt* "(a\n\n\nb)\n" 80))
;; Where the head and first argument still share the opening line, the aligned
;; shape survives the blank line and the element after it keeps its column.
(test-equal "(f a\n\n   b)" (fmt* "(f a\n\nb)\n" 80))

;; Two between top-level forms are kept; three become two.
(test-equal "(x)\n\n\n(y)" (fmt* "(x)\n\n\n(y)\n" 80))
(test-equal "(x)\n\n\n(y)" (fmt* "(x)\n\n\n\n\n(y)\n" 80))

;; A single line ending is not a blank line.
(test-equal "(x)\n(y)" (fmt* "(x)\n(y)\n" 80))

;; A preserved blank line removes the flat layout: putting the form on one line
;; would delete the blank line just preserved.
(test-assert (> (line-count (fmt "(a\n\nb)\n" 10000)) 2))

(test-end)

(test-begin "a blank line after a comment survives, and is empty")

;; A line comment's token text carries the ending that terminated its own line,
;; so every ending in the whitespace that follows is a blank line. Counting them
;; as "endings less one" here is how this used to be dropped.
(test-equal "; one\n\n; two\n" (fmt "; one\n\n; two\n" 80))
(test-equal "; one\n\n(a)\n" (fmt "; one\n\n(a)\n" 80))
(test-equal "(x ; c\n\n  b)" (fmt* "(x ; c\n\nb)\n" 80))

;; Capped like any other run: two between top-level forms, one inside a form.
(test-equal "; one\n\n\n(a)\n" (fmt "; one\n\n\n(a)\n" 80))
(test-equal "; one\n\n\n(a)\n" (fmt "; one\n\n\n\n\n(a)\n" 80))
(test-equal "(x ; c\n\n  b)" (fmt* "(x ; c\n\n\n\nb)\n" 80))

;; No blank line where none was written. Two adjacent line comments have no
;; whitespace token between them at all, so this is the case the count must not
;; over-report.
(test-equal "; one\n; two\n" (fmt "; one\n; two\n" 80))
(test-equal "(x ; c\n  b)" (fmt* "(x ; c\nb)\n" 80))

;; The blank line is empty. The resolver indents after every break, so the
;; comment's own break -- the one that lands on the blank line -- is taken at
;; indentation zero; otherwise the line holds the enclosing indentation as
;; trailing whitespace and is not blank.
(test-assert (not (contains? (fmt "(x ; c\n\nb)\n" 80) " \n")))
(test-assert (not (contains? (fmt "(f (g (h ; c\n\nx)))\n" 80) " \n")))
(test-assert (not (contains? (fmt "; c\n\n(a)\n" 80) " \n")))

;; And a comment followed by exactly one blank line does not raise. `hard-breaks
;; 1` reduces to `hard-nl`, which is also the separator between top-level forms,
;; and the guard against a comment swallowing following code used to compare the
;; two documents rather than the branch that produced them.
(test-assert (not (raises? (lambda () (fmt "; one\n\n(a)\n" 80)))))
(test-assert (not (raises? (lambda () (fmt "(a ; c\n\nb)\n" 80)))))

(test-end)

(test-begin "everything else is re-derived")

;; Original indentation and runs of spaces are discarded.
(test-equal "(a b)" (fmt* "(a     b)\n" 80))
(test-equal "(f a b)" (fmt* "(f\n      a\n         b)\n" 80))

(test-end)

(test-begin "the file ends with exactly one newline")

(test-equal "(a)\n" (fmt "(a)" 80))
(test-equal "(a)\n" (fmt "(a)\n\n\n" 80))
(test-equal "(a)\n" (fmt "\n\n(a)\n" 80))
(test-equal "; c\n" (fmt "; c\n\n\n" 80))
(test-equal "" (fmt "" 80))
(test-equal "" (fmt "\n\n\n" 80))

(test-end)

;;; The styled shapes
;;
;; THIS SECTION PINS THE STYLE TABLE. One positive case per entry, at a width
;; that forces the form to break, because an entry that only ever renders flat
;; is an entry whose shape nothing has checked.

(test-begin "slots share the opening line and the tail goes beneath")

(test-equal "(when (p x)\n  (f x)\n  (g x))" (fmt* "(when (p x) (f x) (g x))\n" 20))
(test-equal "(unless (p x)\n  (f x))" (fmt* "(unless (p x) (f x))\n" 15))

;; The body indent is two columns from the opening delimiter, and it does not
;; vary with the length of the head.
(test-equal "(begin\n  (f)\n  (g))" (fmt* "(begin (f) (g))\n" 10))
(test-equal "(when a\n  (f))" (fmt* "(when a (f))\n" 8))
(test-equal "(unless a\n  (f))" (fmt* "(unless a (f))\n" 10))

;; Exactly two layouts: everything on one line, or the tail fully broken. There
;; is no rendering in which some tail elements share the opening line.
(test-equal "(when a b c)" (fmt* "(when a b c)\n" 80))
(test-equal "(when a\n  b\n  c)" (fmt* "(when a b c)\n" 10))

(test-end)

(test-begin "every core entry has a shape")

(test-equal "(define (f a b)\n  (+ a b))" (fmt* "(define (f a b) (+ a b))\n" 20))
(test-equal "(define x\n  (f a))" (fmt* "(define x (f a))\n" 12))
(test-equal "(define-syntax m\n  (f))" (fmt* "(define-syntax m (f))\n" 18))
(test-equal "(lambda (a b)\n  (f a)\n  (g b))" (fmt* "(lambda (a b) (f a) (g b))\n" 20))
(test-equal "(case-lambda\n  ((a) 1)\n  ((a b) 2))"
            (fmt* "(case-lambda ((a) 1) ((a b) 2))\n" 20))
(test-equal "(let ((x 1) (y 2))\n  (f x y))" (fmt* "(let ((x 1) (y 2)) (f x y))\n" 20))
(test-equal "(let loop ((x 1))\n  (loop x))" (fmt* "(let loop ((x 1)) (loop x))\n" 20))
(test-equal "(let* ((x 1) (y 2))\n  (f x y))"
            (fmt* "(let* ((x 1) (y 2)) (f x y))\n" 20))
(test-equal "(letrec ((x 1))\n  (f x))" (fmt* "(letrec ((x 1)) (f x))\n" 18))
(test-equal "(let-values (((a b) (f)))\n  (g a))"
            (fmt* "(let-values (((a b) (f))) (g a))\n" 28))
(test-equal "(cond\n  ((p x) 1)\n  (else 2))" (fmt* "(cond ((p x) 1) (else 2))\n" 20))
(test-equal "(case x\n  ((1 2) 'a)\n  (else 'b))" (fmt* "(case x ((1 2) 'a) (else 'b))\n" 20))
(test-equal "(do ((i 0 (+ i 1))) ((= i n) r)\n  (f i))"
            (fmt* "(do ((i 0 (+ i 1))) ((= i n) r) (f i))\n" 32))
(test-equal "(guard (e (#t (k e)))\n  (f))" (fmt* "(guard (e (#t (k e))) (f))\n" 24))
(test-equal "(set! x\n  (f a))" (fmt* "(set! x (f a))\n" 12))
(test-equal "(syntax-rules (else)\n  ((_ x) x))"
            (fmt* "(syntax-rules (else) ((_ x) x))\n" 24))
(test-equal "(import\n  (rnrs)\n  (pitch cst))" (fmt* "(import (rnrs) (pitch cst))\n" 20))
(test-equal "(export\n  aa bb cc dd)" (fmt* "(export aa bb cc dd)\n" 14))

(test-end)

(test-begin "every dialect entry has a shape")

(test-equal "(define-values (a b)\n  (f))" (fmt* "(define-values (a b) (f))\n" 22 'r7rs))
(test-equal "(define-record-type <p> (mk x) p?\n  (x px))"
            (fmt* "(define-record-type <p> (mk x) p? (x px))\n" 40 'r7rs))
(test-equal "(parameterize ((p 1))\n  (f))" (fmt* "(parameterize ((p 1)) (f))\n" 24 'r7rs))
(test-equal "(delay\n  (f x))" (fmt* "(delay (f x))\n" 10 'r7rs))
;; A flush body: define-library uses body0, so its elements sit at the column of
;; its opening delimiter rather than two in. See the flush-tail group below.
(test-equal "(define-library (a b)\n(export c))"
            (fmt* "(define-library (a b) (export c))\n" 24 'r7rs))
(test-equal "(cond-expand\n  (chez 1)\n  (else 2))"
            (fmt* "(cond-expand (chez 1) (else 2))\n" 20 'r7rs))

(test-equal "(define-record-type p\n  (fields x)\n  (protocol q))"
            (fmt* "(define-record-type p (fields x) (protocol q))\n" 30 'r6rs))
;; Likewise library, the R6RS spelling of the same construct.
(test-equal "(library (a b)\n(export c)\n(import d))"
            (fmt* "(library (a b) (export c) (import d))\n" 24 'r6rs))
(test-equal "(syntax-case x (else)\n  ((_ y) y))"
            (fmt* "(syntax-case x (else) ((_ y) y))\n" 24 'r6rs))
(test-equal "(with-syntax ((a b))\n  (f))" (fmt* "(with-syntax ((a b)) (f))\n" 22 'r6rs))
(test-equal "(assert\n  (p x))" (fmt* "(assert (p x))\n" 10 'r6rs))

;; The collision, and the reason the table is dialect-parameterized at all.
(test-assert (not (equal? (fmt "(define-record-type <p> (mk x) p? (x px))\n" 40 'r6rs)
                          (fmt "(define-record-type <p> (mk x) p? (x px))\n" 40 'r7rs))))

;; It has no entry in the shared core, so the default dialect degrades it.
(test-equal 'generic
            (compound-shape (first-form "(define-record-type <p> (mk x))\n")
                            core-style-table))

(test-end)

(test-begin "a clause is laid out by the generic shape")

;; A clause introduces no rendering of its own: it is the generic shape with its
;; first element as the head, so the second element shares that element's line
;; and the rest align under the second.
(test-equal "(cond\n  ((p x) (f x)\n         (g x)))"
            (fmt* "(cond ((p x) (f x) (g x)))\n" 16))
;; And it drops to hanging when aligning would overflow, as any form does.
(test-equal "(cond\n  ((p x)\n    (f x)\n    (g x)))"
            (fmt* "(cond ((p x) (f x) (g x)))\n" 12))

;; A clause element that is not a list is emitted as itself.
(test-equal "(cond\n  a\n  (b c))" (fmt* "(cond a (b c))\n" 10))

(test-end)

(test-begin "formals, literals and heads fill")

;; Packed, not one name per line, and wrapped under the first element.
(test-equal "(lambda (aaa bbb\n         ccc ddd)\n  (f))"
            (fmt* "(lambda (aaa bbb ccc ddd) (f))\n" 18))
(test-equal "(define (fn aaa\n         bbb)\n  (f))"
            (fmt* "(define (fn aaa bbb) (f))\n" 16))

;; A non-list in a formals position is unaffected.
(test-equal "(lambda args\n  (f args))" (fmt* "(lambda args (f args))\n" 14))

;; A bytevector fills without reference to any table: its elements are octets.
(test-equal "#vu8(1 2 3 4 5 6\n     7 8 9 10)"
            (fmt* "#vu8(1 2 3 4 5 6 7 8 9 10)\n" 16))
;; A vector does not: its elements can be anything, so it takes the generic
;; shape and no two of them past the first share a line.
(test-equal "#(1 2\n    3\n    4\n    5\n    6)" (fmt* "#(1 2 3 4 5 6)\n" 8))

(test-end)

(test-begin "a fill tail packs")

(test-equal "(export a b)" (fmt* "(export a b)\n" 80))
(test-equal "(export\n  aaa bbb\n  ccc)" (fmt* "(export aaa bbb ccc)\n" 10))
;; At least one line holds more than one name, which is what distinguishes a
;; fill from a body.
(test-assert (contains? (fmt "(export aaa bbb ccc)\n" 10) "aaa bbb"))
;; And `import`, which is a body, does not pack.
(test-assert (not (contains? (fmt "(import (a) (b) (c))\n" 12) "(a) (b)")))

(test-end)

;;; Code and data

(test-begin "a data position is never looked up")

;; The sharp case: a literals list and a binding whose head spells a form that
;; *does* have an entry. Laying either out as that form would be a defect, and
;; the terminal in that position is what says it is not one.
;;
;; `cond` is the discriminator because its style puts the head alone on its own
;; line, which no generic or filled rendering of the same list does. The third
;; case is the control: the same list in an expression position, styled.
(test-equal "(syntax-rules (cond aa\n               bb)\n  ((_ x) x))"
            (fmt* "(syntax-rules (cond aa bb) ((_ x) x))\n" 24))
(test-equal "(let ((cond aa\n            bb))\n  x)"
            (fmt* "(let ((cond aa bb)) x)\n" 16))
(test-equal "(f (cond\n     aa\n     bb))" (fmt* "(f (cond aa bb))\n" 12))

;; Stated as the property rather than as three renderings: the head is alone on
;; its line only where the list sits in an expression position.
(test-assert (not (contains? (fmt "(syntax-rules (cond aa bb) ((_ x) x))\n" 24)
                             "(cond\n")))
(test-assert (not (contains? (fmt "(let ((cond aa bb)) x)\n" 16) "(cond\n")))
(test-assert (contains? (fmt "(f (cond aa bb))\n" 12) "(cond\n"))

;; A body element *is* looked up, which is the other half of the distinction.
(test-equal "(begin\n  (when a\n    b))" (fmt* "(begin (when a b))\n" 12))

;; And a clause's body elements are expressions too.
(test-assert (contains? (fmt "(cond (p (when a bb cc dd)))\n" 16) "(when a\n"))

(test-end)

;;; Degradation

(test-begin "a form that does not match its style degrades")

;; Too few elements for the style's slots. A formatter meets these constantly,
;; in macro-generating code and in half-saved buffers.
(test-equal "(let)" (fmt* "(let)\n" 80))
(test-equal "(when)" (fmt* "(when)\n" 80))
(test-equal "(cond)" (fmt* "(cond)\n" 80))
(test-assert (not (raises? (lambda () (fmt "(let () )\n" 80)))))

;; A slot requiring a list that gets something else.
(test-equal "(let x\n     y)" (fmt* "(let x y)\n" 8))
;; But `f`, `l` and `h` do not require one, so these still match.
(test-equal "(lambda x\n  y)" (fmt* "(lambda x y)\n" 6))
(test-equal "(define x\n  y)" (fmt* "(define x y)\n" 6))

;; An improper list: a dot has no place in any slot.
(test-equal "(begin a . b)" (fmt* "(begin a . b)\n" 80))
(test-equal "(begin aaa\n       . bbb)" (fmt* "(begin aaa . bbb)\n" 14))

;; A comment forcing a break inside the slot region withdraws the style. The
;; comment stays on its own line; moving it is what layer 1 refuses.
(test-equal "(when\n  ; note\n  (p x)\n  (f))" (fmt* "(when\n ; note\n (p x) (f))\n" 40))
(test-equal "(let\n  ; note\n  ((x 1))\n  x)" (fmt* "(let\n ; note\n ((x 1)) x)\n" 40))

;; A blank line inside the slot region does too, for the same reason.
(test-equal "(when\n\n  (p x)\n  (f))" (fmt* "(when\n\n (p x) (f))\n" 40))

;; A head with no entry, and a head that is not an identifier.
(test-equal "((f) a\n     b)" (fmt* "((f) a b)\n" 8))

(test-end)

;;; Comments under a style

(test-begin "a style moves no comment")

;; A trailing comment on a slot stays on that slot's line: the style still
;; applies, because the gap it interrupts is the one before the tail, which
;; breaks anyway.
(test-equal "(when (p x) ; note\n  (f))" (fmt* "(when (p x) ; note\n (f))\n" 40))

;; A trailing comment on the head of a form with no slots likewise.
(test-equal "(begin ; note\n  (f)\n  (g))" (fmt* "(begin ; note\n (f) (g))\n" 40))

;; A comment among the tail elements keeps its place.
(test-assert (contains? (fmt "(when a (f) ; note\n (g))\n" 40) "(f) ; note\n"))
(test-assert (contains? (fmt "(when a\n ; note\n (f))\n" 40) "\n  ; note\n"))

;; An inline-capable comment does not force a break, so the style survives one
;; sitting inside the slot region.
(test-equal "(when #| k |# a\n  b)" (fmt* "(when #| k |# a b)\n" 12))

;; A form containing a line comment still has no flat layout at any width.
(test-assert (> (line-count (fmt "(when a ; note\n b)\n" 10000)) 2))

(test-end)

;;; The zero-indent body

(test-begin "a library body sits flush with its opening delimiter")

(define lib "(library (a b) (export c) (import (rnrs)) (define (c x) (+ x 1)))\n")

;; R6RS. Every body form begins at the column the opening delimiter is at.
(test-equal (string-append "(library (a b)\n"
                           "(export c)\n"
                           "(import (rnrs))\n"
                           "(define (c x) (+ x 1)))")
            (fmt* lib 30 'r6rs))

;; R7RS, the same construct under the other spelling.
(test-equal (string-append "(define-library (a b)\n"
                           "(export c)\n"
                           "(import (scheme base))\n"
                           "(begin (define (c x) x)))")
            (fmt* (string-append "(define-library (a b) (export c)"
                                 " (import (scheme base))"
                                 " (begin (define (c x) x)))\n")
                  30 'r7rs))

;; The change is confined to the new terminal: an ordinary styled form is still
;; indented two from its delimiter.
(test-equal "(when (p x)\n  (f)\n  (g))" (fmt* "(when (p x) (f) (g))\n" 12 'r6rs))

;; Zero *from the delimiter*, not column 0 of the file. These coincide for a
;; top-level library and this is the case that tells them apart.
(test-equal (string-append "(begin\n"
                           "  (library (a b)\n"
                           "  (export c)\n"
                           "  (import (rnrs))\n"
                           "  (define (c x) (+ x 1))))")
            (fmt* (string-append "(begin " lib ")\n") 30 'r6rs))

;; Forms nested inside a library body indent their own bodies normally, so the
;; flush tail does not propagate to what it contains: the `define` body sits at
;; 2 and the `when` body inside it at 4, both measured from their own delimiters.
(test-equal (string-append "(library (a b)\n"
                           "(import (rnrs))\n"
                           "(define (c x)\n"
                           "  (when x\n"
                           "    (foo)\n"
                           "    (bar))))")
            (fmt* (string-append "(library (a b) (import (rnrs))"
                                 " (define (c x) (when x (foo) (bar))))\n")
                  16 'r6rs))

;; Under a dialect with no entry for the head, the generic shape applies and the
;; body is not flush -- the flush tail comes from the table, not from the name.
(test-assert (not (contains? (fmt lib 30) "\n(export c)")))

(test-end)

;;; Lists of peers
;;
;; A list whose style distinguishes no first element -- a binding list -- is not
;; a list with a head, and must not be laid out as one. The generic aligned
;; rendering welds element 2 to element 1 with a space no break may be taken at,
;; then aligns the rest at element 2's column; for `(f a b c)` that is right, and
;; for `([a 1] [b 2] [c 3])` it produces a staircase.
;;
;; The cases at the end of this group are the ones that MUST NOT move. The bug
;; this group exists for shipped with the whole suite green, so pinning the
;; neighbouring paths is not padding: it is what stops a later edit collapsing
;; the three dispatch cases back into two.

(test-begin "a list of peers is aligned at its first element")

;; One binding per line, and every binding -- the first included -- at the column
;; after the binding list's opening delimiter.
(test-equal (string-append "(let ([a 1]\n"
                           "      [b 2]\n"
                           "      [c 3])\n"
                           "  (body))")
            (fmt* "(let ([a 1] [b 2] [c 3]) (body))\n" 20))

;; The shared table entry covers seven forms; cover more than its first member.
(test-equal (string-append "(let* ([a 1]\n"
                           "       [b 2]\n"
                           "       [c 3])\n"
                           "  (body))")
            (fmt* "(let* ([a 1] [b 2] [c 3]) (body))\n" 20))

(test-equal (string-append "(letrec ([a 1]\n"
                           "         [b 2]\n"
                           "         [c 3])\n"
                           "  (body))")
            (fmt* "(letrec ([a 1] [b 2] [c 3]) (body))\n" 20))

(test-equal (string-append "(let-values ([a 1]\n"
                           "             [b 2]\n"
                           "             [c 3])\n"
                           "  (body))")
            (fmt* "(let-values ([a 1] [b 2] [c 3]) (body))\n" 22))

;; do's binding list is fc* in a slot too, so its (var init step) triples are in
;; scope. One per line is what do is conventionally written as; this records that
;; as a decision rather than leaving it to fall out.
;;
;; The test clause trails the binding list's closing delimiter rather than
;; starting a line, and that is do's style rather than anything to do with peers:
;; `(_ fc* ec . body)` has two slots, and a style joins its slots to the head by
;; spaces at which no break may be taken. Only the body lies beneath. The width
;; here is chosen to leave room for that -- narrower, the slots cannot fit at all
;; and the styled shape breaks inside them, which is a different behavior and not
;; this requirement's business.
(test-equal (string-append "(do ([i 0 (+ i 1)]\n"
                           "     [j 1 (* j 2)]) ((= i 3) j)\n"
                           "  (body))")
            (fmt* "(do ([i 0 (+ i 1)] [j 1 (* j 2)]) ((= i 3) j) (body))\n" 40))

;; The two dialect-specific entries in scope.
(test-equal (string-append "(parameterize ([a 1]\n"
                           "               [b 2])\n"
                           "  (body))")
            (fmt* "(parameterize ([a 1] [b 2]) (body))\n" 22 'r7rs))

(test-equal (string-append "(with-syntax ([a 1]\n"
                           "              [b 2])\n"
                           "  (body))")
            (fmt* "(with-syntax ([a 1] [b 2]) (body))\n" 22 'r6rs))

;; Flat when it fits: a peer list denotes two renderings, not one.
(test-equal "(let ([a 1] [b 2]) (body))" (fmt* "(let ([a 1] [b 2]) (body))\n" 40))

;; An empty binding list has no alternatives to choose between.
(test-equal "(let ()\n  (body))" (fmt* "(let () (body))\n" 12))

;; No line ever holds two bindings once the list has broken.
(test-assert
  (let ((out (fmt "(let ([alpha 1] [beta 2] [gamma 3] [delta 4]) (body))\n" 24)))
    (not (or (contains? out "[alpha 1] [beta 2]")
             (contains? out "[beta 2] [gamma 3]")
             (contains? out "[gamma 3] [delta 4]")))))

;;; The paths that must not move

;; A clause's first element IS distinguished -- it is the test -- so a clause
;; keeps the generic shape with that element as head.
(test-assert (contains? (fmt "(cond ((p x) (f x) (g x)))\n" 30) "((p x) (f x)"))

;; guard's slot is (i . ec*): a nested shape WITH a slot, so it is a clause and
;; not a peer list.
(test-assert (contains? (fmt "(guard (e (#t (f e) (g e))) (body))\n" 30) "(e (#t"))

;; A starred terminal in TAIL position was always correct: one clause per line at
;; the body indent, not aligned at a first element.
(test-equal (string-append "(cond\n"
                           "  [(a x) 1]\n"
                           "  [(b x) 2]\n"
                           "  [else 3])")
            (fmt* "(cond [(a x) 1] [(b x) 2] [else 3])\n" 20))

(test-equal (string-append "(case-lambda\n"
                           "  [(a) 1]\n"
                           "  [(a b) 2])")
            (fmt* "(case-lambda [(a) 1] [(a b) 2])\n" 20))

;; A formals list is a peer list whose tail FILLS, so it packs rather than
;; taking a line per name. That branch is untouched.
(test-assert
  (let ((out (fmt "(lambda (alpha beta gamma delta epsilon zeta) (body))\n" 30)))
    (and (> (line-count out) 2) (contains? out "alpha beta"))))

;; And a form with a real head still pairs the head with its first argument.
(test-equal (string-append "(some-function aaaa\n"
                           "               bbbb\n"
                           "               cccc)")
            (fmt* "(some-function aaaa bbbb cccc)\n" 20))

(test-end)

(test-exit)
