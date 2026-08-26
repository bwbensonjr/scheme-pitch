#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; SPDX-License-Identifier: MIT
#!r6rs

(import
  (rnrs (6))
  (pitch reader)
  (tests runner))

(define (first-token text)
  (get-token (make-reader (open-string-input-port text) "<number-test>")))

(define (recognized-number? text)
  (let ((token (first-token text)))
    (and (eq? (token-kind token) 'value)
         (number? (token-value token))
         (string=? (token-text token) text))))

(define (invalid-number? text)
  (guard (condition
          ((lexical-violation? condition) #t)
          (else #f))
    (first-token text)
    #f))

(test-begin "valid-number-syntax")
(for-each
  (lambda (text) (test-assert (recognized-number? text)))
  '("0" "-42"
    "#xff" "#e#x10" "#x#e10" "#B1010"
    "3/4" "#i1/3"
    ".5" "1." "1.25"
    "1e3" "1E-3" "1s2" "1.0|24"
    "1+2i" "1-i" "+2i" "1+inf.0i"
    "1@2" "-1@+2"
    "+inf.0" "-INF.0" "+nan.0" "-NaN.0"))
(test-end)

(test-begin "invalid-number-syntax")
(for-each
  (lambda (text) (test-assert (invalid-number? text)))
  '("1/" "1//2" "1/0" "#x1/00"
    "1e" "1e+" "1.2.3"
    "#x" "#xg" "#b2" "#x1.0"
    "1+2" "1+2j" "1@" "1@@2"
    "1|" "1e2|"
    "#e#i1" "#x#d1"))
(test-end)

(test-exit)
