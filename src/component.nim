import std/[tables, hashes, options]
include dynlib_export

type
  ComponentTypeId* = distinct int64

proc `==`*(a, b: ComponentTypeId): bool {.borrow.}
proc hash*(vr: ComponentTypeId): Hash {.borrow.}
proc `$`*(vr: ComponentTypeId): string {.borrow.}

type
  ComponentOwner* = ref object of RootObj
    components*: seq[Component]
    componentsByType*: Table[ComponentTypeId, Component]

  Component* = ref object of RootObj
    typeId*: ComponentTypeId
    initializeImpl*: proc(owner: ComponentOwner) {.gcsafe, raises: [].}

# DLL API
proc componentGenerateTypeId*(): ComponentTypeId {.apprtl, gcsafe, raises: [].}
proc componentInitialize*(self: Component, owner: ComponentOwner) {.apprtl, gcsafe, raises: [].}
proc componentOwnerAddComponent*(self: ComponentOwner, component: Component) {.apprtl, gcsafe, raises: [].}
proc componentOwnerGetComponent*(self: ComponentOwner, typeId: ComponentTypeId): Option[Component] {.apprtl, gcsafe, raises: [].}

# Nice wrappers
proc addComponent*(self: ComponentOwner, component: Component) = componentOwnerAddComponent(self, component)
proc getComponent*(self: ComponentOwner, typeId: ComponentTypeId): Option[Component] = componentOwnerGetComponent(self, typeId)

# Implementation
when implModule:
  proc componentInitialize*(self: Component, owner: ComponentOwner) =
    if self.initializeImpl != nil:
      self.initializeImpl(owner)

  proc componentOwnerAddComponent*(self: ComponentOwner, component: Component) =
    assert component.typeId.int != 0
    assert component.typeId notin self.componentsByType
    self.components.add(component)
    self.componentsByType[component.typeId] = component
    componentInitialize(component, self)

  proc componentOwnerGetComponent*(self: ComponentOwner, typeId: ComponentTypeId): Option[Component] =
    self.componentsByType.withValue(typeId, c):
      return c[].some
    for c in self.components:
      if c.typeId == typeId:
        return c.some
    return Component.none

  var typeIdGenerator: int64 = 0
  proc componentGenerateTypeId*(): ComponentTypeId =
    inc typeIdGenerator
    return typeIdGenerator.ComponentTypeId
