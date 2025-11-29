import std/[strformat, json, jsonutils, strutils, math, unicode, macros]
import results
import util, render_command, binary_encoder
import "../../src/lisp"
import api
import clay

var views: seq[RenderView] = @[]
var renderCommandEncoder: BinaryEncoder

const FixedGain = 0.05
const ScaleWet = 3.0
const ScaleRoom = 0.28
const OffsetRoom = 0.7
const ScaleDamp = 0.4
const OffsetDamp = 0.1

converter toWitString(s: string): WitString = ws(s)
var target = 50

proc handleViewRender(id: int32, data: uint32) {.cdecl.}

proc fib(n: int64): int64 =
  if n <= 1:
    return 1
  return fib(n - 1) + fib(n - 2)

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

proc getNotePitch(note: string): float =
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
    frequency: float
    startTime: int64
    releaseTime: int64

  AudioFeedback = object
    dt: float
    activeSounds: int
    totalSounds: int
    samples: array[1000, int16]

  PitchKind = enum Frequency, Note
  Pitch = object
    case kind: PitchKind
    of Frequency:
      freq: float
    of Note:
      name: string

  CombFilter = object
    buffer: seq[float]
    index: int
    dampingTarget: float
    feedback: float
    damping: float

  AllPassFilter = object
    buffer: seq[float]
    index: int
    feedback: float

  SchroederReverb = object
    combs: seq[CombFilter]
    allpasses: seq[AllPassFilter]
    dry: float
    wet: float

  FreeVerb = object
    combs: seq[CombFilter]
    allpasses: seq[AllPassFilter]
    dry: float
    wet: float
    damping: float
    size: float

  SoundState = object
    pitch: Pitch
    freq: float
    startTime: int64
    releaseTime: int64

  Track = object
    name: string
    pattern: LispVal

  State = object
    runningAudio: bool
    volume: float
    frequency: float
    muted: bool
    audioThread: bool
    keys: seq[KeyState]
    sounds: seq[SoundState]
    startTime: int64
    bpm: int64
    beat1: int64
    beat2: int64
    nextBarSample: int64
    tracks: seq[Track]
    script: string
    reverb: FreeVerb

type
  AudioEventKind = enum
    SetState = "set-state"
    ChangeVolume = "change-volume"
    ToggleMute = "toggle-mute"
    Command = "command"
    Press = "press"
    Release = "release"
    Reset = "reset"

  AudioEvent = object
    timestamp: int64
    case kind: AudioEventKind
    of SetState:
      setState: tuple[state: State]
    of ChangeVolume:
      changeVolume: tuple[change: float]
    of ToggleMute, Reset:
      discard
    of Command:
      command: string
    of Press:
      press: tuple[key: int, freq: float]
    of Release:
      release: tuple[key: int]

proc initCombFilter(bufferSize: int, feedback: float, damping: float = 0): CombFilter =
  CombFilter(buffer: newSeq[float](bufferSize), feedback: feedback, damping: damping)

proc initAllPassFilter(bufferSize: int, feedback: float): AllPassFilter =
  AllPassFilter(buffer: newSeq[float](bufferSize), feedback: feedback)

proc initFreeVerb(damping: float, size: float): FreeVerb =
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

proc process(filter: var CombFilter, input: float): float =
  let output = filter.buffer[filter.index]
  filter.dampingTarget = (output * (1.0 - filter.damping)) + (filter.dampingTarget * filter.damping)
  filter.buffer[filter.index] = input + filter.dampingTarget * min(filter.feedback, 1)
  inc filter.index
  if filter.index >= filter.buffer.len:
    filter.index = 0
  return output

proc process(filter: var AllPassFilter, input: float): float =
  let bufOut = filter.buffer[filter.index]
  let output = -input + bufOut
  filter.buffer[filter.index] = input + bufOut * min(filter.feedback, 1)
  inc filter.index
  if filter.index >= filter.buffer.len:
    filter.index = 0
  return output

