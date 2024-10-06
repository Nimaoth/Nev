import std/[json, tables, strutils, options]
import chroma, results
import misc/[custom_logger, myjsonutils, util]
import platform/[filesystem]

logCategory "theme"

{.push gcsafe.}
{.push raises: [].}

type
  FontStyle* = enum Italic, Underline, Bold
  Style* = object
    foreground*: Option[Color]
    background*: Option[Color]
    fontStyle*: set[FontStyle]

type
  Theme* = ref object
    path*: string
    name*: string
    typ*: string
    colorSpace*: string
    colors*: Table[string, Color]
    tokenColors*: Table[string, Style]

var gTheme*: Theme = nil

proc parseHexVar*(text: string): Result[Color, string] =
  try:
    let offset = if text.startsWith "#": 1 else: 0
    if text.len == 6 + offset:
      return parseHex(text[offset..^1]).ok
    elif text.len == 8 + offset:
      return parseHexAlpha(text[offset..^1]).ok
    elif text.len == 3 + offset:
      return parseHtmlHexTiny("#" & text[offset..^1]).ok
    elif text.len == 4 + offset:
      var res = parseHtmlHexTiny("#" & text[offset..^2])
      res.a = parseHexInt(text[^1..^1]).float32 / 255
      return res.ok
    result.err "Invalid color"
  except InvalidColor, ValueError:
    result.err getCurrentExceptionMsg()

proc getCascading[T](table: var Table[string, T], key: string, default: T): T =
  table.withValue(key, val):
    return val[]
  let index = key.rfind(".")
  if index != -1:
    return table.getCascading(key[0..<index], default)
  return default

