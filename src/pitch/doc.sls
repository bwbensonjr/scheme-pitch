;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The document algebra: the language (pitch layout) resolves.
;;
;; A document denotes a *set* of candidate layouts, not one rendering. The
;; resolver picks the cheapest member under a cost factory. Documents are
;; immutable values carrying no resolution state, so the same document may be
;; shared at many positions, cached by a caller, and resolved any number of
;; times under any number of cost factories.
;;
;; Nothing here knows anything about Scheme. There are no tokens, no comments,
;; no brackets and no dialects; translating a CST into a document is the
;; printer's job, and it is where comment placement -- the actually hard problem
;; -- lives. Keeping that out of this library is what lets the layout rules be
;; data rather than code.
;;
;; FULLNESS. Two boolean flags travel with a document through resolution,
;; describing its two boundaries: does the position immediately before it, and
;; immediately after it, have to be at end of line? They exist to support `full`.
;; The reference implementation carries them without ever saying what they mean,
;; so, for the record:
;;
;;   - text of positive length fails at either constrained boundary, since it
;;     puts characters there.
;;   - empty text fails at exactly one constrained boundary and succeeds at both
;;     or neither: its two boundaries are the same point, so one constraint
;;     without the other is a contradiction.
;;   - a newline satisfies a constraint before it -- that is where it breaks --
;;     but never one after it, since it lands on a fresh line's indentation.
;;   - `full` fails unless the boundary after it is constrained. That is the
;;     whole definition of `full`.
;;
;; These are computed at construction, stored as a four-bit mask, and let the
;; resolver reject a hopeless branch without descending into it.
;;
;; NAME COLLISION. `newline` here shadows the one in (rnrs io simple (6)).
;; (rnrs base (6)) does not export `newline`, so a library that only builds
;; documents has no conflict; only a file that also does console I/O does, and
;; R6RS reports that at import time with an obvious fix. Renaming the
;; constructor to dodge a collision the module system already reports precisely
;; would trade a clear error for a name that no longer matches the paper.

#!r6rs

(library (pitch doc)
(export
  ;; core constructors
  text newline concat alternatives nest align reset full cost fail

  ;; derived
  empty-doc nl break hard-nl alt flatten group verbatim u-append u-concat us-append
  us-concat v-append v-concat a-append a-concat as-append as-concat space lparen rparen
  lbracket rbracket

  ;; inspection, for (pitch layout)
  doc? doc-nl-cnt fullness-index doc-fails-statically? doc-text? doc-text-len
  doc-text-push doc-newline? doc-newline-s doc-concat? doc-concat-a doc-concat-b
  doc-alt? doc-alt-a doc-alt-b doc-nest? doc-nest-n doc-nest-d doc-align? doc-align-d
  doc-reset? doc-reset-d doc-full? doc-full-d doc-cost? doc-cost-n doc-cost-d doc-fail?)
(import
  (rnrs base (6))
  (rnrs control (6))
  (rnrs lists (6))
  (rnrs hashtables (6))
  (rnrs records syntactic (6))
  (rnrs arithmetic bitwise (6))
  (only (pitch lines) line-ending-index line-ending-pieces))

;;; Representation

;; Every node carries two facts computed at construction:
;;
;;   fail-mask  a four-bit mask of the fullness combinations under which this
;;              document statically has no layout. The bit index is
;;              (beg-full? -> 1) + (end-full? -> 2).
;;   nl-cnt     an overapproximation of how many line breaks the document can
;;              contain. Used only to choose between two tainted candidates,
;;              where more breaks is the better guess.
(define-record-type doc
  (fields fail-mask nl-cnt)
  (opaque #f)
  (nongenerative doc-v0-a5642476-4897-41fa-a085-2cc64df2bf8c))

(define fail-none 0)
(define fail-all 15)
;; text of positive length: nn no, yn yes, ny yes, yy yes.
(define fail-text-nonempty (+ 2 4 8))
;; empty text: fails at exactly one constrained boundary, not at both.
(define fail-text-empty (+ 2 4))
;; newline: never satisfies a constraint after it.
(define fail-newline (+ 4 8))
;; full: fails unless the boundary after it is constrained.
(define fail-full (+ 1 2))

(define (fullness-index beg-full? end-full?) (+ (if beg-full? 1 0) (if end-full? 2 0)))

(define (doc-fails-statically? d index) (bitwise-bit-set? (doc-fail-mask d) index))

;; The text payload is a tree of strings rather than one string: merging two
;; adjacent texts is then O(1) instead of an append, so folding a long run of
;; texts through `concat` stays linear rather than quadratic in total length.
;; Only the total length is ever needed before rendering.
(define-record-type doc-text
  (parent doc)
  (fields s len)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-text-v0-d7ee254b-69b2-4f07-b53c-8e358ff7c0dd))

;; Push a text's pieces onto a reversed accumulator of strings.
(define (doc-text-push d acc)
  (let walk ((s (doc-text-s d)) (acc acc))
    (if (string? s) (cons s acc) (walk (cdr s) (walk (car s) acc)))))

;; s is the string this break becomes when flattened, or #f if it cannot be
;; flattened at all.
(define-record-type doc-newline
  (parent doc)
  (fields s)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-newline-v0-c132fa0e-df48-4ab6-9221-b3fb5f2e844e))

