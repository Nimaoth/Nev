import std/[strformat, json, jsonutils, strutils, math, unicode, macros, random, base64, tables]
import results
import util, render_command, binary_encoder
import "../../src/lisp"
import api
import clay
import wav

var views: seq[RenderView] = @[]
var renderCommandEncoder: BinaryEncoder

const FixedGain = 0.05
const ScaleWet = 3.0
const ScaleRoom = 0.28
const OffsetRoom = 0.7
const ScaleDamp = 0.4
const OffsetDamp = 0.1

type SharedAudioBuffer* = ref object
  len: int
  buffer: SharedBuffer

proc new*(_: typedesc[SharedAudioBuffer], samples: int): SharedAudioBuffer =
  result = SharedAudioBuffer(buffer: newSharedBuffer(samples * sizeof(float32)), len: samples)

proc mount*(self: SharedAudioBuffer, path: string, unique: bool = true): string =
  var b = SharedBuffer()
  swap(b, self.buffer)
  return $b.sharedBufferMount(path.ws, unique = unique)

proc open*(_: typedesc[SharedAudioBuffer], path: string): Option[SharedAudioBuffer] =
  var buffer = sharedBufferOpen(path.ws)
  if not buffer.isSome:
    return SharedAudioBuffer.none
  let bufferLen = buffer.get.len
  if bufferLen mod 4 != 0:
    log lvlError, &"Audio buffer len is not a multiple of 4"
    return SharedAudioBuffer.none
  var b = buffer.take
  return SharedAudioBuffer(buffer: b, len: bufferLen.int div 4).some

proc read*(buffer: SharedAudioBuffer, index: int, dst: openArray[float32]) =
  if dst.len > 0:
    echo &"===================000 read {index} into {dst.len}"
    buffer.buffer.readInto(index, cast[uint32](dst[0].addr), dst.len * sizeof(dst[0]))

proc write*(buffer: SharedAudioBuffer, index: int, src: openArray[float32]) =
  if src.len > 0:
    buffer.buffer.write(index, wl(cast[ptr UncheckedArray[uint8]](src[0].addr), src.len * sizeof(src[0])))

var gwav: WavInfo

proc loadWavFile(path: string): SharedAudioBuffer =
  let res = readSync(path.ws, {Binary})
  if not res.isOk:
    let err = res.error
    log lvlError, &"Failed to load wav file {path}: {err}"
    return SharedAudioBuffer()

  var wav = parseWavFromMemory(res.get.toOpenArray.toOpenArrayByte(0, res.get.len - 1))
  if wav.sampleRate != 48_000:
    for channel in wav.samples.mitems:
      channel = resampleLinear(channel, wav.sampleRate, 48_000)
    wav.sampleRate = 48_000

  for channel in wav.samples.mitems:
    var m = 0.0
    for s in channel:
      m = max(m, abs(s))
    log lvlWarn, &"Max sample: {m}"
    # for s in channel:
    #   max = max(max, abs(s))

  let buf = SharedAudioBuffer.new(wav.samples[0].len)
  buf.write(0, wav.samples[0])

  gwav = wav
  return buf

converter toWitString(s: string): WitString = ws(s)
var target = 50

proc handleViewRender(id: int32, data: uint32) {.cdecl.}

proc measureClayText(text: ClayStringSlice; config: ptr ClayTextElementConfig; userData: pointer): ClayDimensions {.cdecl.} =
  return ClayDimensions(width: text.length.float * 10, height: 20)

let totalMemorySize = clay.minMemorySize()
var memory = ClayArena(capacity: totalMemorySize, memory: cast[ptr UncheckedArray[uint8]](allocShared0(totalMemorySize)))
var clayErrorHandler = ClayErrorHandler(
  errorHandlerFunction: proc (error: ClayErrorData) =
    log lvlError, &"[clay] {error.errorType}: {error.errorText}"
)
var clayContext* = clay.initialize(memory, ClayDimensions(width: 1024, height: 768), clayErrorHandler)
clay.setMeasureTextFunction(measureClayText, nil)
clay.setDebugModeEnabled(false)

proc toggleClayDebugMode() =
  clay.setDebugModeEnabled(not clay.isDebugModeEnabled())

proc getNotePitch(note: string): float32 =
  let (b, octave) = if note[^1] in {'1'..'9'}: (note[0..^2], note[^1].int - '1'.int) else: (note, 3)
  case b
  of "C":
    let notes = [16.35, 32.7, 65.41, 130.81, 261.63, 523.25, 1046.5, 2093, 4186]
    notes[octave]
  of "C#":
    let notes = [17.32, 34.65, 69.3, 138.59, 277.18, 554.37, 1108.73, 2217.46, 4434.92]
    notes[octave]
  of "D":
    let notes = [18.35, 36.71, 73.42, 146.83, 293.66, 587.33, 1174.66, 2349.32, 4698.63]
    notes[octave]
  of "D#":
    let notes = [19.45, 38.89, 77.78, 155.56, 311.13, 622.25, 1244.51, 2489, 4978]
    notes[octave]
  of "E":
    let notes = [20.6, 41.2, 82.41, 164.81, 329.63, 659.25, 1318.51, 2637, 5274]
    notes[octave]
  of "F":
    let notes = [21.83, 43.65, 87.31, 174.61, 349.23, 698.46, 1396.91, 2793.83, 5587.65]
    notes[octave]
  of "F#":
    let notes = [23.12, 46.25, 92.5, 185, 369.99, 739.99, 1479.98, 2959.96, 5919.91]
    notes[octave]
  of "G":
    let notes = [24.5, 49, 98, 196, 392, 783.99, 1567.98, 3135.96, 6271.93]
    notes[octave]
  of "G#":
    let notes = [25.96, 51.91, 103.83, 207.65, 415.3, 830.61, 1661.22, 3322.44, 6644.88]
    notes[octave]
  of "A":
    let notes = [27.5, 55, 110, 220, 440, 880, 1760, 3520, 7040]
    notes[octave]
  of "A#":
    let notes = [29.14, 58.27, 116.54, 233.08, 466.16, 932.33, 1864.66, 3729.31, 7458.62]
    notes[octave]
  of "B":
    let notes = [30.87, 61.74, 123.47, 246.94, 493.88, 987.77, 1975.53, 3951, 7902.13]
    notes[octave]
  else:
    440

