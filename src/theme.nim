import std/[json, tables, strutils, options]
import chroma
import custom_logger, platform/[filesystem]
import myjsonutils

logCategory "theme"

type
  FontStyle* = enum Italic, Underline, Bold
  Style* = object
    foreground*: Option[Color]
    background*: Option[Color]
    fontStyle*: set[FontStyle]

when defined(js):
  import std/[jsffi]
  type StyleCache = distinct JsObject
else:
  type StyleCache = distinct object

type
  Theme* = ref object
    path*: string
    name*: string
    typ*: string
    colorSpace*: string
    colors*: Table[string, Color]
    tokenColors*: Table[string, Style]
    tokenStyleCache: StyleCache

proc parseHexVar*(text: string): Color =
  let offset = if text.startsWith "#": 1 else: 0
  if text.len == 6 + offset:
    return parseHex text[offset..^1]
  elif text.len == 8 + offset:
    return parseHexAlpha text[offset..^1]
  elif text.len == 3 + offset:
    return parseHtmlHexTiny ("#" & text[offset..^1])
  elif text.len == 4 + offset:
    result = parseHtmlHexTiny ("#" & text[offset..^2])
    result.a = parseHexInt(text[^1..^1]).float32 / 255
    return
  echo "Failed to parse hex color '", text, "'"
  assert false
  return Color()

proc getCascading[T](table: var Table[string, T], key: string, default: T): T =
  if table.contains(key):
    return table[key]
  let index = key.rfind(".")
  if index != -1:
    return table.getCascading(key[0..<index], default)
  return default

