;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The Emit/R7RS program edge. All CLI policy remains in (pitch cli); this file
;; only maps its ten host operations to real ports and filesystem procedures.
(import
  (scheme base)
  (scheme file)
  (scheme process-context)
  (pitch cli)
  (emit filesystem))

(define (read-file path)
  (let ((port (open-input-file path)))
    (let loop ((characters '()))
      (let ((character (read-char port)))
        (if (eof-object? character)
            (begin (close-port port) (list->string (reverse characters)))
            (loop (cons character characters)))))))

;; The CLI calls this operation only for its same-directory temporary. Remove a
;; stale temporary from an interrupted earlier run before opening a new one;
;; the destination itself is touched only by replace-file below.
(define (write-file path text)
  (when (file-exists? path) (delete-file path))
  (let ((port (open-output-file path))) (display text port) (close-port port)))

(define host
  (make-host read-file
             write-file
             replace-file
             directory-list
             file-directory?
             file-symbolic-link?
             file-exists?
             (current-input-port)
             (current-output-port)
             (current-error-port)))

(define (parent-directory path)
  (let loop ((index (- (string-length path) 1)))
    (cond
      ((< index 0) ".")
      ((char=? (string-ref path index) #\/)
        (if (= index 0) "/" (substring path 0 index)))
      (else (loop (- index 1))))))

(define (path-join directory name)
  (if (string=? directory "/")
      (string-append directory name)
      (string-append directory "/" name)))

(define command (command-line))
(define default-config-path
  (path-join (parent-directory (car command)) "default-config.scm"))

(exit (run-cli (cdr command) host default-config-path))
