;;; ecb-eshell.el --- eshell integration for the ECB.

;; $Id: ecb-eshell.el,v 1.14 2001/12/15 10:11:35 burtonator Exp $

;; Copyright (C) 2000-2003 Free Software Foundation, Inc.
;; Copyright (C) 2000-2003 Kevin A. Burton (burton@openprivacy.org)

;; Author: Kevin A. Burton (burton@openprivacy.org)
;; Maintainer: Kevin A. Burton (burton@openprivacy.org)
;; Location: http://relativity.yi.org
;; Keywords: 
;; Version: 1.0.0

;; This file is [not yet] part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify it under
;; the terms of the GNU General Public License as published by the Free Software
;; Foundation; either version 2 of the License, or any later version.
;;
;; This program is distributed in the hope that it will be useful, but WITHOUT
;; ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS
;; FOR A PARTICULAR PURPOSE.  See the GNU General Public License for more
;; details.
;;
;; You should have received a copy of the GNU General Public License along with
;; this program; if not, write to the Free Software Foundation, Inc., 59 Temple
;; Place - Suite 330, Boston, MA 02111-1307, USA.

;;; Commentary:

;; This package provides eshell integration for the ECB.  This basically allows
;; you to jump to the eshell in the compilation window, synch up the current
;; eshell with the current ECB buffer and run commands without getting in the
;; way.
;;
;; It provides the following features:
;;
;; - ability to jump to the eshell buffer within the compilation window ( C-.e )
;;   If the eshell isn't running it will be started
;;
;; - expands the compilation window when you run commands.  So for example it
;;   allows you to view the eshell in minimized mode and then when you run 'ls'
;;   the window automatically expands.
;;
;; - Sychronizes the current directory of the eshell with the current buffer
;;   with each every ECB buffer.
;;
;; - Provides smart window layout of the eshell buffer.  This makes sure that
;;   the eshell is taking up the exact amount of space and that nothing is
;;   hidden.
;; 
;; The goal is to make it easy to jump to a command prompt to run OS level
;; commands.  
;; 
;; If you enjoy this software, please consider a donation to the EFF
;; (http://www.eff.org)

;;; History:
;;
;; - Sat Dec 15 2001 01:50 AM (burton@openprivacy.org): We are not being much
;; smarter about saving selected windows.
;;
;; - Fri Dec 14 2001 05:57 PM (burton@openprivacy.org): fixed a bug which caused 
;;
;; - Fri Dec 14 2001 04:48 PM (burton@openprivacy.org): only run eshell/cd if
;; the current directory is different than the eshell/pwd (this is a performance
;; issue and needs to be added in ecb-eshell-current-buffer-sync
;;
;;   - we can't do this.  eshell/pwd does't return a string.  Instead we should
;;     change to the eshell-buffer and see what the directory default-directory
;;     is there.
;;
;; - Fri Dec 14 2001 03:24 PM (burton@openprivacy.org): use
;; eshell-pre-command-hook to increase the size of the window if we are in an
;; ECB layout (and the ecb is activated)...
;;
;; - Sun Nov 18 2001 07:20 PM (burton@openprivacy.org): putting the cursor one
;;   line from the bottom of the window.

;;; TODO:
;;
;; - Right now ecb-eshell doesn't work with dired.  Why?  Try to setup a hook
;; and an ecb-eshell-dired-buffer-sync function that will take care of this.

;; - BUG: ecb-eshell STILL recenters itself!!!  This is BS.
;; 
;;   - this only manifests itself when I an runing eshell.
;;
;;   - the bug is in ecb-eshell-current-buffer-sync
;;
;;   - the problem is in (eshell-send-input)

;;; Code:

(defun ecb-eshell-current-buffer-sync()
  "Synchronize the eshell with the current buffer."
  (interactive)

  ;;only do this if the user is looking at the eshell buffer

  (if (ecb-eshell-running-p)      
      (let((source-buffer-directory default-directory))

        (set-buffer (get-buffer-create eshell-buffer-name))

        ;;at this point source-buffer-directory is a snapshot of the source
        ;;buffer window and default directory is the directory in the eshell
        ;;window

        (if (not (string-equal source-buffer-directory default-directory))
            (progn 

              (save-excursion

                (set-buffer eshell-buffer-name)

                ;;change the directory without showing the cd command
                (eshell/cd source-buffer-directory)

                ;;execute the command
                (save-selected-window
                  (select-window (get-buffer-window eshell-buffer-name))
                
                  (eshell-send-input)))
              
              (ecb-eshell-recenter))))))

(defun ecb-eshell-recenter()
  "Recenter the eshell window so that the prompt is at the end of the buffer."

  (when (ecb-eshell-running-p)

    (save-selected-window

      (select-window (get-buffer-window eshell-buffer-name))
        
      (recenter -1))))

(defun ecb-eshell-running-p()
  "Return true if eshell is currently running."

  (and (boundp 'eshell-buffer-name)
       eshell-buffer-name
       (get-buffer eshell-buffer-name)))
  
(defun ecb-eshell-goto-eshell()
  (interactive)
  
  ;;first... make sure that we change the compilation window to the eshell
  ;;buffer.

  (if (ecb-eshell-running-p)
      (progn 
        (select-window ecb-compile-window)

        (switch-to-buffer eshell-buffer-name))

    ;;we auto start the eshell here?  I think so..
    (select-window ecb-compile-window)
    
    (eshell))

  (ecb-eshell-recenter))

(defun ecb-eshell-resize()
  "Resize the eshell so more information is available.  This is usually done so
  that the eshell has more screen space after we execute a command. "
  (interactive)

  (let(enlargement window)
  
    (setq window (get-buffer-window eshell-buffer-name))
    
    (when (and (ecb-eshell-running-p)
               (window-live-p window)
               ecb-minor-mode)
      ;;is there a better way to do this?  It seems that there should be a way
      ;;to have emacs split or expand a window by 50% like it is done in a lot
      ;;of other places (display-buffer, etc)

      (save-selected-window
      
        (select-window window)
        
        (setq enlargement (- (/ (frame-height) 2) (window-height)))
        
        (if (> enlargement 0)
            (enlarge-window enlargement))))))

(add-hook 'ecb-current-buffer-sync-hook 'ecb-eshell-current-buffer-sync)

;;(add-hook 'dired-after-readin-hook 'ecb-eshell-current-buffer-sync)

(remove-hook 'ecb-redraw-layout-hooks 'ecb-eshell-recenter)

(remove-hook 'eshell-pre-command-hook 'ecb-eshell-resize)

(define-key ecb-mode-map "\C-c.e" 'ecb-eshell-goto-eshell)

(provide 'ecb-eshell)

;;; ecb-eshell.el ends here