;;; ardd.el --- Share Mathbook evaluation through SLY -*- lexical-binding: t; -*-

(require 'cl-lib)
(require 'sly)
(require 'json)
(require 'comint)

(defvar mathbook-ardd-connection nil
  "SLY connection explicitly selected for agent evaluations.")
(defvar mathbook-ardd-busy nil)
(defconst mathbook-ardd-buffer "*Mathbook ARDD*")
(defvar mathbook-ardd-mailbox-directory
  (expand-file-name ".ardd/"
                    (file-name-directory
                     (directory-file-name
                      (file-name-directory (or load-file-name buffer-file-name)))))
  "Project-local request directory, also used by the ./ardd command.")
(defvar mathbook-ardd-mailbox-timer nil)
(defvar mathbook-ardd-mailbox-polling nil)

(defun mathbook-ardd-stop-mailbox ()
  "Stop accepting agent requests through project files."
  (interactive)
  (when (timerp mathbook-ardd-mailbox-timer)
    (cancel-timer mathbook-ardd-mailbox-timer))
  (setq mathbook-ardd-mailbox-timer nil))

(defun mathbook-ardd-start-mailbox ()
  "Accept agent requests through files, without an agent socket connection."
  (interactive)
  (mathbook-ardd-stop-mailbox)
  (dolist (directory '("requests" "results"))
    (make-directory (expand-file-name directory mathbook-ardd-mailbox-directory) t))
  (setq mathbook-ardd-mailbox-timer
        (run-with-timer 0.1 0.1 #'mathbook-ardd--poll)))

(defun mathbook-ardd--write-reply (id reply)
  (let* ((directory (expand-file-name "results/" mathbook-ardd-mailbox-directory))
         (temporary (make-temp-file (expand-file-name ".reply-" directory))))
    (unwind-protect
        (progn
          (let ((coding-system-for-write 'utf-8))
            (write-region (json-encode reply) nil temporary nil 'silent))
          (rename-file temporary (expand-file-name (concat id ".json") directory) t))
      (when (file-exists-p temporary) (delete-file temporary)))))

(defun mathbook-ardd--poll ()
  "Claim and evaluate at most one file request; never re-enter a running request."
  (unless (or mathbook-ardd-mailbox-polling mathbook-ardd-busy)
    (let* ((mathbook-ardd-mailbox-polling t)
           (directory (expand-file-name "requests/" mathbook-ardd-mailbox-directory))
           (file (car (directory-files directory t "\\`[0-9a-f]\\{32\\}\\.json\\'"))))
      (when file
        (let* ((id (file-name-base file))
               (claimed (concat file ".running")))
          (condition-case condition
              (progn
                ;; Renaming is the point at which the request has started.
                ;; If the CLI cancelled first, this fails and nothing executes.
                (rename-file file claimed)
                (let* ((json-object-type 'alist)
                       (request (json-read-file claimed))
                       (source (alist-get 'source request))
                       (expiry (alist-get 'expires_at request)))
                  (unless (and (stringp source) (numberp expiry))
                    (error "Invalid ARDD request"))
                  (when (<= expiry (float-time))
                    (error "ARDD request expired before evaluation; cancelled"))
                  (mathbook-ardd--write-reply
                   id `((ok . t) (result . ,(mathbook-ardd-eval source))))))
            ((error quit)
             (when (file-exists-p claimed)
               (mathbook-ardd--write-reply
                id `((ok . :json-false)
                     (error . ,(error-message-string condition)))))))
          (when (file-exists-p claimed) (delete-file claimed)))))))

(defun mathbook-ardd--append (text)
  (with-current-buffer (get-buffer-create mathbook-ardd-buffer)
    (unless (derived-mode-p 'special-mode) (special-mode))
    (let ((inhibit-read-only t))
      (goto-char (point-max))
      (insert text))))

(defun mathbook-ardd--selected-repl-p ()
  "Whether the current buffer is a REPL on the pinned Mathbook connection."
  (and mathbook-ardd-connection
       (derived-mode-p 'sly-mrepl-mode)
       (eq sly-buffer-connection mathbook-ardd-connection)))

(defun mathbook-ardd--mirror-input (source)
  "Record ordinary REPL input without evaluating it a second time."
  (when (and (mathbook-ardd--selected-repl-p) (not mathbook-ardd-busy))
    (mathbook-ardd--append
     (format "\n[%s human/SLY]\n%s%s" (format-time-string "%H:%M:%S")
             source (if (string-suffix-p "\n" source) "" "\n")))))

(defun mathbook-ardd--mirror-output (text)
  "Mirror SLY's printed output, preserving the filter's original TEXT."
  (when (and (mathbook-ardd--selected-repl-p) (not mathbook-ardd-busy))
    (mathbook-ardd--append (substring-no-properties text)))
  text)

(defun mathbook-ardd--mirror-result (text)
  "Mirror comint results and debugger notes, excluding SLY's prompts.
SLY sends printed output through its separate output filter instead."
  (when (and (mathbook-ardd--selected-repl-p) (not mathbook-ardd-busy)
             (> (length text) 0)
             (not (get-text-property 0 'sly-mrepl--prompt text)))
    (mathbook-ardd--append
     (if (get-text-property 0 'sly-mrepl--result text)
         (concat "=> " (substring-no-properties text) "\n")
       (substring-no-properties text)))))

(defun mathbook-ardd--setup-repl ()
  "Mirror the selected REPL through buffer-local input and output hooks."
  (when (derived-mode-p 'sly-mrepl-mode)
    (dolist (entry '((comint-input-filter-functions . mathbook-ardd--mirror-input)
                     (comint-output-filter-functions . mathbook-ardd--mirror-result)
                     (sly-mrepl-output-filter-functions . mathbook-ardd--mirror-output)))
      (if (mathbook-ardd--selected-repl-p)
          (add-hook (car entry) (cdr entry) nil t)
        (remove-hook (car entry) (cdr entry) t)))))

(defun mathbook-ardd--refresh-repls ()
  (dolist (buffer (buffer-list))
    (with-current-buffer buffer (mathbook-ardd--setup-repl))))

(defun mathbook-ardd-use-connection ()
  "Pin agent evaluations to the current SLY connection.
Run this in the REPL connected to ./dev-repl, not another Lisp."
  (interactive)
  (let* ((connection (sly-current-connection))
         (sly-dispatching-connection connection))
    (unless (and connection (process-live-p connection))
      (user-error "Connect to Mathbook with M-x sly-connect first"))
    (unless (sly-eval '(cl:and (cl:find-package "MATHBOOK-DEV")
                              (cl:getf
                               (cl:funcall (cl:intern "STATUS" "MATHBOOK-DEV"))
                               :running))
                      "CL-USER")
      (user-error "This Lisp was not started with ./dev-repl"))
    (setq mathbook-ardd-connection connection)
    (mathbook-ardd--refresh-repls)
    (mathbook-ardd--append
     (format "\nConnected: %s\n" (sly-connection-name connection)))
    (display-buffer mathbook-ardd-buffer)
    (mathbook-ardd-start-mailbox)
    (message "Mathbook ARDD is ready; SLY REPL input and output are mirrored")))

(defun mathbook-ardd-eval (source &optional label)
  "Evaluate Common Lisp SOURCE via the selected SLY connection.
Record input, output, values and errors in `mathbook-ardd-buffer'.
Evaluations run serially on Mathbook's main thread between frames."
  (interactive (list (read-string "Mathbook Lisp: ") "human"))
  (unless (and mathbook-ardd-connection
               (process-live-p mathbook-ardd-connection))
    (user-error "Run M-x mathbook-ardd-use-connection in the Mathbook SLY REPL"))
  (when mathbook-ardd-busy
    (user-error "Another ARDD evaluation is in progress; wait for its result"))
  (let ((mathbook-ardd-busy t)
        (sly-dispatching-connection mathbook-ardd-connection))
    (mathbook-ardd--append
     (format "\n[%s %s]\n%s\n" (format-time-string "%H:%M:%S")
             (or label "agent") source))
    (condition-case condition
        (pcase (sly-eval `(mathbook-dev:eval-string ,source) "CL-USER")
          (`(:ok ,output ,values)
           (let ((result (concat output
                                 (if values
                                     (mapconcat (lambda (value) (concat "=> " value "\n"))
                                                values "")
                                   "=> ; no values\n"))))
             (mathbook-ardd--append result)
             result))
          (`(:error ,output ,message)
           (mathbook-ardd--append output)
           (error "%s" message))
          (other (error "Unexpected ARDD reply: %S" other)))
      ((error quit)
       (mathbook-ardd--append (format "ERROR: %s\n" (error-message-string condition)))
       (signal (car condition) (cdr condition))))))

(defun mathbook-ardd-eval-file (file)
  "Read FILE as UTF-8 source text and evaluate it in the live Lisp."
  (mathbook-ardd-eval
   (with-temp-buffer
     (let ((coding-system-for-read 'utf-8)) (insert-file-contents file))
     (buffer-string))))

(add-hook 'sly-mrepl-hook #'mathbook-ardd--setup-repl)
;; Also activate mirroring when this file is reloaded into an existing session.
(mathbook-ardd--refresh-repls)

(provide 'mathbook-ardd)
;;; ardd.el ends here
