;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tokenizing and parsing: source text -> token vector -> CST.
;;
;; The token vector is materialized rather than streamed. It is the artifact
;; the round-trip check and the eventual token-equivalence check both compare
;; against, and having it means a lexer bug can be told from a parser bug by
;; looking at it.
;;
;; Parsing is tolerant. A formatter is run from editors on half-typed buffers,
;; so parse always returns a tree; it never raises on malformed input. What it
;; does not do is guess: no token is inserted, dropped or substituted to make
;; a malformed input well formed. A tree is clean exactly when its diagnostic
;; list is empty, and a future CLI refuses to format an unclean one.
;;
;; The reader runs in rnrs mode, the permissive union, so dialect never causes
;; a rejection, and with reader-tolerant? set, so a lexical error is recorded
;; and lexing continues to end of input.
;;
;; Diagnostics take their position from the token they concern, never from the
;; source information on the reader's conditions. That condition position is
;; built from reader-saved-line and reader-saved-column, which describe the
;; innermost recursive lexer entry rather than the token returned, and are
;; right often enough to be dangerous.

(define-library (pitch parse)
(export tokenize parse-tokens parse-source)
(import
  (scheme base)
  (pitch cst)
  (pitch diagnostic)
  (pitch error)
  (pitch reader)
  (pitch sequence))
(begin

  (define-syntax let-values
    (syntax-rules ()
      ((_ (((name ...) expression)) body ...)
        (call-with-values (lambda () expression) (lambda (name ...) body ...)))))

  ;;; Tokenizing

  ;; Returns two values: a vector of every token through end of file, and a list
  ;; of diagnostics for the lexical errors recovered from along the way.
  ;;
  ;; A warning is raised while the token it concerns is still being built, so it
  ;; is held until get-token returns and then anchored to that token.
  (define (tokenize source filename)
    (let ((reader (make-reader (open-input-string source) filename))
          (pending '())
          (tokens '())
          (diagnostics '()))
      (reader-tolerant?-set! reader #t)
      (with-exception-handler
        (lambda (raised)
          (if (reader-error? raised)
              (set! pending (cons (pitch-error-message raised) pending))
              (raise raised)))
        (lambda ()
          (let loop ()
            (let ((tok (get-token reader)))
              (set! tokens (cons tok tokens))
              (unless (null? pending)
                (for-each
                  (lambda (msg)
                    (set! diagnostics (cons (make-diagnostic msg tok) diagnostics)))
                  (reverse pending))
                (set! pending '()))
              (unless (eq? (token-kind tok) 'eof) (loop))))))
      (values (list->vector (reverse tokens)) (reverse diagnostics))))

  ;;; Parsing

  (define (open-kind? k) (memq k '(openp openb vector bytevector)))
  (define (close-kind? k) (memq k '(closep closeb)))
  (define (marker-kind? k) (memq k '(abbrev label)))

  ;; A bracketed list closes with a bracket; everything else closes with a
  ;; parenthesis. #vu8( and #u8( close with ) like #( does.
  (define (expected-close open-kind) (if (eq? open-kind 'openb) 'closeb 'closep))

  (define (trivia-kind? k)
    (memq k '(whitespace comment nested-comment inline-comment directive shebang)))

  ;; Returns two values: the document node, and the diagnostics in source order.
  (define (parse-tokens tokens)
    (let ((n (vector-length tokens)) (diagnostics '()))

      (define (tok-at i) (vector-ref tokens i))
      (define (kind-at i) (token-kind (tok-at i)))

      (define (diagnose! msg tok)
        (set! diagnostics (cons (make-diagnostic msg tok) diagnostics)))

      ;; Build a sequence of children. At the top level a stray close delimiter
      ;; becomes an error node and parsing continues; inside a node it ends the
      ;; sequence and the caller decides whether it matched. Either way the
      ;; token is kept. Returns the children and the index of the token that
      ;; stopped the sequence, which is never consumed here.
      (define (parse-items i top?)
        (let loop ((i i) (acc '()))
          (let ((k (kind-at i)))
            (cond
              ((eq? k 'eof) (values (reverse acc) i))
              ((close-kind? k)
                (if top?
                    (let ((msg "Unexpected closing delimiter"))
                      (diagnose! msg (tok-at i))
                      (loop
                        (+ i 1)
                        (cons
                          (make-error-node (tok-at i) msg (list (make-leaf (tok-at i))))
                          acc)))
                    (values (reverse acc) i)))
              (else (let-values (((node j) (parse-item i)))
                      (loop j (cons node acc))))))))

      (define (parse-item i)
        (let ((k (kind-at i)))
          (cond
            ((open-kind? k) (parse-compound i))
            ((marker-kind? k) (parse-prefix i))
            (else (values (make-leaf (tok-at i)) (+ i 1))))))

      (define (parse-compound i)
        (let* ((open-tok (tok-at i))
               (open-kind (token-kind open-tok))
               (open (make-leaf open-tok)))
          (let-values (((children j) (parse-items (+ i 1) #f)))
            (if (eq? (kind-at j) 'eof)
                ;; Nothing is synthesized to stand in for the missing
                ;; delimiter; the absent close is the representation.
                (begin
                  (diagnose! "Unclosed delimiter at end of input" open-tok)
                  (values (finish-compound open children #f) j))
                (let ((close-tok (tok-at j)))
                  (unless (eq? (token-kind close-tok) (expected-close open-kind))
                    (diagnose! "Mismatched closing delimiter" close-tok))
                  (values (finish-compound open children (make-leaf close-tok))
                          (+ j 1)))))))

      (define (finish-compound open children close)
        (let ((node (make-compound open children close))) (check-dots! node) node))

      ;; A dot must have at least one datum before it, exactly one after, and no
      ;; second dot. Violations are reported; the leaf stays where it is.
      (define (check-dots! node)
        (let* ((data (datum-children node)) (dots (filter dot-leaf? data)))
          (unless (null? dots)
            (cond
              ((not (list-node? node))
                (for-each
                  (lambda (d) (diagnose! "Dot is not allowed here" (leaf-token d)))
                  dots))
              ((not (null? (cdr dots)))
                (for-each
                  (lambda (d) (diagnose! "More than one dot in a list" (leaf-token d)))
                  dots))
              (else (let ((k (position-of (car dots) data))
                          (len (length data))
                          (dot-tok (leaf-token (car dots))))
                      (when (= k 0) (diagnose! "Dot with no datum before it" dot-tok))
                      (unless (= len (+ k 2))
                        (diagnose! "Dot must be followed by exactly one datum"
                                   dot-tok))))))))

      (define (position-of x xs)
        (let loop ((i 0) (xs xs))
          (cond ((null? xs) #f) ((eq? (car xs) x) i) (else (loop (+ i 1) (cdr xs))))))

      (define (parse-prefix i)
        (let ((marker-tok (tok-at i)))
          (let loop ((j (+ i 1)) (triv '()))
            (let ((k (kind-at j)))
              (cond
                ((trivia-kind? k) (loop (+ j 1) (cons (make-leaf (tok-at j)) triv)))
                ((or (eq? k 'eof) (close-kind? k))
                  (diagnose! "Prefix with no datum" marker-tok)
                  (values (make-prefix (make-leaf marker-tok) (reverse triv) #f) j))
                (else (let-values (((datum j) (parse-item j)))
                        (values
                          (make-prefix (make-leaf marker-tok) (reverse triv) datum)
                          j))))))))

      (unless (and (> n 0) (eq? (kind-at (- n 1)) 'eof))
        (error "token vector must end in eof"))
      (let-values (((children i) (parse-items 0 #t)))
        (values (make-document children (make-leaf (tok-at i)))
                (sort-diagnostics diagnostics)))))

  ;; Tokenize and parse. Lexical and structural diagnostics are merged into one
  ;; list in source order.
  (define (parse-source source filename)
    (let-values (((tokens lex-diagnostics) (tokenize source filename)))
      (let-values (((document parse-diagnostics) (parse-tokens tokens)))
        (values document
                (sort-diagnostics (append lex-diagnostics parse-diagnostics))))))))
