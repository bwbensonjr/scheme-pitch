;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The layout engine: given a document and a cost objective, the cheapest
;; layout the document denotes.
;;
;; REFERENCE. This is a port of Pi-e from
;;
;;   Sorawee Porncharoenwase, Justin Pombrio, Emina Torlak.
;;   "A Pretty Expressive Printer." OOPSLA 2023.
;;
;; following the authors' Racket implementation, sorawee/pretty-expressive
;; (pretty-expressive-lib/{core,doc,addons,process}.rkt), read at the version
;; installed from the Racket package catalog in 2026-08.
;;
;; Pi-e is chosen over the Wadler/Leijen lineage because Wadler-style `group`
;; commits greedily -- it takes the flat rendering whenever it fits locally,
;; which cannot see the cost that choice imposes downstream. Pi-e instead
;; minimizes a supplied cost objective over the whole document, so pitch's
;; aesthetic preferences live in a cost factory rather than in printer
;; heuristics.
;;
;; DELIBERATE DIVERGENCES from the reference. Each is answer-preserving except
;; the last two, which are noted as such:
;;
;;   1. Memo tables are external and per call, keyed by eq? on the document,
;;      rather than stored on document nodes and cleared afterwards. Documents
;;      stay immutable, the cleanup traversal disappears, and a measure computed
;;      under one cost factory can never be returned under another -- which
;;      would produce a plausible but wrong layout, the one failure mode no
;;      downstream check of ours can detect.
;;   2. Every internal node is memoized. The reference memoizes every seventh,
;;      trading hit rate for memory via a tuned constant we cannot re-tune. This
;;      changes hit rate, not results. It is the first thing to revisit if a
;;      corpus run is slow.
;;   3. Dynamically discovered failure is recorded in the per-call table rather
;;      than mutated onto the document node, for the same reason as (1).
;;   4. A measure carries a difference list of strings rather than a procedure
;;      writing to an output port, so the engine performs no I/O and returns a
;;      string.
;;   5. Optional arguments are case-lambda arities, not Racket parameters, so a
;;      result depends on nothing but its arguments.
;;   6. `special` is not ported. It exists to pass a non-string value through a
;;      Racket structured output port; pitch renders to a string.
;;   7. `text` refuses a line ending. See (pitch doc). The reference does not
;;      check. This is stricter than the reference, not different from it.
;;   8. `flatten` flattens a newline that is the direct child of align, nest or
;;      reset; the reference returns it unflattened. See (pitch doc) for why
;;      that one is a bug rather than a preference. This is the only divergence
;;      where the two implementations disagree on an answer.
;;
;; HOW IT WORKS. A document resolves, relative to a starting column c and an
;; indentation i, to a *measure set*: a Pareto frontier of (last-column, cost,
;; tokens) triples ordered by decreasing last column and increasing cost, with
;; dominated candidates pruned. Concatenation resolves its right operand once
;; per surviving left measure and merges the results. Pruning plus the bound on
;; the last column keeps the frontier small, which is what turns an exponential
;; choice space into a polynomial search.
;;
;; Past the computation width the resolver stops maintaining a frontier at all
;; and produces a single *tainted* measure, computed lazily. That is what bounds
;; the worst case. A tainted result is complete, valid text; what is withdrawn
;; is the claim that it is minimal. It is a different outcome from a document
;; with no layout at all, which raises.

