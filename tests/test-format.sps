#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the end-to-end pipeline.
;;
;; This is the first place the safety checks run against real output, so the
;; most important test here is not that formatting works -- it is that the check
;; would notice if it did not. "The check receives the produced text" is
;; asserted by taking the pipeline's own output and showing that a mutation of
;; it fails the same check the pipeline calls. Comparing an in-memory tree
;; against itself passes no matter what the printer did, and docs/DESIGN.md §1
;; calls that the vacuousness trap; a check nobody has seen fail is one nobody
;; should trust.
;;
;; RUNTIME. The corpus section formats every file listed twice, which is a few
;; seconds -- most of it in the layout engine, which runs at roughly 20KB of
;; source per second. That is the price of testing against real input rather
;; than against hand-written snippets, and it is the only slow part of `make
;; test`.
#!r6rs

(import
  (except (rnrs (6)) newline)
  (pitch format)
  (pitch check)
  (tests runner))

;;; Helpers

(define (status src . width)
  (let-values (((text result) (apply format-source src "test" width)))
    (format-result-status result)))

(define (text-of src . width)
  (let-values (((text result) (apply format-source src "test" width)))
    text))

(define (tainted? src . width)
  (let-values (((text result) (apply format-source src "test" width)))
    (format-result-tainted? result)))

(define (detail-of src . width)
  (let-values (((text result) (apply format-source src "test" width)))
    (format-result-detail result)))

