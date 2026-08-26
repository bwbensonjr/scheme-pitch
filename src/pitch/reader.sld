;;; GENERATED FILE -- DO NOT EDIT
;;; Generated deterministically from src/pitch/reader.sls by tools/generate-reader.sps.
(define-library
  (pitch reader)
  (export get-token get-token* token? token-kind token-text
   token-start token-end token-value token-start-line
   token-start-column token-end-line token-end-column
   read-annotated read-datum detect-scheme-file-type reader?
   make-reader reader-warning reader-port reader-mode
   reader-mode-set! reader-fold-case? reader-fold-case?-set!
   reader-tolerant? reader-tolerant?-set! reader-line
   reader-column reader-offset reader-saved-line
   reader-saved-column annotation? annotation-expression
   annotation-stripped annotation-source
   annotation-source->condition source-condition?
   source-filename source-line source-column)
  (import (scheme base) (scheme char) (pitch error)
    (pitch sequence) (pitch table))
  (begin
    (define-syntax pitch-let-values
      (syntax-rules ()
        [(_ (((name ...) expression)) body ...)
         (call-with-values
           (lambda () expression)
           (lambda (name ...) body ...))]))
    (define-syntax pitch-let*-values
      (syntax-rules ()
        [(_ () body ...) (let () body ...)]
        [(_ (binding rest ...) body ...)
         (pitch-let-values
           (binding)
           (pitch-let*-values (rest ...) body ...))]))
    (define (pitch-assert value)
      (if value #t (error "reader assertion failed")))
    (define (call-with-string-output-port procedure)
      (let ([port (open-output-string)])
        (procedure port)
        (get-output-string port)))
    (define (lookahead-char reader)
      (peek-char (reader-port reader)))
    (define (line-ending? reader c)
      (cond
        [(memv c '(#\x0a #\x85 #\x2028 #\ )) #t]
        [(eqv? c #\x0d)
         (not (memv (lookahead-char reader) '(#\x0a #\x85)))]
        [else #f]))
    (define (get-char reader)
      (let ([c (read-char (reader-port reader))])
        (when (char? c)
          (when (line-ending? reader c)
            (reader-line-set! reader (+ (reader-line reader) 1))
            (reader-column-set! reader -1))
          (reader-column-set! reader (+ (reader-column reader) 1))
          (reader-offset-set! reader (+ (reader-offset reader) 1))
          (let ([text (reader-text reader)])
            (when text (reader-text-set! reader (cons c text)))))
        c))
    (define (detect-scheme-file-type port)
      (let ([reader (make-reader port "<unknown>")])
        (pitch-let-values
          (((type lexeme) (get-lexeme reader)))
          (case type
            [(eof) 'empty]
            [(shebang) 'r6rs-program]
            [(openp openb)
             (pitch-let-values
               (((type lexeme) (get-lexeme reader)))
               (case type
                 [(identifier)
                  (case lexeme
                    [(import) 'r6rs-program]
                    [(library) 'r6rs-library]
                    [(define-library) 'r7rs-library]
                    [else 'unknown])]
                 [else 'unknown]))]
            [else 'unknown]))))
    (define-record-type <reader>
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
      (text reader-text reader-text-set!))
    (define (make-reader port filename)
      (let ([reader (make-reader-record port filename)])
        (reader-line-set! reader 1)
        (reader-column-set! reader 0)
        (reader-saved-line-set! reader 1)
        (reader-saved-column-set! reader 0)
        (reader-fold-case?-set! reader #f)
        (reader-mode-set! reader 'rnrs)
        (reader-tolerant?-set! reader #f)
        (reader-offset-set! reader 0)
        (reader-text-set! reader #f)
        reader))
    (define-record-type <token>
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
      (value token-value token-value-set!))
    (define (make-token kind text start . rest)
      (let ([token (make-token-record)])
        (token-kind-set! token kind)
        (token-text-set! token text)
        (token-start-set! token start)
        (token-end-set! token (car rest))
        (token-start-line-set! token (car (cdr rest)))
        (token-start-column-set! token (car (cdr (cdr rest))))
        (token-end-line-set! token (car (cdr (cdr (cdr rest)))))
        (token-end-column-set!
          token
          (car (cdr (cdr (cdr (cdr rest))))))
        (token-value-set!
          token
          (car (cdr (cdr (cdr (cdr (cdr rest)))))))
        token))
    (define (reader-mark reader)
      (reader-saved-line-set! reader (reader-line reader))
      (reader-saved-column-set! reader (reader-column reader)))
    (define-record-type <annotation>
      (make-annotation expression source stripped)
      annotation?
      (expression annotation-expression)
      (source annotation-source)
      (stripped annotation-stripped))
    (define-record-type <source-information>
      (make-source-condition file-name line column)
      source-condition?
      (file-name source-filename)
      (line source-line)
      (column source-column))
    (define (annotation-source->condition value)
      (if (vector? value)
          (apply make-source-condition (vector->list value))
          #f))
    (define (reader-source reader)
      (vector
        (reader-filename reader)
        (reader-saved-line reader)
        (reader-saved-column reader)))
    (define (annotate source stripped datum)
      (pitch-assert (vector? source))
      (make-annotation datum source stripped))
    (define (read-annotated reader)
      (pitch-assert (reader? reader))
      (reader-text-set! reader #f)
      (let ([labels (make-labels)])
        (pitch-let*-values
          (((type x) (get-lexeme reader))
            ((_ d^) (handle-lexeme reader type x labels #f)))
          (resolve-labels reader labels)
          d^)))
    (define (read-datum reader)
      (pitch-assert (reader? reader))
      (reader-text-set! reader #f)
      (let ([labels (make-labels)])
        (pitch-let*-values
          (((type x) (get-lexeme reader))
            ((d _) (handle-lexeme reader type x labels #f)))
          (resolve-labels reader labels)
          d)))
    (define (lexical-condition reader message irritants)
      (make-reader-error (reader-filename reader) (reader-saved-line reader)
        (reader-saved-column reader) message irritants))
    (define (reader-error reader msg . irritants)
      (raise (lexical-condition reader msg irritants)))
    (define (reader-warning reader message . irritants)
      (if (reader-tolerant? reader)
          (raise-continuable
            (lexical-condition reader message irritants))
          (apply reader-error reader message irritants)))
    (define (assert-mode p msg modes)
      (unless (memq (reader-mode p) modes)
        (reader-warning
          p
          (string-append msg " is not allowed in this mode")
          (reader-mode p))))
    (define (eof-warning reader)
      (reader-warning reader "Unexpected EOF"))
    (define (unicode-scalar-value? sv)
      (and (exact-integer? sv)
           (<= 0 sv 1114111)
           (not (<= 55296 sv 57343))))
    (define (char-delimiter? reader c)
      (or (eof-object? c)
          (char-whitespace? c)
          (case (reader-mode reader)
            [(r6rs) (memv c '(#\( #\) #\[ #\] #\" #\; #\#))]
            [(r7rs) (memv c '(#\( #\) #\" #\; #\|))]
            [else (memv c '(#\( #\) #\[ #\] #\" #\; #\# #\|))])))
    (define (get-line reader)
      (call-with-string-output-port
        (lambda (out)
          (do ([c (get-char reader) (get-char reader)])
              ((or (eqv? c #\x0a) (eof-object? c)))
            (write-char c out)))))
    (define (get-whitespace reader char)
      (call-with-string-output-port
        (lambda (out)
          (let lp ([char char])
            (write-char char out)
            (let ([char (lookahead-char reader)])
              (when (and (char? char) (char-whitespace? char))
                (lp (get-char reader))))))))
    (define (get-inline-hex-escape p)
      (reader-mark p)
      (let lp ([digits '()])
        (let ([c (get-char p)])
          (cond
            [(eof-object? c) (eof-warning p) #\�]
            [(or (char<=? #\0 c #\9)
                 (char<=? #\a c #\f)
                 (char<=? #\A c #\F))
             (lp (cons c digits))]
            [(and (char=? c #\;) (pair? digits))
             (let ([sv (string->number
                         (list->string (reverse digits))
                         16)])
               (cond
                 [(unicode-scalar-value? sv) (integer->char sv)]
                 [else
                  (reader-warning
                    p
                    "Inline hex escape outside valid range"
                    sv)
                  #\�]))]
            [else
             (reader-warning p "Invalid inline hex escape" c)
             #\�]))))
    (define (get-identifier p initial-char pipe-quoted?)
      (let lp ([chars (if initial-char (list initial-char) '())])
        (let ([c (lookahead-char p)])
          (cond
            [(and (char? c)
                  (or (char<=? #\a c #\z)
                      (char<=? #\A c #\Z)
                      (char<=? #\0 c #\9)
                      (memv
                        c
                        '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^
                              #\_ #\~ #\+ #\- #\. #\@))
                      (and (> (char->integer c) 127)
                           (memq
                             (char-general-category c)
                             '(Lu Ll Lt Lm Lo Mn Nl No Pd Pc Po Sc Sm Sk So
                                  Co Nd Mc Me)))
                      (and (memv (reader-mode p) '(rnrs r7rs))
                           (memv c '(#\‌ #\‍)))))
             (lp (cons (get-char p) chars))]
            [(and pipe-quoted? (char? c) (not (memv c '(#\| #\\))))
             (lp (cons (get-char p) chars))]
            [(or (char-delimiter? p c) (and pipe-quoted? (eqv? c #\|)))
             (when (eqv? c #\|) (get-char p))
             (let ([id (list->string (reverse chars))])
               (if (reader-fold-case? p)
                   (values
                     'identifier
                     (string->symbol (string-foldcase id)))
                   (values 'identifier (string->symbol id))))]
            [(char=? c #\\)
             (get-char p)
             (let ([c (get-char p)])
               (cond
                 [(eqv? c #\x) (lp (cons (get-inline-hex-escape p) chars))]
                 [(and pipe-quoted?
                       (assv
                         c
                         '((#\" . #\") (#\\ . #\\) (#\a . #\x07) (#\b . #\x08)
                            (#\t . #\x09) (#\n . #\x0a)
                            (#\r . #\x0d) (#\| . #\|)))) =>
                  (lambda (c) (lp (cons (cdr c) chars)))]
                 [else
                  (if (eof-object? c)
                      (eof-warning p)
                      (reader-warning p "Invalid character following \\"))
                  (lp chars)]))]
            [else
             (reader-warning p "Invalid character in identifier" c)
             (get-char p)
             (lp chars)]))))
    (define (ascii-downcase c)
      (if (char<=? #\A c #\Z)
          (integer->char
            (+ (char->integer c)
               (- (char->integer #\a) (char->integer #\A))))
          c))
    (define (digit-value c)
      (let ([c (ascii-downcase c)])
        (cond
          [(char<=? #\0 c #\9)
           (- (char->integer c) (char->integer #\0))]
          [(char<=? #\a c #\f)
           (+ 10 (- (char->integer c) (char->integer #\a)))]
          [else #f])))
    (define (digit-in-radix? c radix)
      (let ([value (digit-value c)]) (and value (< value radix))))
    (define (scan-digits text start end radix)
      (let loop ([index start])
        (if (and (< index end)
                 (digit-in-radix? (string-ref text index) radix))
            (loop (+ index 1))
            index)))
    (define (nonzero-digits? text start end)
      (let loop ([index start])
        (and (< index end)
             (or (let ([value (digit-value (string-ref text index))])
                   (and value (not (= value 0))))
                 (loop (+ index 1))))))
    (define (ascii-ci-prefix? text start end expected)
      (let ([expected-end (+ start (string-length expected))])
        (and (<= expected-end end)
             (let loop ([index start] [expected-index 0])
               (if (= expected-index (string-length expected))
                   #t
                   (and (char=?
                          (ascii-downcase (string-ref text index))
                          (string-ref expected expected-index))
                        (loop (+ index 1) (+ expected-index 1))))))))
    (define (infnan-end text start end)
      (cond
        [(or (ascii-ci-prefix? text start end "+inf.0")
             (ascii-ci-prefix? text start end "-inf.0")
             (ascii-ci-prefix? text start end "+nan.0")
             (ascii-ci-prefix? text start end "-nan.0"))
         (+ start 6)]
        [else #f]))
    (define (exponent-marker? c)
      (memv (ascii-downcase c) '(#\e #\s #\f #\d #\l)))
    (define (scan-exponent text start end)
      (let ([digits-start (if (and (< start end)
                                   (memv
                                     (string-ref text start)
                                     '(#\+ #\-)))
                              (+ start 1)
                              start)])
        (let ([digits-end (scan-digits text digits-start end 10)])
          (and (< digits-start digits-end) digits-end))))
    (define (scan-mantissa-width text start end)
      (let ([width-end (scan-digits text start end 10)])
        (and (< start width-end) width-end)))
    (define (scan-decimal-suffix text start end)
      (let ([after-exponent (if (and (< start end)
                                     (exponent-marker?
                                       (string-ref text start)))
                                (scan-exponent text (+ start 1) end)
                                start)])
        (and after-exponent
             (if (and (< after-exponent end)
                      (char=? (string-ref text after-exponent) #\|))
                 (scan-mantissa-width text (+ after-exponent 1) end)
                 after-exponent))))
    (define (parse-ureal text start end radix)
      (cond
        [(and (= radix 10)
              (< start end)
              (char=? (string-ref text start) #\.))
         (let ([fraction-end (scan-digits text (+ start 1) end 10)])
           (and (< (+ start 1) fraction-end)
                (scan-decimal-suffix text fraction-end end)))]
        [else
         (let ([integer-end (scan-digits text start end radix)])
           (and (< start integer-end)
                (cond
                  [(and (< integer-end end)
                        (char=? (string-ref text integer-end) #\/))
                   (let ([denominator-end (scan-digits
                                            text
                                            (+ integer-end 1)
                                            end
                                            radix)])
                     (and (< (+ integer-end 1) denominator-end)
                          (nonzero-digits?
                            text
                            (+ integer-end 1)
                            denominator-end)
                          denominator-end))]
                  [(and (= radix 10)
                        (< integer-end end)
                        (char=? (string-ref text integer-end) #\.))
                   (let ([fraction-end (scan-digits
                                         text
                                         (+ integer-end 1)
                                         end
                                         10)])
                     (scan-decimal-suffix text fraction-end end))]
                  [(and (= radix 10)
                        (< integer-end end)
                        (exponent-marker? (string-ref text integer-end)))
                   (scan-decimal-suffix text integer-end end)]
                  [(and (< integer-end end)
                        (char=? (string-ref text integer-end) #\|))
                   (scan-mantissa-width text (+ integer-end 1) end)]
                  [else integer-end])))]))
    (define (parse-real text start end radix)
      (or (infnan-end text start end)
          (let ([unsigned-start (if (and (< start end)
                                         (memv
                                           (string-ref text start)
                                           '(#\+ #\-)))
                                    (+ start 1)
                                    start)])
            (parse-ureal text unsigned-start end radix))))
    (define (signed-start? text start end)
      (and (< start end)
           (memv (string-ref text start) '(#\+ #\-))))
    (define (complex-number-syntax? text start end radix)
      (if (and (= (+ start 2) end)
               (signed-start? text start end)
               (char-ci=? (string-ref text (+ start 1)) #\i))
          #t
          (let ([first-end (parse-real text start end radix)])
            (and first-end
                 (cond
                   [(= first-end end) #t]
                   [(char=? (string-ref text first-end) #\@)
                    (let ([second-end (parse-real
                                        text
                                        (+ first-end 1)
                                        end
                                        radix)])
                      (and second-end (= second-end end)))]
                   [(char-ci=? (string-ref text first-end) #\i)
                    (and (signed-start? text start end)
                         (= (+ first-end 1) end))]
                   [(memv (string-ref text first-end) '(#\+ #\-))
                    (let ([component-start (+ first-end 1)])
                      (cond
                        [(and (= (+ component-start 1) end)
                              (char-ci=?
                                (string-ref text component-start)
                                #\i))
                         #t]
                        [(infnan-end text first-end end) =>
                         (lambda (component-end)
                           (and (< component-end end)
                                (char-ci=?
                                  (string-ref text component-end)
                                  #\i)
                                (= (+ component-end 1) end)))]
                        [else
                         (let ([component-end (parse-ureal
                                                text
                                                component-start
                                                end
                                                radix)])
                           (and component-end
                                (< component-end end)
                                (char-ci=?
                                  (string-ref text component-end)
                                  #\i)
                                (= (+ component-end 1) end)))]))]
                   [else #f])))))
    (define (scan-number-prefixes text end)
      (let loop ([index 0]
                 [radix 10]
                 [radix-seen? #f]
                 [exactness-seen? #f])
        (if (and (< index end) (char=? (string-ref text index) #\#))
            (and (< (+ index 1) end)
                 (let ([letter (ascii-downcase
                                 (string-ref text (+ index 1)))])
                   (case letter
                     [(#\b)
                      (and (not radix-seen?)
                           (loop (+ index 2) 2 #t exactness-seen?))]
                     [(#\o)
                      (and (not radix-seen?)
                           (loop (+ index 2) 8 #t exactness-seen?))]
                     [(#\d)
                      (and (not radix-seen?)
                           (loop (+ index 2) 10 #t exactness-seen?))]
                     [(#\x)
                      (and (not radix-seen?)
                           (loop (+ index 2) 16 #t exactness-seen?))]
                     [(#\e #\i)
                      (and (not exactness-seen?)
                           (loop (+ index 2) radix radix-seen? #t))]
                     [else #f])))
            (and (< index end) (vector radix index)))))
    (define (number-syntax? text)
      (let* ([end (string-length text)]
             [prefixes (scan-number-prefixes text end)])
        (and prefixes
             (complex-number-syntax?
               text
               (vector-ref prefixes 1)
               end
               (vector-ref prefixes 0)))))
    (define-record-type <opaque-number-marker>
      (make-opaque-number-marker)
      opaque-number-marker?)
    (define opaque-number-marker-instance
      (make-opaque-number-marker))
    (define (make-opaque-number text)
      (vector opaque-number-marker-instance text))
    (define (construct-number text)
      (guard (raised [else #f]) (string->number text)))
    (define (get-number p initial-chars)
      (let lp ([chars initial-chars])
        (let ([c (lookahead-char p)])
          (cond
            [(and (not (memv c '(#\# #\|))) (char-delimiter? p c))
             (let ([str (list->string (reverse chars))])
               (cond
                 [(not (number-syntax? str))
                  (if (and (memq (reader-mode p) '(rnrs r7rs))
                           (not (memv
                                  (string-ref str 0)
                                  '(#\# #\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8
                                        #\9))))
                      (values 'identifier (string->symbol str))
                      (begin
                        (reader-warning p "Invalid number syntax" str)
                        (values 'identifier (string->symbol str))))]
                 [(construct-number str) =>
                  (lambda (num) (values 'value num))]
                 [else (values 'value (make-opaque-number str))]))]
            [else (lp (cons (get-char p) chars))]))))
    (define (get-string p)
      (let lp ([chars '()])
        (let ([c (lookahead-char p)])
          (cond
            [(eof-object? c) (eof-warning p) c]
            [(char=? c #\") (get-char p) (list->string (reverse chars))]
            [(char=? c #\\)
             (get-char p)
             (let ([c (lookahead-char p)])
               (cond
                 [(eof-object? c) (eof-warning p) c]
                 [(or (memv c '(#\x09 #\x0a #\x0d #\x85 #\x2028))
                      (eq? (char-general-category c) 'Zs))
                  (letrec ([skip-intraline-whitespace* (lambda ()
                                                         (let ([c (lookahead-char
                                                                    p)])
                                                           (cond
                                                             [(eof-object?
                                                                c)
                                                              (eof-warning
                                                                p)
                                                              c]
                                                             [(or (char=?
                                                                    c
                                                                    '#\x09)
                                                                  (eq? (char-general-category
                                                                         c)
                                                                       'Zs))
                                                              (get-char p)
                                                              (skip-intraline-whitespace*)])))]
                           [skip-newline (lambda ()
                                           (let ([c (get-char p)])
                                             (cond
                                               [(eof-object? c) c]
                                               [(memv
                                                  c
                                                  '(#\x0a
                                                     #\x85
                                                     #\x2028))]
                                               [(char=? c #\x0d)
                                                (when (memv
                                                        (lookahead-char p)
                                                        '(#\x0a #\x85))
                                                  (get-char p))]
                                               [else
                                                (reader-warning
                                                  p
                                                  "Expected a line ending"
                                                  c)])))])
                    (skip-intraline-whitespace*)
                    (skip-newline)
                    (skip-intraline-whitespace*)
                    (lp chars))]
                 [else
                  (lp (cons
                        (case (get-char p)
                          [(#\") #\"]
                          [(#\\) #\\]
                          [(#\a) #\x07]
                          [(#\b) #\x08]
                          [(#\t) #\x09]
                          [(#\n) #\x0a]
                          [(#\v) (assert-mode p "\\v" '(rnrs r6rs)) #\x0b]
                          [(#\f) (assert-mode p "\\f" '(rnrs r6rs)) #\x0c]
                          [(#\r) #\x0d]
                          [(#\|) (assert-mode p "\\|" '(rnrs r7rs)) #\|]
                          [(#\x) (get-inline-hex-escape p)]
                          [else
                           (reader-warning p "Invalid escape in string" c)
                           #\�])
                        chars))]))]
            [else (lp (cons (get-char p) chars))]))))
    (define (get-nested-comment reader)
      (call-with-string-output-port
        (lambda (out)
          (let lp ([levels 1] [c0 (get-char reader)])
            (let ([c1 (get-char reader)])
              (cond
                [(eof-object? c0) (eof-warning reader)]
                [(and (eqv? c0 #\|) (eqv? c1 #\#))
                 (unless (eqv? levels 1)
                   (write-char c0 out)
                   (write-char c1 out)
                   (lp (- levels 1) (get-char reader)))]
                [(and (eqv? c0 #\#) (eqv? c1 #\|))
                 (write-char c0 out)
                 (write-char c1 out)
                 (lp (+ levels 1) (get-char reader))]
                [else (write-char c0 out) (lp levels c1)]))))))
    (define (get-!-comment reader)
      (call-with-string-output-port
        (lambda (out)
          (let lp ([c0 (get-char reader)])
            (let ([c1 (get-char reader)])
              (cond
                [(eof-object? c0) (eof-warning reader)]
                [(and (eqv? c0 #\!) (eqv? c1 #\#)) #f]
                [else (write-char c0 out) (lp c1)]))))))
    (define (get-comment reader)
      (call-with-string-output-port
        (lambda (out)
          (let lp ()
            (let ([c (get-char reader)])
              (unless (eof-object? c)
                (write-char c out)
                (cond
                  [(memv c '(#\x0a #\x85 #\x2028 #\ ))]
                  [(char=? c #\x0d)
                   (when (memv (lookahead-char reader) '(#\x0a #\x85))
                     (write-char (get-char reader) out))]
                  [else (lp)])))))))
    (define (atmosphere? type)
      (memq
        type
        '(directive
           whitespace
           comment
           inline-comment
           nested-comment)))
    (define (get-lexeme p)
      (pitch-let-values
        (((type lexeme) (get-token* p)))
        (if (atmosphere? type)
            (get-lexeme p)
            (values type lexeme))))
    (define (get-token p)
      (pitch-assert (reader? p))
      (let ([start (reader-offset p)]
            [start-line (reader-line p)]
            [start-column (reader-column p)])
        (reader-text-set! p '())
        (pitch-let-values
          (((kind value) (get-token* p)))
          (let ([text (list->string (reverse (reader-text p)))])
            (reader-text-set! p #f)
            (make-token kind text start (reader-offset p) start-line
              start-column (reader-line p) (reader-column p) value)))))
    (define (get-token* p)
      (pitch-assert (reader? p))
      (reader-mark p)
      (let ([c (get-char p)])
        (cond
          [(eof-object? c) (values 'eof c)]
          [(char-whitespace? c)
           (values 'whitespace (get-whitespace p c))]
          [(char=? c #\;) (values 'comment (get-comment p))]
          [(char=? c #\#)
           (let ([c (get-char p)])
             (case c
               [(#\() (values 'vector #f)]
               [(#\') (values 'abbrev 'syntax)]
               [(#\`) (values 'abbrev 'quasisyntax)]
               [(#\,)
                (case (lookahead-char p)
                  [(#\@) (get-char p) (values 'abbrev 'unsyntax-splicing)]
                  [else (values 'abbrev 'unsyntax)])]
               [(#\v)
                (let* ([c1 (and (eqv? (lookahead-char p) #\u)
                                (get-char p))]
                       [c2 (and (eqv? c1 #\u)
                                (eqv? (lookahead-char p) #\8)
                                (get-char p))]
                       [c3 (and (eqv? c2 #\8)
                                (eqv? (lookahead-char p) #\()
                                (get-char p))])
                  (cond
                    [(and (eqv? c1 #\u) (eqv? c2 #\8) (eqv? c3 #\())
                     (assert-mode p "#vu8(" '(rnrs r6rs))
                     (values 'bytevector #f)]
                    [else
                     (reader-warning p "Expected #vu8(")
                     (get-token* p)]))]
               [(#\u #\U)
                (let* ([c1 (and (eqv? (lookahead-char p) #\8)
                                (get-char p))]
                       [c2 (and (eqv? c1 #\8)
                                (eqv? (lookahead-char p) #\()
                                (get-char p))])
                  (cond
                    [(and (eqv? c1 #\8) (eqv? c2 #\())
                     (assert-mode p "#u8(" '(rnrs r7rs))
                     (values 'bytevector #f)]
                    [else
                     (reader-warning p "Expected #u8(")
                     (get-token* p)]))]
               [(#\;)
                (let lp ([atmosphere '()])
                  (pitch-let-values
                    (((type token) (get-token* p)))
                    (cond
                      [(eq? type 'eof)
                       (eof-warning p)
                       (values
                         'inline-comment
                         (cons (reverse atmosphere) p))]
                      [(atmosphere? type)
                       (lp (cons (cons type token) atmosphere))]
                      [else
                       (pitch-let-values
                         (((d _) (handle-lexeme p type token #f #t)))
                         (values
                           'inline-comment
                           (cons (reverse atmosphere) d)))])))]
               [(#\|) (values 'nested-comment (get-nested-comment p))]
               [(#\!)
                (let ([next-char (lookahead-char p)])
                  (cond
                    [(and (= (reader-saved-line p) 1)
                          (memv next-char '(#\/ #\x20)))
                     (let ([line (reader-saved-line p)]
                           [column (reader-saved-column p)])
                       (values 'shebang `(,line ,column ,(get-line p))))]
                    [(and (char? next-char) (char-alphabetic? next-char))
                     (pitch-let-values
                       (((type id) (get-token* p)))
                       (cond
                         [(eq? type 'identifier)
                          (case id
                            [(r6rs)
                             (assert-mode p "#!r6rs" '(rnrs r6rs))
                             (reader-mode-set! p 'r6rs)]
                            [(fold-case)
                             (assert-mode
                               p
                               "#!fold-case"
                               '(rnrs r6rs r7rs))
                             (reader-fold-case?-set! p #t)]
                            [(no-fold-case)
                             (assert-mode
                               p
                               "#!no-fold-case"
                               '(rnrs r6rs r7rs))
                             (reader-fold-case?-set! p #f)]
                            [(r7rs)
                             (assert-mode p "#!r7rs" '(rnrs))
                             (reader-mode-set! p 'r7rs)]
                            [(false)
                             (assert-mode p "#!false" '(rnrs r2rs))]
                            [(true) (assert-mode p "#!true" '(rnrs r2rs))]
                            [else
                             (reader-warning
                               p
                               "Invalid directive"
                               type
                               id)])
                          (cond
                            [(assq id '((false . #f) (true . #t))) =>
                             (lambda (x) (values 'value (cdr x)))]
                            [else (values 'directive id)])]
                         [else
                          (reader-warning
                            p
                            "Expected an identifier after #!")
                          (get-token* p)]))]
                    [(eq? (reader-mode p) 'rnrs)
                     (get-token* p)
                     (values 'comment (get-!-comment p))]
                    [else
                     (reader-warning p "Expected an identifier after #!")
                     (get-token* p)]))]
               [(#\b #\B #\o #\O #\d #\D #\x #\X #\i #\I #\e #\E)
                (get-number p (list c #\#))]
               [(#\t #\T)
                (unless (char-delimiter? p (lookahead-char p))
                  (if (memq (reader-mode p) '(rnrs r7rs))
                      (let* ([c1 (and (memv (lookahead-char p) '(#\r #\R))
                                      (get-char p))]
                             [c2 (and c1
                                      (memv (lookahead-char p) '(#\u #\U))
                                      (get-char p))]
                             [c3 (and c2
                                      (memv (lookahead-char p) '(#\e #\E))
                                      (get-char p))])
                        (unless (and c1
                                     c2
                                     c3
                                     (char-delimiter?
                                       p
                                       (lookahead-char p)))
                          (reader-warning p "Expected #true")))
                      (reader-warning
                        p
                        "A delimiter is expected after #t")))
                (values 'value #t)]
               [(#\f #\F)
                (unless (char-delimiter? p (lookahead-char p))
                  (if (memq (reader-mode p) '(rnrs r7rs))
                      (let* ([c1 (and (memv (lookahead-char p) '(#\a #\A))
                                      (get-char p))]
                             [c2 (and c1
                                      (memv (lookahead-char p) '(#\l #\L))
                                      (get-char p))]
                             [c3 (and c2
                                      (memv (lookahead-char p) '(#\s #\S))
                                      (get-char p))]
                             [c4 (and c3
                                      (memv (lookahead-char p) '(#\e #\E))
                                      (get-char p))])
                        (unless (and c1
                                     c2
                                     c3
                                     c4
                                     (char-delimiter?
                                       p
                                       (lookahead-char p)))
                          (reader-warning p "Expected #false" c1 c2 c3
                            c4)))
                      (reader-warning
                        p
                        "A delimiter is expected after #f")))
                (values 'value #f)]
               [(#\\)
                (let lp ([char* '()])
                  (let ([c (lookahead-char p)])
                    (cond
                      [(and (pair? char*) (char-delimiter? p c))
                       (let ([char* (reverse char*)])
                         (cond
                           [(null? char*)
                            (reader-warning p "Empty character name")
                            (values 'value #\�)]
                           [(null? (cdr char*))
                            (values 'value (car char*))]
                           [(char=? (car char*) #\x)
                            (cond
                              [(for-all
                                 (lambda (c)
                                   (or (char<=? #\0 c #\9)
                                       (char<=? #\a c #\f)
                                       (char<=? #\A c #\F)))
                                 (cdr char*))
                               (let ([sv (string->number
                                           (list->string (cdr char*))
                                           16)])
                                 (cond
                                   [(unicode-scalar-value? sv)
                                    (values 'value (integer->char sv))]
                                   [else
                                    (reader-warning
                                      p
                                      "Hex-escaped character outside valid range"
                                      sv)
                                    (values 'value #\�)]))]
                              [else
                               (reader-warning
                                 p
                                 "Invalid character in hex-escaped character"
                                 (list->string (cdr char*)))
                               (values 'value #\�)])]
                           [else
                            (let ([char-name (list->string char*)]
                                  [char-names '(("nul" #\x00 r6rs) ("null" #\x00 r7rs)
                                                 ("alarm"
                                                   #\x07
                                                   r6rs
                                                   r7rs)
                                                 ("backspace"
                                                   #\x08
                                                   r6rs
                                                   r7rs)
                                                 ("tab" #\x09 r6rs r7rs)
                                                 ("linefeed"
                                                   #\x0a
                                                   r6rs)
                                                 ("newline"
                                                   #\x0a
                                                   r5rs
                                                   r6rs
                                                   r7rs)
                                                 ("vtab" #\x0b r6rs)
                                                 ("page" #\x0c r6rs)
                                                 ("return"
                                                   #\x0d
                                                   r6rs
                                                   r7rs)
                                                 ("esc" #\x1b r6rs)
                                                 ("escape" #\x1b r7rs)
                                                 ("space"
                                                   #\x20
                                                   r5rs
                                                   r6rs
                                                   r7rs)
                                                 ("delete"
                                                   #\x7f
                                                   r6rs
                                                   r7rs))])
                              (cond
                                [(or (assoc char-name char-names)
                                     (and (reader-fold-case? p)
                                          (assoc
                                            (string-foldcase char-name)
                                            char-names))) =>
                                 (lambda (char-data)
                                   (assert-mode
                                     p
                                     char-name
                                     (cons 'rnrs (cddr char-data)))
                                   (values 'value (cadr char-data)))]
                                [else
                                 (reader-warning
                                   p
                                   "Invalid character name"
                                   char-name)
                                 (values 'value #\�)]))]))]
                      [(and (null? char*) (eof-object? c))
                       (eof-warning p)
                       (values 'value #\�)]
                      [else (lp (cons (get-char p) char*))])))]
               [(#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9)
                (assert-mode p "#<n>=<datum> and #<n>#" '(rnrs r7rs))
                (let lp ([char* (list c)])
                  (let ([next (lookahead-char p)])
                    (cond
                      [(eof-object? next) (eof-warning p) (get-char p)]
                      [(char<=? #\0 next #\9)
                       (lp (cons (get-char p) char*))]
                      [(char=? next #\=)
                       (get-char p)
                       (values
                         'label
                         (string->number
                           (list->string (reverse char*))
                           10))]
                      [(char=? next #\#)
                       (get-char p)
                       (values
                         'reference
                         (string->number
                           (list->string (reverse char*))
                           10))]
                      [else
                       (reader-warning
                         p
                         "Expected #<n>=<datum> or #<n>#"
                         next)
                       (get-token* p)])))]
               [else
                (reader-warning p "Invalid #-syntax" c)
                (get-token* p)]))]
          [(char=? c #\") (values 'value (get-string p))]
          [(memv c '(#\0 #\1 #\2 #\3 #\4 #\5 #\6 #\7 #\8 #\9))
           (get-number p (list c))]
          [(memv c '(#\- #\+))
           (cond
             [(and (char=? c #\-) (eqv? #\> (lookahead-char p)))
              (get-identifier p c #f)]
             [(char-delimiter? p (lookahead-char p))
              (values 'identifier (if (eqv? c #\-) '- '+))]
             [else (get-number p (list c))])]
          [(char=? c #\.)
           (cond
             [(char-delimiter? p (lookahead-char p)) (values 'dot #f)]
             [(and (eq? (reader-mode p) 'r6rs)
                   (eqv? #\. (lookahead-char p)))
              (get-char p)
              (unless (eqv? #\. (get-char p))
                (reader-warning p "Expected the ... identifier"))
              (unless (char-delimiter? p (lookahead-char p))
                (reader-warning p "Expected the ... identifier"))
              (values 'identifier '...)]
             [else (get-number p (list c))])]
          [(or (char<=? #\a c #\z)
               (char<=? #\A c #\Z)
               (memv
                 c
                 '(#\! #\$ #\% #\& #\* #\/ #\: #\< #\= #\> #\? #\^ #\_
                       #\~))
               (and (memv (reader-mode p) '(rnrs r7rs))
                    (or (eqv? c #\@) (memv c '(#\‌ #\‍))))
               (and (> (char->integer c) 127)
                    (memq
                      (char-general-category c)
                      '(Lu Ll Lt Lm Lo Mn Nl No Pd Pc Po Sc Sm Sk So Co))))
           (get-identifier p c #f)]
          [(char=? c #\\)
           (let ([c (get-char p)])
             (cond
               [(eqv? c #\x)
                (get-identifier p (get-inline-hex-escape p) #f)]
               [else
                (cond
                  [(eof-object? c) (eof-warning p)]
                  [else
                   (reader-warning p "Invalid character following \\")])
                (get-token* p)]))]
          [else
           (case c
             [(#\() (values 'openp #f)]
             [(#\)) (values 'closep #f)]
             [(#\[) (values 'openb #f)]
             [(#\]) (values 'closeb #f)]
             [(#\') (values 'abbrev 'quote)]
             [(#\`) (values 'abbrev 'quasiquote)]
             [(#\,)
              (case (lookahead-char p)
                [(#\@) (get-char p) (values 'abbrev 'unquote-splicing)]
                [else (values 'abbrev 'unquote)])]
             [(#\|)
              (assert-mode p "Quoted identifiers" '(rnrs r7rs))
              (get-identifier p #f 'pipe)]
             [else
              (reader-warning p "Invalid leading character" c)
              (get-token* p)])])))
    (define (get-compound-datum p src terminator type labels)
      (define vec #f)
      (define vec^ #f)
      (let lp ([head '()]
               [head^ '()]
               [prev #f]
               [prev^ #f]
               [len 0])
        (pitch-let-values
          (((lextype x) (get-lexeme p)))
          (case lextype
            [(closep closeb eof)
             (unless (eq? lextype terminator)
               (if (eof-object? x)
                   (eof-warning p)
                   (reader-warning p "Mismatched parenthesis/brackets"
                     lextype x terminator)))
             (case type
               [(vector)
                (let ([s (list->vector head)] [s^ (list->vector head^)])
                  (set! vec s)
                  (set! vec^ (annotate src s s^))
                  (values vec vec^))]
               [(list) (values head (annotate src head head^))]
               [(bytevector)
                (let ([s (list->bytevector head)])
                  (values s (annotate src s s)))]
               [else
                (reader-error
                  p
                  "Internal error in get-compound-datum"
                  type)])]
            [(dot)
             (cond
               [(eq? type 'list)
                (pitch-let*-values
                  (((lextype x) (get-lexeme p))
                    ((d d^) (handle-lexeme p lextype x labels #t)))
                  (pitch-let-values
                    (((termtype _) (get-lexeme p)))
                    (cond
                      [(eq? termtype terminator)]
                      [(eq? termtype 'eof) (eof-warning p)]
                      [else
                       (reader-warning
                         p
                         "Improperly terminated dot list")]))
                  (cond
                    [(pair? prev)
                     (cond
                       [(eq? d^ 'reference)
                        (register-reference
                          p
                          labels
                          d
                          (lambda (d d^)
                            (set-cdr! prev d)
                            (set-cdr! prev^ d^)))]
                       [else (set-cdr! prev d) (set-cdr! prev^ d^)])]
                    [else (reader-warning p "Unexpected dot")])
                  (values head (annotate src head head^)))]
               [else
                (reader-warning p "Dot used in non-list datum")
                (lp head head^ prev prev^ len)])]
            [else
             (pitch-let-values
               (((d d^) (handle-lexeme p lextype x labels #t)))
               (cond
                 [(and (eq? type 'bytevector)
                       (or (eq? d^ 'reference)
                           (not (and (exact-integer? d) (<= 0 d 255)))))
                  (reader-warning p "Invalid datum in bytevector" x)
                  (lp head head^ prev prev^ len)]
                 [else
                  (let ([new-prev (cons d '())] [new-prev^ (cons d^ '())])
                    (when (pair? prev)
                      (set-cdr! prev new-prev)
                      (set-cdr! prev^ new-prev^))
                    (when (eq? d^ 'reference)
                      (register-reference
                        p
                        labels
                        d
                        (if (eq? type 'vector)
                            (lambda (d d^)
                              (vector-set! vec len d)
                              (vector-set!
                                (annotation-expression vec^)
                                len
                                d^))
                            (lambda (d d^)
                              (set-car! new-prev d)
                              (set-car! new-prev^ d^)))))
                    (if (pair? head)
                        (lp head head^ new-prev new-prev^ (+ len 1))
                        (lp new-prev new-prev^ new-prev new-prev^
                            (+ len 1))))]))]))))
    (define (handle-lexeme p lextype x labels allow-refs?)
      (let ([src (reader-source p)])
        (case lextype
          [(openp) (get-compound-datum p src 'closep 'list labels)]
          [(openb)
           (assert-mode p "Square brackets" '(rnrs r6rs))
           (get-compound-datum p src 'closeb 'list labels)]
          [(vector) (get-compound-datum p src 'closep 'vector labels)]
          [(bytevector)
           (get-compound-datum p src 'closep 'bytevector labels)]
          [(value eof identifier) (values x (annotate src x x))]
          [(abbrev)
           (pitch-let-values
             (((type lex) (get-lexeme p)))
             (cond
               [(eq? type 'eof) (eof-warning p) (values lex lex)]
               [else
                (pitch-let-values
                  (((d d^) (handle-lexeme p type lex labels #t)))
                  (let ([s (list x d)])
                    (values s (annotate src s (list x d^)))))]))]
          [(label)
           (pitch-let*-values
             (((lextype lexeme) (get-lexeme p))
               ((d d^)
                 (handle-lexeme p lextype lexeme labels allow-refs?)))
             (register-label p labels x d d^)
             (values d d^))]
          [else
           (cond
             [(and allow-refs? (eq? lextype 'reference))
              (values x 'reference)]
             [else
              (unless (and (eq? lextype 'shebang)
                           (eqv? (car x) 1)
                           (eqv? (cadr x) 0))
                (reader-warning p "Unexpected lexeme" lextype x))
              (pitch-let-values
                (((lextype x) (get-lexeme p)))
                (handle-lexeme p lextype x labels allow-refs?))])])))
    (define (make-labels) (make-integer-table))
    (define (register-label p labels label datum
             annotated-datum)
      (when labels
        (table-update!
          labels
          label
          (lambda (old)
            (when (car old) (reader-warning p "Duplicate label" label))
            (cons (cons datum annotated-datum) (cdr old)))
          (cons #f '()))))
    (define (register-reference _p labels label setter)
      (when labels
        (table-update!
          labels
          label
          (lambda (old) (cons (car old) (cons setter (cdr old))))
          (cons #f '()))))
    (define (resolve-labels p labels)
      (pitch-let-values
        (((ids datum/refs*) (table-entries labels)))
        (vector-for-each
          (lambda (id datum/refs)
            (cond
              [(car datum/refs) =>
               (lambda (datum)
                 (let ([refs (cdr datum/refs)])
                   (for-each
                     (lambda (ref) (ref (car datum) (cdr datum)))
                     refs)))]
              [else (reader-warning p "Missing label" id)]))
          ids
          datum/refs*)))))
