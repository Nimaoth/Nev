discard """
  action: "run"
  cmd: "nim $target --app:console --undef:useDynlib --nimblePath:./nimbleDir/simplePkgs $options $file"
  timeout: 500
  targets: "c"
"""

import std/[unittest, tables, json, os, options]
import chroma
import theme, app/theme_styles
import nuigi

proc measureThemeText(text: openArray[char], fontId: UiFontId,
    fontSize, maxWidth: float32, textFlags: UiTextFlags): UiTextArrangement {.raises: [].} =
  discard

proc uiColor(c: Color): UiColor = rgba(c.r, c.g, c.b, c.a)

proc gruvboxTheme(): Theme =
  parseFile(currentSourcePath().parentDir.parentDir.parentDir /
    "themes" / "gruvbox-dark.json").jsonToTheme()

proc checkDefaultColors(nui: UiBuilder) =
  let defaults = newBuilder(measureThemeText)
  for index in UiStyleIndexDefault .. UiStyleIndex.high:
    check nui.themeStyle(index)[].fillColor == defaults.themeStyle(index)[].fillColor
    check nui.themeStyle(index)[].borderColor == defaults.themeStyle(index)[].borderColor
  for index in UiStyleIndexDefaultText .. UiTextStyleIndex.high:
    check nui.themeTextStyle(index)[].textColor == defaults.themeTextStyle(index)[].textColor

