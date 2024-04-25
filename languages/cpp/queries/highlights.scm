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
"class" @keyword
"switch" @keyword
"typedef" @keyword
"union" @keyword
"volatile" @keyword
"while" @keyword
"virtual" @keyword
"override" @keyword
"public" @keyword
"protected" @keyword
"private" @keyword

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
":" @punctuation
"," @punctuation
"(" @punctuation
")" @punctuation
"[" @punctuation
"]" @punctuation
"{" @punctuation
"}" @punctuation

(auto) @keyword
(this) @keyword

(string_literal) @string
(system_lib_string) @string

(null) @constant
(number_literal) @constant.numeric
(char_literal) @constant.numeric

((identifier) @support.type
  (#match? @support.type "^[FUTI][A-Z].*$"))

(qualified_identifier
  scope: (namespace_identifier) @support.type
  name: (identifier) @variable.function)

(qualified_identifier
  scope: (namespace_identifier) @support.type
  name: (template_function
    name: (identifier) @variable.function))

(call_expression
  function: (identifier) @variable.function)
(call_expression
  function: (field_expression
    field: (field_identifier) @variable.function))
(call_expression
  function: (template_function
    name: (identifier) @variable.function))
(function_declarator
  declarator: (identifier) @variable.function)
(preproc_function_def
  name: (identifier) @variable.function.special)

(field_declaration
  declarator: (function_declarator
    declarator: (field_identifier) @variable.function))

(field_identifier) @variable
(statement_identifier) @label
(type_identifier) @support.type
(primitive_type) @support.type
(sized_type_specifier) @support.type

((identifier) @constant
 (#match? @constant "^[A-Z][A-Z\\d_]*$"))

(identifier) @variable

(comment) @comment
