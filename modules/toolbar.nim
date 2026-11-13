#use command_service
import service
from nuigi import UiBuilder

const currentSourcePath2 = currentSourcePath()
include module_base

{.push gcsafe.}
{.push raises: [].}

type
  ToolbarEntry* = object
    icon*: string     ## Unicode text rendered as the icon.
    name*: string     ## Display name shown in the tooltip.
    command*: string  ## Command executed when the entry is clicked.

  ToolbarService* = ref object of DynamicService
    entries*: seq[ToolbarEntry]

func serviceName*(_: typedesc[ToolbarService]): string = "ToolbarService"

# DLL API
{.push rtl, gcsafe, raises: [].}
proc toolbarAddEntry(self: ToolbarService, icon: string, name: string, command: string)
proc toolbarRenderNui(self: ToolbarService, nui: var UiBuilder)
{.pop.}

{.push inline.}
proc addEntry*(self: ToolbarService, icon: string, name: string, command: string) =
  ## Adds an entry to the bottom of the toolbar. `command` is executed when the icon is clicked,
  ## `name` is shown together with the command in the tooltip.
  toolbarAddEntry(self, icon, name, command)

proc renderNui*(self: ToolbarService, nui: var UiBuilder) =
  ## Renders the toolbar as a vertical list of icons which fills the parent height.
  toolbarRenderNui(self, nui)
{.pop.}

when implModule:
  import std/[options]
  import misc/[custom_logger, util]
  import platform
  import command_service
  from nuigi import UiBackendType, UiStyleIndex, UiTextStyleIndex, node, layoutVertical,
    width, height, size, fillY, fit, fillBackground, styleIndex, textStyleIndex, text,
    fontSize, alignCenter, pushId, popId, themeTextStyle, getTextArrangement,
    wasHovered, wasClicked, withParent, offsets, pivot, finishAnchors, noHover,
    absoluteNodePosPrev, currentNode, UiNodeId

  logCategory "toolbar"

  proc toolbarAddEntry(self: ToolbarService, icon: string, name: string, command: string) =
    self.entries.add ToolbarEntry(icon: icon, name: name, command: command)

  proc toolbarRenderNui(self: ToolbarService, nui: var UiBuilder) =
    {.cast(gcsafe).}:
      try:
        let isTerminal = nui.backendType == UiBackendType.Terminal
        let textStyle = nui.themeTextStyle(UiStyleIndexDefaultText)
        let iconFontSize = if isTerminal: textStyle.fontSize else: textStyle.fontSize * 1.5
        let iconRefSize = nui.getTextArrangement("M", textStyle.fontId, iconFontSize).size
        let (itemWidth, itemHeight) = if isTerminal:
          (3.0'f32, 1.0'f32)
        else:
          let s = (max(1.0'f32, iconRefSize.y) * 1.8'f32).int.float32
          (s, s)

        template scaledIconFontSize(nui: var UiBuilder, icon: string): float32 =
          ## Glyphs from fallback fonts have very different sizes, so scale each icon so its
          ## measured box roughly matches the line height at the icon font size.
          block:
            let size = nui.getTextArrangement(icon, textStyle.fontId, textStyle.fontSize).size
            let extent = max(size.x, size.y)
            if isTerminal or extent <= 0:
              iconFontSize
            else:
              textStyle.fontSize * clamp(iconRefSize.y / extent, 0.5'f32, 3.0'f32)

        var clickedIndex = -1
        var hoveredIndex = -1
        var hoveredId: UiNodeId
        nui.layoutVertical("nui-toolbar"):
          discard nui.width(itemWidth).fillY().fillBackground().styleIndex(UiStyleIndexHeader)
            .backendPadding(0).backendGap(0)
          for i, entry in self.entries:
            nui.pushId(i.uint64)
            nui.node("toolbar-entry"):
              discard nui.size(itemWidth, itemHeight)
              let hovered = nui.wasHovered(includeChildren = true)
              if hovered:
                hoveredIndex = i
                hoveredId = nui.currentNode.id
                discard nui.fillBackground().styleIndex(UiStyleIndexMenuItemHover)
              if nui.wasClicked(includeChildren = true):
                clickedIndex = i
              nui.node:
                discard nui.fit().alignCenter()
                  .textStyleIndex(int(if hovered: UiStyleIndexMenuItemHoverText else: UiStyleIndexMenuItemText))
                  .fontSize(nui.scaledIconFontSize(entry.icon)).text(entry.icon)
            nui.popId()

        if hoveredIndex >= 0:
          # Hover state comes from the previous frame, so use the entry's previous position too.
          let entryPos = nui.absoluteNodePosPrev(hoveredId)
          let gap = if isTerminal: 1.0'f32 else: 4.0'f32
          nui.withParent(nui.overlays):
            nui.layoutVertical("toolbar-tooltip"):
              let entry = self.entries[hoveredIndex].addr
              if entry.name.len > 0:
                nui.node:
                  discard nui.fit().textStyleIndex(int(UiStyleIndexDefaultText)).text(entry.name)
              nui.node:
                discard nui.fit().textStyleIndex(int(UiStyleIndexSmallText)).text(entry.command)
              discard nui.fit().fillBackground().styleIndex(UiStyleIndexTooltip)
                .backendBorderWidth(1, 0).backendPaddingX(6, 1).backendPaddingY(4, 0)
                .offsets(entryPos.x + itemWidth + gap, entryPos.y + itemHeight * 0.5, 0, 0)
                .pivot(0, 0.5).finishAnchors().noHover()

        if clickedIndex >= 0:
          let command = self.entries[clickedIndex].command
          let commands = getServiceChecked(CommandService)
          if commands.executeCommand(command, record = false).isNone:
            log lvlWarn, &"Failed to execute toolbar command '{command}'"
      except Exception as e:
        log lvlError, &"Failed to render toolbar: {e.msg}"

  proc init_module_toolbar*() {.cdecl, exportc, dynlib.} =
    let self = ToolbarService()
    self.addEntry("❯", "Command Line", "commands.command-line")
    self.addEntry("🖿", "File Explorer", "file-explorer.toggle")
    self.addEntry("🗁", "Browse Files", "explore-files")
    self.addEntry("⌕", "Find File", "choose-file")
    self.addEntry("🗐", "Open Files", "choose-open")
    self.addEntry("⎌", "Undo Tree", "undotree.toggle")
    self.addEntry("⎇", "Git", "gitui.toggle")
    self.addEntry("⚒", "Builds", "builds.toggle")
    self.addEntry("⚙", "Settings", "browse-settings")
    self.addEntry("🖳", "Platform Settings", "open-platform-settings")
    getServices().addService(self)
