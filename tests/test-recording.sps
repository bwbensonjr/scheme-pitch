#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for what pitch adds to the vendored laesare reader: absolute offset
;; tracking, line counting for every line ending the grammar recognizes, and
;; source-text recording on tokens.
;;
;; The upstream suite in tests/test-reader.sps is the regression baseline and
;; is kept unmodified; everything pitch-specific belongs here.
#!r6rs

(import
  (rnrs (6))
  (pitch reader)
  (tests runner))

(define (make-string-reader input)
  (make-reader (open-string-input-port input) "<test>"))

;; Read every datum in input, then report the reader's final state.
(define (drain input select)
  (let ((r (make-string-reader input)))
    (let lp ()
      (unless (eof-object? (read-datum r))
        (lp)))
    (select r)))

(define (final-line input) (drain input reader-line))
(define (final-offset input) (drain input reader-offset))

;; Line endings
(test-begin "line-endings")

;; Linefeed is the case upstream already handled.
(test-equal 2 (final-line "a\nb"))

;; Carriage return alone. Upstream left the line counter at 1 here.
(test-equal 2 (final-line "a\rb"))

;; CRLF is one line ending, not two.
(test-equal 2 (final-line "a\r\nb"))

;; Carriage return followed by next-line is likewise one ending.
(test-equal 2 (final-line "a\r\x85;b"))

;; The remaining separators the grammar and get-comment recognize.
(test-equal 2 (final-line "a\x85;b"))
(test-equal 2 (final-line "a\x2028;b"))
(test-equal 2 (final-line "a\x2029;b"))

;; Several endings in sequence, mixing forms.
(test-equal 3 (final-line "a\r\nb\rc"))
(test-equal 4 (final-line "a\nb\r\nc\rd"))

;; No line ending at all.
(test-equal 1 (final-line "a b"))

;; A bare carriage return at end of input still ends its line.
(test-equal 2 (final-line "a\r"))

;; Positions after a comment must agree with the comment lexer, which consumes
;; the terminator itself.
(test-equal 2 (final-line "; comment\ra"))
(test-equal 2 (final-line "; comment\r\na"))
(test-equal 2 (final-line "; comment\x2028;a"))
(test-end)

;; Absolute offset
(test-begin "offset")

;; Nothing consumed yet.
(test-equal 0 (reader-offset (make-string-reader "(abc def)")))

;; Offset counts characters, and every character of the input is consumed by
;; the time the reader reports end of file.
(test-equal 9 (final-offset "(abc def)"))
(test-equal 0 (final-offset ""))
(test-equal 3 (final-offset "abc"))

;; Atmosphere counts too.
(test-equal 12 (final-offset "  a ; hi\n  b"))

;; Multi-byte characters count once each, not once per byte.
(test-equal 3 (final-offset "\x3bb;\x3bb;\x3bb;"))
(test-end)

(test-exit)
