;;; ecb-util.el --- utility functions for ECB

;; Copyright (C) 2000, 2001 Jesper Nordenberg

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
;; Contains misc utility functions for ECB.
;;
;; This file is part of the ECB package which can be found at:
;; http://home.swipnet.se/mayhem/ecb.html

;; $Id: ecb-util.el,v 1.11 2001/05/01 13:31:53 creator Exp $

;;; Code:
(defconst running-xemacs (string-match "XEmacs\\|Lucid" emacs-version))
(defconst ecb-directory-sep-char directory-sep-char)
(defconst ecb-directory-sep-string (char-to-string ecb-directory-sep-char))

(defun ecb-fix-filename(name)
  (let ((norm-path (expand-file-name name)))
    (if (= (aref norm-path (1- (length norm-path))) ecb-directory-sep-char)
        (substring norm-path 0 (1- (length norm-path)))
      norm-path)))

(defun ecb-confirm(text)
  (x-popup-dialog (list '(0 0) (selected-window)) (list text '("Yes" . t) '("No" . nil))))

;; Klaus TODO: Making this function more general, means useable for non java
;; code!!
(defun ecb-create-source(dir)
  (let ((filename (read-from-minibuffer "Source name: ")))
    (ecb-switch-to-edit-buffer)
    (jde-gen-class-buffer (concat dir "/" filename (if (not (string-match "\\." filename)) ".java")))))

(defun ecb-create-directory-source(node)
  (ecb-create-source (tree-node-get-data node)))

(defun ecb-create-source-2(node)
  (ecb-create-source (ecb-fix-filename (file-name-directory
					(tree-node-get-data node)))))

(defun ecb-create-file(node)
  (ecb-create-file-3 (tree-node-get-data node)))

(defun ecb-create-file-3(dir)
  (ecb-switch-to-edit-buffer)
  (find-file (concat dir "/" (read-from-minibuffer "File name: "))))

(defun ecb-create-file-2(node)
  (ecb-create-file-3 (ecb-fix-filename (file-name-directory
					(tree-node-get-data node)))))

(defun ecb-delete-source-2(node)
  (ecb-delete-source (tree-node-get-data node)))

(defun ecb-delete-source(file)
  (when (ecb-confirm (concat "Delete " file "?"))
    (when (get-file-buffer file)
      (kill-buffer (get-file-buffer file)))
      
    (delete-file file)))
;;   (save-current-buffer
;;     (ecb-buffer-select ecb-history-buffer-name)
;;     (tree-node-remove-child (tree-buffer-get-root)
;;                 (tree-node-find-child-data (tree-buffer-get-root)
;;                                file))
;;     (ecb-buffer-select ecb-sources-buffer-name)
;;     (tree-node-remove-child (tree-buffer-get-root)
;;                 (tree-node-find-child-data (tree-buffer-get-root)
;;                                file))))

(defun ecb-create-directory(parent-node)
  (make-directory (concat (tree-node-get-data parent-node) "/" (read-from-minibuffer "Directory name: ")))
  (ecb-update-directory-node parent-node)
  (tree-buffer-update))

(defun ecb-delete-directory(node)
  (delete-directory (tree-node-get-data node))
  (ecb-update-directory-node (tree-node-get-parent node))
  (tree-buffer-update))

(provide 'ecb-util)

;;; ecb-util.el ends here
