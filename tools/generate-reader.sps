#!/usr/bin/env scheme-script
;; Deterministically adapt the authoritative R6RS reader to an R7RS library.
#!r6rs

(import (rnrs (6)) (only (chezscheme) pretty-print))

;; This is the complete accepted import surface of reader.sls. The generated
;; wrapper replaces it wholesale; an added or changed import is never copied.
(define expected-imports
  '((rnrs arithmetic fixnums (6))
    (rnrs base (6))
    (rnrs bytevectors (6))
    (rnrs conditions (6))
    (rnrs control (6))
    (rnrs exceptions (6))
    (rnrs hashtables (6))
    (rnrs lists (6))
    (rnrs mutable-pairs (6))
    (prefix (only (rnrs io ports (6))
                  lookahead-char get-char put-char eof-object?
                  call-with-string-output-port)
            rnrs:)
    (only (rnrs io simple (6)) write display newline current-error-port)
    (rnrs records syntactic (6))
    (rnrs unicode (6))))

;; Identifier-level mappings are deliberately small. Record protocols and
;; composite conditions are whole-form mappings below because translating
;; their component names independently would conceal semantic changes.
(define identifier-mappings
  '((rnrs:lookahead-char . peek-char)
    (rnrs:get-char . read-char)
    (rnrs:call-with-string-output-port . call-with-string-output-port)
    (fixnum? . exact-integer?)
    (fx<=? . <=)
    (fx+ . +)
    (make-eqv-hashtable . make-integer-table)
    (hashtable-update! . table-update!)
    (hashtable-entries . table-entries)
    (u8-list->bytevector . list->bytevector)
    (let-values . pitch-let-values)
    (let*-values . pitch-let*-values)
    (assert . pitch-assert)))

(define special-definition-names
  '(eof-object?
    reader token annotation &source-information
    annotation-source->condition lexical-condition reader-warning))

(define legacy-symbols
  '(condition define-condition-type define-record-type
    make-lexical-violation make-message-condition make-irritants-condition
    make-warning assertion-violation rnrs:eof-object?
    remp exists filter partition fold-left fold-right list-sort vector-sort vector-sort!
    make-transcoder native-transcoder transcoder-codec transcoder-eol-style
    transcoder-error-handling-mode utf-8-codec))

(define (string-prefix? prefix text)
  (let ((n (string-length prefix)))
    (and (<= n (string-length text))
         (string=? prefix (substring text 0 n)))))

(define (legacy-symbol? value)
  (and (symbol? value)
       (let ((name (symbol->string value)))
         (or (memq value legacy-symbols)
             (string-prefix? "rnrs:" name)
             (string-prefix? "hashtable-" name)
             (string-prefix? "make-eq-hashtable" name)
             (string-prefix? "make-eqv-hashtable" name)
             (string-prefix? "bitwise-" name)
             (string-prefix? "eol-style-" name)
             (string-prefix? "error-handling-mode-" name)
             (and (string-prefix? "fx" name)
                  (> (string-length name) 2))))))

(define (reject who message value)
  (assertion-violation who message value))

(define (mapping value)
  (let ((entry (assq value identifier-mappings)))
    (and entry (cdr entry))))