proc color*(theme: Theme, name: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return theme.colors.getCascading(name, default.color)

proc color*(theme: Theme, names: seq[string], default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  for name in names:
    if theme.colors.contains(name):
      return theme.colors[name]
  return default.color

proc newStyleCache(): StyleCache =
  when defined(js):
    return newJsObject().StyleCache

proc contains(cache: StyleCache, name: cstring): bool =
  result = false
  when defined(js):
    proc impl(cache: StyleCache, name: cstring): bool {.importjs: "#[#] != null".}
    return impl(cache, name)

proc containsEmpty(cache: StyleCache, name: cstring): bool =
  result = false
  when defined(js):
    proc impl(cache: StyleCache, name: cstring): bool {.importjs: "#[#] === null".}
    return impl(cache, name)

proc `[]=`(cache: var StyleCache, name: cstring, value: Color) =
  when defined(js):
    proc impl(cache: StyleCache, name: cstring, value: Color) {.importjs: "#[#] = #;".}
    impl(cache, name, value)

proc addEmpty(cache: var StyleCache, name: cstring) =
  when defined(js):
    proc impl(cache: StyleCache, name: cstring) {.importjs: "#[#] = null;".}
    impl(cache, name)

proc `[]`(cache: StyleCache, name: cstring): Color =
  when defined(js):
    proc impl(cache: StyleCache, name: cstring): Color {.importjs: "#[#]".}
    return impl(cache, name)

proc tokenColor*(theme: Theme, name: cstring, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  if theme.tokenStyleCache.contains(name):
    return theme.tokenStyleCache[name]
  if theme.tokenStyleCache.containsEmpty(name):
    return default.color

  let res = theme.tokenColors.getCascading($name, Style()).foreground
  if res.isSome:
    theme.tokenStyleCache[name] = res.get
  else:
    theme.tokenStyleCache.addEmpty(name)

  return res.get default.color

proc tokenColor*(theme: Theme, name: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return theme.tokenColors.getCascading(name, Style()).foreground.get default.color

proc tokenColor*(theme: Theme, names: seq[string], default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  for name in names:
    if theme.tokenColors.contains(name):
      let style = theme.tokenColors[name]
      if style.foreground.isSome:
        return style.foreground.get
  return default.color

proc anyColor*(theme: Theme, names: seq[string], default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  for name in names:
    if name.startsWith "#":
      return parseHexVar name
    elif name.startsWith("&") and theme.colors.contains(name[1..^1]):
      return theme.colors[name[1..^1]]
    elif theme.tokenColors.contains(name):
      let style = theme.tokenColors[name]
      if style.foreground.isSome:
        return style.foreground.get

  return default.color

proc tokenBackgroundColor*(theme: Theme, name: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return (theme.tokenColors.getCascading(name, Style())).background.get default.color

proc tokenFontStyle*(theme: Theme, name: string): set[FontStyle] =
  return (theme.tokenColors.getCascading(name, Style(fontStyle: {}))).fontStyle

proc tokenFontStyle*(theme: Theme, names: seq[string]): set[FontStyle] =
  for name in names:
    if theme.tokenColors.contains(name):
      return theme.tokenColors[name].fontStyle
  return {}

proc anyColor*(theme: Theme, color: string, default: Color = Color(r: 0, g: 0, b: 0, a: 1)): Color =
  return if color.startsWith "#":
    parseHexVar color
  elif color.startsWith "&":
    theme.color(color[1..^1], default)
  else:
    theme.tokenColor(color, default)

proc fromJsonHook*(color: var Color, jsonNode: JsonNode) =
  if jsonNode.kind == JNull:
    color = parseHex "000000"
    return

  color = parseHexVar jsonNode.str

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
  result.tokenStyleCache = newStyleCache()
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

proc loadFromFile*(path: string): Option[Theme] =
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
  result.tokenStyleCache = newStyleCache()
  result.name = "default"
  result.typ = "dark"

  result.colors["activityBar.activeFocusBorder"] = parseHexVar "ffd866"
  result.colors["activityBar.background"] = parseHexVar "19181a"
  result.colors["activityBar.border"] = parseHexVar "19181a"
  result.colors["activityBar.foreground"] = parseHexVar "c1c0c0"
  result.colors["activityBar.inactiveForeground"] = parseHexVar "5b595c"
  result.colors["activityBarBadge.background"] = parseHexVar "ffd866"
  result.colors["activityBarBadge.foreground"] = parseHexVar "2d2a2e"
  result.colors["badge.background"] = parseHexVar "ffd866"
  result.colors["badge.foreground"] = parseHexVar "2d2a2e"
  result.colors["banner.background"] = parseHexVar "403e41"
  result.colors["banner.foreground"] = parseHexVar "c1c0c0"
  result.colors["banner.iconForeground"] = parseHexVar "c1c0c0"
  result.colors["breadcrumb.activeSelectionForeground"] = parseHexVar "fcfcfa"
  result.colors["breadcrumb.focusForeground"] = parseHexVar "c1c0c0"
  result.colors["breadcrumb.foreground"] = parseHexVar "939293"
  result.colors["button.background"] = parseHexVar "403e41"
  result.colors["button.foreground"] = parseHexVar "c1c0c0"
  result.colors["button.hoverBackground"] = parseHexVar "5b595c"
  result.colors["button.secondaryBackground"] = parseHexVar "403e41"
  result.colors["button.secondaryForeground"] = parseHexVar "c1c0c0"
  result.colors["button.secondaryHoverBackground"] = parseHexVar "5b595c"
  result.colors["button.separator"] = parseHexVar "2d2a2e"
  result.colors["charts.blue"] = parseHexVar "78dce8"
  result.colors["charts.foreground"] = parseHexVar "fcfcfa"
  result.colors["charts.green"] = parseHexVar "a9dc76"
  result.colors["charts.lines"] = parseHexVar "727072"
  result.colors["charts.orange"] = parseHexVar "fc9867"
  result.colors["charts.purple"] = parseHexVar "ab9df2"
  result.colors["charts.red"] = parseHexVar "ff6188"
  result.colors["charts.yellow"] = parseHexVar "ffd866"
  result.colors["checkbox.background"] = parseHexVar "403e41"
  result.colors["checkbox.border"] = parseHexVar "403e41"
  result.colors["checkbox.foreground"] = parseHexVar "fcfcfa"
  result.colors["commandCenter.activeBackground"] = parseHexVar "2d2a2e"
  result.colors["commandCenter.activeForeground"] = parseHexVar "c1c0c0"
  result.colors["commandCenter.background"] = parseHexVar "221f22"
  result.colors["commandCenter.border"] = parseHexVar "2d2a2e"
  result.colors["commandCenter.foreground"] = parseHexVar "939293"
  result.colors["debugConsole.errorForeground"] = parseHexVar "ff6188"
  result.colors["debugConsole.infoForeground"] = parseHexVar "78dce8"
  result.colors["debugConsole.sourceForeground"] = parseHexVar "fcfcfa"
  result.colors["debugConsole.warningForeground"] = parseHexVar "fc9867"
  result.colors["debugConsoleInputIcon.foreground"] = parseHexVar "ffd866"
  result.colors["debugExceptionWidget.background"] = parseHexVar "403e41"
  result.colors["debugExceptionWidget.border"] = parseHexVar "2d2a2e"
  result.colors["debugIcon.breakpointCurrentStackframeForeground"] = parseHexVar "ffd866"
  result.colors["debugIcon.breakpointDisabledForeground"] = parseHexVar "c1c0c0"
  result.colors["debugIcon.breakpointForeground"] = parseHexVar "ff6188"
  result.colors["debugIcon.breakpointStackframeForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.breakpointUnverifiedForeground"] = parseHexVar "fc9867"
  result.colors["debugIcon.continueForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.disconnectForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.pauseForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.restartForeground"] = parseHexVar "a9dc76"
  result.colors["debugIcon.startForeground"] = parseHexVar "a9dc76"
  result.colors["debugIcon.stepBackForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.stepIntoForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.stepOutForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.stepOverForeground"] = parseHexVar "fcfcfa"
  result.colors["debugIcon.stopForeground"] = parseHexVar "ff6188"
  result.colors["debugTokenExpression.boolean"] = parseHexVar "fc9867"
  result.colors["debugTokenExpression.error"] = parseHexVar "ff6188"
  result.colors["debugTokenExpression.name"] = parseHexVar "78dce8"
  result.colors["debugTokenExpression.number"] = parseHexVar "ab9df2"
  result.colors["debugTokenExpression.string"] = parseHexVar "ffd866"
  result.colors["debugTokenExpression.value"] = parseHexVar "fcfcfa"
  result.colors["debugToolBar.background"] = parseHexVar "403e41"
  result.colors["debugView.exceptionLabelBackground"] = parseHexVar "ff6188"
  result.colors["debugView.exceptionLabelForeground"] = parseHexVar "2d2a2e"
  result.colors["debugView.stateLabelBackground"] = parseHexVar "a9dc76"
  result.colors["debugView.stateLabelForeground"] = parseHexVar "2d2a2e"
  result.colors["debugView.valueChangedHighlight"] = parseHexVar "ffd866"
  result.colors["descriptionForeground"] = parseHexVar "939293"
  result.colors["diffEditor.diagonalFill"] = parseHexVar "403e41"
  result.colors["diffEditor.insertedLineBackground"] = parseHexVar "a9dc7619"
  result.colors["diffEditor.insertedTextBackground"] = parseHexVar "a9dc7619"
  result.colors["diffEditor.removedLineBackground"] = parseHexVar "ff618819"
  result.colors["diffEditor.removedTextBackground"] = parseHexVar "ff618819"
  result.colors["diffEditorGutter.insertedLineBackground"] = parseHexVar "a9dc7619"
  result.colors["diffEditorGutter.removedLineBackground"] = parseHexVar "ff618819"
  result.colors["diffEditorOverview.insertedForeground"] = parseHexVar "a9dc76a5"
  result.colors["diffEditorOverview.removedForeground"] = parseHexVar "ff6188a5"
  result.colors["dropdown.background"] = parseHexVar "2d2a2e"
  result.colors["dropdown.border"] = parseHexVar "2d2a2e"
  result.colors["dropdown.foreground"] = parseHexVar "939293"
  result.colors["dropdown.listBackground"] = parseHexVar "403e41"
  result.colors["editor.background"] = parseHexVar "2d2a2e"
  result.colors["editor.findMatchBackground"] = parseHexVar "fcfcfa26"
  result.colors["editor.findMatchBorder"] = parseHexVar "ffd866"
  result.colors["editor.findMatchHighlightBackground"] = parseHexVar "fcfcfa26"
  result.colors["editor.findMatchHighlightBorder"] = parseHexVar "00000000"
  result.colors["editor.findRangeHighlightBackground"] = parseHexVar "fcfcfa0c"
  result.colors["editor.findRangeHighlightBorder"] = parseHexVar "00000000"
  result.colors["editor.focusedStackFrameHighlightBackground"] = parseHexVar "c1c0c026"
  result.colors["editor.foldBackground"] = parseHexVar "fcfcfa0c"
  result.colors["editor.foreground"] = parseHexVar "fcfcfa"
  result.colors["editor.hoverHighlightBackground"] = parseHexVar "fcfcfa0c"
  result.colors["editor.inactiveSelectionBackground"] = parseHexVar "fcfcfa0c"
  result.colors["editor.inlineValuesBackground"] = parseHexVar "5b595c"
  result.colors["editor.inlineValuesForeground"] = parseHexVar "c1c0c0"
  result.colors["editor.lineHighlightBackground"] = parseHexVar "fcfcfa0c"
  result.colors["editor.lineHighlightBorder"] = parseHexVar "00000000"
  result.colors["editor.linkedEditingBackground"] = parseHexVar "403e41"
  result.colors["editor.rangeHighlightBackground"] = parseHexVar "403e41"
  result.colors["editor.rangeHighlightBorder"] = parseHexVar "403e41"
  result.colors["editor.selectionBackground"] = parseHexVar "c1c0c026"
  result.colors["editor.selectionHighlightBackground"] = parseHexVar "fcfcfa26"
  result.colors["editor.selectionHighlightBorder"] = parseHexVar "00000000"
  result.colors["editor.stackFrameHighlightBackground"] = parseHexVar "c1c0c026"
  result.colors["editor.wordHighlightBackground"] = parseHexVar "fcfcfa26"
  result.colors["editor.wordHighlightBorder"] = parseHexVar "00000000"
  result.colors["editor.wordHighlightStrongBackground"] = parseHexVar "fcfcfa26"
  result.colors["editor.wordHighlightStrongBorder"] = parseHexVar "00000000"
  result.colors["editorBracketHighlight.foreground1"] = parseHexVar "ff6188"
  result.colors["editorBracketHighlight.foreground2"] = parseHexVar "fc9867"
  result.colors["editorBracketHighlight.foreground3"] = parseHexVar "ffd866"
  result.colors["editorBracketHighlight.foreground4"] = parseHexVar "a9dc76"
  result.colors["editorBracketHighlight.foreground5"] = parseHexVar "78dce8"
  result.colors["editorBracketHighlight.foreground6"] = parseHexVar "ab9df2"
  result.colors["editorBracketMatch.background"] = parseHexVar "2d2a2e"
  result.colors["editorBracketMatch.border"] = parseHexVar "727072"
  result.colors["editorCodeLens.foreground"] = parseHexVar "727072"
  result.colors["editorCursor.background"] = parseHexVar "2d2a2e"
  result.colors["editorCursor.foreground"] = parseHexVar "fcfcfa"
  result.colors["editorError.background"] = parseHexVar "00000000"
  result.colors["editorError.border"] = parseHexVar "00000000"
  result.colors["editorError.foreground"] = parseHexVar "ff6188"
  result.colors["editorGroup.border"] = parseHexVar "221f22"
  result.colors["editorGroup.dropBackground"] = parseHexVar "221f22bf"
  result.colors["editorGroup.emptyBackground"] = parseHexVar "19181a"
  result.colors["editorGroup.focusedEmptyBorder"] = parseHexVar "221f22"
  result.colors["editorGroupHeader.noTabsBackground"] = parseHexVar "2d2a2e"
  result.colors["editorGroupHeader.tabsBackground"] = parseHexVar "2d2a2e"
  result.colors["editorGroupHeader.tabsBorder"] = parseHexVar "2d2a2e"
  result.colors["editorGutter.addedBackground"] = parseHexVar "a9dc76"
  result.colors["editorGutter.background"] = parseHexVar "2d2a2e"
  result.colors["editorGutter.deletedBackground"] = parseHexVar "ff6188"
  result.colors["editorGutter.foldingControlForeground"] = parseHexVar "c1c0c0"
  result.colors["editorGutter.modifiedBackground"] = parseHexVar "fc9867"
  result.colors["editorHint.border"] = parseHexVar "2d2a2e"
  result.colors["editorHint.foreground"] = parseHexVar "ab9df2"
  result.colors["editorHoverWidget.background"] = parseHexVar "403e41"
  result.colors["editorHoverWidget.border"] = parseHexVar "2d2a2e"
  result.colors["editorIndentGuide.background"] = parseHexVar "403e41"
  result.colors["editorInfo.background"] = parseHexVar "00000000"
  result.colors["editorInfo.border"] = parseHexVar "2d2a2e"
  result.colors["editorInfo.foreground"] = parseHexVar "78dce8"
  result.colors["editorLightBulb.foreground"] = parseHexVar "ffd866"
  result.colors["editorLightBulbAutoFix.foreground"] = parseHexVar "a9dc76"
  result.colors["editorLineNumber.activeForeground"] = parseHexVar "c1c0c0"
  result.colors["editorLineNumber.foreground"] = parseHexVar "5b595c"
  result.colors["editorLink.activeForeground"] = parseHexVar "78dce8"
  result.colors["editorMarkerNavigation.background"] = parseHexVar "403e41"
  result.colors["editorMarkerNavigationError.background"] = parseHexVar "ff6188"
  result.colors["editorMarkerNavigationInfo.background"] = parseHexVar "78dce8"
  result.colors["editorMarkerNavigationWarning.background"] = parseHexVar "fc9867"
  result.colors["editorOverviewRuler.addedForeground"] = parseHexVar "a9dc76"
  result.colors["editorOverviewRuler.border"] = parseHexVar "2d2a2e"
  result.colors["editorOverviewRuler.currentContentForeground"] = parseHexVar "403e41"
  result.colors["editorOverviewRuler.deletedForeground"] = parseHexVar "ff6188"
  result.colors["editorOverviewRuler.errorForeground"] = parseHexVar "ff6188"
  result.colors["editorOverviewRuler.findMatchForeground"] = parseHexVar "fcfcfa26"
  result.colors["editorOverviewRuler.incomingContentForeground"] = parseHexVar "403e41"
  result.colors["editorOverviewRuler.infoForeground"] = parseHexVar "78dce8"
  result.colors["editorOverviewRuler.modifiedForeground"] = parseHexVar "fc9867"
  result.colors["editorOverviewRuler.rangeHighlightForeground"] = parseHexVar "fcfcfa26"
  result.colors["editorOverviewRuler.selectionHighlightForeground"] = parseHexVar "fcfcfa26"
  result.colors["editorOverviewRuler.warningForeground"] = parseHexVar "fc9867"
  result.colors["editorOverviewRuler.wordHighlightForeground"] = parseHexVar "fcfcfa26"
  result.colors["editorOverviewRuler.wordHighlightStrongForeground"] = parseHexVar "fcfcfa26"
  result.colors["editorPane.background"] = parseHexVar "2d2a2e"
  result.colors["editorRuler.foreground"] = parseHexVar "5b595c"
  result.colors["editorSuggestWidget.background"] = parseHexVar "403e41"
  result.colors["editorSuggestWidget.border"] = parseHexVar "403e41"
  result.colors["editorSuggestWidget.foreground"] = parseHexVar "c1c0c0"
  result.colors["editorSuggestWidget.highlightForeground"] = parseHexVar "fcfcfa"
  result.colors["editorSuggestWidget.selectedBackground"] = parseHexVar "727072"
  result.colors["editorUnnecessaryCode.opacity"] = parseHexVar "000000a5"
  result.colors["editorWarning.background"] = parseHexVar "00000000"
  result.colors["editorWarning.border"] = parseHexVar "00000000"
  result.colors["editorWarning.foreground"] = parseHexVar "fc9867"
  result.colors["editorWhitespace.foreground"] = parseHexVar "5b595c"
  result.colors["editorWidget.background"] = parseHexVar "403e41"
  result.colors["editorWidget.border"] = parseHexVar "403e41"
  result.colors["errorForeground"] = parseHexVar "ff6188"
  result.colors["extensionBadge.remoteForeground"] = parseHexVar "a9dc76"
  result.colors["extensionButton.prominentBackground"] = parseHexVar "403e41"
  result.colors["extensionButton.prominentForeground"] = parseHexVar "fcfcfa"
  result.colors["extensionButton.prominentHoverBackground"] = parseHexVar "5b595c"
  result.colors["extensionIcon.preReleaseForeground"] = parseHexVar "ab9df2"
  result.colors["extensionIcon.sponsorForeground"] = parseHexVar "78dce8"
  result.colors["extensionIcon.starForeground"] = parseHexVar "ffd866"
  result.colors["extensionIcon.verifiedForeground"] = parseHexVar "a9dc76"
  result.colors["focusBorder"] = parseHexVar "727072"
  result.colors["foreground"] = parseHexVar "fcfcfa"
  result.colors["gitDecoration.addedResourceForeground"] = parseHexVar "a9dc76"
  result.colors["gitDecoration.conflictingResourceForeground"] = parseHexVar "fc9867"
  result.colors["gitDecoration.deletedResourceForeground"] = parseHexVar "ff6188"
  result.colors["gitDecoration.ignoredResourceForeground"] = parseHexVar "5b595c"
  result.colors["gitDecoration.modifiedResourceForeground"] = parseHexVar "ffd866"
  result.colors["gitDecoration.stageDeletedResourceForeground"] = parseHexVar "ff6188"
  result.colors["gitDecoration.stageModifiedResourceForeground"] = parseHexVar "ffd866"
  result.colors["gitDecoration.untrackedResourceForeground"] = parseHexVar "c1c0c0"
  result.colors["icon.foreground"] = parseHexVar "939293"
  result.colors["input.background"] = parseHexVar "403e41"
  result.colors["input.border"] = parseHexVar "403e41"
  result.colors["input.foreground"] = parseHexVar "fcfcfa"
  result.colors["input.placeholderForeground"] = parseHexVar "727072"
  result.colors["inputOption.activeBackground"] = parseHexVar "5b595c"
  result.colors["inputOption.activeBorder"] = parseHexVar "5b595c"
  result.colors["inputOption.activeForeground"] = parseHexVar "fcfcfa"
  result.colors["inputOption.hoverBackground"] = parseHexVar "5b595c"
  result.colors["inputValidation.errorBackground"] = parseHexVar "403e41"
  result.colors["inputValidation.errorBorder"] = parseHexVar "ff6188"
  result.colors["inputValidation.errorForeground"] = parseHexVar "ff6188"
  result.colors["inputValidation.infoBackground"] = parseHexVar "403e41"
  result.colors["inputValidation.infoBorder"] = parseHexVar "78dce8"
  result.colors["inputValidation.infoForeground"] = parseHexVar "78dce8"
  result.colors["inputValidation.warningBackground"] = parseHexVar "403e41"
  result.colors["inputValidation.warningBorder"] = parseHexVar "fc9867"
  result.colors["inputValidation.warningForeground"] = parseHexVar "fc9867"
  result.colors["keybindingLabel.background"] = parseHexVar "5b595c"
  result.colors["keybindingLabel.border"] = parseHexVar "5b595c"
  result.colors["keybindingLabel.bottomBorder"] = parseHexVar "403e41"
  result.colors["keybindingLabel.foreground"] = parseHexVar "c1c0c0"
  result.colors["list.activeSelectionBackground"] = parseHexVar "fcfcfa0c"
  result.colors["list.activeSelectionForeground"] = parseHexVar "ffd866"
  result.colors["list.dropBackground"] = parseHexVar "221f22bf"
  result.colors["list.errorForeground"] = parseHexVar "ff6188"
  result.colors["list.focusBackground"] = parseHexVar "2d2a2e"
  result.colors["list.focusForeground"] = parseHexVar "fcfcfa"
  result.colors["list.highlightForeground"] = parseHexVar "fcfcfa"
  result.colors["list.hoverBackground"] = parseHexVar "fcfcfa0c"
  result.colors["list.hoverForeground"] = parseHexVar "fcfcfa"
  result.colors["list.inactiveFocusBackground"] = parseHexVar "2d2a2e"
  result.colors["list.inactiveSelectionBackground"] = parseHexVar "c1c0c00c"
  result.colors["list.inactiveSelectionForeground"] = parseHexVar "ffd866"
  result.colors["list.invalidItemForeground"] = parseHexVar "ff6188"
  result.colors["list.warningForeground"] = parseHexVar "fc9867"
  result.colors["listFilterWidget.background"] = parseHexVar "2d2a2e"
  result.colors["listFilterWidget.noMatchesOutline"] = parseHexVar "ff6188"
  result.colors["listFilterWidget.outline"] = parseHexVar "2d2a2e"
  result.colors["menu.background"] = parseHexVar "2d2a2e"
  result.colors["menu.border"] = parseHexVar "221f22"
  result.colors["menu.foreground"] = parseHexVar "fcfcfa"
  result.colors["menu.selectionForeground"] = parseHexVar "ffd866"
  result.colors["menu.separatorBackground"] = parseHexVar "403e41"
  result.colors["menubar.selectionForeground"] = parseHexVar "fcfcfa"
  result.colors["merge.border"] = parseHexVar "2d2a2e"
  result.colors["merge.commonContentBackground"] = parseHexVar "fcfcfa19"
  result.colors["merge.commonHeaderBackground"] = parseHexVar "fcfcfa26"
  result.colors["merge.currentContentBackground"] = parseHexVar "ff618819"
  result.colors["merge.currentHeaderBackground"] = parseHexVar "ff618826"
  result.colors["merge.incomingContentBackground"] = parseHexVar "a9dc7619"
  result.colors["merge.incomingHeaderBackground"] = parseHexVar "a9dc7626"
  result.colors["mergeEditor.change.background"] = parseHexVar "fcfcfa19"
  result.colors["mergeEditor.change.word.background"] = parseHexVar "fcfcfa19"
  result.colors["mergeEditor.conflict.handled.minimapOverViewRuler"] = parseHexVar "a9dc76"
  result.colors["mergeEditor.conflict.handledFocused.border"] = parseHexVar "a9dc76"
  result.colors["mergeEditor.conflict.handledUnfocused.border"] = parseHexVar "a9dc76"
  result.colors["mergeEditor.conflict.unhandled.minimapOverViewRuler"] = parseHexVar "ff6188"
  result.colors["mergeEditor.conflict.unhandledFocused.border"] = parseHexVar "ff6188"
  result.colors["mergeEditor.conflict.unhandledUnfocused.border"] = parseHexVar "ff6188"
  result.colors["minimap.errorHighlight"] = parseHexVar "ff6188a5"
  result.colors["minimap.findMatchHighlight"] = parseHexVar "939293a5"
  result.colors["minimap.selectionHighlight"] = parseHexVar "c1c0c026"
  result.colors["minimap.selectionOccurrenceHighlight"] = parseHexVar "727072a5"
  result.colors["minimap.warningHighlight"] = parseHexVar "fc9867a5"
  result.colors["minimapGutter.addedBackground"] = parseHexVar "a9dc76"
  result.colors["minimapGutter.deletedBackground"] = parseHexVar "ff6188"
  result.colors["minimapGutter.modifiedBackground"] = parseHexVar "ffd866"
  result.colors["notebook.cellBorderColor"] = parseHexVar "403e41"
  result.colors["notebook.cellEditorBackground"] = parseHexVar "221f227f"
  result.colors["notebook.cellInsertionIndicator"] = parseHexVar "fcfcfa"
  result.colors["notebook.cellStatusBarItemHoverBackground"] = parseHexVar "727072"
  result.colors["notebook.cellToolbarSeparator"] = parseHexVar "403e41"
  result.colors["notebook.editorBackground"] = parseHexVar "2d2a2e"
  result.colors["notebook.focusedEditorBorder"] = parseHexVar "727072"
  result.colors["notebookStatusErrorIcon.foreground"] = parseHexVar "ff6188"
  result.colors["notebookStatusRunningIcon.foreground"] = parseHexVar "fcfcfa"
  result.colors["notebookStatusSuccessIcon.foreground"] = parseHexVar "a9dc76"
  result.colors["notificationCenter.border"] = parseHexVar "403e41"
  result.colors["notificationCenterHeader.background"] = parseHexVar "403e41"
  result.colors["notificationCenterHeader.foreground"] = parseHexVar "939293"
  result.colors["notificationLink.foreground"] = parseHexVar "ffd866"
  result.colors["notifications.background"] = parseHexVar "403e41"
  result.colors["notifications.border"] = parseHexVar "403e41"
  result.colors["notifications.foreground"] = parseHexVar "c1c0c0"
  result.colors["notificationsErrorIcon.foreground"] = parseHexVar "ff6188"
  result.colors["notificationsInfoIcon.foreground"] = parseHexVar "78dce8"
  result.colors["notificationsWarningIcon.foreground"] = parseHexVar "fc9867"
  result.colors["notificationToast.border"] = parseHexVar "403e41"
  result.colors["panel.background"] = parseHexVar "403e41"
  result.colors["panel.border"] = parseHexVar "2d2a2e"
  result.colors["panel.dropBackground"] = parseHexVar "221f22bf"
  result.colors["panelTitle.activeBorder"] = parseHexVar "ffd866"
  result.colors["panelTitle.activeForeground"] = parseHexVar "ffd866"
  result.colors["panelTitle.inactiveForeground"] = parseHexVar "939293"
  result.colors["peekView.border"] = parseHexVar "2d2a2e"
  result.colors["peekViewEditor.background"] = parseHexVar "403e41"
  result.colors["peekViewEditor.matchHighlightBackground"] = parseHexVar "5b595c"
  result.colors["peekViewEditorGutter.background"] = parseHexVar "403e41"
  result.colors["peekViewResult.background"] = parseHexVar "403e41"
  result.colors["peekViewResult.fileForeground"] = parseHexVar "939293"
  result.colors["peekViewResult.lineForeground"] = parseHexVar "939293"
  result.colors["peekViewResult.matchHighlightBackground"] = parseHexVar "5b595c"
  result.colors["peekViewResult.selectionBackground"] = parseHexVar "403e41"
  result.colors["peekViewResult.selectionForeground"] = parseHexVar "fcfcfa"
  result.colors["peekViewTitle.background"] = parseHexVar "403e41"
  result.colors["peekViewTitleDescription.foreground"] = parseHexVar "939293"
  result.colors["peekViewTitleLabel.foreground"] = parseHexVar "fcfcfa"
  result.colors["pickerGroup.border"] = parseHexVar "2d2a2e"
  result.colors["pickerGroup.foreground"] = parseHexVar "5b595c"
  result.colors["ports.iconRunningProcessForeground"] = parseHexVar "a9dc76"
  result.colors["problemsErrorIcon.foreground"] = parseHexVar "ff6188"
  result.colors["problemsInfoIcon.foreground"] = parseHexVar "78dce8"
  result.colors["problemsWarningIcon.foreground"] = parseHexVar "fc9867"
  result.colors["progressBar.background"] = parseHexVar "403e41"
  result.colors["sash.hoverBorder"] = parseHexVar "727072"
  result.colors["scrollbar.shadow"] = parseHexVar "2d2a2e"
  result.colors["scrollbarSlider.activeBackground"] = parseHexVar "727072"
  result.colors["scrollbarSlider.background"] = parseHexVar "c1c0c026"
  result.colors["scrollbarSlider.hoverBackground"] = parseHexVar "fcfcfa26"
  result.colors["selection.background"] = parseHexVar "c1c0c026"
  result.colors["settings.checkboxBackground"] = parseHexVar "403e41"
  result.colors["settings.checkboxBorder"] = parseHexVar "403e41"
  result.colors["settings.checkboxForeground"] = parseHexVar "fcfcfa"
  result.colors["settings.dropdownBackground"] = parseHexVar "403e41"
  result.colors["settings.dropdownBorder"] = parseHexVar "403e41"
  result.colors["settings.dropdownForeground"] = parseHexVar "fcfcfa"
  result.colors["settings.dropdownListBorder"] = parseHexVar "939293"
  result.colors["settings.headerForeground"] = parseHexVar "ffd866"
  result.colors["settings.modifiedItemForeground"] = parseHexVar "ffd866"
  result.colors["settings.modifiedItemIndicator"] = parseHexVar "ffd866"
  result.colors["settings.numberInputBackground"] = parseHexVar "403e41"
  result.colors["settings.numberInputBorder"] = parseHexVar "403e41"
  result.colors["settings.numberInputForeground"] = parseHexVar "fcfcfa"
  result.colors["settings.rowHoverBackground"] = parseHexVar "7270720c"
  result.colors["settings.textInputBackground"] = parseHexVar "403e41"
  result.colors["settings.textInputBorder"] = parseHexVar "403e41"
  result.colors["settings.textInputForeground"] = parseHexVar "fcfcfa"
  result.colors["sideBar.background"] = parseHexVar "221f22"
  result.colors["sideBar.border"] = parseHexVar "19181a"
  result.colors["sideBar.dropBackground"] = parseHexVar "221f22bf"
  result.colors["sideBar.foreground"] = parseHexVar "939293"
  result.colors["sideBarSectionHeader.background"] = parseHexVar "221f22"
  result.colors["sideBarSectionHeader.foreground"] = parseHexVar "727072"
  result.colors["sideBarTitle.foreground"] = parseHexVar "5b595c"
  result.colors["statusBar.background"] = parseHexVar "221f22"
  result.colors["statusBar.border"] = parseHexVar "19181a"
  result.colors["statusBar.debuggingBackground"] = parseHexVar "727072"
  result.colors["statusBar.debuggingBorder"] = parseHexVar "221f22"
  result.colors["statusBar.debuggingForeground"] = parseHexVar "fcfcfa"
  result.colors["statusBar.focusBorder"] = parseHexVar "403e41"
  result.colors["statusBar.foreground"] = parseHexVar "727072"
  result.colors["statusBar.noFolderBackground"] = parseHexVar "221f22"
  result.colors["statusBar.noFolderBorder"] = parseHexVar "19181a"
  result.colors["statusBar.noFolderForeground"] = parseHexVar "727072"
  result.colors["statusBarItem.activeBackground"] = parseHexVar "2d2a2e"
  result.colors["statusBarItem.errorBackground"] = parseHexVar "2d2a2e"
  result.colors["statusBarItem.errorForeground"] = parseHexVar "ff6188"
  result.colors["statusBarItem.focusBorder"] = parseHexVar "727072"
  result.colors["statusBarItem.hoverBackground"] = parseHexVar "fcfcfa0c"
  result.colors["statusBarItem.prominentBackground"] = parseHexVar "403e41"
  result.colors["statusBarItem.prominentHoverBackground"] = parseHexVar "403e41"
  result.colors["statusBarItem.remoteBackground"] = parseHexVar "221f22"
  result.colors["statusBarItem.remoteForeground"] = parseHexVar "a9dc76"
  result.colors["statusBarItem.warningBackground"] = parseHexVar "2d2a2e"
  result.colors["statusBarItem.warningForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.arrayForeground"] = parseHexVar "ff6188"
  result.colors["symbolIcon.booleanForeground"] = parseHexVar "ff6188"
  result.colors["symbolIcon.classForeground"] = parseHexVar "78dce8"
  result.colors["symbolIcon.colorForeground"] = parseHexVar "ab9df2"
  result.colors["symbolIcon.constantForeground"] = parseHexVar "ab9df2"
  result.colors["symbolIcon.constructorForeground"] = parseHexVar "a9dc76"
  result.colors["symbolIcon.enumeratorForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.enumeratorMemberForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.eventForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.fieldForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.fileForeground"] = parseHexVar "c1c0c0"
  result.colors["symbolIcon.folderForeground"] = parseHexVar "c1c0c0"
  result.colors["symbolIcon.functionForeground"] = parseHexVar "a9dc76"
  result.colors["symbolIcon.interfaceForeground"] = parseHexVar "78dce8"
  result.colors["symbolIcon.keyForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.keywordForeground"] = parseHexVar "ff6188"
  result.colors["symbolIcon.methodForeground"] = parseHexVar "a9dc76"
  result.colors["symbolIcon.moduleForeground"] = parseHexVar "78dce8"
  result.colors["symbolIcon.namespaceForeground"] = parseHexVar "78dce8"
  result.colors["symbolIcon.nullForeground"] = parseHexVar "ab9df2"
  result.colors["symbolIcon.numberForeground"] = parseHexVar "ab9df2"
  result.colors["symbolIcon.objectForeground"] = parseHexVar "78dce8"
  result.colors["symbolIcon.operatorForeground"] = parseHexVar "ff6188"
  result.colors["symbolIcon.packageForeground"] = parseHexVar "ab9df2"
  result.colors["symbolIcon.propertyForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.referenceForeground"] = parseHexVar "ab9df2"
  result.colors["symbolIcon.snippetForeground"] = parseHexVar "a9dc76"
  result.colors["symbolIcon.stringForeground"] = parseHexVar "ffd866"
  result.colors["symbolIcon.structForeground"] = parseHexVar "ff6188"
  result.colors["symbolIcon.textForeground"] = parseHexVar "ffd866"
  result.colors["symbolIcon.typeParameterForeground"] = parseHexVar "fc9867"
  result.colors["symbolIcon.unitForeground"] = parseHexVar "ab9df2"
  result.colors["symbolIcon.variableForeground"] = parseHexVar "78dce8"
  result.colors["tab.activeBackground"] = parseHexVar "2d2a2e"
  result.colors["tab.activeBorder"] = parseHexVar "ffd866"
  result.colors["tab.activeForeground"] = parseHexVar "ffd866"
  result.colors["tab.activeModifiedBorder"] = parseHexVar "5b595c"
  result.colors["tab.border"] = parseHexVar "2d2a2e"
  result.colors["tab.hoverBackground"] = parseHexVar "2d2a2e"
  result.colors["tab.hoverBorder"] = parseHexVar "5b595c"
  result.colors["tab.hoverForeground"] = parseHexVar "fcfcfa"
  result.colors["tab.inactiveBackground"] = parseHexVar "2d2a2e"
  result.colors["tab.inactiveForeground"] = parseHexVar "939293"
  result.colors["tab.inactiveModifiedBorder"] = parseHexVar "5b595c"
  result.colors["tab.lastPinnedBorder"] = parseHexVar "5b595c"
  result.colors["tab.unfocusedActiveBorder"] = parseHexVar "939293"
  result.colors["tab.unfocusedActiveForeground"] = parseHexVar "c1c0c0"
  result.colors["tab.unfocusedActiveModifiedBorder"] = parseHexVar "403e41"
  result.colors["tab.unfocusedHoverBackground"] = parseHexVar "2d2a2e"
  result.colors["tab.unfocusedHoverBorder"] = parseHexVar "2d2a2e"
  result.colors["tab.unfocusedHoverForeground"] = parseHexVar "c1c0c0"
  result.colors["tab.unfocusedInactiveForeground"] = parseHexVar "939293"
  result.colors["tab.unfocusedInactiveModifiedBorder"] = parseHexVar "403e41"
  result.colors["terminal.ansiBlack"] = parseHexVar "403e41"
  result.colors["terminal.ansiBlue"] = parseHexVar "fc9867"
  result.colors["terminal.ansiBrightBlack"] = parseHexVar "727072"
  result.colors["terminal.ansiBrightBlue"] = parseHexVar "fc9867"
  result.colors["terminal.ansiBrightCyan"] = parseHexVar "78dce8"
  result.colors["terminal.ansiBrightGreen"] = parseHexVar "a9dc76"
  result.colors["terminal.ansiBrightMagenta"] = parseHexVar "ab9df2"
  result.colors["terminal.ansiBrightRed"] = parseHexVar "ff6188"
  result.colors["terminal.ansiBrightWhite"] = parseHexVar "fcfcfa"
  result.colors["terminal.ansiBrightYellow"] = parseHexVar "ffd866"
  result.colors["terminal.ansiCyan"] = parseHexVar "78dce8"
  result.colors["terminal.ansiGreen"] = parseHexVar "a9dc76"
  result.colors["terminal.ansiMagenta"] = parseHexVar "ab9df2"
  result.colors["terminal.ansiRed"] = parseHexVar "ff6188"
  result.colors["terminal.ansiWhite"] = parseHexVar "fcfcfa"
  result.colors["terminal.ansiYellow"] = parseHexVar "ffd866"
  result.colors["terminal.background"] = parseHexVar "403e41"
  result.colors["terminal.foreground"] = parseHexVar "fcfcfa"
  result.colors["terminal.selectionBackground"] = parseHexVar "fcfcfa26"
  result.colors["terminalCommandDecoration.defaultBackground"] = parseHexVar "fcfcfa"
  result.colors["terminalCommandDecoration.errorBackground"] = parseHexVar "ff6188"
  result.colors["terminalCommandDecoration.successBackground"] = parseHexVar "a9dc76"
  result.colors["terminalCursor.background"] = parseHexVar "00000000"
  result.colors["terminalCursor.foreground"] = parseHexVar "fcfcfa"
  result.colors["testing.iconErrored"] = parseHexVar "ff6188"
  result.colors["testing.iconFailed"] = parseHexVar "ff6188"
  result.colors["testing.iconPassed"] = parseHexVar "a9dc76"
  result.colors["testing.iconQueued"] = parseHexVar "fcfcfa"
  result.colors["testing.iconSkipped"] = parseHexVar "fc9867"
  result.colors["testing.iconUnset"] = parseHexVar "939293"
  result.colors["testing.message.error.decorationForeground"] = parseHexVar "ff6188"
  result.colors["testing.message.error.lineBackground"] = parseHexVar "ff618819"
  result.colors["testing.message.info.decorationForeground"] = parseHexVar "fcfcfa"
  result.colors["testing.message.info.lineBackground"] = parseHexVar "fcfcfa19"
  result.colors["testing.runAction"] = parseHexVar "ffd866"
  result.colors["textBlockQuote.background"] = parseHexVar "403e41"
  result.colors["textBlockQuote.border"] = parseHexVar "403e41"
  result.colors["textCodeBlock.background"] = parseHexVar "403e41"
  result.colors["textLink.activeForeground"] = parseHexVar "fcfcfa"
  result.colors["textLink.foreground"] = parseHexVar "ffd866"
  result.colors["textPreformat.foreground"] = parseHexVar "fcfcfa"
  result.colors["textSeparator.foreground"] = parseHexVar "727072"
  result.colors["titleBar.activeBackground"] = parseHexVar "221f22"
  result.colors["titleBar.activeForeground"] = parseHexVar "939293"
  result.colors["titleBar.border"] = parseHexVar "19181a"
  result.colors["titleBar.inactiveBackground"] = parseHexVar "221f22"
  result.colors["titleBar.inactiveForeground"] = parseHexVar "5b595c"
  result.colors["walkThrough.embeddedEditorBackground"] = parseHexVar "221f22"
  result.colors["welcomePage.buttonBackground"] = parseHexVar "403e41"
  result.colors["welcomePage.buttonHoverBackground"] = parseHexVar "5b595c"
  result.colors["welcomePage.progress.background"] = parseHexVar "727072"
  result.colors["welcomePage.progress.foreground"] = parseHexVar "939293"
  result.colors["welcomePage.tileBackground"] = parseHexVar "403e41"
  result.colors["welcomePage.tileHoverBackground"] = parseHexVar "5b595c"
  result.colors["welcomePage.tileShadow"] = parseHexVar "19181a"
  result.colors["widget.shadow"] = parseHexVar "19181a"

  result.tokenColors["comment"] = Style(foreground: some(parseHexVar "727072"), fontStyle: {Italic})