type
  KeyState = object
    key: int
    frequency: float32
    startTime: int64
    releaseTime: int64

  AudioFeedback = object
    dt: float64
    activeSounds: int
    totalSounds: int
    alignOffset: int
    samples: array[666, int16]

  PitchKind = enum Frequency, Note
  Pitch = object
    case kind: PitchKind
    of Frequency:
      freq: float32
    of Note:
      name: string

  CombFilter = object
    buffer: seq[float32]
    index: int
    dampingTarget: float32
    feedback: float32
    damping: float32

  AllPassFilter = object
    buffer: seq[float32]
    index: int
    feedback: float32

  SchroederReverb = object
    combs: seq[CombFilter]
    allpasses: seq[AllPassFilter]
    dry: float32
    wet: float32

  FreeVerb = object
    combs: seq[CombFilter]
    allpasses: seq[AllPassFilter]
    dry: float32
    wet: float32
    damping: float32
    size: float32

  WaveKind = enum Sin, Saw, Square, Noise, Triangle, Pulse
  SoundKind = enum Synth, Sample
  Sound = object
    case kind: SoundKind
    of Synth:
      layers: array[8, tuple[freqMul: float32, gain: float32, wave: WaveKind, arg1: float32]]
    of Sample:
      name: string

  SoundState = object
    gain: float32
    # pitch: Pitch
    freq: float32
    startTime: int64
    releaseTime: int64
    adsr: tuple[attack, decay, sustainVolume, release: float32]

  ModifierKind {.pure.} = enum Gain, Adsr, Pitch, Timing
  ModifierState = object
    startTime: int64
    releaseTime: int64
    case kind: ModifierKind
    of ModifierKind.Gain, ModifierKind.Pitch, ModifierKind.Timing:
      floatValue: float32
    of ModifierKind.Adsr:
      adsr: tuple[attack, decay, sustainVolume, release: float32]

  Track = object
    name: string
    patterns: seq[LispVal]
    sounds: seq[SoundState]
    mods: seq[ModifierState]
    sound: Sound
    adsr: tuple[attack, decay, sustainVolume, release: float32]
    gain: float32

  AudioFile = object
    buffer: SharedAudioBuffer
    samples: seq[float32]

  State = object
    runningAudio: bool
    info: AudioArgs
    volume: float32
    muted: bool
    audioThread: bool
    keys: seq[KeyState]
    sampleRate: int64
    samplesPerBar: int64
    startTime: int64
    bpm: int64
    beat1: int64
    beat2: int64
    barIndex: int64
    bDepth: int64
    nextBarSample: int64
    tracks: seq[Track]
    script: string
    reverb: FreeVerb
    scheduleStart: int64
    scheduleLen: int64
    scheduleNoteLen: float32
    scheduleModStack: seq[ModifierState]
    files: Table[string, AudioFile]

type
  AudioEventKind = enum
    SetState = "set-state"
    ChangeVolume = "change-volume"
    ToggleMute = "toggle-mute"
    Command = "command"
    Press = "press"
    Release = "release"
    File = "file"

  AudioEvent = object
    timestamp: int64
    case kind: AudioEventKind
    of SetState:
      setState: tuple[state: State]
    of ChangeVolume:
      changeVolume: tuple[change: float32]
    of ToggleMute:
      discard
    of Command:
      command: string
    of Press:
      press: tuple[key: int, note: string]
    of Release:
      release: tuple[key: int]
    of File:
      file: tuple[name: string, path: string]

proc initCombFilter(bufferSize: int, feedback: float32, damping: float32 = 0): CombFilter =
  CombFilter(buffer: newSeq[float32](bufferSize), feedback: feedback, damping: damping)

proc initAllPassFilter(bufferSize: int, feedback: float32): AllPassFilter =
  AllPassFilter(buffer: newSeq[float32](bufferSize), feedback: feedback)

proc initFreeVerb(damping: float32, size: float32): FreeVerb =
  FreeVerb(
    combs: @[
      initCombFilter(1217, size, damping),
      initCombFilter(1296, size, damping),
      initCombFilter(1393, size, damping),
      initCombFilter(1479, size, damping),
      initCombFilter(1551, size, damping),
      initCombFilter(1626, size, damping),
      initCombFilter(1698, size, damping),
      initCombFilter(1764, size, damping),
    ],
    allpasses: @[
      initAllPassFilter(245, 0.5),
      initAllPassFilter(372, 0.5),
      initAllPassFilter(481, 0.5),
      initAllPassFilter(606, 0.5),
    ],
    dry: 0.7,
    wet: 0.3,
    damping: damping,
    size: size,
  )

proc setDampingAndSize(reverb: var FreeVerb, damping: float32, size: float32) =
  reverb.damping = damping
  reverb.size = size
  for comb in reverb.combs.mitems:
    comb.feedback = size
    comb.damping = damping

proc process(filter: var CombFilter, input: float32): float32 =
  let output = filter.buffer[filter.index]
  filter.dampingTarget = (output * (1.0 - filter.damping)) + (filter.dampingTarget * filter.damping)
  filter.buffer[filter.index] = input + filter.dampingTarget * min(filter.feedback, 1)
  inc filter.index
  if filter.index >= filter.buffer.len:
    filter.index = 0
  return output

proc process(filter: var AllPassFilter, input: float32): float32 =
  let bufOut = filter.buffer[filter.index]
  let output = -input + bufOut
  filter.buffer[filter.index] = input + bufOut * min(filter.feedback, 1)
  inc filter.index
  if filter.index >= filter.buffer.len:
    filter.index = 0
  return output

proc process(reverb: var SchroederReverb, x: float32): float32 =
  var sum = 0.0
  for comb in reverb.combs.mitems:
    sum += comb.process(x)

  var ap = sum
  for allpass in reverb.allpasses.mitems:
    ap = allpass.process(ap)

  return x * reverb.dry + ap * reverb.wet

proc process(reverb: var FreeVerb, input: float32): float32 =
  let inputScaled = input * FixedGain
  var acc = 0.0
  for comb in reverb.combs.mitems:
    acc += comb.process(inputScaled)

  for allpass in reverb.allpasses.mitems:
    acc = allpass.process(acc)

  return input * reverb.dry + acc * reverb.wet

proc differenceAtOffset[T](a, b: openArray[T], offset: int): float32 =
  if offset >= a.len or offset >= b.len:
    # echo "offset > len"
    return float32.high
  var error: float32 = 0.0
  let startA = if offset > 0: offset else: 0
  let startB = if offset > 0: 0 else: -offset
  let n = min(a.len - startA, b.len - startB)
  for i in 0..<n:
    if startA + i notin 0..<a.len:
      # echo "out of bounds a ", startA, ", ", i, ", ", a.len
      continue
    if startA + i notin 0..<a.len:
      # echo "out of bounds b ", startB, ", ", i, ", ", b.len
      continue
    error += abs(a[startA + i].float32 - b[startB + i].float32)
  return error

proc alignOffset[T](a, b: openArray[T]): int =
  let maxShiftLeft = b.len - a.len
  let maxShiftRight = 0
  result = 0
  var bestError = float32.high
  var i = -maxShiftLeft
  while i <= maxShiftRight:
    let error = differenceAtOffset(a, b, i)
    if error < bestError:
      bestError = error
      result = i
    i += 10

  for k in max(result - 9, -maxShiftLeft)..min(result + 9, maxShiftRight):
    let error = differenceAtOffset(a, b, k)
    if error < bestError:
      bestError = error
      result = k

macro generateSineLookupTable(samples: static int): untyped =
  var res = nnkBracket.newTree()
  for i in 0..<samples:
    res.add newLit(sin(i.float32 / samples.float32 * 2 * PI))
  return res

const sineLookupTable = generateSineLookupTable(2048)

proc sin(time, freq: float32): float32 =
  let index = (time * freq * sineLookupTable.len).int
  return sineLookupTable[index and (sineLookupTable.len - 1)]

# macro generateNoiseLookupTable(samples: static int): untyped =
#   var res = nnkBracket.newTree()
#   return res

var noiseLookupTable: array[2048, float32]
for n in noiseLookupTable.mitems:
  n = rand(2.0) - 1.0

