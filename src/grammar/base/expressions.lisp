(cl:in-package #:parser.packrat.grammar.base)

;; TODO print-items
(exp:define-expression-class predicate (exp:single-sub-expression-mixin
                                        exp::value-environment-needing-mixin
                                        print-items:print-items-mixin)
  (predicate))

(exp:define-expression-class anything (exp::value-environment-needing-mixin)
  ())

(exp:define-expression-class terminal (exp::value-environment-needing-mixin
                                       print-items:print-items-mixin)
  (exp:value))

(defmethod print-items:print-items append ((object terminal-expression))
  `((:value ,(exp:value object) "~S")))

;;; Combinators

(exp:define-expression-class not (exp:single-sub-expression-mixin
                                  print-items:print-items-mixin)
  ())

(exp:define-expression-class and (exp:sub-expression-mixin
                                  print-items:print-items-mixin)
  ())

(exp:define-expression-class or (exp:sub-expression-mixin
                                 print-items:print-items-mixin)
  ())

(exp:define-expression-class compose (exp:sub-expression-mixin
                                      print-items:print-items-mixin)
  ())

;;; Constant

(exp:define-expression-class constant (print-items:print-items-mixin)
  (exp:value))

(defmethod print-items:print-items append ((object constant-expression))
  `((:value ,(exp:value object))))

;;; Variables

(defclass variable-reference-mixin ()
  ((variable :initarg :variable
             :type    symbol
             :reader  exp:variable)
   (mode     :reader  exp:mode
             :allocation :class))
  (:default-initargs
   :variable (more-conditions:missing-required-initarg 'variable-reference-mixin :variable)))

(defmethod print-items:print-items append ((object variable-reference-mixin))
  `((:variable ,(exp:variable object))))

(defmethod bp:node-initargs ((builder t) (node variable-reference-mixin))
  (list :variable (exp:variable node) :mode (exp:mode node)))

(defmethod exp:direct-variable-references ((grammar    t)
                                           (expression variable-reference-mixin)
                                           &key filter)
  (when (or (not filter) (funcall filter expression))
    (list expression)))

(defclass variable-write-mixin (variable-reference-mixin
                                exp:single-sub-expression-mixin
                                ; exp::value-environment-needing-mixin
                                )
  ((mode :allocation :class
         :initform :write)))

(exp:define-expression-class set (variable-write-mixin
                                  print-items:print-items-mixin)
  ())

(defmethod print-items:print-items append ((object set-expression))
  `((:arrow nil " ← " ((:after :variable)))))

(exp:define-expression-class push (variable-write-mixin
                                   print-items:print-items-mixin)
  ())

(defmethod print-items:print-items append ((object push-expression))
  `((:arrow nil " ←+ " ((:after :variable)))))

(defclass variable-reference #+TODO -expression (exp:expression
                              variable-reference-mixin
                              print-items:print-items-mixin)
  ((mode :allocation :class
         :initform :read)))

(defmethod bp:node-kind ((builder t) (node variable-reference))
  :variable-reference)

(exp:define-expression-class ignored (exp::value-environment-needing-mixin)
  ())

;;; Position

(exp:define-expression-class position ()
  ())

;;; Transform

(exp:define-expression-class transform (exp:single-sub-expression-mixin)
  (code))

;;; `rule-invocation'

(defclass rule-invocation-base (exp:sub-expression-mixin
                                print-items:print-items-mixin)
  ((sub-expressions :initarg  :arguments
                    :accessor arguments)))

(defmethod print-items:print-items append ((object rule-invocation-base))
  (let ((arguments (map 'list #'print-items:print-items (arguments object))))
    `((:sub-expression-count nil        "")
      (:open                 nil        "(")
      (:arguments            ,arguments "~{ ~/print-items:format-print-items/~}" ((:after :open)))
      (:close                nil        ")"                                      ((:after :arguments))))))

(defclass rule-invocation-expression (rule-invocation-base) ; TODO use define-expression-class
  ((grammar :initarg  :grammar
            :reader   grammar
            :initform nil)
   (rule    :initarg  :rule
            :reader   rule))
  (:default-initargs
   :rule (more-conditions:missing-required-initarg 'rule-invocation :rule)))

(defmethod print-items:print-items append ((object rule-invocation-expression))
  `((:rule ,(rule object) "~A" ((:after :open)
                                (:before :arguments)))))

(defmethod bp:node-kind ((builder t) (node rule-invocation-expression))
  :rule-invocation)

(defmethod bp:node-initargs ((builder t) (node rule-invocation-expression))
  (list :rule (rule node)))

(exp:define-expression-class next-rule-invocation (rule-invocation-base)
  ())

(defmethod print-items:print-items append ((object next-rule-invocation-expression))
  `((:rule nil "next-rule" ((:after :open) (:before :arguments)))))
