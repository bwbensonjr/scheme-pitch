#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the CST-to-document translation.
;;
;; These assert on *placement and losslessness*, not on beauty. One generic
;; shape ships, so `cond` and `let` come out looking wrong, and that is expected
;; -- it is the graceful-degradation behavior docs/DESIGN.md §5 requires for a
;; form no style table matches, and the table is a later change. What must be
;; right here is that no token changes, no comment moves, and nothing crashes.
;;
;; Tests that pin the generic shape itself say so, so that the table's arrival
;; identifies exactly which expectations it is allowed to change.
#!r6rs

(import
  (except (rnrs (6)) newline)
  (pitch parse)
  (pitch print)
  (pitch cst)
  (pitch doc)
  (pitch cost)
  (pitch layout)
  (tests runner))

;;; Helpers

(define (doc-of src)
  (let-values (((tree diagnostics) (parse-source src "test")))
    (cst->document tree)))

(define (fmt src width)
  (let-values (((text result) (layout (doc-of src) (default-cost-factory width))))
    text))

;; Formatting is defined to end a file with exactly one newline. For the small
;; cases below that trailing newline is noise, so most tests compare without it.
(define (fmt* src width)
  (let* ((s (fmt src width))
         (n (string-length s)))
    (if (and (> n 0) (char=? (string-ref s (- n 1)) #\linefeed))
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
          ((char=? (string-ref s i) #\linefeed) (loop (+ i 1) (+ n 1)))
          (else (loop (+ i 1) n)))))

(define (raises? thunk)
  (guard (e (#t #t))
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

;; Structurally identical forms lay out identically: no head is special. Two
;; heads of equal length, one of which a style table will certainly treat
;; differently one day, break at exactly the same places today.
(test-equal "(if a\n    b\n    c)" (fmt* "(if a b c)\n" 8))
(test-equal "(xy a\n    b\n    c)" (fmt* "(xy a b c)\n" 8))
(test-equal 'generic (compound-shape (doc-of "(let ((x 1)) x)\n")))

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

(test-exit)
