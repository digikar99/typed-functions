(in-package adhoc-polymorphic-functions)

;; In this file, our main functions/macros are
;; - DEFINE-LAMBDA-LIST-HELPER
;; - LAMBDA-LIST-TYPE
;; - DEFUN-LAMBDA-LIST
;; - DEFUN-BODY
;; - LAMBDA-DECLARATIONS
;; - TYPE-LIST-APPLICABLE-P

;; THE BASICS ==================================================================

(define-constant +lambda-list-types+
    (list 'required
          'required-optional
          'required-key
          'required-untyped-rest)
  :test #'equalp)

(defun lambda-list-type-p (object)
  "Checks whhether the OBJECT is in +LAMBDA-LIST-TYPES+"
  (member object +lambda-list-types+))

(deftype lambda-list-type () `(satisfies lambda-list-type-p))

(5am:def-suite lambda-list :in :adhoc-polymorphic-functions)

(defun valid-parameter-name-p (name)
  (and (symbolp name)
       (not (constantp name))
       (not (member name lambda-list-keywords))))

(defun potential-type-of-lambda-list (lambda-list)
  ;; "potential" because it does not check the symbols
  (declare (type list lambda-list))
  (the lambda-list-type
       (let ((intersection (intersection lambda-list lambda-list-keywords)))
         ;; premature optimization and over-abstraction:/
         (cond ((null intersection)
                'required)
               ((and (car intersection) (null (cdr intersection)) ; length is 1
                     (member '&optional intersection))
                'required-optional)
               ((and (car intersection) (null (cdr intersection)) ; length is 1
                     (member '&key intersection))
                'required-key)
               ((and (car intersection) (null (cdr intersection)) ; length is 1
                     (member '&rest intersection))
                'required-untyped-rest)
               (t
                (error "Neither of ~A types" +lambda-list-types+))))))

(defvar *potential-type*)
(setf (documentation '*potential-type* 'variable)
      "POTENTIAL-TYPE of the LAMBDA-LIST of the typed function being compiled.
Bound inside the functions defined by POLYMORPHS::DEFINE-LAMBDA-LIST-HELPER")

(defvar *lambda-list*)
(setf (documentation '*lambda-list* 'variable)
      "LAMBDA-LIST of the typed function being compiled. Bound inside the functions
defined by POLYMORPHS::DEFINE-LAMBDA-LIST-HELPER")

(defvar *name*)
(setf (documentation '*name* 'variable)
      "NAME of the typed function being compiled. Bound inside DEFINE-POLYMORPH")

(defvar *lambda-list-typed-p*)
(setf (documentation '*lambda-list-typed-p* 'variable)
      "Is T if the *LAMBDA-LIST* being processed is to be treated as if it had type
specifiers. Bound inside the functions defined by POLYMORPHS::DEFINE-LAMBDA-LIST-HELPER")

(defmacro define-lambda-list-helper ((outer-name outer-documentation)
                                     (inner-name inner-documentation)
                                     &body action-form)
  "ACTION-FORM should be defined in terms of *POTENTIAL-TYPE* and *LAMBDA-LIST* variables."
  `(progn
     (defun ,outer-name (lambda-list &key typed)
       ,outer-documentation
       (declare (type list lambda-list))
       (let ((*potential-type*      (potential-type-of-lambda-list lambda-list))
             (*lambda-list*         lambda-list)
             (*lambda-list-typed-p* typed))
         (if (%lambda-list-type *potential-type* lambda-list)
             (progn ,@action-form)
             (error "LAMBDA-LIST ~A is neither of ~%  ~A" lambda-list +lambda-list-types+))))
     (defgeneric ,inner-name (potential-lambda-list-type lambda-list)
       (:documentation ,inner-documentation))
     ;; For better error reporting
     (defmethod ,inner-name ((type t) (lambda-list t))
       (assert (typep type 'lambda-list-type)
               ()
               "Expected POTENTIAL-LAMBDA-LIST-TYPE to be one of ~%  ~A~%but is ~A"
               +lambda-list-types+ type)
       (assert (typep lambda-list 'list)
               ()
               "Expected LAMBDA-LIST to be a LIST but is ~A"
               lambda-list)
       (error "No potential type found for LAMBDA-LIST ~A from amongst ~%  ~A"
              lambda-list +lambda-list-types+))))

;; LAMBDA-LIST-TYPE ============================================================

(define-lambda-list-helper
    (lambda-list-type  #.+lambda-list-type-doc+)
    (%lambda-list-type "Checks whether LAMBDA-LIST is of type POTENTIAL-LAMBDA-LIST-TYPE")
  *potential-type*)

(defun untyped-lambda-list-p (lambda-list)
  (ignore-errors (lambda-list-type lambda-list)))
(defun typed-lambda-list-p (lambda-list)
  (ignore-errors (lambda-list-type lambda-list :typed t)))
(deftype untyped-lambda-list ()
  "Examples:
  (a b)
  (a b &optional c)
Non-examples:
  ((a string))"
  `(satisfies untyped-lambda-list-p))
(deftype typed-lambda-list ()
  "Examples:
  ((a integer) (b integer))
  ((a integer) &optional ((b integer) 0 b-supplied-p))"
  `(satisfies typed-lambda-list-p))

;; DEFUN-LAMBDA-LIST ===========================================================

(define-lambda-list-helper
    (defun-lambda-list  #.+defun-lambda-list-doc+)
    (%defun-lambda-list #.+defun-lambda-list-doc-helper+)
  (%defun-lambda-list *potential-type* *lambda-list*))

(5am:def-suite defun-lambda-list :in lambda-list)

;; DEFUN-BODY ==================================================================

(define-lambda-list-helper
    (defun-body  #.+defun-body-doc+)
    (%defun-body #.+defun-body-doc-helper+)
  (let ((defun-lambda-list (%defun-lambda-list *potential-type* *lambda-list*)))
    (values (%defun-body *potential-type* defun-lambda-list)
            defun-lambda-list)))

;; SBCL-TRANSFORM-BODY-ARGS ====================================================

(define-lambda-list-helper
    (sbcl-transform-body-args #.+sbcl-transform-body-args-doc+)
    (%sbcl-transform-body-args #.+sbcl-transform-body-args-doc+)
  (progn
    (assert (typed-lambda-list-p *lambda-list*))
    (%sbcl-transform-body-args *potential-type* *lambda-list*)))

(def-test sbcl-transform-body-args (:suite lambda-list)
  (is (equalp '(a b nil) (sbcl-transform-body-args '((a number) (b string)) :typed t)))
  (is (equalp '(a b nil) (sbcl-transform-body-args '((a number) &optional ((b string) "hello"))
                                               :typed t)))
  (is (equalp '(a :b b nil) (sbcl-transform-body-args '((a number) &key ((b string) "hello"))
                                                  :typed t)))
  (is (equalp '(a args) (sbcl-transform-body-args '((a number) &rest args)
                                                  :typed t))))

;; LAMBDA-DECLARATIONS =========================================================

(define-lambda-list-helper
    (lambda-declarations  #.+lambda-declarations-doc+)
    (%lambda-declarations #.+lambda-declarations-doc+)
  (progn
    (assert (typed-lambda-list-p *lambda-list*))
    (%lambda-declarations *potential-type* *lambda-list*)))

;; TYPE-LIST-COMPATIBLE-P ======================================================

(defun type-list-compatible-p (type-list untyped-lambda-list)
  "Returns T if the given TYPE-LIST is compatible with the given UNTYPED-LAMBDA-LIST."
  (declare (type type-list                     type-list)
           (type untyped-lambda-list untyped-lambda-list))
  (let ((*lambda-list-typed-p* nil)
        (*potential-type* (potential-type-of-lambda-list untyped-lambda-list)))
    (if (%lambda-list-type *potential-type* untyped-lambda-list)
        (%type-list-compatible-p *potential-type* type-list untyped-lambda-list)
        (error "UNTYPED-LAMBDA-LIST ~A is neither of ~%  ~A" untyped-lambda-list
               +lambda-list-types+))))

(defgeneric %type-list-compatible-p
    (potential-lambda-list-type type-list untyped-lambda-list))

(defmethod %type-list-compatible-p ((type t)
                                    (type-list t)
                                    (untyped-lambda-list t))
  (assert (typep type 'lambda-list-type) nil
          "Expected LAMBDA-LIST-TYPE to be one of ~%  ~a~%but is ~a"
          +lambda-list-types+ type)
  (assert (typep type-list 'type-list) nil
          "Expected TYPE-LIST to be a TYPE-LIST but is ~a" type-list)
  (assert (typep untyped-lambda-list 'untyped-lambda-list) nil
                "Expected ~A to be a UNTYPED-LAMBDA-LIST" untyped-lambda-list)
  (error "This code shouldn't have reached here; perhaps file a bug report!"))

(def-test type-list-compatible-p (:suite lambda-list)
  (5am:is-true  (type-list-compatible-p '(string string) '(c d)))
  (5am:is-false (type-list-compatible-p '(string) '(c d)))
  (5am:is-true  (type-list-compatible-p '(string number &optional t) '(c d &optional e)))
  (5am:is-false (type-list-compatible-p '(number) '(c d &optional d)))
  (5am:is-true  (type-list-compatible-p '(string &key (:d number) (:e string)) '(c &key d e)))
  (5am:is-false (type-list-compatible-p '(string &key (:d number)) '(c &key d e)))
  (5am:is-true  (type-list-compatible-p '(string) '(c &rest e)))
  (5am:is-false (type-list-compatible-p '(number string) '(c &rest e))))

;; APPLICABLE-P-FUNCTION =======================================================

(defgeneric applicable-p-function (lambda-list-type type-list))

(defmethod applicable-p-function ((type t) (type-list t))
  (assert (typep type 'lambda-list-type) nil
          "Expected LAMBDA-LIST-TYPE to be one of ~%  ~a~%but is ~a"
          +lambda-list-types+ type)
  (assert (typep type-list 'type-list) nil
          "Expected TYPE-LIST to be a TYPE-LIST but is ~a" type-list)
  (error "This code shouldn't have reached here; perhaps file a bug report!"))

;; TYPE-LIST-INTERSECT-P =======================================================

(defun type-list-intersect-p (type-list-1 type-list-2)
  #.+type-list-intersect-p+
  (declare (type type-list type-list-1 type-list-2))
  (let ((*lambda-list-typed-p* nil)
        (*potential-type* (potential-type-of-lambda-list type-list-1)))
    (and (length= type-list-1 type-list-2)
         (%type-list-intersect-p *potential-type* type-list-1 type-list-2))))

(defgeneric %type-list-intersect-p (type type-list-1 type-list-2)
  (:documentation #.+type-list-intersect-p+))

(5am:def-suite type-list-intersect-p :in lambda-list)

;; MISCELLANEOUS ===============================================================

(defun type-intersect-p (type-1 type-2)
  ;; TODO: DOes not actually handle intersection
  (or (subtypep type-1 type-2)
      (subtypep type-2 type-1)))

(defvar *compiler-macro-expanding-p* nil
  "Bound to T inside the DEFINE-COMPILER-MACRO defined in DEFINE-POLYMORPH")
(defvar *environment*)
(setf (documentation '*environment* 'variable)
      "Bound inside the DEFINE-COMPILER-MACRO defined in DEFINE-POLYMORPH for
use by functions like TYPE-LIST-APPLICABLE-P")

(defun our-typep (arg type)
  (assert *compiler-macro-expanding-p*)
  (when (and (symbolp arg)              ; type-declared-p
             (not (cdr (assoc 'type
                              (nth-value 2
                                         (variable-information arg *environment*))))))
    (signal 'form-type-failure :form arg))
  (subtypep (form-type arg *environment*) type *environment*))

(def-test our-typep (:suite :adhoc-polymorphic-functions)
  (macrolet ((with-compile-time (&rest body)
               `(let ((*compiler-macro-expanding-p* t)
                      (*environment* nil))
                  ,@body)))
    (5am:is-true (with-compile-time (our-typep 5 '(member 5))))
    (5am:is-true (with-compile-time (our-typep 5 '(eql 5))))
    (5am:is-true (with-compile-time (our-typep ''symbol '(eql symbol))))
    (5am:is-true (with-compile-time (our-typep ''symbol '(member symbol))))
    (5am:is-true (with-compile-time (our-typep ''symbol '(or fixnum (member symbol)))))))

(defun type->param (type-specifier &optional type)
  (if (member type-specifier lambda-list-keywords)
      type-specifier
      (case type
        (&key (list (intern (symbol-name (first type-specifier))
                            :adhoc-polymorphic-functions)
                    nil
                    (gensym (concatenate 'string
                                         (write-to-string (first type-specifier))
                                         "-SUPPLIED-P"))))
        (&optional (list (gensym (write-to-string type-specifier))
                         nil
                         (gensym (concatenate 'string
                                              (write-to-string type-specifier)
                                              "-SUPPLIED-P"))))
        (t (gensym (write-to-string type-specifier))))))
