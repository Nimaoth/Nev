
(defmacro : (command args...)
  `(run-command (quote ,command) ,@args))


(let bind-command (lambda (context keys command)
  (do
    (echo "bind command" command)
    (: add-command-script context ' keys command))))