proc noise(time, freq: float32): float32 =
  let index = (time * freq * noiseLookupTable.len.float32).int
  return noiseLookupTable[index and (noiseLookupTable.len - 1)]

proc saw(time, freq: float32): float32 =
  return fract(time * freq) * 2 - 1

proc square(time, freq: float32): float32 =
  return round(fract(time * freq)) * 2 - 1

proc triangle(time, freq: float32): float32 =
  return abs(fract(time * freq) - 0.5) * 4 - 1

proc pulse(time, freq: float32, width: float32): float32 =
  return if fract(time * freq) < width: 1 else: -1

proc adsr(time, attack, decay, sustain, sustainVolume, release: float32): float32 =
  let sustain = max(sustain - attack - decay, 0)
  var time = time
  if time < 0:
    return 0
  if time <= attack:
    return time / attack
  time -= attack
  if time <= decay:
    let alpha = time / decay
    return lerp(1.float32, sustainVolume, alpha)
  time -= decay
  if time <= sustain:
    return sustainVolume

  time -= sustain
  let alpha = time / release
  return lerp(sustainVolume, 0, min(alpha, 1))

proc modify(state: State, sound: var SoundState, modifier: ModifierState) =
  # log lvlDebug, &"Modify {sound} with {modifier}"
  case modifier.kind
  of Gain:
    sound.gain = modifier.floatValue
  of Pitch:
    sound.freq *= modifier.floatValue
  of Timing:
    let sampleOffset = (modifier.floatValue.float32 * state.sampleRate.float64).int64
    sound.startTime += sampleOffset
    if sound.releaseTime != int64.high:
      sound.releaseTime += sampleOffset
  of Adsr:
    sound.adsr = modifier.adsr

proc scheduleSound(state: var State, track: var Track, sound: SoundState) =
  if sound.startTime < state.startTime:
    return
  track.sounds.add(sound)
  for m in state.scheduleModStack:
    state.modify(track.sounds[^1], m)

proc scheduleMod(state: var State, track: var Track, modifier: ModifierState) =
  track.mods.add(modifier)

proc scheduleTrack(state: var State, track: var Track) =
  # log lvlDebug, &"scheduleTrack {track}"
  # for f in state.files.keys:
  #   log lvlInfo, &"file {f}"
  #   echo track

  var pstate = state.addr
  var ptrack = track.addr

  var env = baseEnv()
  env.onUndefinedSymbol = proc(_: Env, name: string): LispVal =
    # log lvlDebug, &"onUndefinedSymbol '{name}'"
    template impl(body: untyped): untyped =
      newFunc(name, evalArgs=false, fn=proc(args {.inject.}: seq[LispVal]): LispVal =
        try:
          body
        except CatchableError as e:
          raise newException(LispError, e.msg, e)
        return newNil()
      )
    case name
    of "b":
      impl:
        try:
          inc pstate.bDepth
          if args.len > 0:
            let child = (pstate[].barIndex shr (pstate.bDepth - 1)) mod args.len
            discard args[child].eval(env)
        finally:
          dec pstate.bDepth
    of "s":
      impl:
        if args.len > 0:
          let scheduleStart = pstate.scheduleStart
          let scheduleLen = pstate.scheduleLen
          try:
            pstate.scheduleLen = scheduleLen div args.len
            for i in 0..<args.len:

              discard args[i].eval(env)
              pstate.scheduleStart += pstate.scheduleLen
          finally:
            pstate.scheduleStart = scheduleStart
            pstate.scheduleLen = scheduleLen

    of "gain":
      impl:
        if args.len > 0:
          let value = args[0].eval(env).toJson.jsonTo(float32)
          pstate[].scheduleMod(ptrack[], ModifierState(
            kind: ModifierKind.Gain,
            startTime: pstate.scheduleStart,
            releaseTime: pstate.scheduleStart + pstate.scheduleLen,
            floatValue: value,
          ))

    of "sound":
      impl:
        var sound = Sound(kind: Synth)
        for i in 0..<args.len:
          if i >= sound.layers.len:
            break
          let a = args[i]
          if a.kind != List or a.elems.len < 3:
            continue
          let waveSym = a.elems[0]
          if waveSym.kind != Symbol:
            continue
          let wave: WaveKind = case waveSym.sym
          of "sin": Sin
          of "saw": Saw
          of "sqr": Square
          of "nos": Noise
          of "tri": Triangle
          of "pul": Pulse
          else:
            continue

          let freqMul = a.elems[1].eval(env).toJson.jsonTo(float32)
          let gain = a.elems[2].eval(env).toJson.jsonTo(float32)
          let arg1 = if a.elems.len > 3: a.elems[3].eval(env).toJson.jsonTo(float32) else: 0
          sound.layers[i] = (freqMul, gain, wave, arg1)
        ptrack.sound = sound

    of "sample":
      impl:
        var sound = Sound(kind: Sample)
        if args.len > 0:
          let name = args[0].eval(env).toJson.jsonTo(string)
          sound.name = name
        ptrack.sound = sound

    of "pitch":
      impl:
        if args.len > 0:
          let value = args[0].eval(env).toJson.jsonTo(float32)
          pstate[].scheduleMod(ptrack[], ModifierState(
            kind: ModifierKind.Pitch,
            startTime: pstate.scheduleStart,
            releaseTime: pstate.scheduleStart + pstate.scheduleLen,
            floatValue: value,
          ))

    of "t+":
      impl:
        if args.len >= 2:
          let value = args[0].eval(env).toJson.jsonTo(float32)
          try:
            pstate[].scheduleModStack.add ModifierState(
              kind: ModifierKind.Timing,
              floatValue: value,
            )
            discard args[1].eval(env)
          finally:
            discard pstate[].scheduleModStack.pop()

    of "timing":
      impl:
        if args.len > 0:
          let value = args[0].eval(env).toJson.jsonTo(float32)
          pstate[].scheduleMod(ptrack[], ModifierState(
            kind: ModifierKind.Timing,
            startTime: pstate.scheduleStart,
            releaseTime: pstate.scheduleStart + pstate.scheduleLen,
            floatValue: value,
          ))

    of "adsr":
      impl:
        if args.len >= 4:
          let attack = args[0].eval(env).toJson.jsonTo(float32)
          let decay = args[1].eval(env).toJson.jsonTo(float32)
          let sustainVolume = args[2].eval(env).toJson.jsonTo(float32)
          let release = args[3].eval(env).toJson.jsonTo(float32)
          pstate[].scheduleMod(ptrack[], ModifierState(
            kind: ModifierKind.Adsr,
            startTime: pstate.scheduleStart,
            releaseTime: pstate.scheduleStart + pstate.scheduleLen,
            adsr: (attack, decay, sustainVolume, release),
          ))
          ptrack[].adsr = (attack, decay, sustainVolume, release)

    of "**":
      impl:
        if args.len >= 2:
          let scheduleStart = pstate.scheduleStart
          let scheduleLen = pstate.scheduleLen
          try:
            let count = max(args[0].eval(env).toJson.jsonTo(int), 1)
            pstate.scheduleLen = scheduleLen div count
            for i in 0..<count:
              discard args[1].eval(env)
              pstate.scheduleStart += pstate.scheduleLen
          except CatchableError as e:
            raise newException(LispError, e.msg, e)
          finally:
            pstate.scheduleStart = scheduleStart
            pstate.scheduleLen = scheduleLen

    of "..":
      impl:
        if args.len >= 2:
          let scheduleNoteLen = pstate.scheduleNoteLen
          try:
            pstate.scheduleNoteLen = args[0].eval(env).toJson.jsonTo(float32)
            discard args[1].eval(env)
          except CatchableError as e:
            raise newException(LispError, e.msg, e)
          finally:
            pstate.scheduleNoteLen = scheduleNoteLen

    of "rand":
      impl:
        if args.len >= 2:
          let min = args[0].eval(env).toJson.jsonTo(float32)
          let max = args[1].eval(env).toJson.jsonTo(float32)
          return newNumber(min + rand(max - min))
        return newNumber(1)

    of "_":
      return newNil()

    else:
      if name[0] in {'A'..'G'}:
        var noteLen = 1
        if noteLen < name.len and name[noteLen] in {'b', '#'}:
          inc noteLen
        if noteLen < name.len and name[noteLen] in {'1'..'9'}:
          inc noteLen
        if noteLen < name.len and name[noteLen] in {'1'..'9'}:
          inc noteLen
        let frequency = getNotePitch(name[0..<noteLen])
        pstate[].scheduleSound(ptrack[], SoundState(
          gain: 1,
          freq: frequency,
          startTime: pstate.scheduleStart,
          releaseTime: pstate.scheduleStart + (pstate.scheduleNoteLen * pstate.scheduleLen.float32).int64,
          adsr: (0.01, 0.05, 0.8, 0.1),
        ))
        return newNil()

      log lvlError, &"Unknown pattern '{name}'"

      newNil()

  state.scheduleStart = state.nextBarSample
  state.scheduleLen = state.samplesPerBar
  track.mods.setLen(0)
  try:
    for pattern in track.patterns:
      # log lvlDebug, &"eval pattern '{pattern}'"
      state.scheduleStart = state.nextBarSample
      state.scheduleLen = state.samplesPerBar
      discard pattern.eval(env)
  except CatchableError as e:
    log lvlError, &"Failed to schedule tracks: {e.msg}"

  for modifier in track.mods:
    for sound in track.sounds.mitems:
      if sound.startTime <= modifier.releaseTime and sound.releaseTime >= modifier.startTime:
        state.modify(sound, modifier)
  env.clear()