proc process(reverb: var SchroederReverb, x: float): float =
  var sum = 0.0
  for comb in reverb.combs.mitems:
    sum += comb.process(x)

  var ap = sum
  for allpass in reverb.allpasses.mitems:
    ap = allpass.process(ap)

  return x * reverb.dry + ap * reverb.wet

proc process(reverb: var FreeVerb, input: float): float =
  let inputScaled = input * FixedGain
  var acc = 0.0
  for comb in reverb.combs.mitems:
    acc += comb.process(inputScaled)

  for allpass in reverb.allpasses.mitems:
    acc = allpass.process(acc)

  return input * reverb.dry + acc * reverb.wet

proc sin(time, freq: float): float =
  return sin(time * PI * 2 * freq)

proc saw(time, freq: float): float =
  return fract(time * freq)

proc square(time, freq: float): float =
  return round(fract(time * freq))

proc adsr(time, attack, decay, sustain, sustainVolume, release: float): float =
  let sustain = max(sustain - attack - decay, 0)
  var time = time
  if time < 0:
    return 0
  if time <= attack:
    return time / attack
  time -= attack
  if time <= decay:
    let alpha = time / decay
    return lerp(1.float, sustainVolume, alpha)
  time -= decay
  if time <= sustain:
    return sustainVolume

  time -= sustain
  let alpha = time / release
  return lerp(sustainVolume, 0, min(alpha, 1))

proc schedulePattern(state: var State, pattern: LispVal, info: AudioArgs, startSample: int64, len: int64) =
  case pattern.kind
  of List:
    let divisions = pattern.elems.len
    let divisionLen = len div divisions
    var startSample = startSample
    for i in 0..<divisions:
      state.schedulePattern(pattern.elems[i], info, startSample, divisionLen)
      startSample += divisionLen
  of Symbol:
    case pattern.sym
    of "bd":
      state.sounds.add(SoundState(
        freq: 220,
        startTime: startSample,
        releaseTime: startSample,
      ))
    of "sd":
      state.sounds.add(SoundState(
        freq: 330,
        startTime: startSample,
        releaseTime: startSample,
      ))
    of "hh":
      state.sounds.add(SoundState(
        freq: 550,
        startTime: startSample,
        releaseTime: startSample,
      ))
    of "_":
      discard
    else:
      state.sounds.add(SoundState(
        freq: getNotePitch(pattern.sym),
        startTime: startSample,
        releaseTime: startSample,
      ))
  else:
    discard

proc scheduleTrack(state: var State, track: Track, info: AudioArgs) =
  # log lvlDebug, &"scheduleTrack {track}"

  let samplesPerMinute = info.sampleRate * 60
  let samplesPerBeat = samplesPerMinute div state.bpm
  let beatsPerBar = state.beat1
  let samplesPerBar = samplesPerBeat * beatsPerBar

  state.schedulePattern(track.pattern, info, state.nextBarSample, samplesPerBar)

  # state.defineSound "kick", "(pattern hi hi hi)"

proc defineTrack(state: var State, name: string, pattern: LispVal) =
  for track in state.tracks.mitems:
    if track.name == name:
      track.pattern = pattern
      return
  state.tracks.add(Track(name: name, pattern: pattern))

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
    of "track":
      newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
        if args.len < 2 or args[0].kind != Symbol:
          return newNil()
        let name = args[0].sym
        let pattern = args[1]
        pstate[].defineTrack(name, pattern)
        return newNil()
      )
    of "reverb":
      newFunc(name, false, proc(args {.inject.}: seq[LispVal]): LispVal =
        try:
          log lvlDebug, &"Set reverb {args}"
          # pstate.reverb = SchroederReverb(
          #   combs: @[
          #     initCombFilter(1551, 0.8),
          #     initCombFilter(1626, 0.8),
          #     initCombFilter(1698, 0.8),
          #     initCombFilter(1764, 0.8),
          #   ],
          #   allpasses: @[
          #     initAllPassFilter(245, 0.5),
          #     initAllPassFilter(606, 0.5),
          #   ],
          #   dry: 0.7,
          #   wet: 0.3,
          # )
          var damping = OffsetDamp + ScaleDamp * 0.5
          var size = OffsetRoom + ScaleRoom * 0.5
          if args.len > 2:
            damping = args[2].toJson.jsonTo(float)
          if args.len > 3:
            size = args[3].toJson.jsonTo(float)
          pstate.reverb = initFreeVerb(damping, size)
          pstate.reverb.dry = args[0].toJson.jsonTo(float)
          pstate.reverb.wet = args[1].toJson.jsonTo(float)
        except CatchableError as e:
          log lvlError, &"Failed to update reverb: {e.msg}"
        return newNil()
      )
    else:
      newNil()

  log lvlDebug, &"eval {commands}"
  let res = commands.eval(env)

