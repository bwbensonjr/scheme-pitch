;; -*- mode: scheme; coding: utf-8 -*-
;; Benchmark corpus member: hand-written code, 1 copies of the unit.
;;
;; Not compiled, not installed, not part of the correctness suite.
;; Assembled by tools/generate-bench-corpus.sh from pitch sources at
;; 4ad63ecbea6e9eb8a6bfed1a5c44328a7eef16fd. Do not edit by hand.

;; ---- src/pitch/cst.sld, copy 0 ----

;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The concrete syntax tree.
;;
;; A leaf holds exactly one reader token. An interior node holds an ordered
;; sequence of children. Whitespace, comments, #; datum comments, directives
;; and the shebang line are ordinary members of that sequence, in source
;; order, not trivia attached to a neighbouring token. That is what makes
;;
;;   (cst->text (parse-source s)) = s
;;
;; true by construction rather than by discipline: there is no attachment
;; decision at which a comment can be dropped.
;;
;; A leaf's text is its token's text. Offsets and line/column stay reachable
;; through the token for diagnostics, but no node stores text of its own that
;; could disagree with the token. For the same reason nothing derivable is
;; stored: bracket shape is read from the delimiter tokens' kinds, and a
;; compound node's kind is read from its opening token. A second copy of a
;; fact is a second thing that can be wrong.
;;
;; Nothing here branches on dialect. #vu8( and #u8( produce the same node
;; kind; the spelling difference lives in the opening token's text.

