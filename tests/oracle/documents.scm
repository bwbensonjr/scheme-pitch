;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The differential oracle's corpus.
;;
;; ONE file drives BOTH implementations: tests/oracle/oracle-emit.scm builds these
;; documents with (pitch doc) and tests/oracle/oracle.rkt builds them with
;; Racket's pretty-expressive. `make oracle-layout` renders each entry with both
;; and diffs the results. Two hand-written parallel test programs would drift --
;; a case added on one side and forgotten on the other silently reduces coverage
;; and nothing reports it -- so adding a case here must be the only edit needed.
;;
;; Each entry is
;;
;;   (name page-width computation-width offset document)
;;
;; where computation-width may be #f for the default, and document is written in
;; the small description language both drivers interpret:
;;
;;   (text "s")  (newline "s")  (newline #f)  nl  break  hard-nl  empty-doc  fail
;;   (concat a b)  (alternatives a b)  (alt a ...)
;;   (nest n d)  (align d)  (reset d)  (full d)  (cost (badness height) d)
;;   (group d)  (flatten d)
;;   (u-append a ...)  (us-append a ...)  (v-append a ...)
;;   (a-append a ...)  (as-append a ...)
;;
;; EXCLUDED ON PURPOSE:
;;
;;   - `special`, which is not ported. It passes a non-string value through a
;;     Racket structured output port and pitch renders to a string.
;;
;;   - a newline as the DIRECT child of align, nest or reset -- (align nl),
;;     (nest 2 hard-nl), (group (align hard-nl)) and the like. The reference's
;;     `flatten` leaves such a newline unflattened, which pitch treats as a bug
;;     and fixes; see the DIVERGENCE note in src/pitch/doc.sld. The two
;;     implementations disagree there by intent, so comparing them would report
;;     a difference we chose. tests/test-doc-r7rs.scm asserts the fixed behaviour
;;     directly instead.
;;
;; Newlines nested any deeper under those wrappers are fine and are exercised
;; below, since the bug only reaches a direct child.

(
 ;;; Each core constructor in isolation

 (text-simple            80 #f 0 (text "abc"))
 (text-empty             80 #f 0 (text ""))
 (empty                  80 #f 0 empty-doc)
 (newline-hard           80 #f 0 (u-append (text "a") hard-nl (text "b")))
 (newline-soft-flat      80 #f 0 (group (u-append (text "a") nl (text "b"))))
 (newline-break          80 #f 0 (u-append (text "a") break (text "b")))
 (newline-custom         80 #f 0 (flatten (u-append (text "a") (newline "--") (text "b"))))
 (concat-two             80 #f 0 (concat (text "ab") (text "cd")))
 (concat-empty-left      80 #f 0 (concat empty-doc (text "x")))
 (concat-empty-right     80 #f 0 (concat (text "x") empty-doc))
 (alternatives-pick      20 #f 0 (alternatives (text "aaaaaaaaaaaaaaaaaaaaaaaaaaaa") (text "b")))
 (alt-three              20 #f 0 (alt (text "aaaaaaaaaaaaaaaaaaaaaaaaaaaa") (text "bb") (text "c")))
 (nest-basic             80 #f 0 (nest 4 (u-append (text "a") hard-nl (text "b"))))
 (nest-nested            80 #f 0 (nest 2 (nest 3 (u-append (text "a") hard-nl (text "b")))))
 (nest-zero              80 #f 0 (nest 0 (u-append (text "a") hard-nl (text "b"))))
 (align-basic            80 #f 0 (u-append (text "ab") (align (u-append (text "c") hard-nl (text "d")))))
 (align-deep             80 #f 0 (u-append (text "abcd") (align (u-append (text "e") hard-nl (text "f") hard-nl (text "g")))))
 (reset-basic            80 #f 0 (nest 6 (u-append (text "a") hard-nl (reset (u-append (text "b") hard-nl (text "c"))))))
 (cost-annotation        20 #f 0 (alt (cost (0 0) (u-append (text "aa") hard-nl (text "bb")))
                                      (cost (0 5) (text "aa bb"))))
 (cost-tips-the-balance  20 #f 0 (alt (cost (0 9) (u-append (text "aa") hard-nl (text "bb")))
                                      (cost (0 0) (text "aa bb"))))

 ;;; full, satisfiable and not

 (full-alone             80 #f 0 (full (text "a")))
 (full-then-newline      80 #f 0 (u-append (full (text "a")) hard-nl (text "b")))
 (full-then-text         80 #f 0 (concat (full (text "a")) (text "b")))
 (full-idempotent        80 #f 0 (full (full (text "a"))))
 (full-inside-group      80 #f 0 (group (u-append (full (text "a")) hard-nl (text "b"))))
 (full-empty-text-after  80 #f 0 (concat (full (text "a")) (text "")))

 ;;; fail, and its algebra

 (fail-alone             80 #f 0 fail)
 (fail-in-concat         80 #f 0 (concat fail (text "a")))
 (fail-in-alt-left       80 #f 0 (alternatives fail (text "a")))
 (fail-in-alt-right      80 #f 0 (alternatives (text "a") fail))
 (fail-both-alts         80 #f 0 (alternatives fail fail))
 (flatten-hard-fails     80 #f 0 (flatten (u-append (text "a") hard-nl (text "b"))))

 ;;; Overflow, so taint is compared and not only text

 (overflow-single-text   20 #f 0 (text "xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx"))
 (overflow-narrow        10 #f 0 (text "abcdefghijklmnopqrstuvwxyz"))
 (overflow-tiny-limit     8  9 0 (text "abcdefghijklmnop"))
 (overflow-unavoidable   12 #f 0 (u-append (text "aaaaaaaaaaaaaaaa") nl (text "bbbbbbbbbbbbbbbb")))
 (overflow-mixed         12 #f 0 (group (u-append (text "aaaaaaaaaaaaaaaa") nl (text "bb"))))
 (near-limit             10 12 0 (group (u-append (text "aaaaa") nl (text "bbbbb"))))

 ;;; Explicit computation widths

 (cw-equal-page          20 20 0 (group (u-append (text "aaaaaaaaaa") nl (text "bbbbbbbbbb"))))
 (cw-wide                20 60 0 (group (u-append (text "aaaaaaaaaa") nl (text "bbbbbbbbbb"))))
 (cw-narrow              40 12 0 (group (u-append (text "aaaaaaaaaa") nl (text "bbbbbbbbbb"))))

 ;;; Non-zero offsets
 ;;
 ;; A group is only a choice when its argument contains a soft newline: group of
 ;; a document with nothing to flatten is the document. These use `nl` between
 ;; the pieces rather than the space that us-append inserts, so that the offset
 ;; can actually decide whether the group breaks.

 (offset-four            20 #f 4 (group (u-append (text "aaaa") nl (text "bbbb") nl (text "cccc"))))
 (offset-forces-break    12 #f 8 (group (u-append (text "aaaa") nl (text "bbbb"))))
 (offset-with-align      30 #f 6 (a-append (text "head") (u-append (text "x") hard-nl (text "y"))))
 (offset-zero-baseline   12 #f 0 (group (u-append (text "aaaa") nl (text "bbbb"))))

 ;;; The append families

 (u-append-many          80 #f 0 (u-append (text "a") (text "b") (text "c") (text "d")))
 (u-append-none          80 #f 0 (u-append))
 (u-append-one           80 #f 0 (u-append (text "solo")))
 (us-append-many         80 #f 0 (us-append (text "a") (text "b") (text "c")))
 (v-append-many          80 #f 0 (v-append (text "a") (text "b") (text "c")))
 (a-append-two           80 #f 0 (a-append (text "head ") (u-append (text "x") hard-nl (text "y"))))
 (as-append-two          80 #f 0 (as-append (text "head") (u-append (text "x") hard-nl (text "y"))))
 (as-append-three        40 #f 0 (as-append (text "aa") (text "bb") (u-append (text "x") hard-nl (text "y"))))

 ;;; group and flatten, away from the diverging shape

 (group-fits             80 #f 0 (group (u-append (text "aa") nl (text "bb"))))
 (group-does-not-fit      5 #f 0 (group (u-append (text "aaa") nl (text "bbb"))))
 (group-nested-fits      80 #f 0 (group (u-append (text "(") (group (u-append (text "a") nl (text "b"))) (text ")"))))
 (group-nested-breaks     6 #f 0 (group (u-append (text "(") (group (u-append (text "aaa") nl (text "bbb"))) (text ")"))))
 (flatten-idempotent     80 #f 0 (flatten (flatten (u-append (text "a") nl (text "b")))))
 (flatten-of-align       80 #f 0 (flatten (align (u-append (text "a") nl (text "b")))))
 (flatten-of-nest        80 #f 0 (flatten (nest 4 (u-append (text "a") nl (text "b")))))
 (flatten-of-group       80 #f 0 (flatten (group (u-append (text "a") nl (text "b")))))

 ;;; Structural sharing, so memoization is exercised

 (shared-group-depth-3   20 #f 0 (group (u-append (text "aa")
                                                  nl
                                                  (group (u-append (text "bb")
                                                                   nl
                                                                   (group (u-append (text "cc") nl (text "dd"))))))))
 (shared-group-depth-4   16 #f 0 (group (a-append (text "(f ")
                                                  (u-append (group (a-append (text "(g ")
                                                                             (u-append (group (a-append (text "(h ")
                                                                                                        (u-append (group (u-append (text "i") nl (text "j")))
                                                                                                                  (text ")"))))
                                                                                       (text ")"))))
                                                            (text ")")))))
 (shared-group-depth-4-narrow 8 #f 0 (group (a-append (text "(f ")
                                                      (u-append (group (a-append (text "(g ")
                                                                                 (u-append (group (u-append (text "i") nl (text "j")))
                                                                                           (text ")"))))
                                                                (text ")")))))
 (repeated-subdocument   24 #f 0 (v-append (group (u-append (text "aaaa") nl (text "bbbb")))
                                           (group (u-append (text "aaaa") nl (text "bbbb")))
                                           (group (u-append (text "aaaa") nl (text "bbbb")))))

 ;;; Shapes a Lisp printer actually produces

 (sexp-fits              40 #f 0 (group (a-append (text "(define ")
                                                  (u-append (text "(f x)") nl (text "(g x)") (text ")")))))
 (sexp-breaks            12 #f 0 (group (a-append (text "(define ")
                                                  (u-append (text "(f x)") nl (text "(g x)") (text ")")))))
 (sexp-let               24 #f 0 (group (a-append (text "(let ")
                                                  (u-append (align (group (u-append (text "((a 1)") nl (text "(b 2))"))))
                                                            nl
                                                            (text "(+ a b))")))))
 (sexp-nested-calls      20 #f 0
  (group (u-append (text "(a ")
                   (align (group (u-append (text "(b ")
                                           (align (group (u-append (text "c") nl (text "d"))))
                                           (text ")"))))
                   (text ")"))))
 (sexp-nested-calls-tight 8 #f 0
  (group (u-append (text "(a ")
                   (align (group (u-append (text "(b ")
                                           (align (group (u-append (text "c") nl (text "d"))))
                                           (text ")"))))
                   (text ")"))))
 (sexp-wide-arglist      28 #f 0 (group (a-append (text "(call ")
                                                  (u-append (text "arg1") nl (text "arg2") nl
                                                            (text "arg3") nl (text "arg4") (text ")")))))
 (sexp-wide-arglist-tight 14 #f 0 (group (a-append (text "(call ")
                                                   (u-append (text "arg1") nl (text "arg2") nl
                                                             (text "arg3") nl (text "arg4") (text ")")))))
 (sexp-comment-then-break 40 #f 0 (v-append (text "; a leading comment")
                                            (group (u-append (text "(f") nl (text "x)")))))

 ;;; Choice resolved by total cost rather than local fit
 ;;
 ;; The point of Pi-e over a greedy printer. In each of these the first group's
 ;; flat rendering fits on its own, but taking it pushes what follows past the
 ;; page width, so the cheaper whole-document answer is to break early.

 (not-greedy-early-break 12 #f 0 (u-append (group (u-append (text "aaaa") nl (text "bbbb")))
                                           (text "cccccccc")))
 (not-greedy-fits-anyway 40 #f 0 (u-append (group (u-append (text "aaaa") nl (text "bbbb")))
                                           (text "cccccccc")))
 (not-greedy-two-groups  16 #f 0 (u-append (group (u-append (text "aa") nl (text "bb")))
                                           (group (u-append (text "cc") nl (text "dddddddddd")))))

 ;;; The paper's worked examples, from the reference's tests/examples.rkt
 ;;
 ;; Three encodings of one layout problem, at the two page widths where their
 ;; answers differ. tests/test-layout-r7rs.scm pins the expected text directly; here
 ;; they also compare cost. Written out rather than shared, since the corpus
 ;; language has no way to bind a name and sharing changes no answer.

 (paper-traditional-36 36 #f 0
  (u-append (text "function append(first,second,third){")
            (nest 4 (u-append nl (text "return ")
                              (group (nest 4 (u-append (text "first +") nl
                                                       (text "second +") nl
                                                       (text "third"))))))
            nl (text "}")))
 (paper-traditional-22 22 #f 0
  (u-append (text "function append(first,second,third){")
            (nest 4 (u-append nl (text "return ")
                              (group (nest 4 (u-append (text "first +") nl
                                                       (text "second +") nl
                                                       (text "third"))))))
            nl (text "}")))

 (paper-arbitrary-36 36 #f 0
  (v-append (text "function append(first,second,third){")
            (a-append (text "    ")
                      (alt (v-append (a-append (text "return ") (text "("))
                                     (a-append (text "    ")
                                               (v-append (text "first +") (text "second +") (text "third")))
                                     (text ")"))
                           (a-append (text "return ") (text "first +") (text " ")
                                     (text "second +") (text " ") (text "third"))))
            (text "}")))
 (paper-arbitrary-22 22 #f 0
  (v-append (text "function append(first,second,third){")
            (a-append (text "    ")
                      (alt (v-append (a-append (text "return ") (text "("))
                                     (a-append (text "    ")
                                               (v-append (text "first +") (text "second +") (text "third")))
                                     (text ")"))
                           (a-append (text "return ") (text "first +") (text " ")
                                     (text "second +") (text " ") (text "third"))))
            (text "}")))

 (paper-expressive-36 36 #f 0
  (u-append (text "function append(first,second,third){")
            (nest 4 (u-append nl (text "return ")
                              (alt (u-append (text "(")
                                             (nest 4 (u-append nl (text "first +") nl
                                                               (text "second +") nl (text "third")))
                                             nl (text ")"))
                                   (u-append (text "first +") (text " ") (text "second +")
                                             (text " ") (text "third")))))
            nl (text "}")))
 (paper-expressive-22 22 #f 0
  (u-append (text "function append(first,second,third){")
            (nest 4 (u-append nl (text "return ")
                              (alt (u-append (text "(")
                                             (nest 4 (u-append nl (text "first +") nl
                                                               (text "second +") nl (text "third")))
                                             nl (text ")"))
                                   (u-append (text "first +") (text " ") (text "second +")
                                             (text " ") (text "third")))))
            nl (text "}")))
)