;; Lines of content. Every formatted file ends with a newline, and counting the
;; empty string after it as a line would make a one-line file report two.
(define (line-count s)
  (let* ((n (string-length s))
         (n (if (and (> n 0) (char=? (string-ref s (- n 1)) #\linefeed))
                (- n 1)
                n)))
    (let loop ((i 0) (lines 1))
      (cond ((= i n) lines)
            ((char=? (string-ref s i) #\linefeed) (loop (+ i 1) (+ lines 1)))
            (else (loop (+ i 1) lines))))))

(define (contains? haystack needle)
  (let ((hn (string-length haystack)) (nn (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nn) hn) #f)
            ((string=? (substring haystack i (+ i nn)) needle) #t)
            (else (loop (+ i 1)))))))

(define (raises? thunk)
  (guard (e (#t #t))
    (thunk)
    #f))

(define (checks-pass? a b)
  (let-values (((ok? layer detail) (check-output a b)))
    ok?))

(define (file-contents path)
  (let ((p (open-input-file path)))
    (let loop ((acc '()))
      (let ((c (get-char p)))
        (if (eof-object? c)
            (begin (close-port p) (list->string (reverse acc)))
            (loop (cons c acc)))))))

;;; One operation runs the whole pipeline

(test-begin "the pipeline formats")

(test-equal 'ok (status "(define (f x) (g x))\n"))
(test-equal "(define (f x) (g x))\n" (text-of "(define (f x) (g x))\n"))

;; The width is honored: narrower gives at least as many lines.
(test-assert (>= (line-count (text-of "(f (g 1 2) (h 3 4) (i 5 6))\n" 15))
                 (line-count (text-of "(f (g 1 2) (h 3 4) (i 5 6))\n" 80))))
(test-equal 1 (line-count (text-of "(f a b)\n" 80)))

;; The default width is 88, so a call fitting in 88 columns but not 20 comes
;; back on one line when no width is given.
(test-equal 1 (line-count (text-of "(f aaaaaaaaaa bbbbbbbbbb cccccccccc)\n")))
(test-assert (> (line-count (text-of "(f aaaaaaaaaa bbbbbbbbbb cccccccccc)\n" 20)) 1))

;; Already-formatted input comes back unchanged.
(test-equal "(f a b)\n" (text-of "(f a b)\n"))
(test-equal "(a ; note\n  b)\n" (text-of "(a ; note\n  b)\n"))

(test-end)

;;; Refusals

(test-begin "an unclean parse is refused")

(test-equal 'unclean-parse (status "(a"))
(test-equal 'unclean-parse (status "(a))"))
(test-equal 'unclean-parse (status "(a]"))
(test-equal 'unclean-parse (status "(. a)"))

;; No text is returned, and the diagnostics come back as the detail.
(test-equal #f (text-of "(a"))
(test-assert (pair? (detail-of "(a")))

(test-end)

(test-begin "a foreign interior line ending is refused")

;; A CRLF inside a token whose text token equivalence compares. Emitting it as
;; a linefeed would change that text, and normalizing is prohibited while the
;; declared-normalizations list is empty.
(test-equal 'unsupported-line-ending (status "(a #| x\x000D;\x000A;y |# b)\n"))
(test-equal 'unsupported-line-ending (status "(f \"a\x000D;\x000A;b\")\n"))
(test-equal 'unsupported-line-ending (status "(a #;(b\x000D;c) d)\n"))
(test-equal #f (text-of "(a #| x\x000D;\x000A;y |# b)\n"))

;; Between tokens it is whitespace, which the formatter re-derives, so a
;; CRLF-delimited file with no multi-line token formats normally.
(test-equal 'ok (status "(a)\x000D;\x000A;(b)\x000D;\x000A;"))
(test-equal "(a)\n(b)\n" (text-of "(a)\x000D;\x000A;(b)\x000D;\x000A;"))

;; And the line ending terminating a comment is not interior: the printer
;; splits it off and emits an explicit break in its place.
(test-equal 'ok (status "; c\x000D;\x000A;(a)\x000D;\x000A;"))

(test-end)

;;; The checks are live
;;
;; The point of this section: show the check the pipeline calls would fail if
;; the printer misbehaved, using the pipeline's own real output.

(test-begin "the check receives the produced text")

(define comment-src "(define (f x) ; why\n  (g x))\n")
(define comment-out (text-of comment-src))

;; The real output passes both layers.
(test-assert (checks-pass? comment-src comment-out))

;; The same output with the comment deleted does not. So the comparison is
;; against text, and it has teeth on exactly the defect that matters most.
(test-assert (not (checks-pass? comment-src "(define (f x)\n  (g x))\n")))

;; Nor with a bracket flipped, an abbreviation expanded, or a numeric lexeme
;; respelled -- all of which pass datum equivalence and fail token equivalence.
(test-assert (not (checks-pass? "[a b]\n" "(a b)\n")))
(test-assert (not (checks-pass? "'x\n" "(quote x)\n")))
(test-assert (not (checks-pass? "#xff\n" "255\n")))

;; A layout-only difference passes, which is what lets the formatter work at
;; all: comments, brackets, datum comments and numeric lexemes all survive.
(define busy-src
  "(let ([x #xff]) ; note\n  #;(dead code)\n  #| block |#\n  (f 'x `(a ,b)))\n")
(test-equal 'ok (status busy-src))
(test-assert (checks-pass? busy-src (text-of busy-src)))
(test-assert (checks-pass? busy-src (text-of busy-src 20)))

(test-end)

;;; The dialect

(test-begin "the dialect selects a table and nothing else")

;; It changes output. `define-record-type` is the collision: same head, and two
;; incompatible shapes, which is why the table is dialect-parameterized at all.
(define drt "(define-record-type <p> (mk x) p? (x px))\n")
(test-assert (not (equal? (text-of drt 40 'r6rs) (text-of drt 40 'r7rs))))

;; It never changes acceptance. The reader is a permissive union, and the
;; dialect reaches only the translation.
(test-equal 'ok (status drt 40 'r6rs))
(test-equal 'ok (status drt 40 'r7rs))
(test-equal 'ok (status drt 40 'common))
(test-equal 'ok (status "#vu8(1 2)\n" 40 'r7rs))
(test-equal 'ok (status "#u8(1 2)\n" 40 'r6rs))
(test-assert (contains? (text-of "#vu8(1 2)\n" 40 'r7rs) "#vu8("))
(test-assert (contains? (text-of "#u8(1 2)\n" 40 'r6rs) "#u8("))

;; A source valid in either standard is still refused on the same grounds under
;; every dialect: the refusals are not dialect questions.
(test-equal 'unclean-parse (status "(a" 40 'r6rs))
(test-equal 'unclean-parse (status "(a" 40 'r7rs))

;; The default is the shared core.
(test-equal (text-of drt 40) (text-of drt 40 'common))

;; An unknown dialect raises, and raises before an unclean parse could mask it.
(test-assert (raises? (lambda () (format-source "(a)\n" "test" 40 'r5rs))))
(test-assert (raises? (lambda () (format-source "(a" "test" 40 'r5rs))))

(test-end)

;;; Taint

(test-begin "a tainted layout is reported, not failed")

;; A token longer than the page width cannot be laid out within it, so the
;; search stops proving minimality. The text is still complete and checked.
(test-equal 'ok (status "(f aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)\n" 10))
(test-assert (tainted? "(f aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)\n" 10))
(test-assert (string? (text-of "(f aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa)\n" 10)))

;; An ordinary source is not tainted.
(test-assert (not (tainted? "(f a b)\n" 80)))

(test-end)

;;; Idempotence

(test-begin "formatting is idempotent")

(define (idempotent? src width)
  (let ((once (text-of src width)))
    (and once (equal? once (text-of once width)))))

(define idempotence-cases
  (list "(define (f x) (g x) (h x))\n"
        "(a ; trailing\n b)\n"
        "(a\n ; own line\n b)\n"
        "(x)\n\n\n(y)\n"
        "(a\n\nb)\n"
        "(let ([x 1] [y 2]) (f x y))\n"
        "'(1 2 3 4 5 6 7 8 9 10)\n"
        "(a . b)\n"
        "#(1 2 3) #vu8(1 2 3)\n"
        "(a #;(b c) #| k |# d)\n"
        "#!r6rs\n(library (x) (export a) (import (rnrs)) (define a 1))\n"
        "; leading comment\n(f a)\n"
        "(f (g (h (i (j (k 1 2 3)))))) ; deep\n"
        "(a \"str\" #\\x #t)\n"))

(for-each
 (lambda (src)
   (for-each
    (lambda (width)
      (test-assert (idempotent? src width)))
    '(10 20 40 88)))
 idempotence-cases)

(test-end)

;;; The corpus
;;
;; Real input, which is the only kind that finds what hand-written cases do not.
;; Every file here is pitch's own source or its test suite. The vendored copies
;; under vendor/ are deliberately absent: they are pristine upstream, never
;; formatted, and src/pitch/reader.sls is derived from the largest of them and
;; carries the same syntax.

(test-begin "the in-repo corpus formats and is idempotent")

(define corpus
  '("src/pitch/lines.sls"
    "src/pitch/diagnostic.sls"
    "src/pitch/cst.sls"
    "src/pitch/parse.sls"
    "src/pitch/datum.sls"
    "src/pitch/check.sls"
    "src/pitch/cost.sls"
    "src/pitch/doc.sls"
    "src/pitch/layout.sls"
    "src/pitch/print.sls"
    "src/pitch/style.sls"
    "src/pitch/format.sls"
    "src/pitch/reader.sls"
    "tests/runner.sls"))

(define (corpus-check path dialect)
  (let ((source (file-contents path)))
    (let-values (((once result) (format-source source path default-page-width
                                               dialect)))
      (test-equal 'ok (format-result-status result))
      (when (string? once)
        ;; Idempotent, and the second pass is clean too.
        (let-values (((twice result2) (format-source once path
                                                     default-page-width dialect)))
          (test-equal 'ok (format-result-status result2))
          (test-equal once twice))))))

;; Every file, under r6rs -- which is what these files actually are, and whose
;; table is the core plus its own entries, so it exercises strictly more of the
;; table on real input than the default would.
(for-each (lambda (path) (corpus-check path 'r6rs)) corpus)

;; The dialect axis over a subset. Running the whole corpus three times would
;; roughly triple the slowest part of `make test` to show something the files
;; themselves cannot: they are all R6RS, so the other two dialects differ only
;; in which entries degrade, and a few files demonstrate that as well as
;; fourteen. What must hold under every dialect is that the checks still pass
;; and the output is still a fixpoint, and that is what this asserts.
(for-each
 (lambda (path)
   (for-each (lambda (dialect) (corpus-check path dialect))
             '(common r7rs)))
 '("src/pitch/lines.sls"
   "src/pitch/diagnostic.sls"
   "src/pitch/cost.sls"
   "tests/runner.sls"))

(test-end)

(test-exit)
