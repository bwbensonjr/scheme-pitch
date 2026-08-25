;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Test-only access to the shipped external defaults. Production file I/O stays
;; in (pitch cli); tests need resolved values for the pure library interfaces.
#!r6rs

(library (tests config)
(export default-config default-config-text make-test-config make-test-config-with)
(import
  (rnrs base (6))
  (rnrs io simple (6))
  (rnrs io ports (6))
  (pitch config))

(define default-config-path "src/pitch/default-config.scm")

(define (file-text path)
  (let ((port (open-input-file path)))
    (let ((text (get-string-all port)))
      (close-port port)
      (if (eof-object? text) "" text))))

(define default-config-text (file-text default-config-path))
(define default-overlay (parse-config default-config-text default-config-path))
(define default-config (resolve-config default-overlay #f #f #f))

(define (make-test-config width dialect)
  (resolve-config default-overlay #f width dialect))

(define (make-test-config-with text width dialect)
  (resolve-config default-overlay (parse-config text "<test-config>") width dialect)))
