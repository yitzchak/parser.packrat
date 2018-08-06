(cl:in-package #:parser.packrat.grammar.sexp)

#+no (defmethod compile-expression ((grammar      sexp-grammar)
                                    (environment  value-environment)
                                    (expression   terminal-expression)
                                    (position     t)
                                    (success-cont function)
                                    (fail-cont    function))
       `(if (eql ,(value environment) ',(value expression))
            ,(funcall success-cont position)
            ,(funcall fail-cont position))
       #+old (let+ ((value (value expression)))
               (compile-bounds-test
                grammar environment position position
                (lambda (position)
                  (compile-access
                   grammar environment position
                   (lambda (current same)
                     (declare (ignore same))
                     `(if (eql ,current ',value)
                          ,(funcall success-cont current current)
                          ,(funcall fail-cont current)))))
                fail-cont)))

#+no (defmethod compile-expression :before ((grammar      sexp-grammar)
                                       (environment  t)
                                       (expression   exp:sequence-expression)
                                       (success-cont function)
                                       (fail-cont    function))
  (unless (typep environment '(or seq:list-environment seq:vector-environment))
    (error "not in list or vector environment")))

#+no (defmethod compile-expression ((grammar      sexp-grammar)
                               (environment  seq:list-environment)
                               (expression   exp:sequence-expression)
                               (success-cont function)
                               (failure-cont    function))
  (call-next-method))

;;; Structures

#+no (defmethod compile-expression ((grammar      sexp-grammar)
                               (environment  env:value-environment)
                               (expression   cons-expression)
                               (success-cont function)
                               (failure-cont function))
  (let+ (((&with-gensyms car-var cdr-var))
         (value (env:value environment)))
    `(if (consp ,value)
         (let ((,car-var (car ,value)))
           ,(compile-expression
             grammar (env:environment-carrying environment car-var) (car-expression expression)
             (lambda (new-environment)
               (declare (ignore new-environment))
               `(let ((,cdr-var (cdr ,value)))
                  ,(compile-expression
                    grammar (env:environment-carrying environment cdr-var) (cdr-expression expression)
                    success-cont failure-cont)))
             failure-cont))
         ,(funcall failure-cont environment))))

(defmethod compile-expression ((grammar      t)
                               (environment  env:environment)
                               (expression   structure-expression)
                               (success-cont function)
                               (failure-cont function))
  (let+ (((&accessors-r/o (type type*) readers sub-expressions) expression)
         (readers   (mapcar #'ensure-list readers)) ; TODO should not happen here
         (slot-vars (map 'list (compose #'gensym #'string #'first) readers))
         (value     (env:value environment))
         ((&labels+ slot ((&optional ((first-reader &rest first-args) '(nil)) &rest rest-readers)
                          (&optional first-expression                         &rest rest-expressions)
                          (&optional first-var                                &rest rest-vars)
                          slot-environment)
            (let+ (((&flet make-reader-args ()
                      (cond
                        ((not first-args)
                         (list value))
                        ((find :x first-args) ; TODO temp hack
                         (substitute value :x first-args))
                        (t
                         (list* value first-args)))))
                   ((&flet make-value-environment (value)
                      (env:environment-at
                             slot-environment (list :value value)
                             :class 'env:value-environment
                             :state '()))))
              (if first-reader
                  `(let ((,first-var (,first-reader ,@(make-reader-args))))
                     ,(compile-expression
                       grammar
                       #+old (env:environment-carrying environment first-var)
                       (make-value-environment first-var)
                       first-expression
                       (curry #'slot rest-readers rest-expressions rest-vars)
                       failure-cont))
                  (funcall success-cont (make-value-environment value)))))))
    (compile-expression
     grammar environment type
     (lambda (new-environment)
       `(if (typep ,value ,(env:value new-environment))
            ,(slot readers sub-expressions slot-vars environment)
            ,(funcall failure-cont environment)))
     failure-cont)))

;;; Casts

;; TODO similar to following method
(defmethod compile-expression ((grammar      t)
                               (environment  env:environment)
                               (expression   as-list-expression)
                               (success-cont function)
                               (failure-cont function))
  (let+ ((value (env:value environment))
         ((&flet call-with-value-environment (cont parent-environment)
            (funcall cont (env:environment-at
                           parent-environment (list :value value)
                           :class 'env:value-environment
                           :state '()))))
         (list-environment (env:environment-at
                            environment (list :tail value)
                            :class 'seq:list-environment
                            :state '())))
    `(if (typep ,value ',(target-type expression))
         ,(compile-expression
           grammar list-environment (sub-expression expression)
           (lambda (new-environment)
             (compile-expression
              grammar new-environment (make-instance 'seq::bounds-test-expression
                                                     :sub-expression (make-instance 'base::ignored-expression))
              (curry #'call-with-value-environment failure-cont)
              (curry #'call-with-value-environment success-cont)))
           (curry #'call-with-value-environment failure-cont))
         ,(funcall failure-cont environment))))

(defmethod compile-expression ((grammar      sexp-grammar)
                               (environment  seq:list-environment)
                               (expression   rest-expression)
                               (success-cont function)
                               (failure-cont function))
  (let+ (((&with-gensyms tail-var end-var))
         (rest-environment (env:environment-at
                            environment (list :value tail-var)
                            :class 'env:value-environment
                            :state '())))
    `(let ((,tail-var ,(seq:tail environment)))
       ,(compile-expression
         grammar rest-environment (exp:sub-expression expression)
         (lambda (new-environment)
           (let ((end-environment (env:environment-at
                                   new-environment (list :tail end-var)
                                   :class 'seq:list-environment
                                   :state '())))
             `(let ((,end-var nil))
                ,(funcall success-cont end-environment))))
         (lambda (new-environment)
           (declare (ignore new-environment))
           (funcall failure-cont environment))))))

(defmethod compile-expression ((grammar      sexp-grammar)
                               (environment  env:environment)
                               (expression   as-vector-expression)
                               (success-cont function)
                               (failure-cont function))
  (let+ ((value (env:value environment))
         ((&flet call-with-value-environment (cont parent-environment)
            (funcall cont (env:environment-at
                           parent-environment (list :value value)
                           :class 'env:value-environment
                           :state '()))))
         ((&with-gensyms end-var))
         (vector-environment (env:environment-at
                              environment (list :sequence value
                                                :position 0
                                                :end      end-var)
                              :class 'seq:vector-environment
                              :state '())))
    `(if (typep ,value ',(target-type expression))
         (let ((,end-var (length ,value)))
           ,(compile-expression
             grammar vector-environment (sub-expression expression)
             ;; If the sub-expression succeeds, ensure that the entire
             ;; vector has been consumed by compiling a
             ;; `bounds-test-expression' that is expected to fail. In
             ;; any case, continue with a new `value-environment' for
             ;; VALUE.
             (lambda (new-environment)
               (compile-expression
                grammar new-environment (make-instance 'seq::bounds-test-expression
                                                       :sub-expression (make-instance 'base::ignored-expression))
                (curry #'call-with-value-environment failure-cont)
                (curry #'call-with-value-environment success-cont)))
             (lambda (new-environment)
               (call-with-value-environment failure-cont new-environment))))
         ,(funcall failure-cont environment))))
