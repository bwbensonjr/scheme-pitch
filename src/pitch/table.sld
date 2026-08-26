;;; Tables with the three equality contracts Pitch needs.
(define-library (pitch table)
  (export
    make-symbol-table
    make-integer-table
    make-identity-table
    table?
    table-ref
    table-set!
    table-update!
    table-delete!
    table-contains?
    table-size
    table-keys
    table-entries
    table-copy)
  (import (scheme base))
  (begin
    (define-record-type <table>
      (make-table kind storage)
      table?
      (kind table-kind)
      (storage table-storage table-storage-set!))

    (define (make-symbol-table) (make-table 'symbol (make-hash-table)))
    (define (make-integer-table) (make-table 'integer (make-hash-table)))

    ;; Identity tables deliberately use an eq?-searched association list.
    ;; Emit's ordinary hash table is equal?-keyed, which would merge distinct
    ;; document records and would traverse cyclic keys.
    (define (make-identity-table) (make-table 'identity '()))

    (define (check-key table key)
      (case (table-kind table)
        ((symbol) (if (symbol? key) #t (error 'table "expected symbol key" key)))
        ((integer) (if (integer? key) #t (error 'table "expected integer key" key)))
        (else #t)))

    (define (identity-entry entries key)
      (cond
        ((null? entries) #f)
        ((eq? key (caar entries)) (car entries))
        (else (identity-entry (cdr entries) key))))

    (define (table-ref table key default)
      (check-key table key)
      (if (eq? (table-kind table) 'identity)
          (let ((entry (identity-entry (table-storage table) key)))
            (if entry (cdr entry) default))
          (hash-table-ref/default (table-storage table) key default)))

    (define (table-contains? table key)
      (check-key table key)
      (if (eq? (table-kind table) 'identity)
          (if (identity-entry (table-storage table) key) #t #f)
          (hash-table-contains? (table-storage table) key)))

    (define (table-set! table key value)
      (check-key table key)
      (if (eq? (table-kind table) 'identity)
          (let ((entry (identity-entry (table-storage table) key)))
            (if entry
                (set-cdr! entry value)
                (table-storage-set!
                  table
                  (cons (cons key value) (table-storage table)))))
          (hash-table-set! (table-storage table) key value)))

    (define (table-update! table key update default)
      (table-set! table key (update (table-ref table key default))))

    (define (remove-identity entries key)
      (cond
        ((null? entries) '())
        ((eq? key (caar entries)) (cdr entries))
        (else (cons (car entries) (remove-identity (cdr entries) key)))))

    (define (table-delete! table key)
      (check-key table key)
      (if (eq? (table-kind table) 'identity)
          (table-storage-set! table (remove-identity (table-storage table) key))
          (hash-table-delete! (table-storage table) key)))

    (define (table-size table)
      (if (eq? (table-kind table) 'identity)
          (length (table-storage table))
          (hash-table-size (table-storage table))))

    (define (table-keys table)
      (if (eq? (table-kind table) 'identity)
          (map car (table-storage table))
          (hash-table-keys (table-storage table))))

    (define (table-entries table)
      (let ((entries (if (eq? (table-kind table) 'identity)
                         (table-storage table)
                         (hash-table->alist (table-storage table)))))
        (values (list->vector (map car entries))
                (list->vector (map cdr entries)))))

    (define (table-copy table)
      (let ((copy (case (table-kind table)
                    ((symbol) (make-symbol-table))
                    ((integer) (make-integer-table))
                    (else (make-identity-table)))))
        (if (eq? (table-kind table) 'identity)
            (for-each
              (lambda (entry) (table-set! copy (car entry) (cdr entry)))
              (reverse (table-storage table)))
            (for-each
              (lambda (entry) (table-set! copy (car entry) (cdr entry)))
              (hash-table->alist (table-storage table))))
        copy))))