(define-record-type doc-concat
  (parent doc)
  (fields a b)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-concat-v0-e683ef33-64c9-4957-ad4d-4b6e47ec1555))

(define-record-type doc-alt
  (parent doc)
  (fields a b)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-alt-v0-77c572d4-abb4-48f7-a58c-01b370f40d08))

(define-record-type doc-nest
  (parent doc)
  (fields n d)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-nest-v0-3619886e-d008-48f1-989b-04d43d9aaa99))

(define-record-type doc-align
  (parent doc)
  (fields d)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-align-v0-1ce81ed7-2a87-4a6f-829b-4bbd2eb36531))

(define-record-type doc-reset
  (parent doc)
  (fields d)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-reset-v0-8b2a31c9-8a04-4236-8efe-960032a1483e))

(define-record-type doc-full
  (parent doc)
  (fields d)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-full-v0-883592ee-8149-4eb5-8165-b4243c483bc9))

(define-record-type doc-cost
  (parent doc)
  (fields n d)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-cost-v0-8ab8a31c-feff-4079-96ae-822d61a63421))

(define-record-type doc-fail
  (parent doc)
  (fields)
  (sealed #t)
  (opaque #f)
  (nongenerative doc-fail-v0-322b64eb-fbae-4b70-82e9-50e8f7090d12))

;;; text, and the line ending it refuses

;; What counts as a line ending is (pitch lines)' business, shared with the
;; token-equivalence check and the printer. Three copies of that set would be
;; three things to keep in step, and the copy that drifts is always the one
;; nothing else exercises.

;; A line ending inside a text is refused, not split and not repaired.
;;
;; The arithmetic reason: a text contributes its length to the column, and the
;; cost factory prices it against the page width from that column. A newline
;; inside makes both silently wrong -- the layout is not merely ugly, it is
;; mis-costed, and nothing downstream can tell.
;;
;; The reason that actually matters here: a line comment's token text *includes*
;; the line ending that terminated it. So a printer that emits
;; (text (token-text tok)) for a comment produces a document with a break hidden
;; inside a text, and the result is the single most dangerous bug a Lisp
;; formatter has -- a comment that swallows the code after it. Refusing the
;; string forces the printer to split the terminator off and say explicitly what
;; follows. That does not replace the assertion the printer still owes; it makes
;; the mistake impossible to make by accident.
;;
;; A caller that legitimately holds a string containing an ending -- a string
;; literal written across lines, a block comment spanning lines -- uses
;; `verbatim` below, which is the sanctioned way to say "emit this exactly".
(define (text s)
  (let ((i (line-ending-index s)))
    (when i
      (assertion-violation
        'text
        "a document text may not contain a line ending; split it and emit an explicit break"
        s
        i)))
  (make-text-node s (string-length s)))

(define (make-text-node s len)
  (make-doc-text (if (= len 0) fail-text-empty fail-text-nonempty) 0 s len))

(define (newline s) (make-doc-newline fail-newline 1 s))

(define fail (make-doc-fail fail-all -1))

;;; Smart constructors
;;
;; Each of these partially evaluates at construction. Most are size reductions
;; that leave the denoted layout set alone, but two are the semantics:
;;
;;   (concat (full d) (text s)) with s non-empty is `fail` -- that is what
;;   `full` means, and
;;
;;   merging adjacent texts, together with the failure masks above, is what lets
;;   the resolver assume a leaf never fails and skip the check on the hot path.
;;
;; A consequence: the constructors are not injective, so a caller cannot recover
;; the shape it built. Nothing in this library's interface exposes structure to
;; a caller, so that costs nothing here.

(define (concat a b)
  (cond
    ((and (doc-text? a) (= 0 (doc-text-len a))) b)
    ((and (doc-text? b) (= 0 (doc-text-len b))) a)
    ;; nothing may follow a document required to end its line
    ((and (doc-full? a) (doc-text? b)) fail)
    ((doc-fail? a) fail)
    ((doc-fail? b) fail)
    ((and (doc-text? a) (doc-text? b))
      (make-text-node (cons (doc-text-s a) (doc-text-s b))
                      (+ (doc-text-len a) (doc-text-len b))))
    (else (make-doc-concat fail-none (+ (doc-nl-cnt a) (doc-nl-cnt b)) a b))))

(define (alternatives a b)
  (cond
    ((doc-fail? a) b)
    ((doc-fail? b) a)
    ((eq? a b) a)
    (else (make-doc-alt fail-none (max (doc-nl-cnt a) (doc-nl-cnt b)) a b))))

;; Indentation is unobservable on a text, and on a document whose own
;; indentation is already fixed by an inner align or reset.
(define (indentation-inert? d)
  (or (doc-fail? d) (doc-align? d) (doc-reset? d) (doc-text? d)))

(define (nest n d)
  (cond
    ((indentation-inert? d) d)
    ((doc-nest? d) (nest (+ n (doc-nest-n d)) (doc-nest-d d)))
    (else (make-doc-nest fail-none (doc-nl-cnt d) n d))))

(define (align d)
  (if (indentation-inert? d) d (make-doc-align fail-none (doc-nl-cnt d) d)))

(define (reset d)
  (if (indentation-inert? d) d (make-doc-reset fail-none (doc-nl-cnt d) d)))

(define (full d)
  (cond
    ((doc-full? d) d)
    ((doc-fail? d) fail)
    (else (make-doc-full fail-full (doc-nl-cnt d) d))))

(define (cost n d) (if (doc-fail? d) fail (make-doc-cost fail-none (doc-nl-cnt d) n d)))

;;; Derived combinators

(define empty-doc (text ""))

(define nl (newline " "))
(define break (newline ""))
(define hard-nl (newline #f))

(define space (text " "))
(define lparen (text "("))
(define rparen (text ")"))
(define lbracket (text "["))
(define rbracket (text "]"))

(define (alt . xs) (fold-right alternatives fail xs))

;; Rebuild d with f applied to each of its immediate sub-documents, returning d
;; itself when nothing changed so that sharing survives.
(define (doc-map-children f d)
  (cond
    ((doc-concat? d)
      (let ((a (f (doc-concat-a d))) (b (f (doc-concat-b d))))
        (if (and (eq? a (doc-concat-a d)) (eq? b (doc-concat-b d))) d (concat a b))))
    ((doc-alt? d)
      (let ((a (f (doc-alt-a d))) (b (f (doc-alt-b d))))
        (if (and (eq? a (doc-alt-a d)) (eq? b (doc-alt-b d))) d (alternatives a b))))
    ((doc-nest? d) (let ((x (f (doc-nest-d d))))
                     (if (eq? x (doc-nest-d d)) d (nest (doc-nest-n d) x))))
    ((doc-align? d) (let ((x (f (doc-align-d d))))
                      (if (eq? x (doc-align-d d)) d (align x))))
    ((doc-reset? d) (let ((x (f (doc-reset-d d))))
                      (if (eq? x (doc-reset-d d)) d (reset x))))
    ((doc-full? d) (let ((x (f (doc-full-d d))))
                     (if (eq? x (doc-full-d d)) d (full x))))
    ((doc-cost? d) (let ((x (f (doc-cost-d d))))
                     (if (eq? x (doc-cost-d d)) d (cost (doc-cost-n d) x))))
    (else d)))

;; Replace every newline by its flat string, failing where it has none.
;; Indentation becomes unobservable once no break survives, so nest, align and
;; reset are discarded on the way down.
;;
;; DIVERGENCE FROM THE REFERENCE. sorawee/pretty-expressive strips those three
;; wrappers and then maps over the *child's* children rather than recurring on
;; the child itself, so a newline that is the direct child of an align, nest or
;; reset comes back unflattened. There, (flatten (align nl)) is a hard break
;; instead of a space, and (flatten (align hard-nl)) is a hard break instead of
;; a failure -- which means (group (align d)), the shape a Lisp printer uses
;; constantly, can take its "flat" branch and still emit a line break. For a
;; formatter that promises to change only whitespace, a break nobody asked for
;; is not a cosmetic difference. Fixed here, and excluded from the differential
;; oracle's corpus with a note, since the two implementations disagree by
;; intent.
;;
;; The memo table makes this linear on a shared DAG. `group` shares its argument
;; between both alternatives, so nested groups would otherwise be exponential.
(define (flatten d)
  (let ((seen (make-eq-hashtable)))
    (let loop ((d d))
      (or (hashtable-ref seen d #f)
          (let ((result (cond
                          ((doc-align? d) (loop (doc-align-d d)))
                          ((doc-reset? d) (loop (doc-reset-d d)))
                          ((doc-nest? d) (loop (doc-nest-d d)))
                          ((doc-newline? d) (let ((s (doc-newline-s d)))
                                              (if s (text s) fail)))
                          (else (doc-map-children loop d)))))
            (hashtable-set! seen d result)
            result)))))

(define (group d) (alternatives d (flatten d)))

;;; verbatim
;;
;; `text` refuses a line ending, which is right, but a caller may hold a string
;; that legally contains one: in pitch's case a string literal written across
;; lines, a #| |# block spanning lines, or a #; eliding a datum written across
;; lines. `verbatim` is the sanctioned way to emit such a string exactly.
;;
;; It lives here rather than in the caller because it is the sanctioned answer
;; to a restriction this library imposes: `text` refuses, and `verbatim` is what
;; it refuses in favour of. It knows nothing about Scheme, so it costs this
;; library none of its independence.
;;
;; The breaks are hard and the whole thing sits under `reset`, so the
;; continuation lines get no indentation at all. That is not a stylistic choice:
;; indenting inside a string literal changes the value the literal denotes, and
;; indenting inside a comment rewrites the comment's contents, which pitch never
;; does. Both callers want the same thing, so there is nothing to parameterize.
;;
;; What it does not preserve: the resolver renders every break as a linefeed, so
;; a string whose interior endings are CR, CRLF, NEL, LS or PS comes back with
;; linefeeds. A caller for whom that is observable has to refuse the input; this
;; library has no way to say "break with *these* characters".

;; The join is written out rather than delegated to v-concat, which is defined
;; further down: a forward reference would work, but reading order should not
;; depend on knowing that.
(define (verbatim s)
  (let ((pieces (line-ending-pieces s)))
    (if (null? (cdr pieces))
        (text s)
        (reset (let loop ((d (text (car pieces))) (rest (cdr pieces)))
                 (if (null? rest)
                     d
                     (loop (concat d (concat hard-nl (text (car rest))))
                           (cdr rest))))))))

;;; The append families
;;
;; Five ways to join documents, each with a variadic -append and a list-taking
;; -concat. The Racket originals' infix aliases (<>, <$>, <+>, <s>, <+s>) are
;; not provided: they read as operators there and as line noise here, and the
;; spelled-out name says which of the five it is.

(define (fold-doc f xs) (if (null? xs) empty-doc (fold-left f (car xs) (cdr xs))))

(define (join-plain x y) (concat x y))
(define (join-space x y) (concat x (concat space y)))
(define (join-hard-nl x y) (concat x (concat hard-nl y)))
(define (join-aligned x y) (concat x (align y)))
(define (join-space-aligned x y) (concat x (concat space (align y))))

(define (u-concat xs) (fold-doc join-plain xs))
(define (us-concat xs) (fold-doc join-space xs))
(define (v-concat xs) (fold-doc join-hard-nl xs))
(define (a-concat xs) (fold-doc join-aligned xs))
(define (as-concat xs) (fold-doc join-space-aligned xs))

(define-syntax define-append
  (syntax-rules ()
    ((_ name binary lister)
      (define name
        (case-lambda (() empty-doc) ((x) x) ((x y) (binary x y)) (xs (lister xs)))))))

(define-append u-append join-plain u-concat)
(define-append us-append join-space us-concat)
(define-append v-append join-hard-nl v-concat)
(define-append a-append join-aligned a-concat)
(define-append as-append join-space-aligned as-concat))