(define-library (pitch layout)
(export
  layout pretty-format layout-result? layout-result-tainted? layout-result-cost
  layout-failure?)
(import
  (scheme base)
  (scheme case-lambda)
  (pitch cost)
  (pitch doc)
  (pitch error)
  (pitch sequence)
  (pitch table))
(begin

  (define-syntax let-values
    (syntax-rules ()
      ((_ () body ...) (begin body ...))
      ((_ (((name ...) producer)) body ...)
        (call-with-values (lambda () producer) (lambda (name ...) body ...)))
      ((_ (((name ...) producer) rest ...) body ...)
        (call-with-values (lambda () producer)
                          (lambda (name ...) (let-values (rest ...) body ...))))))

  ;;; Results

  (define-record-type <layout-result> (make-layout-result tainted? cost) layout-result?
    (tainted? layout-result-tainted?)
    (cost layout-result-cost))

  (define layout-failure? layout-error?)

  (define (raise-layout-failure)
    (raise
      (make-layout-error
        "the document denotes no layout: it is `fail`, or every alternative fails")))

  ;;; Measures
  ;;
  ;; `last` is the column the layout ends at, `cost` its cost under the factory in
  ;; force, and `tokens` a procedure prepending the layout's strings, in reverse
  ;; order, onto an accumulator. Building the text lazily this way means the many
  ;; measures that lose a comparison never pay for their output.

  (define-record-type <measure> (make-measure last cost tokens) measure?
    (last measure-last)
    (cost measure-cost)
    (tokens measure-tokens))

  ;; A tainted measure set: at most one measure, computed on demand. `nl` is the
  ;; document's overapproximated line-break count, used to choose between two
  ;; tainted candidates -- more breaks is the better guess, since the reason we
  ;; are here is that something overflowed.
  (define-record-type <lazy-set> (make-lazy-set nl thunk value done?) lazy-set?
    (nl lazy-set-nl)
    (thunk lazy-set-thunk lazy-set-thunk-set!)
    (value lazy-set-value lazy-set-value-set!)
    (done? lazy-set-done? lazy-set-done?-set!))

  (define (delayed nl thunk) (make-lazy-set nl thunk #f #f))

  (define (force-set ls)
    (if (lazy-set-done? ls)
        (lazy-set-value ls)
        (let ((v ((lazy-set-thunk ls))))
          (lazy-set-value-set! ls v)
          (lazy-set-done?-set! ls #t)
          (lazy-set-thunk-set! ls #f)
          v)))

  ;; A measure set is a list of measures, or a lazy-set. `null?` is total, so it
  ;; is safe to ask of either.
  (define (extract-at-most-one ms)
    (cond ((lazy-set? ms) (force-set ms)) ((null? ms) '()) (else (list (car ms)))))

  ;;; Rendering

  ;; Concatenate a list of strings without an argument-count ceiling and without
  ;; the quadratic behaviour of folding string-append.
  (define (concatenate pieces)
    (let* ((total (fold-left (lambda (n s) (+ n (string-length s))) 0 pieces))
           (out (make-string total)))
      (let loop ((ps pieces) (at 0))
        (if (null? ps)
            out
            (let* ((s (car ps)) (n (string-length s)))
              (let copy ((k 0))
                (if (= k n)
                    (loop (cdr ps) (+ at n))
                    (begin
                      (string-set! out (+ at k) (string-ref s k))
                      (copy (+ k 1))))))))))

  (define (render m) (concatenate (reverse ((measure-tokens m) '()))))

  ;;; Resolution

  ;; Returns the winning measure and whether it is tainted.
  (define (resolve-document d factory offset)
    (let* ((cost<=? (cost-factory-cost<=? factory))
           (cost+ (cost-factory-cost+ factory))
           (cost-text (cost-factory-cost-text factory))
           (cost-nl (cost-factory-cost-nl factory))
           (limit (cost-factory-limit factory))
           (limit+1 (+ limit 1))
           ;; doc -> (eqv hashtable of packed (index, i, c) -> measure set)
           (memo (make-identity-table))
           ;; doc -> set of fullness indexes found to have no layout
           (dynamic-failure (make-identity-table)))

      (define (known-failing? d index)
        (or (doc-fails-statically? d index)
            (if (memv index (table-ref dynamic-failure d '())) #t #f)))

      (define (note-failing! d index)
        (let ((indexes (table-ref dynamic-failure d '())))
          (unless (memv index indexes)
            (table-set! dynamic-failure d (cons index indexes)))))

      (define (dominates? m1 m2)
        (and (<= (measure-last m1) (measure-last m2))
             (cost<=? (measure-cost m1) (measure-cost m2))))

      (define (concat-measure m1 m2)
        (let ((t1 (measure-tokens m1)) (t2 (measure-tokens m2)))
          (make-measure (measure-last m2)
                        (cost+ (measure-cost m1) (measure-cost m2))
                        (lambda (acc) (t2 (t1 acc))))))

      ;; Merge two frontiers, dropping dominated candidates. A concrete candidate
      ;; always beats a tainted one. `prunable?` says the caller knows both sides
      ;; either fail or succeed together, so keeping one tainted candidate is
      ;; enough and no fallback chain is needed.
      (define (merge ms1 ms2 prunable?)
        (cond
          ((null? ms2) ms1)
          ((null? ms1) ms2)
          ((and (lazy-set? ms1) (lazy-set? ms2))
            (let* ((swap? (< (lazy-set-nl ms1) (lazy-set-nl ms2)))
                   (keep (if swap? ms2 ms1))
                   (other (if swap? ms1 ms2)))
              (if prunable?
                  keep
                  (delayed (lazy-set-nl keep)
                           (lambda ()
                             (let ((v (force-set keep)))
                               (if (null? v) (force-set other) v)))))))
          ((lazy-set? ms2) ms1)
          ((lazy-set? ms1) ms2)
          (else (pareto-merge ms1 ms2))))

      (define (pareto-merge ms1 ms2)
        (cond
          ((null? ms1) ms2)
          ((null? ms2) ms1)
          (else (let ((m1 (car ms1)) (m2 (car ms2)))
                  (cond
                    ((dominates? m1 m2) (pareto-merge ms1 (cdr ms2)))
                    ((dominates? m2 m1) (pareto-merge (cdr ms1) ms2))
                    ((> (measure-last m1) (measure-last m2))
                      (cons m1 (pareto-merge (cdr ms1) ms2)))
                    (else (cons m2 (pareto-merge ms1 (cdr ms2)))))))))

      ;; Concatenate a fixed left measure onto each of a right frontier, keeping
      ;; the result a frontier. The right side is ordered by decreasing last
      ;; column, and cost+ is monotone, so a later candidate whose cost is no
      ;; worse dominates the one before it.
      (define (extend-left d a-m b-ms)
        (cond
          ((lazy-set? b-ms)
            (delayed (doc-nl-cnt d)
                     (lambda ()
                       (let ((bv (force-set b-ms)))
                         (if (null? bv) '() (list (concat-measure a-m (car bv))))))))
          ((null? b-ms) '())
          (else (let loop ((best (concat-measure a-m (car b-ms)))
                           (rest (cdr b-ms))
                           (kept '()))
                  (if (null? rest)
                      (reverse (cons best kept))
                      (let ((current (concat-measure a-m (car rest))))
                        (if (cost<=? (measure-cost current) (measure-cost best))
                            (loop current (cdr rest) kept)
                            (loop current (cdr rest) (cons best kept)))))))))

      ;; The memoizing entry point.
      (define (resolve d c i beg-full? end-full?)
        (let ((index (fullness-index beg-full? end-full?)))
          (cond
            ((known-failing? d index) '())
            ;; Past the limit the result is lazy and position-dependent in ways
            ;; the key does not capture, so it is not cached.
            ((or (> c limit) (> i limit))
              (resolve-taint d c i beg-full? end-full? index))
            (else
              (let* ((table (or (table-ref memo d #f)
                                (let ((fresh (make-integer-table)))
                                  (table-set! memo d fresh)
                                  fresh)))
                     (key (+ (* (+ (* index limit+1) i) limit+1) c))
                     (hit (table-ref table key #f)))
                ;; A stored value is a list or a lazy-set, never #f, and the empty
                ;; list is true in Scheme, so absence is unambiguous.
                (or hit
                    (let ((computed (resolve-taint d c i beg-full? end-full? index)))
                      (table-set! table key computed)
                      computed)))))))

      ;; The taint boundary. A text is measured by where it ends, everything else
      ;; by where it starts.
      (define (resolve-taint d c i beg-full? end-full? index)
        (let ((column-pos (if (doc-text? d) (+ c (doc-text-len d)) c)))
          (if (or (> column-pos limit) (> i limit))
              (delayed (doc-nl-cnt d)
                       (lambda ()
                         (let ((r (extract-at-most-one
                                    (resolve-form d c i beg-full? end-full?))))
                           (when (null? r) (note-failing! d index))
                           r)))
              (resolve-form d c i beg-full? end-full?))))

      (define (resolve-form d c i beg-full? end-full?)
        (cond
          ((doc-text? d) (let ((len (doc-text-len d)))
                           (list (make-measure (+ c len)
                                               (cost-text c len)
                                               (lambda (acc) (doc-text-push d acc))))))

          ((doc-newline? d) (list (make-measure i
                                                (cost-nl i)
                                                (lambda (acc)
                                                  (cons (make-string i #\space)
                                                        (cons "\n" acc))))))

          ((doc-concat? d)
            (let ((a (doc-concat-a d)) (b (doc-concat-b d)))
              ;; The boundary between a and b may or may not be constrained to end
              ;; a line; both are tried and merged.
              (define (analyze-left mid-full?)
                (let ((a-ms (resolve a c i beg-full? mid-full?)))
                  (if (lazy-set? a-ms)
                      (delayed (doc-nl-cnt d)
                               (lambda ()
                                 (let ((av (force-set a-ms)))
                                   (if (null? av)
                                       '()
                                       (let* ((a-m (car av))
                                              (bv (extract-at-most-one
                                                    (resolve b
                                                             (measure-last a-m)
                                                             i
                                                             mid-full?
                                                             end-full?))))
                                         (if (null? bv)
                                             '()
                                             (list (concat-measure a-m (car bv)))))))))
                      ;; Resolving a succeeded, so resolving b succeeds or fails
                      ;; uniformly across the starting columns a offers. That is
                      ;; what licenses pruning to a single tainted candidate.
                      (let loop ((ams a-ms))
                        (if (null? ams)
                            '()
                            (let ((a-m (car ams)))
                              (merge
                                (extend-left
                                  d
                                  a-m
                                  (resolve b (measure-last a-m) i mid-full? end-full?))
                                (loop (cdr ams))
                                #t)))))))
              (merge (analyze-left #f) (analyze-left #t) #f)))

          ((doc-alt? d) (merge (resolve (doc-alt-a d) c i beg-full? end-full?)
                               (resolve (doc-alt-b d) c i beg-full? end-full?)
                               #f))

          ((doc-align? d) (resolve (doc-align-d d) c c beg-full? end-full?))

          ((doc-reset? d) (resolve (doc-reset-d d) c 0 beg-full? end-full?))

          ((doc-nest? d)
            (resolve (doc-nest-d d) c (+ i (doc-nest-n d)) beg-full? end-full?))

          ((doc-cost? d) (let ((n (doc-cost-n d))
                               (ms (resolve (doc-cost-d d) c i beg-full? end-full?)))
                           (define (bump m)
                             (make-measure (measure-last m)
                                           (cost+ (measure-cost m) n)
                                           (measure-tokens m)))
                           (if (lazy-set? ms)
                               (delayed (doc-nl-cnt d)
                                        (lambda ()
                                          (let ((v (force-set ms)))
                                            (if (null? v) '() (list (bump (car v)))))))
                               (map bump ms))))

          ;; Reached only with end-full? true; the static mask rejects the rest.
          ;; The inner document is resolved under both, since `full` constrains
          ;; what follows it rather than what it contains.
          ((doc-full? d) (merge (resolve (doc-full-d d) c i beg-full? #f)
                                (resolve (doc-full-d d) c i beg-full? #t)
                                #f))

          ((doc-fail? d) '())

          (else (error 'layout "not a document" d))))

      (let* ((result (merge (resolve d offset 0 #f #f) (resolve d offset 0 #f #t) #f))
             (tainted? (lazy-set? result))
             (final (extract-at-most-one result)))
        (if (null? final) (raise-layout-failure) (values (car final) tainted?)))))

  ;;; Entry points

  ;; Returns two values: the rendered text, and a layout-result carrying the cost
  ;; and whether the search gave up before proving minimality.
  (define layout
    (case-lambda
      ((d factory) (layout d factory 0))
      ((d factory offset)
        (let-values (((m tainted?) (resolve-document d factory offset)))
          (values (render m) (make-layout-result tainted? (measure-cost m)))))))

  ;; The text alone, under the default cost objective.
  (define pretty-format
    (case-lambda
      ((d) (pretty-format d 80))
      ((d page-width)
        (let-values (((text result) (layout d (default-cost-factory page-width) 0)))
          text))))))
