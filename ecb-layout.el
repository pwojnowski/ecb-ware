;;; ecb-layout.el --- layout for ECB

;; Copyright (C) 2000 Jesper Nordenberg

;; Author: Jesper Nordenberg <mayhem@home.se>
;; Maintainer: Jesper Nordenberg <mayhem@home.se>
;; Keywords: java, class, browser

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation; either version 2, or (at your option) any later version.

;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.

;; You should have received a copy of the GNU General Public License along with
;; GNU Emacs; see the file COPYING.  If not, write to the Free Software
;; Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA 02111-1307, USA.

;;; Commentary:
;;
;; Contains functions for settings the ECB layout.
;;
;; This file is part of the ECB package which can be found at:
;; http://home.swipnet.se/mayhem/ecb.html


;; This file has been re-implemented by Klaus Berndl <klaus.berndl@sdm.de>.
;; What has been done:
;; Completely rewritten the layout mechanism for better customizing, adding
;; new layouts, better redrawing and more straight forward code.
;; 1. Now all user-layouting is done by customizing the new option
;;    `ecb-layout-nr'. The function `ecb-redraw-layout' (formally
;;    known as 'ecb-set-layout) can still be called interactively but
;;    without arguments because it does only a redraw of the layout
;;    specified in `ecb-layout-nr'. All changes to the layout must be made
;;    by customizing this new option. Please read the very detailed comment
;;    of `ecb-layout-nr'!
;; 2. Adding new layouts is now much easier and more straight forward: We
;;    have now a main core-layout function (`ecb-redraw-layout') which is
;;    the "environment" for the specific "layout-index" functions. The core
;;    function does first some layout independent actions, then calls the
;;    layout-index-function for the index which has been set in
;;    `ecb-layout-nr' and after that it does some layout independent
;;    actions again (see the comments in this function).
;;    An index layout function must follow the following guide-lines:
;;    - The name of the function must be
;;      "ecb-layout-function-<integer>". So this function is called for
;;      layouting if a user has set in `ecb-layout-nr' <integer> als
;;      general layout index.
;;    - A layout functon is called without any argument.
;;    - Preconditions a layout-function can assume:
;;      + The current frame contains only one window
;;      + This window is not dedicated
;;    - Postconditions a layout-function must fulfil after finishing the
;;      job:
;;      + All windows of the layout must be created.
;;      + The edit window must not be splitted! (This is done outside a
;;        layout-function)
;;      + The edit window must be stored in `ecb-edit-window'
;;      + The compilation window (if one) must be stored in
;;        `ecb-compile-window'.
;;    - Things a layout function can/should use:
;;      + Height of the compilation window (if any): `ecb-compile-window-height'
;;      + Height of the ECB-windows: `ecb-windows-height'
;;      + Width of the ECB-windows: `ecb-windows-width'
;;    A good recipe to make a new layout-function is to copy an existing
;;    one and modify that one.
;;
;;
;; New adviced intelligent window-functions as replacement for these originals:
;; - `other-window'
;; - `delete-window'
;; - `delete-other-windows'
;; - `split-window-horizontally'
;; - `split-window-vertically'
;; - `find-file-other-window'
;; - `switch-to-buffer-other-window'
;; The behavior of the adviced functions is:
;; - All these function behaves exactly like their corresponding original
;;   functons but they always act as if the edit-window(s) of ECB would be the
;;   only window(s) of the ECB-frame. So the edit-window(s) of ECB seems to be
;;   a normal Emacs-frame to the user.
;; - If called in a not edit-window of ECB all these function jumps first to
;;   the (first) edit-window, so you can never destroy the ECB-window layout
;;   unintentionally.
;;
;; IMPORTANT: A note for programing elisp for packages which work during
;; activated ECB (for ECB itself too :-): ECB offers three macros for easy
;; temporally (regardless of the settings in `ecb-advice-window-functions'!)
;; using all original-functions, all adviced functions or only some adviced
;; functions:
;; - `ecb-with-original-functions'
;; - `ecb-with-adviced-functions'
;; - `ecb-with-some-adviced-functions'
;;
;; IMPORTANT: For each new layout with index <index> the programmer must
;; write two functions for this feature:
;; - 'ecb-delete-other-windows-in-editwindow-<index>' and
;; - 'ecb-delete-window-in-editwindow-<index>.
;; Both of these functions must follow the following guide-lines:
;; - Preconditions for these functions:
;;   + the edit window is splitted
;;   + These functions are always(!) with deactivated adviced `delete-window'
;;     function.
;; - What must they do:
;;   1. Checking if the point is in one of the two parts of the splitted
;;      edit-window. If in another window, do nothing and return nil.
;;   2. Checking in which part of the splitted editwindow the point is.
;;   3. Doing the appropriate action (e.g.
;;      `ecb-delete-window-in-editwindow-0' must delete this half-part
;;      of the splitted edit-window which contains the point, so the other
;;      half-part fills the whole edit-window. If the split has been undone
;;      then non nil must be returned! This action must be done appropriate
;;      for the current ECB-layout with index <index>.
;;   4. These functions can only use `delete-window' of the set of maybe
;;      adviced window functions, because of a bug in advice.el only one
;;      function�s advice can be deactivated within a advice itself!
;; - Postcondition of these functions:
;;   + The edit-window must not be splitted and the point must reside in
;;     the not deleted edit-window.

;; $Id: ecb-layout.el,v 1.32 2001/04/25 06:26:22 berndl Exp $

;;; Code:

;;; Options
(eval-when-compile
  ;; to avoid compiler grips
  (require 'cl))

(defgroup ecb-layout nil
  "Settings for the screenlayout of the Emacs code browser."
  :group 'ecb
  :prefix "ecb-")


(defconst ecb-layout-option-set-function
  '(lambda (symbol value)
     (set symbol value)
     ;; we must check this because otherwise the layout would be drawn
     ;; if we have changed the initial value regardless if ECB is
     ;; activated or not.
     (if (and (boundp 'ecb-activated)
              ecb-activated)
         (ecb-redraw-layout))))

(defcustom ecb-layout-nr 9
  "*Define the window layout of ECB. A positive integer which sets the
general layout. Currently there are 10 predefined layouts with index from 0 to
9. You can savely try out any of them by changing this value and saving it
only for the current session. If you are sure which layout you want you can
save it for future sessions. To get a picture of the layout for index <index>
call C-h f ecb-layout-function-<index>, e.g. `ecb-layout-function-9'.

Currently available layouts \(see the doc-string for a picture ot the layout):
`ecb-layout-function-0'
`ecb-layout-function-1'
`ecb-layout-function-2'
`ecb-layout-function-3'
`ecb-layout-function-4'
`ecb-layout-function-5'
`ecb-layout-function-6'
`ecb-layout-function-7'
`ecb-layout-function-8'
`ecb-layout-function-9'

Regardless of the settings you define here: If you have destroyed or
changed the ECB-screen-layout by any action you can always go back to this
layout with `ecb-redraw-layout'"
  :group 'ecb-layout
  :initialize 'custom-initialize-default
  :set ecb-layout-option-set-function
  :type 'integer)

(defconst ecb-old-compilation-window-height compilation-window-height)

(defcustom ecb-compile-window-height 5.0
  "*If you want a compilation window shown at the bottom
of the ECB-layout then set here the height of it \(Default is a height of 5).
If you redraw the current layout with `ecb-redraw-layout' then the compilation
window (if any) shows always your last \"compile\"-output \(this can be a real
compilation, a grepping or any opther things using the compilation-mode of
Emacs) and has the heigth you set here. If the number is less than 1.0 the
height is a fraction of the frame height.

If you do not set a durable compilation window then doing a compilation
splits temporally the edit window vertically if the edit window is not
splitted already \(see documentation of the
window-function-replacements, e.g. `ecb-delete-window') or uses the
\"other\" edit window temporally for comilation output if the edit window
is already splitted.

Regardless of the settings you define here: If you have destroyed or
changed the ECB-screen-layout by any action you can always go back to this
layout with `ecb-redraw-layout'"
  :group 'ecb-layout
  :initialize 'custom-initialize-default
  :set ecb-layout-option-set-function
  :type '(radio (const :tag "No compilation window" nil)
                (number :tag "Window height")))

(defcustom ecb-compile-window-temporally-enlarge nil
  "*Let Emacs the compile-window of the ECB-layout temporally enlarge
after finishing the compilation-output. If nil then the compile-window has
always exactly the height defined in `ecb-compile-window-height' otherwise it
is enlarged to the value of `compilation-window-height' after finishing
compilation. To restore the ECB-layout just call `ecb-redraw-layout'."
  :group 'ecb-layout
  :initialize 'custom-initialize-default
  :set ecb-layout-option-set-function
  :type 'boolean)

;; This variable is also set by the following adviced functions:
;; - `delete-other-windows'
;; - `delete-window'
;; - `split-window-vertically'
;; - `split-window-horizontally'
(defcustom ecb-split-edit-window nil
  "*Sets how and if the edit window should be splitted.
But be aware: ECB offers four somehow intelligent \"window-\(un)splitting\"-
functions:
- `delete-other-windows'
- `delete-window'
- `split-window-vertically'
- `split-window-horizontally'.
If `ecb-advice-window-functions' is set properly then ECB advices these
functions so they are more suitable for ECB.

These adviced function change the value of this option too so do not wonder if
you open a customize buffer for this option and it contains a value you have
not set. This value has been set from one of these adviced functions! Also
`ecb-redraw-layout' is always oriented on the CURRENT value of this option
regardless if set by your customization or by one of these adviced functions!

But you can always \(un)split the edit-window by customizing this option and
ECB uses at start-time always the value you have set for this option!"
  :group 'ecb-layout
  :initialize 'custom-initialize-default
  :set ecb-layout-option-set-function
  :type '(radio (const :tag "Split horizontally"
                       :value horizontal)
                (const :tag "Split vertically"
                       :value vertical)
                (const :tag "Do not split"
                       :value nil)))

(defcustom ecb-select-compile-window nil
  "*Set this to non nil if compilation-output is not displayed in the
ECB-compile-window of the choosen ECB-layout. Normally this should not be
necessary because compilation automatically takes place in the
ECB-compile-window and the point remains in the edit-window. But maybe you
have defined a new \"wild\" layout and with this layout compilation is somehow
magically done in some other window than the ECB-compile-window. Then you can
set this variable to non nil and the following takes place:
1. At begin of the compilation the point jumps explicitly into the
   ECB-compile-window.
2. Compilation is done in the compile window. During the whole process the
   point stays in the compile window.
3. After finishing compilation the point jumps back to the edit-window from
   which compilation has been started.
The drawback of this method is that the point stays in the ECB-compile-window
during compilation process."
  :group 'ecb-layout
  :type 'boolean)

(defcustom ecb-windows-width 0.33
  "*The width of the ECB windows in columns when they are placed to the left
or right of the edit window. If the number is less than 1.0 the width is a
fraction of the frame width."
  :group 'ecb-layout
  :initialize 'custom-initialize-default
  :set ecb-layout-option-set-function
  :type 'number)

(defcustom ecb-windows-height 0.33
  "*The height of the ECB windows in lines when they are placed above or below
the edit window. If the number is less than 1.0 the width is a fraction of the
frame height."
  :group 'ecb-layout
  :initialize 'custom-initialize-default
  :set ecb-layout-option-set-function
  :type 'number)

(defcustom ecb-other-window-jump-behavior 'all
  "*Which windows of ECB should be accessable by the ECB-adviced function
`other-window', an intelligent replacement for the Emacs standard version of
`other-window'. Following settings are possible:
- 'all: ECB will cycle through all windows of ECB, means it behaves like the
  original `other-window'.
- 'only-edit: ECB will only cycle through the edit-windows of ECB.
- 'edit-and-compile: Like 'only-edit plus the compile window if any."
  :group 'ecb-layout
  :type '(radio (const :tag "All windows" all)
                (const :tag "Only edit windows" only-edit)
                (const :tag "Edit + compile window" edit-and-compile)))


;; (defcustom ecb-delete-other-windows-behavior 'smart
;;   "*What should ECB do when deleting other windows.  This should be used in all
;; advice to enable/disable smart deletion of other windows."
;;   :group 'ecb-layout
;;   :type '(radio (const :tag "Smart deletion of windows within ECB"
;;                        :value smart)
;;                 (const :tag "Standard deletion of all windows"
;;                        :value standard)))

(defcustom ecb-advice-window-functions '(other-window
                                         delete-window
                                         delete-other-windows
                                         split-window-horizontally
                                         split-window-vertically
                                         find-file-other-window
                                         switch-to-buffer-other-window)
  "*Use the intelligent windows functions of ECB instead of the standard
Emacs functions. You can choose the following functions to be adviced by ECB
so they behave as if the edit-window\(s) of ECB would be the only windows\(s)
of the ECB-frame:
- `other-window'
- `delete-window'
- `delete-other-windows'
- `split-window-horizontally'
- `split-window-vertically'
- `find-file-other-window'
- `switch-to-buffer-other-window'

For working most conveniant with ECB it is the best to advice all these
functions, because then all the standard-shortcuts of these functions are also
useable with ECB without doing anything else. Also other packages can interact
best with ECB if these functions are all adviced. If these adviced functions
are called in another frame than the ECB-frame they behave all exactly like the
not adviced versions!

But please read also the following:

Normally all packages should work correct with ECB and it�s adviced functions
but if there occur problems with a package cause of some of these adviced
functions ECB offers the following fall-back solution:

1. Deactivate in `ecb-advice-window-functions' all the adviced-functions which
   make problems with other packages.
2. For every of the adviceable functions <adv-func> ECB offers a interactively
   function named \"ecb-<adv-func>\" which does exactly the same as the
   adviced version of <adv-func>. Use \"ecb-<adv-func>\" instead the original
   one to get the proper ECB behavior even if the function is not adviced
   anymore.
3. You can bind in `ecb-activate-hook' the standard-shortcut of <adv-func> to
   \"ecb-<adv-func>\" and rebind it in `ecb-deactivate-hook' to <adv-func>.
4. Now you have the best of both worlds: The problematic package works and you
   have the ECB-behavior of <adv-func> as if it would be adviced.

Here is an example: Suppose you must deactivating the advice for
`find-file-other-window'. Then you deactivate this function with this option
and you can use `ecb-find-file-other-window' instead. Bind the shortcut you
normally use for `find-file-other-window' to `ecb-find-file-other-window'
\(use `ecb-activate-hook' for this) and rebind it to the original function in
the `ecb-deactivate-hook'."
  :group 'ecb-layout
  :initialize 'custom-initialize-default
  :set '(lambda (symbol value)
          (set symbol value)
          (if (and (boundp 'ecb-activated)
                   ecb-activated)            
              (ecb-activate-adviced-functions value)))
  :type '(set (const :tag "other-window"
                     :value other-window)
              (const :tag "delete-window"
                     :value delete-window)
              (const :tag "delete-other-windows"
                     :value delete-other-windows)
              (const :tag "split-window-horizontally"
                     :value split-window-horizontally)
              (const :tag "split-window-vertically"
                     :value split-window-vertically)
              (const :tag "find-file-other-window"
                     :value find-file-other-window)
              (const :tag "switch-to-buffer-other-window"
                     :value switch-to-buffer-other-window)))


(defcustom ecb-use-dedicated-windows t
  "*Use dedicated windows for the ECB buffers."
  :group 'ecb-layout
  :type 'boolean)

;; ====== internal variables ====================================

(defvar ecb-frame nil
  "Frame where ECB runs")

(defvar ecb-edit-window nil
  "Window to edit source in. If this window is splitted in two windows then
`ecb-edit-window' is always the leftmost/topmost window of the two
edit-windows! ")
(defvar ecb-last-edit-window-with-point nil
  "The edit-window of ECB which had the point before an emacs-command is
done.")
(defvar ecb-compile-window nil
  "Window to display compile-output in.")

;; =========== intelligent window functions ==========================

(defconst ecb-adviceable-functions
  '(other-window
    split-window-vertically
    split-window-horizontally
    delete-window
    delete-other-windows
    find-file-other-window
    switch-to-buffer-other-window
    )
  "A list of functions which can be advised by the ECB package.")

;; utilities
(defun ecb-activate-adviced-functions (functions)
  "Acivates the ecb-advice of exactly FUNCTIONS and only of FUNCTIONS, means
deactivates also all functions of `ecb-adviceable-functions' which are not
element of FUNCTIONS. FUNCTIONS must be nil or a subset of
`ecb-adviceable-functions'."
  (dolist (elem ecb-adviceable-functions)
    (if (memq elem functions)
        (ad-enable-advice elem 'around 'ecb)
      (ad-disable-advice elem 'around 'ecb))
    (ad-activate elem)))

(defmacro ecb-with-original-functions (&rest body)
  "Evaluates BODY with all adviced functions of ECB deactivated \(means with
their original definition). Restores always the previous state of the ECB
adviced functions, means after evaluating BODY it activates the advices of
exactly the functions in `ecb-advice-window-functions'!"
  `(unwind-protect
       (progn
         (ecb-activate-adviced-functions nil)
         ,@body)
     (ecb-activate-adviced-functions ecb-advice-window-functions)))

(defmacro ecb-with-adviced-functions (&rest body)
  "Evaluates BODY with all adviceable functions of ECB activated \(means with
their new ECB-ajusted definition). Restores always the previous state of the
ECB adviced functions, means after evaluating BODY it activates the advices of
exactly the functions in `ecb-advice-window-functions'!"
  `(unwind-protect
       (progn
         (ecb-activate-adviced-functions ecb-adviceable-functions)
         ,@body)
     (ecb-activate-adviced-functions ecb-advice-window-functions)))

(defmacro ecb-with-some-adviced-functions (functions &rest body)
  "Like `ecb-with-adviced-functions' but activates the advice of exactly
FUNCTIONS. Restores always the previous state of the ECB adviced functions,
means after evaluating BODY it activates the advices of exactly the functions
in `ecb-advice-window-functions'!
FUNCTIONS must be nil or a subset of `ecb-adviceable-functions'!"
  `(unwind-protect
       (progn
         (ecb-activate-adviced-functions ,functions)
         ,@body)
     (ecb-activate-adviced-functions ecb-advice-window-functions)))

(defun ecb-point-in-edit-window ()
  "Return non nil iff point stays in an edit-window nil otherwise."

  (cond ((eq (selected-window) ecb-edit-window)
         t)
        ((and ecb-split-edit-window
              (eq (previous-window (selected-window) 0) ecb-edit-window))
         t)
        (t nil)))

(defun ecb-pre-command-hook-function ()
  "During activated ECB this function is added to `pre-command-hook' to set
always `ecb-last-edit-window-with-point' correct so other functions can use
this variable."
  (if (ecb-point-in-edit-window)
      (setq ecb-last-edit-window-with-point (selected-window))))

(defun ecb-ediff-before-setup-hook ()
  "Added to the `ediff-before-setup-windows-hook' during ECB is activated. It
temporally deactivates the advices because otherwise ediff does not work."
  (ecb-activate-adviced-functions nil))

(defun ecb-ediff-quit-hook ()
  "Added to the end of `ediff-quit-hook' during ECB is activated. It
restores the advices after finishing ediff."
  (ecb-activate-adviced-functions ecb-advice-window-functions))


;; here come the advices

;; Important: `other-window', `delete-window', `delete-other-windows',
;; `split-window-horizontally' and `split-window-vertically' need none of the
;; other advices and can therefore be used savely by the other advices (means,
;; other functions or advices can savely (de)activate these "basic"-advices!
(defadvice other-window (around ecb)
  "The ECB-version of `other-window'. Works exactly like the original function
with the following ECB-ajustment:

The behavior depends on `ecb-other-window-jump-behavior'."
  (if (or (not (eq (selected-frame) ecb-frame))
          (eq ecb-other-window-jump-behavior 'all))
      ;; here we process the 'all value of `ecb-other-window-jump-behavior'
      ad-do-it
    ;; in the following cond-clause `ecb-other-window-jump-behavior' can only
    ;; have the values 'only-edit and 'edit-and-compile! we have implemented
    ;; the logic for the values 1 and -1 for ARG-argument of other-window.
    ;; This algorithm is called ARG-times with the right direction if ARG != 1
    ;; or -1.
    (let ((count (if (ad-get-arg 0)
                     (if (< (ad-get-arg 0) 0)
                         (* -1 (ad-get-arg 0))
                       (ad-get-arg 0))
                   1))
          (direction (if (or (not (ad-get-arg 0)) (>= (ad-get-arg 0) 0)) 1 -1)))
      (while (> count 0)
        (setq count (1- count))
        (cond ((eq (selected-window) ecb-edit-window)
               (if (= direction 1)
                   (if ecb-split-edit-window
                       (select-window (next-window))
                     (if (eq ecb-other-window-jump-behavior 'edit-and-compile)
                         (ignore-errors
                           (select-window ecb-compile-window))))
                 (if (eq ecb-other-window-jump-behavior 'edit-and-compile)
                     (ignore-errors
                       (select-window ecb-compile-window))
                   (if ecb-split-edit-window
                       (select-window (next-window))))))
              ((and ecb-compile-window
                    (eq (selected-window) ecb-compile-window))
               (ignore-errors
                 (select-window ecb-edit-window))
               (if ecb-split-edit-window
                   (if (= direction -1)
                       (select-window (next-window)))))
              ((and ecb-split-edit-window
                    (eq (previous-window (selected-window) 0) ecb-edit-window))
               (if (= direction 1)
                   (if (and (eq ecb-other-window-jump-behavior 'edit-and-compile)
                            ecb-compile-window)
                       (ignore-errors
                         (select-window ecb-compile-window))
                     (ignore-errors
                       (select-window ecb-edit-window)))
                 (ignore-errors
                   (select-window ecb-edit-window))))
              (t
               (ignore-errors
                 (select-window ecb-edit-window))))))))

(defadvice delete-window (around ecb)
  "The ECB-version of `delete-window'. Works exactly like the original
function with the following ECB-ajustment:

If called in a splitted edit-window then it works like as if the two parts of
the splitted edit window would be the only windows in the frame. This means
the part of the splitted edit-window which contains the point will be
destroyed and the other part fills the whole edit-window.
If called in an unsplitted edit-window then nothing is done.
If called in any other window of the current ECB-layout it jumps first in the
\(first) edit-window and does then it�s job \(see above)."
  (if (not (eq (selected-frame) ecb-frame))
      ad-do-it
    (if (not (ecb-point-in-edit-window))
        (ignore-errors (select-window ecb-edit-window)))
    (ad-with-originals 'delete-window
      (if ecb-split-edit-window
          (if (funcall (intern (format "ecb-delete-window-in-editwindow-%d"
                                       ecb-layout-nr)))
              (setq ecb-split-edit-window nil))))))

(defadvice delete-other-windows (around ecb)
  "The ECB-version of `delete-other-windows'. Works exactly like the
original function with the following ECB-ajustment:

If called in a splitted edit-window then it works like as if the two parts of
the splitted edit window would be the only windows in the frame. This means
the part of the splitted edit-window which contains the point fills the whole
edit-window.
If called in an unsplitted edit-window then nothing is done.
If called in any other window of the current ECB-layout it jumps first in the
\(first) edit-window and does then it�s job \(see above)."
  (if (not (eq (selected-frame) ecb-frame))
      ad-do-it
    (if (not (ecb-point-in-edit-window))
        (ignore-errors (select-window ecb-edit-window)))
    (ad-with-originals 'delete-window
      (if ecb-split-edit-window
          (if (funcall (intern (format "ecb-delete-other-windows-in-editwindow-%d"
                                       ecb-layout-nr)))
              (setq ecb-split-edit-window nil))))))

(defadvice split-window-horizontally (around ecb)
  "The ECB-version of `split-window-horizontally'. Works exactly like the
original function with the following ECB-ajustment:

If called in an unsplitted edit-window then the edit window will be splitted
horizontally.
If called in an already splitted edit-window then nothing is done.
If called in any other window of the current ECB-layout it jumps first in the
\(first) edit-window and does then it�s job \(see above)."
  (if (not (eq (selected-frame) ecb-frame))
      ad-do-it
    (if (not (ecb-point-in-edit-window))
        (ignore-errors (select-window ecb-edit-window)))
    (when (and (not ecb-split-edit-window)
               (eq (selected-window) ecb-edit-window))
      (ad-with-originals 'split-window-horizontally
        (ecb-split-hor 0.5 t))
      (setq ecb-split-edit-window 'horizontal))))

(defadvice split-window-vertically (around ecb)
  "The ECB-version of `split-window-vertically'. Works exactly like the
original function with the following ECB-ajustment:

Called in an unsplitted edit-window then the edit window will be splitted
vertically.
If called in an already splitted edit-window then nothing is done.
If called in any other window of the current ECB-layout it jumps first in the
\(first) edit-window and does then it�s job \(see above)."
  (if (not (eq (selected-frame) ecb-frame))
      ad-do-it
    (if (not (ecb-point-in-edit-window))
        (ignore-errors (select-window ecb-edit-window)))
    (when (and (not ecb-split-edit-window)
               (eq (selected-window) ecb-edit-window))
      (ad-with-originals 'split-window-vertically
        (ecb-split-ver 0.5 t))
      (setq ecb-split-edit-window 'vertical))))

(defadvice find-file-other-window (around ecb)
  "The ECB-version of `find-file-other-window'. Works exactly like the
original function but opens the file always in another edit-window.

If called in any non edit-window of the current ECB-layout it jumps first in
the \(first) edit-window and does then it�s job \(see above)."
  (if (not (eq (selected-frame) ecb-frame))
      ad-do-it
    (if (not (ecb-point-in-edit-window))
        (ignore-errors (select-window ecb-edit-window)))
    (let ((ecb-other-window-jump-behavior 'only-edit))
      (ecb-with-adviced-functions
       (if ecb-split-edit-window
           (other-window 1)
         (split-window-vertically)
         (other-window 1)))
      ;; now we are always in the other window, so we can now open the file.
      (find-file (ad-get-arg 0) (ad-get-arg 1)))))

(defadvice switch-to-buffer-other-window (around ecb)
  "The ECB-version of `switch-to-buffer-other-window'. Works exactly
like the original but switch to the buffer always in another edit-window.

If called in any non edit-window of the current ECB-layout it jumps first in
the \(first) edit-window and does then it�s job \(see above)."
  (if (not (eq (selected-frame) ecb-frame))
      ad-do-it
    (if (not (ecb-point-in-edit-window))
        (ignore-errors (select-window ecb-edit-window)))
    (let ((ecb-other-window-jump-behavior 'only-edit))
      (ecb-with-adviced-functions
       (if ecb-split-edit-window
           (other-window 1)
         (split-window-vertically)
         (other-window 1)))
      ;; now we are always in the other window, so we can switch to the buffer
      (switch-to-buffer (ad-get-arg 0) (ad-get-arg 1)))))

(defun ecb-jde-open-class-at-point-ff-function(filename &optional wildcards)
  "Special handling of the class opening at point JDE feature. This function
calls the value of `jde-open-class-at-point-find-file-function' with activated
ECB-adviced functions."
  (ecb-with-adviced-functions
   (if (and (boundp 'jde-open-class-at-point-find-file-function)
            (fboundp jde-open-class-at-point-find-file-function))
       (funcall jde-open-class-at-point-find-file-function
                filename wildcards))))

;; here come the prefixed equivalents to the adviced originals
(defun ecb-find-file-other-window ()
  "Acts like the adviced version of `find-file-other-window'."
  (interactive)
  (ecb-with-adviced-functions
   (call-interactively 'find-file-other-window)))

(defun ecb-switch-to-buffer-other-window ()
  "Acts like the adviced version of `switch-to-buffer-other-window'."
  (interactive)
  (ecb-with-adviced-functions
   (call-interactively 'switch-to-buffer-other-window)))

(defun ecb-other-window (&optional arg)
  "Acts like the adviced version of `other-window'."
  (interactive)
  (ecb-with-adviced-functions
   (call-interactively 'other-window)))

(defun ecb-delete-other-windows ()
  "Acts like the adviced version of `delete-other-windows'."
  (interactive)
  (ecb-with-adviced-functions
   (call-interactively 'delete-other-windows)))

(defun ecb-delete-window ()
  "Acts like the adviced version of `delete-window'."
  (interactive)
  (ecb-with-adviced-functions
   (call-interactively 'delete-window)))

(defun ecb-split-window-vertically ()
  "Acts like the adviced version of `split-window-vertically'."
  (interactive)
  (ecb-with-adviced-functions
   (call-interactively 'split-window-vertically)))

(defun ecb-split-window-horizontally ()
  "Acts like the adviced version of `split-window-horizontally'."
  (interactive)
  (ecb-with-adviced-functions
   (call-interactively 'split-window-horizontally)))


;; here come the internal ...delete-...functions which are called from
;; `ecb-delete-other-windows' or `ecb-delete-window' with respect
;; to the current layout-index (see `ecb-layout-nr').
(defun ecb-delete-other-windows-in-editwindow-0 ()
  (cond ((eq (selected-window) ecb-edit-window)
         (delete-window (next-window))
         (select-window ecb-edit-window)
         t)
        ((eq (previous-window (selected-window) 0)
             ecb-edit-window)
         (let ((prev-width (window-width (previous-window
                                          (selected-window) 0))))
           (setq ecb-edit-window (selected-window))
           (delete-window (previous-window (selected-window) 0))
           (if (eq ecb-split-edit-window 'horizontal)
               (enlarge-window (+ 2 prev-width) t))
           t))
        (t nil)))

(defun ecb-delete-window-in-editwindow-0 ()
  (cond ((eq (selected-window) ecb-edit-window)
         (let ((width (window-width (selected-window))))
           (setq ecb-edit-window (next-window))
           (delete-window)
           (if (eq ecb-split-edit-window 'horizontal)
               (enlarge-window (+ 2 width) t))
           t))
        ((eq (previous-window (selected-window) 0)
             ecb-edit-window)
         (delete-window)
         (select-window ecb-edit-window)
         t)
        (t nil)))

;; for the layouts 1-4, 6, 8, 9 the ecb-delete-window- and
;; ecb-delete-other-windows-in-editwindow-0 function can be used.
(defalias 'ecb-delete-other-windows-in-editwindow-1
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-1
  'ecb-delete-window-in-editwindow-0)
(defalias 'ecb-delete-other-windows-in-editwindow-2
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-2
  'ecb-delete-window-in-editwindow-0)
(defalias 'ecb-delete-other-windows-in-editwindow-3
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-3
  'ecb-delete-window-in-editwindow-0)
(defalias 'ecb-delete-other-windows-in-editwindow-4
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-4
  'ecb-delete-window-in-editwindow-0)
(defalias 'ecb-delete-other-windows-in-editwindow-6
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-6
  'ecb-delete-window-in-editwindow-0)
(defalias 'ecb-delete-other-windows-in-editwindow-8
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-8
  'ecb-delete-window-in-editwindow-0)
(defalias 'ecb-delete-other-windows-in-editwindow-9
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-9
  'ecb-delete-window-in-editwindow-0)
(defalias 'ecb-delete-other-windows-in-editwindow-10
  'ecb-delete-other-windows-in-editwindow-0)
(defalias 'ecb-delete-window-in-editwindow-10
  'ecb-delete-window-in-editwindow-0)

(defun ecb-delete-other-windows-in-editwindow-5 ()
  (cond ((eq (previous-window (selected-window) 0)
             ecb-edit-window)
         (setq ecb-edit-window (selected-window))
         (delete-window (previous-window))
         t)
        ((eq (selected-window) ecb-edit-window)
         (delete-window (next-window))
         t)
        (t nil)))

(defun ecb-delete-window-in-editwindow-5 ()
  (cond ((eq (previous-window (selected-window) 0)
             ecb-edit-window)
         (delete-window)
         (select-window ecb-edit-window)
         t)
        ((eq (selected-window) ecb-edit-window)
         (setq ecb-edit-window (next-window))
         (delete-window)
         t)
        (t nil)))

(defun ecb-delete-other-windows-in-editwindow-7 ()
  (cond ((eq (selected-window) ecb-edit-window)
         (delete-window (next-window))
         t)
        ((eq (previous-window (selected-window) 0)
             ecb-edit-window)
         (let ((prev-height (window-height (previous-window
                                            (selected-window) 0))))
           (setq ecb-edit-window (selected-window))
           (delete-window (previous-window (selected-window) 0))
           (if (eq ecb-split-edit-window 'vertical)
               (enlarge-window prev-height))
           t))
        (t nil)))

(defun ecb-delete-window-in-editwindow-7 ()
  (cond ((eq (selected-window) ecb-edit-window)
         (let ((height (window-height (selected-window))))
           (setq ecb-edit-window (next-window))
           (delete-window)
           (if (eq ecb-split-edit-window 'vertical)
               (enlarge-window height))
           t))
        ((eq (previous-window (selected-window) 0)
             ecb-edit-window)
         (delete-window)
         (select-window ecb-edit-window)
         t)
        (t nil)))



;;======= Helper-functions ===========================================

(defun ecb-split-hor(amount &optional dont-switch-window)
  "Splits the current-window and returns the absolute amount in columns"
  (let ((abs-amout (floor (if (and (< amount 1.0)
                                   (> amount -1.0))
                              (* (window-width) amount)
                            amount))))
    (ecb-split-hor-abs abs-amout dont-switch-window)
    abs-amout))

(defun ecb-split-hor-abs(amount &optional dont-switch-window)
  (split-window-horizontally amount)
  (if (not dont-switch-window)
      (select-window (next-window))))

(defun ecb-split-ver(amount &optional dont-switch-window)
  "Splits the current-window and returns the absolute amount in lines"
  (let ((abs-amout (floor (if (and (< amount 1.0)
                                   (> amount -1.0))
                              (* (window-height) amount)
                            amount))))
    (ecb-split-ver-abs abs-amout dont-switch-window)
    abs-amout))

(defun ecb-split-ver-abs(amount &optional dont-switch-window)
  (split-window-vertically amount)
  (if (not dont-switch-window)
      (select-window (next-window))))

(defun ecb-set-buffer(name)
  (switch-to-buffer name)
  (set-window-dedicated-p (selected-window) ecb-use-dedicated-windows))

(defun ecb-set-directories-buffer()
  (ecb-set-buffer ecb-directories-buffer-name))

(defun ecb-set-sources-buffer()
  (ecb-set-buffer ecb-sources-buffer-name))

(defun ecb-set-methods-buffer()
  (ecb-set-buffer ecb-methods-buffer-name))

(defun ecb-set-history-buffer()
  (ecb-set-buffer ecb-history-buffer-name))

;;======= The new layout mechanism========================================

;; Klaus: Completely rewritten the layout mechanism to make it more
;; straight forward, more customizable by users and slightly more
;; conveniant.


;; the next section makes handling of the compilation window (if any) much
;; better and more conveniant.

(defvar ecb-layout-selected-window-before-compile nil
  "Contains the window from which a compilation-process \(compile, igrep etc.)
command was called.")

(defvar ecb-last-compile-window-buffer "*scratch*"
  "Stores always the last compile-buffer \(e.g. *igrep*, *compilation*
etc...) after a compile for better relayouting later")

(defun ecb-layout-go-to-compile-window ()
  "Saves the window point was before a compilation-process and jumps then to
the end of the compilation-window if any defined in the churrent ECB-layout.
This is only be done if `ecb-select-compile-window' is non nil.
This hook will only be added to `compilation-mode-hook' if ECB was activated."
  (setq ecb-layout-selected-window-before-compile (selected-window))
  (if ecb-select-compile-window
      ;; we must du this with ignore-errors because maybe the
      ;; compilation-window was destroyed and `ecb-compile-window' was
      ;; not nil.
      (ignore-errors
        (progn
          (select-window ecb-compile-window)
          (end-of-buffer)))))

(defun ecb-layout-return-from-compilation (comp-buf process-state)
  "Jumps back to the window from which the compilation-process was started.
This is only be done if `ecb-select-compile-window' is non nil.
This hook will only be added to `compilation-finish-functions' if ECB was
activated. The arguments are required by `compilation-finish-functions' but
will not be evaluated here."
  (setq ecb-last-compile-window-buffer (buffer-name))
  (if ecb-select-compile-window
      (ignore-errors
        (select-window ecb-layout-selected-window-before-compile))))

(defun ecb-set-edit-window-split-hook-function ()
  "This function is added to `compilation-mode-hook' and `help-mode-hook' to
handle splitting the edit-window correctly."
  (if (and (not ecb-compile-window-height)
           (not ecb-split-edit-window))
      (setq ecb-split-edit-window 'vertical)))

;; the main layout core-function. This function is the "environment" for a
;; special layout function (l.b.)

(defun ecb-redraw-layout ()
  "Redraw the ECB screen according to the layout set in `ecb-layout-nr'. After
this function the edit-window is selected."
  (interactive)

  (let* ((window-before-redraw (cond ((eq (selected-window) ecb-edit-window)
                                      1)
                                     ((and ecb-split-edit-window
                                           (eq (previous-window (selected-window) 0)
                                               ecb-edit-window))
                                      2)
                                     (t 0)))
         (pos-before-redraw (and (> window-before-redraw 0) (point)))
         ;; height of ecb-compile-window-height in lines
         (ecb-compile-window-height-lines (if ecb-compile-window-height
                                              (floor
                                               (if (< ecb-compile-window-height 1.0)
                                                   (* (1- (frame-height))
                                                      ecb-compile-window-height)
                                                 ecb-compile-window-height))))
         ;; height of compilation-window-height
         (compile-window-height (if (and (not ecb-compile-window-temporally-enlarge)
                                         ecb-compile-window-height)
                                    ecb-compile-window-height-lines
                                  ecb-old-compilation-window-height)))

    ;; deactivating the adviced functions, so the layout-functions can use the
    ;; original function-definitions.
    (ecb-activate-adviced-functions nil)

    ;; first we go to the edit-window we must do this with ignore-errors
    ;; because maybe the edit-window was destroyed by some mistake or error
    ;; and `ecb-edit-window' was not nil.
    (ignore-errors
      (select-window ecb-edit-window))

    ;; Do some actions regardless of the choosen layout
    (delete-other-windows)
    (setq ecb-frame (selected-frame))
    (set-window-dedicated-p (selected-window) nil)

    ;; we force a layout-function to set both of this windows
    ;; correctly.
    (setq ecb-edit-window nil
          ecb-compile-window nil)

    ;; Now we call the layout-function
    (funcall (intern (format "ecb-layout-function-%d"
                             ecb-layout-nr)))

    ;; Now all the windows must be created and the editing window must not be
    ;; splitted! In addition the variables `ecb-edit-window' and
    ;; `ecb-compile-window' must be set the correct windows.

    ;; The following when-expression is added for better relayouting the
    ;; choosen layout if we have a compilation-window.
    (when ecb-compile-window-height
      ;; here we always stay in the `ecb-edit-window'
      (select-window (if ecb-compile-window
                         ecb-compile-window
                       (error "Compilations-window not set in the layout-function")))
      
      ;; go one window back, so display-buffer always shows the buffer in the
      ;; next window, which is then savely the compile-window.
      (select-window (previous-window (selected-window) 0))
      ;; if a relayouting is done we always display the last
      ;; compile-buffer; this can be for example a *igrep*-, a
      ;; *compilation*- or any other buffer with compile-mode.
      (display-buffer (or (get-buffer ecb-last-compile-window-buffer)
                          (get-buffer "*scratch*")))
      ;; setting compilation-window-height
      (if compile-window-height
          (setq compilation-window-height compile-window-height))
      ;; Cause of display-buffer changes the height of the compile-window we
      ;; must resize it again to the correct value
      (select-window (next-window))
      (shrink-window (- (window-height)
                        ecb-compile-window-height-lines)))

    ;; set compilation-window-height to the correct value.
    (setq compilation-window-height compile-window-height)

    (select-window (if ecb-edit-window
                       ecb-edit-window
                     (error "Edit-window not set in the layout-function")))

    ;; Maybe we must split the editing window again if it was splitted before
    ;; the redraw
    (cond ((eq ecb-split-edit-window 'horizontal)
           (ecb-split-hor 0.5 t))
          ((eq ecb-split-edit-window 'vertical)
           (ecb-split-ver 0.5 t)))

    ;; at the end of the redraw we always stay in that edit-window as before
    ;; the redraw
    (select-window ecb-edit-window)
    (if (eq window-before-redraw 2)
        (select-window (next-window)))

    (setq ecb-last-edit-window-with-point (selected-window))

    ;; Now let�s update the directories buffer
    (ecb-update-directories-buffer)

    ;; activating the adviced functions
    (ecb-activate-adviced-functions ecb-advice-window-functions)

    ;; if we were in an edit-window before redraw let us go to the old place.
    (if pos-before-redraw
        (goto-char pos-before-redraw))))


;; ========= Current available layouts ===============================

;; Here come all the index layout-functions:

;; Number 0-8 are the original ones, number 9 is new.
;; I have increased the width of the ECB-windows from 0.2 to 0.3 in 0-4, 6
;; and 8 because i think 0.2 is too small for most screens.

(defun ecb-layout-function-0 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |      |       |                                      |
   | Sour | Hist  |                 Edit                 |
   |      |       |                                      |
   |      |       |                                      |
   |--------------|                                      |
   |              |                                      |
   |  Methods     |                                      |
   |              |                                      |
   |              |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.3)
  (ecb-set-sources-buffer)
  (ecb-split-ver 0.5)
  (ecb-set-methods-buffer)
  (select-window (previous-window))
  (ecb-split-hor 0.5)
  (ecb-set-history-buffer)
  (select-window (next-window (next-window)))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-1 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                 Edit                 |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |  Sources     |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.5)
  (ecb-set-sources-buffer)
  (select-window (next-window))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-2 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |              |                                      |
   |  Sources     |                 Edit                 |
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |              |                                      |
   |  Methods     |                                      |
   |              |                                      |
   |              |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.3)
  (ecb-set-sources-buffer)
  (ecb-split-ver 0.5)
  (ecb-set-methods-buffer)
  (select-window (next-window))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-3 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                 Edit                 |
   |      |       |                                      |
   |      |       |                                      |
   |      |       |                                      |
   | Sour | Hist  |                                      |
   |      |       |                                      |
   |      |       |                                      |
   |      |       |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.5)
  (ecb-set-sources-buffer)
  (ecb-split-hor 0.5)
  (ecb-set-history-buffer)
  (select-window (next-window))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-4 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |              |                                      |
   |  Sources     |                 Edit                 |
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |              |                                      |
   |  History     |                                      |
   |              |                                      |
   |              |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.3)
  (ecb-set-sources-buffer)
  (ecb-split-ver 0.5)
  (ecb-set-history-buffer)
  (select-window (next-window))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-5 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |                                      |              |
   |                                      |  Directories |
   |                                      |              |
   |                                      |              |
   |                                      |--------------|
   |                                      |              |
   |                                      |              |
   |             Edit                     |  Sources     |
   |                                      |              |
   |                                      |              |
   |                                      |--------------|
   |                                      |              |
   |                                      |  Methods     |
   |                                      |              |
   |                                      |              |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor (- ecb-windows-width) t)
  (setq ecb-edit-window (selected-window))
  (select-window (next-window))
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.3)
  (ecb-set-sources-buffer)
  (ecb-split-ver 0.5)
  (ecb-set-methods-buffer))

(defun ecb-layout-function-6 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |      |       |                                      |
   | Sour | Hist  |                 Edit                 |
   |      |       |                                      |
   |      |       |                                      |
   |--------------|                                      |
   |              |                                      |
   |  Methods     |                                      |
   |              |                                      |
   |              |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.3)
  (ecb-set-sources-buffer)
  (ecb-split-ver 0.5)
  (ecb-set-methods-buffer)
  (select-window (previous-window))
  (ecb-split-hor 0.5)
  (ecb-set-history-buffer)
  (select-window (next-window (next-window)))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-7 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |                        |             |              |
   |                        |             |              |
   |      Directories       |  Sources    |  Methods     |
   |                        |             |              |
   |                        |             |              |
   |-----------------------------------------------------|
   |                                                     |
   |                                                     |
   |                                                     |
   |                                                     |
   |                    Edit                             |
   |                                                     |
   |                                                     |
   |                                                     |
   |                                                     |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (ecb-split-ver ecb-windows-height t)
  (ecb-set-directories-buffer)
  (ecb-split-hor 0.5)
  (ecb-set-sources-buffer)
  (ecb-split-hor 0.5)
  (ecb-set-methods-buffer)
  (if ecb-compile-window-height
      (progn
        (select-window (next-window))
        (ecb-split-ver (* -1 ecb-compile-window-height) t)
        (setq ecb-compile-window (next-window))
        (select-window (next-window))
        (switch-to-buffer ecb-history-buffer-name)
        (select-window (previous-window)))
    (select-window (next-window)))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-8 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                 Edit                 |
   |              |                                      |
   |  History     |                                      |
   |              |                                      |
   |--------------|                                      |
   |              |                                      |
   |  Methods     |                                      |
   |              |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place.
This layout works best if you set `ecb-show-sources-in-directories-buffer'
to non nil!"
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.6)
  (ecb-set-history-buffer)
  (ecb-split-ver 0.4)
  (ecb-set-methods-buffer)
  (select-window (next-window))
  (setq ecb-edit-window (selected-window)))

;; Klaus: New: Like 2 but with a fourth vertical window: ECB-History
(defun ecb-layout-function-9 ()
  "This function creates the following layout:

   -------------------------------------------------------
   |              |                                      |
   |  Directories |                                      |
   |              |                                      |
   |--------------|                                      |
   |              |                                      |
   |  Sources     |                                      |
   |              |                                      |
   |--------------|                 Edit                 |
   |              |                                      |
   |  Methods     |                                      |
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |  History     |                                      |
   |              |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)
  (ecb-set-directories-buffer)
  (ecb-split-ver 0.3)
  (ecb-set-sources-buffer)
  (ecb-split-ver 0.35)
  (ecb-set-methods-buffer)
  (ecb-split-ver 0.65)
  (ecb-set-history-buffer)
  (select-window (next-window))
  (setq ecb-edit-window (selected-window)))

(defun ecb-layout-function-10()
  "This function creates the following layout:

   -------------------------------------------------------
   |  Sources     |                                      | 
   |--------------|                                      |
   |              |                                      |
   |              |                                      |
   |              |                                      |
   |  Methods     |                 Edit                 |
   |              |                                      | 
   |              |                                      |
   |              |                                      |
   |--------------|                                      |
   |  History     |                                      |
   -------------------------------------------------------
   |                                                     |
   |                    Compilation                      |
   |                                                     |
   -------------------------------------------------------

If you have not set a compilation-window in `ecb-layout-nr' then the layout
contains no compilation window and the other windows get a little more
place."
  (when ecb-compile-window-height
    (ecb-split-ver (* -1 ecb-compile-window-height) t)
    (setq ecb-compile-window (next-window)))
  (ecb-split-hor ecb-windows-width t)

  ;;(ecb-set-directories-buffer)
  ;;(ecb-split-ver 0.3)
  (ecb-set-sources-buffer)
  (ecb-split-ver 0.2)
  (ecb-set-methods-buffer)
  (ecb-split-ver 0.75)
  (ecb-set-history-buffer)
  (select-window (next-window))
  (setq ecb-edit-window (selected-window)))


(provide 'ecb-layout)

;;; ecb-layout.el ends here
