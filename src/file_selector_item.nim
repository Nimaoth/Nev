import std/[options, json]
import workspaces/[workspace]
import misc/[id, util, myjsonutils]
import selector_popup_builder, scripting_api

type FileSelectorItem* = ref object of SelectorItem
  name*: string
  directory*: string
  path*: string
  location*: Option[Cursor]
  workspaceFolder*: Option[WorkspaceFolder]

method changed*(self: FileSelectorItem, other: SelectorItem): bool =
  let other = other.FileSelectorItem
  return self.path != other.path

method itemToJson*(self: FileSelectorItem): JsonNode = %*{
    "score": self.score,
    "path": self.path,
    "name": self.name,
    "directory": self.directory,
    "location": (if self.location.getSome(location):
        location.toJson
      else:
        newJNull()),
    "workspace": if self.workspaceFolder.getSome(workspace):
        workspace.id.toJson
      else:
        newJNull()
  }