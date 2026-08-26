(import (scheme base) (pitch cst) (pitch diagnostic) (pitch parse) (pitch reader))

(define (check name expected actual)
  (if (equal? expected actual) #t (error name "mismatch" expected actual)))

(define (parsed source)
  (call-with-values
    (lambda () (parse-source source "<test>"))
    (lambda (document diagnostics) document)))

(define (diagnostics-of source)
  (call-with-values
    (lambda () (parse-source source "<test>"))
    (lambda (document diagnostics) diagnostics)))

(define (only-form source) (car (datum-children (parsed source))))
(define (round-trip source) (cst->text (parsed source)))

;; Losslessness is checked against the original text, including malformed text.
(for-each
  (lambda (source) (check 'round-trip source (round-trip source)))
  '("" "\n\n" "(a b)" "[a b]" "(let ([x 1]) x)"
    "  (a ; note\n b)  " "#| block\ncomment |# #;(a b) c"
    "'x `y ,z ,@w" "#'x #`y #,z #,@w"
    "#xff 1E10 \"\\x41;\" #\\null |foo bar|"
    "#(1 2) #vu8(3 4) #u8(5 6)" "#0=(a . #0#)"
    "(a (b" "a)" "'" "(. a)" "(a . b c)" "(a]" "(a #z b)"))

;; Token sequence and leaf sequence are exactly the same objects.
(call-with-values
  (lambda () (tokenize "#(1 #;(x) 2) '[a . b]" "<test>"))
  (lambda (tokens diagnostics)
    (call-with-values
      (lambda () (parse-tokens tokens))
      (lambda (document parse-diagnostics)
        (check 'leaf-count (vector-length tokens) (length (cst-tokens document)))
        (check 'same-tokens #t (equal? (vector->list tokens) (cst-tokens document)))))))

;; Trivia remains in place as ordinary children.
(define commented (only-form "(a ; note\n b)"))
(check 'comment-children
       '("a" " " "; note\n" " " "b")
       (map cst->text (node-children commented)))
(check 'comment-data '("a" "b") (map cst->text (datum-children commented)))

;; Bracket shapes remain distinct tokens while sharing the list node kind.
(define parens (only-form "(a)"))
(define brackets (only-form "[a]"))
(check 'paren-kind 'list (node-kind parens))
(check 'bracket-kind 'list (node-kind brackets))
(check 'paren-open "(" (cst->text (compound-open parens)))
(check 'bracket-open "[" (cst->text (compound-open brackets)))
(check 'bracket-close "]" (cst->text (compound-close brackets)))

;; Prefixes and datum comments retain their spellings and structure.
(check 'prefix-marker "'" (cst->text (prefix-marker (only-form "'x"))))
(check 'prefix-datum "x" (cst->text (prefix-datum (only-form "'x"))))
(check 'datum-comment-trivia
       '("a" "d")
       (map cst->text (datum-children (only-form "(a #;(b c) d)"))))

;; Malformed input is diagnosed, never repaired.
(check 'clean 0 (length (diagnostics-of "(a b)")))
(check 'two-unclosed 2 (length (diagnostics-of "(a (b")))
(check 'stray-close 1 (length (diagnostics-of "a)")))
(check 'mismatch 1 (length (diagnostics-of "(a]")))
(check 'bad-dot 1 (length (diagnostics-of "(. a)")))
(check 'bad-number 1 (length (diagnostics-of "(a 1e+ b)")))

;; Diagnostic positions come from the token re-read from the source.
(define positioned (car (diagnostics-of "x\ny\n)")))
(check 'diagnostic-line 3 (diagnostic-line positioned))
(check 'diagnostic-column 0 (diagnostic-column positioned))
(check 'diagnostic-token-line
       (token-start-line (diagnostic-token positioned))
       (diagnostic-line positioned))

(display "test-cst-r7rs: ok\n")
