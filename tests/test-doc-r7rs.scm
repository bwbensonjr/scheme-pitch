;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the document algebra.
;;
;; The smart constructors are tested by *rendering* the simplified and the
;; unsimplified form and requiring identical text and cost, rather than by
;; inspecting the tree. A simplification is only allowed to preserve meaning, so
;; meaning is what the test should check; asserting on the resulting shape would
;; pin an implementation detail and would still pass if the simplification
;; changed what the document denotes.
;;
;; The line-ending refusal and the `flatten` fix are asserted directly here.
;; Neither is covered by the differential oracle: the reference does not check
;; text for line endings, and it disagrees with pitch on `flatten`. See the
;; DIVERGENCE note in src/pitch/doc.sld.
(import
  (scheme base)
  (pitch doc)
  (pitch cost)
  (pitch layout)
  (tests runner))

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

;;; Helpers

(define (fmt d width)
  (let-values (((rendered result) (layout d (default-cost-factory width))))
    rendered))

(define (cost-of d width)
  (let-values (((rendered result) (layout d (default-cost-factory width))))
    (layout-result-cost result)))

;; Two documents denote the same thing if they render alike and cost alike.
(define (same? a b width)
  (and (string=? (fmt a width) (fmt b width))
       (equal? (cost-of a width) (cost-of b width))))

