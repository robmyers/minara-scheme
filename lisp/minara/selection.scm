;; selection.scm : selected object management for minara
;;
;; Copyright (c) 2006, 2009, 2010, 2016 Rob Myers, rob@robmyers.org
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


;; This is the selection list on the buffer
;; Selection mathematics is in picking.scm

;; !!! Make sure these work with undo!!!
;; Well, make adding/removing to the list undo actions


;; Can't combine ranges if transforms clash
;; Copy all transforms for each selection?
;; So get all before selection but discard on push/pop? (optimise later)
;; eg. collect-transforms-for in picking <----- !!!!!
;;
;; Or ignore smaller selections && replace with larger selections
;; So save transform in pick information for each hit:
;; (struct pick-hit index from to transform)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Modules
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (minara selection)
  :use-module (srfi srfi-11)
  :use-module (srfi srfi-13)
  :use-module (ice-9 gap-buffer)
  :use-module (minara events)
  :use-module (minara transformations)
  :use-module (minara picking)
  :use-module (minara picking-hit)
  :use-module (minara buffer)
  :use-module (minara tool)
  :use-module (minara keymap)
  :use-module (minara undo)
  :use-module (minara window)
  :use-module (minara sexp)
  :use-module (minara view)
  :export (selections-var
           delete-selections))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Selection list handling
;; A list of dotted ranges eg '() , '((12. 47)) or '((12 .47) (123 456))
;; The selection tool replaces or appends depending on a modifier key (shift?).
;; Undoable
;; Consumed by a copy/paste delete, restored if they undo
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; TODO: removing a range that matches an existing value,
;;       for selective deselecting.

(define (selections-var buffer)
  (buffer-variable buffer "_selections"))

