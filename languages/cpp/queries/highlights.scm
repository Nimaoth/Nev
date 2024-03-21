"break" @keyword
"case" @keyword
"const" @keyword
"continue" @keyword
"default" @keyword
"do" @keyword
"else" @keyword
"enum" @keyword
"extern" @keyword
"for" @keyword
"if" @keyword
"inline" @keyword
"return" @keyword
"sizeof" @keyword
"static" @keyword
"struct" @keyword
"switch" @keyword
"typedef" @keyword
"union" @keyword
"volatile" @keyword
"while" @keyword

"#define" @keyword
"#elif" @keyword
"#else" @keyword
"#endif" @keyword
"#if" @keyword
"#ifdef" @keyword
"#ifndef" @keyword
"#include" @keyword
(preproc_directive) @keyword

"--" @keyword.operator
"-" @keyword.operator
"-=" @keyword.operator
"->" @keyword.operator
"=" @keyword.operator
"!=" @keyword.operator
"*" @keyword.operator
"&" @keyword.operator
"&&" @keyword.operator
"+" @keyword.operator
"++" @keyword.operator
"+=" @keyword.operator
"<" @keyword.operator
"==" @keyword.operator
">" @keyword.operator
"||" @keyword.operator

"." @punctuation
";" @punctuation

(string_literal) @string
(system_lib_string) @string

(null) @constant
(number_literal) @constant.numeric
(char_literal) @constant.numeric

(call_expression
  function: (identifier) @variable.function)
(call_expression
  function: (field_expression
    field: (field_identifier) @variable.function))
(function_declarator
  declarator: (identifier) @variable.function)
(preproc_function_def
  name: (identifier) @variable.function.special)

(field_identifier) @variable
(statement_identifier) @label
(type_identifier) @storage.type
(primitive_type) @storage.type
(sized_type_specifier) @storage.type

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

(identifier) @variable

(comment) @comment