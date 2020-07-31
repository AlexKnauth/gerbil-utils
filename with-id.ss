(export #t)

(import ./syntax (for-syntax ./syntax))

;; Written with the precious help of Alex Knauth
(defsyntax (with-id stx)
  (syntax-case stx ()
    ((wi (id-spec ...) body ...)
     #'(wi wi (id-spec ...) body ...))
    ((wi ctx (id-spec ...) body body1 body+ ...)
     (identifier? #'ctx)
     #'(wi ctx (id-spec ...) (begin body body1 body+ ...)))
    ((_ ctx (id-spec ...) template)
     (identifier? #'ctx)
     (with-syntax ((((id expr) ...)
                    (stx-map (lambda (spec) (syntax-case spec ()
                                         ((id) #'(id 'id))
                                         ((id ct-expr more ...) #'(id (list ct-expr more ...)))
                                         (id (identifier? #'id) #'(id 'id))))
                             #'(id-spec ...))))
       #'(begin
           (defsyntax (m stx2)
             (with-syntax ((id (identifierify (quote-syntax ctx) expr)) ...)
               (... #'(... template))))
           (m))))))