(define-library (bench cst-0)
(export
  ;; leaves
  make-leaf leaf? leaf-token leaf-text leaf-kind
  ;; interior nodes
  make-document document? document-children document-eof make-compound compound?
  compound-open compound-children compound-close compound-kind make-prefix prefix?
  prefix-marker prefix-children prefix-datum make-error-node error-node?
  error-node-token error-node-message error-node-children
  ;; generic
  cst-node? node-kind node-children list-node? vector-node? bytevector-node?
  ;; classification
  trivia? datum-children dot-leaf? list-improper?
  ;; serialization
  cst-leaves cst-tokens cst->text write-cst)
(import (scheme base) (bench reader-0) (bench sequence-0))
(begin

  ;;; Node types

  ;; One token. The token is the authority for this node's text.
  (define-record-type <leaf> (make-leaf token) leaf? (token leaf-token))

  ;; The whole source. The end-of-file leaf is held so that the tree's leaves
  ;; are exactly the token vector; its text is empty, so it costs nothing.
  (define-record-type <document> (make-document children eof) document?
    (children document-children)
    (eof document-eof))

  ;; A list, vector or bytevector. close is #f when the delimiter was never
  ;; closed in the source. The kind is derived from open, not stored.
  (define-record-type <compound> (make-compound open children close) compound?
    (open compound-open)
    (children compound-children)
    (close compound-close))

  ;; An abbreviation ('x, `x, ,x, ,@x and their syntax forms) or a datum label
  ;; (#0=). children are the trivia between the marker and the datum; datum is
  ;; #f when the marker had nothing to prefix.
  (define-record-type <prefix> (make-prefix marker children datum) prefix?
    (marker prefix-marker)
    (children prefix-children)
    (datum prefix-datum))

  ;; A malformed region. Holds every token it covers, so serializing is
  ;; unaffected by the malformation.
  (define-record-type <error-node> (make-error-node token message children) error-node?
    (token error-node-token)
    (message error-node-message)
    (children error-node-children))

  ;;; Generic accessors

  (define (cst-node? x)
    (or (leaf? x) (document? x) (compound? x) (prefix? x) (error-node? x)))

  (define (leaf-text x) (token-text (leaf-token x)))
  (define (leaf-kind x) (token-kind (leaf-token x)))

  ;; Derived from the opening token rather than stored, so it cannot disagree
  ;; with the text. Bracket shape is read the same way, from openp vs openb.
  (define (compound-kind node)
    (case (leaf-kind (compound-open node))
      ((openp openb) 'list)
      ((vector) 'vector)
      ((bytevector) 'bytevector)
      (else (error "Not an opening delimiter" (leaf-kind (compound-open node))))))

  (define (node-kind node)
    (cond
      ((leaf? node) 'leaf)
      ((document? node) 'document)
      ((compound? node) (compound-kind node))
      ((prefix? node) 'prefix)
      ((error-node? node) 'error)
      (else (error "Not a CST node" node))))

  ;; The interior children only. Delimiters, prefix markers, prefixed data and
  ;; the end-of-file leaf are reached through their own accessors.
  (define (node-children node)
    (cond
      ((leaf? node) '())
      ((document? node) (document-children node))
      ((compound? node) (compound-children node))
      ((prefix? node) (prefix-children node))
      ((error-node? node) (error-node-children node))
      (else (error "Not a CST node" node))))

  (define (list-node? x) (and (compound? x) (eq? (compound-kind x) 'list)))
  (define (vector-node? x) (and (compound? x) (eq? (compound-kind x) 'vector)))
  (define (bytevector-node? x) (and (compound? x) (eq? (compound-kind x) 'bytevector)))

  ;;; Classification

  ;; Everything that occupies source but is not a datum. #; is here because the
  ;; lexer has already made it one opaque token spanning the commented datum.
  (define (trivia? node)
    (and (leaf? node)
         (memq (leaf-kind node)
               '(whitespace comment nested-comment inline-comment directive shebang))
         #t))

  (define (datum-children node)
    (filter (lambda (c) (not (trivia? c))) (node-children node)))

  (define (dot-leaf? node) (and (leaf? node) (eq? (leaf-kind node) 'dot)))

  ;; True for a list whose dot is in a valid tail position: at least one datum
  ;; before it, exactly one after, and no second dot. The dot is an ordinary
  ;; child, so this is a question about the child sequence rather than about a
  ;; field that construction had to get right.
  (define (list-improper? node)
    (and (list-node? node)
         (let* ((data (datum-children node)) (n (length data)))
           (let loop ((i 0) (xs data) (dot #f))
             (cond
               ((null? xs) (and dot (= n (+ dot 2))))
               ((dot-leaf? (car xs)) (and (not dot) ;a second dot is not a tail
                                          (> i 0) ;nothing to be the head
                                          (loop (+ i 1) (cdr xs) i)))
               (else (loop (+ i 1) (cdr xs) dot)))))))

  ;;; Serialization

  ;; The leaves in source order. This sequence is exactly the token vector the
  ;; tree was parsed from, which is the sharper form of the round-trip
  ;; invariant: when it fails it names the token that moved.
  (define (cst-leaves node)
    (define (walk node acc) ;acc is reversed
      (cond
        ((leaf? node) (cons node acc))
        ((document? node) (cons (document-eof node)
                                (walk* (document-children node) acc)))
        ((compound? node)
          (let ((acc (walk* (compound-children node) (cons (compound-open node) acc))))
            (if (compound-close node) (cons (compound-close node) acc) acc)))
        ((prefix? node)
          (let ((acc (walk* (prefix-children node) (cons (prefix-marker node) acc))))
            (if (prefix-datum node) (walk (prefix-datum node) acc) acc)))
        ((error-node? node) (walk* (error-node-children node) acc))
        (else (error "Not a CST node" node))))
    (define (walk* nodes acc)
      (if (null? nodes) acc (walk* (cdr nodes) (walk (car nodes) acc))))
    (reverse (walk node '())))

  (define (cst-tokens node) (map leaf-token (cst-leaves node)))

  (define (write-cst node port)
    (for-each (lambda (l) (write-string (leaf-text l) port)) (cst-leaves node)))

  ;; Reproduces; does not format. No character is inserted, removed or moved.
  (define (cst->text node)
    (let ((port (open-output-string)))
      (write-cst node port)
      (get-output-string port)))))

;; ---- src/pitch/table.sld, copy 0 ----

;;; Tables with the three equality contracts Pitch needs.
(define-library (bench table-0)
(export
  make-symbol-table make-integer-table make-identity-table table? table-ref table-set!
  table-update! table-delete! table-contains? table-size table-keys table-entries
  table-copy)
(import (scheme base))
(begin
  (define-record-type <table> (make-table kind storage) table?
    (kind table-kind)
    (storage table-storage))

  (define (make-symbol-table) (make-table 'symbol (make-hash-table)))
  (define (make-integer-table) (make-table 'integer (make-hash-table)))

  ;; Identity tables use Emit's eq?-keyed table so distinct document records
  ;; remain distinct and cyclic keys require no structural traversal.
  (define (make-identity-table) (make-table 'identity (make-eq-hash-table)))

  (define (check-key table key)
    (case (table-kind table)
      ((symbol) (if (symbol? key) #t (error 'table "expected symbol key" key)))
      ((integer) (if (integer? key) #t (error 'table "expected integer key" key)))
      (else #t)))

  (define (table-ref table key default)
    (check-key table key)
    (hash-table-ref/default (table-storage table) key default))

  (define (table-contains? table key)
    (check-key table key)
    (hash-table-contains? (table-storage table) key))

  (define (table-set! table key value)
    (check-key table key)
    (hash-table-set! (table-storage table) key value))

  (define (table-update! table key update default)
    (table-set! table key (update (table-ref table key default))))

  (define (table-delete! table key)
    (check-key table key)
    (hash-table-delete! (table-storage table) key))

  (define (table-size table) (hash-table-size (table-storage table)))

  (define (table-keys table) (hash-table-keys (table-storage table)))

  (define (table-entries table)
    (let ((entries (hash-table->alist (table-storage table))))
      (values (list->vector (map car entries)) (list->vector (map cdr entries)))))

  (define (table-copy table)
    (let ((copy (case (table-kind table)
                  ((symbol) (make-symbol-table))
                  ((integer) (make-integer-table))
                  (else (make-identity-table)))))
      (for-each (lambda (entry) (table-set! copy (car entry) (cdr entry)))
                (hash-table->alist (table-storage table)))
      copy))))