proc handleAudioEvent(state: var State, eventStr: string, log: bool = false) =
  let event = eventStr.parseJson.jsonTo(AudioEvent)
  case event.kind
  of SetState:
    let nextBarSample = state.nextBarSample
    state = event.setState.state
    state.keys.setLen(0)
    state.sounds.setLen(0)
    state.nextBarSample = nextBarSample
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
      # state.sounds.add(SoundState(
        # key: event.press.key,
      #   frequency: event.press.freq,
      #   startTime: event.timestamp,
      #   releaseTime: int64.high,
      # ))
      # state.keys.add(KeyState(
      #   key: event.press.key,
      #   frequency: event.press.freq,
      #   startTime: event.timestamp,
      #   releaseTime: int64.high,
      # ))
      if log:
        log lvlInfo, &"Play freq {state.frequency}"
  of Release:
    if state.audioThread:
      for key in state.keys.mitems:
        if key.key == event.release.key and key.releaseTime == int64.high:
          key.releaseTime = event.timestamp
  of Reset:
    state.frequency = 220
    if log:
      log lvlInfo, &"Reset {state}"

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
  frequency: 220,
  muted: false,
  bpm: 100,
  beat1: 4,
  beat2: 4,
)

var buffer = newSeq[float]()
var discreteBuffer = newSeq[int16]()
var startIndex: int64 = -1
var audioEventReader: Option[ReadChannel]
var audioEventWriter: Option[WriteChannel]
var audioFeedbackReader: Option[ReadChannel]
var audioFeedbackWriter: Option[WriteChannel]

proc send[T](channel: WriteChannel, value: T) =
  channel.writeBytes(wl(cast[ptr uint8](value.unsafeAddr), sizeof(T)))

proc sendAudioFeedback[T](data: openArray[T]) =
  if audioFeedbackWriter.isSome:
    # var len: uint32 = data.len
    # audioFeedbackWriter.get.writeBytes(wl(cast[ptr uint8](len.addr), sizeof(len)))
    audioFeedbackWriter.get.send((data.len * sizeof(T)).uint32)
    audioFeedbackWriter.get.writeBytes(wl(cast[ptr uint8](data[0].unsafeAddr), data.len * sizeof(T)))