(define (clear-selections-var buffer)
  (buffer-variable-set-undoable buffer
                                "_selections"
                                '()))

(define (sort-selections selections)
  (sort selections
        (lambda (a b)
          (< (picking-hit-from a)
             (picking-hit-from b)))))

(define (append-selection selections selection)
  (cons selection selections))

;; Combine any overlapping selections into a single range
;; Assumes they're in order
;; So get first one, get next, if overlap discard first & combine,
;; otherwise

;; REDO: Overlaps need reworking in light of the way transforms work

(define (selections-overlap? a b)
  (and (> (cdr a)
          (car b))
       (< (car a)
          (cdr b))))

(define (combine-selections a b)
  (cons (min (car a) (car b))
        (max (car a) (cdr b))))

(define (combine-selections-list-aux range selections sorted)
  (if (selections)
      (let ((next-range (car selections))
            (rest (cdr selections)))
        (if (selections-overlap? range next-range)
            (combine-selections-list-aux (car rest)
                                         (cdr rest)
                                         (cons (combine-selections range
                                                                   next-range)
                                               sorted)))
        (combine-selections-list-aux next-range
                                     rest
                                     (cons range sorted))))
  (cons range sorted))

(define (combine-selections-list selections)
  (combine-selections-list-aux (car selections) (cdr selections) '()))

(define (append-selections-var buffer range)
  (buffer-variable-set-undoable buffer
                                "_selections"
                                (sort-selections
                                 (combine-selections-list
                                  (append-selection
                                   (selections-var buffer)
                                   range)))))

(define (selections-var buffer)
  (buffer-variable buffer
                   "_selections"))

(define (set-selections-var buffer range)
  (buffer-variable-set-undoable buffer
                                "_selections"
                                (list range)))

;; Assumes selections are sorted highest to lowest and do not overlap

(define (delete-selections buffer)
  (for-each
   (lambda (pick)
     (buffer-delete-undoable buffer
                             (picking-hit-from pick)
                             (picking-hit-to pick)))
   (selections-var buffer))
  (clear-selections-var buffer))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Copy buffer (clipboard) handling
;; This is a buffer, but it is not on the buffer stack,
;; it's in a buffer variable on the main buffer.
;; QUERY - How do we copy from one window to another?
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; TODO: Write a general (ensure-buffer-variable buff name value) MACRO

(define (buffer-copy-buffer buffer)
  (buffer-variable buffer "_copy"))

(define (ensure-copy-buffer-var buffer)
  (or (buffer-copy-buffer buffer)
      (begin (set-buffer-variable! buffer
                                   "_copy"
                                   (make-buffer))
             (buffer-copy-buffer buffer))))

(define (clear-copy-buffer-var buffer)
  (set-buffer-variable! buffer "_copy" #f))

(define (copy-selections-to-buffer main-buffer to-buffer)
  (let ((selections (selections-var main-buffer)))
    ;; If selections is #f, for-each will fail.
    (if selections
        (for-each
         (lambda (selection)
           (let ((text
                  (format #f "(push-matrix)~%~a~%~a~%(pop-matrix)~%"
                          (matrix-to-concatenate-string
                           (picking-hit-transform selection))
                          (buffer-range-to-string
                           main-buffer
                           (picking-hit-from selection)
                           (picking-hit-to selection)))))
             (buffer-insert-no-undo to-buffer
                                    #f
                                    text)))
         selections))))

(define (copy-selections-to-copy-buffer-var buffer)
  (let ((copy-buf (ensure-copy-buffer-var buffer)))
    (copy-selections-to-buffer buffer copy-buf)))

(define (cut-selections-to-copy-buffer-var buffer)
  (copy-selections-to-copy-buffer-var buffer)
  (clear-selections-var buffer))

(define (paste-copy-buffer-var buffer)
  (buffer-insert-undoable buffer
                          #f
                          (buffer-to-string (ensure-copy-buffer-var buffer))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Copy
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (do-copy-key)
  (copy-selections-to-copy-buffer-var (window-buffer-main (window-current))))

(keymap-add-fun-global do-copy-key "Cc")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Delete
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (do-delete-key)
  (delete-selections (window-buffer-main (window-current)))
  (window-redraw (window-current)))

(keymap-add-fun-global do-delete-key "Cd")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Cut
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (do-cut-key)
  (cut-selections-to-copy-buffer-var (window-buffer-main (window-current))))

(keymap-add-fun-global do-cut-key "Cx")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Paste
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (do-paste-key)
  (clear-selections-var (window-buffer-main (window-current))))

(keymap-add-fun-global do-paste-key "Cv")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Clear Selection
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (do-clear-selection-key)
  (clear-copy-buffer-var (window-buffer-main (window-current))))

;; Map this to n in for "none" in case we need s c for copy
(keymap-add-fun-global do-clear-selection-key "s" " ")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Select
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (select-mouse-up win button x y)
  (let ((selection (pick-path-window win
                                     (window-view-x win x)
                                     (window-view-y win y))))
    (if selection
        (begin
          (if (= button 1)
              (set-selections-var (window-buffer-main win)
                                  selection)
              (append-selections-var (window-buffer-main win)
                                     selection))
          (highlight-selection win))
        (clear-highlight-selection win))))

;; Install

(define (select-tool-install)
  (add-mouse-up-hook select-mouse-up))

;; Uninstall

(define (select-tool-uninstall)
  (remove-mouse-up-hook select-mouse-up))

;; Register

(install-tool select-tool-install
              select-tool-uninstall
              "Select"
              "s" "s")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Selection highlighting
;; Copy the selections to a buffer, with translation code prepended.
;; The translation code gets the translation variables from the buffer
;;  when evaluating.
;; We also override the colour setting and temporarily rebind set-rgba.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (highlight-selection win)
  (let ((highlight-buffer (ensure-window-buffer win "_highlight")))
    ;; The current position of the selection as it is dragged around
    (set-buffer-variable! highlight-buffer "x" 0.0)
    (set-buffer-variable! highlight-buffer "y" 0.0)
    (buffer-undo-mark highlight-buffer)
    (buffer-insert-no-undo
     highlight-buffer
     #f
     "(push-matrix)(translate (buffer-variable (current-buffer) \"x\") (buffer-variable (current-buffer) \"y\"))\n(set-rgba 1.0 0.0 0.0 1.0)\n(define old-set-rgba set-rgba)\n(set! set-rgba (lambda (a b c d) #f))\n")
    (copy-selections-to-buffer (window-buffer-main win)
                               highlight-buffer)
    (buffer-insert-no-undo
     highlight-buffer
     #f
     "\n(set! set-rgba old-set-rgba)(pop-matrix)\n") ;; Restore col!
    (buffer-invalidate highlight-buffer)
    (window-redraw win)))

(define (clear-highlight-selection win)
  (remove-window-buffer win "_highlight"))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Ensuring that a selection is wrapped in a push/translate/pop block
;; This will need improving
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (roll-selections-down selections after by)
  (for-each (lambda (selection)
              ;; If the range is after the range we started inserting at,
              (if (>= (car selection) after)
                  ;; move the range along by the amount we inserted.
                  (begin
                    (set-car! (car selection) by)
                    (set-cdr! (cdr selection) by))))
            selections))

(define (update-selection-ranges selections after by)
  (if selections
      (let ((selection (car selections)))
        (if (> after
               (picking-hit-index selection))
            (begin
              (set-picking-hit-from! selection
                                     (+ (picking-hit-from selection)
                                        by))
              (set-picking-hit-to! selection
                                   (+ (picking-hit-to selection)
                                      by)))))
      (roll-selections-down (cdr selections) after by)))

