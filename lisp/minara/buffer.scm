;; buffer.scm : buffers for minara
;;
;; Copyright (c) 2004, 2016 Rob Myers, rob@robmyers.org
;;
;; This file is part of minara.
;;
;; minara is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation; either version 3 of the License, or
;; (at your option) any later version.
;;
;; minara is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.
;;
;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;; Buffer indices start at 1


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Modules
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (minara buffer)
  :use-module (ice-9 gap-buffer)
  :use-module (srfi srfi-9)
  :use-module (ice-9 rdelim)
  :use-module (scripts slurp)
  :export (timestamp
           initialise-timestamp!
           update-timestamp!
           timestamp-from-file
           buffer
           buffer-text
           set-buffer-text!
           ;;buffer-variables
           ;;set-buffer-variables!
           make-buffer
           make-buffer-from-file
           make-buffer-from-string
           buffer-file
           buffer-file-reload
           buffer-insert-no-undo
           write-buffer
           buffer-start
           buffer-end
           buffer-to-string
           buffer-range-to-string
           set-buffer-variable!
           buffer-variable
           ensure-buffer-variable
           kill-buffer-variable!
           current-buffer
           evaluate-buffer
           draw-buffer
           buffer-invalidate
           buffer-erase))

;; NOTES:
;; buffer indexes start at 1
;; buffer "end" is 1 after # chars in buffer


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Timestamps
;; We use timestamps to keep track of when something has changed.
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
                      variables)
  buffer?
  ;; The text buffer
  (text buffer-text
        set-buffer-text!)
  ;; The variables alist
  (variables buffer-variables
             set-buffer-variables!))

;; Public constructor

(define (make-buffer)
  (let ((buf (really-make-buffer (make-gap-buffer)
                                 '())))
    (update-timestamp! (buffer-text buf))
    buf))

;; Public constructor to load the buffer from file

(define (make-buffer-from-file file-path)
  (let ((buf (make-buffer)))
    (set-object-property! (buffer-text buf) 'filename file-path)
    (buffer-insert-no-undo buf
                           0
                           (slurp (buffer-file buf)))
    buf))

;; Public constructor to load the buffer from a string

(define (make-buffer-from-string text)
  (let ((buf (make-buffer)))
    (buffer-insert-no-undo buf 0 text)
    buf))

;; The file path for a buffer than has been loaded from file

(define (buffer-file buf)
  (object-property (buffer-text buf) 'filename))

;; Reload the buffer from file.

(define (buffer-file-reload buf)
  (buffer-delete-undoable buf #f #f)
  (buffer-insert-undoable buf
                          0
                          (slurp (buffer-file buf)))
  (buffer-undo-mark buf)
  (buffer-invalidate buf))

;; Save the buffer

(define (write-buffer buf filepath)
  (set-object-property! buffer 'filename filepath)
  (with-output-to-file filepath
    (lambda () (display (buffer-to-string buf)))))

;; Convert the buffer to a string

(define (buffer-to-string buf)
  (gb->string (buffer-text buf)))

(define (buffer-erase buf)
  (gb-erase! (buffer-text buf)))

(define (buffer-end buf)
  (gb-point-max (buffer-text buf)))

(define (buffer-start buf)
  (gb-point-min (buffer-text buf)))

(define (buffer-range-to-string buf from to)
  ;; to is the character *after*, so to may be (# chars in buffer + 1)
  (string-copy (buffer-to-string buf)
               from
               (- to 1)))

;; Insert outside of the undo system. No, you really do not want this. See undo.

(define (buffer-insert-no-undo buffer pos text)
  (let* ((gap-buffer (buffer-text buffer))
         (position (or pos
                       (gb-point-max gap-buffer))))
    (gb-goto-char gap-buffer
                  position)
    (gb-insert-string! gap-buffer
                       text)))

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

;; Get buffer variable, creating it if it doesn't exist

(define (ensure-buffer-variable buffer name)
  (assoc-ref (buffer-variables buffer)
             name))

;; Remove buffer variable

(define (kill-buffer-variable! buffer name)
  (set-buffer-variables! buffer
                         (assoc-remove! (buffer-variables buffer)
                                        name)))

;; Remove all buffer variables

(define (kill-all-buffer-variables buffer)
  (set-buffer-variables! buffer '()))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Buffer Drawing
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; So code located in the current buffer can get buffer variables, for example.

(define %current-buffer #f)

(define (current-buffer)
  %current-buffer)

(define (evaluate-buffer cb module)
  (set! %current-buffer cb)
  (eval-string (buffer-to-string cb) module)
  (set! %current-buffer #f))

;; Flag the buffer to be drawn when the window next redraws

(define (buffer-invalidate cb)
  (update-timestamp! (buffer-text cb)))

(define (draw-buffer cb)
  (evaluate-buffer cb (resolve-module '(minara-internal cairo-rendering))))
