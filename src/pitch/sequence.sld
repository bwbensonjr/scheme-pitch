;;; Small sequence operations used by Pitch outside (scheme base).
(define-library (pitch sequence)
  (export for-all exists filter fold-left fold-right list-sort)
  (import (scheme base))
  (begin
    (define (for-all predicate values)
      (if (null? values)
          #t
          (and (predicate (car values))
               (for-all predicate (cdr values)))))

    (define (exists predicate values)
      (if (null? values)
          #f
          (or (predicate (car values))
              (exists predicate (cdr values)))))

    (define (filter predicate values)
      (cond
        ((null? values) '())
        ((predicate (car values))
         (cons (car values) (filter predicate (cdr values))))
        (else (filter predicate (cdr values)))))

    (define (fold-left combine initial values)
      (let loop ((result initial) (remaining values))
        (if (null? remaining)
            result
            (loop (combine result (car remaining)) (cdr remaining)))))

    (define (fold-right combine initial values)
      (if (null? values)
          initial
          (combine (car values)
                   (fold-right combine initial (cdr values)))))

    (define (split-at items count)
      (let loop ((remaining items) (count count) (prefix '()))
        (if (= count 0)
            (values (reverse prefix) remaining)
            (loop (cdr remaining) (- count 1) (cons (car remaining) prefix)))))

    ;; Choose from the left unless the right value is strictly smaller. Equal
    ;; keys therefore retain their input order.
    (define (merge less? left right)
      (cond
        ((null? left) right)
        ((null? right) left)
        ((less? (car right) (car left))
         (cons (car right) (merge less? left (cdr right))))
        (else
         (cons (car left) (merge less? (cdr left) right)))))

    (define (list-sort less? values)
      (if (or (null? values) (null? (cdr values)))
          values
          (call-with-values
            (lambda () (split-at values (quotient (length values) 2)))
            (lambda (left right)
              (merge less?
                     (list-sort less? left)
                     (list-sort less? right))))))))
