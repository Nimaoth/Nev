import std/[os, strutils, strformat, json]

## This file adds a second link for certain docs, linking the generated script wrapper functions to the exposed function in the editor.

proc postProcess(filename: string, replacementFile: string) =
  echo "post processing doc ", filename, ", ", replacementFile
  let (path, name, ext) = filename.splitFile
  let mappingsJson = readFile(fmt"int/{name}.map")
  let mappings = parseJson(mappingsJson)

  let searchString = "<a href=\"https://github.com/Nimaoth/Nev//"

  let content = readFile(filename)
  var result = ""

  for line in content.splitLines:
    result.add line
    result.add "\n"

    let index = line.find(searchString)
    if index == -1:
      continue

    let opStartIndex = index + searchString.len
    let opEndIndex = line.find("/", opStartIndex)
    let branchStartIndex = opEndIndex + 1
    let branchEndIndex = line.find("/", branchStartIndex)

    let fileStartIndex = branchEndIndex + 1
    let fileEndIndex = line.find("#", fileStartIndex)
    let lineNumberStartIndex = fileEndIndex + 2
    let lineNumberEndIndex = line.find("\"", lineNumberStartIndex)
    let nameStartIndex = line.find(">", lineNumberEndIndex) + 1
    let nameEndIndex = line.find("<", nameStartIndex)

    if fileEndIndex < 0 or lineNumberEndIndex < 0 or opEndIndex < 0 or opEndIndex < 0 or nameEndIndex < 0:
      continue

    let op = line[opStartIndex..<opEndIndex]
    let branch = line[branchStartIndex..<branchEndIndex]
    let fileName = line[fileStartIndex..<fileEndIndex]
    let lineNumber = line[lineNumberStartIndex..<lineNumberEndIndex]

    if op == "edit":
      continue

    echo fmt"{op}, {branch}, {fileName}, {lineNumber}"
    echo line

    let newLineNumber = if mappings.hasKey(lineNumber):
      mappings[lineNumber].getStr
    else:
      lineNumber

    var newLine = line
    newLine.delete(nameStartIndex..<nameEndIndex)
    newLine.insert("Editor Source", nameStartIndex)
    newLine.delete(lineNumberStartIndex..<lineNumberEndIndex)
    newLine.insert(newLineNumber, lineNumberStartIndex)
    newLine.delete(fileStartIndex..<fileEndIndex)
    newLine.insert(replacementFile, fileStartIndex)
    newLine.delete((opStartIndex-1)..<opStartIndex)
    result.add newLine
    result.add "\n"

    echo newLine

  # writeFile(fmt"{path}/{name}.post{ext}", result)
  writeFile(fmt"{path}/{name}{ext}", result)

postProcess("scripting/htmldocs/editor_text_api.html", "src/text/text_editor.nim")
postProcess("scripting/htmldocs/editor_model_api.html", "src/ast/model_document.nim")
postProcess("scripting/htmldocs/editor_api.html", "src/app.nim")
postProcess("scripting/htmldocs/lsp_api.html", "src/text/language/lsp_client.nim")
postProcess("scripting/htmldocs/popup_selector_api.html", "src/selector_popup.nim")