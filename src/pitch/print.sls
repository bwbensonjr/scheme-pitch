;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The translation: a CST becomes a document the layout engine can resolve.
;;
;; This is the seam the whole pipeline was built around. Every layer below was
;; chosen so that a comment cannot be lost by accident -- trivia are ordinary
;; children, text is owned by tokens, the leaf sequence is the token vector --
;; and all of that protects the representation. Deciding where a comment goes
;; when the line it was written on no longer exists is a decision that has to be
;; made here, explicitly, and it is the decision that has sunk every datum-based
;; Scheme pretty-printer.
;;
;; WHAT THIS READS. Token text, and the text of whitespace children. Nothing
;; else. In particular it never reads a token's offsets, line or column, so a
;; bug in the recorded positions cannot produce a misplaced comment. Whether a
;; comment was written after code on the same line is answered by looking for a
;; line ending in the whitespace between them, which is both more direct than
;; arithmetic across two tokens and immune to the trap docs/DESIGN.md warns
;; about: token-end-line is not the last line a token occupies when its text
;; ends with a line ending, which is true of every line comment -- exactly the
;; tokens this classification is about.
;;
;; WHAT THIS DOES NOT KNOW. Any per-form layout rule. `compound-shape` is the
;; one place a head symbol could ever be consulted, and today it returns the
;; same answer for every node without looking at it. Style tables are data, not
;; code; when the table arrives it replaces that function's body and nothing
;; else here changes.
;;
;; IDEMPOTENCE. The document depends on exactly three properties of the tree:
;; each token's text, whether a line ending separates two children, and how many
;; blank lines a whitespace run holds. Run the formatter on its own output and
;; all three are already at their fixed point -- texts are unchanged by
;; construction, an attached comment is still emitted with no ending before it,
;; an own-line comment is still preceded by a break, and blank runs are already
;; at or under their caps. So the second run builds the *same document*, and the
;; same document lays out to the same text. That is why layer 3 is an argument
;; here rather than only a test over there.

#!r6rs

