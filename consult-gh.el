;;; consult-gh.el --- Consulting GitHub Client -*- lexical-binding: t -*-

;; Copyright (C) 2023 Armin Darvish

;; Author: Armin Darvish
;; Maintainer: Armin Darvish
;; Created: 2023
;; Version: 0.1
;; Package-Requires: ((emacs "27.1") (consult "0.34") (gh "2.29"))
;; Homepage: https://github.com/armindarvish/consult-gh
;; Keywords: convenience, matching, tools, vc

;;; Commentary:

;;; Code:

(eval-when-compile
(require 'consult)
(require 'json)
)

(defgroup consult-gh nil
  "Consulting GitHub CLI"
  :group 'convenience
  :group 'minibuffer
  :group 'consult
  :group 'magit
  :prefix "consult-gh-")

(defcustom consult-gh-category 'consult-gh
  "Category symbol for the `consult-gh' package."
  :group 'consult-gh
  :type 'symbol)

(defcustom consult-gh-repos-category 'consult-gh-repos
  "Category symbol for the `consult-gh' package."
  :group 'consult-gh
  :type 'symbol)

(defcustom consult-gh--issues-category 'consult-gh-issues
  "Category symbol for the `consult-gh' package."
  :group 'consult-gh
  :type 'symbol)


(defcustom consult-gh-files-category 'consult-gh-files
  "Category symbol for the `consult-gh' package."
  :group 'consult-gh
  :type 'symbol)

(defcustom consult-gh-tempdir nil
"Temporary file directory for the `consult-gh' package."
  :group 'consult-gh
  :type 'string
)

(setq consult-gh-tempdir (expand-file-name "consult-gh" temporary-file-directory))

(defcustom consult-gh--default-maxnum 30
  "Maximum number of output for gh list operations normally passed top \"--limit\" in the command line."
  :group 'consult-gh
  :type 'integer)

(defcustom consult-gh-crm-separator "[\s]"
  "Separator for multiple selections with completing-read-multiple. for more info see `crm-separator'."
  :group 'consult-gh
  :type 'string)

(defcustom consult-gh-preview-buffer-mode 'markdown-mode
  "Major Mode to show README of repositories in preview."
  :group 'consult-gh
  :type 'symbol)

(defcustom consult-gh--preview-buffers-list (list)
  "List of currently open preview buffers"
  :group 'consult-gh
  :type 'list)

(defcustom consult-gh-default-orgs-list (list)
  "List of default github orgs for `consult-gh' package."
  :group 'consult-gh
  :type 'list)

(defcustom consult-gh-preview-buffer-name "*consult-gh-preview*"
  "Default directory to clone github repos in for `consult-gh' package."
  :group 'consult-gh
  :type 'string)


(defcustom consult-gh-show-preview nil
  "Default directory to clone github repos in for `consult-gh' package."
  :group 'consult-gh
  :type 'boolean)

(defcustom consult-gh-default-clone-directory nil
  "Default directory to clone github repos in for `consult-gh' package."
  :group 'consult-gh
  :type 'string)

(defcustom consult-gh-default-save-directory "~/Downloads/"
  "Default directory to clone github repos in for `consult-gh' package."
  :group 'consult-gh
  :type 'string)

(defcustom consult-gh-confirm-before-clone t
  "This variable defines whether `consult-gh' queries the user for directory and name before cloning a repo or uses the default directory and package name. It's useful to set this to nil if you want to clone multiple repos without all at once."
  :group 'consult-gh
  :type 'boolean)

(defcustom consult-gh-default-branch-to-load "ask"
  "This variable defines whether `consult-gh' queries the user for directory and name before cloning a repo or uses the default directory and package name. It's useful to set this to nil if you want to clone multiple repos without all at once."
  :group 'consult-gh
  :type 'symbol)

(defcustom consult-gh-repo-action #'consult-gh--repo-browse-url-action
  "This variable defines the function that is used when selecting a repo. By default it is set to `consult-gh--repo-browse-url-action', but you can cahnge it to other actions such as `consult-gh--repo-clone-action' or `consult-gh--repo-fork-action'."
  :group 'consult-gh
  :type 'function)

(defcustom consult-gh-issue-action #'consult-gh--issue-browse-url-action
  "This variable defines the function that is used when selecting an issue. By default it is set to `consult-gh--issue-browse-url-action', but you can change it to other actions."
  :group 'consult-gh
  :type 'function)

(defcustom consult-gh-file-action #'consult-gh--files-browse-url-action
  "This variable defines the function that is used when selecting a file. By default it is set to `consult-gh--browse-files-url-action', but you can change it to other actions."
  :group 'consult-gh
  :type 'function)


(defvar consult-gh--repos-history nil
  "History variable for repos used in `consult-gh-search-repos'.")

(defvar consult-gh--org-history nil
  "History variable for orgs used in  `consult-gh-orgs' .")

(defvar consult-gh--issues-history nil
  "History variable for isseus used in  `consult-gh-search-issues' .")

(defvar consult-gh--known-orgs-list nil
  "List of previously visited orgs for `consult-gh'.")

(defvar consult-gh--known-repos-list nil
  "List of previously visited orgs for `consult-gh'.")

(defface consult-gh-default-face
  `((t :inherit 'default)) "default face used items in the list")
(defface consult-gh-visibility-face
  `((t :inherit 'font-lock-variable-face)) "inherit from font-lock-variable-face for repos visibility")
(defface consult-gh-user-face
  `((t :inherit 'font-lock-warning-face)) "inherit from font-lock-warning-face for the user")
(defface consult-gh-date-face
  `((t :inherit 'font-lock-keyword-face)) "inherit from font-lock-keyword-face for the date")
(defface consult-gh-tags-face
  `((t :inherit 'font-lock-comment-face)) "inherit from font-lock-comment-face for the tags")

(defun consult-gh--output-cleanup (string)
"Remove non UTF-8 characters if any in the string. This is used in "
  (string-join
   (delq nil (mapcar (lambda (ch) (encode-coding-char ch 'utf-8 'unicode))
                     string))))

(defun consult-gh--markdown-to-org-footnotes (&optional buffer)
"Convert markdown style footnotes to org-mode style footnotes"
  (let ((buffer (or buffer (current-buffer))))
    (with-current-buffer buffer
      (save-mark-and-excursion
        (save-restriction
          (goto-char (point-max))
          (insert "\n")
          (while (re-search-backward "^\\[\\([^fn].*\\)\\]:" nil t)
            (replace-match "[fn:\\1] ")))))
    nil))

(defun consult-gh--markdown-to-org-emphasis (&optional buffer)
"Convert markdown style emphasis to org-mode style emphasis"
  (let ((buffer (or buffer (current-buffer))))
    (with-current-buffer buffer
      (save-mark-and-excursion
        (save-restriction
          (goto-char (point-min))
          (when (re-search-forward "^-\\{2\\}$" nil t)
          (delete-char -2)
          (insert "=================================\n")
          (replace-regexp "\\(^[a-zA-Z]+:[[:blank:]]\\)" "#+\\1" nil 0 (point-marker) nil nil))
          (while (re-search-forward "#\\|\\*\\{1,2\\}\\(?1:.+?\\)\\*\\{1,2\\}|_\\{1,2\\}\\(?2:.+?\\)_\\{1,2\\}\\|`\\(?3:[^`].+?\\)`\\|```\\(?4:.*\n\\)\\(?5:[^`]*\\)```" nil t)
            (pcase (match-string-no-properties 0)
              ("#" (if (looking-at "#\\|[[:blank:]]")
                       (progn
                         (delete-char -1)
                         (insert "*"))))

              ((pred (lambda (el) (string-match-p "\\*\\{1\\}[^\\*]*?\\*\\{1\\}" el)))
               (replace-match "/\\1/"))

              ((pred (lambda (el) (string-match-p "\\*\\{2\\}.+?\\*\\{2\\}" el)))
               (replace-match "*\\1*"))

              ((pred (lambda (el) (string-match-p "_\\{1\\}[^_]*?_\\{1\\}" el)))
               (replace-match "/\\2/"))

              ((pred (lambda (el) (string-match-p "_\\{2\\}.+?_\\{2\\}" el)))
               (replace-match "*\\2*"))

              ((pred (lambda (el) (string-match-p "`[^`].+?`" el)))
               (replace-match "=\\3="))

              ((pred (lambda (el) (string-match-p "```.*\n[^`]*```" el)))
               (replace-match "#+begin_src \\4\n\\5\n#+end_src\n")))))))
    nil))

(defun consult-gh--markdown-to-org-links (&optional buffer)
"Convert markdown links to org-mode links"
  (let ((buffer (or buffer (current-buffer))))
    (with-current-buffer buffer
      (save-mark-and-excursion
        (save-restriction
          (goto-char (point-min))
          (while (re-search-forward "\\[\\(?1:.+?\\)\\]\\[\\]\\{1\\}\\|\\[\\(?2:.[^\\[]+?\\)\\]\\[\\(?3:.[^\\[]+?\\)\\]\\{1\\}\\|\\[\\(?4:.+?\\)\\]\(#\\(?5:.+?\\)\)\\{1\\}\\|.\\[\\(?6:.+?\\)\\]\(\\(?7:[^#].+?\\)\)\\{1\\}" nil t)
            (pcase (match-string-no-properties 0)
              ((pred (lambda (el) (string-match-p "\\[.+?\\]\\[\\]\\{1\\}" el)))
               (replace-match "[fn:\\1]"))

              ((pred (lambda (el) (string-match-p "\\[.[^\\[]+?\\]\\[.[^\\[]+?\\]\\{1\\}" el)))
               (replace-match "\\2 [fn:\\3]"))

              ((pred (lambda (el) (string-match-p "\\[.+?\\]\(#.+?\)\\{1\\}" el)))
               (replace-match "[[*\\5][\\4]]"))

              ((pred (lambda (el) (string-match-p "!\\[.*\\]\([^#].*\)" el)))
               (replace-match "[[\\7][\\6]]"))

              ((pred (lambda (el) (string-match-p "[[:blank:]]\\[.*\\]\([^#].*\)" el)))
               (replace-match " [[\\7][\\6]]"))))

          (goto-char (point-min))
          (while
              (re-search-forward
               "\\[fn:\\(.+?\\)\\]\\{1\\}" nil t)
            (pcase (match-string 0)
              ((pred (lambda (el) (string-match-p "\\[fn:.+?[[:blank:]].+?\\]\\{1\\}" (substring-no-properties el))))
               (progn
                 (replace-regexp-in-region "[[:blank:]]" "_" (match-beginning 1) (match-end 1)))))))))
    nil))

(defun consult-gh--markdown-to-org (&optional buffer)
  "Convert from markdown format to org-mode format"
  (let ((buffer (or buffer (get-buffer-create consult-gh-preview-buffer-name))))
    (with-current-buffer buffer
      (consult-gh--markdown-to-org-footnotes buffer)
      (consult-gh--markdown-to-org-emphasis buffer)
      (consult-gh--markdown-to-org-links buffer)
      (org-mode)
      (org-table-map-tables 'org-table-align t)
      (org-fold-show-all)
      (goto-char (point-min))))
  nil)

(defun consult-gh--call-process (&rest args)
 "Run \"gh\" with args and return outputs"
(if (executable-find "gh")
      (with-temp-buffer
        (set-buffer-file-coding-system 'cp1047)
        (list (apply 'call-process "gh" nil (current-buffer) nil args)
                         (replace-regexp-in-string "" "\n"
                                                   (buffer-string))))
  (progn
      (message (propertize "\"gh\" is not found on this system" 'face 'warning))
      '(0 ""))
))

(defun consult-gh--command-to-string (&rest args)
  "Run \"gh\" with args and return output as a string if there is no error. If there are erros pass them to *Messages*."
  (let ((out (apply #'consult-gh--call-process args)))
          (if (= (car out) 0)
              (cadr out)
            (progn
              (message (cadr out))
              nil)
            )))

(defun consult-gh-kill-preview-buffers ()
  (interactive)
  (when consult-gh--preview-buffers-list
    (mapcar (lambda (buff) (if (buffer-live-p buff)
                             (kill-buffer buff))
               (unless (buffer-live-p buff)
                             (setq consult-gh--preview-buffers-list (delete buff consult-gh--preview-buffers-list)))
               ) consult-gh--preview-buffers-list)
    )
)

(defun consult-gh--api-get-json (url)
  (consult-gh--call-process "api" "-H" "Accept: application/vnd.github+json" url))

(defun consult-gh--api-json-to-table (json &optional key)
  (let ((json-object-type 'hash-table)
        (json-array-type 'list)
        (json-key-type 'string)
        (json-false :false))
    (if key
        (gethash key (json-read-from-string json))
      (json-read-from-string json))))

(defun consult-gh--files-get-branches (repo)
  (consult-gh--api-get-json (concat "repos/" repo "/branches")))

(defun consult-gh--files-branches-table-to-list (table repo)
    (mapcar (lambda (el) (propertize (gethash "name" el) ':repo repo ':branch (gethash "name" el) ':url (gethash "url" el))) table))

(defun consult-gh--files-branches-list-items (repo)
(let ((response (consult-gh--files-get-branches repo)))
  (if (eq (car response) 0)
      (consult-gh--files-branches-table-to-list (consult-gh--api-json-to-table (cadr response)) repo)
    (message (cadr response)))))



(defun consult-gh--files-get-trees (repo &optional branch)
  (let ((branch (or branch "HEAD")))
  (consult-gh--api-get-json (concat "repos/" repo "/git/trees/" branch ":?recursive=1"))))

(defun consult-gh--files-table-to-list (table repo &optional branch)
   (let ((branch (or branch "HEAD")))
    (mapcar (lambda (el) (propertize (gethash "path" el) ':repo repo ':branch branch ':url (gethash "url" el) ':path (gethash "path" el) ':size (gethash "size" el))) table)))

(defun consult-gh--files-list-items (repo &optional branch)
(let* ((branch (or branch "HEAD"))
       (response (consult-gh--files-get-trees repo branch))
       )
  (if (eq (car response) 0)
     (delete-dups (sort (consult-gh--files-table-to-list (consult-gh--api-json-to-table (cadr response) "tree") repo branch) 'string<))
    (message (cadr response)))))

(defun consult-gh--files-get-content (url)
  (let* ((response (consult-gh--api-get-json url))
        (content (if (eq (car response) 0) (consult-gh--api-json-to-table (cadr response) "content")
                   nil)))
    (if content
        (base64-decode-string content)
      "")))

(defun consult-gh--files-narrow (item)
"Create narrowing function for items in `consult-gh' by the first letter of the name of the user/organization."
  (if (stringp item)
    (cons (string-to-char (substring-no-properties item)) (substring-no-properties item))))

(defun consult-gh--files-browse-url-action ()
"Default action to run on selected itesm in `consult-gh'."
(lambda (cand)
  (let* ((path (substring-no-properties (get-text-property 0 ':path cand)))
        (repo (substring-no-properties (get-text-property 0 ':repo cand)))
        (branch (substring-no-properties (get-text-property 0 ':branch cand)))
        (url (concat (string-trim (consult-gh--command-to-string "browse" "--repo" repo "--no-browser")) "/blob/" branch "HEAD/" path)))
        (browse-url url))))

(defun consult-gh--make-source-from-branches (repo)
"Create a source for consult from contents of a repo to use in `consult-gh-browse-repo'."
                  `(;;:narrow ,(consult-gh--files-narrow repo)
                    :category 'consult-gh
                    :items  ,(consult-gh--files-branches-list-items repo)
                    :face 'consult-gh-default-face
                    :action ,(funcall consult-gh-file-action)
                    :annotate ,(consult-gh--files-annotate)
                    :state ,(and consult-gh-show-preview #'consult-gh--files-preview)
                    :default t
                    :history t
                    :sort t
                    ))

(defun consult-gh--files-view (repo path url &optional no-select tempdir buffer)
  "Default action to run on selected item in `consult-gh'."
  (let* ((tempdir (or tempdir consult-gh-tempdir))
         (prefix (concat (file-name-sans-extension  (file-name-nondirectory path))))
         (suffix (concat "." (file-name-extension path)))
         (temp-file (expand-file-name path tempdir))
         (text (consult-gh--files-get-content url)))

         (make-directory (file-name-directory temp-file) t)
         (with-temp-file temp-file
           (insert text)
           (set-buffer-file-coding-system 'raw-text)
           )
         (if no-select
             (find-file-noselect temp-file)
           (progn
             (find-file temp-file)
            (add-to-list 'consult-gh--preview-buffers-list (current-buffer)))
         )))

(defun consult-gh--files-view-action ()
  "Default action to run on selected item in `consult-gh'."
  (lambda (cand)
    (let* ((repo (get-text-property 0 ':repo cand))
           (path (get-text-property 0 ':path cand))
           (url (get-text-property 0 ':url cand))
           (file-p (or (file-name-extension path) (get-text-property 0 ':size cand))))
      (if file-p
          (consult-gh--files-view repo path url)
      ))))

(defun consult-gh--files-save-file-action ()
(lambda (cand)
    (let* ((repo (get-text-property 0 ':repo cand))
           (path (get-text-property 0 ':path cand))
           (url (get-text-property 0 ':url cand))
           (file-p (or (file-name-extension path) (get-text-property 0 ':size cand)))
           (filename (and file-p (file-name-nondirectory path)))
           (buffer (and file-p (consult-gh--files-view repo path url t))))
    (if file-p
    (save-mark-and-excursion
      (save-restriction
        (with-current-buffer buffer
          (write-file (read-file-name "Save As: " consult-gh-default-save-directory filename nil filename) t)
        )
        ))))))

(defun consult-gh--files-group (cand transform)
"Group the list of item in `consult-gh' by the name of the user"
  (let ((name (concat (get-text-property 0 ':repo cand) "[@" (get-text-property 0 ':branch cand) "]")))
           (if transform (substring cand) name)))

(defun consult-gh--files-preview ()
  (lambda (action cand)
    (let* ((preview (consult--buffer-preview))
           )
      (pcase action
        ('preview
         (if cand
             (let* ((repo (get-text-property 0 ':repo cand))
                    (path (get-text-property 0 ':path cand))
                    (branch (get-text-property 0 ':branch cand))
                    (url (get-text-property 0 ':url cand))
                    (file-p (or (file-name-extension path) (get-text-property 0 ':size cand)))
                    (tempdir (expand-file-name (concat repo "/" branch) consult-gh-tempdir))
                    (prefix (concat (file-name-sans-extension  (file-name-nondirectory path))))
                    (suffix (concat "." (file-name-extension path)))
                    (temp-file (expand-file-name path tempdir))
                    (_ (and file-p (make-directory (file-name-directory temp-file) t)))
                    (text (and file-p (consult-gh--files-get-content url)))
                    (_ (and file-p (with-temp-file temp-file (insert text) (set-buffer-file-coding-system 'raw-text)
                                                   )))
                    (buffer (or (and file-p (with-temp-buffer (find-file-noselect temp-file t))) nil)))
               (add-to-list 'consult-gh--preview-buffers-list buffer)
               (funcall preview action
                        (and
                         cand
                         buffer
                         ))) ()))
        ))))

(defun consult-gh--files-annotate ()
"Annotate each repo in `consult-gh' by user, visibility and date."
(lambda (cand)
  (if-let* ((size (get-text-property 0 :size cand))
            (size (format "%s Bytes" size)))
      (progn
        (setq size (propertize size 'face 'consult-gh-visibility-face))
        (format "\t%s" size)
     )
   nil)
  ))

(defun consult-gh--repo-list (org)
"Get a list of repos of \"organization\" and format each as a text with properties to pass to consult."
  (let* ((maxnum (format "%s" consult-gh--default-maxnum))
         (repolist  (or (consult-gh--command-to-string "repo" "list" org "--limit" maxnum) ""))
         (repos (mapcar (lambda (s) (string-split s "\t")) (split-string repolist "\n"))))

    (remove "" (mapcar (lambda (src) (propertize (car src) ':repo (car src) ':user (car (string-split (car src) "\/")) ':description (cadr src) ':visible (cadr (cdr src)) ':version (cadr (cdr (cdr src))))) repos)))
    )

(defun consult-gh--repo-browse-url-action ()
"Default action to run on selected itesm in `consult-gh'."
(lambda (cand)
  (let* ((response (consult-gh--call-process "browse" "--repo" (substring-no-properties cand) "--no-browser"))
        (url (string-trim (cadr response))))
    (if (eq (car response) 0)
        (browse-url url)
      (message url))
)))

(defun consult-gh--repo-view (repo &optional buffer)
  "Default action to run on selected item in `consult-gh'."
  (let ((buffer (or buffer (get-buffer-create consult-gh-preview-buffer-name)))
        (text (cadr (consult-gh--call-process "repo" "view" repo))))
    (with-current-buffer buffer
      (erase-buffer)
      (insert text)
      (goto-char (point-min-marker))
      (pcase consult-gh-preview-buffer-mode
        ('markdown-mode
         (if (featurep 'markdown-mode)
             (progn
             (require 'markdown-mode)
             (markdown-mode)
             (markdown-display-inline-images))
             (message "markdown-mode not available")))
        ('org-mode
         (let ((org-display-remote-inline-images 'download))
         (consult-gh--markdown-to-org buffer)
         ))
        (_ ()))
      )
    ))


(defun consult-gh--repo-view-action ()
  "Default action to run on selected item in `consult-gh'."
  (lambda (cand)
    (let* ((repo (substring-no-properties cand))
          (buffername (concat (string-trim consult-gh-preview-buffer-name "" "*") ":" repo "*")))
      (consult-gh--repo-view repo)
      (switch-to-buffer (get-buffer-create consult-gh-preview-buffer-name))
      (rename-buffer buffername t)
      )))

(defun consult-gh--repo-browse-files-action ()
  "Default action to run on selected item in `consult-gh'."
  (lambda (cand)
    (let* ((repo (get-text-property 0 ':repo cand)))
      (consult-gh-browse-repo-files (list repo))
      )))

(defun consult-gh--repo-clone (repo targetdir name)
"Clone the repo to targetdir/name directory. It uses \"gh clone repo ...\"."
  (consult-gh--command-to-string "repo" "clone" (format "%s" repo) (expand-file-name name targetdir))
  (message (format "repo %s was cloned to %s" (propertize repo 'face 'font-lock-keyword-face) (propertize (expand-file-name name targetdir) 'face 'font-lock-type-face))))


(defun consult-gh-repo-clone (&optional repo targetdir name)
"Interactively clone the repo to targetdir/name directory after confirming names and dir. It uses \"gh clone repo ...\"."
  (interactive)
  (let ((repo (read-string "repo: " repo))
        (targetdir (read-directory-name "target directory: " targetdir))
        (name (read-string "name: " name))
        )
  (consult-gh--repo-clone repo targetdir name)
    ))

(defun consult-gh--repo-clone-action ()
"action function for cloning the repo that can be used in conslt-gh source."
  (lambda (cand)
    (let* ((reponame  (consult-gh--output-cleanup (string-trim (substring-no-properties cand))))
         (package (car (last (split-string reponame "\/"))))
         )
    (if consult-gh-confirm-before-clone
        (consult-gh-repo-clone reponame consult-gh-default-clone-directory package)
      (consult-gh--repo-clone reponame consult-gh-default-clone-directory package))
    )))

(defun consult-gh--repo-fork (repo &rest args)
"Fork the repo to user's account (login on gh). It uses \"gh fork repo ...\"."
  (consult-gh--command-to-string "repo" "fork" (format "%s" repo) )
  (message (format "repo %s was forked" (propertize repo 'face 'font-lock-keyword-face))))

(defun consult-gh-repo-fork (&optional repo name &rest args)
"Interactively Fork the repo to user's account (login on gh) after confirming name. It uses \"gh fork repo ...\"."
  (interactive)
  (let* ((repo (read-string "repo: " repo))
        (package (car (last (split-string repo "\/"))))
        (name (read-string "name: " package)))
  (consult-gh--repo-fork repo  "--fork-name" name args)
    ))

(defun consult-gh--repo-fork-action ()
"action function for forking the repo that can be used in conslt-gh source."
  (lambda (cand)
     (let* ((reponame  (consult-gh--output-cleanup (string-trim (substring-no-properties cand)))))
      (consult-gh--repo-fork reponame)
    )))

(defun consult-gh--repo-group (cand transform)
"Group the list of item in `consult-gh' by the name of the user"
  (let ((name (car (string-split (substring cand) "\/"))))
           (if transform (substring cand) name)))

(defun consult-gh--repo-preview ()
  (lambda (action cand)
    (let ((preview (consult--buffer-preview)))
      (if cand
          (pcase action
            ('preview
             (let ((repo (substring-no-properties cand))
                   (buffer (get-buffer-create consult-gh-preview-buffer-name)))
               (add-to-list 'consult-gh--preview-buffers-list buffer)
               (consult-gh--repo-view repo buffer)
               (funcall preview action
                        (and
                         cand
                         buffer
                         )
                        ))
             )
            )
        ))))

(defun consult-gh--repo-narrow (item)
"Create narrowing function for items in `consult-gh' by the first letter of the name of the user/organization."
  (if (stringp item)
    (cons (string-to-char (substring-no-properties item)) (substring-no-properties item))))

(defun consult-gh--repo-annotate ()
"Annotate each repo in `consult-gh' by user, visibility and date."
(lambda (cand)
  (if-let ((user (format "%s" (get-text-property 0 :user cand)))
         (visible (format "%s" (get-text-property 0 :visible cand)))
         (date (format "%s" (get-text-property 0 :version cand))))

      (progn
        (setq user (propertize user 'face 'consult-gh-user-face)
              visible (propertize visible 'face 'consult-gh-visibility-face)
              date (propertize date 'face 'consult-gh-date-face))
        (format "%s\t%s\t%s" user visible date)
     )
    nil)
))

(defun consult-gh--search-repos (repo)
"Search for repos with \"gh search repos\" and return a list of items each formatted with properties to pass to consult."
  (let* ((maxnum (format "%s" consult-gh--default-maxnum))
         (repolist  (or (consult-gh--command-to-string "search" "repos" repo "--limit" maxnum) ""))
         (repos (mapcar (lambda (s) (string-split s "\t")) (split-string repolist "\n"))))
    (remove "" (mapcar (lambda (src) (propertize (car src) ':repo (car src) ':user (car (string-split (car src) "\/")) ':description (cadr src) ':visible (cadr (cdr src)) ':version (cadr (cdr (cdr src))))) repos)))
    )

(defun consult-gh--issue-list (repo)
"search issues of a repo with \"gh issue list\" and return a list of items for viewing."
  (let* ((maxnum (format "%s" consult-gh--default-maxnum))
         (issueslist  (or (consult-gh--command-to-string "issue" "--repo" repo "list" "--limit" maxnum) ""))
         (issues (mapcar (lambda (s) (string-split s "\t")) (split-string issueslist "\n"))))
    (remove ":" (remove "" (mapcar (lambda (src) (propertize (concat (car src) ":" (cadr (cdr src))) ':issue (string-trim (car src) "#") ':repo repo ':status (cadr src) ':description (cadr (cdr src)) ':tags (cadr (cdr (cdr src))) ':date (cadr (cdr (cdr (cdr src)))))) issues))
   ))
    )

(defun consult-gh--issue-browse-url-action ()
"Default action to run on selected itesm in `consult-gh'."
(lambda (cand)
  (consult-gh--call-process "issue" "view" "--repo" (substring-no-properties (get-text-property 0 :repo cand))  "--web" (substring-no-properties (get-text-property 0 :issue cand)))
  ))

(defun consult-gh--issue-view (repo issue &optional buffer)
  "Default action to run on selected item in `consult-gh'."
  (let ((buffer (or buffer (get-buffer-create consult-gh-preview-buffer-name)))
        (text (cadr (consult-gh--call-process "issue" "--repo" repo "view" issue))))
    (with-current-buffer buffer
      (erase-buffer)
      (insert text)
      (goto-char (point-min-marker))
      (pcase consult-gh-preview-buffer-mode
        ('markdown-mode
         (if (featurep 'markdown-mode)
             (progn
             (markdown-mode)
             (markdown-display-inline-images))
             (message "markdown-mode not available")))
        ('org-mode
         (let ((org-display-remote-inline-images 'download))
         (consult-gh--markdown-to-org buffer)
         ))
        (_ ()))
      )
    ))

(defun consult-gh--issue-view-action ()
  "Default action to run on selected item in `consult-gh'."
  (lambda (cand)
    (let* ((repo (substring (get-text-property 0 :repo cand)))
          (issue (substring (get-text-property 0 :issue cand)))
          (buffername (concat (string-trim consult-gh-preview-buffer-name "" "*") ":" repo "/issues/" issue "*")))
      (consult-gh--issue-view repo issue)
      (switch-to-buffer (get-buffer-create consult-gh-preview-buffer-name))
      (rename-buffer buffername t)
      )))

(defun consult-gh--issue-preview ()
  (lambda (action cand)
    (let ((preview (consult--buffer-preview)))
      (if cand
          (pcase action
            ('preview
             (let ((repo (substring (get-text-property 0 :repo cand)))
                   (issue (substring (get-text-property 0 :issue cand)))
                   (buffer (get-buffer-create consult-gh-preview-buffer-name)))
               (add-to-list 'consult-gh--preview-buffers-list buffer)
               (consult-gh--issue-view repo issue buffer)
               (funcall preview action
                        (and
                         cand
                         buffer
                         )
                        ))
             )
            )
        ))))

(defun consult-gh--issue-group (cand transform)
"Group the list of issues in a repo by the status of the issues"
(let ((name (substring (get-text-property 0 :status cand))))
           (if transform (substring cand) name)))

(defun consult-gh--issue-narrow (item)
"Create narrowing function for issues in a repo by the status of the issue"
    (cons (string-to-char (substring-no-properties item)) (substring-no-properties item)))

(defun consult-gh--issue-annotate ()
"Annotate each issue by description, status, repo and date."
(lambda (cand)
  ;; (format "%s" cand)
  (if-let ((repo (format "%s" (get-text-property 0 :repo cand)))
         (status (format "%s" (get-text-property 0 :status cand)))
         (tags (format "%s" (get-text-property 0 :tags cand)))
         (date (format "%s" (get-text-property 0 :date cand))))
      (progn
        (setq status (propertize status 'face 'consult-gh-user-face)
              tags (propertize tags 'face 'consult-gh-visibility-face)
              date (propertize date 'face 'consult-gh-date-face))
        (format "%s\t%s\t%s" status tags date)
     )
    nil)
))



(defun consult-gh--make-source-from-org  (org)
"Create a source for consult from the repos of the organization to use in `consult-gh-orgs'."
                  `(:narrow ,(consult-gh--repo-narrow org)
                    :category 'consult-gh
                    :items  ,(consult-gh--repo-list org)
                    :face 'consult-gh-default-face
                    :action ,(funcall consult-gh-repo-action)
                    :annotate ,(consult-gh--repo-annotate)
                    :state ,(and consult-gh-show-preview #'consult-gh--repo-preview)
                    :defualt t
                    :history t
                    :sort t
                    ))

(defun consult-gh--make-source-from-search-repo  (repo)
"Create a source for consult from the search results for repo to use in `consult-gh-search-repos'."
                  `(:narrow ,(consult-gh--repo-narrow repo)
                    :category 'consult-gh
                    :items  ,(consult-gh--search-repos repo)
                    :face 'consult-gh-default-face
                    :action ,(funcall consult-gh-repo-action)
                    :annotate ,(consult-gh--repo-annotate)
                    :state ,(and consult-gh-show-preview #'consult-gh--repo-preview)
                    :default t
                    :history t
                    :sort t
                    ))

(defun consult-gh--make-source-from-issues (repo)
"Create a source for consult from the repos of the organization to use in `consult-gh-orgs'."
                  `(;;:narrow ,(consult-gh--repo-narrow org)
                    :category 'consult-gh
                    :items  ,(consult-gh--issue-list repo)
                    :face 'consult-gh-default-face
                    :action ,(funcall consult-gh-issue-action)
                    :annotate ,(consult-gh--issue-annotate)
                    :state ,(and consult-gh-show-preview #'consult-gh--issue-preview)
                    :default t
                    :history t
                    :sort t
                    ))

(defun consult-gh--make-source-from-files  (repo &optional branch)
"Create a source for consult from contents of a repo to use in `consult-gh-browse-repo'."
                  `(:narrow ,(consult-gh--files-narrow repo)
                    :category 'consult-files
                    :items  ,(consult-gh--files-list-items repo branch)
                    :face 'consult-gh-default-face
                    :action ,(funcall consult-gh-file-action)
                    :annotate ,(consult-gh--files-annotate)
                    :state ,(and consult-gh-show-preview #'consult-gh--files-preview)
                    :default t
                    :history t
                    :sort t
                    ))

(defun consult-gh-orgs (&optional orgs)
"Get a list of organizations from the user and provide their repos."
  (interactive
   (let* ((crm-separator consult-gh-crm-separator)
         (candidates (or (delete-dups (append consult-gh-default-orgs-list consult-gh--known-orgs-list)) (list))))
   (list (delete-dups (completing-read-multiple "Search GitHub Users/Organization: " candidates nil nil nil 'consult-gh--org-history nil t)))))

  (let ((candidates (consult--slow-operation "Collecting Repos ..." (mapcar #'consult-gh--make-source-from-org orgs))))
    (if (not (member nil (mapcar (lambda (cand) (plist-get cand :items)) candidates)))
      (progn
          (setq consult-gh--known-orgs-list (append consult-gh--known-orgs-list orgs))
          (consult--multi candidates
                    :prompt "Select User/Organization: "
                    :require-match nil
                    :sort t
                    :group #'consult-gh--repo-group
                    :history 'consult-gh--repos-history
                    :category 'consult-gh
                    :sort t
                    )))))

(defun consult-gh-default-repos ()
"Show the repos from default organizaitons."
  (interactive)
(consult-gh-orgs consult-gh-default-orgs-list))

(defun consult-gh-search-repos (&optional repos)

"Get a list of repos from the user and return the results in `consult-gh' menu by runing \"gh search repos\"."
  (interactive
   (let* ((crm-separator consult-gh-crm-separator)
         (candidates (or (delete-dups consult-gh--known-repos-list) (list))))
   (list (delete-dups (completing-read-multiple "Search GitHub Repositories: " candidates nil nil nil nil nil t)))))
  (let ((candidates (consult--slow-operation "Collecting Repos ..." (mapcar #'consult-gh--make-source-from-search-repo repos))))
    (if (not (member nil (mapcar (lambda (cand) (plist-get cand :items)) candidates)))
      (progn
          (setq consult-gh--known-repos-list (append consult-gh--known-repos-list repos))
          (consult--multi candidates
                    :prompt "Select Repositories(s): "
                    :require-match t
                    :sort nil
                    :group #'consult-gh--repo-group
                    :history 'consult-gh--repos-history
                    :category 'consult-gh
                    :sort t
                    ))
      (message (concat "consult-gh: " (propertize "no repositories matched your search!" 'face 'warning))))))

(defun consult-gh-issue-list (&optional repos)
"Get a list of repos from the user and return the results in `consult-gh' menu by runing \"gh search repos\"."
  (interactive
   (let* ((crm-separator consult-gh-crm-separator)
         (candidates (or (delete-dups consult-gh--known-repos-list) (list))))
   (list (delete-dups (completing-read-multiple "Search GitHub Repositories: " candidates nil nil nil nil nil t)))))
  (let ((candidates (consult--slow-operation "Collecting Issues ..." (mapcar #'consult-gh--make-source-from-issues repos))))
    (if (not (member nil (mapcar (lambda (cand) (plist-get cand :items)) candidates)))
      (progn
          (setq consult-gh--known-repos-list (append consult-gh--known-repos-list repos))
          (consult--multi candidates
                    :prompt "Select Issue(s): "
                    :require-match t
                    :sort t
                    :group #'consult-gh--issue-group
                    :preview-key 'any
                    :history 'consult-gh--issues-history
                    :category 'consult-gh
                    :sort t
                    )
          )
      (message (concat "consult-gh: " (propertize "no repositories matched your search!" 'face 'warning))))))

(defun consult-gh-browse-repo-files (&optional repos)

  "Get a list of repos from the user and return the results in `consult-gh' menu by runing \"gh search repos\"."
  (interactive
   (let* ((crm-separator consult-gh-crm-separator)
         (candidates (or (delete-dups consult-gh--known-repos-list) (list))))
     (list (completing-read-multiple "Select Repository(s): " candidates nil nil nil nil nil t))))
  (let ((branches (list)))
    (pcase consult-gh-default-branch-to-load
      ("ask"
    (if (y-or-n-p "Load Default HEAD branch?")
        (setq branches (mapcar (lambda (repo) (cons repo "HEAD")) repos))
      (setq branches (cl-loop for repo in repos
                              collect (cons repo (completing-read (concat "Select Branch for " (propertize (format "\"%s\"" repo) 'face 'consult-gh-default-face) ": ") (consult-gh--files-branches-list-items repo)))))))
      ('nil
        (setq branches (mapcar (lambda (repo) (cons repo "HEAD")) repos))
        )
      (_
        (setq branches (mapcar (lambda (repo) (cons repo (format "%s" consult-gh-default-branch-to-load))) repos))))
    (let ((consult-gh-tempdir (expand-file-name (make-temp-name "") consult-gh-tempdir))
          (candidates (consult--slow-operation "Collecting Contents ..." (mapcar (lambda (repo) (consult-gh--make-source-from-files repo (alist-get repo branches))) repos)))
          )
      (if (not (member nil (mapcar (lambda (cand) (plist-get cand :items)) candidates)))
          (progn
            (setq consult-gh--known-repos-list (append consult-gh--known-repos-list repos))
            (consult--multi candidates
                            :prompt "Select File: "
                            :require-match t
                            :sort t
                            :group #'consult-gh--files-group
                            :history 'consult-gh--repos-history
                            :category 'consult-gh-files
                            :sort t
                            ))
        (message (concat "consult-gh: " (propertize "no contents matched your repo!" 'face 'warning)))))))


;; (setq my:test '("a" "b" "c"))
;; (setq my:test2 (repeat "header" (length my:test)))


;; (let ((brnaches (list))
;;       (repos '("armindarvish/consult-gh" "minad/vertico")))
;;   (if (y-or-n-p "Load Default HEAD branch?")
;;       (setq branches (mapcar (lambda (repo) (cons repo "HEAD")) repos))
;;     (setq branches (cl-loop for repo in repos
;;                             collect (cons repo (completing-read "branch: " (consult-gh--files-branches-list-items repo))))))
;;   (alist-get (car repos) branches))

(provide 'consult-gh)

;;; filename ends here
