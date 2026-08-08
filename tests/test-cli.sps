#!/usr/bin/env scheme-script
;; -*- mode: scheme; coding: utf-8 -*- !#
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; Tests for the command line.
;;
;; THE IMPORTANT ASSERTIONS HERE ARE NEGATIVE, and that is what the in-memory
;; host is for. "A refused file is not written" and "an already-formatted file
;; is not written" are the two claims that matter most in this layer, because
;; this is the only part of pitch that can destroy a user's source. Against a
;; real filesystem they would mean comparing modification times and hoping about
;; clock resolution. Against a host backed by an association list they mean the
;; write log is empty, which is exact and fast.
;;
;; The host also records renames separately from writes, so the atomic-write
;; protocol -- write beside the target, rename over it -- is checked rather than
;; assumed.
;;
;; WHAT IS NOT COVERED HERE. `format-source` cannot be made to return a
;; check-failed status from outside: it arises only from a printer bug, and
;; tests/test-format.sps exercises the check machinery directly for that reason.
;; The CLI branches on `(eq? status 'ok)` in exactly one place, so check-failed
;; takes the identical no-write path as the two refusals that are exercised
;; below; what is untested is only the wording of its message.

#!r6rs

(import
  (rnrs (6))
  (pitch cli)
  (only (pitch format) format-source format-result-status)
  (tests runner))

;;; The in-memory filesystem