(library (pitch print)
  (export cst->document compound-shape)
  (import
    (rnrs base (6))
    (rnrs control (6))
    (rnrs lists (6))
    (rnrs records syntactic (6))
    (pitch cst)
    (pitch doc)
    (only (pitch lines) line-ending-count strip-final-line-ending))

;;; Tuning

;; How far a hanging body is indented from its opening delimiter. SRFI 272 calls
;; this pp-tab. It is a constant rather than configuration: README.md says the
;; configuration surface is width and dialect, and this is neither.
(define hanging-indent 2)

;; Blank lines survive, capped. README.md's rule, which is black's.
(define blank-cap-inside 1)
(define blank-cap-top 2)

;;; Items
;;
;; The child sequence interleaves data with whitespace and comments. Folding it
;; into items is where every placement decision is made, and after that the
;; shapes below only decide where the breaks and the indentation go.
;;
;;   doc       the document for this item, including anything attached to it
;;   blanks    blank lines preceding it, already capped
;;   broken?   whether it ends in a forced break, so nothing may follow it on
;;             its line
;;   own-line? whether it is a comment that was written on a line of its own, so
;;             nothing may precede it on its line either
;;   dot?      whether it is the `.` of an improper list, awaiting its tail

(define-record-type item
  (fields doc blanks broken? own-line? dot?)
  (sealed #t) (opaque #f)
  (nongenerative item-v0-6f0b7e91-2a4d-4c8e-9f13-0d5a7c4e2b16))

(define (whitespace-leaf? node)
  (and (leaf? node) (eq? (leaf-kind node) 'whitespace)))

;; The only token kinds whose text can end with a line ending, and therefore the
;; only ones that force a break after themselves. #| |# ends with |#, #; ends
;; with the elided datum, and #!r6rs ends with the directive name, so none of
;; those three is here.
(define (forced-break-leaf? node)
  (and (leaf? node) (memq (leaf-kind node) '(comment shebang)) #t))

;;; Leaves

;; A leaf is its token's text, emitted exactly. Not the printed form of the
;; token's value: the declared-normalizations list is empty, so #xff stays #xff
;; and "\x41;" stays "\x41;". `verbatim` rather than `text` because a token may
;; legally span lines -- a string literal, a #| |# block, a #; eliding a datum
;; written across lines -- and those keep their interior, with no indentation
;; added, since indenting inside a string changes the value it denotes and
;; inside a comment it rewrites the comment's contents.
;;
;; A line comment is the one leaf that is not just its text. Its token text
;; includes the line ending that terminated it, which `text` refuses outright;
;; the terminator is split off and re-emitted as an explicit break. There is no
;; branch here that omits that break -- including for a comment ending the
;; source with no terminator, which gets one anyway, and which is also what
;; makes a formatted file end with a newline.
(define (leaf-doc node)
  (if (forced-break-leaf? node)
      (concat (verbatim (strip-final-line-ending (leaf-text node))) hard-nl)
      (verbatim (leaf-text node))))

;;; Nodes
;;
;; Returns two values: the document, and whether it ends in a forced break. The
;; second is what the sequencer needs and cannot recover from the first, since
;; the algebra exposes no "does this end in a break" predicate and inventing one
;; would be a second description of a fact the tree already has.

(define (node-doc node)
  (cond ((leaf? node) (values (leaf-doc node) (forced-break-leaf? node)))
        ((compound? node) (compound-doc node))
        ((prefix? node) (prefix-doc node))
        ((error-node? node) (error-doc node))
        ((document? node) (values (document-doc node) #f))
        (else (assertion-violation 'node-doc "Not a CST node" node))))

;;; Sequencing

;; Fold a child sequence into items. Whitespace never becomes an item; it
;; contributes the two facts the placement rules need, and is otherwise
;; discarded and re-derived, which is what "reflows from scratch" means.
(define (children->items children cap)
  (let loop ((cs children) (endings 0) (items '()))
    (if (null? cs)
        (reverse items)
        (let ((c (car cs)))
          (if (whitespace-leaf? c)
              (loop (cdr cs) (+ endings (line-ending-count (leaf-text c))) items)
              (let-values (((d broken?) (node-doc c)))
                (loop (cdr cs)
                      0
                      (add-item items c d
                                (min cap (max 0 (- endings 1)))
                                broken?
                                (= endings 0)))))))))

;; Where a child joins the sequence. Three outcomes, and the order matters: a
;; comment attaches before the dot rule can fire, so `(a . ; why` attaches the
;; comment to the dot rather than treating it as the tail.
(define (add-item items node d blanks broken? same-line?)
  (let ((prev (and (pair? items) (car items))))
    (cond
      ;; A comment written after code on its line stays on that line. Note that
      ;; an item already ending in a forced break can never take an attachment:
      ;; two adjacent line comments have no whitespace token between them at all
      ;; -- the first comment's text swallowed the line ending -- so same-line?
      ;; is true, and only prev's broken? tells them apart.
      ((and prev (trivia? node) same-line? (not (item-broken? prev))
            (= blanks 0))
       (cons (make-item (concat (item-doc prev) (concat space d))
                        (item-blanks prev) broken?
                        (item-own-line? prev) (item-dot? prev))
             (cdr items)))
      ;; The dot binds to what follows it. Left as an item of its own, an
      ;; improper list breaking would put the dot alone on a line, which is
      ;; worse than useless; binding forward also removes any path by which a
      ;; break could land between the dot and the tail.
      ((and prev (item-dot? prev) (not (item-broken? prev)) (= blanks 0)
            (not (trivia? node)))
       (cons (make-item (concat (item-doc prev) (concat space d))
                        (item-blanks prev) broken?
                        (item-own-line? prev) #f)
             (cdr items)))
      ;; Anything else starts an item. A comment that did not attach was
      ;; written on a line of its own, and stays there: the reflow is free to
      ;; pull a *datum* up onto the preceding line, since layout is re-derived,
      ;; but moving a comment changes which code a reader takes it to be about.
      (else
       (cons (make-item d blanks broken?
                        (and (trivia? node) (not same-line?))
                        (dot-leaf? node))
             items)))))

;;; Joining

;; n forced breaks, of which only the last carries the indentation in force.
;;
;; The resolver indents after every break, so n breaks in a row would leave the
;; blank lines between them holding the enclosing indentation as trailing
;; whitespace. A blank line has to be empty, so all but the final break are
;; taken under `reset`, where the indentation is zero. The final one lands on
;; the line that actually has content and indents it normally.
(define (hard-breaks n)
  (let loop ((n (- n 1)) (d empty-doc))
    (if (<= n 0)
        (concat (reset d) hard-nl)
        (loop (- n 1) (concat d hard-nl)))))

;; What goes between two items.
;;
;; A blank line means the pair definitely broke, so the separator is hard: one
;; break to end the line, plus one per blank line. When the previous item ended
;; in a forced break, that break already ended the line, so one fewer is needed
;; -- and when there are no blanks, nothing at all is needed.
;;
;; A comment written on a line of its own gets a forced break before it too.
;; Without one, the head-to-first-argument join of the aligned shape -- which is
;; a hard space, so that the two share the opening line -- would pull it up onto
;; the preceding line and change which code it reads as being about.
(define (gap prev it sep)
  (let ((blanks (item-blanks it)))
    (let ((d (cond ((> blanks 0)
                    (hard-breaks (if (item-broken? prev) blanks (+ blanks 1))))
                   ((item-broken? prev) empty-doc)
                   ((item-own-line? it) hard-nl)
                   (else sep))))
      ;; The second of two guards on a comment swallowing the code after it.
      ;; The first is that leaf-doc has no branch omitting the break; this one
      ;; is that nothing is ever placed after one on the same line. Both are
      ;; true by construction today, which is the point: this one fails loudly
      ;; if a later edit to the cond above makes it false.
      (when (item-broken? prev)
        (assert (not (eq? d sep))))
      d)))

;; items must be non-empty.
(define (join-items items sep)
  (let loop ((d (item-doc (car items))) (prev (car items)) (rest (cdr items)))
    (if (null? rest)
        d
        (let ((it (car rest)))
          (loop (concat d (concat (gap prev it sep) (item-doc it)))
                it
                (cdr rest))))))

(define (last-item-broken? items)
  (and (pair? items) (item-broken? (car (reverse items)))))

;;; The style seam

;; The single point at which a per-form rule is consulted. It ignores its
;; argument: this change ships one generic shape, which docs/DESIGN.md requires
;; anyway as the graceful-degradation behavior for a form no table matches. When
;; the SRFI 272 table arrives it looks up the head symbol here and returns a
;; richer descriptor; no other function in this library may examine a head.
(define (compound-shape node) 'generic)

;;; Compound nodes

;; Three candidate layouts, and the cost objective chooses among them over the
;; whole document rather than greedily at each node. That global choice is the
;; entire reason the Pi-e engine was ported: a Wadler-style group commits to the
;; flat rendering whenever it fits and cannot see the cost that imposes further
;; down.
;;
;;   flat      (f a b c)
;;   aligned   (f a          hanging   (f
;;                b                      a
;;                c)                     b
;;                                       c)
;;
;; DETERMINISM. Which of aligned and hanging wins must not depend on the order
;; the resolver happens to keep equally ranked candidates in. It does not, and
;; without needing a cost penalty to arrange it: hanging breaks before the first
;; argument where aligned does not, and is otherwise the same set of breaks, so
;; hanging is always exactly one line taller. Under an objective that ranks
;; overflow before height -- which the default factory does -- hanging therefore
;; wins only when it strictly reduces overflow, and ties are impossible except
;; where the two render identically anyway.
;;
;; The rejected alternative was buying that with `(cost n d)`. It would have
;; worked and it would have been wrong: `cost` takes a value in the cost
;; factory's own representation, so a penalty here would couple the translation
;; to one factory. The translation must not know what a cost looks like.
(define (compound-doc node)
  (let* ((open (leaf-doc (compound-open node)))
         (close (if (compound-close node) (leaf-doc (compound-close node)) empty-doc))
         (items (children->items (compound-children node) blank-cap-inside)))
    ;; The whole node is wrapped in align, so its indentation is the column its
    ;; opening delimiter was laid out at. That is what puts a closing delimiter
    ;; forced onto its own line -- by a trailing line comment -- underneath the
    ;; opening one, and it is what hanging's indent is measured from.
    (define (whole body) (align (concat open (concat body close))))
    (values
      (cond
        ((null? items) (concat open close))
        ((null? (cdr items)) (group (whole (item-doc (car items)))))
        ;; The aligned shape captures its indentation at the column after the
        ;; head, which is only the first argument's column if nothing forced a
        ;; break inside the head. A trailing line comment on the head does force
        ;; one -- `(a ; note` -- and then the alignment would be captured at the
        ;; start of the next line, putting the arguments at column zero where
        ;; they read as new top-level forms. Hanging measures from the opening
        ;; delimiter through `whole`'s align, which is entered before any content
        ;; and so cannot be moved by a break, so it is the shape that survives.
        ((not (eq? (gap (car items) (cadr items) space) space))
         (group (whole (hanging-body items))))
        (else
         (alternatives (group (whole (aligned-body items)))
                       (whole (hanging-body items)))))
      ;; An unclosed node ending in a comment is the only compound that leaves a
      ;; forced break at its end. It arises only on malformed input, which the
      ;; pipeline refuses to format, but the translation stays total.
      (and (not (compound-close node)) (last-item-broken? items)))))

;; The head and the first argument share the opening line; the rest begin at the
;; first argument's column. The separator between the two is a hard space, so
;; there is no break to choose there -- that choice is what the hanging
;; alternative is.
(define (aligned-body items)
  (let ((head (car items)) (rest (cdr items)))
    (concat (item-doc head)
            (concat (gap head (car rest) space)
                    (align (join-items rest nl))))))

;; The head alone on the opening line, the arguments indented from the opening
;; delimiter.
;;
;; The head is inside the nest even though it is on the opening line and so
;; cannot be indented by it. That is not redundant: a head carrying a trailing
;; line comment emits its own break, and a break is indented by the nesting in
;; force where the break occurs, not by the nesting around what follows it. With
;; the head outside, `(a ; note` would put `b` back at column zero -- reading as
;; a new top-level form -- while everything after it indented correctly, which
;; is worse than either being wrong consistently.
(define (hanging-body items)
  (let ((head (car items)) (rest (cdr items)))
    (nest hanging-indent
          (concat (item-doc head)
                  (concat (gap head (car rest) nl)
                          (join-items rest nl))))))

;;; Prefix nodes

;; The marker and its datum are concatenated with nothing between them, so a
;; break can never appear between an abbreviation and what it abbreviates. When
;; trivia sit between the two they are sequenced normally, but joined with a
;; hard space rather than a soft newline: the only line break that may separate
;; a marker from its datum is one a comment forced.
(define (prefix-doc node)
  (let* ((marker (leaf-doc (prefix-marker node)))
         (datum (prefix-datum node))
         ;; Whitespace between the marker and its datum is discarded like any
         ;; other, so `'  x` binds as tightly as `'x`. The test is on the items,
         ;; not on the raw children: a child sequence holding nothing but
         ;; whitespace produces no items at all.
         (mid (children->items (prefix-children node) blank-cap-inside)))
    (if (null? mid)
        (if datum
            (let-values (((d broken?) (node-doc datum)))
              (values (concat marker d) broken?))
            (values marker #f))
        (let* ((head (make-item marker 0 #f #f #f))
               (items (if datum
                          (let-values (((d broken?) (node-doc datum)))
                            (append (cons head mid)
                                    (list (make-item d 0 broken? #f #f))))
                          (cons head mid))))
          (values (join-items items space)
                  (last-item-broken? items))))))

;;; Error nodes

;; Every token the malformed region covers, emitted in order. Never formatted in
;; practice -- the pipeline refuses an unclean parse -- but the translation is
;; total over the node kinds, and a test that translates a malformed tree should
;; get a document rather than an exception.
(define (error-doc node)
  (let ((items (children->items (error-node-children node) blank-cap-inside)))
    (if (null? items)
        (values empty-doc #f)
        (values (join-items items space) (last-item-broken? items)))))

;;; The document node

;; Top-level forms are separated by a hard break: two of them never share a
;; line, and the forced separator also keeps the resolver from exploring choices
;; across them, which is what keeps a whole file's frontier from compounding.
;;
;; The file ends with exactly one line ending. A last item that already ends in
;; a forced break -- a file ending in a line comment -- has one, and adding
;; another would leave a blank line at end of file.
(define (document-doc node)
  (let ((items (children->items (document-children node) blank-cap-top)))
    (if (null? items)
        empty-doc
        (concat (join-items items hard-nl)
                (if (last-item-broken? items) empty-doc hard-nl)))))

;;; Entry point

(define (cst->document node)
  (let-values (((d broken?) (node-doc node)))
    d)))
