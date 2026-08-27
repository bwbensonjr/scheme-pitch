;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Exercise formatter text through Emit's real textual file ports. The shell
;; driver constructs and compares the fixtures byte for byte; this program does
;; all reads and permitted writes through R7RS ports.
(import
  (scheme base)
  (scheme file)
  (scheme process-context)
  (pitch format)
  (tests config)
  (tests runner))

(define-syntax let-values
  (syntax-rules ()
    ((_ (((name ...) producer)) body ...)
     (call-with-values (lambda () producer) (lambda (name ...) body ...)))))

(define arguments (cdr (command-line)))
(unless (= (length arguments) 1)
  (error 'test-text-files-r7rs "expected one fixture-directory argument" arguments))
(define fixture-directory (car arguments))

(define (fixture name)
  (string-append fixture-directory "/" name))

(define (read-text path)
  (let ((port (open-input-file path)))
    (let loop ((characters '()))
      (let ((character (read-char port)))
        (if (eof-object? character)
            (begin
              (close-port port)
              (list->string (reverse characters)))
            (loop (cons character characters)))))))

(define (write-text path text)
  (when (file-exists? path) (delete-file path))
  (let ((port (open-output-file path)))
    (display text port)
    (close-port port)))

(define (format-file input-path output-path)
  (let ((source (read-text input-path)))
    (let-values (((output result)
                  (format-source source input-path default-config)))
      (when output (write-text output-path output))
      (values output result))))

(test-begin "real textual file ports")

;; The shell driver compares the two files byte for byte after this program
;; exits. This equality also proves the port round trip preserved the decoded
;; CRLF and Unicode characters.
(let ((text (read-text (fixture "raw-input.scm"))))
  (write-text (fixture "raw-output.scm") text)
  (test-equal text (read-text (fixture "raw-output.scm"))))

;; CRLF between tokens is re-derived whitespace, while Unicode token contents
;; survive exactly. The shell driver checks the expected UTF-8 bytes.
(let-values (((output result)
              (format-file (fixture "accepted.scm")
                           (fixture "accepted-output.scm"))))
  (test-equal 'ok (format-result-status result))
  (test-assert output))

;; A line ending inside a token is source text Pitch cannot reproduce yet. The
;; formatter returns no output, so the pre-existing sentinel file is never
;; opened or replaced.
(for-each
 (lambda (name)
   (let ((output-path (fixture (string-append name "-output.scm"))))
     (let-values (((output result)
                   (format-file (fixture (string-append name ".scm"))
                                output-path)))
       (test-equal 'unsupported-line-ending (format-result-status result))
       (test-equal #f output)
       (test-equal "sentinel\n" (read-text output-path)))))
 '("interior-crlf" "interior-unicode"))

(test-end)
(test-exit)
