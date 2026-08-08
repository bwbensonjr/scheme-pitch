;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The pipeline: source text in, formatted text out, or a reason why not.
;;
;;   tokenize -> parse -> cst->document -> layout -> check
;;
;; This is the first thing that runs the safety checks against real output, and
;; the shape of the interface is what keeps that honest. check-output takes two
;; source *texts*, and the text it is given here is the string the layout engine
;; returned. There is no in-memory tree on that path, and no way to put one
;; there: check-output does not accept a tree. docs/DESIGN.md §1 calls comparing
;; a tree against itself the vacuousness trap, and the reason it is avoidable
;; here is structural rather than a matter of remembering.
;;
;; REFUSAL IS THE COMMON CASE FOR ANYTHING DOUBTFUL. An unclean parse is not
;; formatted, a source whose multi-line tokens carry a line ending the engine
;; cannot reproduce is not formatted, and output that fails a check is not
;; returned at all. Tolerant parsing is required of a formatter run from an
;; editor on a half-typed buffer; tolerant *output* is not, and returning text
;; pitch could not verify -- under any status -- invites a caller to write it to
;; a file, which is the one failure the whole check apparatus exists to prevent.
;;
;; Taint is not a failure. A document whose layouts all pass the computation
;; width renders normally and reports that the search stopped proving
;; minimality. The text is complete, valid, and checked like any other; what was
;; withdrawn is the claim that nothing cheaper exists.

#!r6rs

(library (pitch format)
  (export
    format-source
    format-result? format-result-status format-result-detail
    format-result-tainted?
    default-page-width)
  (import
    (rnrs base (6))
    (rnrs control (6))
    (rnrs lists (6))
    (rnrs records syntactic (6))
    (pitch parse)
    (pitch print)
    (pitch check)
    (only (pitch cst) cst-tokens)
    (only (pitch lines) line-ending-char? strip-final-line-ending)
    (only (pitch reader) token-text)
    (only (pitch cost) default-cost-factory)
    (only (pitch layout) layout layout-result-tainted?))

;; README.md's default, and black's.
(define default-page-width 88)

;; status   one of ok, unclean-parse, unsupported-line-ending, check-failed
;; detail   what belongs to that status: a diagnostics list, the offending
;;          token, the failing layer, or #f
;; tainted? whether the layout engine proved its result minimal
(define-record-type format-result
  (fields status detail tainted?)
  (sealed #t) (opaque #f)
  (nongenerative format-result-v0-83c1a5de-7b2f-4e60-a1cc-9d40e6f7b512))

;;; Stage 2: line endings the engine cannot reproduce
;;
;; The resolver renders every break as a linefeed. Between tokens that is
;; harmless -- those endings live in whitespace, which the formatter re-derives,
;; and re-deriving whitespace is the one change pitch is allowed to make. Inside
;; a token it is not: a CRLF within a multi-line string or a #| |# block is part
;; of a text that token equivalence compares, and emitting it as a linefeed
;; would change that text.
;;
;; So such a source is refused up front. Normalizing it is prohibited -- the
;; declared-normalizations list is empty and every entry needs a proposal
;; arguing for it -- and letting layer 1 catch it after the fact would report a
;; printer bug for what is really a known unsupported input. This can be lifted
;; by teaching (pitch doc) which ending to render, which is a change to the
;; algebra and wants its own proposal.
;;
;; The trailing ending of a line comment is not interior and is not screened:
;; the printer splits it off and emits an explicit break in its place.
(define (foreign-interior-ending? text)
  (let* ((body (strip-final-line-ending text))
         (n (string-length body)))
    (let loop ((i 0))
      (cond ((= i n) #f)
            ((char=? (string-ref body i) #\linefeed) (loop (+ i 1)))
            ((line-ending-char? (string-ref body i)) #t)
            (else (loop (+ i 1)))))))

(define (find-foreign-token tokens)
  (cond ((null? tokens) #f)
        ((foreign-interior-ending? (token-text (car tokens))) (car tokens))
        (else (find-foreign-token (cdr tokens)))))

;;; The pipeline

(define format-source
  (case-lambda
    ((source) (format-source source "<string>" default-page-width))
    ((source filename) (format-source source filename default-page-width))
    ((source filename width)
     (let-values (((tree diagnostics) (parse-source source filename)))
       (cond
         ;; Stage 1. A tree is clean exactly when its diagnostics list is empty,
         ;; and an unclean one is refused rather than repaired.
         ((not (null? diagnostics))
          (values #f (make-format-result 'unclean-parse diagnostics #f)))
         (else
          (let ((foreign (find-foreign-token (cst-tokens tree))))
            (cond
              ;; Stage 2.
              (foreign
               (values #f (make-format-result 'unsupported-line-ending
                                              foreign #f)))
              (else
               ;; Stage 3. A document with no layout at all raises out of
               ;; (pitch layout), and is deliberately not caught: that is a bug
               ;; in the translation, not a property of the input, and turning
               ;; it into a status would hide it.
               (let-values (((output result)
                             (layout (cst->document tree)
                                     (default-cost-factory width))))
                 (let ((tainted? (layout-result-tainted? result)))
                   ;; Stage 4. Two texts: the one that came in, and the one just
                   ;; produced. Never the tree either was built from.
                   (let-values (((ok? layer detail)
                                 (check-output source output)))
                     (if ok?
                         (values output (make-format-result 'ok #f tainted?))
                         (values #f
                                 (make-format-result 'check-failed
                                                     (if layer
                                                         (cons layer detail)
                                                         detail)
                                                     tainted?))))))))))))))))
