;; -*- mode: scheme; coding: utf-8 -*-
;; Copyright © 2026 Brent Benson
;; SPDX-License-Identifier: MIT

;; The command line: the argument grammar, the per-input driver, and the exit
;; status. This is the only caller of (pitch format) that writes anything down.
;;
;; THE HOST IS WHY THIS FILE IS PORTABLE AND WHY ITS BEHAVIOR IS TESTABLE.
;; Everything below (pitch format) is a pure function; the worst a bug in it can
;; do is return a wrong string, and the safety checks exist to catch exactly
;; that. This library writes to files, which is a different kind of mistake and
;; wants a different kind of evidence.
;;
;; So the driver performs no input or output of its own. It is handed a `host`
;; -- a record of the ten operations it needs from the outside world -- and
;; everything it does to the world goes through that record. tests/test-cli.sps
;; supplies one backed by an association list and a write log, which turns the
;; claims that matter here into exact assertions rather than hopeful ones. The
;; important claims are all NEGATIVE: a refused file is *not* written, an
;; already-formatted file is *not* written. Against a real filesystem those mean
;; comparing modification times and hoping about clock resolution. Against the
;; in-memory host they mean the write log is empty, which is a fact.
;;
;; src/pitch/main.sps builds the real host and contains no decisions.
;;
;; REFUSAL LEAVES THE FILE ALONE. (pitch format) returns no text at all under any
;; status but `ok`, so there is nothing to write even by accident; what this file
;; owes is not manufacturing one. An unclean parse, an unsupported line ending
;; and a failed check are reported and the file is left byte for byte as it was.

#!r6rs