(define-record-type fs
  (fields (mutable files)                ;alist of path -> contents
          (mutable writes)               ;reverse list of paths written
          (mutable renames)              ;reverse list of (from . to)
          dirs links unreadable unwritable)
  (sealed #t) (opaque #f)
  (nongenerative fs-v0-b1d7c4a2-8e35-4f90-a6c8-3d21e7fb5904))

(define (fs-new files dirs links unreadable unwritable)
  (make-fs files '() '() dirs links unreadable unwritable))

(define (has? path list) (and (member path list) #t))

(define (fs-read fs path)
  (cond ((has? path (fs-unreadable fs))
         (assertion-violation 'read-file "permission denied" path))
        ((assoc path (fs-files fs)) => cdr)
        (else (assertion-violation 'read-file "no such file" path))))

(define (fs-write! fs path text)
  (when (has? path (fs-unwritable fs))
    (assertion-violation 'write-file "permission denied" path))
  (fs-writes-set! fs (cons path (fs-writes fs)))
  (fs-files-set! fs (cons (cons path text)
                          (remp (lambda (e) (string=? (car e) path))
                                (fs-files fs)))))

(define (fs-rename! fs from to)
  (let ((text (fs-read fs from)))
    (fs-renames-set! fs (cons (cons from to) (fs-renames fs)))
    (fs-files-set! fs (cons (cons to text)
                            (remp (lambda (e)
                                    (or (string=? (car e) from)
                                        (string=? (car e) to)))
                                  (fs-files fs))))))

(define (parent-of path)
  (let loop ((i (- (string-length path) 1)))
    (cond ((< i 0) "")
          ((char=? (string-ref path i) #\/) (substring path 0 i))
          (else (loop (- i 1))))))

(define (basename path)
  (let loop ((i (- (string-length path) 1)))
    (cond ((< i 0) path)
          ((char=? (string-ref path i) #\/)
           (substring path (+ i 1) (string-length path)))
          (else (loop (- i 1))))))

;; Every known path whose parent is this directory, files and subdirectories
;; alike, as bare entry names -- which is what a real directory listing gives.
(define (fs-list fs dir)
  (let ((all (append (map car (fs-files fs)) (fs-dirs fs))))
    (map basename
         (filter (lambda (p) (string=? (parent-of p) dir)) all))))

(define (fs-exists? fs path)
  (or (and (assoc path (fs-files fs)) #t)
      (has? path (fs-dirs fs))))

;; The write log as target paths in the order they were replaced. A file is
;; "written" when a rename put new contents at its path; the temporary that
;; preceded it is in fs-writes.
(define (replaced fs) (reverse (map cdr (fs-renames fs))))
(define (written fs) (reverse (fs-writes fs)))
(define (contents fs path) (cond ((assoc path (fs-files fs)) => cdr) (else #f)))

;;; Running the driver

(define-record-type run
  (fields status out err fs)
  (sealed #t) (opaque #f)
  (nongenerative run-v0-4c9e2a71-6b83-4d15-9f27-8ae0c3b6d142))

(define (invoke args fs stdin-text)
  (let-values (((out get-out) (open-string-output-port))
               ((err get-err) (open-string-output-port)))
    (let* ((host (make-host
                   (lambda (p) (fs-read fs p))
                   (lambda (p t) (fs-write! fs p t))
                   (lambda (a b) (fs-rename! fs a b))
                   (lambda (p) (fs-list fs p))
                   (lambda (p) (has? p (fs-dirs fs)))
                   (lambda (p) (has? p (fs-links fs)))
                   (lambda (p) (fs-exists? fs p))
                   (open-string-input-port stdin-text)
                   out
                   err))
           (status (run-cli args host)))
      (make-run status (get-out) (get-err) fs))))

;; The common case: some files, no directories, no failures, empty stdin.
(define (run-files args files)
  (invoke args (fs-new files '() '() '() '()) ""))

(define (run-stdin args text)
  (invoke args (fs-new '() '() '() '() '()) text))

(define (string-contains? haystack needle)
  (let ((n (string-length haystack)) (m (string-length needle)))
    (let loop ((i 0))
      (cond ((> (+ i m) n) #f)
            ((string=? (substring haystack i (+ i m)) needle) #t)
            (else (loop (+ i 1)))))))

;;; The sources the tests format
;;
;; `tidy` is computed rather than written out, so these tests assert what the
;; CLI does with the pipeline's output rather than re-encoding the layout
;; engine's decisions. A change in layout cannot silently invalidate them.

(define (formatted text)
  (let-values (((out result) (format-source text "x" 88 'common)))
    out))

(define ugly "(define  (f  x)   (+ x  1))\n")
(define tidy (formatted ugly))
(define bad "(a\n")
(define crlf "#| a\r\nb |#\n(a)\n")

(test-begin "the sources behave as these tests assume")

;; Preconditions. If any of these stops holding, the tests below stop meaning
;; what they say, so they are asserted rather than assumed.
(test-assert (string? tidy))
(test-assert (not (string=? ugly tidy)))
(test-equal tidy (formatted tidy))
(test-equal 'unclean-parse
            (let-values (((o r) (format-source bad "x" 88 'common)))
              (format-result-status r)))
(test-equal 'unsupported-line-ending
            (let-values (((o r) (format-source crlf "x" 88 'common)))
              (format-result-status r)))

(test-end)

;;; 2. Argument parsing

(test-begin "the defaults apply when no option is given")

(let ((r (run-files '("a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal (list "a.sls") (replaced (run-fs r)))
  (test-equal tidy (contents (run-fs r) "a.sls"))
  (test-equal "" (run-out r)))

(test-end)

(test-begin "the width reaches the formatter")

;; A narrow width must change the output; that it is honored at all is
;; format-pipeline's requirement, and this asserts only that the flag arrives.
(let ((r (run-files '("--stdout" "--width" "20" "a.sls")
                    (list (cons "a.sls" "(aaaa bbbb cccc dddd eeee)\n")))))
  (test-equal 0 (run-status r))
  (test-assert (not (string=? (run-out r) "(aaaa bbbb cccc dddd eeee)\n"))))

(test-end)

(test-begin "the dialect reaches the formatter")

;; define-record-type is the form whose shape collides between the standards,
;; so it is the one whose output can differ by dialect.
(let* ((src "(define-record-type point (fields x y) (sealed #t) (opaque #f))\n")
       (a (run-files (list "--stdout" "--width" "30" "--dialect" "r6rs" "a.sls")
                     (list (cons "a.sls" src))))
       (b (run-files (list "--stdout" "--width" "30" "--dialect" "r7rs" "a.sls")
                     (list (cons "a.sls" src)))))
  (test-equal 0 (run-status a))
  (test-equal 0 (run-status b))
  (test-assert (not (string=? (run-out a) (run-out b)))))

(test-end)

(test-begin "options and operands may be interleaved")

(let ((r (run-files '("a.sls" "--width" "40") (list (cons "a.sls" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal (list "a.sls") (replaced (run-fs r))))

(test-end)

(test-begin "-- ends option parsing")

(let ((r (run-files '("--" "-weird.sls") (list (cons "-weird.sls" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal (list "-weird.sls") (replaced (run-fs r))))

(test-end)

(test-begin "an unknown option is a usage error")

(let ((r (run-files '("--verbose" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-assert (string-contains? (run-err r) "--verbose"))
  ;; No file is read and no file is written.
  (test-equal '() (written (run-fs r)))
  (test-equal ugly (contents (run-fs r) "a.sls")))

(test-end)

(test-begin "an option missing its value is a usage error")

(let ((r (run-files '("--width") '())))
  (test-equal 2 (run-status r))
  (test-assert (string-contains? (run-err r) "--width")))

(let ((r (run-files '("--dialect") '())))
  (test-equal 2 (run-status r))
  (test-assert (string-contains? (run-err r) "--dialect")))

(test-end)

(test-begin "option values are validated before any file is opened")

;; The whole point: three operands, and none of them is touched.
(let ((r (run-files '("--dialect" "r5rs" "a.sls" "b.sls" "c.sls")
                    (list (cons "a.sls" ugly) (cons "b.sls" ugly)
                          (cons "c.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r)))
  (test-equal ugly (contents (run-fs r) "a.sls"))
  (test-equal ugly (contents (run-fs r) "b.sls"))
  (test-equal ugly (contents (run-fs r) "c.sls")))

(let ((r (run-files '("--width" "wide" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r))))

(let ((r (run-files '("--width" "0" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r))))

(let ((r (run-files '("--width" "-3" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r))))

(test-end)

(test-begin "two dispositions together are a usage error")

(let ((r (run-files '("--stdout" "--check" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r))))

(let ((r (run-files '("--check" "--stdout" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r))))

(test-end)

(test-begin "help and version succeed on standard output")

(let ((r (run-files '("--help") '())))
  (test-equal 0 (run-status r))
  (test-assert (string-contains? (run-out r) "usage: pitch"))
  (test-equal "" (run-err r)))

(let ((r (run-files '("--version") '())))
  (test-equal 0 (run-status r))
  (test-assert (string-contains? (run-out r) "pitch"))
  (test-equal "" (run-err r)))

;; Help wins over operands, and reads nothing.
(let ((r (run-files '("--help" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal '() (written (run-fs r)))
  (test-equal ugly (contents (run-fs r) "a.sls")))

(test-end)

(test-begin "an invocation naming no input fails on standard error")

;; The contrast with --help is the entire reason both spellings exist: the same
;; text, the other stream, the other status.
(let ((r (run-files '() '())))
  (test-equal 2 (run-status r))
  (test-assert (string-contains? (run-err r) "usage: pitch"))
  (test-equal "" (run-out r)))

;; Options that name no input are the same case.
(let ((r (run-files '("--width" "40") '())))
  (test-equal 2 (run-status r))
  (test-assert (string-contains? (run-err r) "usage: pitch")))

;; --check no longer implies standard input, so it must name something.
(let ((r (run-files '("--check") '())))
  (test-equal 2 (run-status r))
  (test-assert (string-contains? (run-err r) "usage: pitch")))

;; And a bare invocation must not consume standard input.
(let ((r (run-stdin '() ugly)))
  (test-equal 2 (run-status r))
  (test-equal "" (run-out r)))

(test-end)

;;; 3. Input selection

(test-begin "standard input is read when it is named")

(let ((r (run-stdin '("-") ugly)))
  (test-equal 0 (run-status r))
  (test-equal tidy (run-out r))
  (test-equal '() (written (run-fs r))))

(let ((r (run-stdin '("--stdout") ugly)))
  (test-equal 0 (run-status r))
  (test-equal tidy (run-out r)))

;; --stdout with - says the same thing twice, which is allowed.
(let ((r (run-stdin '("--stdout" "-") ugly)))
  (test-equal 0 (run-status r))
  (test-equal tidy (run-out r)))

(test-end)

(test-begin "a refusal on standard input names <stdin> and writes no text")

(let ((r (run-stdin '("-") bad)))
  (test-equal 1 (run-status r))
  (test-equal "" (run-out r))
  (test-assert (string-contains? (run-err r) "<stdin>:1:")))

(test-end)

(test-begin "check mode works on named standard input")

(let ((r (run-stdin '("--check" "-") ugly)))
  (test-equal 1 (run-status r))
  (test-equal "" (run-out r)))

(let ((r (run-stdin '("--check" "-") tidy)))
  (test-equal 0 (run-status r))
  (test-equal "" (run-out r))
  (test-equal "" (run-err r)))

(test-end)

(test-begin "standard input cannot be mixed with other operands")

(let ((r (invoke '("-" "a.sls") (fs-new (list (cons "a.sls" ugly)) '() '() '() '())
                 ugly)))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r)))
  (test-equal ugly (contents (run-fs r) "a.sls"))
  ;; Standard input is not consumed either.
  (test-equal "" (run-out r)))

(let ((r (invoke '("--stdout" "-" "a.sls")
                 (fs-new (list (cons "a.sls" ugly)) '() '() '() '()) ugly)))
  (test-equal 2 (run-status r))
  (test-equal "" (run-out r)))

(test-end)

(test-begin "a named file is formatted whatever its extension")

(let ((r (run-files '("notes.txt") (list (cons "notes.txt" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal tidy (contents (run-fs r) "notes.txt")))

(let ((r (run-files '("plain") (list (cons "plain" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal tidy (contents (run-fs r) "plain")))

(test-end)

;;; Directory discovery

(define (tree-fs)
  (fs-new (list (cons "d/a.sls" ugly)
                (cons "d/b.sps" ugly)
                (cons "d/readme.md" ugly)
                (cons "d/sub/c.scm" ugly)
                (cons "d/.git/h.scm" ugly)
                (cons "d/link/x.sls" ugly))
          '("d" "d/sub" "d/.git" "d/link")
          '("d/link")
          '() '()))

(test-begin "a directory operand yields its Scheme files")

(let ((r (invoke '("d") (tree-fs) "")))
  (test-equal 0 (run-status r))
  ;; Depth-first, name order at each level. readme.md is not a Scheme file,
  ;; .git is hidden, and d/link is a symbolic link to a directory.
  (test-equal '("d/a.sls" "d/b.sps" "d/sub/c.scm") (replaced (run-fs r)))
  (test-equal ugly (contents (run-fs r) "d/readme.md"))
  (test-equal ugly (contents (run-fs r) "d/.git/h.scm"))
  (test-equal ugly (contents (run-fs r) "d/link/x.sls")))

(test-end)

(test-begin "the traversal order is deterministic")

(let ((a (invoke '("--check" "d") (tree-fs) ""))
      (b (invoke '("--check" "d") (tree-fs) "")))
  (test-equal (run-err a) (run-err b))
  (test-assert (string-contains? (run-err a) "d/a.sls")))

(test-end)

(test-begin "a linked directory is walked when named as an operand")

(let ((r (invoke '("d/link") (tree-fs) "")))
  (test-equal 0 (run-status r))
  (test-equal '("d/link/x.sls") (replaced (run-fs r))))

(test-end)

(test-begin "a directory with no Scheme file succeeds having done nothing")

(let ((r (invoke '("e") (fs-new (list (cons "e/readme.md" ugly)) '("e") '()
                                '() '())
                 "")))
  (test-equal 0 (run-status r))
  (test-equal '() (written (run-fs r))))

(test-end)

(test-begin "a missing or unreadable operand is a usage error")

(let ((r (run-files '("nope.sls") '())))
  (test-equal 2 (run-status r))
  (test-assert (string-contains? (run-err r) "nope.sls")))

;; The remaining operands are still processed.
(let ((r (run-files '("nope.sls" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 2 (run-status r))
  (test-equal tidy (contents (run-fs r) "a.sls")))

(let ((r (invoke '("a.sls") (fs-new (list (cons "a.sls" ugly)) '() '()
                                    '("a.sls") '())
                 "")))
  (test-equal 2 (run-status r))
  (test-equal '() (written (run-fs r)))
  (test-assert (string-contains? (run-err r) "a.sls")))

(test-end)

;;; 4 and 6. The write path, stated as negatives

(test-begin "an already-formatted file is not written at all")

(let ((r (run-files '("a.sls") (list (cons "a.sls" tidy)))))
  (test-equal 0 (run-status r))
  (test-equal '() (written (run-fs r)))
  (test-equal '() (replaced (run-fs r)))
  (test-equal tidy (contents (run-fs r) "a.sls")))

(test-end)

(test-begin "a second run over a directory writes nothing")

(let* ((fs (tree-fs))
       (first (invoke '("d") fs ""))
       (before (length (fs-renames fs)))
       (second (invoke '("d") fs "")))
  (test-equal 0 (run-status first))
  (test-equal 0 (run-status second))
  (test-equal 3 before)
  ;; Nothing further was written the second time round.
  (test-equal 3 (length (fs-renames fs))))

(test-end)

(test-begin "the write is atomic")

(let ((r (run-files '("a.sls") (list (cons "a.sls" ugly)))))
  ;; Written beside the target, then renamed over it.
  (test-equal '("a.sls.pitch-tmp") (written (run-fs r)))
  (test-equal '(("a.sls.pitch-tmp" . "a.sls")) (reverse (fs-renames (run-fs r))))
  (test-equal tidy (contents (run-fs r) "a.sls")))

(test-end)

(test-begin "a failed write leaves the original intact")

(let ((r (invoke '("a.sls") (fs-new (list (cons "a.sls" ugly)) '() '() '()
                                    '("a.sls.pitch-tmp"))
                 "")))
  (test-equal 2 (run-status r))
  (test-equal ugly (contents (run-fs r) "a.sls"))
  (test-equal '() (replaced (run-fs r)))
  (test-assert (string-contains? (run-err r) "a.sls")))

(test-end)

(test-begin "a refused file is left byte-identical")

;; An unclean parse.
(let ((r (run-files '("a.sls") (list (cons "a.sls" bad)))))
  (test-equal 1 (run-status r))
  (test-equal '() (written (run-fs r)))
  (test-equal bad (contents (run-fs r) "a.sls"))
  (test-assert (string-contains? (run-err r) "a.sls:")))

;; An unsupported line ending.
(let ((r (run-files '("a.sls") (list (cons "a.sls" crlf)))))
  (test-equal 1 (run-status r))
  (test-equal '() (written (run-fs r)))
  (test-equal crlf (contents (run-fs r) "a.sls"))
  (test-assert (string-contains? (run-err r) "line ending")))

(test-end)

(test-begin "a refusal writes nothing under --stdout and --check")

(let ((r (run-files '("--stdout" "a.sls") (list (cons "a.sls" bad)))))
  (test-equal 1 (run-status r))
  (test-equal "" (run-out r))
  (test-equal '() (written (run-fs r))))

(let ((r (run-files '("--check" "a.sls") (list (cons "a.sls" bad)))))
  (test-equal 1 (run-status r))
  (test-equal "" (run-out r))
  (test-equal '() (written (run-fs r)))
  (test-equal bad (contents (run-fs r) "a.sls")))

(test-end)

(test-begin "a multi-file run continues past a refusal")

(let ((r (run-files '("a.sls" "b.sls" "c.sls")
                    (list (cons "a.sls" ugly) (cons "b.sls" bad)
                          (cons "c.sls" ugly)))))
  (test-equal 1 (run-status r))
  (test-equal '("a.sls" "c.sls") (replaced (run-fs r)))
  (test-equal tidy (contents (run-fs r) "a.sls"))
  (test-equal bad (contents (run-fs r) "b.sls"))
  (test-equal tidy (contents (run-fs r) "c.sls"))
  (test-assert (string-contains? (run-err r) "b.sls:")))

(test-end)

;;; --stdout and --check

(test-begin "--stdout writes the formatted text and touches no file")

(let ((r (run-files '("--stdout" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal tidy (run-out r))
  (test-equal '() (written (run-fs r)))
  (test-equal ugly (contents (run-fs r) "a.sls")))

;; Several files concatenate with nothing between them.
(let ((r (run-files '("--stdout" "a.sls" "b.sls")
                    (list (cons "a.sls" ugly) (cons "b.sls" ugly)))))
  (test-equal 0 (run-status r))
  (test-equal (string-append tidy tidy) (run-out r)))

;; Diagnostics never reach standard output.
(let ((r (run-files '("--stdout" "a.sls" "b.sls")
                    (list (cons "a.sls" ugly) (cons "b.sls" bad)))))
  (test-equal 1 (run-status r))
  (test-equal tidy (run-out r))
  (test-assert (string-contains? (run-err r) "b.sls:")))

(test-end)

(test-begin "--check writes nothing and reports what would change")

(let ((r (run-files '("--check" "a.sls") (list (cons "a.sls" ugly)))))
  (test-equal 1 (run-status r))
  (test-equal "" (run-out r))
  (test-equal '() (written (run-fs r)))
  (test-assert (string-contains? (run-err r) "would reformat")))

;; A file that would not change is silent.
(let ((r (run-files '("--check" "a.sls") (list (cons "a.sls" tidy)))))
  (test-equal 0 (run-status r))
  (test-equal "" (run-err r))
  (test-equal '() (written (run-fs r))))

(test-end)

;;; 5. Reporting and exit status

(test-begin "diagnostics are path:line:column: message on standard error")

(let ((r (run-files '("a.sls") (list (cons "a.sls" "(a\n")))))
  (test-assert (string-contains? (run-err r) "a.sls:1:0:"))
  (test-equal "" (run-out r)))

(test-end)

(test-begin "the status of a run is the worst status of its parts")

;; One failure among nine successes.
(let* ((files (list (cons "f0.sls" bad)
                    (cons "f1.sls" ugly) (cons "f2.sls" ugly)
                    (cons "f3.sls" ugly) (cons "f4.sls" ugly)
                    (cons "f5.sls" ugly) (cons "f6.sls" ugly)
                    (cons "f7.sls" ugly) (cons "f8.sls" ugly)
                    (cons "f9.sls" ugly)))
       (r (run-files (map car files) files)))
  (test-equal 1 (run-status r))
  (test-equal 9 (length (replaced (run-fs r)))))

;; A usage error outranks a refusal.
(let ((r (run-files '("nope.sls" "a.sls") (list (cons "a.sls" bad)))))
  (test-equal 2 (run-status r)))

(test-end)

(test-begin "a tainted layout is silent and succeeds")

;; A token wider than the page cannot be broken, so the engine cannot prove its
;; layout minimal. The text is complete and checked; nothing is reported.
(let* ((wide (string-append "(a " (make-string 60 #\x) ")\n"))
       (r (run-files '("--width" "20" "a.sls") (list (cons "a.sls" wide)))))
  (test-equal 0 (run-status r))
  (test-equal "" (run-err r)))

(test-end)

(test-exit)
