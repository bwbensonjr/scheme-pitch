(import
  (scheme base)
  (pitch check)
  (pitch cst)
  (pitch datum)
  (pitch diagnostic)
  (pitch parse))

(define (check name expected actual)
  (if (equal? expected actual) #t (error name "mismatch" expected actual)))

(define (project source)
  (call-with-values
    (lambda () (parse-source source "<test>"))
    (lambda (document parse-diagnostics)
      (call-with-values
        (lambda () (cst->datum document))
        (lambda (data datum-diagnostics) data)))))

(define (project-one source) (car (project source)))

(define (datum-diagnostics source)
  (call-with-values
    (lambda () (parse-source source "<test>"))
    (lambda (document parse-diagnostics)
      (call-with-values
        (lambda () (cst->datum document))
        (lambda (data datum-diagnostics) datum-diagnostics)))))

(define (token-equivalent? left right)
  (call-with-values
    (lambda () (check-token-equivalence left right))
    (lambda (ok? mismatch diagnostics) ok?)))

(define (datum-equivalent? left right)
  (call-with-values
    (lambda () (check-datum-equivalence left right))
    (lambda (ok? diagnostics) ok?)))

(define (output-ok? left right)
  (call-with-values
    (lambda () (check-output left right))
    (lambda (ok? layer detail) ok?)))

;; Projection preserves all host datum kinds and top-level order.
(check 'list '(a b c) (project-one "(a b c)"))
(check 'tops '((a) (b)) (project "(a) (b)"))
(check 'vector #t (vector? (project-one "#(1 2)")))
(check 'bytevector #t (bytevector? (project-one "#u8(1 2)")))
(check 'abbreviation '(quote x) (project-one "'x"))
(check 'improper '(a . b) (project-one "(a . b)"))

;; Labels resolve by identity and cycles terminate under datum=?.
(define shared (project-one "(#0=(a) #0#)"))
(check 'shared-identity #t (eq? (car shared) (cadr shared)))
(define cycle-a (project-one "#0=(a . #0#)"))
(define cycle-b (project-one "#0=(a . #0#)"))
(check 'cycle-shape #t (eq? (cdr cycle-a) cycle-a))
(check 'cycle-equal #t (datum=? cycle-a cycle-b))
(check 'cycle-unequal
       #f
       (datum=? cycle-a (project-one "#0=(b . #0#)")))

;; Opaque numbers are projected directly from token values and compare across
;; fresh reads without becoming numbers or octets.
(define huge "999999999999999999999999999999999999999999")
(define huge-value (project-one huge))
(check 'opaque-not-number #f (number? huge-value))
(check 'opaque-fresh-equality #t (datum=? huge-value (project-one huge)))
(check 'opaque-spelling-significant
       #f
       (datum=? huge-value (project-one (string-append "#d" huge))))
(check 'opaque-byte-diagnostic
       #t
       (pair? (datum-diagnostics (string-append "#u8(" huge ")"))))

;; Projection defects diagnose rather than raise or guess.
(check 'bad-byte #t (pair? (datum-diagnostics "#u8(300)")))
(check 'unresolved-label #t (pair? (datum-diagnostics "(#1#)")))

;; Layer 1 compares kind/text after fresh tokenization and preserves comments.
(check 'layout-token-equivalence #t (token-equivalent? "(a  b)" "(a\n b)"))
(check 'number-respelling #f (token-equivalent? "#xff" "255"))
(check 'comment-deletion #f (token-equivalent? "(a ; note\n b)" "(a b)"))
(check 'comment-movement #f (token-equivalent? "(a ; c\n b)" "(a b ; c\n)"))

;; Layer 2 is independently re-read and intentionally weaker.
(check 'layout-datum-equivalence #t (datum-equivalent? "(a  b)" "(a\n b)"))
(check 'representable-radix-equivalence #t (datum-equivalent? "#xff" "255"))
(check 'comment-weakness #t (datum-equivalent? "(a ; note\n b)" "(a b)"))
(check 'meaning-change #f (datum-equivalent? "(a b)" "(a c)"))
(check 'exactness-significant #f (datum-equivalent? "1" "1.0"))
(check 'opaque-fresh-text #t (datum-equivalent? huge huge))

;; The combined check runs both fresh-text paths and refuses malformed output.
(check 'combined-layout #t (output-ok? "(a b)" "(a  b)"))
(check 'combined-token-loss #f (output-ok? "(a ; c\n b)" "(a b)"))
(check 'combined-malformed #f (output-ok? "(a b)" "(a b"))

(display "test-datum-check-r7rs: ok\n")
