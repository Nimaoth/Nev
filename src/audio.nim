import std/[math, atomics, strformat]
import misc/[util, timer]
import winim

type
  AudioCallback* = proc(buffer: var openArray[int16], index: int, channelInfo: ChannelInfo): bool {.gcsafe, raises: [].}
  AudioCallbackData* = object
    data*: pointer
    cb*: proc(data: pointer, buffer: var openArray[int16], index: int, channelInfo: ChannelInfo): bool {.gcsafe, raises: [].}

  ChannelInfo* = object
    sampleRate*: int

const sampleRate = 48000
const bitsPerSample = 16
const numChannels = 1

const chunkSamples = sampleRate div 1000 * 50
var buffer1: array[chunkSamples, int16]
var buffer2: array[chunkSamples, int16]
var buffer3: array[chunkSamples, int16]

var audioCallbackChannel: Channel[AudioCallbackData]
audioCallbackChannel.open()

var audioTimer = startTimer()
var currentAudioSample: Atomic[int64]
var nextAudioSample: Atomic[int64]
var currentAudioTime: Atomic[float]
var currentSampleRate: Atomic[int64]

proc addAudioCallback*(cb: AudioCallback) =
  type Data = object
    cb: AudioCallback

  proc call(data: pointer, buffer: var openArray[int16], index: int, channelInfo: ChannelInfo): bool {.gcsafe, raises: [].} =
    let data = cast[ptr Data](data)
    data.cb(buffer, index, channelInfo)

  let data = create(Data)
  data.cb = cb
  audioCallbackChannel.send(AudioCallbackData(data: data, cb: call))

proc getNextAudioSample*(): int64 =
  var sample = (audioTimer.elapsed.float64 * currentSampleRate.load().float64).int64
  # echo &"getNextAudioSample {currentAudioSample.load}, {nextAudioSample.load}, {currentAudioTime} -> {sample}"
  if sample < nextAudioSample.load():
    sample = nextAudioSample.load()
  return sample

proc audioThread(s: int) {.thread, nimcall.} =
  var waveOutHandle = HWAVEOUT.default
  var format = WAVEFORMATEX(
    wFormatTag: WAVE_FORMAT_PCM,
    nChannels: WORD(numChannels),
    nSamplesPerSec: sampleRate.DWORD,
    nAvgBytesPerSec: DWORD(sampleRate * bitsPerSample * numChannels / 8),
    nBlockAlign: WORD(bitsPerSample * numChannels / 8),
    wBitsPerSample: bitsPerSample,
    cbSize: 0,
  )
  if waveOutOpen(waveOutHandle.addr, WAVE_MAPPER, format.addr, 0, 0, CALLBACK_NULL) != MMSYSERR_NOERROR:
    echo "Failed to open wave output"
    return

  var callbacks = newSeq[AudioCallbackData]()
  var sample = 0
  proc generateSamples(buffer: var openArray[int16], sample: var int, callbacks: var seq[AudioCallbackData]) {.gcsafe.} =
    let sample = nextAudioSample.load()
    nextAudioSample.store(sample + chunkSamples)

    zeroMem(buffer[0].addr, buffer.len * sizeof(int16))

    var i = 0
    while i < callbacks.len:
      if callbacks[i].cb(callbacks[i].data, buffer, sample, ChannelInfo(sampleRate: sampleRate)):
        inc i
      else:
        callbacks.removeShift(i)

    currentAudioSample.store(sample)
    currentAudioTime.store(audioTimer.elapsed.float)

  audioTimer = startTimer()
  currentSampleRate.store(sampleRate)
  currentAudioSample.store(-chunkSamples)
  nextAudioSample.store(0)
  currentAudioTime.store(audioTimer.elapsed.float)

  generateSamples(buffer1, sample, callbacks)
  generateSamples(buffer2, sample, callbacks)
  # generateSamples(buffer3, sample, callbacks)

  var header1 = WAVEHDR(
    lpData: cast[LPSTR](buffer1[0].addr),
    dwBufferLength: DWORD(buffer1.len * bitsPerSample / 8),
  )

  var header2 = WAVEHDR(
    lpData: cast[LPSTR](buffer2[0].addr),
    dwBufferLength: DWORD(buffer2.len * bitsPerSample / 8),
  )

  var header3 = WAVEHDR(
    lpData: cast[LPSTR](buffer3[0].addr),
    dwBufferLength: DWORD(buffer3.len * bitsPerSample / 8),
  )

  waveOutPrepareHeader(waveOutHandle, header1.addr, sizeof(header1).UINT)
  waveOutPrepareHeader(waveOutHandle, header2.addr, sizeof(header2).UINT)
  waveOutPrepareHeader(waveOutHandle, header3.addr, sizeof(header3).UINT)

  waveOutWrite(waveOutHandle, header1.addr, sizeof(header1).UINT)
  waveOutWrite(waveOutHandle, header2.addr, sizeof(header2).UINT)
  # waveOutWrite(waveOutHandle, header3.addr, sizeof(header3).UINT)

  while true:
    let (ok, cb) = audioCallbackChannel.tryRecv()
    if ok:
      callbacks.add cb

    if (header1.dwFlags and WHDR_DONE) != 0:
      generateSamples(buffer1, sample, callbacks)
      waveOutWrite(waveOutHandle, header1.addr, sizeof(header1).UINT)
      header1.dwFlags = header1.dwFlags and (not WHDR_DONE)

    if (header2.dwFlags and WHDR_DONE) != 0:
      generateSamples(buffer2, sample, callbacks)
      waveOutWrite(waveOutHandle, header2.addr, sizeof(header2).UINT)
      header2.dwFlags = header2.dwFlags and (not WHDR_DONE)
      continue

    # if (header3.dwFlags and WHDR_DONE) != 0:
    #   generateSamples(buffer3, sample, callbacks)
    #   waveOutWrite(waveOutHandle, header3.addr, sizeof(header3).UINT)
    #   header3.dwFlags = header3.dwFlags and (not WHDR_DONE)

    Sleep(1)

  waveOutUnprepareHeader(waveOutHandle, header1.addr, sizeof(header1).UINT)
  waveOutUnprepareHeader(waveOutHandle, header2.addr, sizeof(header2).UINT)
  waveOutUnprepareHeader(waveOutHandle, header3.addr, sizeof(header3).UINT)

  discard waveOutClose(waveOutHandle)

var thread: Thread[int]
thread.createThread(audioThread, 0)