proc sendAudioFeedback[T](data {.byref.}: T) =
  if audioFeedbackWriter.isSome:
    # var len: uint32 = sizeof(T).uint32
    # audioFeedbackWriter.get.writeBytes(wl(cast[ptr uint8](len.addr), sizeof(len)))
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

  let start = getTime()
  if startIndex < 0:
    state = State(
      runningAudio: false,
      volume: 1,
      frequency: 220,
      muted: false,
      bpm: 100,
      beat1: 4,
      beat2: 4,
    )

    startIndex = info.index
    audioEventReader = readChannelOpen("audio-events")
    audioFeedbackWriter = writeChannelOpen("audio-feedback")

    state.script = "(track kick (bd bd bd))"
    state.runScript()

  var events = WitString()
  if audioEventReader.isSome:
    discard audioEventReader.get.flushRead()
    events = audioEventReader.get.readAllString()

  if events.len > 0:
    handleAudioEvents(state, events.toOpenArray(), log = true)

  # log lvlInfo, &"generate audio {data} with {info}"
  buffer.setLen(info.bufferLen)
  discreteBuffer.setLen(info.bufferLen)

  let sampleTime = 1.0 / info.sampleRate.float

  let index = info.index

  # for key in state.keys:
  #   echo &"key {key} -> {key.startTime - index}, {(index - key.startTime).float * sampleTime}, {(index + buffer.len - key.startTime).float * sampleTime}"

  let samplesPerMinute = info.sampleRate * 60
  let samplesPerBeat = samplesPerMinute div state.bpm
  let beatsPerBar = state.beat1
  let samplesPerBar = samplesPerBeat * beatsPerBar

  if info.index >= state.nextBarSample:
    # schedule sounds for next bar
    while state.nextBarSample + samplesPerBar < info.index:
      state.nextBarSample += samplesPerBar
    for track in state.tracks:
      state.scheduleTrack(track, info)
    state.nextBarSample += samplesPerBar

  var soundsPlayed = 0
  for v in buffer.mitems:
    v = 0
  var k = 0
  while k < state.sounds.len:
    let sound {.cursor.} = state.sounds[k]

    let endTime = sound.releaseTime + info.sampleRate div 2
    if sound.startTime > info.index + buffer.len:
      # Sound doesn't start yet
      inc k
      continue
    if endTime < info.index:
      # Sound ended before this buffer, remove it.
      state.sounds.removeShift(k)
      continue

    inc soundsPlayed

    let dt = 1 / info.sampleRate.float
    var i = max(sound.startTime - info.index, 0)
    var t = max(sound.startTime, info.index)
    var time = t.float / info.sampleRate.float
    while i < buffer.len and t < endTime:
      var sample = 0.0

      let vol = adsr(time = (t - sound.startTime).float * sampleTime, attack = 0.01, decay = 0.2, sustain = (sound.releaseTime - sound.startTime).float * sampleTime, sustainVolume = 0.8, release = 0.1)
      sample += sin(time, sound.freq) * vol
        # saw(time, sound.frequency * 2) * vol * 0.85 +
        # square(time, sound.frequency * 4) * vol * 0.55

      buffer[i] += sample
      inc i
      inc t
      time += dt

    inc k

  for i in 0..<buffer.len:
    buffer[i] = state.reverb.process(buffer[i])

  if not state.muted:
    for i in 0..<buffer.len:
      discreteBuffer[i] = int16(buffer[i] * state.volume * 2550)
  else:
    for i in 0..<buffer.len:
      discreteBuffer[i] = 0

  lastFeedback.dt = getTime() - start
  lastFeedback.activeSounds = soundsPlayed
  lastFeedback.totalSounds = state.sounds.len
  copyMem(lastFeedback.samples[0].addr, discreteBuffer[0].addr, min(lastFeedback.samples.len, discreteBuffer.len))
  sendAudioFeedback(lastFeedback)
  return cast[ptr UncheckedArray[int16]](discreteBuffer[0].addr)

proc addAudioCallback() =
  var (reader1, writer1) = newInMemoryChannel()
  var (reader2, writer2) = newInMemoryChannel()
  let path = reader1.readChannelMount("audio-events", false)
  discard writer2.writeChannelMount("audio-feedback", false)
  audioEventWriter = writer1.some
  audioFeedbackReader = reader2.some

  state.runningAudio = true
  addAudioCallback(cast[uint32](generateAudio), 0)

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
    discard runCommand("wrap-layout", """{"kind": "horizontal", "temporary": true, "max-children": 2}""")
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
      setting("Sounds", &"{lastFeedback.activeSounds}/{lastFeedback.totalSounds}")

    let clayRenderCommands = clay.endLayout()

    renderCommandEncoder.buffer.setLen(0)
    renderCommandEncoder.encodeClayRenderCommands(clayRenderCommands)

    buildCommands(renderCommandEncoder):
      for x in 0..lastFeedback.samples.high:
        let t = x.float / 200
        # let vol = adsr(time = t, attack = 0.2, decay = 0.4, sustain = 1, sustainVolume = 0.8, release = 0.3)
        let vol = (lastFeedback.samples[x]).float / 8550.0
        let y = 800.0 - vol * 500
        let h = 800.0 - y
        fillRect(rect(x.float, y, 1, h), color(1, 1, 1))

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
      openCustomView(show = true)
      addAudioCallback()
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
