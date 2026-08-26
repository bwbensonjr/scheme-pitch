(import (scheme base) (pitch error))

(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (error name "mismatch" expected actual)))

(define config (make-config-error "pitch.scm" "bad configuration" '(width)))
(define reader (make-reader-error "source.scm" 3 7 "bad token" '(token)))
(define layout (make-layout-error "no layout"))

(check 'config-guard
       '(config "pitch.scm")
       (guard (condition
                ((config-error? condition)
                 (list 'config (config-error-path condition)))
                (else 'wrong))
         (raise config)))

(check 'reader-guard
       '(reader "source.scm" 3 7)
       (guard (condition
                ((reader-error? condition)
                 (list 'reader
                       (reader-error-filename condition)
                       (reader-error-line condition)
                       (reader-error-column condition)))
                (else 'wrong))
         (raise reader)))

(check 'layout-guard
       'layout
       (guard (condition ((layout-error? condition) 'layout) (else 'wrong))
         (raise layout)))

(check 'config-message "bad configuration" (pitch-error-message config))
(check 'reader-message "bad token" (pitch-error-message reader))
(check 'layout-message "no layout" (pitch-error-message layout))

(define r7rs-error
  (guard (condition (else condition))
    (error "host message" 'detail)))
(check 'r7rs-message "host message" (pitch-error-message r7rs-error))
(check 'unknown-message "unknown error" (pitch-error-message 'not-an-error))

(display "test-error: ok\n")
