;From nvim-treesitter/nvim-treesitter
(atx_heading (inline) @text.title)
(setext_heading (paragraph) @text.title)

(atx_heading (atx_h1_marker) heading_content: (_) @header1)
(atx_heading (atx_h2_marker) heading_content: (_) @header2)
(atx_heading (atx_h3_marker) heading_content: (_) @header3)
(atx_heading (atx_h4_marker) heading_content: (_) @header4)
(atx_heading (atx_h5_marker) heading_content: (_) @header5)
(atx_heading (atx_h6_marker) heading_content: (_) @header6)

(atx_h1_marker) @header1
(atx_h2_marker) @header2
(atx_h3_marker) @header3
(atx_h4_marker) @header4
(atx_h5_marker) @header5
(atx_h6_marker) @header6

[
  (setext_h1_underline)
  (setext_h2_underline)
] @punctuation.special

[
  (link_title)
  (indented_code_block)
  (fenced_code_block)
] @text.literal

[
  (fenced_code_block_delimiter)
] @punctuation.delimiter

(code_fence_content) @none

[
  (link_destination)
] @text.uri

[
  (link_label)
] @text.reference

[
  (list_marker_plus)
  (list_marker_minus)
  (list_marker_star)
  (list_marker_dot)
  (list_marker_parenthesis)
  (thematic_break)
] @punctuation.special

[
  (block_continuation)
  (block_quote_marker)
] @punctuation.special

[
  (backslash_escape)
] @string.escape
