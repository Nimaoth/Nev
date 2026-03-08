
(string_literal) @string
; (identifier) @variable
(field_identifier) @variable

; ((identifier) @keyword
;   (#match? @keyword "(ref|const)"))

; ((identifier) @type
;  (#match? @type "^[A-Z][a-zA-Z\\d_]*$"))

; ((identifier) @constant
;  (#match? @constant "^[A-Z][A-Z\\d_]*$"))

(datatype (identifier) @type)
(field_expression field: (field_identifier) @property)
(scope_expression left: (_) @type)
(call_expression function: (reciever (scope_expression right: (_) @function)))
(call_expression function: (reciever (field_expression field: (field_identifier) @function)))
(call_expression function: (reciever (variable_access (identifier) @function)))
(func name: (identifier) @function)

(uproperty (identifier) @property)
(ufunction (identifier) @property)
(uclass (identifier) @property)
(ustruct (identifier) @property)
(meta_arg (identifier) @property)

[
  "float"
  "int"
  "void"
  "bool"
  "auto"
] @type

[
  "nullptr"
] @constant

[
  "return"
  "if"
  "else"
  "for"
  "event"
  "mixin"
  "class"
  "struct"
  "private"
  "protected"
  "while"
  "shared"
  "const"
  "continue"
  "break"
  "UFUNCTION"
  "UPROPERTY"
  "UCLASS"
  "USTRUCT"
] @keyword

[
  "+"
  "++"
  "-"
  "--"
  "*"
  "/"
  "%"
  "="
  "=="
  "@"
  "!"
  "&"
  "|"
  "&&"
  "||"
  "<"
  "<<"
  ">"
  ">>"
] @keyword.operator

[
  "."
  ";"
  ","
  ":"
] @punctuation.delimiter
[
  "("
  ")"
  "["
  "]"
  "{"
  "}"
] @punctuation.bracket

(number_literal) @number

(comment) @comment
