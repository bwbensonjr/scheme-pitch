;;; Raised values shared by the R7RS Pitch libraries.
(define-library (pitch error)
  (export
    make-config-error config-error? config-error-path config-error-irritants
    make-reader-error reader-error? reader-error-filename reader-error-line
    reader-error-column reader-error-irritants
    make-layout-error layout-error?
    pitch-error? pitch-error-message)
  (import (scheme base))
  (begin
    (define-record-type <config-error>
      (make-config-error path message irritants)
      config-error?
      (path config-error-path)
      (message config-error-message)
      (irritants config-error-irritants))

    (define-record-type <reader-error>
      (make-reader-error filename line column message irritants)
      reader-error?
      (filename reader-error-filename)
      (line reader-error-line)
      (column reader-error-column)
      (message reader-error-message)
      (irritants reader-error-irritants))

    (define-record-type <layout-error>
      (make-layout-error message)
      layout-error?
      (message layout-error-message))

    (define (pitch-error? value)
      (or (config-error? value)
          (reader-error? value)
          (layout-error? value)))

    ;; This is the only place CLI-facing code needs to know the difference
    ;; between Pitch records and R7RS error objects.
    (define (pitch-error-message value)
      (cond
        ((config-error? value) (config-error-message value))
        ((reader-error? value) (reader-error-message value))
        ((layout-error? value) (layout-error-message value))
        ((error-object? value) (error-object-message value))
        (else "unknown error")))))
