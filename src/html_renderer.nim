import std/[strformat, tables, options, sequtils, os]
import fusion/matching, chroma
import util, id, ast, theme, ast_document
import compiler

proc serializeNodeHtml(self: AstDocument, node: AstNode): string =
  let dq = "\""
  case node.kind
  # of Empty:
  of Identifier:
    let name = if self.nodes.contains(node.reff):
      self.nodes[node.reff].text
    else:
      $node.reff
    return fmt("<a id=\"{node.id}\" href=\"#{node.reff}\" class=\"identifier\">{name}</a>")
  of NumberLiteral:
    return fmt("<span id=\"{node.id}\" class=\"number-literal\">{node.text}</span>")
  # of StringLiteral:
  # of ConstDecl:
  # of LetDecl:
  # of VarDecl:
  of NodeList:
    result = fmt("<div id=\"{node.id}\">")
    for c in node.children:
      result.add self.serializeNodeHtml(c)
      result.add "\n  "
    result.add "\n  </div>"
  # of Call:
  # of If:
  # of While:
  # of FunctionDefinition:
  # of Params:
  # of Assignment:
  else:
    result = fmt"<span id={dq}{node.id}{dq}>{node.text}</span>"
    for c in node.children:
      result.add self.serializeNodeHtml(c)
      result.add "\n  "

proc serializeNodeHtml(self: AstDocument, node: VisualNode, theme: Theme): string =
  let id = if node.node.isNil: "" else: fmt("id=\"id-{node.node.id}\"")

  if node.text.len > 0:
    let color = theme.anyColor(node.colors, rgb(255, 255, 255)).toHtmlHex
    var style = theme.tokenFontStyle(node.colors)
    if node.styleOverride.getSome(override):
      style.incl override

    let fontWeight = if Bold in style: "bold" else: "normal"
    let fontStyle = if Italic in style: "italic" else: "normal"
    let decoration = if Underline in style: "underline" else: ""

    let text = node.text
    if not node.node.isNil and node.node.reff != null:
      result.add fmt("<a {id} href=\"#id-{node.node.reff}\" style=\"color: {color}; font-weight: {fontWeight}; font-style: {fontStyle}; text-decoration: {decoration}\">{text}</a>")
    else:
      var classes = ""
      if not node.node.isNil:
        classes.add " def"
      result.add fmt("<span {id} class=\"{classes}\" style=\"color: {color}; font-weight: {fontWeight}; font-style: {fontStyle}; text-decoration: {decoration}\">{text}</span>")

  elif node.node != nil and node.node.kind == Empty:
    let text = if node.node.text.len > 0: node.node.text else: " "
    result.add fmt("<span {id}\" style=\"color: #fff; border: 1px solid red; white-space: pre-wrap;\">{text}</span>")

  if node.children.len > 0:
    if node.indent > 0:
      let indent = " ".repeat(node.indent * 2)
      result.add fmt("<span style=\"white-space: pre-wrap;\">{indent}</span>")

    if node.orientation == Vertical:
      result.add fmt("<div class=\"collapsible inline-block\" style=\"color: white; display: inline-block\">-</div>")
    result.add fmt("<div {id} class=\"content inline-block\" style=\"display: inline-block\">\n")
    for i, child in node.children:
      let childHtml = self.serializeNodeHtml(child, theme)
      if i > 0 and childHtml.len > 0 and node.orientation == Vertical:
        result.add("<br my-indent=\"1\">\n")
      result.add childHtml
    result.add fmt("</div>\n")


proc serializeLayoutHtml(self: AstDocument, layout: NodeLayout, theme: Theme): string =
  result = ""
  var i = 0
  var addedDiv = false
  for line in layout.root.children:
    let lineHtml = self.serializeNodeHtml(line, theme)
    if lineHtml.len == 0:
      continue

    if i == 1:
      addedDiv = true
      result.add fmt("<div class=\"collapsible block\" style=\"color: white;\">-</div>")
      result.add fmt("<div class=\"content\">")

    result.add lineHtml
    result.add "<br my-indent=\"2\">\n"
    inc i

  if addedDiv:
    result.add fmt("</div>")

proc serializeHtml*(self: AstDocument, theme: Theme): string =
  let title = self.filename.splitFile.name

  var body = ""
  var diagnosticsCss = ""
#   for c in self.rootNode.children:
#     let input = ctx.getOrCreateNodeLayoutInput NodeLayoutInput(node: c, renderDivisionVertically: true)
#     let layout = ctx.computeNodeLayout(input)
#     let html = self.serializeLayoutHtml(layout, theme)
#     body.add fmt("<div class=\"code\">{html}</div><br>\n")

