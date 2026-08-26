#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the output safety checks: layer 1 token equivalence, layer 2 datum
;; equivalence, and the combined runner.
;;
;; The layer 2 groups moved here unchanged from tests/test-datum.sps, which
;; keeps the projection tests. They arrived there because the projection and
;; the check shipped together; with two checks in (pitch check) they belong
;; with their sibling.
;;
;; The negative tests matter more than the positive ones throughout. A
;; comparator that returns #t unconditionally passes every positive test in
;; this file.
#!r6rs

(import
  (rnrs (6))
  (pitch reader)
  (pitch parse)
  (pitch check)
  (tests runner))

;;; Layer 1 helpers

(define (token-equivalent? a b)
  (let-values (((ok? mismatch diagnostics) (check-token-equivalence a b))) ok?))

(define (token-mismatch a b)
  (let-values (((ok? mismatch diagnostics) (check-token-equivalence a b)))
    mismatch))

(define (token-check-diagnostics a b)
  (let-values (((ok? mismatch diagnostics) (check-token-equivalence a b)))
    diagnostics))

;; The i-th token of a source, for the token=? unit tests.
(define (tok source i)
  (let-values (((tokens diagnostics) (tokenize source "<test>")))
    (vector-ref tokens i)))

;;; Layer 2 helpers

(define (equivalent? a b)
  (let-values (((ok? diagnostics) (check-datum-equivalence a b))) ok?))

(define (check-diagnostics a b)
  (let-values (((ok? diagnostics) (check-datum-equivalence a b))) diagnostics))

;;; Combined helpers

(define (output-ok? a b)
  (let-values (((ok? layer detail) (check-output a b))) ok?))

(define (output-layer a b)
  (let-values (((ok? layer detail) (check-output a b))) layer))

(define (output-detail a b)
  (let-values (((ok? layer detail) (check-output a b))) detail))

;;; token=?

(test-begin "token-equality")

(test-assert (token=? (tok "abc" 0) (tok "abc" 0)))
(test-assert (not (token=? (tok "abc" 0) (tok "abd" 0))))

;; Differing kind, differing text.
(test-assert (not (token=? (tok "(" 0) (tok "[" 0))))
(test-assert (not (token=? (tok ")" 0) (tok "]" 0))))

;; Position is not compared: the same identifier on line 1 and on line 3.
(test-assert (token=? (tok "abc" 0) (tok "\n\n  abc" 1)))
(test-equal 1 (token-start-line (tok "abc" 0)))
(test-equal 3 (token-start-line (tok "\n\n  abc" 1)))

;; The value is not compared, so equal values with different text differ.
(test-assert (not (token=? (tok "#xff" 0) (tok "255" 0))))
(test-assert (not (token=? (tok "#t" 0) (tok "#true" 0))))
(test-assert (not (token=? (tok "#e1@1" 0) (tok "#e01@1" 0))))

(test-end)

;;; The trailing line ending is filtered, like all other whitespace

(test-begin "trailing-line-ending")

;; A line comment's text includes its terminator, so these differ only in
;; whitespace and must compare equal.
(test-assert (token=? (tok "; c" 0) (tok "; c\n" 0)))
(test-assert (token-equivalent? "(a) ; c" "(a) ; c\n"))

;; Every line ending the reader's grammar counts, including the two-character
;; forms, which count as one.
(for-each (lambda (source) (test-assert (token=? (tok "; c" 0) (tok source 0))))
          '("; c\n" "; c\r" "; c\r\n" "; c\x85;" "; c\r\x85;"
            "; c\x2028;" "; c\x2029;"))

;; Content is still compared exactly. This is not a normalization.
(test-assert (not (token=? (tok "; c" 0) (tok "; d" 0))))
(test-assert (not (token-equivalent? "(a) ; c" "(a) ; d")))
(test-assert (not (token-equivalent? "(a) ;; c" "(a) ; c")))

