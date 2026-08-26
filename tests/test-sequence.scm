(import (scheme base) (pitch sequence))

(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (error name "mismatch" expected actual)))

(check 'for-all-empty #t (for-all number? '()))
(check 'exists-empty #f (exists number? '()))
(check 'filter-empty '() (filter number? '()))
(check 'fold-left-empty 'seed (fold-left cons 'seed '()))
(check 'fold-right-empty 'seed (fold-right cons 'seed '()))

(check 'for-all #t (for-all number? '(1 2 3)))
(check 'exists #t (exists (lambda (value) (= value 2)) '(1 2 3)))
(check 'filter '(2 4) (filter even? '(1 2 3 4)))
(check 'fold-left '((seed . 1) . 2) (fold-left cons 'seed '(1 2)))
(check 'fold-right '(1 2 . seed) (fold-right cons 'seed '(1 2)))

(check 'sort-empty '() (list-sort < '()))
(check 'sort-singleton '(7) (list-sort < '(7)))
(check 'sort-numbers '(1 1 2 3) (list-sort < '(3 1 2 1)))

(define keyed '((2 . first) (1 . before) (2 . second) (1 . after)))
(check 'sort-stability
       '((1 . before) (1 . after) (2 . first) (2 . second))
       (list-sort (lambda (left right) (< (car left) (car right))) keyed))

(check 'sort-paths
       '("a.scm" "dir/a.scm" "dir/b.scm" "z.scm")
       (list-sort string<? '("z.scm" "dir/b.scm" "a.scm" "dir/a.scm")))

(display "test-sequence: ok\n")
