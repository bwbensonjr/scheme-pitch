(import (scheme base) (scheme cxr) (scheme write) (pitch error) (pitch reader))

(define (diagnostic-data raised)
  (list (pitch-error-message raised)
        (if (reader-error? raised) (reader-error-line raised) #f)
        (if (reader-error? raised) (reader-error-column raised) #f)))
