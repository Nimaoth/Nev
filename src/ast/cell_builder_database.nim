import std/[tables]
import cells
import model

var builders = initTable[LanguageId, CellBuilder]()

proc registerBuilder*(language: LanguageId, builder: CellBuilder) =
  builders[language] = builder

proc getBuilder*(language: LanguageId): CellBuilder =
  return builders[language]