proc scheduleTracks(state: var State) =
  # schedule sounds for next bar
  while state.nextBarSample - state.samplesPerBar < state.info.index + state.info.bufferLen:
    for track in state.tracks.mitems:
      state.scheduleTrack(track)
    state.nextBarSample += state.samplesPerBar
    inc state.barIndex

proc initSinSynth(): Sound =
  result = Sound(kind: SoundKind.Synth)
  result.layers[0] = (1.0, 1.0, Sin, 0)

proc defineTrack(state: var State, name: string, patterns: sink seq[LispVal]) =
  for track in state.tracks.mitems:
    if track.name == name:
      track.patterns = patterns
      return
  state.tracks.add(Track(name: name, patterns: patterns, sound: initSinSynth(), adsr: (0.01, 0.05, 0.8, 0.1)))

proc clearUpcomingSounds(state: var State) =
  for track in state.tracks.mitems:
    var k = 0
    while k < track.sounds.len:
      let sound {.cursor.} = track.sounds[k]

      if sound.startTime >= state.startTime:
        track.sounds.removeShift(k)
        continue
      inc k

proc runScript(state: var State) =
  let commands = state.script.parseLisp()
  if commands.kind != List:
    return

  let pstate = state.addr
  var env = baseEnv()
  env.onUndefinedSymbol = proc(_: Env, name: string): LispVal =
    template impl(body: untyped): untyped =
      newFunc(name, proc(args {.inject.}: seq[LispVal]): LispVal =
        lastSelections = selections
        body
        if self.debugMoves:
          log lvlDebug, "move '", name, "' ", $lastSelections, " -> ", selections
      )

    case name
    of "reset":
      newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
        pstate[].tracks.setLen(0)
        pstate[].bpm = 100
        pstate[].beat1 = 4
        pstate[].beat2 = 4
        return newNil()
      )
    of "bpm":
      newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
        if args.len < 1 or args[0].kind != Number:
          return newNil()
        try:
          pstate.bpm = args[0].toJson.jsonTo(int).int64
          let samplesPerMinute = pstate.info.sampleRate * 60
          let samplesPerBeat = samplesPerMinute div pstate.bpm
          let beatsPerBar = pstate.beat1
          pstate.samplesPerBar = samplesPerBeat * beatsPerBar
          return newNil()
        except CatchableError as e:
          log lvlError, &"Failed to update reverb: {e.msg}"
      )
    of "track":
      newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
        if args.len < 2 or args[0].kind != Symbol:
          return newNil()
        let name = args[0].sym
        let patterns = args[1..^1]
        pstate[].defineTrack(name, patterns)
        return newNil()
      )
    of "reverb":
      newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
        try:
          log lvlDebug, &"Set reverb {args}"
          var damping = OffsetDamp + ScaleDamp * 0.5
          var size = OffsetRoom + ScaleRoom * 0.5
          if args.len > 2:
            damping = args[2].toJson.jsonTo(float32)
          if args.len > 3:
            size = args[3].toJson.jsonTo(float32)
          pstate.reverb.setDampingAndSize(damping, size)
          pstate.reverb.dry = args[0].toJson.jsonTo(float32)
          pstate.reverb.wet = args[1].toJson.jsonTo(float32)
        except CatchableError as e:
          log lvlError, &"Failed to update reverb: {e.msg}"
        return newNil()
      )
    else:
      newNil()

  log lvlDebug, &"eval {commands}"
  let res = commands.eval(env)

  state.clearUpcomingSounds()

  state.nextBarSample -= state.samplesPerBar * 3
  state.scheduleTracks()

proc handleAudioEvent(state: var State, eventStr: string, log: bool = false) =
  let event = eventStr.parseJson.jsonTo(AudioEvent)
  case event.kind
  of SetState:
    let nextBarSample = state.nextBarSample
    let files = state.files
    state = event.setState.state
    state.keys.setLen(0)
    state.nextBarSample = nextBarSample
    state.files = files
    if state.script != "":
      state.runScript()
    if log:
      log lvlInfo, &"Set state {event.setState.state}"
  of ChangeVolume:
    state.volume += event.changeVolume.change
    if log:
      log lvlInfo, &"Volume {state.volume}"
  of ToggleMute:
    state.muted = not state.muted
    if log:
      log lvlInfo, &"Muted: {state.muted}"
  of Command:
    state.script = event.command
    state.runScript()
  of Press:
    if state.audioThread:
      for key in state.keys.mitems:
        if key.key == event.press.key and event.timestamp < key.releaseTime:
          return
      # let sampleAlign = state.samplesPerBar div 24
      # let timeInBar = event.timestamp - (state.nextBarSample - state.samplesPerBar)
      # let timeInBarAligned = (round(timeInBar.float64 / sampleAlign.float64) * sampleAlign.float64).int64
      # let time = timeInBarAligned + (state.nextBarSample - state.samplesPerBar)
      state.keys.add(KeyState(
        key: event.press.key,
        frequency: getNotePitch(event.press.note),
        startTime: event.timestamp,
        releaseTime: int64.high,
      ))
  of Release:
    if state.audioThread:
      for key in state.keys.mitems:
        if key.key == event.release.key and key.releaseTime == int64.high:
          key.releaseTime = event.timestamp
  of File:
    log lvlDebug, &"open shared buffer '{event.file.path}'"
    let buffer = SharedAudioBuffer.open(event.file.path)
    if buffer.isSome:
      log lvlDebug, &"Receive audio file {event.file.name} with {buffer.get.len} samples"
      var samples = newSeq[float32](buffer.get.len)
      buffer.get.read(0, samples)
      echo samples[0..100]
      var m = 0.0
      for s in samples:
        m = max(m, abs(s))
      log lvlDebug, &"Receive audio file {event.file.name} with {samples.len} samples, max: {m}"
      state.files[event.file.name] = AudioFile(samples: samples.ensureMove)

    # let decoded = base64.decode(event.file.samples)
    # if decoded.len > 0:
    #   let len = decoded.len div 4
    #   var samples = newSeq[float32](len)
    #   copyMem(samples[0].addr, decoded[0].addr, decoded.len)
    #   var m = 0.0
    #   for s in samples:
    #     m = max(m, abs(s))
    #   log lvlDebug, &"Receive audio file {event.file.name} with {samples.len} samples, max: {m}"
      # state.files[event.file.name] = AudioFile(samples: samples.ensureMove)

