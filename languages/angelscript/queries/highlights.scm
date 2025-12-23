
(string_literal) @string
; (identifier) @variable
(field_identifier) @variable

((identifier) @keyword
  (#match? @keyword "(ref|const)"))

((identifier) @type
 (#match? @type "^[A-Z][a-zA-Z\\d_]*$"))

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

(datatype (identifier) @keyword)
(field_expression field: (field_identifier) @property)
(call_expression function: (reciever (field_expression field: (field_identifier) @function)))
(call_expression function: (reciever (variable_access (identifier) @function)))
(func name: (identifier) @function)

[
  "float"
  "int"
  "void"
] @type

[
  "return"
  "if"
  "while"
  "shared"
  "const"
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
