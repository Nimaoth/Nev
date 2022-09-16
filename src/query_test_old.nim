
type
  CachedValue = object
    value: Type
    dependencies: seq[AstNode]
    # lastChanged: int # Revision when this value last changed
    # lastComputed: int # Revision when this value computed
    dirty: bool

  Database = ref object
    computeTypeCache: Table[AstNode, CachedValue]
    computeTypeDependencyStack: seq[seq[AstNode]]
    computeTypeDependents: Table[AstNode, HashSet[AstNode]]
    revision: int

proc `$`(db: Database): string =
  echo "Database"
  echo "  revision: ", db.revision
  echo "  computeType"
  echo "    dependents"
  for (key, value) in db.computeTypeDependents.pairs:
    echo "      ", key, ": ", value
  echo "    cache"
  for (key, value) in db.computeTypeCache.pairs:
    echo "      ", key, ": ", value

proc updateAst(db: Database, node: AstNode) =
  echo "updateAst ", node, ", revision: ", db.revision
  # inc db.revision
  if db.computeTypeCache.contains(node):
    # db.computeTypeCache[node].lastChanged = db.revision
    # db.computeTypeCache[node].lastComputed = db.revision
    db.computeTypeCache[node].dirty = true

  if db.computeTypeDependents.contains(node):
    for dep in db.computeTypeDependents[node].items:
      db.updateAst dep

proc computeTypeQuery(db: Database, node: AstNode): Type

proc computeType(db: Database, node: AstNode): Type =
  echo indent("", db.computeTypeDependencyStack.len * 2), "computeType ", node

  if db.computeTypeDependencyStack.len > 0:
    db.computeTypeDependencyStack[db.computeTypeDependencyStack.high].add node

  if db.computeTypeCache.contains(node) and not db.computeTypeCache[node].dirty:
    echo indent("", db.computeTypeDependencyStack.len * 2 + 2), "computeType ", node, ", using cache"
    return db.computeTypeCache[node].value

  db.computeTypeDependencyStack.add @[]
  let value = db.computeTypeQuery(node)

  let dependencies = db.computeTypeDependencyStack.pop
  echo indent("", db.computeTypeDependencyStack.len * 2 + 2),  "Dependencies of ", node, ": ", dependencies
  for dep in dependencies:
    if not db.computeTypeDependents.contains dep:
      db.computeTypeDependents.add(dep, initHashSet[AstNode]())
    db.computeTypeDependents[dep].incl node

  echo indent("", db.computeTypeDependencyStack.len * 2 + 2),  "computeType ", node, ", caching ", value
  db.computeTypeCache[node] = CachedValue(value: value, dependencies: dependencies)

  return value

proc computeTypeQuery(db: Database, node: AstNode): Type =
  case node
  of NumberLiteral():
    return Int

  of StringLiteral():
    return String

  of Call():
    let function = node[0]

    if function.id != IdAdd:
      return Error
    if node.len != 3:
      return Error

    let left = node[1]
    let right = node[2]

    let leftType = db.computeType(left)
    let rightType = db.computeType(right)

    if leftType == Int and rightType == Int:
      return Int

    if leftType == String and rightType == Int:
      return String

    return Error

  else:
    return Error

let node = makeTree(AstNode):
  # Declaration(id: == newId(), text: "foo"):
  Call():
    Identifier(id: == IdAdd)
    Call():
      Identifier(id: == IdAdd)
      NumberLiteral(text: "69")
      NumberLiteral(text: "420")
    NumberLiteral(text: "3")

echo $$node

let db = Database()
echo db.computeType node

echo ""
echo db

echo ""
db.updateAst node[1][1]
node[1][1] = makeTree(AstNode): StringLiteral(text: "lol")

echo ""
echo db

echo ""
echo db.computeType node

echo ""
echo db

db.updateAst node[1][1]
node[1][1] = makeTree(AstNode): NumberLiteral(text: "drei")
echo db.computeType node