(define (wrap-selection-translate buffer sel x y)
  (let ((prefix (format #f "(push-matrix)~%(translate ~a ~a)~%" x y))
        (suffix "(pop-matrix)\n"))
    ;; Wrap the selection in a new transform
    (buffer-insert-undoable buffer
                            (picking-hit-to sel)
                            suffix)
    (buffer-insert-undoable buffer
                            (picking-hit-from sel)
                            prefix)
    ;; And roll down the rest
    (update-selection-ranges (selections-var buffer)
                             (+ (picking-hit-index sel)
                                1)
                             (+ (string-length prefix)
                                (string-length suffix)))))

(define (update-selection-translate buffer sel x y prev-from prev-to)
  (let-values (((old-x old-y)
                (get-translate-values (buffer-range-to-string buffer
                                                              (+ prev-from 1)
                                                              (+ prev-to 1)))))
    (let* ((new-x (+ old-x x))
           (new-y (+ old-y y))
           (new-translate (format #f "(translate ~a ~a)"
                                  new-x new-y)))
      ;; Update the existing transform very inefficiently
      (buffer-delete-undoable buffer
                              (+ prev-from 1)
                              (- prev-to prev-from))
      (buffer-insert-undoable buffer
                              (+ prev-from 1)
                              new-translate)
      ;; Roll down the selections that follow
      (update-selection-ranges
       (selections-var buffer)
       (picking-hit-index sel)
       (- (string-length new-translate)
          (- prev-from
             prev-to))))))

(define (update-selection-parameters buffer sel)
  (let ((buffer-str (buffer-to-string buffer)))
    ;; What if it's first or last?
    (let-values (((prev-from prev-to)
                  (sexp-before buffer-str (picking-hit-from sel)))
                 ((next-from next-to)
                  (sexp-after buffer-str (picking-hit-to sel))))
      (let ((prev-symbol (if prev-from
                             (sexp-symbol-string buffer-str prev-from)
                             ""))
            (next-symbol (if next-from
                             (sexp-symbol-string buffer-str next-from)
                             "")))
        (values (if (and (string= prev-symbol "translate")
                         (or (string= next-symbol "pop-matrix")
                             (= next-symbol #f)))
                    #t
                    #f)
                prev-from
                prev-to)))))

(define (update-selection-transform buffer sel x y)
  (let-values (((wrapped? prev-from prev-to)
                (update-selection-parameters buffer sel)))
    ;; What if it's a rotate but preceded by a translate? Later.
    (if wrapped?
        (update-selection-translate buffer
                                    sel x y prev-from prev-to)
        ;; else
        (wrap-selection-translate buffer sel x y))))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Deselect
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define (deselect-all)
  (let* ((win (window-current))
         (buffer (window-buffer-main win)))
    (clear-selections-var buffer)
    (clear-copy-buffer-var buffer)
    (clear-highlight-selection win)
    (window-redraw win)))

(keymap-add-fun-global deselect-all "s" "n")

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Move tool
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define move-tool-mouse-down #f)
(define move-tool-mouse-down-x #f)
(define move-tool-mouse-down-y #f)
(define move-tool-initial-mouse-down-x #f)
(define move-tool-initial-mouse-down-y #f)

(define (move-mouse-down win button x y)
  (set! move-tool-mouse-down-x (window-view-x win x))
  (set! move-tool-mouse-down-y (window-view-y win y))
  (if (eq? move-tool-initial-mouse-down-x #f)
      (begin
        (set! move-tool-initial-mouse-down-x move-tool-mouse-down-x)
        (set! move-tool-initial-mouse-down-y move-tool-mouse-down-y)))
  (let ((highlight-buffer (ensure-window-buffer win "_highlight")))
    (set-buffer-variable! highlight-buffer
                          "x"
                          move-tool-mouse-down-x)
    (set-buffer-variable! highlight-buffer
                          "y"
                          move-tool-mouse-down-y))
  (set! move-tool-mouse-down #t))

(define (move-mouse-move win x y)
  (if move-tool-mouse-down
      (let ((highlight-buffer (window-buffer win "_highlight")))
        (set-buffer-variable! highlight-buffer
                              "x"
                              (- (window-view-x win x)
                                 move-tool-initial-mouse-down-x))
        (set-buffer-variable! highlight-buffer
                              "y"
                              (- (window-view-y win y)
                                 move-tool-initial-mouse-down-y))
        (buffer-invalidate highlight-buffer)
        (window-redraw win))))

(define (translate-selections win x y)
  (let* ((highlight-buffer (window-buffer win "_highlight"))
         (main (window-buffer-main win))
         (selections (selections-var main))
         (new-x (- (window-view-x win x)
                   move-tool-mouse-down-x))
         (new-y (- (window-view-y win y)
                   move-tool-mouse-down-y)))
    (for-each
     (lambda (sel)
       (update-selection-transform main sel new-x new-y))
     (or selections
         '()))))

(define (move-mouse-up win button x y)
  (set! move-tool-mouse-down '#f)
  (translate-selections win x y)
  (buffer-invalidate (window-buffer-main win))
  (window-redraw win)
  )

;; Install

(define (move-tool-install)
  (set! move-tool-initial-mouse-down-x #f)
  (set! move-tool-initial-mouse-down-y #f)
  (add-mouse-move-hook move-mouse-move)
  (add-mouse-down-hook move-mouse-down)
  (add-mouse-up-hook move-mouse-up))

;; Uninstall

(define (move-tool-uninstall)
  (remove-mouse-move-hook move-mouse-move)
  (remove-mouse-down-hook move-mouse-down)
  (remove-mouse-up-hook move-mouse-up))

;; Register

(install-tool move-tool-install
              move-tool-uninstall
              "Move"
              "s" "m")
