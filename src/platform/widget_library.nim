import std/[strformat, strutils]
import document, workspaces/workspace, ui/node
import chroma

template createHeader*(builder: UINodeBuilder, inRenderHeader: bool, inMode: string, inDocument: Document, inHeaderColor: Color, inTextColor: Color, body: untyped): UINode =
  block:
    var leftFunc: proc()
    var rightFunc: proc()

    template left(inBody: untyped) =
      leftFunc = proc() =
        inBody

    template right(inBody: untyped) =
      rightFunc = proc() =
        inBody

    body

    var bar: UINode
    if inRenderHeader:
      builder.panel(&{FillX, SizeToContentY, FillBackground, LayoutHorizontal}, backgroundColor = inHeaderColor):
        bar = currentNode

        let workspaceName = inDocument.workspace.map(wf => " - " & wf.name).get("")

        let mode = if inMode.len == 0: "normal" else: inMode
        builder.panel(&{SizeToContentX, SizeToContentY, DrawText}, textColor = inTextColor, text = " $# - $# $# " % [mode, inDocument.filename, workspaceName])

        if leftFunc.isNotNil:
          leftFunc()

        builder.panel(&{FillX, SizeToContentY, LayoutHorizontalReverse}):
          if rightFunc.isNotNil:
            rightFunc()

    else:
      builder.panel(&{FillX}):
        bar = currentNode

    bar