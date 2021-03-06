;; keymap.scm : keymaps for minara
;;
;; Copyright (c) 2004, 2010, 2016 Rob Myers, rob@robmyers.org
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Keymaps
;; Inspired by, but different from, Emacs keymaps.
;; In particular keymaps fit within more general event handlers, rather than
;; the other way round.
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-module (minara keymap)
  :export (keymap-make
           keymap-current-root
           keymap?
           keymap-current
           reset-current-keymap
           keymap-current-root-set
           keymap-current-root-reset
           keymap-current-set
           keymap-add-fun-global
           keymap-add-fun
           keymap-add-fun-list
           dispatch-keymap
           dispatch-key
           key-dispatch-hook-method))

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Making and getting keymaps
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Make an empty keymap alist
(define (keymap-make)
  (make-hash-table 31))

;; The one and only global keymap
(define %global-keymap (keymap-make))

;; The current root keymap
(define keymap-current-root #f)

;; Check that the object is a keymap
(define (keymap? keymap)
  (hash-table? keymap))

;; The current keymap
(define keymap-current keymap-current-root)

;; Reset the history
(define (reset-current-keymap)
  (set! keymap-current keymap-current-root))

;; Set the root keymap
(define (keymap-current-root-set keymap)
  (set! keymap-current-root keymap)
  (reset-current-keymap))

;; Reset the root keymap
(define (keymap-current-root-reset)
  (set! keymap-current-root #f))

;; Set the current keymap
(define (keymap-current-set keymap)
  (set! keymap-current keymap))

;; Put the key unto the global keymap
(define (keymap-add-fun-global fun . keys)
  (keymap-add-fun-list %global-keymap fun keys))

;; Add a possibly nested key fun to the keymap
;; A key is a basic key (aA1) prefixed with CA for control and/or alt

(define (keymap-add-fun keymap fun . keys)
  (keymap-add-fun-list keymap fun keys))

(define (keymap-add-fun-list keymap fun keys)
  (let* ((key (car keys))
         (rest-of-keys (cdr keys))
         (keymap-entry-for-key (hash-ref keymap
                                         key)))
    ;;(format #t "keys: ~a~%key: ~a~%keymap-for-key: ~a~%rest: ~a~%~%"
    ;;        keys key keymap-entry-for-key rest-of-keys)
    (cond
     ;; Last key? Insert in current keymap
     ((equal? rest-of-keys
              '())
      ;; Warn if rebinding key
      ;;(if (hash-ref keymap
      ;;              key)
      ;;    (format #t "Redefined key ~a in keymap ~a~%" key keymap))
      (hash-set! keymap
                 key
                 fun))
     ;; No keymap for key?
     ((equal? keymap-entry-for-key
              #f)
      ;; Create it
      (hash-set! keymap
                 key
                 (make-hash-table 31))
      ;; And recurse
      (keymap-add-fun-list (hash-ref keymap
                                     key)
                           fun
                           rest-of-keys))
     ;; Keymap exists but key is not last key?
     (else
      ;; If it's a key, replace witha  keymap
      (if (procedure? keymap-entry-for-key)
          (hash-set! keymap
                     key
                     (make-hash-table 31)))
      ;; Just recurse, re-getting keymap in case we replaced key with keymap
      (keymap-add-fun-list (hash-ref keymap
                                     key)
                           fun
                           rest-of-keys)))))


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Dispatching keypresses through keymaps
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Try to dispatch the key press in the keymap
(define (dispatch-keymap keymap key)
  (let ((next-candidate (hash-ref keymap
                                  key)))
    (cond
     ;; Keymap? Install as current keymap
     ((keymap? next-candidate)
      (keymap-current-set next-candidate)
      #t)
     ;; No match? Reset
     ((not next-candidate)
      (reset-current-keymap)
      #f)
     ;; Fun? Call
     (else ;;(fun? next-candidate)
      (next-candidate)
      (reset-current-keymap)
      #t))))

;; Try to dispatch the current keymap
(define (dispatch-key key)
  (if (not (and keymap-current
                (dispatch-keymap keymap-current
                                 key)))
      (if (not (dispatch-keymap %global-keymap
                                key))
          (format #t
                  "No match for key ~a in current or global keymap.~%"
                  key))))

;; Our method to interface to the event system

(define (key-dispatch-hook-method win key-char modifiers)
  (let ((key (string key-char))
        (shift (memq 'shift modifiers))
        (control (memq 'control modifiers))
        (alt (memq 'alt modifiers)))
    ;; Shift is just the upper-case character. Ensure it *is* upper-case.
    (if shift
        (set! key (string-upcase key)))
    (if control
        (set! key (string-append "C" key)))
    (if alt
        (set! key (string-append "A" key)))
    (dispatch-key key)))

;; Install the cancel key into the global keymap
(keymap-add-fun %global-keymap reset-current-keymap "Cg")

;; TEST

                                        ; (define (dummy)
                                        ;   (write "hello"))

                                        ; (define (dummy2)
                                        ;   (write "hello 2"))

                                        ; (define km (keymap-make))

                                        ; (keymap-add-fun km dummy "a")
                                        ; (keymap-add-fun km dummy2 "b" "c")
                                        ; (keymap-current-root-set km)
