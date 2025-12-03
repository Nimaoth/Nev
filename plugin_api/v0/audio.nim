
{.push, hint[DuplicateModuleImport]: off.}
import
  std / [options]

from std / unicode import Rune

import
  results, wit_types, wit_runtime, wit_guest

{.pop.}
type
  AudioArgs* = object
    bufferLen*: int64
    index*: int64
    sampleRate*: int64
proc audioAddAudioCallbackImported(a0: uint32; a1: uint32): void {.
    wasmimport("add-audio-callback", "nev:plugins/audio").}
proc addAudioCallback*(fun: uint32; data: uint32): void {.nodestroy.} =
  ## todo
  var
    arg0: uint32
    arg1: uint32
  arg0 = fun
  arg1 = data
  audioAddAudioCallbackImported(arg0, arg1)

proc audioNextAudioSampleImported(): int64 {.
    wasmimport("next-audio-sample", "nev:plugins/audio").}
proc nextAudioSample*(): int64 {.nodestroy.} =
  let res = audioNextAudioSampleImported()
  result = convert(res, int64)

proc audioSetBufferSizeImported(a0: int32): void {.
    wasmimport("set-buffer-size", "nev:plugins/audio").}
proc setBufferSize*(size: int32): void {.nodestroy.} =
  var arg0: int32
  arg0 = size
  audioSetBufferSizeImported(arg0)

proc audioEnableTripleBufferingImported(a0: bool): void {.
    wasmimport("enable-triple-buffering", "nev:plugins/audio").}
proc enableTripleBuffering*(enabled: bool): void {.nodestroy.} =
  var arg0: bool
  arg0 = enabled
  audioEnableTripleBufferingImported(arg0)