(library (pitch cli)
  (export
    run-cli
    make-host host?
    host-read-file host-write-file host-rename-file
    host-list-directory host-directory? host-symbolic-link? host-file-exists?
    host-stdin host-stdout host-stderr
    pitch-version)
  (import
    (rnrs base (6))
    (rnrs control (6))
    (rnrs lists (6))
    (rnrs sorting (6))
    (rnrs exceptions (6))
    (rnrs conditions (6))
    (rnrs records syntactic (6))
    (only (rnrs io ports (6)) put-string get-string-all eof-object?)
    (only (pitch format)
          format-source
          format-result-status format-result-detail
          default-page-width default-dialect)
    (only (pitch diagnostic)
          diagnostic-message diagnostic-line diagnostic-column sort-diagnostics)
    (only (pitch reader) token-start-line token-start-column))

(define pitch-version "0.1.0")

;;; The host
;;
;; The enumeration of what this program needs from the world, which is short
;; because the program does very little to it. This is deliberately not a
;; general filesystem abstraction with implementations to swap: adding a field
;; means justifying a new thing the CLI does outside itself, and the export list
;; is a cheap place to notice that happening.
;;
;;   read-file       path -> string, or raise
;;   write-file      path string -> unspecified, or raise
;;   rename-file     from to -> unspecified, or raise
;;   list-directory  path -> list of entry names, without . and ..
;;   directory?      path -> boolean, following symbolic links
;;   symbolic-link?  path -> boolean
;;   file-exists?    path -> boolean
;;   stdin           textual input port
;;   stdout          textual output port
;;   stderr          textual output port
;;
;; directory? and symbolic-link? are two operations rather than one because the
;; walk must descend into a directory and must not descend into a link naming
;; one; asking the two questions separately keeps that decision here rather than
;; in whichever host happens to answer it.
(define-record-type host
  (fields read-file write-file rename-file
          list-directory directory? symbolic-link? file-exists?
          stdin stdout stderr)
  (sealed #t) (opaque #f)
  (nongenerative host-v0-6a41f30d-9c78-4b52-8e05-2d7b16ca94f1))

;;; Exit status
;;
;; Three values, and they must not be collapsed. A continuous-integration job
;; has to tell "this code is unformatted" from "this invocation is wrong", and a
;; single non-zero status makes that impossible.
;;
;; Ordered so that `max` is the aggregation rule: the worst outcome any input
;; produced is the one the run reports. A usage error outranks a refusal because
;; it says the invocation itself could not be carried out.
(define status-ok 0)
(define status-failure 1)
(define status-usage 2)

(define (worse a b) (max a b))

;;; Writing to the two streams

(define (emit port . parts)
  (for-each (lambda (s) (put-string port s)) parts))

;; Every diagnostic goes here. Standard output carries formatted text and
;; nothing else, so that `pitch --stdout f.sls > g.sls` cannot produce a g.sls
;; with a warning in the middle of it.
(define (report host . parts)
  (apply emit (host-stderr host) parts)
  (emit (host-stderr host) "\n"))

;; path:line:column: message -- what editors and line-oriented tools parse.
(define (report-at host path line column message)
  (report host path ":" (number->string line) ":" (number->string column)
          ": " message))

(define (condition-text con)
  (if (message-condition? con) (condition-message con) "unknown error"))

;;; Usage

(define usage-lines
  '("usage: pitch [options] <file|directory>..."
    "       pitch [options] -            format standard input"
    "       pitch --stdout               format standard input"
    ""
    "options:"
    "  --stdout        write formatted text to standard output, rewriting nothing"
    "  --check         write nothing; fail if any input would change"
    "  --width N       page width (default 88)"
    "  --dialect D     common, r6rs, or r7rs (default common)"
    "  --help          show this message"
    "  --version       show the version"
    ""
    "exit status:"
    "  0  every input succeeded; under --check, nothing would change"
    "  1  an input was refused, or under --check would change"
    "  2  a usage error, or a path that could not be read or written"))

(define (emit-usage port)
  (for-each (lambda (line) (emit port line "\n")) usage-lines))

;;; Options
;;
;; disposition  one of in-place, stdout, check
;; width        a positive exact integer
;; dialect      common, r6rs or r7rs
;; source       either the symbol stdin, or a list of operand paths
(define-record-type options
  (fields disposition width dialect source)
  (sealed #t) (opaque #f)
  (nongenerative options-v0-0d5c8b74-3e19-4a6f-b2c1-57ff9e0a4d38))

;;; Argument parsing
;;
;; Returns two values: an outcome symbol and its payload.
;;
;;   options      an options record
;;   help         write the usage to standard output and succeed
;;   version      likewise for the version string
;;   no-input     the invocation named nothing to format
;;   usage-error  the payload is the message to print
;;
;; EVERY OPTION VALUE IS VALIDATED HERE, BEFORE ANY FILE IS OPENED. For --width
;; that is ordinary hygiene. For --dialect it is a correctness requirement:
;; dialect-style-table *raises* on a symbol naming no dialect, and left to the
;; per-file loop that condition would escape as an unhandled exception after
;; some files had already been rewritten -- a backtrace instead of a message,
;; with the run in a state nobody can reason about. Checking the name here turns
;; a static property of the invocation into a message and an untouched tree.
(define (parse-arguments args)
  (let loop ((args args)
             (disposition #f)
             (width default-page-width)
             (dialect default-dialect)
             (operands '())
             (literal? #f))
    (if (null? args)
        (finish disposition width dialect (reverse operands))
        (let ((arg (car args)) (rest (cdr args)))
          (cond
            ;; Everything after -- is an operand whatever it looks like, which
            ;; is how a file whose name begins with a dash is reachable.
            (literal?
             (loop rest disposition width dialect (cons arg operands) #t))
            ((string=? arg "--")
             (loop rest disposition width dialect operands #t))
            ((string=? arg "--help") (values 'help #f))
            ((string=? arg "--version") (values 'version #f))
            ((string=? arg "--stdout")
             (if (eq? disposition 'check)
                 (values 'usage-error
                         "--stdout and --check name incompatible outcomes")
                 (loop rest 'stdout width dialect operands #f)))
            ((string=? arg "--check")
             (if (eq? disposition 'stdout)
                 (values 'usage-error
                         "--stdout and --check name incompatible outcomes")
                 (loop rest 'check width dialect operands #f)))
            ((string=? arg "--width")
             (if (null? rest)
                 (values 'usage-error "--width requires a value")
                 (let ((w (string->number (car rest))))
                   (if (and w (integer? w) (exact? w) (positive? w))
                       (loop (cdr rest) disposition w dialect operands #f)
                       (values 'usage-error
                               (string-append "--width wants a positive whole"
                                              " number, got " (car rest)))))))
            ((string=? arg "--dialect")
             (if (null? rest)
                 (values 'usage-error "--dialect requires a value")
                 (let ((d (parse-dialect (car rest))))
                   (if d
                       (loop (cdr rest) disposition width d operands #f)
                       (values 'usage-error
                               (string-append "--dialect wants common, r6rs or"
                                              " r7rs, got " (car rest)))))))
            ;; A lone - names standard input and is an operand. Anything else
            ;; beginning with a dash is an option, and we have run out of ones
            ;; we know.
            ((and (> (string-length arg) 1) (char=? (string-ref arg 0) #\-))
             (values 'usage-error (string-append "unknown option " arg)))
            (else
             (loop rest disposition width dialect (cons arg operands) #f)))))))

(define (parse-dialect s)
  (cond ((string=? s "common") 'common)
        ((string=? s "r6rs") 'r6rs)
        ((string=? s "r7rs") 'r7rs)
        (else #f)))

;; Resolve what is to be formatted, once every option is known.
;;
;; Standard input is named or it is not used. The absence of an operand never
;; selects it: see run-cli's no-input case for why that is a failure rather than
;; a stream.
(define (finish disposition width dialect operands)
  (let ((names-stdin? (member "-" operands)))
    (cond
      ;; -- with any other operand would put two dispositions in one run,
      ;; decided per operand and announced by no flag: the named file rewritten
      ;; in place while the stream goes to standard output.
      ((and names-stdin? (not (null? (cdr operands))))
       (values 'usage-error "- cannot be combined with another operand"))
      ((or names-stdin? (and (null? operands) (eq? disposition 'stdout)))
       (values 'options
               (make-options (or disposition 'stdout) width dialect 'stdin)))
      ((null? operands) (values 'no-input #f))
      (else
       (values 'options
               (make-options (or disposition 'in-place) width dialect
                             operands))))))

;;; The entry point

(define (run-cli args host)
  (let-values (((outcome payload) (parse-arguments args)))
    (case outcome
      ;; The explicit request, and it succeeds: standard output, status 0, no
      ;; file read even when operands are also given.
      ((help) (emit-usage (host-stdout host)) status-ok)
      ((version) (emit (host-stdout host) "pitch " pitch-version "\n") status-ok)
      ;; The same text as `help`, on the other stream, with the other status.
      ;; That contrast is the entire reason both spellings exist. An invocation
      ;; carrying no operand is overwhelmingly a script whose file list came out
      ;; empty -- a find that matched nothing, an unset variable, a `git diff
      ;; --name-only` on a clean tree -- and exiting 0 there would report a
      ;; clean run over nothing. The exit status is the only channel a script
      ;; reads, so it is the one that has to carry the fact that no input was
      ;; named. A user who typed `pitch` to see what it does is still told.
      ((no-input) (emit-usage (host-stderr host)) status-usage)
      ((usage-error)
       (report host "pitch: " payload)
       (report host "try `pitch --help'")
       status-usage)
      (else (run-options payload host)))))

(define (run-options opts host)
  (if (eq? (options-source opts) 'stdin)
      (run-stdin opts host)
      (fold-left (lambda (status operand)
                   (worse status (run-operand opts host operand)))
                 status-ok
                 (options-source opts))))

;;; Standard input
;;
;; In-place is meaningless for a stream, so the disposition degrades to stdout
;; rather than the invocation being rejected. --check stays --check.
(define (run-stdin opts host)
  (let* ((raw (get-string-all (host-stdin host)))
         (text (if (eof-object? raw) "" raw))
         (disposition (if (eq? (options-disposition opts) 'check)
                          'check
                          'stdout)))
    (format-one opts host "<stdin>" text disposition)))

;;; Operands
;;
;; A path naming nothing, and one that cannot be read, are usage errors rather
;; than formatting failures: they are facts about the invocation or the
;; environment, not about the formatting of any code, and a --check job that
;; exited 1 for an unreadable file would claim a violation that does not exist.
;;
;; Every operand is processed whatever an earlier one did. An editor formatting
;; a project and a hook formatting a changeset both need the good files done and
;; the bad ones named; stopping at the first failure gives them neither.
(define (run-operand opts host operand)
  (cond
    (((host-directory? host) operand)
     (fold-left (lambda (status path)
                  (worse status (format-file opts host path)))
                status-ok
                (walk host operand)))
    (((host-file-exists? host) operand)
     ;; A file named explicitly is formatted whatever it is called: the user
     ;; naming it is a stronger signal than its suffix.
     (format-file opts host operand))
    (else
     (report host "pitch: " operand ": no such file or directory")
     status-usage)))

;;; Directory discovery
;;
;; THE EXTENSION SET FILTERS DISCOVERY AND SELECTS NOTHING ELSE. In particular
;; it never selects a dialect: docs/DESIGN.md §4 is explicit that .scm and .ss
;; are used by both camps, so a suffix is not evidence about which standard a
;; file is written in. That is what --dialect is for, and what content sniffing
;; will be for.
(define scheme-extensions '(".sls" ".sps" ".scm" ".ss" ".sld"))

(define (string-suffix? suffix s)
  (let ((n (string-length s)) (m (string-length suffix)))
    (and (>= n m) (string=? (substring s (- n m) n) suffix))))

(define (scheme-file? name)
  (exists (lambda (ext) (string-suffix? ext name)) scheme-extensions))

(define (path-join dir name)
  (let ((n (string-length dir)))
    (if (and (> n 0) (char=? (string-ref dir (- n 1)) #\/))
        (string-append dir name)
        (string-append dir "/" name))))

(define (hidden? name)
  (and (> (string-length name) 0) (char=? (string-ref name 0) #\.)))

;; Depth-first, each directory's entries in name order, so that the sequence of
;; files processed -- and therefore the order of any diagnostics -- is
;; reproducible across machines. list-directory returns entries in filesystem
;; order, which is not.
(define (walk host root)
  (reverse (walk-reversed host root)))

(define (walk-reversed host root)
  (let descend ((dir root) (acc '()))
    (let loop ((names (list-sort string<? ((host-list-directory host) dir)))
               (acc acc))
      (if (null? names)
          acc
          (let ((name (car names)))
            (cond
              ;; Keeps the walk out of .git and editor directories without
              ;; naming any of them.
              ((hidden? name) (loop (cdr names) acc))
              (else
               (let ((path (path-join dir name)))
                 (cond
                   ;; Descending into linked directories admits cycles, and
                   ;; detecting one needs path identity the host does not
                   ;; expose. Skipping is the refuse-rather-than-guess rule the
                   ;; project applies everywhere else; a user who wants a linked
                   ;; tree formatted can name it as an operand, which is
                   ;; followed.
                   (((host-directory? host) path)
                    (if ((host-symbolic-link? host) path)
                        (loop (cdr names) acc)
                        (loop (cdr names) (descend path acc))))
                   ((scheme-file? name) (loop (cdr names) (cons path acc)))
                   (else (loop (cdr names) acc)))))))))))

;;; The per-input driver
;;
;; One call site for the pipeline, so the three dispositions cannot drift apart.
(define (format-file opts host path)
  (let-values (((ok? text) (attempt (lambda () ((host-read-file host) path)))))
    (if (not ok?)
        (begin
          (report host "pitch: " path ": cannot read: " (condition-text text))
          status-usage)
        (format-one opts host path text (options-disposition opts)))))

(define (attempt thunk)
  (guard (con (#t (values #f con)))
    (values #t (thunk))))

(define (format-one opts host path text disposition)
  (let-values (((output result)
                (format-source text path (options-width opts)
                               (options-dialect opts))))
    ;; format-result-tainted? is deliberately never consulted. Taint is a
    ;; withdrawn minimality claim, not a defect: the text is complete and
    ;; verified by the output checks like any other, and its usual cause is a
    ;; token wider than the page, which the user cannot act on. A warning nobody
    ;; can act on is one they learn to filter, including the ones that matter.
    (if (eq? (format-result-status result) 'ok)
        (dispose host path text output disposition)
        (begin (report-refusal host path result) status-failure))))

(define (dispose host path text output disposition)
  (case disposition
    ;; No separator, header or filename banner between several inputs: a banner
    ;; would be text the formatter did not produce, in the stream reserved for
    ;; text it did.
    ((stdout) (emit (host-stdout host) output) status-ok)
    ((check)
     (if (string=? output text)
         status-ok
         (begin (report host path ": would reformat") status-failure)))
    (else (write-back host path text output))))

;; The write rule, and every clause of it is a requirement rather than an
;; optimization.
(define (write-back host path text output)
  (if (string=? output text)
      ;; Formatting is idempotent, so an already-formatted tree is the steady
      ;; state and a run over one must be a no-op at the filesystem level: no
      ;; file replaced, no modification time touched, no rebuild storm. A
      ;; formatter that rewrites unconditionally makes its no-op case
      ;; indistinguishable from its working case.
      status-ok
      ;; THIS IS THE ONLY OPERATION IN THE CODEBASE THAT CAN DESTROY A USER'S
      ;; SOURCE. Write the new contents beside the target and rename over it, so
      ;; an interrupted run leaves the file wholly unchanged or wholly replaced
      ;; and never half of each. The temporary lives in the target's own
      ;; directory, which is what keeps the rename within one filesystem and
      ;; therefore atomic.
      (let ((tmp (string-append path ".pitch-tmp")))
        (let-values (((ok? con)
                      (attempt (lambda ()
                                 ((host-write-file host) tmp output)
                                 ((host-rename-file host) tmp path)))))
          (if ok?
              status-ok
              (begin
                (report host "pitch: " path ": cannot write: "
                        (condition-text con))
                status-usage))))))

;;; Refusals

(define (report-refusal host path result)
  (let ((detail (format-result-detail result)))
    (case (format-result-status result)
      ((unclean-parse) (report-diagnostics host path detail))
      ((unsupported-line-ending)
       (report-at host path
                  (token-start-line detail) (token-start-column detail)
                  "unsupported line ending inside a multi-line token"))
      ((check-failed)
       ;; check-output hands back either a diagnostics list, or a pair of the
       ;; failing layer and its detail. A failing layer has no position of its
       ;; own and none is invented for it.
       (if (and (pair? detail) (symbol? (car detail)))
           (report host path ": internal error: " (symbol->string (car detail))
                   " check failed; the file was not written")
           (report-diagnostics host path detail)))
      (else (report host path ": refused")))))

(define (report-diagnostics host path diagnostics)
  (for-each (lambda (d)
              (report-at host path
                         (diagnostic-line d) (diagnostic-column d)
                         (diagnostic-message d)))
            (sort-diagnostics diagnostics))))