proc handleAudioEvents(state: var State, events: openArray[char], log: bool = false) =
  for line in events.toOpenArray().split('\n'.Rune):
    try:
      if line.len > 0:
        handleAudioEvent(state, line, log)
    except CatchableError as e:
      log lvlError, &"Failed to run audio command '{line}': {e.msg}"
      break

var state = State(
  runningAudio: false,
  volume: 1,
  muted: false,
  bpm: 100,
  beat1: 4,
  beat2: 4,
  reverb: initFreeVerb(0, 0.91),
)

var buffer = newSeq[float32]()
var discreteBuffer = newSeq[int16]()
var discreteBufferDownSampled = newSeq[int16]()
var startIndex: int64 = -1
var audioEventReader: Option[ReadChannel]
var audioEventWriter: Option[WriteChannel]
var audioFeedbackReader: Option[ReadChannel]
var audioFeedbackWriter: Option[WriteChannel]

proc send[T](channel: WriteChannel, value: T) =
  channel.writeBytes(wl(cast[ptr uint8](value.unsafeAddr), sizeof(T)))

proc sendAudioFeedback[T](data: openArray[T]) =
  if audioFeedbackWriter.isSome:
    audioFeedbackWriter.get.send((data.len * sizeof(T)).uint32)
    audioFeedbackWriter.get.writeBytes(wl(cast[ptr uint8](data[0].unsafeAddr), data.len * sizeof(T)))

proc sendAudioFeedback[T](data {.byref.}: T) =
  if audioFeedbackWriter.isSome:
    audioFeedbackWriter.get.send(sizeof(T).uint32)
    audioFeedbackWriter.get.writeBytes(wl(cast[ptr uint8](data.unsafeAddr), sizeof(T)))

var currentAudioFeedbackLen: int64 = -1
proc readAudioFeedback(): Option[WitList[uint8]] =
  if audioFeedbackReader.isSome:
    if currentAudioFeedbackLen < 0:
      let available = audioFeedbackReader.get.flushRead()
      if available >= sizeof(uint32):
        let data = audioFeedbackReader.get.readBytes(sizeof(uint32))
        if data.len >= sizeof(uint32):
          currentAudioFeedbackLen = cast[ptr uint32](data[0].addr)[].int
    if currentAudioFeedbackLen >= 0:
      if currentAudioFeedbackLen > 0:
        let available = audioFeedbackReader.get.flushRead()
        if available >= currentAudioFeedbackLen:
          let data = audioFeedbackReader.get.readBytes(currentAudioFeedbackLen.int32)
          currentAudioFeedbackLen = -1
          return data.some

  return WitList[uint8].none

func uncheckedArray*[T](self: openArray[T]): ptr UncheckedArray[T] =
  cast[ptr UncheckedArray[T]](self.data)

template generateSamples(tempBuffer: untyped, body: untyped): untyped =
  let dt {.inject.} = 1.0 / state.info.sampleRate.float64
  var currentTimeSeconds {.inject.} = startIndex.float64 * dt
  var currentSampleIndex {.inject.} = startIndex
  for i in 0..<bufferLen:
    let sample {.inject.} = tempBuffer[i].addr
    body
    currentTimeSeconds += dt
    currentSampleIndex += 1

proc generateSin(state: var State, track: var Track, sound: var SoundState, startIndex: int64, freq: float32, gain: float32, tempBuffer: ptr UncheckedArray[float32], bufferLen: int) =
  let dt = 1.0 / state.info.sampleRate.float64
  var currentTimeSeconds = startIndex.float64 * dt
  var currentSampleIndex = startIndex
  for i in 0..<bufferLen:
    let sample = tempBuffer[i].addr
    sample[] += sin(currentTimeSeconds, freq) * gain
    currentTimeSeconds += dt
    currentSampleIndex += 1

proc generateSaw(state: var State, track: var Track, sound: var SoundState, startIndex: int64, freq: float32, gain: float32, tempBuffer: ptr UncheckedArray[float32], bufferLen: int) =
  let dt = 1.0 / state.info.sampleRate.float64
  var currentTimeSeconds = startIndex.float64 * dt
  var currentSampleIndex = startIndex
  for i in 0..<bufferLen:
    let sample = tempBuffer[i].addr
    sample[] += saw(currentTimeSeconds, freq) * gain
    currentTimeSeconds += dt
    currentSampleIndex += 1

proc generateSquare(state: var State, track: var Track, sound: var SoundState, startIndex: int64, freq: float32, gain: float32, tempBuffer: ptr UncheckedArray[float32], bufferLen: int) =
  let dt = 1.0 / state.info.sampleRate.float64
  var currentTimeSeconds = startIndex.float64 * dt
  var currentSampleIndex = startIndex
  for i in 0..<bufferLen:
    let sample = tempBuffer[i].addr
    sample[] += square(currentTimeSeconds, freq) * gain
    currentTimeSeconds += dt
    currentSampleIndex += 1

proc generatePulse(state: var State, track: var Track, sound: var SoundState, startIndex: int64, freq: float32, width: float32, gain: float32, tempBuffer: ptr UncheckedArray[float32], bufferLen: int) =
  let dt = 1.0 / state.info.sampleRate.float64
  var currentTimeSeconds = startIndex.float64 * dt
  var currentSampleIndex = startIndex
  for i in 0..<bufferLen:
    let sample = tempBuffer[i].addr
    sample[] += pulse(currentTimeSeconds, freq, width) * gain
    currentTimeSeconds += dt
    currentSampleIndex += 1

proc generateTriangle(state: var State, track: var Track, sound: var SoundState, startIndex: int64, freq: float32, gain: float32, tempBuffer: ptr UncheckedArray[float32], bufferLen: int) =
  let dt = 1.0 / state.info.sampleRate.float64
  var currentTimeSeconds = startIndex.float64 * dt
  var currentSampleIndex = startIndex
  for i in 0..<bufferLen:
    let sample = tempBuffer[i].addr
    sample[] += triangle(currentTimeSeconds, freq) * gain
    currentTimeSeconds += dt
    currentSampleIndex += 1

