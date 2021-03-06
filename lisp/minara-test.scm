(read-enable 'positions)

(if (not (defined? '$minara-lisp-dir))
    (define $minara-lisp-dir "."))

(set! %load-path (cons $minara-lisp-dir %load-path))

;; Dummies

(define-module (minara-internal window)
  :export ("window-make" "window-dispose" "window-current-id"
	   "window-set" "window-set-title" "window-draw-text"
	   "window-invalidate" "window-draw-begin" "window-draw-end"))

(define-module (minara-internal events)
  :export (%bind-event-hooks))

(define (%bind-event-hooks) #f)

(define-module (minara-internal config))

(define-module (minara-test)
  :use-module (minara load-libraries))

(define (load-test file)
  (let ((filename (string-append "minara-test/" file "-tests.scm")))
    (format #t "~a~%" filename)
    (if (access? filename R_OK)
	(begin
	  (format #t "Loading test file: ~a~%" filename)
	  (load filename)))))

(define (load-tests)
  (for-each (lambda (file)
	      (load-test file))
	    $library-files))

(load-tests)

(define-module (minara run-tests)
  :use-module (unit-test))
(exit-with-summary (run-all-defined-test-cases))
