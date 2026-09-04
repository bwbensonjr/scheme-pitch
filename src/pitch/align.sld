;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Trailing-comment column alignment: the second entry on the
;; preserved-formatting list.
;;
;; Recognition happens on the SOURCE, application on the OUTPUT. There is
;; nothing to detect in the rendered text -- the printer emits one space before
;; every trailing comment -- and nothing to apply in the source, because the
;; column has to be computed against code whose width layout has already
;; decided. So this library reads the source to learn which comments the author
;; aligned, and rewrites the rendered text to put them at a column derived from
;; the reflowed code.
;;
;; ALIGNMENT IS RECOGNIZED AS A SHARED COLUMN, NEVER AS PADDING. This is the
;; load-bearing decision and it exists for one reason: idempotence. Align a run
;; whose code widths are 20, 30 and 25 and the widest line receives a single
;; space. A rule keyed on "two or more spaces" would then fail to re-recognize
;; that line when this output is formatted again, the run would split into three
;; runs of one, and all three would collapse back to single spaces. A shared
;; column re-detects itself exactly, because after alignment every comment in
;; the run begins at the same column. See the change proposal
;; preserve-trailing-comment-alignment for the alternatives that were rejected.
;;
;; This library knows nothing of the document algebra, the cost factory, the
;; layout engine, the printer or the style tables, and must not learn: the
;; column depends on sibling lines, which no document in the Pi-e algebra can
;; see, and teaching the engine about Scheme's comment conventions would break
;; the layering invariant outright. The import list is the check, and
;; tests/test-align-r7rs.scm asserts it.
;;
;; THE ONLY CHARACTERS THIS LIBRARY WRITES ARE SPACES, and it writes them only
;; where it has already read spaces. Everything else in the rendered text is
;; copied. That is a property of the loop in `rewrite` rather than a claim
;; about it, which matters because this pass runs before the output checks and
;; is therefore inside the region they verify.

