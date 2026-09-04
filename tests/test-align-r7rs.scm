;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for trailing-comment column alignment.
;;
;; Two halves, and they test different things through different doors.
;;
;; RECOGNITION is tested against the source alone, through
;; source-alignment-flags. Everything a source can say about alignment is said
;; by which of its line comments are trailing and which of those share a column
;; with an adjacent line's, so these tests need no layout, no width and no
;; output.
;;
;; THE FIXED POINT is tested through the whole pipeline, because that is the
;; only place it means anything. The important test in this file is not that a
;; run aligns -- it is that formatting the aligned output again returns it
;; unchanged. A padding rule ("two or more spaces means the author aligned
;; this") passes every alignment test here and fails the fixed-point ones,
;; because the widest line of an aligned run carries a single space and a
;; padding rule cannot see it. That is the whole reason recognition is by shared
;; column, and `run-recognized-whole` below is the test that says so.
(import
  (scheme base)
  (scheme file)
  (pitch align)
  (pitch format)
  (tests config)
  (tests runner))

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

;;; Helpers

(define (config width) (make-test-config width 'r7rs))

(define (status src width)
  (let-values (((text result) (format-source src "test" (config width))))
    (format-result-status result)))

(define (text-of src width)
  (let-values (((text result) (format-source src "test" (config width))))
    text))

;; The output of formatting the output. Every alignment claim in this file is
;; paired with one of these, and a claim without one is worth little: alignment
;; that is not a fixed point is a formatter that never settles.
(define (twice src width)
  (let ((once (text-of src width)))
    (and once (text-of once width))))

(define (settles? src width)
  (let ((once (text-of src width)))
    (and once (equal? once (text-of once width)))))

;; Every run of spaces sitting between a non-space and a semicolon, reduced to
;; one space. Applied to a text the pass produced, this undoes exactly what the
;; pass is allowed to do, so comparing the result against the rendered text the
;; pass was handed asserts that no other character moved. Indentation is left
;; alone: a run at the start of a line is not a gap.
(define (collapse-gaps text)
  (let ((n (string-length text)) (out (open-output-string)))
    (let loop ((i 0) (prev #\newline))
      (if (= i n)
          (let ((result (get-output-string out))) (close-port out) result)
          (let ((c (string-ref text i)))
            (if (char=? c #\space)
                (let count ((j i))
                  (if (and (< j n) (char=? (string-ref text j) #\space))
                      (count (+ j 1))
                      (begin
                        (if (and (not (char=? prev #\newline))
                                 (< j n)
                                 (char=? (string-ref text j) #\;))
                            (write-char #\space out)
                            (write-string (make-string (- j i) #\space) out))
                        (loop j #\space))))
                (begin (write-char c out) (loop (+ i 1) c))))))))

(define (file-text path)
  (let ((port (open-input-file path)))
    (let loop ((characters '()))
      (let ((character (read-char port)))
        (if (eof-object? character)
            (begin (close-port port) (list->string (reverse characters)))
            (loop (cons character characters)))))))

(define (contains? haystack needle)
  (let ((hn (string-length haystack)) (nn (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i nn) hn) #f)
            ((string=? (substring haystack i (+ i nn)) needle) #t)
            (else (loop (+ i 1)))))))

(define lf (string (integer->char #x0a)))
(define cr (string (integer->char #x0d)))
(define nel (string (integer->char #x85)))
(define ls (string (integer->char #x2028)))
(define ps (string (integer->char #x2029)))

;;; 1. Recognition, tested against the source alone

(test-begin "recognition-shared-column")

;; Three consecutive lines at one column: a table with three rows.
(test-equal '(#t #t #t)
            (source-alignment-flags
              (string-append
                "(aa) ; one" lf
                "(bb) ; two" lf
                "(cc) ; three" lf)))

;; A lone trailing comment has no partner and is not aligned. Nothing in the
;; source distinguishes it from a remark, because nothing in the source does.
(test-equal '(#f) (source-alignment-flags (string-append "(aa) ; one" lf)))

;; Padding is not alignment. Both of these comments are preceded by several
;; spaces and neither is aligned, because the columns differ. A rule that
;; counted spaces would call both of them aligned.
(test-equal '(#f #f)
            (source-alignment-flags
              (string-append
                "(aa)   ; one" lf
                "(bbbbbb)   ; two" lf)))

;; The same column but not an adjacent line. Two runs of one, not a run of two.
(test-equal '(#f #f)
            (source-alignment-flags
              (string-append
                "(aa) ; one" lf
                "(bb) 2" lf
                "(cc) ; three" lf)))

(test-end)

(test-begin "recognition-own-line")

;; An own-line comment has no code to align against and is never aligned,
;; whatever column it begins at -- here at column 0 and at the same column as
;; the trailing comments around it.
(test-equal '(#f #f) (source-alignment-flags (string-append ";; note" lf ";; more" lf)))

(test-equal '(#f #f)
            (source-alignment-flags
              (string-append
                "(aa) 1" lf
                "     ;; note" lf
                "     ;; more" lf)))

;; An own-line comment between two aligned lines does not join the run, and the
;; two trailing comments are no longer on adjacent lines, so the run is gone.
;; The own-line comment here begins at exactly the column the run shared.
(test-equal '(#f #f #f)
            (source-alignment-flags
              (string-append
                "(aaaaaa) ; one" lf
                "         ;; note" lf
                "(bbbbbb) ; two" lf)))

;; A comment preceded on its line by a block comment rather than by code is
;; still an own-line comment for this purpose: `#|x|#` is not code.
(test-equal '(#f #f)
            (source-alignment-flags
              (string-append
                "#|x|# ; one" lf
                "#|y|# ; two" lf)))

(test-end)

(test-begin "recognition-not-line-comments")

;; A block comment is inline-capable -- code may follow it on its line -- so
;; "the comment ends the line" is not a property it has, and it is never
;; aligned. Two at one column on adjacent lines yield no candidates at all.
(test-equal '() (source-alignment-flags (string-append "(aa) #|x|#" lf "(bb) #|y|#" lf)))

;; A datum comment, likewise.
(test-equal '() (source-alignment-flags (string-append "(aa) #;(x)" lf "(bb) #;(y)" lf)))

;; A directive, likewise.
(test-equal '()
            (source-alignment-flags
              (string-append "(aa) #!fold-case" lf "(bb) #!fold-case" lf)))

;; `#! ... !#` lexes as a comment token in the permissive mode the reader parses
;; with, and it is the one case where testing the token's kind is not enough. It
;; is delimited rather than terminated by a line ending, and is not aligned.
(test-equal '()
            (source-alignment-flags
              (string-append "(aa) #! x !#" lf "(bb) #! y !#" lf)))

;; Neither can one of them be the partner that aligns a real line comment: this
;; comment is alone on its own terms, and the block comment below it at the same
;; column does not change that.
(test-equal '(#f)
            (source-alignment-flags
              (string-append "(aa) ; one" lf "(bb) #|y|#" lf)))

(test-end)

(test-begin "recognition-line-endings")

;; All seven endings the reader's grammar counts. CR LF and CR NEL are one
;; ending, not two, which is where a character scan written for this would
;; count twice as many lines and find no adjacent pairs at all.
(define (run-separated-by ending)
  (string-append
    "(aa) ; one" ending
    "(bb) ; two" ending
    "(cc) ; three" ending))

(test-equal '(#t #t #t) (source-alignment-flags (run-separated-by lf)))
(test-equal '(#t #t #t) (source-alignment-flags (run-separated-by cr)))
(test-equal '(#t #t #t) (source-alignment-flags (run-separated-by (string-append cr lf))))
(test-equal '(#t #t #t) (source-alignment-flags (run-separated-by (string-append cr nel))))
(test-equal '(#t #t #t) (source-alignment-flags (run-separated-by nel)))
(test-equal '(#t #t #t) (source-alignment-flags (run-separated-by ls)))
(test-equal '(#t #t #t) (source-alignment-flags (run-separated-by ps)))

;; CRLF again, mixed with a line that breaks the run, so that a miscount would
;; show up as the wrong flag rather than as no flags.
(test-equal '(#t #t #f)
            (source-alignment-flags
              (string-append
                "(aa) ; one" cr lf
                "(bb) ; two" cr lf
                "(cccccc) ; three" cr lf)))

(test-end)

(test-begin "recognition-file-edges")

;; A run that begins on the first line of the file: there is no line before it,
;; which is a #f neighbor rather than a missing one.
(test-equal '(#t #t)
            (source-alignment-flags (string-append "(aa) ; one" lf "(bb) ; two" lf)))

;; A run that ends on the last line, and a last line with no terminator at all
;; -- the comment token then carries no line ending, which is the case a scan
;; over terminators would drop.
(test-equal '(#t #t) (source-alignment-flags (string-append "(aa) ; one" lf "(bb) ; two")))

(test-equal '(#f)
            (source-alignment-flags (string-append "(aa) 1" lf "(bbbbbb) ; last")))

;; A single line, no terminator, one trailing comment: no neighbor on either
;; side.
(test-equal '(#f) (source-alignment-flags "(aa) ; only"))

(test-end)

;;; 2. The fixed point

;; Issue #14's repro, at the column its author chose.
(define issue-14
  (string-append
    "(define sfy-fold-limit 1073741823)              ; 2^30 - 1" lf
    "(define sfy-other-limit 255)                    ; a byte" lf
    "(define sfy-third 7)                            ; three bits" lf))

;; The same three lines at the column the code actually implies: one past the
;; end of `(define sfy-fold-limit 1073741823)`, which is 34 characters wide. The
;; widest line therefore carries exactly one space.
(define issue-14-aligned
  (string-append
    "(define sfy-fold-limit 1073741823) ; 2^30 - 1" lf
    "(define sfy-other-limit 255)       ; a byte" lf
    "(define sfy-third 7)               ; three bits" lf))

(test-begin "issue-14")

(test-equal 'ok (status issue-14 88))
(test-equal issue-14-aligned (text-of issue-14 88))
(test-equal issue-14-aligned (twice issue-14 88))

(test-end)

(test-begin "run-recognized-whole")

;; THE TEST THAT JUSTIFIES RECOGNITION BY SHARED COLUMN. Its subject is the
;; output above, in which the widest line carries a single space and the other
;; two carry six and fourteen. A padding rule would recognize two of these three
;; and split the run; a shared column recognizes all three.
(test-equal '(#t #t #t) (source-alignment-flags issue-14-aligned))

;; And so the aligned output is a fixed point rather than something that
;; oscillates: formatting it returns it, byte for byte.
(test-equal issue-14-aligned (text-of issue-14-aligned 88))
(test-assert (settles? issue-14-aligned 88))

(test-end)

(test-begin "run-reflowed-apart")

;; A source run of three whose middle form is too wide for the page. Its comment
;; stays on the form's last line, which is now the fourth output line, so the
;; three comments land on output lines 1, 4 and 5. Runs are formed over output
;; lines, so this is a run of one and a run of two, aligned independently.
(define reflowed-apart
  (string-append
    "(define x 1)                                                   ; one" lf
    "(define (f a b) (some-long-call a b) (another-long-call a b))  ; two" lf
    "(define y 2)                                                   ; three" lf))

(define reflowed-apart-aligned
  (string-append
    "(define x 1) ; one" lf
    "(define (f a b)" lf
    "  (some-long-call a b)" lf
    "  (another-long-call a b)) ; two" lf
    "(define y 2)               ; three" lf))

(test-equal '(#t #t #t) (source-alignment-flags reflowed-apart))
(test-equal 'ok (status reflowed-apart 40))
(test-equal reflowed-apart-aligned (text-of reflowed-apart 40))
(test-equal reflowed-apart-aligned (twice reflowed-apart 40))

(test-end)

(test-begin "runs-reflowed-together")

;; Two source runs, at columns 30 and 26, recognized separately. In the output
;; their four comments are on consecutive lines, so they are one run and take
;; one column -- 26, one past `(define cc-longer-name 3)`. The source's
;; two-run structure does not survive, and should not: the column is a fact
;; about the output.
(define two-source-runs
  (string-append
    "(define aa 1)                 ; one" lf
    "(define bb 2)                 ; two" lf
    "(define cc-longer-name 3) ; three" lf
    "(define dd 4)             ; four" lf))

(define two-source-runs-aligned
  (string-append
    "(define aa 1)             ; one" lf
    "(define bb 2)             ; two" lf
    "(define cc-longer-name 3) ; three" lf
    "(define dd 4)             ; four" lf))

(test-equal '(#t #t #t #t) (source-alignment-flags two-source-runs))
(test-equal 'ok (status two-source-runs 88))
(test-equal two-source-runs-aligned (text-of two-source-runs 88))
(test-equal two-source-runs-aligned (twice two-source-runs 88))

(test-end)

(test-begin "declined-for-width")

;; Both comments are aligned in the source, at column 29. Aligning them in the
;; output would put the first line's comment at column 29 and end it at 45,
;; past a page width of 40 -- so the run keeps its single spaces. Pitch does not
;; buy a horizontal signal with an overflowing line.
(define declined
  (string-append
    "(define aa 1)                ; a comment here" lf
    "(define bb-much-longer-nm 2) ; b" lf))

(define declined-output
  (string-append
    "(define aa 1) ; a comment here" lf
    "(define bb-much-longer-nm 2) ; b" lf))

(test-equal '(#t #t) (source-alignment-flags declined))
(test-equal 'ok (status declined 40))
(test-equal declined-output (text-of declined 40))

;; A declined run is stable for the same reason an aligned one is: single spaces
;; at differing columns are recognized as unaligned, so the second run leaves
;; them alone.
(test-equal '(#f #f) (source-alignment-flags declined-output))
(test-equal declined-output (twice declined 40))

;; The same source at a width that accommodates the aligned run: the run is
;; aligned, so the refusal above is about the width and not about the run.
(test-equal
  (string-append
    "(define aa 1)                ; a comment here" lf
    "(define bb-much-longer-nm 2) ; b" lf)
  (text-of declined 60))

(test-end)

(test-begin "mixed-file")

;; Alignable and declined runs, own-line comments, blank lines and a form that
;; reflows, in one file, at three widths. The claim is only idempotence: this is
;; the case where the pieces interact, and interaction is where a rule that
;; holds in isolation stops holding.
(define mixed
  (string-append
    ";;; A header comment on its own line." lf
    lf
    "(define aa 1)                 ; the first run" lf
    "(define bb-wider-name 2)      ; still the first run" lf
    lf
    ";; An own-line comment between the runs." lf
    "(define cc 3)   ; a run of one" lf
    lf
    "(define (g a b)                 ; a trailing comment on a form head" lf
    "  (first-long-call a b)         ; inside the body" lf
    "  (second-long-call a b))       ; and the last line" lf
    lf
    "(define dd 4)                                        ; wants a far column" lf
    "(define ee-considerably-longer-name-here 5)          ; and cannot have it" lf))

(test-equal 'ok (status mixed 40))
(test-equal 'ok (status mixed 60))
(test-equal 'ok (status mixed 88))
(test-assert (settles? mixed 40))
(test-assert (settles? mixed 60))
(test-assert (settles? mixed 88))

(test-end)

;;; 3. The pass, at its own interface

;; What the printer renders for the three fixtures above, before alignment: one
;; space before every trailing comment. These are the second argument the pass
;; takes, and the texts the aligned output must reduce back to.
(define issue-14-rendered
  (string-append
    "(define sfy-fold-limit 1073741823) ; 2^30 - 1" lf
    "(define sfy-other-limit 255) ; a byte" lf
    "(define sfy-third 7) ; three bits" lf))

(define reflowed-apart-rendered
  (string-append
    "(define x 1) ; one" lf
    "(define (f a b)" lf
    "  (some-long-call a b)" lf
    "  (another-long-call a b)) ; two" lf
    "(define y 2) ; three" lf))

(define two-source-runs-rendered
  (string-append
    "(define aa 1) ; one" lf
    "(define bb 2) ; two" lf
    "(define cc-longer-name 3) ; three" lf
    "(define dd 4) ; four" lf))

(test-begin "correspondence-by-ordinal")

;; The flags are matched to the output's comments by ordinal, so the pass first
;; establishes that there are as many of one as of the other.
(test-equal issue-14-aligned (align-trailing-comments issue-14 issue-14-rendered 88))

;; When there are not, nothing is aligned and the rendered text is returned as
;; it stands -- not raised on, and not aligned against a guessed pairing. A
;; count that disagrees is a printer defect, and layer 1, one stage later,
;; reports it precisely.
(test-equal (string-append "(aa) ; one" lf)
            (align-trailing-comments
              (string-append "(aa) ; one" lf "(bb) ; two" lf)
              (string-append "(aa) ; one" lf)
              88))

(test-equal (string-append "(aa) ; one" lf "(bb) ; two" lf)
            (align-trailing-comments
              (string-append "(aa) ; one" lf)
              (string-append "(aa) ; one" lf "(bb) ; two" lf)
              88))

;; Alignment depends on the source text, the rendered text and the width, and
;; on nothing else -- so a width that cannot hold the run yields the rendered
;; text unchanged from the same two texts.
(test-equal issue-14-rendered (align-trailing-comments issue-14 issue-14-rendered 40))

(test-end)

(test-begin "only-the-gap-changes")

;; Reducing every gap of the aligned text to one space returns the rendered text
;; the pass was given, character for character. Anything the pass had touched
;; besides the spaces before a semicolon would survive that reduction and show
;; up here.
(test-equal issue-14-rendered
            (collapse-gaps (align-trailing-comments issue-14 issue-14-rendered 88)))

(test-equal reflowed-apart-rendered
            (collapse-gaps
              (align-trailing-comments reflowed-apart reflowed-apart-rendered 40)))

(test-equal two-source-runs-rendered
            (collapse-gaps
              (align-trailing-comments two-source-runs two-source-runs-rendered 88)))

;; And the helper is not vacuous: it does reduce a gap when there is one.
(test-equal issue-14-rendered (collapse-gaps issue-14-aligned))

(test-end)

(test-begin "a-gap-that-is-not-spaces-alone")

;; `(a) #|x|# ; c` -- a block comment between the code and the comment. Both
;; comments here are trailing and share a column, so both are recognized as
;; aligned, but widening this gap would move a token rather than whitespace, and
;; which column "one past the code" names is not a question this rule answers.
;; So the site declines, and declining is stable.
(define gap-not-spaces
  (string-append
    "(aa)      #|x|# ; one" lf
    "(bbbbbb)  #|x|# ; two" lf))

(define gap-not-spaces-output
  (string-append
    "(aa) #|x|# ; one" lf
    "(bbbbbb) #|x|# ; two" lf))

(test-equal '(#t #t) (source-alignment-flags gap-not-spaces))
(test-equal 'ok (status gap-not-spaces 88))
(test-equal gap-not-spaces-output (text-of gap-not-spaces 88))
(test-equal gap-not-spaces-output (twice gap-not-spaces 88))

(test-end)

(test-begin "the-alignment-library-is-layered-below-the-engine")

;; The column depends on sibling lines, which no document in the algebra can
;; see, so this pass sits outside the engine and must stay there. What it is
;; allowed to import is the check, in the way the style library's is.
(define align-source (file-text "src/pitch/align.sld"))

(for-each
  (lambda (forbidden) (test-assert (not (contains? align-source forbidden))))
  '("(pitch doc)" "(pitch cost)" "(pitch layout)" "(pitch print)" "(pitch style)"))

(test-end)

(test-exit)
