;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Line endings, defined once.
;;
;; The reader's grammar counts seven: line feed, carriage return, CR LF, CR NEL,
;; next line, line separator, and paragraph separator. Four layers need to agree
;; about that set and disagree about nothing:
;;
;;   (pitch doc)     text refuses one; verbatim splits at one
;;   (pitch check)   layer 1 trims one trailing ending before comparing text
;;   (pitch print)   a line comment's terminator is split off and re-emitted
;;   (pitch format)  an interior ending the engine cannot reproduce is refused
;;
;; Before this library, doc.sls and check.sls each carried their own copy, with
;; a comment in doc.sls observing that "two definitions of line ending in one
;; codebase is a divergence waiting to happen". Adding a third for the printer
;; would have been the one that drifted, since it is the copy nothing else
;; exercises. So there is one, and it is here rather than in any of the four
;; because check must not import the layout algebra.
;;
;; The two-character forms are the whole subtlety. CR LF and CR NEL are one
;; ending, not two, so a naive character scan counts a CRLF file's lines twice
;; and splits "a\r\nb" into three pieces instead of two.

#!r6rs

(library (pitch lines)
  (export
    line-ending-char? line-ending-index line-ending-pieces line-ending-count
    strip-final-line-ending)
  (import (rnrs base (6)) (rnrs control (6)))

  ;; The five characters that can begin an ending. The two-character forms both
  ;; begin with CR, so recognizing these five recognizes all seven.
  (define (line-ending-char? c)
    (or (char=? c #\linefeed)
        (char=? c #\return)
        (char=? c #\x85)
        (char=? c #\x2028)
        (char=? c #\x2029)))

  ;; The index of the first ending character, or #f. Used by text to refuse.
  (define (line-ending-index s)
    (let ((n (string-length s)))
      (let loop ((i 0))
        (cond
          ((= i n) #f)
          ((line-ending-char? (string-ref s i)) i)
          (else (loop (+ i 1)))))))

  ;; The index just past the ending that starts at i.
  (define (skip-line-ending s i n)
    (if (and (char=? (string-ref s i) #\return)
             (< (+ i 1) n)
             (let ((c (string-ref s (+ i 1))))
               (or (char=? c #\linefeed) (char=? c #\x85))))
        (+ i 2)
        (+ i 1)))

  ;; The pieces of s between its endings, in order. Always at least one piece, so
  ;; the ending count is one less than the length: "" is one piece, "a" is one,
  ;; "a\nb" is two, "a\n" is two -- the second being empty, which is what says the
  ;; string ended with an ending rather than that it had none.
  (define (line-ending-pieces s)
    (let ((n (string-length s)))
      (let loop ((i 0) (start 0) (acc '()))
        (cond
          ((= i n) (reverse (cons (substring s start n) acc)))
          ((line-ending-char? (string-ref s i))
            (let ((next (skip-line-ending s i n)))
              (loop next next (cons (substring s start i) acc))))
          (else (loop (+ i 1) start acc))))))

  ;; The same count without building the pieces. Every whitespace token in a file
  ;; goes through this one.
  (define (line-ending-count s)
    (let ((n (string-length s)))
      (let loop ((i 0) (count 0))
        (cond
          ((= i n) count)
          ((line-ending-char? (string-ref s i))
            (loop (skip-line-ending s i n) (+ count 1)))
          (else (loop (+ i 1) count))))))

  ;; Drop one trailing ending, the two-character forms counting as one. A string
  ;; that does not end with one is returned unchanged.
  (define (strip-final-line-ending s)
    (let ((n (string-length s)))
      (if (= n 0)
          s
          (let ((last (string-ref s (- n 1))))
            (cond
              ((or (char=? last #\linefeed) (char=? last #\x85))
                (if (and (>= n 2) (char=? (string-ref s (- n 2)) #\return))
                    (substring s 0 (- n 2))
                    (substring s 0 (- n 1))))
              ((or (char=? last #\return) (char=? last #\x2028) (char=? last #\x2029))
                (substring s 0 (- n 1)))
              (else s)))))))