(define-library (pitch align)
(export align-trailing-comments source-alignment-flags)
(import (scheme base) (pitch lines) (pitch parse) (pitch reader))
(begin

  (define-syntax let-values
    (syntax-rules ()
      ((_ (((name ...) producer)) body ...)
        (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

  ;;; What counts as a line comment

  ;; A line comment is a comment token spelled with a semicolon. The kind alone
  ;; is not enough: in the permissive mode the reader parses with, `#! ... !#`
  ;; also lexes as 'comment, and that form is delimited rather than terminated
  ;; by a line ending, so code can follow it on its line. Block comments,
  ;; datum comments and directives are excluded for the same reason -- "the
  ;; comment ends the line" is not a property any of them has -- and they are
  ;; excluded by kind, since none of them lexes as 'comment.
  (define (line-comment? tok)
    (and (eq? (token-kind tok) 'comment)
         (let ((text (token-text tok)))
           (and (positive? (string-length text)) (char=? (string-ref text 0) #\;)))))

  ;; Everything that occupies source but is not a datum, plus eof. A comment
  ;; needs a *code* token before it on its line to be trailing, so a block
  ;; comment or a datum comment sitting to its left does not make it one.
  (define (code-token? tok)
    (not (memq (token-kind tok)
               '(whitespace comment nested-comment inline-comment directive shebang
                 eof))))

  ;;; Source side

  ;; One entry per line comment, in source order: #f when the comment is not
  ;; trailing, otherwise the pair (line . column) of its semicolon.
  ;;
  ;; A comment is trailing when a code token before it ends on its line. Tracking
  ;; the last code token's END line rather than its start is what makes a
  ;; multi-line token -- a string or a `#| |#` block spanning lines -- count as
  ;; code on the line it finishes.
  ;;
  ;; The line and column are the reader's own, so the seven line endings its
  ;; grammar counts are all handled here by not being handled here. CR LF and
  ;; CR NEL are one ending to the reader, which is the case a character scan
  ;; written for this would miscount.
  (define (comment-sites text)
    (let-values (((tokens diagnostics) (tokenize text "<align>")))
      (let ((n (vector-length tokens)))
        (let loop ((i 0) (code-end-line #f) (sites '()))
          (if (= i n)
              (reverse sites)
              (let ((tok (vector-ref tokens i)))
                (cond
                  ((code-token? tok) (loop (+ i 1) (token-end-line tok) sites))
                  ((line-comment? tok)
                    (let ((line (token-start-line tok)))
                      (loop (+ i 1)
                            code-end-line
                            (cons (and (eqv? code-end-line line)
                                       (cons line (token-start-column tok)))
                                  sites))))
                  (else (loop (+ i 1) code-end-line sites)))))))))

  ;; The trailing sites, in source order. Line numbers are increasing and
  ;; distinct -- a line comment runs to the end of its line, so no two share one
  ;; -- which is what lets "the adjacent source line" be answered by looking at
  ;; the neighboring entries of this list rather than by searching.
  (define (trailing-sites sites)
    (let loop ((sites sites) (acc '()))
      (cond
        ((null? sites) (reverse acc))
        ((car sites) (loop (cdr sites) (cons (car sites) acc)))
        (else (loop (cdr sites) acc)))))

  ;; Whether the site shares a column with a trailing comment on the line
  ;; immediately before or immediately after it. The line difference must be
  ;; exactly one: two trailing comments at one column with a line between them
  ;; that carries none are two runs of one, not a run of two.
  (define (aligned-site? site before after)
    (define (partner? other delta)
      (and other (= (car other) (+ (car site) delta)) (= (cdr other) (cdr site))))
    (or (partner? before -1) (partner? after 1)))

  ;; One flag per line comment in source order: #t when that comment is an
  ;; aligned trailing comment, #f otherwise. Everything that is not a trailing
  ;; line comment is #f, including every own-line comment, whatever column it
  ;; begins at.
  (define (source-alignment-flags text)
    (let* ((sites (comment-sites text)) (trailing (trailing-sites sites)))
      ;; Walk the sites and the trailing sublist together. Each trailing site is
      ;; the head of what remains of the sublist, so its neighbors are the
      ;; element behind it and the second element ahead.
      (let loop ((sites sites) (before #f) (rest trailing) (flags '()))
        (cond
          ((null? sites) (reverse flags))
          ((not (car sites)) (loop (cdr sites) before rest (cons #f flags)))
          (else
            (let ((site (car rest)) (after (if (null? (cdr rest)) #f (car (cdr rest)))))
              (loop (cdr sites)
                    site
                    (cdr rest)
                    (cons (aligned-site? site before after) flags))))))))

  ;;; Output side

  ;; A trailing line comment in the rendered text that this pass could move.
  ;;
  ;;   line          the output line the comment is on
  ;;   gap-start     index just past the last code token on that line
  ;;   comment-start index of the semicolon
  ;;   code-end      column just past that code token
  ;;   width         visible length of the comment, terminator excluded
  ;;
  ;; The two indices bracket exactly the run of spaces to rewrite, and the
  ;; column and width are what the run's arithmetic needs. Nothing here refers
  ;; to the source: the column is a fact about the output.
  (define-record-type <site> (make-site line gap-start comment-start code-end
                              width) site?
    (line site-line)
    (gap-start site-gap-start)
    (comment-start site-comment-start)
    (code-end site-code-end)
    (width site-width))

  (define (spaces-only? text start end)
    (let loop ((i start))
      (or (= i end) (and (char=? (string-ref text i) #\space) (loop (+ i 1))))))

  ;; A site, or #f when this comment cannot be moved: when no code token ends on
  ;; its line, and when what lies between that token and the semicolon is not
  ;; spaces alone.
  ;;
  ;; The second case is a block comment or a datum comment between the code and
  ;; the comment, as in `(a) #|x|# ; c`. Widening that gap would move a token
  ;; rather than whitespace, and which column "one past the code" names is not a
  ;; question this rule answers, so the site declines. Declining is stable: the
  ;; text is left as the printer rendered it, and the next format declines it
  ;; again for the same reason.
  (define (site-for text code tok)
    (and code
         (= (token-end-line code) (token-start-line tok))
         (spaces-only? text (token-end code) (token-start tok))
         (make-site (token-start-line tok)
                    (token-end code)
                    (token-start tok)
                    (token-end-column code)
                    (string-length (strip-final-line-ending (token-text tok))))))

  ;; One entry per line comment in the rendered text, in output order: a site,
  ;; or #f where the comment cannot be moved. An entry appears for every line
  ;; comment either way, because this list's length is what the correspondence
  ;; check compares against the source's.
  (define (output-sites text)
    (let-values (((tokens diagnostics) (tokenize text "<align>")))
      (let ((n (vector-length tokens)))
        (let loop ((i 0) (code #f) (sites '()))
          (if (= i n)
              (reverse sites)
              (let ((tok (vector-ref tokens i)))
                (cond
                  ((code-token? tok) (loop (+ i 1) tok sites))
                  ((line-comment? tok)
                    (loop (+ i 1) code (cons (site-for text code tok) sites)))
                  (else (loop (+ i 1) code sites)))))))))

  ;;; Correspondence, runs and the column

  ;; The sites the source marked and the output can move, in output order.
  ;;
  ;; The pairing is by ordinal, which is exactly what layer 1 asserts one stage
  ;; later. This pass runs first and so cannot lean on that assertion; the
  ;; caller checks the one thing it needs, that the two sequences are the same
  ;; length, and this walk then consumes them together.
  (define (marked-sites flags sites)
    (let loop ((flags flags) (sites sites) (acc '()))
      (cond
        ((null? flags) (reverse acc))
        ((and (car flags) (car sites))
          (loop (cdr flags) (cdr sites) (cons (car sites) acc)))
        (else (loop (cdr flags) (cdr sites) acc)))))

  ;; The marked sites grouped into maximal sequences of consecutive output
  ;; lines. Grouping is over line numbers rather than over positions in the
  ;; list, because a line carrying no marked comment terminates a run whether or
  ;; not it carries a comment at all. This is why a source run that reflows
  ;; apart becomes several runs, and why two source runs that end up adjacent
  ;; become one: the runs are the output's, not the source's.
  (define (runs-of sites)
    (if (null? sites)
        '()
        (let loop ((sites (cdr sites)) (run (list (car sites))) (runs '()))
          (cond
            ((null? sites) (reverse (cons (reverse run) runs)))
            ((= (site-line (car sites)) (+ (site-line (car run)) 1))
              (loop (cdr sites) (cons (car sites) run) runs))
            (else (loop (cdr sites) (list (car sites)) (cons (reverse run) runs)))))))

  ;; One space past the widest code in the run. A run of one therefore takes a
  ;; single space, which is what an unaligned trailing comment already has, so
  ;; the formula needs no special case for it and has none.
  (define (run-column run)
    (let loop ((run run) (col 0))
      (if (null? run) col (loop (cdr run) (max col (+ (site-code-end (car run)) 1))))))

  ;; Whether every line of the run still ends at or before the page width with
  ;; its comment at col. A line of exactly the page width fits, which is the
  ;; cost factory's convention: badness begins past it, not at it.
  (define (run-fits? run col width)
    (or (null? run)
        (and (<= (+ col (site-width (car run))) width)
             (run-fits? (cdr run) col width))))

  ;; The gaps to widen, as (gap-start comment-start spaces) in increasing index
  ;; order. A run that would overflow contributes nothing and keeps the single
  ;; spaces the printer emitted -- pitch does not buy a horizontal signal with
  ;; an overflowing line. The refusal is per run, so one wide line cannot
  ;; un-align an unrelated block.
  (define (gaps runs width)
    (let loop ((runs runs) (acc '()))
      (if (null? runs)
          (reverse acc)
          (let* ((run (car runs)) (col (run-column run)))
            (loop (cdr runs)
                  (if (run-fits? run col width)
                      (let widen ((sites run) (acc acc))
                        (if (null? sites)
                            acc
                            (widen (cdr sites)
                                   (cons (list (site-gap-start (car sites))
                                               (site-comment-start (car sites))
                                               (- col (site-code-end (car sites))))
                                         acc))))
                      acc))))))

  ;;; The rewrite

  ;; Everything outside a gap is copied as a substring of the input, and the only
  ;; characters written into a gap are spaces. So the claim that nothing but the
  ;; whitespace before a semicolon changes is a property of this loop: there is
  ;; no branch here that could emit anything else.
  (define (rewrite text gaps)
    (if (null? gaps)
        text
        (let ((out (open-output-string)))
          (let loop ((i 0) (gaps gaps))
            (if (null? gaps)
                (begin
                  (write-string (substring text i (string-length text)) out)
                  (let ((result (get-output-string out))) (close-port out) result))
                (let ((gap (car gaps)))
                  (write-string (substring text i (car gap)) out)
                  (write-string (make-string (car (cddr gap)) #\space) out)
                  (loop (car (cdr gap)) (cdr gaps))))))))

  ;;; The pass

  ;; Source text, rendered text and page width in; the rendered text with some
  ;; gaps widened out. Nothing else reaches this: not the dialect, not the style
  ;; table, not the CST.
  ;;
  ;; When the source's line comments and the output's differ in number the
  ;; correspondence cannot be established, so nothing is aligned and the
  ;; rendered text is returned as it stands. This does not raise and does not
  ;; guess at a pairing: the discrepancy is a printer defect, layer 1 is the
  ;; check that reports it precisely, and aligning against a guessed pairing
  ;; would turn that defect into a cosmetic anomaly and hide it.
  (define (align-trailing-comments source rendered width)
    (let ((flags (source-alignment-flags source)) (sites (output-sites rendered)))
      (if (= (length flags) (length sites))
          (rewrite rendered (gaps (runs-of (marked-sites flags sites)) width))
          rendered)))))
