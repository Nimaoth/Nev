#use formatting_component
import std/[options, tables]
import nimsumtree/[arc]
import regex
import misc/[event, custom_async]
import vfs, config_provider, service, document, formatting_component
import component

export component

const currentSourcePath2 = currentSourcePath()
include module_base

type
  AngelscriptFormatter* = ref object of Formatter
    keywordsRequiringIdentifiers: seq[tuple[regex1, regex2, regex3: Regex2]]
    formatStringRegex: Regex2 = re2"""^[A-z][\'\"].*"""
    inOutRegex: Regex2 = re2"""^.?&(in|out).*"""
    startLineRegex: Regex2 = re2"""^\s*([A-z_])+\s+([A-z0-9_])+\s*\(.*"""
    startLineEditedRegex: Regex2 = re2"""^\s*([A-z_])+\r?\n\s*([A-z0-9_])+\s*\(.*"""
    accessRegex: Regex2 = re2"""^\s*access\s*:.*"""

# DLL API

# Nice wrappers

# Implementation
when implModule:
  import std/[sequtils, parsexml, streams, strformat]
  import misc/[util, custom_logger, rope_utils, async_process]
  import nimsumtree/[rope, buffer, clock]
  import document, text_component, channel
  import scripting_api except DocumentEditor, TextDocumentEditor, AstDocumentEditor

  logCategory "angelscript-formatter"
  proc allowEdit(self: AngelscriptFormatter, content: Rope, edit: Range[Point], text: string): bool =
    let lineRange = content.lineRange(edit.a.row.int)
    let startLine = $content.slice(lineRange)

    if edit.a.row == edit.b.row:
      if edit.a.column.int > startLine.len or edit.b.column.int > startLine.len:
        return false

      let startLineEdited = startLine[0..<edit.a.column.int] & text & startLine[edit.b.column.int..^1]

      if edit.a == edit.b and edit.a.column > 0:
        let testRange = point(edit.a.row, edit.a.column - 1)...point(edit.b.row.int, lineRange.b - lineRange.a)
        let text = $content.slice(testRange)

        # Prevent spaces from being added between string prefixes and the string (e.g. f-strings)
        if text.match(self.formatStringRegex):
          return false

        # Prevent spaces from being added between & and "in" or "out"
        if text.match(self.inOutRegex):
          return false

      # Prevent new lines after function return types
      # This can happen if you have e.g. a struct that you don't close with a semicolon, followed by a function
      #    struct Foo {}
      #    void bar() {}
      #    ----------
      #    struct Foo {}
      #    void
      #    bar() {}
      if startLine.match(self.startLineRegex) and startLineEdited.match(self.startLineEditedRegex) and text.find("\n") != -1:
        return false

      # Prevent new lines breaking up the 'keyword type name'
      for keyword in self.keywordsRequiringIdentifiers:
        if startLine.match(keyword.regex1) and (startLineEdited.match(keyword.regex2) or startLineEdited.match(keyword.regex3)):
          return false

    # Don't format "access:" lines, these are a bit special
    if startLine.match(self.accessRegex):
      return false

    return true

  proc readStderr(stderr: Arc[BaseChannel]): Future[void] {.gcsafe, async: (raises: []).} =
    try:
      var t = ""
      while true:
        let available = stderr.flushRead()
        if available == 0 and not stderr.isOpen:
          break
        t.setLen(available)
        if available > 0:
          discard stderr.read(t.toOpenArrayByte(0, t.high))
          echo t
        await sleepAsync(1.milliseconds)
    except CatchableError:
      discard

  proc formatAngelscript(self: AngelscriptFormatter, document: Document): Future[void] {.gcsafe, async: (raises: []).} =
    log lvlInfo, &"Format angelscript '{document.filename}'"
    let text = document.getTextComponent().getOr:
      return

    let content = text.content
    let version = text.buffer.version

    try:
      let formatterArgs = @["--output-replacements-xml", &"--assume-filename={document.localizedPath}"]
      var process = startAsyncProcess("clang-format", formatterArgs, killOnExit = true, autoStart = false)
      discard process.start()
      asyncSpawn readStderr(process.stderr)

      for chunk in content.iterateChunks:
        process.stdin.write(chunk.chars)
        await sleepAsync(1.milliseconds)

      process.stdin.close()

      var res = newStringOfCap(content.len * 2)
      var t = ""
      while true:
        let available = process.stdout.flushRead()
        if available == 0 and not process.isAlive:
          break
        t.setLen(available)
        if available > 0:
          discard process.stdout.read(t.toOpenArrayByte(0, t.high))
          res.add t
        await sleepAsync(1.milliseconds)

      var selections: seq[Range[Point]]
      var texts: seq[string]
      var x: XmlParser
      var s = newStringStream(res)
      x.open(s, document.filename, {reportWhitespace})
      x.next()
      while true:
        case x.kind
        of xmlElementOpen:
          if cmpIgnoreCase(x.elementName, "replacement") == 0:
            var offset = 0
            var length = 0
            var text = ""
            while true:
              x.next()
              case x.kind:
              of xmlAttribute:
                let key = x.attrKey
                let value = x.attrValue
                if key == "offset":
                  offset = value.parseInt
                elif key == "length":
                  length = value.parseInt
                else:
                  break
              of xmlCharData, xmlWhitespace:
                text.add x.charData
              of xmlEof, xmlElementEnd: break # end of file reached
              else:
                discard

            let startPoint = content.offsetToPoint(offset)
            let endPoint = content.offsetToPoint(offset + length)
            # echo &"edit {offset}:{length}, {startPoint...endPoint}, '{text}'"
            if self.allowEdit(content, startPoint...endPoint, text):
              selections.add(startPoint...endPoint)
              texts.add(text)
          else:
            x.next()

        of xmlEof: break # end of file reached
        else:
          x.next()
          discard # ignore other events

      x.close()

      if text.buffer.version != version:
        log lvlError, &"Document changed since formatting, retry"
        return
      log lvlInfo, &"Apply {selections.len} changes for formatting"
      discard text.edit(selections, selections, texts, checkpoint = "insert")
    except CatchableError:
      discard

  proc registerFormatter() {.async.} =
    let services = getServices()
    if services == nil:
      log lvlWarn, &"Failed to initialize init_module_formatting_component: no services found"
      return

    var formatter = AngelscriptFormatter()
    formatter.formatImpl = proc(self: Formatter, document: Document): Future[void] {.gcsafe, async: (raises: []).} =
      await self.AngelscriptFormatter.formatAngelscript(document)

    for keyword in ["private", "protected", "delegate", "event"]:
      formatter.keywordsRequiringIdentifiers.add (
        re2(&"^\\s*{keyword}\\s+\\w+.*"),
        re2(&"^\\s*{keyword}\r?\n.*"),
        re2(&"^\\s*{keyword}\\s+\\w+\r?\n.*"),
      )

    # todo: make sure modules are loaded in dependency order so we can be sure the service exists at this point
    var formattingService = services.getService(FormattingService)
    var maxTries = 0
    while formattingService.isNone and maxTries < 1000:
      await sleepAsync(10.milliseconds)
      formattingService = services.getService(FormattingService)
      inc maxTries

    if formattingService.isNone:
      log lvlError, &"Failed to register angelscript formatter"
      return

    formattingService.get.registerFormatter("angelscript", formatter)

  proc init_module_angelscript_formatter*() {.cdecl, exportc, dynlib.} =
    asyncSpawn registerFormatter()