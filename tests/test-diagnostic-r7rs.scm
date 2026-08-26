(import (scheme base) (pitch diagnostic) (pitch reader))

(define (check name expected actual)
  (if (equal? expected actual) #t (error name "mismatch" expected actual)))

(define reader (make-reader (open-input-string "a b") "<test>"))
(define first (get-token reader))
(define space (get-token reader))
(define second (get-token reader))
(define later (make-diagnostic "later" second))
(define earlier (make-diagnostic "earlier" first))

(check 'record #t (diagnostic? earlier))
(check 'message "earlier" (diagnostic-message earlier))
(check 'line 1 (diagnostic-line earlier))
(check 'column 0 (diagnostic-column earlier))
(check 'later-column 2 (diagnostic-column later))
(check 'source-order
       '("earlier" "later")
       (map diagnostic-message (sort-diagnostics (list later earlier))))

(display "test-diagnostic-r7rs: ok\n")
