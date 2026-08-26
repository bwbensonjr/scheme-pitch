;; Shared serialized reader fixtures. Each wrapper supplies diagnostic-data.

(define parity-cases
  (list
    (list 'core 'rnrs #f
          " (a #xff 1e3 \"\\x41;\" #\\space) ; note\r\n")
    (list 'r6rs 'r6rs #f
          "#vu8(1 2) [a 1e2]")
    (list 'r7rs 'r7rs #f
          "#u8(1 2) |a b| #true #false")
    (list 'directives 'rnrs #f
          "#!fold-case Foo #!no-fold-case Bar")
    (list 'diagnostics 'r7rs #t
          "1e+ #z")
    (list 'positions 'rnrs #f
          "λ\r\n  β")))

(define (serialized-value value)
  (cond
    ((eof-object? value) '(eof))
    ((boolean? value) (list 'boolean value))
    ((number? value) (list 'number value))
    ((char? value) (list 'character (char->integer value)))
    ((string? value) (list 'string value))
    ((symbol? value) (list 'symbol (symbol->string value)))
    (else '(other))))

(define (serialized-token token)
  (list (token-kind token)
        (token-text token)
        (token-start token)
        (token-end token)
        (token-start-line token)
        (token-start-column token)
        (token-end-line token)
        (token-end-column token)
        (serialized-value (token-value token))))

(define (run-parity-case fixture)
  (let* ((name (car fixture))
         (mode (cadr fixture))
         (tolerant? (caddr fixture))
         (source (cadddr fixture))
         (reader (make-reader (open-input-string source) "<parity>"))
         (diagnostics '()))
    (reader-mode-set! reader mode)
    (reader-tolerant?-set! reader tolerant?)
    (with-exception-handler
      (lambda (raised)
        (set! diagnostics (cons (diagnostic-data raised) diagnostics))
        #f)
      (lambda ()
        (let loop ((tokens '()))
          (let ((token (get-token reader)))
            (if (eq? (token-kind token) 'eof)
                (write
                  (list 'case name
                        (reverse (cons (serialized-token token) tokens))
                        (reverse diagnostics)
                        (list 'final
                              (reader-mode reader)
                              (reader-fold-case? reader)
                              (reader-line reader)
                              (reader-column reader)
                              (reader-offset reader))))
                (loop (cons (serialized-token token) tokens)))))))
    (newline)))

(for-each run-parity-case parity-cases)