proc color*(theme: Theme, name: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return theme.colors.getCascading(name, default.color)

proc color*(theme: Theme, names: seq[string], default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  for name in names:
    theme.colors.withValue(name, val):
      return val[]
  return default.color

proc tokenColor*(theme: Theme, name: cstring, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  let res = theme.tokenColors.getCascading($name, Style()).foreground
  return res.get default.color

proc tokenColor*(theme: Theme, name: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return theme.tokenColors.getCascading(name, Style()).foreground.get default.color

proc tokenColor*(theme: Theme, names: seq[string], default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  for name in names:
    theme.tokenColors.withValue(name, style):
      if style[].foreground.isSome:
        return style[].foreground.get
  return default.color

proc anyColor*(theme: Theme, names: seq[string], default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  for name in names:
    if name.startsWith "#":
      return parseHexVar(name).valueOr(default)
    elif name.startsWith("&") and theme.colors.contains(name[1..^1]):
      return theme.colors[name[1..^1]]
    else:
      theme.tokenColors.withValue(name, style):
        if style[].foreground.isSome:
          return style[].foreground.get

  return default.color

proc tokenBackgroundColor*(theme: Theme, name: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return (theme.tokenColors.getCascading(name, Style())).background.get default.color

proc tokenFontStyle*(theme: Theme, name: string): set[FontStyle] =
  return (theme.tokenColors.getCascading(name, Style(fontStyle: {}))).fontStyle

proc tokenFontStyle*(theme: Theme, names: seq[string]): set[FontStyle] =
  for name in names:
    theme.tokenColors.withValue(name, style):
      return style.fontStyle
  return {}

proc anyColor*(theme: Theme, color: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return if color.startsWith "#":
    parseHexVar(color).valueOr(default)
  elif color.startsWith "&":
    theme.color(color[1..^1], default)
  else:
    theme.tokenColor(color, default)

{.pop.} # raises: []
{.pop.} # gcsafe

proc fromJsonHook*(color: var Color, jsonNode: JsonNode) =
  if jsonNode.kind == JNull:
    color = Color()
    return

  color = parseHexVar(jsonNode.str).valueOr(Color())

proc fromJsonHook*(style: var set[FontStyle], jsonNode: JsonNode) =
  style = {}
  let text = jsonNode.str
  if text.contains "italic": style.incl Italic
  if text.contains "bold": style.incl Bold
  if text.contains "underline": style.incl Underline

proc fromJsonHook*(style: var Style, jsonNode: JsonNode) =
  if jsonNode.hasKey("foreground"):
    style.foreground = some(jsonNode["foreground"].jsonTo Color)
  if jsonNode.hasKey("background"):
    style.background = some(jsonNode["background"].jsonTo Color)
  else:
    style.background = Color.none
  if jsonNode.hasKey("fontStyle"):
    style.fontStyle = jsonNode["fontStyle"].jsonTo set[FontStyle]

proc jsonToTheme*(json: JsonNode, opt = Joptions()): Theme =
  result = Theme()
  result.name = json["name"].jsonTo string

  if json.hasKey("type"):
    result.typ = json["type"].jsonTo string

  if json.hasKey("colorSpaceName"):
    result.colorSpace = json["colorSpaceName"].jsonTo string

  if json.hasKey("colors"):
    for (key, value) in json["colors"].fields.pairs:
      result.colors[key] = value.jsonTo Color
      # result.colorsC[key.cstring] = value.jsonTo Color

  if json.hasKey("tokenColors"):
    for item in json["tokenColors"].elems:
      var scopes: seq[string] = @[]

      if item.hasKey("scope"):
        let scope = item["scope"]
        if scope.kind == JString:
          scopes.add scope.str
        else:
          for scopeName in scope.elems:
            scopes.add scopeName.str
      else:
        scopes.add "."

      let settings = item["settings"]
      for scope in scopes:
        if not result.tokenColors.contains(scope):
          result.tokenColors[scope] = Style(foreground: Color.none, background: Color.none)
        if settings.hasKey("foreground"):
          result.tokenColors[scope].foreground = some(settings["foreground"].jsonTo Color)
          # result.tokenColorsC[scope.cstring].foreground = some(settings["foreground"].jsonTo Color)
        if settings.hasKey("background"):
          result.tokenColors[scope].background = some(settings["background"].jsonTo Color)
          # result.tokenColorsC[scope.cstring].background = some(settings["background"].jsonTo Color)
        if settings.hasKey("fontStyle"):
          result.tokenColors[scope].fontStyle = settings["fontStyle"].jsonTo set[FontStyle]
          # result.tokenColorsC[scope.cstring].fontStyle = settings["fontStyle"].jsonTo set[FontStyle]

proc loadFromString*(input: string, path: string = "string"): Option[Theme] =
  try:
    let json = input.parseJson
    var newTheme = json.jsonToTheme
    newTheme.path = path
    return some(newTheme)
  except CatchableError:
    debugf"Failed to load theme from {path}: {getCurrentExceptionMsg()}"
    debugf"{getCurrentException().getStackTrace()}"
    return Theme.none

proc loadFromFile*(fs: Filesystem, path: string): Option[Theme] =
  try:
    let jsonText = fs.loadApplicationFile(path)
    return loadFromString(jsonText, path)
  except CatchableError:
    debugf"Failed to load theme from {path}: {getCurrentExceptionMsg()}"
    debugf"{getCurrentException().getStackTrace()}"
    return Theme.none


# let theme = loadFromFile("themes/Monokai Pro.json")
# print theme

proc defaultTheme*(): Theme =
  new result
  result.name = "default"
  result.typ = "dark"

  proc parseHexVarTemp(str: string): Color = parseHexVar(str).get(Color())

  result.colors["activityBar.activeFocusBorder"] = parseHexVarTemp "ffd866"
  result.colors["activityBar.background"] = parseHexVarTemp "19181a"
  result.colors["activityBar.border"] = parseHexVarTemp "19181a"
  result.colors["activityBar.foreground"] = parseHexVarTemp "c1c0c0"
  result.colors["activityBar.inactiveForeground"] = parseHexVarTemp "5b595c"
  result.colors["activityBarBadge.background"] = parseHexVarTemp "ffd866"
  result.colors["activityBarBadge.foreground"] = parseHexVarTemp "2d2a2e"
  result.colors["badge.background"] = parseHexVarTemp "ffd866"
  result.colors["badge.foreground"] = parseHexVarTemp "2d2a2e"
  result.colors["banner.background"] = parseHexVarTemp "403e41"
  result.colors["banner.foreground"] = parseHexVarTemp "c1c0c0"
  result.colors["banner.iconForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["breadcrumb.activeSelectionForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["breadcrumb.focusForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["breadcrumb.foreground"] = parseHexVarTemp "939293"
  result.colors["button.background"] = parseHexVarTemp "403e41"
  result.colors["button.foreground"] = parseHexVarTemp "c1c0c0"
  result.colors["button.hoverBackground"] = parseHexVarTemp "5b595c"
  result.colors["button.secondaryBackground"] = parseHexVarTemp "403e41"
  result.colors["button.secondaryForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["button.secondaryHoverBackground"] = parseHexVarTemp "5b595c"
  result.colors["button.separator"] = parseHexVarTemp "2d2a2e"
  result.colors["charts.blue"] = parseHexVarTemp "78dce8"
  result.colors["charts.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["charts.green"] = parseHexVarTemp "a9dc76"
  result.colors["charts.lines"] = parseHexVarTemp "727072"
  result.colors["charts.orange"] = parseHexVarTemp "fc9867"
  result.colors["charts.purple"] = parseHexVarTemp "ab9df2"
  result.colors["charts.red"] = parseHexVarTemp "ff6188"
  result.colors["charts.yellow"] = parseHexVarTemp "ffd866"
  result.colors["checkbox.background"] = parseHexVarTemp "403e41"
  result.colors["checkbox.border"] = parseHexVarTemp "403e41"
  result.colors["checkbox.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["commandCenter.activeBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["commandCenter.activeForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["commandCenter.background"] = parseHexVarTemp "221f22"
  result.colors["commandCenter.border"] = parseHexVarTemp "2d2a2e"
  result.colors["commandCenter.foreground"] = parseHexVarTemp "939293"
  result.colors["debugConsole.errorForeground"] = parseHexVarTemp "ff6188"
  result.colors["debugConsole.infoForeground"] = parseHexVarTemp "78dce8"
  result.colors["debugConsole.sourceForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugConsole.warningForeground"] = parseHexVarTemp "fc9867"
  result.colors["debugConsoleInputIcon.foreground"] = parseHexVarTemp "ffd866"
  result.colors["debugExceptionWidget.background"] = parseHexVarTemp "403e41"
  result.colors["debugExceptionWidget.border"] = parseHexVarTemp "2d2a2e"
  result.colors["debugIcon.breakpointCurrentStackframeForeground"] = parseHexVarTemp "ffd866"
  result.colors["debugIcon.breakpointDisabledForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["debugIcon.breakpointForeground"] = parseHexVarTemp "ff6188"
  result.colors["debugIcon.breakpointStackframeForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.breakpointUnverifiedForeground"] = parseHexVarTemp "fc9867"
  result.colors["debugIcon.continueForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.disconnectForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.pauseForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.restartForeground"] = parseHexVarTemp "a9dc76"
  result.colors["debugIcon.startForeground"] = parseHexVarTemp "a9dc76"
  result.colors["debugIcon.stepBackForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.stepIntoForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.stepOutForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.stepOverForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["debugIcon.stopForeground"] = parseHexVarTemp "ff6188"
  result.colors["debugTokenExpression.boolean"] = parseHexVarTemp "fc9867"
  result.colors["debugTokenExpression.error"] = parseHexVarTemp "ff6188"
  result.colors["debugTokenExpression.name"] = parseHexVarTemp "78dce8"
  result.colors["debugTokenExpression.number"] = parseHexVarTemp "ab9df2"
  result.colors["debugTokenExpression.string"] = parseHexVarTemp "ffd866"
  result.colors["debugTokenExpression.value"] = parseHexVarTemp "fcfcfa"
  result.colors["debugToolBar.background"] = parseHexVarTemp "403e41"
  result.colors["debugView.exceptionLabelBackground"] = parseHexVarTemp "ff6188"
  result.colors["debugView.exceptionLabelForeground"] = parseHexVarTemp "2d2a2e"
  result.colors["debugView.stateLabelBackground"] = parseHexVarTemp "a9dc76"
  result.colors["debugView.stateLabelForeground"] = parseHexVarTemp "2d2a2e"
  result.colors["debugView.valueChangedHighlight"] = parseHexVarTemp "ffd866"
  result.colors["descriptionForeground"] = parseHexVarTemp "939293"
  result.colors["diffEditor.diagonalFill"] = parseHexVarTemp "403e41"
  result.colors["diffEditor.insertedLineBackground"] = parseHexVarTemp "a9dc7619"
  result.colors["diffEditor.insertedTextBackground"] = parseHexVarTemp "a9dc7619"
  result.colors["diffEditor.removedLineBackground"] = parseHexVarTemp "ff618819"
  result.colors["diffEditor.removedTextBackground"] = parseHexVarTemp "ff618819"
  result.colors["diffEditorGutter.insertedLineBackground"] = parseHexVarTemp "a9dc7619"
  result.colors["diffEditorGutter.removedLineBackground"] = parseHexVarTemp "ff618819"
  result.colors["diffEditorOverview.insertedForeground"] = parseHexVarTemp "a9dc76a5"
  result.colors["diffEditorOverview.removedForeground"] = parseHexVarTemp "ff6188a5"
  result.colors["dropdown.background"] = parseHexVarTemp "2d2a2e"
  result.colors["dropdown.border"] = parseHexVarTemp "2d2a2e"
  result.colors["dropdown.foreground"] = parseHexVarTemp "939293"
  result.colors["dropdown.listBackground"] = parseHexVarTemp "403e41"
  result.colors["editor.background"] = parseHexVarTemp "2d2a2e"
  result.colors["editor.findMatchBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editor.findMatchBorder"] = parseHexVarTemp "ffd866"
  result.colors["editor.findMatchHighlightBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editor.findMatchHighlightBorder"] = parseHexVarTemp "00000000"
  result.colors["editor.findRangeHighlightBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["editor.findRangeHighlightBorder"] = parseHexVarTemp "00000000"
  result.colors["editor.focusedStackFrameHighlightBackground"] = parseHexVarTemp "c1c0c026"
  result.colors["editor.foldBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["editor.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["editor.hoverHighlightBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["editor.inactiveSelectionBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["editor.inlineValuesBackground"] = parseHexVarTemp "5b595c"
  result.colors["editor.inlineValuesForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["editor.lineHighlightBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["editor.lineHighlightBorder"] = parseHexVarTemp "00000000"
  result.colors["editor.linkedEditingBackground"] = parseHexVarTemp "403e41"
  result.colors["editor.rangeHighlightBackground"] = parseHexVarTemp "403e41"
  result.colors["editor.rangeHighlightBorder"] = parseHexVarTemp "403e41"
  result.colors["editor.selectionBackground"] = parseHexVarTemp "c1c0c026"
  result.colors["editor.selectionHighlightBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editor.selectionHighlightBorder"] = parseHexVarTemp "00000000"
  result.colors["editor.stackFrameHighlightBackground"] = parseHexVarTemp "c1c0c026"
  result.colors["editor.wordHighlightBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editor.wordHighlightBorder"] = parseHexVarTemp "00000000"
  result.colors["editor.wordHighlightStrongBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editor.wordHighlightStrongBorder"] = parseHexVarTemp "00000000"
  result.colors["editorBracketHighlight.foreground1"] = parseHexVarTemp "ff6188"
  result.colors["editorBracketHighlight.foreground2"] = parseHexVarTemp "fc9867"
  result.colors["editorBracketHighlight.foreground3"] = parseHexVarTemp "ffd866"
  result.colors["editorBracketHighlight.foreground4"] = parseHexVarTemp "a9dc76"
  result.colors["editorBracketHighlight.foreground5"] = parseHexVarTemp "78dce8"
  result.colors["editorBracketHighlight.foreground6"] = parseHexVarTemp "ab9df2"
  result.colors["editorBracketMatch.background"] = parseHexVarTemp "2d2a2e"
  result.colors["editorBracketMatch.border"] = parseHexVarTemp "727072"
  result.colors["editorCodeLens.foreground"] = parseHexVarTemp "727072"
  result.colors["editorCursor.background"] = parseHexVarTemp "2d2a2e"
  result.colors["editorCursor.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["editorError.background"] = parseHexVarTemp "00000000"
  result.colors["editorError.border"] = parseHexVarTemp "00000000"
  result.colors["editorError.foreground"] = parseHexVarTemp "ff6188"
  result.colors["editorGroup.border"] = parseHexVarTemp "221f22"
  result.colors["editorGroup.dropBackground"] = parseHexVarTemp "221f22bf"
  result.colors["editorGroup.emptyBackground"] = parseHexVarTemp "19181a"
  result.colors["editorGroup.focusedEmptyBorder"] = parseHexVarTemp "221f22"
  result.colors["editorGroupHeader.noTabsBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["editorGroupHeader.tabsBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["editorGroupHeader.tabsBorder"] = parseHexVarTemp "2d2a2e"
  result.colors["editorGutter.addedBackground"] = parseHexVarTemp "a9dc76"
  result.colors["editorGutter.background"] = parseHexVarTemp "2d2a2e"
  result.colors["editorGutter.deletedBackground"] = parseHexVarTemp "ff6188"
  result.colors["editorGutter.foldingControlForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["editorGutter.modifiedBackground"] = parseHexVarTemp "fc9867"
  result.colors["editorHint.border"] = parseHexVarTemp "2d2a2e"
  result.colors["editorHint.foreground"] = parseHexVarTemp "ab9df2"
  result.colors["editorHoverWidget.background"] = parseHexVarTemp "403e41"
  result.colors["editorHoverWidget.border"] = parseHexVarTemp "2d2a2e"
  result.colors["editorIndentGuide.background"] = parseHexVarTemp "403e41"
  result.colors["editorInfo.background"] = parseHexVarTemp "00000000"
  result.colors["editorInfo.border"] = parseHexVarTemp "2d2a2e"
  result.colors["editorInfo.foreground"] = parseHexVarTemp "78dce8"
  result.colors["editorLightBulb.foreground"] = parseHexVarTemp "ffd866"
  result.colors["editorLightBulbAutoFix.foreground"] = parseHexVarTemp "a9dc76"
  result.colors["editorLineNumber.activeForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["editorLineNumber.foreground"] = parseHexVarTemp "5b595c"
  result.colors["editorLink.activeForeground"] = parseHexVarTemp "78dce8"
  result.colors["editorMarkerNavigation.background"] = parseHexVarTemp "403e41"
  result.colors["editorMarkerNavigationError.background"] = parseHexVarTemp "ff6188"
  result.colors["editorMarkerNavigationInfo.background"] = parseHexVarTemp "78dce8"
  result.colors["editorMarkerNavigationWarning.background"] = parseHexVarTemp "fc9867"
  result.colors["editorOverviewRuler.addedForeground"] = parseHexVarTemp "a9dc76"
  result.colors["editorOverviewRuler.border"] = parseHexVarTemp "2d2a2e"
  result.colors["editorOverviewRuler.currentContentForeground"] = parseHexVarTemp "403e41"
  result.colors["editorOverviewRuler.deletedForeground"] = parseHexVarTemp "ff6188"
  result.colors["editorOverviewRuler.errorForeground"] = parseHexVarTemp "ff6188"
  result.colors["editorOverviewRuler.findMatchForeground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editorOverviewRuler.incomingContentForeground"] = parseHexVarTemp "403e41"
  result.colors["editorOverviewRuler.infoForeground"] = parseHexVarTemp "78dce8"
  result.colors["editorOverviewRuler.modifiedForeground"] = parseHexVarTemp "fc9867"
  result.colors["editorOverviewRuler.rangeHighlightForeground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editorOverviewRuler.selectionHighlightForeground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editorOverviewRuler.warningForeground"] = parseHexVarTemp "fc9867"
  result.colors["editorOverviewRuler.wordHighlightForeground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editorOverviewRuler.wordHighlightStrongForeground"] = parseHexVarTemp "fcfcfa26"
  result.colors["editorPane.background"] = parseHexVarTemp "2d2a2e"
  result.colors["editorRuler.foreground"] = parseHexVarTemp "5b595c"
  result.colors["editorSuggestWidget.background"] = parseHexVarTemp "403e41"
  result.colors["editorSuggestWidget.border"] = parseHexVarTemp "403e41"
  result.colors["editorSuggestWidget.foreground"] = parseHexVarTemp "c1c0c0"
  result.colors["editorSuggestWidget.highlightForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["editorSuggestWidget.selectedBackground"] = parseHexVarTemp "727072"
  result.colors["editorUnnecessaryCode.opacity"] = parseHexVarTemp "000000a5"
  result.colors["editorWarning.background"] = parseHexVarTemp "00000000"
  result.colors["editorWarning.border"] = parseHexVarTemp "00000000"
  result.colors["editorWarning.foreground"] = parseHexVarTemp "fc9867"
  result.colors["editorWhitespace.foreground"] = parseHexVarTemp "5b595c"
  result.colors["editorWidget.background"] = parseHexVarTemp "403e41"
  result.colors["editorWidget.border"] = parseHexVarTemp "403e41"
  result.colors["errorForeground"] = parseHexVarTemp "ff6188"
  result.colors["extensionBadge.remoteForeground"] = parseHexVarTemp "a9dc76"
  result.colors["extensionButton.prominentBackground"] = parseHexVarTemp "403e41"
  result.colors["extensionButton.prominentForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["extensionButton.prominentHoverBackground"] = parseHexVarTemp "5b595c"
  result.colors["extensionIcon.preReleaseForeground"] = parseHexVarTemp "ab9df2"
  result.colors["extensionIcon.sponsorForeground"] = parseHexVarTemp "78dce8"
  result.colors["extensionIcon.starForeground"] = parseHexVarTemp "ffd866"
  result.colors["extensionIcon.verifiedForeground"] = parseHexVarTemp "a9dc76"
  result.colors["focusBorder"] = parseHexVarTemp "727072"
  result.colors["foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["gitDecoration.addedResourceForeground"] = parseHexVarTemp "a9dc76"
  result.colors["gitDecoration.conflictingResourceForeground"] = parseHexVarTemp "fc9867"
  result.colors["gitDecoration.deletedResourceForeground"] = parseHexVarTemp "ff6188"
  result.colors["gitDecoration.ignoredResourceForeground"] = parseHexVarTemp "5b595c"
  result.colors["gitDecoration.modifiedResourceForeground"] = parseHexVarTemp "ffd866"
  result.colors["gitDecoration.stageDeletedResourceForeground"] = parseHexVarTemp "ff6188"
  result.colors["gitDecoration.stageModifiedResourceForeground"] = parseHexVarTemp "ffd866"
  result.colors["gitDecoration.untrackedResourceForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["icon.foreground"] = parseHexVarTemp "939293"
  result.colors["input.background"] = parseHexVarTemp "403e41"
  result.colors["input.border"] = parseHexVarTemp "403e41"
  result.colors["input.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["input.placeholderForeground"] = parseHexVarTemp "727072"
  result.colors["inputOption.activeBackground"] = parseHexVarTemp "5b595c"
  result.colors["inputOption.activeBorder"] = parseHexVarTemp "5b595c"
  result.colors["inputOption.activeForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["inputOption.hoverBackground"] = parseHexVarTemp "5b595c"
  result.colors["inputValidation.errorBackground"] = parseHexVarTemp "403e41"
  result.colors["inputValidation.errorBorder"] = parseHexVarTemp "ff6188"
  result.colors["inputValidation.errorForeground"] = parseHexVarTemp "ff6188"
  result.colors["inputValidation.infoBackground"] = parseHexVarTemp "403e41"
  result.colors["inputValidation.infoBorder"] = parseHexVarTemp "78dce8"
  result.colors["inputValidation.infoForeground"] = parseHexVarTemp "78dce8"
  result.colors["inputValidation.warningBackground"] = parseHexVarTemp "403e41"
  result.colors["inputValidation.warningBorder"] = parseHexVarTemp "fc9867"
  result.colors["inputValidation.warningForeground"] = parseHexVarTemp "fc9867"
  result.colors["keybindingLabel.background"] = parseHexVarTemp "5b595c"
  result.colors["keybindingLabel.border"] = parseHexVarTemp "5b595c"
  result.colors["keybindingLabel.bottomBorder"] = parseHexVarTemp "403e41"
  result.colors["keybindingLabel.foreground"] = parseHexVarTemp "c1c0c0"
  result.colors["list.activeSelectionBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["list.activeSelectionForeground"] = parseHexVarTemp "ffd866"
  result.colors["list.dropBackground"] = parseHexVarTemp "221f22bf"
  result.colors["list.errorForeground"] = parseHexVarTemp "ff6188"
  result.colors["list.focusBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["list.focusForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["list.highlightForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["list.hoverBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["list.hoverForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["list.inactiveFocusBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["list.inactiveSelectionBackground"] = parseHexVarTemp "c1c0c00c"
  result.colors["list.inactiveSelectionForeground"] = parseHexVarTemp "ffd866"
  result.colors["list.invalidItemForeground"] = parseHexVarTemp "ff6188"
  result.colors["list.warningForeground"] = parseHexVarTemp "fc9867"
  result.colors["listFilterWidget.background"] = parseHexVarTemp "2d2a2e"
  result.colors["listFilterWidget.noMatchesOutline"] = parseHexVarTemp "ff6188"
  result.colors["listFilterWidget.outline"] = parseHexVarTemp "2d2a2e"
  result.colors["menu.background"] = parseHexVarTemp "2d2a2e"
  result.colors["menu.border"] = parseHexVarTemp "221f22"
  result.colors["menu.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["menu.selectionForeground"] = parseHexVarTemp "ffd866"
  result.colors["menu.separatorBackground"] = parseHexVarTemp "403e41"
  result.colors["menubar.selectionForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["merge.border"] = parseHexVarTemp "2d2a2e"
  result.colors["merge.commonContentBackground"] = parseHexVarTemp "fcfcfa19"
  result.colors["merge.commonHeaderBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["merge.currentContentBackground"] = parseHexVarTemp "ff618819"
  result.colors["merge.currentHeaderBackground"] = parseHexVarTemp "ff618826"
  result.colors["merge.incomingContentBackground"] = parseHexVarTemp "a9dc7619"
  result.colors["merge.incomingHeaderBackground"] = parseHexVarTemp "a9dc7626"
  result.colors["mergeEditor.change.background"] = parseHexVarTemp "fcfcfa19"
  result.colors["mergeEditor.change.word.background"] = parseHexVarTemp "fcfcfa19"
  result.colors["mergeEditor.conflict.handled.minimapOverViewRuler"] = parseHexVarTemp "a9dc76"
  result.colors["mergeEditor.conflict.handledFocused.border"] = parseHexVarTemp "a9dc76"
  result.colors["mergeEditor.conflict.handledUnfocused.border"] = parseHexVarTemp "a9dc76"
  result.colors["mergeEditor.conflict.unhandled.minimapOverViewRuler"] = parseHexVarTemp "ff6188"
  result.colors["mergeEditor.conflict.unhandledFocused.border"] = parseHexVarTemp "ff6188"
  result.colors["mergeEditor.conflict.unhandledUnfocused.border"] = parseHexVarTemp "ff6188"
  result.colors["minimap.errorHighlight"] = parseHexVarTemp "ff6188a5"
  result.colors["minimap.findMatchHighlight"] = parseHexVarTemp "939293a5"
  result.colors["minimap.selectionHighlight"] = parseHexVarTemp "c1c0c026"
  result.colors["minimap.selectionOccurrenceHighlight"] = parseHexVarTemp "727072a5"
  result.colors["minimap.warningHighlight"] = parseHexVarTemp "fc9867a5"
  result.colors["minimapGutter.addedBackground"] = parseHexVarTemp "a9dc76"
  result.colors["minimapGutter.deletedBackground"] = parseHexVarTemp "ff6188"
  result.colors["minimapGutter.modifiedBackground"] = parseHexVarTemp "ffd866"
  result.colors["notebook.cellBorderColor"] = parseHexVarTemp "403e41"
  result.colors["notebook.cellEditorBackground"] = parseHexVarTemp "221f227f"
  result.colors["notebook.cellInsertionIndicator"] = parseHexVarTemp "fcfcfa"
  result.colors["notebook.cellStatusBarItemHoverBackground"] = parseHexVarTemp "727072"
  result.colors["notebook.cellToolbarSeparator"] = parseHexVarTemp "403e41"
  result.colors["notebook.editorBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["notebook.focusedEditorBorder"] = parseHexVarTemp "727072"
  result.colors["notebookStatusErrorIcon.foreground"] = parseHexVarTemp "ff6188"
  result.colors["notebookStatusRunningIcon.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["notebookStatusSuccessIcon.foreground"] = parseHexVarTemp "a9dc76"
  result.colors["notificationCenter.border"] = parseHexVarTemp "403e41"
  result.colors["notificationCenterHeader.background"] = parseHexVarTemp "403e41"
  result.colors["notificationCenterHeader.foreground"] = parseHexVarTemp "939293"
  result.colors["notificationLink.foreground"] = parseHexVarTemp "ffd866"
  result.colors["notifications.background"] = parseHexVarTemp "403e41"
  result.colors["notifications.border"] = parseHexVarTemp "403e41"
  result.colors["notifications.foreground"] = parseHexVarTemp "c1c0c0"
  result.colors["notificationsErrorIcon.foreground"] = parseHexVarTemp "ff6188"
  result.colors["notificationsInfoIcon.foreground"] = parseHexVarTemp "78dce8"
  result.colors["notificationsWarningIcon.foreground"] = parseHexVarTemp "fc9867"
  result.colors["notificationToast.border"] = parseHexVarTemp "403e41"
  result.colors["panel.background"] = parseHexVarTemp "403e41"
  result.colors["panel.border"] = parseHexVarTemp "2d2a2e"
  result.colors["panel.dropBackground"] = parseHexVarTemp "221f22bf"
  result.colors["panelTitle.activeBorder"] = parseHexVarTemp "ffd866"
  result.colors["panelTitle.activeForeground"] = parseHexVarTemp "ffd866"
  result.colors["panelTitle.inactiveForeground"] = parseHexVarTemp "939293"
  result.colors["peekView.border"] = parseHexVarTemp "2d2a2e"
  result.colors["peekViewEditor.background"] = parseHexVarTemp "403e41"
  result.colors["peekViewEditor.matchHighlightBackground"] = parseHexVarTemp "5b595c"
  result.colors["peekViewEditorGutter.background"] = parseHexVarTemp "403e41"
  result.colors["peekViewResult.background"] = parseHexVarTemp "403e41"
  result.colors["peekViewResult.fileForeground"] = parseHexVarTemp "939293"
  result.colors["peekViewResult.lineForeground"] = parseHexVarTemp "939293"
  result.colors["peekViewResult.matchHighlightBackground"] = parseHexVarTemp "5b595c"
  result.colors["peekViewResult.selectionBackground"] = parseHexVarTemp "403e41"
  result.colors["peekViewResult.selectionForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["peekViewTitle.background"] = parseHexVarTemp "403e41"
  result.colors["peekViewTitleDescription.foreground"] = parseHexVarTemp "939293"
  result.colors["peekViewTitleLabel.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["pickerGroup.border"] = parseHexVarTemp "2d2a2e"
  result.colors["pickerGroup.foreground"] = parseHexVarTemp "5b595c"
  result.colors["ports.iconRunningProcessForeground"] = parseHexVarTemp "a9dc76"
  result.colors["problemsErrorIcon.foreground"] = parseHexVarTemp "ff6188"
  result.colors["problemsInfoIcon.foreground"] = parseHexVarTemp "78dce8"
  result.colors["problemsWarningIcon.foreground"] = parseHexVarTemp "fc9867"
  result.colors["progressBar.background"] = parseHexVarTemp "403e41"
  result.colors["sash.hoverBorder"] = parseHexVarTemp "727072"
  result.colors["scrollbar.shadow"] = parseHexVarTemp "2d2a2e"
  result.colors["scrollbarSlider.activeBackground"] = parseHexVarTemp "727072"
  result.colors["scrollbarSlider.background"] = parseHexVarTemp "c1c0c026"
  result.colors["scrollbarSlider.hoverBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["selection.background"] = parseHexVarTemp "c1c0c026"
  result.colors["settings.checkboxBackground"] = parseHexVarTemp "403e41"
  result.colors["settings.checkboxBorder"] = parseHexVarTemp "403e41"
  result.colors["settings.checkboxForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["settings.dropdownBackground"] = parseHexVarTemp "403e41"
  result.colors["settings.dropdownBorder"] = parseHexVarTemp "403e41"
  result.colors["settings.dropdownForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["settings.dropdownListBorder"] = parseHexVarTemp "939293"
  result.colors["settings.headerForeground"] = parseHexVarTemp "ffd866"
  result.colors["settings.modifiedItemForeground"] = parseHexVarTemp "ffd866"
  result.colors["settings.modifiedItemIndicator"] = parseHexVarTemp "ffd866"
  result.colors["settings.numberInputBackground"] = parseHexVarTemp "403e41"
  result.colors["settings.numberInputBorder"] = parseHexVarTemp "403e41"
  result.colors["settings.numberInputForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["settings.rowHoverBackground"] = parseHexVarTemp "7270720c"
  result.colors["settings.textInputBackground"] = parseHexVarTemp "403e41"
  result.colors["settings.textInputBorder"] = parseHexVarTemp "403e41"
  result.colors["settings.textInputForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["sideBar.background"] = parseHexVarTemp "221f22"
  result.colors["sideBar.border"] = parseHexVarTemp "19181a"
  result.colors["sideBar.dropBackground"] = parseHexVarTemp "221f22bf"
  result.colors["sideBar.foreground"] = parseHexVarTemp "939293"
  result.colors["sideBarSectionHeader.background"] = parseHexVarTemp "221f22"
  result.colors["sideBarSectionHeader.foreground"] = parseHexVarTemp "727072"
  result.colors["sideBarTitle.foreground"] = parseHexVarTemp "5b595c"
  result.colors["statusBar.background"] = parseHexVarTemp "221f22"
  result.colors["statusBar.border"] = parseHexVarTemp "19181a"
  result.colors["statusBar.debuggingBackground"] = parseHexVarTemp "727072"
  result.colors["statusBar.debuggingBorder"] = parseHexVarTemp "221f22"
  result.colors["statusBar.debuggingForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["statusBar.focusBorder"] = parseHexVarTemp "403e41"
  result.colors["statusBar.foreground"] = parseHexVarTemp "727072"
  result.colors["statusBar.noFolderBackground"] = parseHexVarTemp "221f22"
  result.colors["statusBar.noFolderBorder"] = parseHexVarTemp "19181a"
  result.colors["statusBar.noFolderForeground"] = parseHexVarTemp "727072"
  result.colors["statusBarItem.activeBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["statusBarItem.errorBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["statusBarItem.errorForeground"] = parseHexVarTemp "ff6188"
  result.colors["statusBarItem.focusBorder"] = parseHexVarTemp "727072"
  result.colors["statusBarItem.hoverBackground"] = parseHexVarTemp "fcfcfa0c"
  result.colors["statusBarItem.prominentBackground"] = parseHexVarTemp "403e41"
  result.colors["statusBarItem.prominentHoverBackground"] = parseHexVarTemp "403e41"
  result.colors["statusBarItem.remoteBackground"] = parseHexVarTemp "221f22"
  result.colors["statusBarItem.remoteForeground"] = parseHexVarTemp "a9dc76"
  result.colors["statusBarItem.warningBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["statusBarItem.warningForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.arrayForeground"] = parseHexVarTemp "ff6188"
  result.colors["symbolIcon.booleanForeground"] = parseHexVarTemp "ff6188"
  result.colors["symbolIcon.classForeground"] = parseHexVarTemp "78dce8"
  result.colors["symbolIcon.colorForeground"] = parseHexVarTemp "ab9df2"
  result.colors["symbolIcon.constantForeground"] = parseHexVarTemp "ab9df2"
  result.colors["symbolIcon.constructorForeground"] = parseHexVarTemp "a9dc76"
  result.colors["symbolIcon.enumeratorForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.enumeratorMemberForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.eventForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.fieldForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.fileForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["symbolIcon.folderForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["symbolIcon.functionForeground"] = parseHexVarTemp "a9dc76"
  result.colors["symbolIcon.interfaceForeground"] = parseHexVarTemp "78dce8"
  result.colors["symbolIcon.keyForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.keywordForeground"] = parseHexVarTemp "ff6188"
  result.colors["symbolIcon.methodForeground"] = parseHexVarTemp "a9dc76"
  result.colors["symbolIcon.moduleForeground"] = parseHexVarTemp "78dce8"
  result.colors["symbolIcon.namespaceForeground"] = parseHexVarTemp "78dce8"
  result.colors["symbolIcon.nullForeground"] = parseHexVarTemp "ab9df2"
  result.colors["symbolIcon.numberForeground"] = parseHexVarTemp "ab9df2"
  result.colors["symbolIcon.objectForeground"] = parseHexVarTemp "78dce8"
  result.colors["symbolIcon.operatorForeground"] = parseHexVarTemp "ff6188"
  result.colors["symbolIcon.packageForeground"] = parseHexVarTemp "ab9df2"
  result.colors["symbolIcon.propertyForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.referenceForeground"] = parseHexVarTemp "ab9df2"
  result.colors["symbolIcon.snippetForeground"] = parseHexVarTemp "a9dc76"
  result.colors["symbolIcon.stringForeground"] = parseHexVarTemp "ffd866"
  result.colors["symbolIcon.structForeground"] = parseHexVarTemp "ff6188"
  result.colors["symbolIcon.textForeground"] = parseHexVarTemp "ffd866"
  result.colors["symbolIcon.typeParameterForeground"] = parseHexVarTemp "fc9867"
  result.colors["symbolIcon.unitForeground"] = parseHexVarTemp "ab9df2"
  result.colors["symbolIcon.variableForeground"] = parseHexVarTemp "78dce8"
  result.colors["tab.activeBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["tab.activeBorder"] = parseHexVarTemp "ffd866"
  result.colors["tab.activeForeground"] = parseHexVarTemp "ffd866"
  result.colors["tab.activeModifiedBorder"] = parseHexVarTemp "5b595c"
  result.colors["tab.border"] = parseHexVarTemp "2d2a2e"
  result.colors["tab.hoverBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["tab.hoverBorder"] = parseHexVarTemp "5b595c"
  result.colors["tab.hoverForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["tab.inactiveBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["tab.inactiveForeground"] = parseHexVarTemp "939293"
  result.colors["tab.inactiveModifiedBorder"] = parseHexVarTemp "5b595c"
  result.colors["tab.lastPinnedBorder"] = parseHexVarTemp "5b595c"
  result.colors["tab.unfocusedActiveBorder"] = parseHexVarTemp "939293"
  result.colors["tab.unfocusedActiveForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["tab.unfocusedActiveModifiedBorder"] = parseHexVarTemp "403e41"
  result.colors["tab.unfocusedHoverBackground"] = parseHexVarTemp "2d2a2e"
  result.colors["tab.unfocusedHoverBorder"] = parseHexVarTemp "2d2a2e"
  result.colors["tab.unfocusedHoverForeground"] = parseHexVarTemp "c1c0c0"
  result.colors["tab.unfocusedInactiveForeground"] = parseHexVarTemp "939293"
  result.colors["tab.unfocusedInactiveModifiedBorder"] = parseHexVarTemp "403e41"
  result.colors["terminal.ansiBlack"] = parseHexVarTemp "403e41"
  result.colors["terminal.ansiBlue"] = parseHexVarTemp "fc9867"
  result.colors["terminal.ansiBrightBlack"] = parseHexVarTemp "727072"
  result.colors["terminal.ansiBrightBlue"] = parseHexVarTemp "fc9867"
  result.colors["terminal.ansiBrightCyan"] = parseHexVarTemp "78dce8"
  result.colors["terminal.ansiBrightGreen"] = parseHexVarTemp "a9dc76"
  result.colors["terminal.ansiBrightMagenta"] = parseHexVarTemp "ab9df2"
  result.colors["terminal.ansiBrightRed"] = parseHexVarTemp "ff6188"
  result.colors["terminal.ansiBrightWhite"] = parseHexVarTemp "fcfcfa"
  result.colors["terminal.ansiBrightYellow"] = parseHexVarTemp "ffd866"
  result.colors["terminal.ansiCyan"] = parseHexVarTemp "78dce8"
  result.colors["terminal.ansiGreen"] = parseHexVarTemp "a9dc76"
  result.colors["terminal.ansiMagenta"] = parseHexVarTemp "ab9df2"
  result.colors["terminal.ansiRed"] = parseHexVarTemp "ff6188"
  result.colors["terminal.ansiWhite"] = parseHexVarTemp "fcfcfa"
  result.colors["terminal.ansiYellow"] = parseHexVarTemp "ffd866"
  result.colors["terminal.background"] = parseHexVarTemp "403e41"
  result.colors["terminal.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["terminal.selectionBackground"] = parseHexVarTemp "fcfcfa26"
  result.colors["terminalCommandDecoration.defaultBackground"] = parseHexVarTemp "fcfcfa"
  result.colors["terminalCommandDecoration.errorBackground"] = parseHexVarTemp "ff6188"
  result.colors["terminalCommandDecoration.successBackground"] = parseHexVarTemp "a9dc76"
  result.colors["terminalCursor.background"] = parseHexVarTemp "00000000"
  result.colors["terminalCursor.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["testing.iconErrored"] = parseHexVarTemp "ff6188"
  result.colors["testing.iconFailed"] = parseHexVarTemp "ff6188"
  result.colors["testing.iconPassed"] = parseHexVarTemp "a9dc76"
  result.colors["testing.iconQueued"] = parseHexVarTemp "fcfcfa"
  result.colors["testing.iconSkipped"] = parseHexVarTemp "fc9867"
  result.colors["testing.iconUnset"] = parseHexVarTemp "939293"
  result.colors["testing.message.error.decorationForeground"] = parseHexVarTemp "ff6188"
  result.colors["testing.message.error.lineBackground"] = parseHexVarTemp "ff618819"
  result.colors["testing.message.info.decorationForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["testing.message.info.lineBackground"] = parseHexVarTemp "fcfcfa19"
  result.colors["testing.runAction"] = parseHexVarTemp "ffd866"
  result.colors["textBlockQuote.background"] = parseHexVarTemp "403e41"
  result.colors["textBlockQuote.border"] = parseHexVarTemp "403e41"
  result.colors["textCodeBlock.background"] = parseHexVarTemp "403e41"
  result.colors["textLink.activeForeground"] = parseHexVarTemp "fcfcfa"
  result.colors["textLink.foreground"] = parseHexVarTemp "ffd866"
  result.colors["textPreformat.foreground"] = parseHexVarTemp "fcfcfa"
  result.colors["textSeparator.foreground"] = parseHexVarTemp "727072"
  result.colors["titleBar.activeBackground"] = parseHexVarTemp "221f22"
  result.colors["titleBar.activeForeground"] = parseHexVarTemp "939293"
  result.colors["titleBar.border"] = parseHexVarTemp "19181a"
  result.colors["titleBar.inactiveBackground"] = parseHexVarTemp "221f22"
  result.colors["titleBar.inactiveForeground"] = parseHexVarTemp "5b595c"
  result.colors["walkThrough.embeddedEditorBackground"] = parseHexVarTemp "221f22"
  result.colors["welcomePage.buttonBackground"] = parseHexVarTemp "403e41"
  result.colors["welcomePage.buttonHoverBackground"] = parseHexVarTemp "5b595c"
  result.colors["welcomePage.progress.background"] = parseHexVarTemp "727072"
  result.colors["welcomePage.progress.foreground"] = parseHexVarTemp "939293"
  result.colors["welcomePage.tileBackground"] = parseHexVarTemp "403e41"
  result.colors["welcomePage.tileHoverBackground"] = parseHexVarTemp "5b595c"
  result.colors["welcomePage.tileShadow"] = parseHexVarTemp "19181a"
  result.colors["widget.shadow"] = parseHexVarTemp "19181a"

  result.tokenColors["comment"] = Style(foreground: some(parseHexVarTemp "727072"), fontStyle: {Italic})