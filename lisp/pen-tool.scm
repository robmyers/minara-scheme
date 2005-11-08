;; pen-tool.scm : the pen tool
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
;; This is a simple scribble tool for testing during initial development.
;; It should be renamed "scribble" and replaced with a real pen tool.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Keep track of the mouse button state
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define pen-tool-mouse-down #f)
  
;; When the button is pressed, make and initialise the pen drawing buffers

(define (pen-mouse-down win button x y) 
  (let* ((window (window-for-id win))
	 (pen-buffer (buffer-text (make-window-buffer window
				       "pen")))
	(close-buffer (buffer-text (make-window-buffer window
						       "pen-close"))))
    (gb-goto-char pen-buffer (gb-point-max pen-buffer))
    (gb-insert-string! pen-buffer 
		       (format #f 
			       "(set-colour 0.625 0.5 0.987 0.0)~%(path-begin)~%(move-to ~a ~a)~%" 
			       (window-view-x window x)
			       (window-view-y window y)))
    (gb-insert-string! close-buffer "(path-end)\n")
    (window-undo-stack-push window
			    pen-buffer)
    (set! pen-tool-mouse-down #t)))

;; When the mouse is dragged, add the new co-ordinate to the drawing buffer
;; And redraw the pen drawing buffers

(define (pen-mouse-move win x y) 
  (if pen-tool-mouse-down
      (let* ((window (window-for-id win))
	     (pen-buffer (window-buffer window
					"pen"))
	     ;;(pen-text (buffer-text pen-buffer))
	     (pen-close-buffer (window-buffer (window-for-id win) 
					      "pen-close")))
	(buffer-insert-undoable pen-buffer 
				#f
				(format #f 
					"(line-to ~a ~a)~%" 
					(window-view-x window x)
					(window-view-y window y)))
	(buffer-undo-mark pen-buffer)
	;;	(gb-goto-char pen-text (gb-point-max pen-text))
	;;	(gb-insert-string! pen-text move)
	(buffer-invalidate pen-buffer)   
	(buffer-invalidate pen-close-buffer)
	(window-redraw win))))

;; When the mouse is released, add the pen drawing buffers to the main buffer
;; Redraw the main buffer, and release the pen drawing buffers

(define (pen-mouse-up win button x y) 
  (set! pen-tool-mouse-down #f)
  (let* ((window (window-for-id win))
	 (buff (buffer-text (window-buffer
			     window
			    "pen")))
	(close-buffer (buffer-text (window-buffer 
				    window
				    "pen-close")))
	(main-buff (window-buffer-main window)))
    ;; Add the overlay to the main buffer
    ;;(gb-goto-char main-buff (gb-point-max main-buff))
    ;;(gb-insert-string! main-buff (gb->string buff))
    ;;(gb-goto-char main-buff (gb-point-max main-buff))
    ;;(gb-insert-string! main-buff (gb->string close-buffer))
    (buffer-insert-undoable main-buff
			    #f
			    (gb->string buff))
    (buffer-insert-undoable main-buff
			    #f
			    (gb->string close-buffer))
    (buffer-undo-mark main-buff)
    (window-undo-stack-pop window)
    ;; Clean up and redraw
    (remove-window-buffer window 
			  "pen")
    (remove-window-buffer window 
			  "pen-close")
    (buffer-invalidate (window-buffer-main window))
    (window-redraw win)))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Tool lifecycle
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Install

(define (pen-tool-install)
  (add-mouse-move-hook pen-mouse-move)
  (add-mouse-down-hook pen-mouse-down)
  (add-mouse-up-hook pen-mouse-up))

;; Uninstall

(define (pen-tool-uninstall)
  (remove-mouse-move-hook pen-mouse-move)
  (remove-mouse-down-hook pen-mouse-down)
  (remove-mouse-up-hook pen-mouse-up))

;; Register

(install-tool pen-tool-install 
	      pen-tool-uninstall
	      "Simple Pen"
	      "t" "p")