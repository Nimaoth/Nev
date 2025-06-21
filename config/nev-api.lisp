; Utility functions
(let map (lambda (l f)
  (repeat i (len l) (f i (. l i)))))

(let max (lambda (a b)
  (if (> a b) a b)))

; Run a command
; Examples:
; (: set-option ui.background.transparent true)
(defmacro : (command args...)
  `(run-command (quote ,command) ,@args))

; Bind a command to a key combination
; Examples:
; (bind-command 'vim.normal '<LEADER>n ".align-cursors")
(let bind-command (lambda (context keys command)
  (do
    (echo "bind command" command)
    (: add-command-script context ' keys command))))

; Example command

; Aligns all cursors at the right most cursor by inserting spaces
(add-command-raw 'editor.text 'align-cursors true
  (lambda (editor)
    (do
      (let selections (: .get-selections editor))

      ; find max column
      (let max-column 0)
      (repeat i (len selections) (do
        (set max-column (max max-column (. (. (. selections i) 'last) 'column)))))

      ; aligned selections
      (let aligned-selections (map selections
        (lambda (i v)
          (do
            (let last (. v 'last))
            (let line (. last 'line))
            {first: {line: line, column: max-column}, last: {line: line, column: max-column}}
            ))))

      ; calculate text to insert at each selection
      (let texts (map selections
        (lambda (i v)
          (do
            (let column (. (. (. selections i) 'last) 'column))
            (let diff (- max-column column))
            ; ` creates a list like (build-str " "  " "  " "  " ")
            ; use eval to actually run it
            ; (repeat a b c) repeats the expression c, b times, with a bound to the index (starting at 0)
            (let text (eval `(build-str ,@(repeat _ diff " "))))
            text))))

      ; modify document
      (: .add-next-checkpoint "insert")
      (: .edit selections texts)
      (: .set-selections aligned-selections)
      nil)))
