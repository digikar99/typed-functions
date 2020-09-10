(in-package typed-dispatch)

(defun get-type-list (arg-list &optional env)
  ;; TODO: Improve this
  (flet ((type-declared-p (var)
           (cdr (assoc 'type (nth-value 2 (variable-information var env))))))
    (let* ((undeclared-args ())
           (type-list
             (loop :for arg :in arg-list
                   :collect (cond ((symbolp arg)
                                   (unless (type-declared-p arg)
                                     (push arg undeclared-args))
                                   (variable-type arg env))
                                  ((constantp arg) (type-of arg))
                                  ((and (listp arg)
                                        (eq 'the (first arg)))
                                   (second arg))
                                  (t (signal 'compiler-note "Cannot optimize this case!"))))))
      (if undeclared-args
          (mapcar (lambda (arg)
                    (signal 'undeclared-type :var arg))
                  (nreverse undeclared-args))
          type-list))))

(defmacro define-typed-function (name untyped-lambda-list)
  "Define a function named NAME that can then be used for DEFUN-TYPED for specializing on ORDINARY and OPTIONAL argument types."
  (declare (type function-name       name)
           (type untyped-lambda-list untyped-lambda-list))
  ;; TODO: Handle the case of redefinition
  (let* ((lambda-list untyped-lambda-list)
         (processed-lambda-list (process-untyped-lambda-list untyped-lambda-list))
         (typed-args  (remove-untyped-args processed-lambda-list :typed nil))
         ;; TODO: Handle the case of parsed-args better
         ;; (parsed-args (parse-lambda-list   lambda-list :typed nil))
         )

    (register-typed-function-wrapper name lambda-list)
    `(progn
       (eval-when (:compile-toplevel)
         ;; Take this out of progn?
         ;; > Perhaps, keep it inside; helps macroexpanders know better what the macro is doing
         (register-typed-function-wrapper ',name ',lambda-list))
       
       (defun ,name ,processed-lambda-list
         (declare (ignorable ,@(loop :for arg :in typed-args
                                     :appending (etypecase arg
                                                  (symbol (list arg))
                                                  (list (list (first arg) (third arg)))))))
         ,(let ((typed-args  typed-args)
                (type-list-code nil)
                (arg-list-code  nil))
            (loop :for typed-arg := (first typed-args)
                  :while (and typed-arg (symbolp typed-arg))
                  :do (push `(type-of ,typed-arg) type-list-code)
                  :do (push typed-arg arg-list-code)
                  :do (setq typed-args (rest typed-args)))
            `(let ((type-list (list ,@type-list-code))
                   (arg-list  (list ,@arg-list-code)))
               ,@(when (and typed-args (listp (first typed-args)))
                   ;; some typed-args are still pending
                   ;; - these should be the &optional ones
                   (loop :for (typed-arg default argp) :in typed-args
                         :collect `(when ,argp
                                     (push (type-of ,typed-arg) type-list)
                                     (push ,typed-arg arg-list))))
               (nreversef type-list)
               (nreversef arg-list)
               (apply (nth-value 1 (retrieve-typed-function ',name type-list))
                      arg-list))))
       
       ;; (define-compiler-macro ,name (&whole form ,@lambda-list &environment env)
       ;;   (declare (ignorable ,@typed-args)) ; typed-args are a subset of lambda-list
       ;;   (if (eq (car form) ',name)
       ;;       (if (< 1 (policy-quality 'speed env)) ; optimize for speed
       ;;           (handler-case
       ;;               (let ((type-list (get-type-list (list ,@typed-args) env)))
       ;;                 (if (retrieve-typed-function-compiler-macro ',name type-list)
       ;;                     (funcall (retrieve-typed-function-compiler-macro ',name type-list)
       ;;                              form
       ;;                              env)
       ;;                     ;; TODO: Use some other declaration for inlining as well
       ;;                     ;; Optimized for speed and type information available
       ;;                     `((lambda ,@(subseq (nth-value 0 ; inline
       ;;                                          (retrieve-typed-function ',name type-list))
       ;;                                  2))
       ;;                       ,@(cdr form))))
       ;;             (condition (condition)
       ;;               (format t "~%~%; Unable to optimize ~D because:" form)
       ;;               (write-string
       ;;                (str:replace-all (string #\newline)
       ;;                                 (uiop:strcat #\newline #\; "  ")
       ;;                                 (format nil "~D" condition)))
       ;;               form))
       ;;           (let ((first-note-signalled-p nil))   ; not for speed
       ;;             (flet ((ensure-first-note-signalled ()
       ;;                      (unless first-note-signalled-p
       ;;                        (format t
       ;;                                "~%~%; While compiling ~D: "
       ;;                                form)
       ;;                        (setq first-note-signalled-p t))))
       ;;               (handler-case
       ;;                   (handler-bind ((undeclared-type
       ;;                                    (lambda (condition)
       ;;                                      (ensure-first-note-signalled)
       ;;                                      (write-string
       ;;                                       (str:replace-all (string #\newline)
       ;;                                                        (uiop:strcat #\newline #\; "   ")
       ;;                                                        (format nil "~D" condition))))))
       ;;                     (let ((type-list (get-type-list (list ,@typed-args) env)))
       ;;                       (retrieve-typed-function ',name type-list)))
       ;;                 (error (condition)
       ;;                   (ensure-first-note-signalled)
       ;;                   (write-string
       ;;                    (str:replace-all (string #\newline)
       ;;                                     (uiop:strcat #\newline #\; "   ")
       ;;                                     (format nil "~D" condition))))))
       ;;             form))
       ;;       (progn
       ;;         (signal 'optimize-speed-note
       ;;                 :form form
       ;;                 :reason "COMPILER-MACRO of ~D can only optimize raw function calls."
       ;;                 :args (list ',name))
       ;;         form)))
       )))

(defmacro defun-typed (name typed-lambda-list &body body)
  "  Expects OPTIONAL args to be in the form ((A TYPE) DEFAULT-VALUE) or ((A TYPE) DEFAULT-VALUE AP)."
  (declare (type function-name name)
           (type typed-lambda-list typed-lambda-list))
  ;; TODO: Handle the case when NAME is not bound to a TYPED-FUNCTION
  (let* ((lambda-list        typed-lambda-list)
         (processed-lambda-list (process-typed-lambda-list lambda-list)
                              ;; (typed-function-wrapper-lambda-list
                              ;;  (retrieve-typed-function-wrapper name))
                              )
         (type-list          (nth-value 1 (remove-untyped-args lambda-list :typed t)))
         (lambda-body        `(named-lambda ,name ,processed-lambda-list ,@body)))
    ;; We need the LAMBDA-BODY due to compiler macros, and "objects of type FUNCTION can't be dumped into fasl files.
    `(progn
       (register-typed-function ',name ',type-list
                                ',lambda-body
                                (named-lambda ,name ,processed-lambda-list
                                  ,@body))
       ',name)))

(defmacro define-compiler-macro-typed (name type-list compiler-macro-lambda-list
                                       &body body)
  (declare (type function-name name)
           (type type-list type-list))
  ;; TODO: Handle the case when NAME is not bound to a TYPED-FUNCTION
  (let ((gensym (gensym)))
    `(progn
       (compile ',gensym (parse-compiler-macro ',gensym
                                               ',compiler-macro-lambda-list
                                               ',body))
       (register-typed-function-compiler-macro ',name ',type-list
                                               (symbol-function ',gensym))
       ',name)))


