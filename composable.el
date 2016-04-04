;;; composable.el --- composable editing -*- lexical-binding: t; -*-

;; Copyright (C) 2016 Simon Friis Vindum

;; Author: Simon Friis Vindum <simon@vindum.io>
;; Keywords: lisp
;; Version: 0.0.1

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; Composable editing for Emacs


;;; Code:

(defvar composable--command)
(defvar composable--skip-first)
(defvar composable--prefix-arg nil)
(defvar composable--start-point)
(defvar composable--fn-pairs (make-hash-table :test 'equal))

(defvar composable-repeat t) ;; TODO: make this a defcustom

(defun composable-create-composable (command)
  "Take a function and return it in a composable wrapper.
The returned function will ask for a motion, mark the region it
specifies and call COMMAND on the region."
  (lambda ()
    (interactive)
    (if mark-active
        (call-interactively command)
      (setq composable--command command)
      (composable-range-mode))))

(defun composable-def (commands)
  "Define composable function from a list COMMANDS.
The list should contain functions operating on regions.
For each function named foo a function name composable-foo is created."
  (dolist (c commands)
    (fset (intern (concat "composable-" (symbol-name c)))
          (composable-create-composable c))))

(defun composable-mark-line (arg)
  "Mark ARG lines."
  (interactive "p")
  (beginning-of-line)
  (push-mark
   (save-excursion
     (when (region-active-p)
       (goto-char (mark)))
     (forward-line arg)
     (point))
   nil t))

(defun composable-mark-join (arg)
  "Mark the whitespace seperating lines.
Between the line above if ARG is negative otherwise below."
  (interactive "p")
  (forward-line arg)
  (cl-flet ((move (dir)
                  (funcall(if (< 0 dir)
                              'skip-chars-forward
                            'skip-chars-backward)
                          "[:space:]\n")))
    (when (< arg 0) (end-of-line))
    (move arg)
    (push-mark nil nil t)
    (move (- arg))))

(composable-def
 '(kill-region kill-ring-save indent-region comment-or-uncomment-region
   smart-comment-region upcase-region))

(defvar composable--activated-with-marking nil)

(defun composable--singleton-map (key def)
  "Create a map with a single KEY with definition DEF."
  (let ((map (make-sparse-keymap)))
    (define-key map key def)
    map))

(defun composable--call-excursion (command start-point)
  "Call COMMAND if set then go to START-POINT."
  (when (commandp command)
    (call-interactively command)
    (goto-char (marker-position composable--start-point))))

(defun composable--repeater (excursion-marker motion command)
  "Preserve point at EXCURSION-MARKER when doing MOTION and COMMAND."
  (lambda ()
    (interactive)
    (goto-char (marker-position excursion-marker))
    ;; Activate mark, some mark functions expands region when mark is active
    (set-mark (mark))
    (call-interactively motion)
    (set-marker excursion-marker (point))
    (composable--call-excursion command composable--start-point)))

(defun composable--contain-marking (prefix)
  "Remove marking before or after point based on PREFIX."
  (let ((fn (if (eq composable--prefix-arg 'composable-begin) 'min 'max))
        (pos (marker-position composable--start-point)))
    (set-mark (funcall fn (mark) pos))
    (goto-char (funcall fn (point) pos))))

(defun composable--post-command-hook-handler ()
  "Called after each command when composable-rangemode is on."
  (cond
   (composable--skip-first
    (setq composable--skip-first nil))
   ((/= (point) (mark))
    (when composable--prefix-arg
      (cond
       ((gethash this-command composable--fn-pairs)
        (set-mark (point))
        (call-interactively (gethash this-command composable--fn-pairs)))
       (mark-active (composable--contain-marking composable--prefix-arg))))
    (let ((motion this-command)
          (excursion-marker (point-marker)))
      (composable--call-excursion composable--command composable--start-point)
      (when composable-repeat
        (set-transient-map
         (composable--singleton-map
          (vector last-command-event)
          (composable--repeater excursion-marker motion composable--command))
         t
         (lambda ()
           (set-marker excursion-marker nil)
           (set-marker composable--start-point nil)))))
    (composable-range-mode -1))))

(defun composable-add-pair (fn1 fn2)
  "Take two commands FN1 and FN2 and add them as pairs."
  (puthash fn2 fn1 composable--fn-pairs)
  (puthash fn1 fn2 composable--fn-pairs))

(composable-add-pair 'forward-word 'backward-word)

(define-minor-mode composable-range-mode
  "Composable mode."
  :lighter "Range "
  :keymap
  '(((kbd "e") . move-end-of-line)
    ((kbd "1") . digit-argument)
    ((kbd "2") . digit-argument)
    ((kbd "3") . digit-argument)
    ((kbd "4") . digit-argument)
    ((kbd "5") . digit-argument)
    ((kbd "6") . digit-argument)
    ((kbd "7") . digit-argument)
    ((kbd "8") . digit-argument)
    ((kbd "9") . digit-argument)
    ((kbd ".") . composable-end-argument)
    ((kbd ",") . composable-begin-argument)
    ((kbd "a") . move-beginning-of-line)
    ((kbd "'") . avy-goto-char-in-line)
    ((kbd "f") . forward-word)
    ((kbd "b") . backward-word)
    ((kbd "n") . next-line)
    ((kbd "p") . previous-line)
    ((kbd "l") . composable-mark-line)
    ((kbd "{") . backward-paragraph)
    ((kbd "}") . forward-paragraph)
    ((kbd "s") . mark-sexp)
    ((kbd "w") . mark-word)
    ((kbd "h") . mark-paragraph)
    ((kbd "m") . mark-sentence)
    ((kbd "u") . er/mark-url)
    ((kbd "r") . er/mark)
    ((kbd "g") . composable-keyboard-quit)
    ((kbd "j") . composable-mark-join)
    ((kbd "C-g") . composable-keyboard-quit))
  (if composable-range-mode
      (progn
        (if (not mark-active) (push-mark nil t))
        (setq composable--start-point (point-marker))
        (setq composable--skip-first t)
        (add-hook 'post-command-hook 'composable--post-command-hook-handler))
    (remove-hook 'post-command-hook 'composable--post-command-hook-handler)
    (setq composable--activated-with-marking nil)
    (setq composable--prefix-arg nil)
    (setq composable--command nil)))

(defun composable--set-mark-command-advice (&rest _)
  "Advice for `set-mark-command'.  _ are ignored."
  (unless composable-range-mode
    (setq composable--activated-with-marking t)
    (composable-range-mode)))

(defun composable-begin-argument ()
  "Set prefix argument to end."
  (interactive)
  (setq composable--prefix-arg 'composable-begin))

(defun composable-end-argument ()
  "Set prefix argument to end."
  (interactive)
  (setq composable--prefix-arg 'composable-end))

(defun composable--deactivate-mark-hook-handler ()
  "Leave range mode when the mark is disabled.
This also allows for leaving range mode by pressing \\[keyboard-quit]."
  (composable-range-mode -1))

(add-hook 'deactivate-mark-hook 'composable--deactivate-mark-hook-handler)

(advice-add 'set-mark-command :after 'composable--set-mark-command-advice)

(define-minor-mode composable-mode
  "Toggle Composable mode."
  :lighter " Composable"
  :global 1
  :keymap
  `((,(kbd "C-w") . composable-kill-region)
    (,(kbd "M-w") . composable-kill-ring-save)
    (,(kbd "M-;") . composable-comment-or-uncomment-region)
    (,(kbd "C-x C-u") . composable-upcase-region)
    (,(kbd "C-M-\\") . composable-indent-region)))

(provide 'composable)

;;; composable.el ends here
