(import (scheme base) (pitch style))

(define (check name expected actual)
  (if (equal? expected actual) #t (error name "mismatch" expected actual)))

(define (raises? thunk)
  (guard (raised (else #t)) (thunk) #f))

(define body-shape (style->shape '(_ e . body)))
(check 'styled #t (styled? body-shape))
(check 'slot-count 1 (length (styled-slots body-shape)))
(check 'expression-slot 'expression (slot-style (car (styled-slots body-shape))))
(check 'body-style 'expression (tail-style (styled-tail body-shape)))
(check 'body-indent hanging-indent (tail-indent (styled-tail body-shape)))
(check 'body-not-fill #f (tail-fill? (styled-tail body-shape)))

(define fill-shape (style->shape '(_ . fill)))
(check 'fill #t (tail-fill? (styled-tail fill-shape)))
(define flush-shape (style->shape '(_ . body0)))
(check 'flush-indent flush-indent (tail-indent (styled-tail flush-shape)))
(check 'optional-id #t (slot-optional-id? (car (styled-slots (style->shape '(_ i? . body))))))
(check 'clause-list #t (slot-requires-list? (car (styled-slots (style->shape '(_ ec . body))))))

(check 'bad-head #t (raises? (lambda () (style->shape '(x . body)))))
(check 'bad-terminal #t (raises? (lambda () (style->shape '(_ q . body)))))
(check 'missing-tail #t (raises? (lambda () (style->shape '(_ i e)))))

(define base
  (make-style-table '(((cond) (_ . ec*)) ((when unless) (_ e . body)))))
(check 'table #t (style-table? base))
(check 'present #t (styled? (style-table-ref base 'cond)))
(check 'absent #f (style-table-ref base 'if))
(check 'shared #t (eq? (style-table-ref base 'when) (style-table-ref base 'unless)))

(define extended
  (extend-style-table base '(((project-let) (_ fc* . body))) '(cond)))
(check 'extension #t (styled? (style-table-ref extended 'project-let)))
(check 'removal #f (style-table-ref extended 'cond))
(check 'base-unchanged #t (styled? (style-table-ref base 'cond)))

(display "test-style-r7rs: ok\n")
