;; minibuffer.scm : minara scheme development file
;;
;; Copyright (c) 2004 Rob Myers, rob@robmyers.org
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

(define-module (minara minibuffer)
  :use-module (srfi srfi-9)
  :use-module (ice-9 gap-buffer)
  :use-module (minara picking)
  :use-module (minara buffer)
  :use-module (minara tool)
  :use-module (minara keymap)
  :export (minibuffer
           minibuffer?
           minibuffer-window
           minibuffer-return-callback
           minibuffer-cancel-callback
           minibuffer-make
           minibuffer-string
           window-minibuffer
           window-add-minibuffer
           window-remove-minibuffer))

;; Add key event and idle handlers to minibuffer type

(define-record-type minibuffer
  (%make-minibuffer gap-buffer
                    window
                    return-callback
                    cancel-callback)
  minibuffer?
  (gap-buffer
   minibuffer-buffer) ;; Deliberately not "text". Not public like buffer-text.
  (window
   minibuffer-window)
  (return-callback
   minibuffer-return-callback)
  (cancel-callback
   minibuffer-cancel-callback))

(define (minibuffer-make window
                         initial-text
                         ok
                         cancel)
  (let ((mini (%make-minibuffer (make-gap-buffer)
                                window
                                ok
                                cancel)))
    (gb-insert-string! (minibuffer-buffer mini)
                       initial-text)
    (minibuffer-go-end mini)
    mini))

(define (minibuffer-length mini)
  (gb-point-max (minibuffer-buffer mini)))

(define (minibuffer-position mini)
  (gb-point (minibuffer-buffer mini)))

(define (minibuffer-string mini)
  (buffer-to-string (minibuffer-buffer mini)))

(define (minibuffer-redraw mini)
  (let ((window (minibuffer-window mini)))
    (set-window-status! window
                        (minibuffer-string mini))
    (window-redraw window)))

(define (minibuffer-insert mini char)
  (gb-insert-char! (minibuffer-buffer mini)
                   char)
  (minibuffer-redraw mini))

(define (minibuffer-delete mini)
  (gb-delete-char! (minibuffer-buffer mini)
                   -1) ;; -1 for char before
  (minibuffer-redraw mini))

(define (minibuffer-erase mini)
  (gb-erase! (minibuffer-buffer mini))
  (minibuffer-redraw mini))

(define (minibuffer-go-start mini)
  (let ((buff (minibuffer-buffer mini)))
    (gb-goto-char buff
                  (gb-point-min buff)))
  (minibuffer-redraw mini))

(define (minibuffer-go-end mini)
  (let ((buff (minibuffer-buffer mini)))
    (gb-goto-char buff
                  (gb-point-max buff)))
  (minibuffer-redraw mini))

(define (minibuffer-go-forward mini)
  (let ((buff (minibuffer-buffer mini)))
    (gb-forward-char buff
                     1))
  (minibuffer-redraw mini))

(define (minibuffer-go-back mini)
  (gb-backward-char buff
                    1)
  (minibuffer-redraw mini))

;; Key handler

(define (minibuffer-key-handler mini k)
  (let ((key (string-ref k 0)))
    (case key
      ((GLUT_KEY_LEFT)
       (minibuffer-go-back mini))
      ((GLUT_KEY_RIGHT)
       (minibuffer-go-forward mini))
      ((GLUTKEY_UP)
       (minibuffer-go-end mini))
      ((GLUTKEY_DOWN)
       (minibuffer-go-start mini))
      ((#\del)
       (minibuffer-delete mini))
      ((#\return) ;; #\nl
       (window-remove-minibuffer (minibuffer-window mini))
       ((minibuffer-return-callback mini)))
      ((#\esc)
       (window-remove-minibuffer (minibuffer-window mini))
       ((minibuffer-cancel-callback mini)))
      (else
       (minibuffer-insert mini
                          key)))))

(define (window-minibuffer-key-handler window key modifiers)
  (minibuffer-key-handler (window-minibuffer window)
                          key))

;; Adding & removing to window

(define (window-minibuffer window)
  (buffer-variable (window-buffer-main window)
                   "_minibuffer"))

(define (window-add-minibuffer window initial-text ok cancel)
  (set-buffer-variable! (window-buffer-main window)
                        "_minibuffer"
                        (minibuffer-make window
                                         initial-text
                                         ok
                                         cancel))
  (install-minibuffer-key-handler)
  (minibuffer-redraw (window-minibuffer window)))

(define (window-remove-minibuffer window)
  (kill-buffer-variable! (window-buffer-main window)
                         "_minibuffer")
  (uninstall-minibuffer-key-handler)
  (window-redraw window))

;; Will need fixing for multi-window operation
;; How should window & global event handlers interact?
;; Tools must ensure their buffers on mouse-down rather than create on install?

(define %previous-key-handlers #f)

(define (install-minibuffer-key-handler)
  (set! %previous-key-handlers %key-release-funs)
  (set! %key-release-funs (list window-minibuffer-key-handler)))

(define (uninstall-minibuffer-key-handler)
  (set! %key-release-funs previous-key-handlers)
  (set! %previous-key-handlers #f))
