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
;; WHAT THIS READS. Token text, token values, and the text of whitespace
;; children. Nothing else. In particular it never reads a token's offsets, line
;; or column, so a bug in the recorded positions cannot produce a misplaced
;; comment. Whether a comment was written after code on the same line is
;; answered by looking for a line ending in the whitespace between them, which
;; is both more direct than arithmetic across two tokens and immune to the trap
;; docs/DESIGN.md warns about: token-end-line is not the last line a token
;; occupies when its text ends with a line ending, which is true of every line
;; comment -- exactly the tokens this classification is about.
;;
;; A token's *value* is read in exactly one place, `compound-shape`, and only to
;; select a layout -- which is to say only to select whitespace. Every character
;; this library emits comes from `leaf-text`. That is what keeps the empty
;; declared-normalizations list intact while letting `|cond|` and, under
;; #!fold-case, `COND` take the shape they mean.
;;
;; WHERE THE PER-FORM KNOWLEDGE IS. In (pitch style), as data. `compound-shape`
;; is the one function here that looks a head up, and no other function in this
;; library may examine a head. Everything below it dispatches on a descriptor
;; and would work just as well against a table nobody has written yet.
;;
;; WHY ITEMS HOLD NODES RATHER THAN DOCUMENTS. An item carries the child nodes
;; it was folded from and materializes its document only once a style has been
;; assigned. The alternative -- build documents, decide the shape, rebuild the
;; ones whose style turned out not to be the default -- translates a styled
;; subtree twice, and since styled forms nest, twice per level is exponential in
;; nesting depth. Splitting the fold from the materialization means every
;; subtree is translated exactly once whatever shape wins.
;;
;; IDEMPOTENCE. The document depends on exactly four properties of the tree:
;; each token's text, each list's head symbol, whether a line ending separates
;; two children, and how many blank lines a whitespace run holds. Run the
;; formatter on its own output and all four are already at their fixed point --
;; texts and therefore values are unchanged by construction, an attached comment
;; is still emitted with no ending before it, an own-line comment is still
;; preceded by a break, and blank runs are already at or under their caps. So
;; the second run selects the same style, reaches the same degradation decision,
;; builds the *same document*, and the same document lays out to the same text.
;; That is why layer 3 is an argument here rather than only a test over there.

