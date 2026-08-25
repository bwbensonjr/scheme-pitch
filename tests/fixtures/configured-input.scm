(project-let ((x
                1)
              (y
                2))
  (f x)
  (g y))
(define-record-type point
  (fields x y)
  (sealed #t)
  (opaque #f))