#     # Add diagnostics
#     for (id, visualRange) in layout.nodeToVisualNode.pairs:
#       if ctx.diagnosticsPerNode.contains(id):
#         var foundErrors = false
#         for diagnostics in ctx.diagnosticsPerNode[id].queries.values:
#           for diagnostic in diagnostics:
#             # last = ed.renderCtx.drawText(vec2(contentBounds.xw, last.yh), diagnostic.message, ed.theme.color("editorError.foreground", rgb(255, 0, 0)), pivot = vec2(1, 0))
#             foundErrors = true
#         if foundErrors:
#           diagnosticsCss.add fmt"""#id-{id} {{
#   border: 1px solid red;
# }}
# """

  return fmt"""<!DOCTYPE html>
<html>
  <head>
    <meta charset=utf-8>
    <title>{title}</title>
    <style>
      body {{
        margin: 0px;
        font-family: "Courier New", monospace;
        background: #222222;
      }}
      .code span {{
        vertical-align: top;
        border-width: 1px;
      }}
      .code a {{
        text-decoration: none;
        vertical-align: top;
        border-width: 1px;
      }}
      .code div {{
        vertical-align: top;
        border-width: 1px;
      }}

      .code a:hover {{
        text-decoration: underline;
      }}

      .highlight {{
        outline-width: 1px;
        outline-color: yellow;
        outline-style: solid;
      }}

      .primary {{
        outline-width: 1px;
        outline-color: red;
        outline-style: solid;
      }}

      {diagnosticsCss}

      .collapsible {{
        cursor: pointer; /* Add a cursor to the div */

        -webkit-touch-callout: none; /* Disable callout on iOS */
        -webkit-user-select: none; /* Disable selection on iOS */
        -khtml-user-select: none; /* Disable selection on Konqueror */
        -moz-user-select: none; /* Disable selection on Firefox */
        -ms-user-select: none; /* Disable selection on IE 10+ */
        user-select: none; /* Disable selection on modern browsers */
      }}

      /* Style the sidebar */
      .sidebar {{
        height: 100%; /* Set the height to 100% */
        width: 100; /* Set the width */
        position: fixed; /* Fix the position */
        top: 0; /* Set the top position */
        left: 0; /* Set the left position */
        background-color: #444;
        padding: 8px; /* Add some padding */
      }}

      /* Style the main content */
      .main {{
        margin-left: 116px; /* Set the margin to the left of the sidebar */
        padding: 8px;
      }}

      @media (max-width: 600px) {{
        .sidebar {{
          position: sticky; /* Set the position to relative */
          width: 100%; /* Set the width to 100% */
        }}
        .main {{
          margin-left: 0; /* Remove the margin */
        }}
      }}

    </style>
  </head>

  <body>
    <div class="sidebar">
      <button onclick="collapseAll(true)">Collapse All</button><br>
      <button onclick="collapseAll(false)">Expand All</button>
    </div>

    <div class="main">
      <h1><a href="./{title}.ast" style="color: white">{title}</a></h1>
      {body}
    </div>

    <script>

      function clearAllHighlights() {{
        // Remove the highlight class from all elements
        let elements = document.querySelectorAll('.highlight');
        for (let i = 0; i < elements.length; i++) {{
          elements[i].classList.remove('highlight');
        }}
        elements = document.querySelectorAll('.primary');
        for (let i = 0; i < elements.length; i++) {{
          elements[i].classList.remove('primary');
        }}
      }}

      let links = document.querySelectorAll('a');
      for (let i = 0; i < links.length; i++) {{
        links[i].addEventListener('click', function() {{
          clearAllHighlights();

          // Add the highlight class to the element with the same id as the clicked link
          const href = this.getAttribute('href')
          if (href.startsWith('#')) {{
            let element = document.getElementById(this.getAttribute('href').substring(1));
            if (element !== null) {{
              element.classList.add('highlight');
              console.log("test");
              element.scrollIntoView({{
                behavior: "smooth",
                block: "center"
              }});
              return false;
            }}
          }}

          return true;
        }});

        links[i].addEventListener('mouseenter', function() {{
          const href = this.getAttribute('href')
          if (href.startsWith('#')) {{
            clearAllHighlights();
            let href = this.getAttribute('href').substring(1);
            let element = document.getElementById(href);
            if (element !== null) {{
              //element.classList.add('highlight');
              element.classList.add('primary');
            }}
            highlightReferences(href);
          }}
          this.classList.add('highlight');
        }});
      }}

      let defs = document.querySelectorAll('.def');
      for (let i = 0; i < defs.length; i++) {{
        defs[i].addEventListener('mouseleave', function() {{
          clearAllHighlights();
          return true;
        }})
        defs[i].addEventListener('mouseenter', function() {{
          clearAllHighlights();
          highlightReferences(this.id);
          // this.classList.add('highlight');
          this.classList.add('primary');
          return true;
        }})
      }}

      function highlightReferences(id) {{
        let links = document.querySelectorAll(`a[href="#${{id}}"]`);
        for (let link of links) {{
          link.classList.add('highlight');
        }}
      }}

      var coll = document.getElementsByClassName("collapsible");
      var i;

      for (i = 0; i < coll.length; i++) {{
        coll[i].addEventListener("click", function() {{
          this.classList.toggle("active");
          var content = this.nextElementSibling;
          if (content.style.display !== "none") {{
            content.style.display = "none";
            this.innerHTML = "+";
          }} else {{
            this.innerHTML = "-";
            if (this.classList.contains("block"))
              content.style.display = "block";
            else if (this.classList.contains("inline-block"))
              content.style.display = "inline-block";
            else
              content.style.display = "block";
          }}
        }});
      }}

      function collapseAll(collapse) {{
        var coll = document.getElementsByClassName("collapsible");

        for (let i = 0; i < coll.length; i++) {{
          var content = coll[i].nextElementSibling;
          if (collapse) {{
            coll[i].classList.add("active");
            content.style.display = "none";
            coll[i].innerHTML = "+";
          }} else {{
            coll[i].classList.remove("active");
            coll[i].innerHTML = "-";
            if (coll[i].classList.contains("block"))
              content.style.display = "block";
            else if (coll[i].classList.contains("inline-block"))
              content.style.display = "inline-block";
            else
              content.style.display = "block";
          }}
        }}
      }}
    </script>
  </body>
</html>"""