(define-library (pitch print)
(export cst->document compound-shape)
(import
  (scheme base)
  (scheme case-lambda)
  (pitch cst)
  (pitch doc)
  (pitch lines)
  (pitch reader)
  (pitch sequence)
  (pitch style)
  )
(begin

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

;;; Tuning

;; hanging-indent -- how far a broken body sits from its opening delimiter --
;; is imported from (pitch style), where it has to live because terminal-tail
;; needs it and that library imports nothing. See the note beside it there for
;; why it is measured from the delimiter and why it is not configuration. The
;; generic shape below uses it directly; a *styled* form takes its indent from
;; its tail terminal instead, which is what lets `body0` sit flush.

;; Blank lines survive, capped. README.md's rule, which is black's.
(define blank-cap-inside 1)
(define blank-cap-top 2)

;; The separator inside a filled list: each gap chooses independently, so the
;; elements pack rather than taking a line each. This needs no addition to
;; (pitch doc) -- a per-gap choice is exactly what `alternatives` is -- and it
;; is the shape the Pi-e engine exists to resolve without backtracking.
(define fill-sep (alternatives space nl))

;;; Items
;;
;; The child sequence interleaves data with whitespace and comments. Folding it
;; into items is where every placement decision is made, and after that the
;; shapes below only decide where the breaks and the indentation go.
;;
;;   pieces    the child nodes this item was folded from, in order; its document
;;             is these joined by hard spaces, built once a style is known
;;   blanks    blank lines preceding it, already capped
;;   broken?   whether it ends in a forced break, so nothing may follow it on
;;             its line
;;   own-line? whether it is a comment that was written on a line of its own, so
;;             nothing may precede it on its line either
;;   dot?      whether it is the `.` of an improper list, awaiting its tail
;;   datum?    whether it began from a datum rather than from trivia; this is
;;             what says whether it can occupy a style's slot
;;   style     how its pieces are laid out, assigned after the fold
;;   blank-after? whether a blank line follows it, which decides whether its own
;;             forced break may carry indentation

(define-record-type <item>
  (make-item-record pieces attributes)
  item?
  (pieces item-pieces)
  (attributes item-attributes))

;; Keep the public construction shape used by the fold without requiring an
;; eight-argument record constructor from the host ABI.
(define (make-item pieces blanks broken? own-line? . rest)
  (make-item-record pieces
                    (vector blanks
                            broken?
                            own-line?
                            (list-ref rest 0)
                            (list-ref rest 1)
                            (list-ref rest 2)
                            (list-ref rest 3))))

(define (item-blanks it) (vector-ref (item-attributes it) 0))
(define (item-broken? it) (vector-ref (item-attributes it) 1))
(define (item-own-line? it) (vector-ref (item-attributes it) 2))
(define (item-dot? it) (vector-ref (item-attributes it) 3))
(define (item-datum? it) (vector-ref (item-attributes it) 4))
(define (item-style it) (vector-ref (item-attributes it) 5))
(define (item-blank-after? it) (vector-ref (item-attributes it) 6))

(define (item-node it) (car (item-pieces it)))

(define (item-with-style it style)
  (make-item (item-pieces it)
             (item-blanks it)
             (item-broken? it)
             (item-own-line? it)
             (item-dot? it)
             (item-datum? it)
             style
             (item-blank-after? it)))

(define (item-with-blank-after it blank-after?)
  (make-item (item-pieces it)
             (item-blanks it)
             (item-broken? it)
             (item-own-line? it)
             (item-dot? it)
             (item-datum? it)
             (item-style it)
             blank-after?))

(define (whitespace-leaf? node) (and (leaf? node) (eq? (leaf-kind node) 'whitespace)))

;; The only token kinds whose text can end with a line ending, and therefore the
;; only ones that force a break after themselves. #| |# ends with |#, #; ends
;; with the elided datum, and the R6RS directive ends with its name, so none of
;; those three is here.
(define (forced-break-leaf? node)
  (and (leaf? node) (memq (leaf-kind node) '(comment shebang)) #t))

;;; Forced breaks, structurally
;;
;; Whether a node's document ends in a forced break, answered without building
;; that document. The fold needs it before any style has been chosen, and the
;; emitters need it too, so it is defined once here rather than returned
;; alongside each document -- a second copy of a fact is a second thing that can
;; be wrong. It walks only the rightmost spine.

(define (node-broken? node)
  (cond
    ((leaf? node) (forced-break-leaf? node))
    ;; A closed compound ends with its delimiter, so only an unclosed one --
    ;; malformed input -- can end in a break.
    ((compound? node) (and (not (compound-close node))
                           (children-broken? (compound-children node))))
    ((prefix? node) (if (prefix-datum node)
                        (node-broken? (prefix-datum node))
                        (children-broken? (prefix-children node))))
    ((error-node? node) (children-broken? (error-node-children node)))
    ((document? node) #f)
    (else (error 'node-broken? "Not a CST node" node))))

;; The last item's break is the last non-whitespace child's: every branch of
;; `add-item` carries the incoming child's flag onto the item it produces.
(define (children-broken? children)
  (let loop ((cs children) (last #f))
    (cond
      ((null? cs) (and last (node-broken? last)))
      ((whitespace-leaf? (car cs)) (loop (cdr cs) last))
      (else (loop (cdr cs) (car cs))))))

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
;;
;; `reset-break?` takes that break at indentation zero. It is set when a blank
;; line follows, because the resolver indents after every break and this break
;; is then the one that lands on the blank line -- a line holding the enclosing
;; indentation as trailing whitespace is not blank. Neither branch omits the
;; break, which is the property this function exists to guarantee.
(define leaf-doc
  (case-lambda
    ((node) (leaf-doc node #f))
    ((node reset-break?)
      (if (forced-break-leaf? node)
          (concat (verbatim (strip-final-line-ending (leaf-text node)))
                  (if reset-break? (reset hard-nl) hard-nl))
          (verbatim (leaf-text node))))))

;;; Nodes

(define (node-doc node tbl)
  (cond
    ((leaf? node) (leaf-doc node))
    ((compound? node) (compound-doc node tbl))
    ((prefix? node) (prefix-doc node tbl))
    ((error-node? node) (error-doc node tbl))
    ((document? node) (document-doc node tbl))
    (else (error 'node-doc "Not a CST node" node))))

;; What one subform is laid out as. The three element styles agree on everything
;; that is not a compound, and they differ only in the compound's *own* shape:
;; its children are laid out by the ordinary rules either way, so suppression is
;; shallow.
;;
;;   expression   the ordinary rules; a list here consults the table
;;   datum        no lookup, and no shape of its own
;;   (nested s)   no lookup, and its elements are styled by s
(define (styled-node-doc node style tbl)
  (cond
    ((or (eq? style 'expression) (not (compound? node))) (node-doc node tbl))
    ((nested-style? style) (headless-doc node (nested-style-shape style) tbl))
    (else (headless-doc node #f tbl))))

;;; Sequencing

;; Fold a child sequence into items. Whitespace never becomes an item; it
;; contributes the two facts the placement rules need, and is otherwise
;; discarded and re-derived, which is what "reflows from scratch" means.
;; A whitespace run's blank-line count is its line endings less the one that
;; terminated the preceding line -- unless the preceding token already carried
;; that ending in its own text, which is exactly what a line comment does. After
;; a comment, every ending in the run is a blank line. Subtracting one anyway is
;; how `; c` followed by a blank line used to lose it.
(define (blank-count endings prev-broken? cap)
  (min cap (max 0 (if prev-broken? endings (- endings 1)))))

(define (children->items children cap)
  (let loop ((cs children) (endings 0) (prev-broken? #f) (items '()))
    (if (null? cs)
        (mark-blanks-after (reverse items))
        (let ((c (car cs)))
          (if (whitespace-leaf? c)
              (loop (cdr cs)
                    (+ endings (line-ending-count (leaf-text c)))
                    prev-broken?
                    items)
              (let ((broken? (node-broken? c)))
                (loop (cdr cs)
                      0
                      broken?
                      (add-item items
                                c
                                (blank-count endings prev-broken? cap)
                                broken?
                                (= endings 0)))))))))

;; Record on each item whether a blank line follows it. Only the item before a
;; blank run can know that, and every emitter that materializes an item needs
;; it, so it is settled once here rather than rediscovered at each join -- where
;; missing a case would silently leave whitespace on a line that must be empty.
(define (mark-blanks-after items)
  (let loop ((xs items) (out '()))
    (cond
      ((null? xs) (reverse out))
      ((null? (cdr xs)) (reverse (cons (car xs) out)))
      (else (loop (cdr xs)
                  (cons (item-with-blank-after (car xs) (> (item-blanks (cadr xs)) 0))
                        out))))))

;; Where a child joins the sequence. Three outcomes, and the order matters: a
;; comment attaches before the dot rule can fire, so `(a . ; why` attaches the
;; comment to the dot rather than treating it as the tail.
(define (add-item items node blanks broken? same-line?)
  (let ((prev (and (pair? items) (car items))))
    (define (extend prev dot?)
      (cons (make-item (append (item-pieces prev) (list node))
                       (item-blanks prev)
                       broken?
                       (item-own-line? prev)
                       dot?
                       (item-datum? prev)
                       (item-style prev)
                       (item-blank-after? prev))
            (cdr items)))
    (cond
      ;; A comment written after code on its line stays on that line. Note that
      ;; an item already ending in a forced break can never take an attachment:
      ;; two adjacent line comments have no whitespace token between them at all
      ;; -- the first comment's text swallowed the line ending -- so same-line?
      ;; is true, and only prev's broken? tells them apart.
      ((and prev (trivia? node) same-line? (not (item-broken? prev)) (= blanks 0))
        (extend prev (item-dot? prev)))
      ;; The dot binds to what follows it. Left as an item of its own, an
      ;; improper list breaking would put the dot alone on a line, which is
      ;; worse than useless; binding forward also removes any path by which a
      ;; break could land between the dot and the tail.
      ((and prev
            (item-dot? prev)
            (not (item-broken? prev))
            (= blanks 0)
            (not (trivia? node))) (extend prev #f))
      ;; Anything else starts an item. A comment that did not attach was
      ;; written on a line of its own, and stays there: the reflow is free to
      ;; pull a *datum* up onto the preceding line, since layout is re-derived,
      ;; but moving a comment changes which code a reader takes it to be about.
      (else (cons (make-item (list node)
                             blanks
                             broken?
                             (and (trivia? node) (not same-line?))
                             (dot-leaf? node)
                             (not (trivia? node))
                             'expression
                             #f)
                  items)))))

;;; Materializing

;; An item's document: its pieces under its style, joined by hard spaces. A
;; piece that is not the item's datum is trivia, and every style agrees on a
;; leaf, so applying the item's style to all of them is uniform rather than
;; approximate.
;; An item's forced break, when it has one, is its last piece's. That is the
;; break a following blank line lands on, so it is the one that takes the reset.
(define (item-doc it tbl)
  (let ((style (item-style it))
        (reset-last? (and (item-broken? it) (item-blank-after? it))))
    (let loop ((ps (item-pieces it)) (d #f))
      (if (null? ps)
          (or d empty-doc)
          (let* ((last? (null? (cdr ps)))
                 (pd (if (and last? reset-last? (leaf? (car ps)))
                         (leaf-doc (car ps) #t)
                         (styled-node-doc (car ps) style tbl))))
            (loop (cdr ps) (if d (concat d (concat space pd)) pd)))))))

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
    (if (<= n 0) (concat (reset d) hard-nl) (loop (- n 1) (concat d hard-nl)))))

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
;; When the previous item ended in a forced break, that break already ended the
;; line and already opened the first blank one, so `blanks` more breaks are
;; needed rather than `blanks + 1`. That break is also under `reset` -- see
;; `item-doc` -- so the blank line it opens is genuinely empty.
(define (gap prev it sep)
  (let ((blanks (item-blanks it)))
    (cond
      ((> blanks 0) (hard-breaks (if (item-broken? prev) blanks (+ blanks 1))))
      ((item-broken? prev) empty-doc)
      ((item-own-line? it) hard-nl)
      (else
        ;; The second of two guards on a comment swallowing the code after
        ;; it. The first is that leaf-doc has no branch omitting the break;
        ;; this one is that the ordinary separator -- the only outcome that
        ;; can put something on the previous item's line -- is unreachable
        ;; after an item that ended in one. It is true by construction, and
        ;; it is written so that a later edit to this cond fails loudly.
        ;;
        ;; The test is on the branch rather than on the document it returns.
        ;; Comparing documents was wrong: `hard-breaks 1` reduces to exactly
        ;; `hard-nl`, which is also the separator between top-level forms, so
        ;; a comment followed by one blank line tripped an assertion on
        ;; perfectly good input.
        (unless (not (item-broken? prev))
          (error 'gap "broken item reached the ordinary separator" prev))
        sep))))

;; items must be non-empty.
(define (join-items items sep tbl)
  (let loop ((d (item-doc (car items) tbl)) (prev (car items)) (rest (cdr items)))
    (if
      (null? rest)
      d
      (let ((it (car rest)))
        (loop (concat d (concat (gap prev it sep) (item-doc it tbl))) it (cdr rest))))))

(define (last-item items) (car (reverse items)))

(define (last-item-broken? items) (and (pair? items) (item-broken? (last-item items))))

(define (split-items items n)
  (let loop ((xs items) (n n) (acc '()))
    (if (or (= n 0) (null? xs))
        (values (reverse acc) xs)
        (loop (cdr xs) (- n 1) (cons (car xs) acc)))))

;;; The style seam

;; The single point at which a per-form rule is consulted, and the only place in
;; this library that reads a head. It returns `generic`, `fill`, or the compiled
;; style the table holds for this head.
;;
;; A bytevector is `fill` without reference to any table: its elements are
;; octets, so no per-form judgment applies and one octet per line is nobody's
;; intent. A vector is left generic, because its elements can be anything.
(define (compound-shape node tbl)
  (cond
    ((bytevector-node? node) 'fill)
    ((not (list-node? node)) 'generic)
    (else (let ((head (head-symbol node)))
            (or (and head (style-table-ref tbl head)) 'generic)))))

;; The head is the first datum child, and it keys the table by its token's
;; *value* -- the symbol the reader produced. `|cond|` is `cond`, and under
;; #!fold-case so is `COND`; a formatter that styled one spelling and not
;; another would be reporting a lexical accident as a semantic difference. Any
;; other head, including a compound, keys nothing.
(define (head-symbol node)
  (let loop ((cs (compound-children node)))
    (cond
      ((null? cs) #f)
      ((trivia? (car cs)) (loop (cdr cs)))
      ((and (leaf? (car cs)) (eq? (leaf-kind (car cs)) 'identifier))
        (token-value (leaf-token (car cs))))
      (else #f))))

;;; Matching a style

(define (identifier-item? it)
  (let ((n (item-node it))) (and (leaf? n) (eq? (leaf-kind n) 'identifier))))

(define (list-item? it) (list-node? (item-node it)))

(define (has-dot? node) (exists dot-leaf? (compound-children node)))

;; How many items the style's slots consume, or #f when the style does not
;; describe this form. Every failure here is ordinary input rather than an
;; error, and every one of them falls back to the generic shape.
;;
;; The gap test is the comment case, and it reuses `gap` rather than re-deriving
;; the question: the separator between two items is a plain space exactly when
;; nothing forced a break between them. A comment inside the region a style
;; requires to be on one line therefore withdraws the style, which is right --
;; the alternative would be moving the comment, and that is what layer 1
;; refuses.
(define (styled-slot-count items shape)
  (and
    (pair? items)
    (item-datum? (car items))
    (let loop ((slots (styled-slots shape)) (prev (car items)) (rest (cdr items)) (n 0))
      (cond
        ((null? slots) n)
        ((null? rest) #f) ;fewer elements than slots
        (else (let ((s (car slots)) (it (car rest)))
                (cond
                  ((not (item-datum? it)) #f) ;a comment landed in a slot
                  ((not (eq? (gap prev it space) space)) #f)
                  ;; i? consumes its element only if that element is an
                  ;; identifier; otherwise it consumes nothing and the rest of the
                  ;; style matches at the same element. One entry then covers both
                  ;; (let ((x 1)) b) and (let loop ((x 1)) b).
                  ((and (slot-optional-id? s) (not (identifier-item? it)))
                    (loop (cdr slots) prev rest n))
                  ((and (slot-requires-list? s) (not (list-item? it))) #f)
                  (else (loop (cdr slots) it (cdr rest) (+ n 1))))))))))

;; Give each item the style its position calls for. `head?` says whether the
;; first item is a keyword that takes no slot, which is true of a headed form
;; and false of a list being styled from a data position.
(define (assign-styles items shape head?)
  (let ((tail-s (tail-style (styled-tail shape))))
    (let loop ((in items) (slots (styled-slots shape)) (head? head?) (out '()))
      (cond
        ((null? in) (reverse out))
        ;; The keyword, and any trivia item, keeps the default: trivia are
        ;; leaves, on which every style agrees, and they must not consume a slot.
        ((or head? (not (item-datum? (car in))))
          (loop (cdr in) slots #f (cons (car in) out)))
        (else (let ((it (car in)))
                (let skip ((slots slots))
                  (cond
                    ((null? slots)
                      (loop (cdr in) '() #f (cons (item-with-style it tail-s) out)))
                    ((and (slot-optional-id? (car slots)) (not (identifier-item? it)))
                      (skip (cdr slots)))
                    (else (loop (cdr in)
                                (cdr slots)
                                #f
                                (cons (item-with-style it (slot-style (car slots)))
                                      out)))))))))))

;;; Compound nodes

(define (compound-doc node tbl)
  (let ((shape (compound-shape node tbl))
        (items (children->items (compound-children node) blank-cap-inside)))
    (cond
      ((eq? shape 'fill) (fill-body node items tbl))
      ((eq? shape 'generic) (generic-body node items tbl))
      (else
        ;; A dot has no place in any slot, and a styled form is never improper in
        ;; practice, so the whole form degrades rather than the dot being
        ;; special-cased into the match.
        (let ((k (and (not (has-dot? node)) (styled-slot-count items shape))))
          (if k
              (styled-body node (assign-styles items shape #t) shape k tbl)
              (generic-body node items tbl)))))))

;; A list in a data position: no lookup, and its elements styled by `shape` when
;; there is one. Which of three renderings it takes turns on whether its style
;; distinguishes a first element, and that is exactly what its slot list says.
;;
;;   a slot     the first element is distinguished -- it is a clause's test, or
;;              guard's condition variable -- so the generic shape applies with
;;              that element as the head, and a clause needs no emitter of its
;;              own
;;   no slots,  every element is a peer described by a starred tail: a binding
;;   no fill    list. Aligned at the first element, one per line
;;   no slots,  peers again, but formals, literals, definition heads and
;;   fill       bytevectors, where one element per line is nobody's intent
;;
;; The middle case is the one this dispatch originally missed, and the comment
;; that stood here said the missing thing out loud: that a headless list "has no
;; keyword, so its first element plays that part". True of a clause. False of a
;; binding list, where treating binding 1 as a head welds binding 2 to it and
;; staircases the rest off binding 2's column.
(define (headless-doc node shape tbl)
  (let* ((raw (children->items (compound-children node) blank-cap-inside))
         (items (if shape (assign-styles raw shape #f) raw)))
    (cond
      ((or (bytevector-node? node)
           (and shape (null? (styled-slots shape)) (tail-fill? (styled-tail shape))))
        (fill-body node items tbl))
      ((and shape (null? (styled-slots shape))) (peer-body node items tbl))
      (else (generic-body node items tbl)))))

(define (open-doc node) (leaf-doc (compound-open node)))

(define (close-doc node)
  (if (compound-close node) (leaf-doc (compound-close node)) empty-doc))

;; The whole node is wrapped in align, so its indentation is the column its
;; opening delimiter was laid out at. That is what puts a closing delimiter
;; forced onto its own line -- by a trailing line comment -- underneath the
;; opening one, and it is what a broken body's indent is measured from.
(define (whole node body)
  (align (concat (open-doc node) (concat body (close-doc node)))))

;; The generic shape: three candidate layouts, and the cost objective chooses
;; among them over the whole document rather than greedily at each node. That
;; global choice is the entire reason the Pi-e engine was ported: a Wadler-style
;; group commits to the flat rendering whenever it fits and cannot see the cost
;; that imposes further down.
;;
;;   flat      (f a b c)
;;   aligned   (f a          hanging   (f
;;                b                      a
;;                c)                     b
;;                                       c)
;;
;; This is the fallback for every form a table does not match, which is why it
;; had to exist and be correct before the table did.
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
(define (generic-body node items tbl)
  (cond
    ((null? items) (concat (open-doc node) (close-doc node)))
    ((null? (cdr items)) (group (whole node (item-doc (car items) tbl))))
    ;; The aligned shape captures its indentation at the column after the head,
    ;; which is only the first argument's column if nothing forced a break
    ;; inside the head. A trailing line comment on the head does force one --
    ;; `(a ; note` -- and then the alignment would be captured at the start of
    ;; the next line, putting the arguments at column zero where they read as
    ;; new top-level forms. Hanging measures from the opening delimiter through
    ;; `whole`'s align, which is entered before any content and so cannot be
    ;; moved by a break, so it is the shape that survives.
    ((not (eq? (gap (car items) (cadr items) space) space))
      (group (whole node (hanging-body items tbl))))
    (else (alternatives (group (whole node (aligned-body items tbl)))
                        (whole node (hanging-body items tbl))))))

;; The head and the first argument share the opening line; the rest begin at the
;; first argument's column. The separator between the two is a hard space, so
;; there is no break to choose there -- that choice is what the hanging
;; alternative is.
(define (aligned-body items tbl)
  (let ((head (car items)) (rest (cdr items)))
    (concat (item-doc head tbl)
            (concat (gap head (car rest) space) (align (join-items rest nl tbl))))))

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
(define (hanging-body items tbl)
  (let ((head (car items)) (rest (cdr items)))
    (nest hanging-indent
          (concat (item-doc head tbl)
                  (concat (gap head (car rest) nl) (join-items rest nl tbl))))))

;; A matched style: the head and every slot share the opening line, joined by
;; spaces at which no break may be taken, and the tail is laid out beneath at
;; the body indent. Wrapped in `group`, so the form denotes the all-flat
;; rendering and the fully-broken one and nothing between.
;;
;; Exactly two layouts is worth noticing. The generic shape offers three and
;; needs an argument that two of them can never tie; a styled form needs no such
;; argument, because its two candidates differ in height *and* in width. Adding
;; a style to a form removes work from the cost objective rather than adding a
;; tie for it to break.
;;
;; The head and slots sit inside the nest for the same reason the hanging shape
;; puts its head there: a break emitted from inside the head -- which only a
;; trailing comment can do, and only when the style has no slots, since a
;; comment among the slots withdraws the style -- must land at the body indent
;; rather than at column zero.
;;
;; The gap between the last slot and the tail is a soft newline even for a fill
;; tail. Letting it join the fill would allow the first element to stay on the
;; keyword's line while later ones sat at the body indent, which reads as two
;; different shapes at once.
;; The indent comes off the tail terminal rather than from the constant: two
;; values exist and the terminal is the only thing that selects between them.
;; No branch here, and no head symbol -- substituting the accessor for the
;; constant is the whole of it.
(define (styled-body node items shape k tbl)
  (let ((sep (if (tail-fill? (styled-tail shape)) fill-sep nl)))
    (let-values (((head rest) (split-items items (+ k 1))))
      (group (whole node
                    (nest (tail-indent (styled-tail shape))
                          (if (null? rest)
                              (join-items head space tbl)
                              (concat (join-items head space tbl)
                                      (concat (gap (last-item head) (car rest) nl)
                                              (join-items rest sep tbl))))))))))

;; A filled list: every element packed onto as few lines as the width allows,
;; with wrapped lines under the first element. This is the shape for formals,
;; literals, definition heads and bytevectors -- lists of names, literals or
;; octets, where one per line is nobody's intent.
(define (fill-body node items tbl)
  (if (null? items)
      (concat (open-doc node) (close-doc node))
      (whole node (align (join-items items fill-sep tbl)))))

;; A list of peers: the same construction as fill-body with the separator that
;; breaks every gap together rather than each independently, plus a `group` for
;; the flat rendering. This is a binding list.
;;
;; TWO RENDERINGS, NOT THREE. The generic shape offers hanging so a head can sit
;; alone on the opening line with its arguments beneath. A peer list has no head,
;; so hanging would mean `(let (` with the bindings two columns in, which nothing
;; in either community writes. Withholding it also keeps this shape free of the
;; tie-break the generic one needed: flat and aligned differ in both width and
;; height, so no ordering question arises.
;;
;; `align` is entered immediately after the opening delimiter, so it captures the
;; first element's column and a break forced inside that element -- by a trailing
;; comment -- cannot move it. That is the same argument fill-body relies on, and
;; it is why neither needs the hanging fallback the generic shape keeps for
;; exactly that case.
(define (peer-body node items tbl)
  (if (null? items)
      (concat (open-doc node) (close-doc node))
      (group (whole node (align (join-items items nl tbl))))))

;;; Prefix nodes

;; The marker and its datum are concatenated with nothing between them, so a
;; break can never appear between an abbreviation and what it abbreviates. When
;; trivia sit between the two they are sequenced normally, but joined with a
;; hard space rather than a soft newline: the only line break that may separate
;; a marker from its datum is one a comment forced.
(define (prefix-doc node tbl)
  (let* ((marker (prefix-marker node))
         (datum (prefix-datum node))
         ;; Whitespace between the marker and its datum is discarded like any
         ;; other, so `'  x` binds as tightly as `'x`. The test is on the items,
         ;; not on the raw children: a child sequence holding nothing but
         ;; whitespace produces no items at all.
         (mid (children->items (prefix-children node) blank-cap-inside)))
    (if (null? mid)
        (if datum (concat (leaf-doc marker) (node-doc datum tbl)) (leaf-doc marker))
        (let* ((head (make-item (list marker) 0 #f #f #f #t 'expression #f))
               (items (if datum
                          (append (cons head mid)
                                  (list (make-item (list datum)
                                                   0
                                                   (node-broken? datum)
                                                   #f
                                                   #f
                                                   #t
                                                   'expression
                                                   #f)))
                          (cons head mid))))
          (join-items items space tbl)))))

;;; Error nodes

;; Every token the malformed region covers, emitted in order. Never formatted in
;; practice -- the pipeline refuses an unclean parse -- but the translation is
;; total over the node kinds, and a test that translates a malformed tree should
;; get a document rather than an exception.
(define (error-doc node tbl)
  (let ((items (children->items (error-node-children node) blank-cap-inside)))
    (if (null? items) empty-doc (join-items items space tbl))))

;;; The document node

;; Top-level forms are separated by a hard break: two of them never share a
;; line, and the forced separator also keeps the resolver from exploring choices
;; across them, which is what keeps a whole file's frontier from compounding.
;;
;; The file ends with exactly one line ending. A last item that already ends in
;; a forced break -- a file ending in a line comment -- has one, and adding
;; another would leave a blank line at end of file.
(define (document-doc node tbl)
  (let ((items (children->items (document-children node) blank-cap-top)))
    (if (null? items)
        empty-doc
        (concat (join-items items hard-nl tbl)
                (if (last-item-broken? items) empty-doc hard-nl)))))

;;; Entry point

;; Configuration and dialect selection happen at the caller's edge. Translation
;; sees only the immutable data interface it needs.
(define (cst->document node table) (node-doc node table))))
