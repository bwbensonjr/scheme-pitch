(import (scheme base) (pitch table))

(define (check name expected actual)
  (if (equal? expected actual)
      #t
      (error name "mismatch" expected actual)))

(define symbols (make-symbol-table))
(table-set! symbols 'alpha 1)
(table-set! symbols 'alpha 2)
(check 'symbol-ref 2 (table-ref symbols 'alpha #f))
(check 'symbol-size 1 (table-size symbols))

(define integers (make-integer-table))
(table-set! integers (+ 100 23) 'found)
(table-update! integers 123 (lambda (old) (cons 'updated old)) 'missing)
(check 'integer-ref '(updated . found) (table-ref integers 123 #f))
(check 'integer-missing 'missing (table-ref integers 124 'missing))

(define-record-type <document>
  (make-document content)
  document?
  (content document-content))

(define first (make-document '(same structure)))
(define second (make-document '(same structure)))
(check 'documents-have-equal-structure
       #t
       (equal? (document-content first) (document-content second)))
(check 'documents-are-distinct #f (eq? first second))

(define identities (make-identity-table))
(table-set! identities first 'first)
(table-set! identities second 'second)
(check 'identity-first 'first (table-ref identities first #f))
(check 'identity-second 'second (table-ref identities second #f))
(check 'identity-size 2 (table-size identities))

(define equal-first (list 'same 'value))
(define equal-second (list 'same 'value))
(check 'lists-have-equal-structure #t (equal? equal-first equal-second))
(check 'equal-lists-are-distinct #f (eq? equal-first equal-second))
(table-set! identities equal-first 'equal-first)
(table-set! identities equal-second 'equal-second)
(check 'equal-identity-first 'equal-first (table-ref identities equal-first #f))
(check 'equal-identity-second 'equal-second (table-ref identities equal-second #f))
(check 'equal-identity-size 4 (table-size identities))

(define cycle-a (cons 'cycle '()))
(define cycle-b (cons 'cycle '()))
(set-cdr! cycle-a cycle-a)
(set-cdr! cycle-b cycle-b)
(table-set! identities cycle-a 'cycle-a)
(check 'cyclic-identity-hit 'cycle-a (table-ref identities cycle-a #f))
(check 'cyclic-identity-miss 'missing (table-ref identities cycle-b 'missing))

(define copied (table-copy identities))
(table-delete! copied first)
(check 'copy-delete #f (table-contains? copied first))
(check 'copy-independent #t (table-contains? identities first))

(call-with-values
  (lambda () (table-entries symbols))
  (lambda (keys values)
    (check 'entry-count 1 (vector-length keys))
    (check 'entry-key 'alpha (vector-ref keys 0))
    (check 'entry-value 2 (vector-ref values 0))))

(display "test-table: ok\n")
