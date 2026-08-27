;;; Tables with the three equality contracts Pitch needs.
(define-library (pitch table)
(export
  make-symbol-table make-integer-table make-identity-table table? table-ref table-set!
  table-update! table-delete! table-contains? table-size table-keys table-entries
  table-copy)
(import (scheme base))
(begin
  (define-record-type <table> (make-table kind storage) table?
    (kind table-kind)
    (storage table-storage))

  (define (make-symbol-table) (make-table 'symbol (make-hash-table)))
  (define (make-integer-table) (make-table 'integer (make-hash-table)))

  ;; Identity tables use Emit's eq?-keyed table so distinct document records
  ;; remain distinct and cyclic keys require no structural traversal.
  (define (make-identity-table) (make-table 'identity (make-eq-hash-table)))

  (define (check-key table key)
    (case (table-kind table)
      ((symbol) (if (symbol? key) #t (error 'table "expected symbol key" key)))
      ((integer) (if (integer? key) #t (error 'table "expected integer key" key)))
      (else #t)))

  (define (table-ref table key default)
    (check-key table key)
    (hash-table-ref/default (table-storage table) key default))

  (define (table-contains? table key)
    (check-key table key)
    (hash-table-contains? (table-storage table) key))

  (define (table-set! table key value)
    (check-key table key)
    (hash-table-set! (table-storage table) key value))

  (define (table-update! table key update default)
    (table-set! table key (update (table-ref table key default))))

  (define (table-delete! table key)
    (check-key table key)
    (hash-table-delete! (table-storage table) key))

  (define (table-size table) (hash-table-size (table-storage table)))

  (define (table-keys table) (hash-table-keys (table-storage table)))

  (define (table-entries table)
    (let ((entries (hash-table->alist (table-storage table))))
      (values (list->vector (map car entries)) (list->vector (map cdr entries)))))

  (define (table-copy table)
    (let ((copy (case (table-kind table)
                  ((symbol) (make-symbol-table))
                  ((integer) (make-integer-table))
                  (else (make-identity-table)))))
      (for-each (lambda (entry) (table-set! copy (car entry) (cdr entry)))
                (hash-table->alist (table-storage table)))
      copy))))