suite "Nuigi application theme synchronization":
  test "every named style reaches persistent and current-frame slots":
    let theme = Theme()
    for index in UiStyleIndexDefault .. UiStyleIndex.high:
      let name = widgetStyleKeys[index]
      theme.colors[name & ".background"] = color(index.int.float32 / 100, 0.2, 0.3, 0.4)
      theme.colors[name & ".border"] = color(0.5, index.int.float32 / 100, 0.6, 0.7)
    for index in UiStyleIndexDefaultText .. UiTextStyleIndex.high:
      theme.colors[textStyleKeys[index] & ".foreground"] = color(0.8, 0.9, index.int.float32 / 100, 0.5)
    var nui = newBuilder(measureThemeText)
    discard nui.beginUiFrame(UiFrameContext())
    nui.syncThemeStyles(theme)
    for index in UiStyleIndexDefault .. UiStyleIndex.high:
      let name = widgetStyleKeys[index]
      let style = nui.themeStyle(index)[]
      check nui.themeStyleIndex(name) == index.uint16
      check style.fillColor == uiColor(theme.colors[name & ".background"])
      check style.borderColor == uiColor(theme.colors[name & ".border"])
      check nui.frame.styles[index.int - 1] == style
    for index in UiStyleIndexDefaultText .. UiTextStyleIndex.high:
      let name = textStyleKeys[index]
      let style = nui.themeTextStyle(index)[]
      check nui.themeTextStyleIndex(name) == index.uint16
      check style.textColor == uiColor(theme.colors[name & ".foreground"])
      check nui.frame.texts[index.int - 1].textColor == style.textColor
    check nui.defaultStyle == nui.themeStyle(UiStyleIndexDefault)[]
    check nui.defaultText.textColor == nui.themeTextStyle(UiStyleIndexDefaultText)[].textColor
    nui.endUiFrame()

  test "legacy names token fallbacks and dotted parents are ignored":
    let theme = Theme()
    for key in ["editor.background", "editor.foreground", "titleBar.foreground",
        "titleBar.activeForeground", "titleBar.background", "tab.activeBackground",
        "tab.inactiveBackground", "focusBorder", "list.activeSelectionBackground",
        "editorSuggestWidget.background", "editorSuggestWidget.foreground",
        "editorHoverWidget.background", "scrollBar", "scrollbarSlider.background",
        "editorCursor.background", "editorError.foreground", "signatureHelp.activeParam",
        "breadcrumbPicker.background", "rainbow0", "terminal.ansiBrightRed",
        "diffEditor.insertedTextBackground", "default-text", "panel", "plugin"]:
      theme.colors[key] = color(1, 0, 1)
    for key in ["error", "warning", "info", "hint"]:
      theme.tokenColors[key] = Style(foreground: color(1, 0, 1).some)
    var nui = newBuilder(measureThemeText)
    nui.syncThemeStyles(theme)
    nui.checkDefaultColors()

  test "overrides preserve transparency metrics fonts and custom slots":
    let theme = Theme()
    theme.colors["panel.background"] = color(1, 0, 0, 0)
    theme.colors["menu.border"] = color(0, 1, 0, 0)
    theme.colors["default-mono.foreground"] = color(0, 0, 1, 0)
    var nui = newBuilder(measureThemeText)
    let defaults = newBuilder(measureThemeText)
    nui.themeStyle(UiStyleIndexPanel)[].paddingX = 37
    nui.themeStyle(UiStyleIndexPanel)[].borderWidth = 3
    nui.themeStyle(UiStyleIndexPanel)[].cornerRadius = 11
    nui.themeTextStyle(UiStyleIndexDefaultMono)[].fontSize = 23
    nui.themeTextStyle(UiStyleIndexDefaultMono)[].fontId = UiFontId(7)
    let customStyle = UiStyle(fillColor: rgba(1.0'f32, 0.0'f32, 1.0'f32, 0.5'f32))
    nui.setThemeStyle("custom", customStyle)
    theme.colors["custom.background"] = customStyle.fillColor.toColor
    let slotCount = nui.themeStyles.len
    let nameCount = nui.themeStyleIndices.len
    discard nui.beginUiFrame(UiFrameContext())
    nui.syncThemeStyles(theme)
    check nui.themeStyle(UiStyleIndexPanel)[].fillColor == rgba(1, 0, 0, 0)
    check nui.themeStyle(UiStyleIndexPanel)[].borderColor == defaults.themeStyle(UiStyleIndexPanel)[].borderColor
    check nui.themeStyle(UiStyleIndexMenu)[].fillColor == defaults.themeStyle(UiStyleIndexMenu)[].fillColor
    check nui.themeStyle(UiStyleIndexMenu)[].borderColor == rgba(0, 1, 0, 0)
    check nui.themeTextStyle(UiStyleIndexDefaultMono)[].textColor == rgba(0, 0, 1, 0)
    check nui.themeStyle(UiStyleIndexPanel)[].paddingX == 37
    check nui.themeStyle(UiStyleIndexPanel)[].borderWidth == 3
    check nui.themeStyle(UiStyleIndexPanel)[].cornerRadius == 11
    check nui.themeTextStyle(UiStyleIndexDefaultMono)[].fontSize == 23
    check nui.themeTextStyle(UiStyleIndexDefaultMono)[].fontId == UiFontId(7)
    check nui.themeStyle("custom")[] == customStyle
    check nui.frame.styles[nui.themeStyleIndex("custom").int - 1] == customStyle
    check nui.highlightStyleColor("custom") == customStyle.fillColor
    check nui.highlightStyleColor("selection") == nui.themeStyle(UiStyleIndexSelection)[].fillColor
    check nui.highlightStyleColor("error-text") == nui.themeTextStyle(UiStyleIndexErrorText)[].textColor
    check nui.highlightStyleColor("custom.extra") == nui.themeStyle(UiStyleIndexSelection)[].fillColor
    nui.endUiFrame()
    for i in 0 .. 9:
      nui.syncThemeStyles(Theme())
      nui.checkDefaultColors()
      check nui.themeStyle("custom")[].fillColor == defaults.defaultStyle.fillColor
      nui.syncThemeStyles(theme)
      check nui.themeStyles.len == slotCount
      check nui.themeStyleIndices.len == nameCount
      check nui.themeStyle("custom")[] == customStyle

  test "custom properties create grouped widget and text styles in this frame":
    var nui = newBuilder(measureThemeText)
    let theme = Theme()
    theme.colors["plugin.badge.background"] = color(0.1, 0.2, 0.3, 0.4)
    theme.colors["plugin.badge.border"] = color(0.5, 0.6, 0.7, 0)
    theme.colors["plugin.badge.foreground"] = color(0.8, 0.9, 1, 0.5)
    theme.colors["border-only.border"] = color(1, 0, 0)
    theme.colors["panel.foreground"] = color(0, 1, 0)
    theme.colors["error-text.background"] = color(0, 0, 1)
    theme.colors["focusBorder"] = color(1, 0, 1)
    theme.colors["rainbow0"] = color(1, 0, 1)
    theme.colors[".background"] = color(1, 0, 1)
    discard nui.beginUiFrame(UiFrameContext())
    nui.syncThemeStyles(theme)
    check nui.themeStyleIndices.len == UiStyleIndex.high.int + 3
    check nui.themeTextStyleIndices.len == UiTextStyleIndex.high.int + 2
    check nui.themeStyle("plugin.badge")[].fillColor == rgba(0.1, 0.2, 0.3, 0.4)
    check nui.themeStyle("plugin.badge")[].borderColor == rgba(0.5, 0.6, 0.7, 0)
    check nui.themeTextStyle("plugin.badge")[].textColor == rgba(0.8, 0.9, 1, 0.5)
    check nui.themeStyle("border-only")[].fillColor == rgba(0, 0, 0, 0)
    check nui.themeTextStyle("panel")[].textColor == rgba(0, 1, 0, 1)
    check nui.themeStyle("error-text")[].fillColor == rgba(0, 0, 1, 1)
    check not nui.themeStyleIndices.hasKey("focusBorder")
    check not nui.themeTextStyleIndices.hasKey("rainbow0")
    let widgetIndex = nui.themeStyleIndex("plugin.badge")
    let textIndex = nui.themeTextStyleIndex("plugin.badge")
    check nui.frame.styles[widgetIndex.int - 1] == nui.themeStyle(widgetIndex)[]
    check nui.frame.texts[textIndex.int - 1].textColor == nui.themeTextStyle(textIndex)[].textColor
    nui.themeStyle(widgetIndex)[].paddingX = 42
    nui.themeTextStyle(textIndex)[].fontSize = 23
    let widgets = nui.themeStyles.len
    let texts = nui.themeTextStyles.len
    nui.endUiFrame()
    for i in 0 .. 4:
      discard nui.beginUiFrame(UiFrameContext())
      nui.syncThemeStyles(nil)
      check nui.themeStyleIndex("plugin.badge") == widgetIndex
      check nui.themeTextStyleIndex("plugin.badge") == textIndex
      check nui.themeStyle(widgetIndex)[].fillColor == rgba(0, 0, 0, 0)
      check nui.themeStyle(widgetIndex)[].borderColor == rgba(0, 0, 0, 0)
      let defaults = newBuilder(measureThemeText)
      check nui.themeTextStyle(textIndex)[].textColor ==
        defaults.themeTextStyle(UiStyleIndexDefaultText)[].textColor
      nui.syncThemeStyles(theme)
      check nui.themeStyle(widgetIndex)[].paddingX == 42
      check nui.themeTextStyle(textIndex)[].fontSize == 23
      check nui.themeStyles.len == widgets
      check nui.themeTextStyles.len == texts
      check nui.frame.styles[widgetIndex.int - 1] == nui.themeStyle(widgetIndex)[]
      check nui.frame.texts[textIndex.int - 1].textColor == nui.themeTextStyle(textIndex)[].textColor
      nui.endUiFrame()

  test "active styles are independent and missing keys reset to factory defaults":
    var nui = newBuilder(measureThemeText)
    let theme = Theme()
    theme.colors["panel.background"] = color(1, 0, 0)
    theme.colors["header.background"] = color(0, 1, 0)
    theme.colors["panel-active.background"] = color(0.6, 0.5, 0.4, 0.3)
    theme.colors["header-active.background"] = color(0.3, 0.4, 0.5, 0.6)
    nui.syncThemeStyles(theme)
    check nui.themeStyle(UiStyleIndexPanelActive)[].fillColor == rgba(0.6, 0.5, 0.4, 0.3)
    check nui.themeStyle(UiStyleIndexHeaderActive)[].fillColor == rgba(0.3, 0.4, 0.5, 0.6)
    theme.colors.del("panel-active.background")
    theme.colors.del("header-active.background")
    nui.syncThemeStyles(theme)
    let defaults = newBuilder(measureThemeText)
    for index in [UiStyleIndexPanelActive, UiStyleIndexHeaderActive]:
      check nui.themeStyle(index)[].fillColor == defaults.themeStyle(index)[].fillColor
    nui.syncThemeStyles(gruvboxTheme())
    discard nui.beginUiFrame(UiFrameContext())
    nui.syncThemeStyles(Theme())
    nui.checkDefaultColors()
    for index in UiStyleIndexDefault .. UiStyleIndex.high:
      check nui.frame.styles[index.int - 1] == nui.themeStyle(index)[]
    for index in UiStyleIndexDefaultText .. UiTextStyleIndex.high:
      check nui.frame.texts[index.int - 1].textColor == nui.themeTextStyle(index)[].textColor
    nui.endUiFrame()
    nui.syncThemeStyles(nil)
    nui.checkDefaultColors()
