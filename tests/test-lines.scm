(import (scheme base) (pitch lines))

(define (check name expected actual)
  (if (equal? expected actual) #t (error name "mismatch" expected actual)))

(define cr (string (integer->char 13)))
(define lf (string (integer->char 10)))
(define nel (string (integer->char #x85)))
(define ls (string (integer->char #x2028)))
(define ps (string (integer->char #x2029)))

(check 'empty-index #f (line-ending-index ""))
(check 'plain-index #f (line-ending-index "abc"))
(check 'lf-index 1 (line-ending-index (string-append "a" lf "b")))
(check 'all-endings-count
       7
       (line-ending-count
         (string-append lf cr cr lf cr nel nel ls ps)))
(check 'crlf-pieces
       '("a" "b" "")
       (line-ending-pieces (string-append "a" cr lf "b" ps)))
(check 'empty-pieces '("") (line-ending-pieces ""))
(check 'strip-none "a" (strip-final-line-ending "a"))
(check 'strip-lf "a" (strip-final-line-ending (string-append "a" lf)))
(check 'strip-crlf "a" (strip-final-line-ending (string-append "a" cr lf)))
(check 'strip-crnel "a" (strip-final-line-ending (string-append "a" cr nel)))

(display "test-lines: ok\n")
