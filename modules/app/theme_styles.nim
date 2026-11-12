import std/[algorithm, strutils, tables]
import misc/custom_logger
import chroma
import theme
import nuigi
import nuigi/debug/profiler

{.push gcsafe.}
{.push raises: [].}

logCategory "theme-styles"

const
  widgetStyleKeys* = block:
    var keys: array[UiStyleIndex, string]
    for index in UiStyleIndexDefault .. UiStyleIndex.high:
      keys[index] = themeSlotName($index)
    keys
  textStyleKeys* = block:
    var keys: array[UiTextStyleIndex, string]
    for index in UiStyleIndexDefaultText .. UiTextStyleIndex.high:
      keys[index] = themeSlotName($index)
    keys

proc toColor*(c: UiColor): Color =
  color(c.r, c.g, c.b, c.a)

proc highlightStyleColor*(nui: UiBuilder, name: string): UiColor =
  if nui.themeStyleIndices.hasKey(name):
    return nui.themeStyle(name)[].fillColor
  if nui.themeTextStyleIndices.hasKey(name):
    return nui.themeTextStyle(name)[].textColor
  log lvlWarn, "Unknown highlight theme style: ", name
  nui.themeStyle(UiStyleIndexSelection)[].fillColor

proc styleColor(theme: Theme, key: string, fallback: UiColor): UiColor =
  if theme != nil:
    let tint = theme.colors.getOrDefault(key, fallback.toColor)
    return rgba(tint.r, tint.g, tint.b, tint.a)
  fallback

proc syncThemeStyles*(nui: var UiBuilder, theme: Theme) =
  prof("syncThemeStyles")
  let defaultStyles = initDefaultThemeStyles()
  let defaultTexts = initDefaultThemeTextStyles()
  for index in UiStyleIndexDefault .. UiStyleIndex.high:
    let defaults = defaultStyles[index.int - 1]
    var style = nui.themeStyle(index)[]
    style.fillColor = theme.styleColor(widgetStyleKeys[index] & ".background", defaults.fillColor)
    style.borderColor = theme.styleColor(widgetStyleKeys[index] & ".border", defaults.borderColor)
    nui.setThemeStyle(index.uint16, style)
    # beginUiFrame has already seeded these slots before app rendering.
    if index.int <= nui.frame.styles.len:
      nui.frame.styles[index.int - 1] = style
  for index in UiStyleIndexDefaultText .. UiTextStyleIndex.high:
    var style = nui.themeTextStyle(index)[]
    style.textColor = theme.styleColor(textStyleKeys[index] & ".foreground",
      defaultTexts[index.int - 1].textColor)
    nui.setThemeTextStyle(index.uint16, style)
    if index.int <= nui.frame.texts.len:
      nui.frame.texts[index.int - 1] = style

  for i in UiStyleIndex.high.int ..< nui.themeStyles.len:
    nui.themeStyles[i].fillColor = defaultStyles[UiStyleIndexDefault.int - 1].fillColor
    nui.themeStyles[i].borderColor = defaultStyles[UiStyleIndexDefault.int - 1].borderColor
  for i in UiTextStyleIndex.high.int ..< nui.themeTextStyles.len:
    nui.themeTextStyles[i].textColor = defaultTexts[UiStyleIndexDefaultText.int - 1].textColor

  if theme != nil:
    var keys: seq[string]
    for key in theme.colors.keys:
      keys.add key
    keys.sort()
    for key in keys:
      let dot = key.rfind('.')
      if dot <= 0:
        continue
      let name = key[0 ..< dot]
      let tint = theme.colors[key]
      let value = rgba(tint.r, tint.g, tint.b, tint.a)
      case key[dot + 1 .. ^1]
      of "background", "border":
        if not nui.themeStyleIndices.hasKey(name):
          var style = nui.defaultStyle
          style.fillColor = defaultStyles[UiStyleIndexDefault.int - 1].fillColor
          style.borderColor = defaultStyles[UiStyleIndexDefault.int - 1].borderColor
          nui.setThemeStyle(name, style)
        let index = nui.themeStyleIndex(name)
        if index.int <= UiStyleIndex.high.int:
          continue
        var style = nui.themeStyle(index)[]
        if key.endsWith(".background"):
          style.fillColor = value
        else:
          style.borderColor = value
        nui.setThemeStyle(index, style)
      of "foreground":
        if not nui.themeTextStyleIndices.hasKey(name):
          nui.setThemeTextStyle(name, nui.defaultText)
        let index = nui.themeTextStyleIndex(name)
        if index.int <= UiTextStyleIndex.high.int:
          continue
        var style = nui.themeTextStyle(index)[]
        style.textColor = value
        nui.setThemeTextStyle(index, style)
      else:
        discard

  while nui.frame.styles.len < nui.themeStyles.len:
    nui.frame.styles.add nui.themeStyles[nui.frame.styles.len]
  for i in UiStyleIndex.high.int ..< nui.themeStyles.len:
    nui.frame.styles[i] = nui.themeStyles[i]
  while nui.frame.texts.len < nui.themeTextStyles.len:
    nui.frame.texts.add nui.themeTextStyles[nui.frame.texts.len]
  for i in UiTextStyleIndex.high.int ..< nui.themeTextStyles.len:
    nui.frame.texts[i] = nui.themeTextStyles[i]

{.pop.}
{.pop.}
