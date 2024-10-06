import std/[json, options]
import "../src/scripting_api"
import plugin_api_internal

## This file is auto generated, don't modify.

proc connectCollaborator*(port: int = 6969) =
  collab_connectCollaborator_void_int_impl(port)
proc hostCollaborator*(port: int = 6969) =
  collab_hostCollaborator_void_int_impl(port)