proc generateAdsr(state: var State, track: var Track, sound: var SoundState, startIndex: int64, freq: float32, gain: float32, tempBuffer: ptr UncheckedArray[float32], bufferLen: int) =
  let dt = 1.0 / state.info.sampleRate.float64
  var currentTimeSeconds = startIndex.float64 * dt
  var currentSampleIndex = startIndex
  for i in 0..<bufferLen:
    let sample = tempBuffer[i].addr
    sample[] *= adsr(time = (currentSampleIndex - sound.startTime).float64 * dt, attack = sound.adsr.attack, decay = sound.adsr.decay, sustain = (sound.releaseTime - sound.startTime).float64 * dt, sustainVolume = sound.adsr.sustainVolume, release = sound.adsr.release) * gain
    currentTimeSeconds += dt
    currentSampleIndex += 1

var tempBuffer: array[10_000, float32]
proc generateSound(state: var State, track: var Track, sound: var SoundState, buffer: ptr UncheckedArray[float32], bufferLen: int64) =

  let releaseTime = if sound.releaseTime == int64.high: sound.releaseTime else: sound.releaseTime + (state.info.sampleRate.float64 * (sound.adsr.release + 0.5)).int64
  let startIndex = max(sound.startTime - state.info.index, 0).int
  let endIndex = min(releaseTime - state.info.index, bufferLen).int
  if endIndex <= startIndex:
    return
  let startSample = max(sound.startTime, state.info.index)

  let samplesToGenerate = endIndex - startIndex
  zeroMem(tempBuffer[0].addr, samplesToGenerate * sizeof(tempBuffer[0]))

  let dt {.inject.} = 1.0 / state.info.sampleRate.float64
  let currentTimeSeconds = startIndex.float64 * dt

  case track.sound.kind
  of Synth:
    for l in track.sound.layers:
      if l.gain == 0 or l.freqMul == 0:
        break
      case l.wave
      of Sin:
        state.generateSin(track, sound, startSample, sound.freq * l.freqMul, l.gain, cast[ptr UncheckedArray[float32]](tempBuffer[0].addr), samplesToGenerate)
      of Saw:
        state.generateSaw(track, sound, startSample, sound.freq * l.freqMul, l.gain, cast[ptr UncheckedArray[float32]](tempBuffer[0].addr), samplesToGenerate)
      of Square:
        state.generateSquare(track, sound, startSample, sound.freq * l.freqMul, l.gain, cast[ptr UncheckedArray[float32]](tempBuffer[0].addr), samplesToGenerate)
      # of Noise:
      #   state.generateSaw(track, sound, startSample, sound.freq * l.freqMul, l.gain, cast[ptr UncheckedArray[float32]](tempBuffer[0].addr), samplesToGenerate)
      of Triangle:
        state.generateTriangle(track, sound, startSample, sound.freq * l.freqMul, l.gain, cast[ptr UncheckedArray[float32]](tempBuffer[0].addr), samplesToGenerate)
      of Pulse:
        state.generatePulse(track, sound, startSample, sound.freq * l.freqMul, l.arg1, l.gain, cast[ptr UncheckedArray[float32]](tempBuffer[0].addr), samplesToGenerate)
      else:
        discard
    state.generateAdsr(track, sound, startSample, 1, sound.gain, cast[ptr UncheckedArray[float32]](tempBuffer[0].addr), samplesToGenerate)
  of Sample:
    if state.files.contains(track.sound.name):
      let file = state.files[track.sound.name].addr
      let fileStartIndex = max(startSample - sound.startTime, 0)
      let fileEndIndex = min(releaseTime - sound.startTime, file.samples.len)
      if fileStartIndex < fileEndIndex:
        let samplesToCopy = fileEndIndex - fileStartIndex
        copyMem(tempBuffer[0].addr, file.samples[fileStartIndex].addr, min(samplesToGenerate, samplesToCopy) * sizeof(float32))
    # else:
      # sample += sin(time, 880) * 1
  else:
    discard

  for i in 0..<samplesToGenerate:
    buffer[startIndex + i] += tempBuffer[i]

var audioThreadInitialized = false
var lastFeedback = AudioFeedback()
proc generateAudio(data: uint32, info: AudioArgs): ptr UncheckedArray[int16] {.cdecl.} =
  if not audioThreadInitialized:
    log lvlDebug, "Init audio thread..."
    emscripten_stack_init()
    NimMain()
    audioThreadInitialized = true

  state.audioThread = true
  state.startTime = info.index
  state.sampleRate = info.sampleRate
  state.info = info

  let start = getTime()
  if startIndex < 0:
    startIndex = info.index
    audioEventReader = readChannelOpen("audio-events")
    audioFeedbackWriter = writeChannelOpen("audio-feedback")

    state.script = "(reset) (bpm 100) (reverb 1 1 1 0) (track kick (** 4 C3))"
    state.runScript()

  var events = WitString()
  if audioEventReader.isSome:
    discard audioEventReader.get.flushRead()
    events = audioEventReader.get.readAllString()

  if events.len > 0:
    handleAudioEvents(state, events.toOpenArray(), log = true)

  let samplesPerMinute = info.sampleRate * 60
  let samplesPerBeat = samplesPerMinute div state.bpm
  let beatsPerBar = state.beat1
  state.samplesPerBar = samplesPerBeat * beatsPerBar

  # log lvlInfo, &"generate audio {data} with {info}"
  buffer.setLen(info.bufferLen)
  discreteBuffer.setLen(info.bufferLen)

  let sampleTime = 1.0 / info.sampleRate.float64

  let index = info.index

  # for key in state.keys:
  #   echo &"key {key} -> {key.startTime - index}, {(index - key.startTime).float64 * sampleTime}, {(index + buffer.len - key.startTime).float64 * sampleTime}"

  state.scheduleTracks()

  var totalSounds = 0
  var soundsPlayed = 0
  for v in buffer.mitems:
    v = 0

  for track in state.tracks.mitems:
    var k = 0
    while k < track.sounds.len:
      let sound = track.sounds[k].addr
      inc totalSounds

      let endTime = if sound.releaseTime == int64.high: sound.releaseTime else: sound.releaseTime + (info.sampleRate.float64 * (sound.adsr.release + 0.5)).int64
      if sound.startTime > info.index + buffer.len:
        # Sound doesn't start yet
        inc k
        continue
      if endTime < info.index:
        # Sound ended before this buffer, remove it.
        track.sounds.removeShift(k)
        continue

      inc soundsPlayed

      state.generateSound(track, sound[], cast[ptr UncheckedArray[float32]](buffer[0].addr), buffer.len)

      inc k

  # keys
  block:
    var k = 0
    while k < state.keys.len:
      inc totalSounds
      let key {.cursor.} = state.keys[k]

      let endTime = if key.releaseTime == int64.high: key.releaseTime else: key.releaseTime + info.sampleRate div 2
      if key.startTime > info.index + buffer.len:
        # Sound doesn't start yet
        inc k
        continue
      if endTime < info.index:
        # Sound ended before this buffer, remove it.
        state.keys.removeShift(k)
        continue

      inc soundsPlayed

      var sound = SoundState(
        gain: 1,
        freq: key.frequency,
        startTime: key.startTime,
        releaseTime: key.releaseTime,
        adsr: if state.tracks.len > 0: state.tracks[0].adsr else: (0.01, 0.2, 0.8, 0.1),
      )

      state.generateSound(state.tracks[0], sound, cast[ptr UncheckedArray[float32]](buffer[0].addr), buffer.len)
      # let dt = 1 / info.sampleRate.float64
      # var i = max(sound.startTime - info.index, 0)
      # var t = max(sound.startTime, info.index)
      # var time = t.float64 / info.sampleRate.float64
      # while i < buffer.len and t < endTime:
      #   var sample = 0.0
      #   if state.tracks.len > 0:
      #     sample = state.generateSynth(state.tracks[0], sound, time, t, sampleTime)
      #   else:
      #     let vol = adsr(time = (t - sound.startTime).float64 * sampleTime, attack = 0.01, decay = 0.2, sustain = (sound.releaseTime - sound.startTime).float64 * sampleTime, sustainVolume = 0.8, release = 0.1)
      #     sample += sin(time, sound.freq) * vol * 0.8

      #   buffer[i] += sample
      #   inc i
      #   inc t
      #   time += dt

      inc k

  for i in 0..<buffer.len:
    buffer[i] = state.reverb.process(buffer[i])

  for i in 0..<buffer.len:
    discreteBuffer[i] = int16(buffer[i] * state.volume * 2550)

  let downsampleFactor = 2
  discreteBufferDownSampled.setLen(discreteBuffer.len div downsampleFactor)
  for i in 0..discreteBufferDownSampled.high:
    var sample: float32 = 0
    for k in (i * downsampleFactor)..<(i * downsampleFactor + downsampleFactor):
      sample += discreteBuffer[k].float32
    sample /= downsampleFactor.float32
    discreteBufferDownSampled[i] = sample.int16

  lastFeedback.activeSounds = soundsPlayed
  lastFeedback.totalSounds = totalSounds
  lastFeedback.alignOffset = min(alignOffset(lastFeedback.samples, discreteBufferDownSampled), 0)
  copyMem(lastFeedback.samples[0].addr, discreteBufferDownSampled[-lastFeedback.alignOffset].addr, min(lastFeedback.samples.len, discreteBufferDownSampled.len + lastFeedback.alignOffset))
  lastFeedback.dt = getTime() - start
  sendAudioFeedback(lastFeedback)

  if state.muted:
    for i in 0..<buffer.len:
      discreteBuffer[i] = 0
  return cast[ptr UncheckedArray[int16]](discreteBuffer[0].addr)

