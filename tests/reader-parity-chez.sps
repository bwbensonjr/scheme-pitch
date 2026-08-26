#!/usr/bin/env scheme-script
#!r6rs

(import
  (rnrs (6))
  (pitch reader))

(define open-input-string open-string-input-port)

(define (diagnostic-data raised)
  (list (if (message-condition? raised) (condition-message raised) "unknown error")
        (if (source-condition? raised) (source-line raised) #f)
        (if (source-condition? raised) (source-column raised) #f)))