(define (no-layout? d)
  (guard (e ((layout-failure? e) #t))
    (fmt d 80)
    #f))

(define (raises? thunk)
  (guard (e (else #t))
    (thunk)
    #f))

;;; A document is an immutable value

(test-begin "documents are values")

(define shared (group (u-append (text "aa") nl (text "bb"))))

;; Resolving twice gives the same answer.
(test-equal (fmt shared 80) (fmt shared 80))
(test-equal (cost-of shared 80) (cost-of shared 80))

;; The same document value used in several positions behaves as a copy would.
(test-equal (fmt (v-append shared shared) 80)
            (fmt (v-append (group (u-append (text "aa") nl (text "bb")))
                           (group (u-append (text "aa") nl (text "bb"))))
                 80))

(test-end)

;;; text refuses a line ending

(test-begin "text refuses a line ending")

;; All seven endings the reader's grammar counts. The two-character forms begin
;; with CR, so the five characters below cover all seven.
(test-assert (raises? (lambda () (text "a\x000A;b"))))     ; line feed
(test-assert (raises? (lambda () (text "a\x000D;b"))))     ; carriage return
(test-assert (raises? (lambda () (text "a\x000D;\x000A;b")))) ; CR LF
(test-assert (raises? (lambda () (text "a\x000D;\x0085;b")))) ; CR NEL
(test-assert (raises? (lambda () (text "a\x0085;b"))))     ; next line
(test-assert (raises? (lambda () (text "a\x2028;b"))))     ; line separator
(test-assert (raises? (lambda () (text "a\x2029;b"))))     ; paragraph separator

;; A line ending anywhere, not only in the middle.
(test-assert (raises? (lambda () (text "\x000A;"))))
(test-assert (raises? (lambda () (text "abc\x000A;"))))
(test-assert (raises? (lambda () (text "\x000A;abc"))))

;; The case this exists for: a line comment's token text includes the line
;; ending that terminated it, so emitting it as a text must be refused.
(test-assert (raises? (lambda () (text "; a comment\x000A;"))))

;; The same comment without its terminator is ordinary text.
(test-equal "; a comment" (fmt (text "; a comment") 80))

;; Nothing else is refused, including a semicolon, quotes and a lone CR-less
;; string of punctuation.
(test-equal "#\\x;" (fmt (text "#\\x;") 80))
(test-equal "\"s\"" (fmt (text "\"s\"") 80))
(test-equal "" (fmt (text "") 80))

(test-end)

;;; verbatim is the way to emit a string that has one

(test-begin "verbatim")

;; With no ending it is exactly text.
(test-equal "abc" (fmt (verbatim "abc") 80))
(test-equal "" (fmt (verbatim "") 80))
(test-assert (same? (verbatim "abc") (text "abc") 80))

;; With one it renders on two lines.
(test-equal "ab\ncd" (fmt (verbatim "ab\x000A;cd") 80))

;; All seven endings split, and the two-character forms split once rather than
;; twice -- three pieces would show up here as two breaks.
(test-equal "a\nb" (fmt (verbatim "a\x000A;b") 80))
(test-equal "a\nb" (fmt (verbatim "a\x000D;b") 80))
(test-equal "a\nb" (fmt (verbatim "a\x000D;\x000A;b") 80))
(test-equal "a\nb" (fmt (verbatim "a\x000D;\x0085;b") 80))
(test-equal "a\nb" (fmt (verbatim "a\x0085;b") 80))
(test-equal "a\nb" (fmt (verbatim "a\x2028;b") 80))
(test-equal "a\nb" (fmt (verbatim "a\x2029;b") 80))

;; An ending at either edge produces an empty piece rather than being dropped.
(test-equal "\n" (fmt (verbatim "\x000A;") 80))
(test-equal "abc\n" (fmt (verbatim "abc\x000A;") 80))
(test-equal "\nabc" (fmt (verbatim "\x000A;abc") 80))

;; No indentation is added to a continuation line. This is the whole point:
;; indenting inside a string literal would change the value it denotes, and
;; inside a comment it would rewrite the comment's contents.
(test-equal "x\n    ab\n  cd"
            (fmt (nest 4 (u-append (text "x") hard-nl (verbatim "ab\x000A;  cd"))) 80))
(test-equal "xyab\ncd"
            (fmt (u-append (text "xy") (align (verbatim "ab\x000A;cd"))) 80))
(test-equal "x\n    ab\ncd"
            (fmt (nest 4 (u-append (text "x") hard-nl (verbatim "ab\x000A;cd"))) 80))

;; The characters between the endings are untouched -- no collapsing, no
;; trimming, at either edge of a piece.
(test-equal "a  b\n   c  " (fmt (verbatim "a  b\x000A;   c  ") 80))

;; Its breaks are hard, so there is no flat alternative to choose. A group over
;; it is the group's own argument.
(test-equal "ab\ncd" (fmt (group (verbatim "ab\x000A;cd")) 80))
(test-assert (no-layout? (flatten (verbatim "ab\x000A;cd"))))

;; And a group over a document containing one cannot go flat either, which is
;; what stops a multi-line token being folded onto one line.
(test-equal "(a\nb)"
            (fmt (group (u-append (text "(") (verbatim "a\x000A;b") (text ")"))) 80))

(test-end)

;;; The smart constructors preserve meaning

(test-begin "smart constructors preserve meaning")

(define broken (u-append (text "a") hard-nl (text "b")))

;; An empty text is dropped from either side of a concatenation.
(test-assert (same? (concat empty-doc broken) broken 80))
(test-assert (same? (concat broken empty-doc) broken 80))

;; Adjacent texts merge, and the merged form is the text it spells.
(test-assert (same? (concat (text "ab") (text "cd")) (text "abcd") 80))
(test-equal "abcd" (fmt (concat (text "ab") (text "cd")) 80))
;; Merging repeatedly keeps the pieces in order.
(test-equal "abcdef" (fmt (u-append (text "ab") (text "cd") (text "ef")) 80))
(test-equal "abcdef" (fmt (concat (concat (text "ab") (text "cd")) (text "ef")) 80))
(test-equal "abcdef" (fmt (concat (text "ab") (concat (text "cd") (text "ef"))) 80))

;; Nested nests combine.
(test-assert (same? (nest 2 (nest 3 broken)) (nest 5 broken) 80))
(test-equal "a\n     b" (fmt (nest 2 (nest 3 broken)) 80))

;; Indentation is unobservable on a text.
(test-assert (same? (nest 4 (text "a")) (text "a") 80))
(test-assert (same? (align (text "a")) (text "a") 80))
(test-assert (same? (reset (text "a")) (text "a") 80))

;; And on a document whose indentation an inner align or reset already fixes.
(test-assert (same? (nest 4 (align broken)) (align broken) 80))
(test-assert (same? (nest 4 (reset broken)) (reset broken) 80))
(test-assert (same? (align (align broken)) (align broken) 80))

;; Choice with itself is itself.
(test-assert (same? (alternatives broken broken) broken 80))

;; full is idempotent.
(test-assert (same? (full (full (text "a"))) (full (text "a")) 80))

(test-end)

;;; fail is the unit of choice and the zero of concatenation

(test-begin "fail")

(test-assert (no-layout? fail))
(test-assert (no-layout? (concat fail (text "a"))))
(test-assert (no-layout? (concat (text "a") fail)))
(test-assert (no-layout? (alternatives fail fail)))
(test-assert (no-layout? (nest 2 fail)))
(test-assert (no-layout? (align fail)))
(test-assert (no-layout? (cost '(0 1) fail)))
(test-assert (no-layout? (full fail)))

;; Choice discards a failing alternative rather than failing.
(test-equal "a" (fmt (alternatives fail (text "a")) 80))
(test-equal "a" (fmt (alternatives (text "a") fail) 80))
(test-equal "a" (fmt (alt fail fail (text "a")) 80))

;; alt of nothing has no layout.
(test-assert (no-layout? (alt)))

(test-end)

;;; full constrains what follows it

(test-begin "full")

;; Nothing may follow a document required to end its line.
(test-assert (no-layout? (concat (full (text "a")) (text "b"))))

;; An empty text is not "something", so it is permitted.
(test-assert (same? (concat (full (text "a")) (text "")) (full (text "a")) 80))

;; A line break may follow.
(test-equal "a\nb" (fmt (u-append (full (text "a")) hard-nl (text "b")) 80))

;; A full document at top level is fine: the top level tries both fullness
;; constraints on the outer boundary.
(test-equal "a" (fmt (full (text "a")) 80))

(test-end)

;;; The derived combinators

(test-begin "derived combinators")

;; flatten replaces a soft newline with its string.
(test-equal "a b" (fmt (flatten (u-append (text "a") nl (text "b"))) 80))
(test-equal "ab" (fmt (flatten (u-append (text "a") break (text "b"))) 80))
(test-equal "a--b" (fmt (flatten (u-append (text "a") (newline "--") (text "b"))) 80))

;; flatten fails on a hard newline, which has no flat spelling.
(test-assert (no-layout? (flatten hard-nl)))
(test-assert (no-layout? (flatten (u-append (text "a") hard-nl (text "b")))))

;; flatten discards indentation, since none of it is observable afterwards.
(test-assert (same? (flatten (nest 4 (u-append (text "a") nl (text "b"))))
                    (flatten (u-append (text "a") nl (text "b")))
                    80))
(test-assert (same? (flatten (align (u-append (text "a") nl (text "b"))))
                    (flatten (u-append (text "a") nl (text "b")))
                    80))

;; THE DIVERGENCE. A newline that is the direct child of align, nest or reset
;; must flatten like any other. sorawee/pretty-expressive returns it
;; unflattened, so (flatten (align nl)) is a line break there and a space here,
;; and (flatten (align hard-nl)) is a line break there and a failure here. That
;; makes the reference's (group (align d)) able to emit a break from its "flat"
;; alternative, which for a formatter that promises to change only whitespace is
;; a real defect rather than a preference. Asserted directly, because the oracle
;; cannot cover a shape the two implementations disagree on by intent.
(test-equal " " (fmt (flatten (align nl)) 80))
(test-equal " " (fmt (flatten (nest 2 nl)) 80))
(test-equal " " (fmt (flatten (reset nl)) 80))
(test-equal "" (fmt (flatten (align break)) 80))
(test-assert (no-layout? (flatten (align hard-nl))))
(test-assert (no-layout? (flatten (nest 2 hard-nl))))
(test-assert (no-layout? (flatten (reset hard-nl))))
;; and therefore group of that shape has only the broken alternative.
(test-equal "\n" (fmt (group (align hard-nl)) 80))

;; group takes the flat rendering when it fits and the broken one when it does
;; not. The document must contain a soft newline for group to be a choice at
;; all -- group of something with nothing to flatten is that thing.
(define groupable (group (u-append (text "aaa") nl (text "bbb"))))
(test-equal "aaa bbb" (fmt groupable 80))
(test-equal "aaa\nbbb" (fmt groupable 4))

;; flatten is idempotent.
(test-assert (same? (flatten (flatten (u-append (text "a") nl (text "b"))))
                    (flatten (u-append (text "a") nl (text "b")))
                    80))

;; The constants.
(test-equal "" (fmt empty-doc 80))
(test-equal " " (fmt space 80))
(test-equal "()" (fmt (u-append lparen rparen) 80))
(test-equal "[]" (fmt (u-append lbracket rbracket) 80))
(test-equal "a b" (fmt (flatten (u-append (text "a") nl (text "b"))) 80))
(test-equal "ab" (fmt (flatten (u-append (text "a") break (text "b"))) 80))

(test-end)

;;; The append families

(test-begin "append families")

;; Every family is empty at zero arguments and the identity at one.
(test-equal "" (fmt (u-append) 80))
(test-equal "" (fmt (us-append) 80))
(test-equal "" (fmt (v-append) 80))
(test-equal "" (fmt (a-append) 80))
(test-equal "" (fmt (as-append) 80))
(test-equal "solo" (fmt (u-append (text "solo")) 80))
(test-equal "solo" (fmt (us-append (text "solo")) 80))
(test-equal "solo" (fmt (v-append (text "solo")) 80))
(test-equal "solo" (fmt (a-append (text "solo")) 80))
(test-equal "solo" (fmt (as-append (text "solo")) 80))

;; Two and several arguments.
(test-equal "abc" (fmt (u-append (text "a") (text "b") (text "c")) 80))
(test-equal "a b c" (fmt (us-append (text "a") (text "b") (text "c")) 80))
(test-equal "a\nb\nc" (fmt (v-append (text "a") (text "b") (text "c")) 80))

;; The -concat forms take a list and agree with the variadic forms.
(test-equal (fmt (u-append (text "a") (text "b")) 80)
            (fmt (u-concat (list (text "a") (text "b"))) 80))
(test-equal (fmt (us-append (text "a") (text "b")) 80)
            (fmt (us-concat (list (text "a") (text "b"))) 80))
(test-equal (fmt (v-append (text "a") (text "b")) 80)
            (fmt (v-concat (list (text "a") (text "b"))) 80))
(test-equal (fmt (a-append (text "a") (text "b")) 80)
            (fmt (a-concat (list (text "a") (text "b"))) 80))
(test-equal (fmt (as-append (text "a") (text "b")) 80)
            (fmt (as-concat (list (text "a") (text "b"))) 80))
(test-equal "" (fmt (u-concat '()) 80))

;; The aligned families indent the right operand to the current column.
(test-equal "ab\n  cd" (fmt (a-append (text "ab") (u-append (text "") hard-nl (text "cd"))) 80))
(test-equal "ab \n   cd" (fmt (as-append (text "ab") (u-append (text "") hard-nl (text "cd"))) 80))
;; while the unaligned one does not.
(test-equal "ab\ncd" (fmt (u-append (text "ab") (u-append (text "") hard-nl (text "cd"))) 80))

(test-end)

(test-exit)