proc sendAudioFile(name: string, file: SharedAudioBuffer) =
  let path = file.mount(&"audioex-buffer-{name}", unique = true)
  if audioEventWriter.isSome and file.len > 0:
    log lvlInfo, &"sendAudioFile '{name}', {file.len} samples -> '{path}'"
    # var encoded = base64.encode(cast[ptr UncheckedArray[uint8]](file.samples[0][0].addr).toOpenArray(0, file.samples[0].len * 4 - 1))
    audioEventWriter.get.writeString($AudioEvent(kind: File, file: (name, path)).toJson & "\n")

proc openCustomView(show: bool)
proc addAudioCallback() =
  var (reader1, writer1) = newInMemoryChannel()
  var (reader2, writer2) = newInMemoryChannel()
  let path = reader1.readChannelMount("audio-events", false)
  discard writer2.writeChannelMount("audio-feedback", false)
  audioEventWriter = writer1.some
  audioFeedbackReader = reader2.some

  state.runningAudio = true
  addAudioCallback(cast[uint32](generateAudio), 0)
  openCustomView(show = true)

  # loadWavFile("audio-samples://Drums/")
  sendAudioFile("bd1", loadWavFile("D:/Music/SamplePacks/Drums/Kick/Analogue - Fat 01 Kick.wav"))
  sendAudioFile("sd1", loadWavFile("D:/Music/SamplePacks/Drums/Snare/Analogue - Med 03 Snare.wav"))
  sendAudioFile("hh1", loadWavFile("D:/Music/SamplePacks/Drums/Hats/Analogue - Med 06 CH.wav"))

proc stopAudio() =
  state.runningAudio = false

setPluginSaveCallback proc(): WitList[uint8] =
  state.reverb = default(typeof(state.reverb))
  let stateJson = $state.toJson
  log lvlInfo, &"Save state {stateJson}"
  return stackWitList(cast[ptr UncheckedArray[uint8]](stateJson[0].addr).toOpenArray(0, stateJson.high))

setPluginLoadCallback proc(rawState: WitList[uint8]) =
  let stateJson = cast[ptr UncheckedArray[char]](rawState[0].addr).toOpenArray(0, rawState.len - 1).join("")
  log lvlInfo, &"Restore state {stateJson}"
  state = stateJson.parseJson.jsonTo(State)
  if state.runningAudio:
    addAudioCallback()
    if audioEventWriter.isSome:
      audioEventWriter.get.writeString($AudioEvent(kind: SetState, setState: (state,)).toJson & "\n")

proc openCustomView(show: bool) =
  var renderView = renderViewFromUserId(ws"test_plugin_view")
  if renderView.isNone:
    log lvlInfo, "[guest] Create new RenderView"
    renderView = newRenderView().some
  else:
    log lvlInfo, "[guest] Reusing existing RenderView"
  renderView.get.setUserId(ws"test_plugin_view")
  renderView.get.setRenderWhenInactive(true)
  renderView.get.setPreventThrottling(true)
  renderView.get.setRenderCallback(cast[uint32](handleViewRender), views.len.uint32)
  renderView.get.addMode(ws"test-plugin")
  renderView.get.markDirty()
  if show:
    # discard runCommand("wrap-layout", """{"kind": "horizontal", "temporary": true, "max-children": 2}""")
    show(renderView.get.view, ws"**.+<>", false, false)
  views.add(renderView.take)

converter toRect(c: ClayBoundingBox): bumpy.Rect =
  rect(c.x, c.y, c.width, c.height)

converter toColor(c: ClayColor): Color =
  color(c.r / 255, c.g / 255, c.b / 255, c.a / 255)

converter toClayVec(c: Vec2f): ClayVector2 =
  ClayVector2(x: c.x, y: c.y)

converter toClayVec(c: Vec2): ClayVector2 =
  ClayVector2(x: c.x, y: c.y)

converter toVec(c: Vec2f): Vec2 =
  vec2(c.x, c.y)

proc encodeClayRenderCommands(renderCommandEncoder: var BinaryEncoder, clayRenderCommands: ClayRenderCommandArray) =
  buildCommands(renderCommandEncoder):
    for c in clayRenderCommands:
      case c.commandType
      of None:
        discard
      of Rectangle:
        let color = c.renderData.rectangle.backgroundColor.toColor
        let bounds = c.boundingBox.toRect
        fillRect(bounds, color)
      of Border:
        let color = c.renderData.border.color.toColor
        let bounds = c.boundingBox.toRect
        # let width = c.renderData.border.width
        # todo: width > 1
        drawRect(bounds, color)
      of Text:
        let color = c.renderData.text.textColor.toColor
        let bounds = c.boundingBox.toRect
        drawText(c.renderData.text.stringContents.toOpenArray(), bounds, color, 0.UINodeFlags)
      of Image:
        log lvlError, &"Not implemented: {c.commandType}"
      of ScissorStart:
        startScissor(c.boundingBox.toRect)
      of ScissorEnd:
        endScissor()
      of Custom:
        log lvlError, &"Not implemented: {c.commandType}"

