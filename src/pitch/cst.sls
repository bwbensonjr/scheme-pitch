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

#!r6rs

(library (pitch cst)
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
(import
  (rnrs base (6))
  (rnrs control (6))
  (rnrs lists (6))
  (rnrs records syntactic (6))
  (only (rnrs io ports (6)) put-string call-with-string-output-port)
  (only (pitch reader) token? token-kind token-text))

;;; Node types

;; One token. The token is the authority for this node's text.
(define-record-type leaf
  (fields token)
  (sealed #t)
  (opaque #f)
  (nongenerative leaf-v0-2d492370-7759-478b-99cd-7e3a6a2cfc89))

;; The whole source. The end-of-file leaf is held so that the tree's leaves
;; are exactly the token vector; its text is empty, so it costs nothing.
(define-record-type document
  (fields children eof)
  (sealed #t)
  (opaque #f)
  (nongenerative document-v0-a5a42a61-d8be-46fe-bc41-75a2a14ec9f4))

;; A list, vector or bytevector. close is #f when the delimiter was never
;; closed in the source. The kind is derived from open, not stored.
(define-record-type compound
  (fields open children close)
  (sealed #t)
  (opaque #f)
  (nongenerative compound-v0-c1789c3f-c689-4791-8c63-df7a3e23fd52))

;; An abbreviation ('x, `x, ,x, ,@x and their syntax forms) or a datum label
;; (#0=). children are the trivia between the marker and the datum; datum is
;; #f when the marker had nothing to prefix.
(define-record-type prefix
  (fields marker children datum)
  (sealed #t)
  (opaque #f)
  (nongenerative prefix-v0-25132d85-a285-4345-ba69-f9d27d6e7a9c))

;; A malformed region. Holds every token it covers, so serializing is
;; unaffected by the malformation.
(define-record-type error-node
  (fields token message children)
  (sealed #t)
  (opaque #f)
  (nongenerative error-node-v0-402c4dca-f598-4b16-ac75-058ae991d2f3))

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
    (else (assertion-violation 'compound-kind
                               "Not an opening delimiter"
                               (leaf-kind (compound-open node))))))

(define (node-kind node)
  (cond
    ((leaf? node) 'leaf)
    ((document? node) 'document)
    ((compound? node) (compound-kind node))
    ((prefix? node) 'prefix)
    ((error-node? node) 'error)
    (else (assertion-violation 'node-kind "Not a CST node" node))))

;; The interior children only. Delimiters, prefix markers, prefixed data and
;; the end-of-file leaf are reached through their own accessors.
(define (node-children node)
  (cond
    ((leaf? node) '())
    ((document? node) (document-children node))
    ((compound? node) (compound-children node))
    ((prefix? node) (prefix-children node))
    ((error-node? node) (error-node-children node))
    (else (assertion-violation 'node-children "Not a CST node" node))))

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
      ((document? node) (cons (document-eof node) (walk* (document-children node) acc)))
      ((compound? node)
        (let ((acc (walk* (compound-children node) (cons (compound-open node) acc))))
          (if (compound-close node) (cons (compound-close node) acc) acc)))
      ((prefix? node)
        (let ((acc (walk* (prefix-children node) (cons (prefix-marker node) acc))))
          (if (prefix-datum node) (walk (prefix-datum node) acc) acc)))
      ((error-node? node) (walk* (error-node-children node) acc))
      (else (assertion-violation 'cst-leaves "Not a CST node" node))))
  (define (walk* nodes acc)
    (if (null? nodes) acc (walk* (cdr nodes) (walk (car nodes) acc))))
  (reverse (walk node '())))

(define (cst-tokens node) (map leaf-token (cst-leaves node)))

(define (write-cst node port)
  (for-each (lambda (l) (put-string port (leaf-text l))) (cst-leaves node)))

;; Reproduces; does not format. No character is inserted, removed or moved.
(define (cst->text node)
  (call-with-string-output-port (lambda (port) (write-cst node port)))))
