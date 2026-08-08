;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The output safety checks that compare two source texts.
;;
;; Every check here takes two *texts*. That is the whole design of these
;; signatures: the call site is check(input, formatted-output), and accepting
;; trees, token vectors or data would let a caller pass the artifact the printer
;; produced. A formatter changes only layout and trivia, so comparing a
;; printer's own output against itself is identical by construction and would
;; pass no matter how badly it misbehaved. Black's --safe does not reuse its
;; in-memory tree either; it reparses the string it printed.
;;
;; Layer 1, token equivalence, is the primary check. It uses the lexer and
;; nothing else. That is deliberate and is what makes the independence of the
;; two layers real: layer 2 runs through the lexer, the parser and the
;; projection, so a failure there has three possible authors, while a layer 1
;; failure has one. It costs no coverage, because a structural defect in the
;; output -- an unbalanced delimiter, a dropped close paren -- changes the token
;; sequence, which the comparison sees without the parser being involved.
;;
;; Layer 2, datum equivalence, is strictly weaker and is kept because it is an
;; independent code path. All of the following PASS it and FAIL layer 1:
;;
;;   a deleted comment, a #; dropped or moved to elide a different form,
;;   [ rewritten to (, 'x expanded to (quote x), #xff rewritten as 255,
;;   "\x41;" as "A", #\nul as #\null
;;
;; Neither layer is wired to a formatter yet, because there is no printer.

#!r6rs

(library (pitch check)
  (export
    ;; layer 1
    token=? check-token-equivalence mismatch? mismatch-index mismatch-input-token
    mismatch-output-token
    ;; layer 2
    datum=? check-datum-equivalence
    ;; both
    check-output)
  (import
    (rnrs base (6))
    (rnrs lists (6))
    (rnrs records syntactic (6))
    (pitch diagnostic)
    (pitch parse)
    (pitch datum)
    (only (pitch lines) strip-final-line-ending)
    (only (pitch reader) token-kind token-text))

  ;;; Layer 1: token equivalence

  ;; A line comment's text includes the line ending that terminates it, so "; c"
  ;; and "; c\n" are different texts differing only in whitespace. Dropping that
  ;; terminator is not a normalization -- no comment content is changed or
  ;; ignored, and two comments whose content differs still compare unequal. It
  ;; stops a tokenization boundary from turning a whitespace change into a text
  ;; change, and it lets a printer end a file with a newline even when the file
  ;; ends in a comment. Line endings as such are layer 0's business, where they
  ;; are compared byte for byte.
  ;;
  ;; Only comment and shebang tokens can end with a line ending; #| |# ends with
  ;; |#, #; ends with the elided datum, and #!r6rs ends with the directive name.
  ;; The endings recognized are the ones the reader's grammar counts, with CR+LF
  ;; and CR+NEL counting as one -- (pitch lines) owns that set, shared with the
  ;; layout algebra and the printer.

  ;; Kind and text, never position -- formatting changes line and column by
  ;; definition. Kind is not redundant with text: the reader's mode changes
  ;; mid-file on #!r6rs and #!r7rs and its fold-case state on #!fold-case, so
  ;; identical text can lex differently depending on what preceded it. The parsed
  ;; value is not compared; it is derived from the text, and comparing it would
  ;; import layer 2's weakness, since #xff and 255 share a value.
  (define (token=? a b)
    (and (eq? (token-kind a) (token-kind b))
         (string=? (strip-final-line-ending (token-text a))
                   (strip-final-line-ending (token-text b)))))

  ;; Every non-whitespace token in source order: code tokens and comments in one
  ;; interleaved sequence, not two subsequences. Interleaving is what catches a
  ;; comment migrating across a code token, which changes which code the comment
  ;; documents and is a meaning change rather than a layout one. The eof token
  ;; survives filtering and always agrees; leaving it in keeps the sequence
  ;; uniform.
  (define (significant-tokens text filename)
    (let-values (((tokens diagnostics) (tokenize text filename)))
      (let loop ((i (- (vector-length tokens) 1)) (acc '()))
        (if (negative? i)
            (values acc diagnostics)
            (let ((tok (vector-ref tokens i)))
              (loop (- i 1)
                    (if (eq? (token-kind tok) 'whitespace) acc (cons tok acc))))))))

  ;; Where the sequences first diverge.
  ;;
  ;; Either token is #f when that side ran out of tokens. That branch is
  ;; defensive rather than reachable today: both sequences end with an eof token,
  ;; and eof matches only eof, so a shorter sequence produces a mismatch of eof
  ;; against a real token before either list empties. A dropped comment therefore
  ;; reports a comment on one side and the following code token on the other, not
  ;; an absent side.
  (define-record-type mismatch
    (fields index input-token output-token)
    (sealed #t)
    (opaque #f)
    (nongenerative mismatch-v0-6b1f4d02-8e73-4c19-a5d8-31f0c7b9e264))

  ;; Returns three values: whether the sequences are equivalent, the first
  ;; mismatch or #f, and the diagnostics found in either text.
  ;;
  ;; Reporting where it failed is worth the extra value here in a way it is not
  ;; for layer 2. This sequence is flat, so the index and the two tokens are
  ;; free, whereas locating a difference between two data means walking a graph
  ;; that may be cyclic. Layer 1 is also the check that will actually fire while
  ;; a printer is being written.
  (define (check-token-equivalence input-text output-text)
    (let-values (((input-tokens input-diagnostics)
                   (significant-tokens input-text "<input>"))
                  ((output-tokens output-diagnostics)
                    (significant-tokens output-text "<output>")))
      (let ((diagnostics (append input-diagnostics output-diagnostics)))
        (if (not (null? diagnostics))
            (values #f #f diagnostics)
            (let loop ((a input-tokens) (b output-tokens) (i 0))
              (cond
                ((and (null? a) (null? b)) (values #t #f '()))
                ((null? a) (values #f (make-mismatch i #f (car b)) '()))
                ((null? b) (values #f (make-mismatch i (car a) #f) '()))
                ((token=? (car a) (car b)) (loop (cdr a) (cdr b) (+ i 1)))
                (else (values #f (make-mismatch i (car a) (car b)) '()))))))))

  ;;; Layer 2: datum equivalence

  ;; Named so tests and callers have one operation to reach for, and so a future
  ;; divergence has somewhere to live. Today it is equal?, which R6RS requires to
  ;; terminate on circular arguments -- which is why the projection produces host
  ;; data rather than a representation whose comparator we would have to write.
  (define (datum=? a b) (equal? a b))

  ;; The two layers each report in source order; merging them keeps that, so a
  ;; reader of the list is not asked to interleave two orderings mentally.
  (define (source->data text filename)
    (let-values (((document parse-diagnostics) (parse-source text filename)))
      (let-values (((data datum-diagnostics) (cst->datum document)))
        (values data (sort-diagnostics (append parse-diagnostics datum-diagnostics))))))

  ;; Returns two values: whether the two texts are datum-equivalent, and the
  ;; diagnostics found in either. A defect on either side is a failure, not a
  ;; comparison: there is no useful sense in which two unusable inputs agree.
  (define (check-datum-equivalence input-text output-text)
    (let-values (((input-data input-diagnostics) (source->data input-text "<input>"))
                  ((output-data output-diagnostics)
                    (source->data output-text "<output>")))
      (let ((diagnostics (append input-diagnostics output-diagnostics)))
        (if (null? diagnostics)
            (values (datum=? input-data output-data) '())
            (values #f diagnostics)))))

  ;;; Both layers

  ;; Returns three values: whether the pair passed, which layer failed, and a
  ;; detail whose shape follows the failure -- the diagnostics when either text
  ;; is unusable, the mismatch when token equivalence found one, #f otherwise.
  ;;
  ;; Token equivalence runs first because it is strictly stronger and reports
  ;; where it failed, so when both would fail the useful message is its.
  ;;
  ;; This covers only the layers that compare two texts. Round-trip compares a
  ;; tree against the input it was parsed from rather than comparing two texts,
  ;; so it does not share this signature; idempotence requires running the
  ;; formatter more than once. Both join the pipeline with the formatter, and the
  ;; printer's change is expected to revise this.
  (define (check-output input-text output-text)
    (let-values (((token-ok? mismatch token-diagnostics)
                   (check-token-equivalence input-text output-text))
                  ((datum-ok? datum-diagnostics)
                    (check-datum-equivalence input-text output-text)))
      (cond
        ;; Layer 2 sees the lexical diagnostics layer 1 sees, plus the parse and
        ;; projection ones, so its list is the more complete of the two.
        ((not (null? datum-diagnostics)) (values #f #f datum-diagnostics))
        ((not (null? token-diagnostics)) (values #f #f token-diagnostics))
        ((not token-ok?) (values #f 'token-equivalence mismatch))
        ((not datum-ok?) (values #f 'datum-equivalence #f))
        (else (values #t #f #f))))))
