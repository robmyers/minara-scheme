;; buffer.scm : buffers for minara
;;
;; Copyright (c) 2004 Rob Myers, rob@robmyers.org
;;
;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 2 of the License, or
;; (at your option) any later version.
;;
;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program; if not, write to the Free Software
;; Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Modules
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Buffers
(use-modules (ttn gap-buffer))
(use-modules (ttn find-file))

;; Records
(use-modules (srfi srfi-9))

;; Line reading
(use-modules (ice-9 rdelim))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Timestamps
;; We use timestamps to keep track of when something has changed,
;; particularly buffers of scheme code and the cached drawing of them.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Timestamps

(define (timestamp buf)
  (object-property buf 'timestamp))

(define (initialise-timestamp! buf)
  (set-object-property! buf 'timestamp 0))

(define (update-timestamp! buf)
  (set-object-property! buf 'timestamp (current-time)))

(define (timestamp-from-file buf file-path)
  (set-object-property! buf 
		       'timestamp
		       (stat:mtime (stat file-path))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Buffer
;; A buffer of text, particularly the Scheme code describing the drawing
;; instructions from a document or an overlay.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; The buffer record

(define-record-type buffer
  (really-make-buffer text 
		      cache
		      variables)
  cached-buffer?
  ;; The text buffer
  (text buffer-text)
  ;; The cached rendering generated by executing the text buffer
  (cache buffer-cache)
  ;; The variables alist
  (buffer-variables buffer-variables
		    set-buffer-variables!))

;; Public constructor

(define (make-buffer)
  (let ((buf (really-make-buffer (make-gap-buffer)
				 (cache-make)
				 (list))))
    (update-timestamp! (buffer-text buf))
    (initialise-timestamp! (buffer-cache buf))
    buf))

;; Public constrictor to load the buffer from file

(define (make-buffer-from-file file-path)
  (let ((buf (really-make-buffer (find-file file-path)
				 (cache-make)			     
				 '())))
    (update-timestamp! (buffer-text buf))
    (initialise-timestamp! (buffer-cache buf))
    buf))

;; The file path for a buffer than has been loaded from file

(define (buffer-file buf)
  (object-property (buffer-text buf) 'filename))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Buffer Variables
;; A buffer can have an arbitrary number of named variables set on it.
;; These will last until the buffer is disposed of, and are unaffected by event
;; handling, particularly redraws, unless the code inside the buffer affects 
;; the variables when evaluated, which would be weird.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Set buffer variable

(define (set-buffer-variable! buffer name value)
  (let ((variables (buffer-variables buffer)))
    (set-buffer-variables! buffer 
			   (assoc-set! variables 
				       name 
				       value))))

;; Get buffer variable

(define (buffer-variable buffer name)
  (assoc-ref (buffer-variables buffer)
	     name))

;; Remove buffer variable

(define (kill-buffer-variable! buffer name)
  (set-buffer-variables! buffer 
			 (assoc-remove! (buffer-variables buffer) 
					name)))

;; Remove all buffer variables

(define (kill-all-buffer-variables buffer)
  (set-buffer-variables! '()))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Buffer Drawing and Caching
;; Note that we draw lazily, only evaluating a buffer if it has been updated
;; since it was last cached.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Redraw the buffer (just run the cache if no timestamp variation)

(define (draw-buffer cb)
  ;; Is the cache more recent than the buffer text?
  (if (< (timestamp (buffer-text cb))
	 (timestamp (buffer-cache cb)))
      ;; Just redraw the cache, the text hasn't changed
      (cache-draw (buffer-cache cb))
      ;; Otherwise, generate the cache and update the cache timestamp
      (let ((c (buffer-cache cb)))
	(cache-record-begin c)
	(eval-string (gb->string (buffer-text cb)))
	  (cache-record-end c)
	  (update-timestamp! (buffer-cache cb)))))

;; Flag the buffer to be drawn when the window next redraws

(define (buffer-invalidate cb)
  (update-timestamp! (buffer-text cb)))