var lastTime = 0.0
var lastRenderTime = 0.0
var lastRenderTimeStr = ""
proc handleViewRender(id: int32, data: uint32) {.cdecl.} =
  let index = data.int
  if index notin 0..views.high:
    log lvlError, "handleViewRender: index out of bounds {index} notin 0..<{views.len}"
    return

  let view {.cursor.} = views[index]

  try:
    while true:
      let feedback = readAudioFeedback()
      if feedback.isNone:
        break

      lastFeedback = cast[ptr AudioFeedback](feedback.get[0].addr)[]
    # if audioFeedbackReader.isSome:
    #   let available = audioFeedbackReader.get.flushRead()
    #   if available >= sizeof(AudioFeedback):
    #     let data = audioFeedbackReader.get.readBytes(sizeof(AudioFeedback))
    #     if data.len >= sizeof(AudioFeedback):
    #       lastFeedback = cast[ptr AudioFeedback](data[0].addr)[]

    let start = getTime()
    let deltaTime = start / 1000 - lastTime
    lastTime = start / 1000

    proc vec2(v: Vec2f): Vec2 = vec2(v.x, v.y)

    let size = vec2(view.size)

    clay.setLayoutDimensions(ClayDimensions(width: size.x, height: size.y))
    clay.setPointerState(view.mousePos, view.mouseDown(0))
    clay.updateScrollContainers(true, view.scrollDelta.toVec * 4.0, deltaTime)

    var layoutElement = ClayLayoutConfig(padding: ClayPadding(left: 2, right: 2), layoutDirection: TopToBottom)
    var descTextConfig = ClayTextElementConfig(textColor: clayColor(1, 1, 1))
    var valueTextConfig = ClayTextElementConfig(textColor: clayColor(1, 0.6, 0.3))

    template setting(name: string, value: string): untyped =
      var valueStr = value
      UI(layout = ClayLayoutConfig(padding: ClayPadding(left: 10, right: 10))):
        clayText(name, textColor = clayColor(1, 1, 1))
        clayText(": ", textColor = clayColor(1, 1, 1))
        clayText(valueStr, valueTextConfig)

    clay.beginLayout()
    UI(backgroundColor = clayColor(0.15, 0.15, 0.15), layout = layoutElement, clip = ClayClipElementConfig(vertical: true, childOffset: clay.getScrollOffset())):
      setting("Muted", $state.muted)
      setting("Volume", $state.volume)
      setting("Audio thread ms", $((lastFeedback.dt * 10).int / 10))
      setting("Align", $lastFeedback.alignOffset)
      setting("Sounds", &"{lastFeedback.activeSounds}/{lastFeedback.totalSounds}")

    let clayRenderCommands = clay.endLayout()

    renderCommandEncoder.buffer.setLen(0)
    renderCommandEncoder.encodeClayRenderCommands(clayRenderCommands)

    if gwav.samples.len > 0:
      buildCommands(renderCommandEncoder):
        for x in 0..gwav.samples[0].high:
          let t = x.float32 / 200
          # let vol = adsr(time = t, attack = 0.2, decay = 0.4, sustain = 1, sustainVolume = 0.8, release = 0.3)
          let vol = (gwav.samples[0][min(gwav.samples[0].high, x * 40)]).float32
          let y = 1000.0 - vol * 300
          let h = 1000.0 - y
          fillRect(rect(x.float32 * 1, y, 1, h), color(0.5, 0.5, 0.5))
          if x > 1000:
            break

    buildCommands(renderCommandEncoder):
      for x in 0..lastFeedback.samples.high:
        let t = x.float32 / 200
        # let vol = adsr(time = t, attack = 0.2, decay = 0.4, sustain = 1, sustainVolume = 0.8, release = 0.3)
        let vol = (lastFeedback.samples[x]).float32 / 8550.0
        let y = 500.0 - vol * 500
        let h = 500.0 - y
        fillRect(rect(x.float32 * 3, y, 3, h), color(0.5, 0.5, 0.5))

    view.setRenderCommands(@@(renderCommandEncoder.buffer.toOpenArray(0, renderCommandEncoder.buffer.high)))

    let interval = getSetting("test.render-interval", 500)
    view.setRenderInterval(interval)

    let elapsed = getTime() - start
    lastRenderTime = lerp(lastRenderTime, elapsed, 0.1)
    lastRenderTimeStr = &"dt: {lastRenderTime} ms"
  except Exception as e:
    log lvlError, &"[guest] Failed to render: {e.msg}\n{e.getStackTrace()}"

defineCommand(ws"toggle-clay-debug-mode",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 0):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    toggleClayDebugMode()
    return ws""

defineCommand(ws"test-audio",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let editor = activeTextEditor({})
      addAudioCallback()
      if editor.isSome:
        if audioEventWriter.isSome:
          let command = editor.get.content.text
          state.script = $command
          audioEventWriter.get.writeString($AudioEvent(kind: Command, command: $command).toJson & "\n")
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"stop-audio",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      stopAudio()
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"toggle-muted",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      if audioEventWriter.isSome:
        audioEventWriter.get.writeString("toggle-mute\n")
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"eval-audio-file",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      let editor = activeTextEditor({})
      if editor.isSome:
        if audioEventWriter.isSome:
          let command = editor.get.content.text
          state.script = $command
          audioEventWriter.get.writeString($AudioEvent(kind: Command, command: $command).toJson & "\n")
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

defineCommand(ws"send-audio-event",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    try:
      var j = ($args).parseJson
      if j.kind == JObject:
        if j.hasKey("kind"):
          j["kind"] = j["kind"].jsonTo(AudioEventKind).int.toJson
        j["timestamp"] = nextAudioSample().toJson()

      handleAudioEvents(state, $j)
      if audioEventWriter.isSome:
        audioEventWriter.get.writeString($j & "\n")
    except CatchableError as e:
      log lvlError, &"[guest] err: {e.msg}"
    return ws""

var bufferSize = 25
var tripleBuffer = false

defineCommand(ws"toggle-triple-buffering",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    tripleBuffer = not tripleBuffer
    log lvlInfo, &"Enable triple audio buffering {tripleBuffer}"
    audio.enableTripleBuffering(tripleBuffer)
    return ws""

defineCommand(ws"increase-buffer-size",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    bufferSize += 1
    log lvlInfo, &"Set audio buffer size {bufferSize} ms"
    audio.setBufferSize(bufferSize * 48000 div 1000)
    return ws""

defineCommand(ws"decrease-buffer-size",
  active = false,
  docs = ws"",
  params = wl[(WitString, WitString)](nil, 0),
  returnType = ws"",
  context = ws"",
  data = 123):
  proc(data: uint32, args: WitString): WitString {.cdecl.} =
    bufferSize -= 1
    log lvlInfo, &"Set audio buffer size {bufferSize} ms"
    audio.setBufferSize(bufferSize * 48000 div 1000)
    return ws""
