(import (scheme base) (pitch cost))

(define (check name expected actual)
  (if (equal? expected actual) #t (error name "mismatch" expected actual)))

(define factory (default-cost-factory 80))
(define cost-text (cost-factory-cost-text factory))
(define cost+ (cost-factory-cost+ factory))
(define cost<=? (cost-factory-cost<=? factory))
(define cost-nl (cost-factory-cost-nl factory))

(check 'default-width 96 (default-computation-width 80))
(check 'rounded-width 15 (default-computation-width 13))
(check 'factory-limit 96 (cost-factory-limit factory))
(check 'inside-page '(0 0) (cost-text 75 5))
(check 'overflow '(25 0) (cost-text 75 10))
(check 'telescopes
       (cost-text 75 10)
       (cost+ (cost-text 75 5) (cost-text 80 5)))
(check 'newline '(0 1) (cost-nl 40))
(check 'badness-first #t (cost<=? '(1 2) '(2 1)))
(check 'height-second #t (cost<=? '(1 1) '(1 2)))
(check 'explicit-limit 100 (cost-factory-limit (default-cost-factory 80 100)))

(display "test-cost: ok\n")
