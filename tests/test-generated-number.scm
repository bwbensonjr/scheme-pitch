(import (scheme base) (pitch error) (pitch reader))

(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (error name "mismatch" expected actual)))

(define (value-of text)
  (token-value
    (get-token (make-reader (open-input-string text) "<number-test>"))))

(define (reader-error-raised? thunk)
  (guard (raised
          ((reader-error? raised) #t)
          (else #f))
    (thunk)
    #f))

(define huge "999999999999999999999999999999999999999999")
(define huge-value (value-of huge))

(check 'representable-number #t (number? (value-of "#xff")))
(check 'large-integer-is-opaque #f (number? huge-value))
(check 'rational-is-opaque #f (number? (value-of "3/4")))
(check 'rectangular-is-opaque #f (number? (value-of "1+2i")))
(check 'polar-is-opaque #f (number? (value-of "1@2")))
(check 'fresh-opaque-values-compare-equal #t (equal? huge-value (value-of huge)))
(check 'different-opaque-lexemes-differ
       #f
       (equal? huge-value (value-of (string-append "#d" huge))))
(check 'ordinary-data-cannot-match-marker
       #f
       (equal? huge-value (vector 'opaque-number huge)))
(check 'opaque-is-not-an-exact-integer #f (exact-integer? huge-value))
(check 'opaque-is-refused-as-byte
       #t
       (reader-error-raised?
         (lambda ()
           (read-datum
             (make-reader
               (open-input-string (string-append "#u8(" huge ")"))
               "<number-test>")))))

(display "test-generated-number: ok\n")