;; Only a trailing line ending is dropped; a nested comment ends with |# and
;; is untouched.
(test-assert (not (token=? (tok "#| b |#" 0) (tok "#| c |#" 0))))
(test-assert (token=? (tok "#| b |#" 0) (tok "#| b |#" 0)))

;; A shebang also carries its newline.
(test-assert (token=? (tok "#! g !#\n" 0) (tok "#! g !#" 0)))

(test-end)

;;; Whitespace filtering

(test-begin "whitespace-filtered")

(test-assert (token-equivalent? "(a  b)" "(a\n  b)"))
(test-assert (token-equivalent? "(define (f x)\n  (g x))" "(define (f x) (g x))"))
(test-assert (token-equivalent? "  (a b)  " "(a b)"))
(test-assert (token-equivalent? "(a)\n\n\n(b)" "(a) (b)"))
(test-assert (token-equivalent? "(a)" "(a)\n"))

;; A reindented comment keeps its place in the sequence.
(test-assert (token-equivalent? "(a ; c\n b)" "(a   ; c\n     b)"))

(test-end)

;;; The sequence is interleaved, not two subsequences

(test-begin "interleaved-sequence")

;; A comment moving across a code token changes which code it documents.
;; Separate code and comment subsequences would call this equivalent.
(test-assert (not (token-equivalent? "(a ; c\n b)" "(a b ; c\n)")))

;; Two comments exchanged.
(test-assert (not (token-equivalent? "(a ; c\n b ; d\n)" "(a ; d\n b ; c\n)")))

;; A directive moving across code.
(test-assert (not (token-equivalent? "#!fold-case (a)" "(a) #!fold-case")))

(test-end)

;;; Layer 1 catches what layer 2 cannot
;;
;; Each pair is asserted twice: layer 2 passes it, layer 1 catches it. Keeping
;; both assertions side by side is what makes "strictly stronger" a fact in the
;; suite rather than a claim in a comment.

(test-begin "layer1-stronger-than-layer2")

(letrec ((only-layer1-catches
          (lambda (a b)
            (and (equivalent? a b)              ;layer 2 passes
                 (not (token-equivalent? a b))))))  ;layer 1 catches
  (test-assert (only-layer1-catches "(a ; note\n b)" "(a b)"))   ;comment deleted
  (test-assert (only-layer1-catches "(a #;(x) b)" "(a b)"))      ;#; deleted
  (test-assert (only-layer1-catches "(a #;(x) b)" "(a b #;(x))")) ;#; relocated
  (test-assert (only-layer1-catches "[a b]" "(a b)"))            ;bracket flipped
  (test-assert (only-layer1-catches "'x" "(quote x)"))           ;abbrev expanded
  (test-assert (only-layer1-catches "#xff" "255"))               ;radix changed
  (test-assert (only-layer1-catches "\"\\x41;\"" "\"A\""))       ;escape respelled
  (test-assert (only-layer1-catches "#\\nul" "#\\null"))         ;char name
  (test-assert (only-layer1-catches "#vu8(1)" "#u8(1)"))         ;dialect spelling
  (test-assert (only-layer1-catches "(a #| c |# b)" "(a b)")))   ;block comment

(test-end)

;;; Merging and swallowing

(test-begin "layer1-merging")

;; The re-lex class: text that reads back as different tokens.
(test-assert (not (token-equivalent? "(- 1)" "(-1)")))
(test-assert (not (token-equivalent? "(a . b)" "(a .b)")))
(test-assert (not (token-equivalent? "(a b)" "(ab)")))

;; The most dangerous printer bug in any Lisp formatter: a line comment not
;; followed by a line break swallows the rest of the line.
(test-assert (not (token-equivalent? "(a ; c\n b)" "(a ; c b)")))

;; Lost and gained delimiters.
(test-assert (not (token-equivalent? "(a b)" "(a b")))
(test-assert (not (token-equivalent? "(a b)" "(a b))")))