;; Quoted data are not executable identifiers and are intentionally untouched.
(define (rewrite expression)
  (cond
    ((symbol? expression)
     (or (mapping expression)
         (if (legacy-symbol? expression)
             (reject 'generate-reader "unmapped R6RS identifier" expression)
             expression)))
    ((not (pair? expression)) expression)
    ((and (symbol? (car expression))
          (memq (car expression) '(quote quasiquote)))
     expression)
    ((and (eq? (car expression) 'rnrs:put-char)
          (pair? (cdr expression))
          (pair? (cddr expression))
          (null? (cdddr expression)))
     `(write-char ,(rewrite (caddr expression))
                  ,(rewrite (cadr expression))))
    (else (cons (rewrite (car expression)) (rewrite (cdr expression))))))

(define reader-record
  '(define-record-type <reader>
     (make-reader-record port filename)
     reader?
     (port reader-port)
     (filename reader-filename)
     (line reader-line reader-line-set!)
     (column reader-column reader-column-set!)
     (saved-line reader-saved-line reader-saved-line-set!)
     (saved-column reader-saved-column reader-saved-column-set!)
     (fold-case? reader-fold-case? reader-fold-case?-set!)
     (mode reader-mode reader-mode-set!)
     (tolerant? reader-tolerant? reader-tolerant?-set!)
     (offset reader-offset reader-offset-set!)
     (text reader-text reader-text-set!)))

(define reader-constructor
  '(define (make-reader port filename)
     (let ((reader (make-reader-record port filename)))
       (reader-line-set! reader 1)
       (reader-column-set! reader 0)
       (reader-saved-line-set! reader 1)
       (reader-saved-column-set! reader 0)
       (reader-fold-case?-set! reader #f)
       (reader-mode-set! reader 'rnrs)
       (reader-tolerant?-set! reader #f)
       (reader-offset-set! reader 0)
       (reader-text-set! reader #f)
       reader)))

(define token-record
  '(define-record-type <token>
     (make-token-record)
     token?
     (kind token-kind token-kind-set!)
     (text token-text token-text-set!)
     (start token-start token-start-set!)
     (end token-end token-end-set!)
     (start-line token-start-line token-start-line-set!)
     (start-column token-start-column token-start-column-set!)
     (end-line token-end-line token-end-line-set!)
     (end-column token-end-column token-end-column-set!)
     (value token-value token-value-set!)))

(define token-constructor
  '(define (make-token kind text start . rest)
     (let ((token (make-token-record)))
       (token-kind-set! token kind)
       (token-text-set! token text)
       (token-start-set! token start)
       (token-end-set! token (car rest))
       (token-start-line-set! token (car (cdr rest)))
       (token-start-column-set! token (car (cdr (cdr rest))))
       (token-end-line-set! token (car (cdr (cdr (cdr rest)))))
       (token-end-column-set! token (car (cdr (cdr (cdr (cdr rest))))))
       (token-value-set! token (car (cdr (cdr (cdr (cdr (cdr rest)))))))
       token)))

(define annotation-record
  '(define-record-type <annotation>
     (make-annotation expression source stripped)
     annotation?
     (expression annotation-expression)
     (source annotation-source)
     (stripped annotation-stripped)))

(define source-record
  '(define-record-type <source-information>
     (make-source-condition file-name line column)
     source-condition?
     (file-name source-filename)
     (line source-line)
     (column source-column)))

(define opaque-number-marker-record
  '(define-record-type <opaque-number-marker>
     (make-opaque-number-marker)
     opaque-number-marker?))

(define annotation-source-definition
  '(define (annotation-source->condition value)
     (if (vector? value)
         (apply make-source-condition (vector->list value))
         #f)))

(define lexical-condition-definition
  '(define (lexical-condition reader message irritants)
     (make-reader-error (reader-filename reader)
                        (reader-saved-line reader)
                        (reader-saved-column reader)
                        message
                        irritants)))

(define reader-warning-definition
  '(define (reader-warning reader message . irritants)
     (if (reader-tolerant? reader)
         (raise-continuable (lexical-condition reader message irritants))
         (apply reader-error reader message irritants))))

(define injected-helpers
  '((define-syntax pitch-let-values
      (syntax-rules ()
        ((_ (((name ...) expression)) body ...)
         (call-with-values (lambda () expression)
           (lambda (name ...) body ...)))))
    (define-syntax pitch-let*-values
      (syntax-rules ()
        ((_ () body ...) (let () body ...))
        ((_ (binding rest ...) body ...)
         (pitch-let-values (binding)
           (pitch-let*-values (rest ...) body ...)))))
    (define (pitch-assert value)
      (if value #t (error "reader assertion failed")))
    (define (call-with-string-output-port procedure)
      (let ((port (open-output-string)))
        (procedure port)
        (get-output-string port)))))

(define (defined-name form)
  (and (pair? form)
       (eq? (car form) 'define)
       (pair? (cdr form))
       (let ((head (cadr form)))
         (if (pair? head) (car head) head))))

(define (record-name form)
  (and (pair? form)
       (eq? (car form) 'define-record-type)
       (pair? (cdr form))
       (cadr form)))

(define (condition-name form)
  (and (pair? form)
       (eq? (car form) 'define-condition-type)
       (pair? (cdr form))
       (cadr form)))

(define (rewrite-top-level form)
  (let ((record (record-name form))
        (condition (condition-name form))
        (name (defined-name form)))
    (cond
      ((eq? record 'reader) (list reader-record reader-constructor))
      ((eq? record 'token) (list token-record token-constructor))
      ((eq? record 'annotation) (list annotation-record))
      ((eq? record 'opaque-number-marker) (list opaque-number-marker-record))
      (record (reject 'generate-reader "unknown R6RS record form" record))
      ((eq? condition '&source-information) (list source-record))
      (condition (reject 'generate-reader "unknown R6RS condition form" condition))
      ((eq? name 'eof-object?) '())
      ((eq? name 'annotation-source->condition) (list annotation-source-definition))
      ((eq? name 'lexical-condition) (list lexical-condition-definition))
      ((eq? name 'reader-warning) (list reader-warning-definition))
      (else (list (rewrite form))))))

(define (same-members? left right)
  (and (= (length left) (length right))
       (for-all (lambda (item) (member item right)) left)))

(define (transform-library library-form)
  (unless (and (pair? library-form)
               (eq? (car library-form) 'library)
               (equal? (cadr library-form) '(pitch reader)))
    (reject 'generate-reader "expected (library (pitch reader) ...)" library-form))
  (let ((export-form (caddr library-form))
        (import-form (cadddr library-form))
        (body (cddddr library-form)))
    (unless (and (pair? export-form) (eq? (car export-form) 'export))
      (reject 'generate-reader "missing reader export form" export-form))
    (unless (and (pair? import-form)
                 (eq? (car import-form) 'import)
                 (same-members? (cdr import-form) expected-imports))
      (reject 'generate-reader "reader import set is outside the closed mapping" import-form))
    `(define-library (pitch reader)
       ,export-form
       (import (scheme base)
               (scheme char)
               (pitch error)
               (pitch sequence)
               (pitch table))
       (begin
         ,@injected-helpers
         ,@(apply append (map rewrite-top-level body))))))

(define (read-library path)
  (call-with-input-file path
    (lambda (port) (read port))))

(define named-character-mappings
  '(("#\\nul" . "#\\x00")
    ("#\\alarm" . "#\\x07")
    ("#\\backspace" . "#\\x08")
    ("#\\tab" . "#\\x09")
    ("#\\newline" . "#\\x0a")
    ("#\\vtab" . "#\\x0b")
    ("#\\page" . "#\\x0c")
    ("#\\return" . "#\\x0d")
    ("#\\esc" . "#\\x1b")
    ("#\\space" . "#\\x20")
    ("#\\delete" . "#\\x7f")))

(define (string-replace-all text old new)
  (let ((old-length (string-length old))
        (text-length (string-length text)))
    (call-with-string-output-port
     (lambda (port)
       (let loop ((start 0))
         (cond
           ((> (+ start old-length) text-length)
            (display (substring text start text-length) port))
           ((string=? old (substring text start (+ start old-length)))
            (display new port)
            (loop (+ start old-length)))
           (else
            (put-char port (string-ref text start))
            (loop (+ start 1)))))))))

(define (render-library form)
  ;; Chez chooses R6RS-only names for several character objects. Emit accepts
  ;; their portable hexadecimal spellings, so canonicalize the pretty-printed
  ;; tokens using this closed rendering map.
  (let ((rendered
         (call-with-string-output-port
          (lambda (port) (pretty-print form port)))))
    (fold-left (lambda (text entry)
                 (string-replace-all text (car entry) (cdr entry)))
               rendered
               named-character-mappings)))

(define (write-library path form source)
  (when (file-exists? path) (delete-file path))
  (call-with-output-file path
    (lambda (port)
      (display ";;; GENERATED FILE -- DO NOT EDIT\n" port)
      (display ";;; Generated deterministically from " port)
      (display source port)
      (display " by tools/generate-reader.sps.\n" port)
      (display (render-library form) port))))

(define (rejected? thunk)
  (guard (condition (else #t))
    (thunk)
    #f))

(define (inject-import library-form)
  (let ((import-form (cadddr library-form)))
    (cons (car library-form)
          (cons (cadr library-form)
                (cons (caddr library-form)
                      (cons (append import-form '((rnrs imaginary (6))))
                            (cddddr library-form)))))))

(define (inject-form library-form)
  (append library-form '((fxmystery 1))))

(define (self-test source)
  (let ((library-form (read-library source)))
    (transform-library library-form)
    (unless (rejected? (lambda () (transform-library (inject-import library-form))))
      (reject 'generate-reader "self-test accepted an unknown import" source))
    (unless (rejected? (lambda () (transform-library (inject-form library-form))))
      (reject 'generate-reader "self-test accepted an unknown portability form" source))))

(let ((arguments (cdr (command-line))))
  (cond
    ((and (= (length arguments) 2) (string=? (car arguments) "--audit"))
     (transform-library (read-library (cadr arguments))))
    ((and (= (length arguments) 2) (string=? (car arguments) "--self-test"))
     (self-test (cadr arguments)))
    ((= (length arguments) 2)
     (let ((source (car arguments)) (output (cadr arguments)))
       (write-library output (transform-library (read-library source)) source)))
    (else
     (display "usage: generate-reader.sps [--audit|--self-test] SOURCE [OUTPUT]\n"
              (current-error-port))
     (exit 2))))
