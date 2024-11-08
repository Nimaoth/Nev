
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types

{.pop.}
type
  Cursor* = object
    line*: int32
    column*: int32
  Selection* = object
    first*: Cursor
    last*: Cursor