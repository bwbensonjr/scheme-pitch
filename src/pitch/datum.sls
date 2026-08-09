;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The datum projection: a CST to ordinary host Scheme data.
;;
;; The result is pairs, vectors, bytevectors, symbols, strings, characters,
;; numbers, booleans and the empty list -- nothing of our own. That is the
;; point: comparing two projections is then equal?, which R6RS requires to
;; terminate on circular arguments, so the comparator in a checking layer is
;; not code we wrote.
;;
;; Every leaf's contribution is token-value, the value the lexer already
;; computed. There is no number parser, string unescaper or character-name
;; table here, and there must not be: a second lexer would have to be kept in
;; agreement with the first. It also makes #!fold-case correct for free, since
;; folding happened at lex time and the directive folds both sides of a
;; comparison identically without this file knowing it exists.
;;
;; The information this deliberately loses -- radix, escape spelling, bracket
;; shape, abbreviations, comments -- is exactly what makes datum equivalence
;; the weaker check. It is kept because it is an independent code path from
;; token equivalence, not because it is strong.
;;
;; This is also where defects become visible that structure cannot show. The
;; parser sees brackets; it does not resolve datum labels or check that a
;; bytevector element is an octet, so (#1#) and #vu8(300) both parse clean.
;; They are reported here, on the same diagnostic channel the parser uses.
;;
;; Nothing here branches on dialect: #vu8( and #u8( project alike.

#!r6rs

(library (pitch datum)
(export cst->datum)
(import
  (rnrs base (6))
  (rnrs control (6))
  (rnrs lists (6))
  (rnrs hashtables (6))
  (rnrs bytevectors (6))
  (rnrs mutable-pairs (6)) ;to tie the knot on #0= cycles
  (rnrs records syntactic (6))
  (pitch cst)
  (pitch diagnostic)
  (only (pitch reader) token-value))

;; A datum reference stands in for its target until the enclosing top-level
;; datum is built and the patchers run. It never survives into a returned
;; datum unless the reference was unresolvable, which is diagnosed.
(define-record-type placeholder
  (fields label)
  (sealed #t)
  (opaque #f)
  (nongenerative placeholder-v0-9a3c1e77-5f24-4a1b-8c60-0d5b6e2f4a13))

;; A unique object meaning "this node contributes no datum at all", as
;; distinct from contributing #f. Containers drop it.
(define omitted (list 'omitted))

;; Returns two values: the top-level data in source order, and diagnostics.
;; Never raises: where a node cannot be projected it is diagnosed and dropped.
(define (cst->datum document)
  (let ((diagnostics '())
        (labels #f) ;fresh per top-level datum
        (patchers '()))

    (define (diagnose! msg node)
      (set! diagnostics (cons (make-diagnostic msg (anchor-token node)) diagnostics)))

    ;; Diagnostics report a token, and any node's first leaf is the token a
    ;; human would point at.
    (define (anchor-token node) (leaf-token (car (cst-leaves node))))

    (define (register-patch! label node proc)
      (set! patchers (cons (list label node proc) patchers)))

    ;; Run after the enclosing top-level datum exists, which is what lets a
    ;; reference resolve to a datum that contains it.
    (define (resolve-patches!)
      (for-each (lambda (p)
                  (let ((label (car p)) (node (cadr p)) (proc (caddr p)))
                    (if (hashtable-contains? labels label)
                        (proc (hashtable-ref labels label #f))
                        (diagnose! "Datum reference with no matching label" node))))
                (reverse patchers)))

    ;; Children that can contribute a datum. Trivia contribute nothing, and
    ;; #; needs no rule of its own: the lexer made it one opaque trivia leaf,
    ;; so the datum it elides is already absent. Error nodes hold tokens the
    ;; parser could not place, and contribute nothing either.
    (define (projectable node) (remp error-node? (datum-children node)))

    (define (before-dot cs)
      (let loop ((cs cs) (acc '()))
        (cond
          ((null? cs) (reverse acc))
          ((dot-leaf? (car cs)) (reverse acc))
          (else (loop (cdr cs) (cons (car cs) acc))))))

    (define (after-dot cs)
      (let loop ((cs cs))
        (cond
          ((null? cs) #f)
          ((dot-leaf? (car cs)) (and (pair? (cdr cs)) (cadr cs)))
          (else (loop (cdr cs))))))

    ;; Returns (values datum ref), where ref is a label number when the datum
    ;; is an unresolved reference and #f otherwise. The caller owns the slot
    ;; the datum goes into, so the caller is what can register a patcher.
    (define (project node)
      (cond
        ((leaf? node) (project-leaf node))
        ((compound? node)
          (case (compound-kind node)
            ((list) (project-list node))
            ((vector) (project-vector node))
            ((bytevector) (project-bytevector node))
            (else (assertion-violation 'cst->datum "Unknown compound" node))))
        ((prefix? node) (project-prefix node))
        (else (values omitted #f))))

    (define (project-leaf node)
      (if (eq? (leaf-kind node) 'reference)
          (let ((n (token-value (leaf-token node)))) (values (make-placeholder n) n))
          (values (token-value (leaf-token node)) #f)))

    ;; Project each child, dropping the ones that contribute nothing.
    ;; Each survivor becomes (datum ref node).
    (define (project-each nodes)
      (let loop ((ns nodes) (acc '()))
        (if (null? ns)
            (reverse acc)
            (let-values (((d ref) (project (car ns))))
              (loop (cdr ns)
                    (if (eq? d omitted) acc (cons (list d ref (car ns)) acc)))))))

    (define (build-chain triples)
      (if (null? triples)
          '()
          (let ((cells (map (lambda (t) (cons (car t) '())) triples)))
            (let link ((cs cells))
              (unless (null? (cdr cs)) (set-cdr! (car cs) (cadr cs)) (link (cdr cs))))
            (for-each
              (lambda (t cell)
                (when (cadr t)
                  (register-patch! (cadr t) (caddr t) (lambda (v) (set-car! cell v)))))
              triples
              cells)
            (car cells))))

    (define (last-cell chain) (if (null? (cdr chain)) chain (last-cell (cdr chain))))

    (define (project-list node)
      (let* ((cs (projectable node))
             (improper? (list-improper? node))
             ;; A dot outside a valid tail position was diagnosed at parse
             ;; time. It names no datum, so it is dropped rather than
             ;; projected to some invented value.
             (elems (if improper? (before-dot cs) (remp dot-leaf? cs)))
             (tail (and improper? (after-dot cs)))
             (chain (build-chain (project-each elems))))
        (when (and tail (pair? chain))
          (let-values (((d ref) (project tail)))
            (unless (eq? d omitted)
              (let ((cell (last-cell chain)))
                (set-cdr! cell d)
                (when ref (register-patch! ref tail (lambda (v) (set-cdr! cell v))))))))
        (values chain #f)))

    (define (project-vector node)
      (let* ((triples (project-each (remp dot-leaf? (projectable node))))
             (vec (list->vector (map car triples))))
        (let loop ((ts triples) (i 0))
          (unless (null? ts)
            (when (cadr (car ts))
              (register-patch! (cadr (car ts))
                               (caddr (car ts))
                               (lambda (v) (vector-set! vec i v))))
            (loop (cdr ts) (+ i 1))))
        (values vec #f)))

    (define (octet? x) (and (integer? x) (exact? x) (<= 0 x 255)))

    (define (project-bytevector node)
      (let ((octets '()))
        (for-each (lambda (child)
                    (let-values (((d ref) (project child)))
                      (cond
                        ;; A bytevector holds octets, not object slots, so there is
                        ;; nothing for a patcher to write into later.
                        (ref (diagnose! "Datum reference in bytevector" child))
                        ((eq? d omitted))
                        ((octet? d) (set! octets (cons d octets)))
                        (else (diagnose! "Invalid datum in bytevector" child)))))
                  (remp dot-leaf? (projectable node)))
        (values (u8-list->bytevector (reverse octets)) #f)))

    (define (project-prefix node)
      (let ((marker (prefix-marker node)) (target (prefix-datum node)))
        (cond
          ((not target) (diagnose! "Prefix with no datum" marker) (values omitted #f))
          ((eq? (leaf-kind marker) 'label) (project-label marker target))
          (else (project-abbrev marker target)))))

    (define (project-label marker target)
      (let ((n (token-value (leaf-token marker))))
        (let-values (((d ref) (project target)))
          (cond
            ((eq? d omitted) (values omitted #f))
            (else (if (hashtable-contains? labels n)
                      (diagnose! "Duplicate datum label" marker)
                      (hashtable-set! labels n d))
                  ;; ref propagates: #0=#1# labels whatever #1# resolves to,
                  ;; and the slot to patch belongs to our caller.
                  (values d ref))))))

    ;; The abbreviation token's value is already the expansion symbol, so no
    ;; table maps ' to quote.
    (define (project-abbrev marker target)
      (let ((sym (token-value (leaf-token marker))))
        (let-values (((d ref) (project target)))
          (if (eq? d omitted)
              (values omitted #f)
              (let* ((cell (cons d '())) (form (cons sym cell)))
                (when ref (register-patch! ref target (lambda (v) (set-car! cell v))))
                (values form #f))))))

    ;; Labels are scoped to the top-level datum they appear in, as the
    ;; standards require and as read-datum does upstream with a fresh table
    ;; per call.
    (define (project-top node)
      (set! labels (make-eqv-hashtable))
      (set! patchers '())
      (let-values (((d ref) (project node)))
        (resolve-patches!)
        (cond
          ((not ref) d)
          ((hashtable-contains? labels ref) (hashtable-ref labels ref #f))
          (else (diagnose! "Datum reference with no matching label" node) d))))

    (let loop ((ns (remp error-node? (datum-children document))) (acc '()))
      (if (null? ns)
          (values (reverse acc) (sort-diagnostics diagnostics))
          (let ((d (project-top (car ns))))
            (loop (cdr ns) (if (eq? d omitted) acc (cons d acc)))))))))