;; A merge is caught by kind before text even matters: the "-" identifier
;; becomes part of a number.
(let ((m (token-mismatch "(- 1)" "(-1)")))
  (test-equal 1 (mismatch-index m))
  (test-equal 'identifier (token-kind (mismatch-input-token m)))
  (test-equal 'value (token-kind (mismatch-output-token m))))

(test-end)

;;; Mismatch reporting

(test-begin "layer1-mismatch-reporting")

;; The first differing position, with both tokens.
(let ((m (token-mismatch "(a b)" "(a c)")))
  (test-equal 2 (mismatch-index m))
  (test-equal "b" (token-text (mismatch-input-token m)))
  (test-equal "c" (token-text (mismatch-output-token m))))

;; A dropped comment: the mismatch is at the comment's position, and the two
;; sides disagree about what is there.
(let ((m (token-mismatch "(a ; note\n b)" "(a b)")))
  (test-equal 2 (mismatch-index m))
  (test-equal 'comment (token-kind (mismatch-input-token m)))
  (test-assert (not (eq? 'comment (token-kind (mismatch-output-token m))))))

;; A lost closing delimiter shows up as a delimiter meeting end of input.
(let ((m (token-mismatch "(a b)" "(a b")))
  (test-equal 'closep (token-kind (mismatch-input-token m)))
  (test-equal 'eof (token-kind (mismatch-output-token m))))

;; An equivalent pair reports no mismatch at all.
(test-equal #f (token-mismatch "(a  b)" "(a\n b)"))
(test-equal #f (token-mismatch "(a)" "(a)"))

(test-end)

;;; Layer 1 diagnostics

(test-begin "layer1-diagnostics")

;; Identical texts, but neither is usable.
(test-assert (not (token-equivalent? "(a #z b)" "(a #z b)")))
(test-assert (positive? (length (token-check-diagnostics "(a #z b)" "(a #z b)"))))

;; A clean pair reports none.
(test-equal '() (token-check-diagnostics "(a b)" "(a  b)"))

;; Layer 1 uses the lexer alone, so a purely structural defect is not a
;; diagnostic here -- it shows up as a differing token sequence instead.
(test-equal '() (token-check-diagnostics "(a b)" "(a b)"))

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
(test-assert (not (equivalent? "#e1@1" "#e01@1")))

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

;; Fresh reads of one opaque spelling compare equal. Alternate opaque
;; spellings are intentionally not a layer-2 normalization.
(test-assert (equivalent? "#e1@1" "#e1@1"))

(test-end)

;;; The combined runner

(test-begin "combined-runner")

;; A layout-only difference passes every layer, and no layer is blamed.
(test-assert (output-ok? "(define (f x)\n  (g x))" "(define (f x) (g x))"))
(test-equal #f (output-layer "(define (f x)\n  (g x))" "(define (f x) (g x))"))
(test-equal #f (output-detail "(define (f x)\n  (g x))" "(define (f x) (g x))"))

;; A difference only layer 1 sees.
(test-assert (not (output-ok? "(a ; note\n b)" "(a b)")))
(test-equal 'token-equivalence (output-layer "(a ; note\n b)" "(a b)"))
(test-assert (mismatch? (output-detail "(a ; note\n b)" "(a b)")))

;; A difference both layers see is blamed on the stronger one, whose report
;; says where.
(test-assert (not (output-ok? "(a b)" "(a c)")))
(test-equal 'token-equivalence (output-layer "(a b)" "(a c)"))
(test-equal 2 (mismatch-index (output-detail "(a b)" "(a c)")))

;; An unusable text fails before any layer runs, so none is blamed.
(test-assert (not (output-ok? "(a (b" "(a (b")))
(test-equal #f (output-layer "(a (b" "(a (b"))
(test-assert (pair? (output-detail "(a (b" "(a (b")))

(test-assert (not (output-ok? "(#1#)" "(#1#)")))
(test-equal #f (output-layer "(#1#)" "(#1#)"))
(test-assert (pair? (output-detail "(#1#)" "(#1#)")))

(test-end)

(test-exit)
