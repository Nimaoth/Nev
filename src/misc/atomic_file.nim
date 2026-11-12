import std/os

when defined(posix):
  proc rename(source, dest: cstring): cint {.importc, header: "<stdio.h>", sideEffect.}

{.push gcsafe.}
{.push raises: [].}

proc moveFileAtomic*(source, dest: string) {.raises: [OSError].} =
  ## Renames a file without a copy/delete fallback; both paths must be on the same filesystem.
  when defined(posix):
    if rename(source.cstring, dest.cstring) != 0:
      raiseOSError(osLastError(), source & " -> " & dest)
  else:
    moveFile(source, dest)
