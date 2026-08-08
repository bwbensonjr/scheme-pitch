#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The `pitch` program: build a real host, run the driver, exit with what it
;; returned.
;;
;; THIS FILE HOLDS THE IMPLEMENTATION-SPECIFIC CODE AND NO DECISIONS. Every rule
;; about what pitch does -- the argument grammar, the write rule, the exit
;; statuses, what is refused -- lives in (pitch cli), which is portable R6RS and
;; is tested against an in-memory host. What is left here is the wiring, and it
;; is deliberately dull enough to read in one screen.
;;
;; Porting pitch to another R6RS implementation means rewriting this file and
;; nothing else. Only two of the operations below are outside the standard:
;; directory-list and file-directory?, plus file-symbolic-link? for the rule
;; that a walk does not descend into a linked directory. `command-line` and
;; `exit` are (rnrs programs (6)) and need no implementation-specific import at
;; all; reading and writing are (rnrs io ports (6)).
;;
;; The first element of `command-line` is the program itself, so the driver is
;; handed its cdr.

#!r6rs

(import
  (rnrs (6))
  (rnrs programs (6))
  (only (chezscheme) directory-list file-directory? file-symbolic-link?
        rename-file)
  (pitch cli))

;; Files are UTF-8. The reader and the printer both work in characters, and the
;; safety checks compare the text that came in against the text that goes out,
;; so the one thing that must not vary between those two is the transcoder.
(define (utf8-transcoder)
  (make-transcoder (utf-8-codec) (eol-style none) (error-handling-mode raise)))

(define (read-file path)
  (let ((port (open-file-input-port path (file-options) (buffer-mode block)
                                    (utf8-transcoder))))
    (let ((text (get-string-all port)))
      (close-port port)
      (if (eof-object? text) "" text))))

;; no-fail lets the temporary be overwritten if a previous run died between
;; writing it and renaming it.
(define (write-file path text)
  (let ((port (open-file-output-port path (file-options no-fail)
                                     (buffer-mode block) (utf8-transcoder))))
    (put-string port text)
    (close-port port)))

;; R6RS has no rename, which is the one operation the atomic write needs and
;; cannot get portably. Chez's is in the same library as the other three.
(define host
  (make-host
    read-file
    write-file
    (lambda (from to) (rename-file from to))
    (lambda (path) (directory-list path))
    (lambda (path) (file-directory? path))
    (lambda (path) (file-symbolic-link? path))
    (lambda (path) (file-exists? path))
    (current-input-port)
    (current-output-port)
    (current-error-port)))

(exit (run-cli (cdr (command-line)) host))
