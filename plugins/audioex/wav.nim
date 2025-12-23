import std/math

type
  WavInfo* = object
    sampleRate*: int
    samples*: seq[seq[float32]]

# ---------------------------
# Byte reader utilities
# ---------------------------

type
  Reader = object
    data: ptr UncheckedArray[uint8]
    len: int
    pos: int

proc readU8(r: var Reader): uint8 =
  let v = r.data[r.pos]
  r.pos.inc
  v

proc readLE16(r: var Reader): int =
  let b0 = int(r.readU8())
  let b1 = int(r.readU8())
  b0 or (b1 shl 8)

proc readLE24(r: var Reader): int =
  let b0 = int(r.readU8())
  let b1 = int(r.readU8())
  let b2 = int(r.readU8())
  var v = b0 or (b1 shl 8) or (b2 shl 16)
  # sign-extend 24-bit
  if (v and (1 shl 23)) != 0:
    v = v or not((1 shl 24) - 1)
  v

proc readLE32(r: var Reader): int =
  let b0 = int(r.readU8())
  let b1 = int(r.readU8())
  let b2 = int(r.readU8())
  let b3 = int(r.readU8())
  b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)

proc skip(r: var Reader; n: int) =
  r.pos += n

proc readStr(r: var Reader; n: int): string =
  result = newString(n)
  for i in 0..<n:
    result[i] = char(r.readU8())

# ---------------------------
# PCM conversion
# ---------------------------

proc pcmToFloat(val: int; bits: int; isFloat: bool): float32 =
  if isFloat:
    # reinterpret IEEE float32 bits
    return cast[float32](val)

  case bits:
  of 8:   result = float32(val.float / 127.0)
  of 16:  result = float32(val.float / 32767.0)
  of 24:  result = float32(val.float / 8388607.0)
  of 32:  result = float32(val.float / 2147483647.0)
  else:
    raise newException(IOError, "Unsupported PCM bit depth")

# ---------------------------
# WAV parser
# ---------------------------

proc parseWavFromMemory*(buf: openArray[uint8]): WavInfo =
  var r = Reader(data: cast[ptr UncheckedArray[uint8]](buf), pos: 0, len: buf.len)

  # --- RIFF/WAVE headers ---
  if r.readStr(4) != "RIFF": raise newException(IOError, "Not RIFF")
  discard r.readLE32() # file size
  if r.readStr(4) != "WAVE": raise newException(IOError, "Not WAVE")

  var fmtFound = false
  var dataFound = false

  var audioFormat, channels, sampleRate, bitsPerSample: int
  var dataOffset = 0
  var dataSize = 0

  # Parse chunks
  while r.pos < buf.len:
    let chunkId = r.readStr(4)
    let chunkSize = r.readLE32()

    case chunkId
    of "fmt ":
      audioFormat = r.readLE16()
      channels = r.readLE16()
      sampleRate = r.readLE32()
      discard r.readLE32()
      discard r.readLE16()
      bitsPerSample = r.readLE16()
      fmtFound = true

      # skip extra format bytes
      if chunkSize > 16:
        r.skip(chunkSize - 16)

    of "data":
      dataOffset = r.pos
      dataSize = chunkSize
      dataFound = true
      break

    else:
      r.skip(chunkSize)

  if not fmtFound or not dataFound:
    raise newException(IOError, "Missing fmt or data chunk")

  # --- Decode sample data ---
  let bytesPerSample = bitsPerSample div 8
  let totalFrames = dataSize div (bytesPerSample * channels)

  # prepare output buffers
  var samples: seq[seq[float32]]
  samples.setLen(channels)
  for c in 0..<channels:
    samples[c] = newSeq[float32](totalFrames)

  # move reader to start of data
  r.pos = dataOffset

  let isFloat = (audioFormat == 3)  # 3 = IEEE float

  for i in 0..<totalFrames:
    for ch in 0..<channels:
      var raw: int
      case bytesPerSample:
      of 1: raw = int(r.readU8()) - 128
      of 2: raw = r.readLE16()
      of 3: raw = r.readLE24()
      of 4:
        raw = r.readLE32()
      else:
        raise newException(IOError, "Unsupported sample size")

      samples[ch][i] = pcmToFloat(raw, bitsPerSample, isFloat)

  result = WavInfo(
    sampleRate: sampleRate,
    samples: samples,
  )

proc resampleLinear*(input: openArray[float32],
                     srcRate, dstRate: int): seq[float32] =
  ## Resample 1-channel PCM float data using linear interpolation.
  ## Input/Output samples are normalized float32 [-1, +1].

  if input.len == 0 or srcRate <= 0 or dstRate <= 0:
    return @[]

  if srcRate == dstRate:
    return @input

  let ratio = float(dstRate) / float(srcRate)
  let outLen = int(floor(float(input.len) * ratio))
  result = newSeq[float32](outLen)

  for i in 0..<outLen:
    # position in source
    let pos = float(i) / ratio
    let idx = int(pos)
    let frac = pos - float(idx)

    if idx >= input.len - 1:
      result[i] = input[^1]    # clamp at end
    else:
      let a = input[idx]
      let b = input[idx + 1]
      result[i] = float32(a + (b - a) * frac)

when isMainModule:
  let data = readFile("D:/Music/SamplePacks/Drums/Kick/Analogue - Fat 01 Kick.wav")
  let wav = parseWavFromMemory(data.toOpenArrayByte(0, data.high))
  echo wav.sampleRate
  echo wav.samples.len        # number of channels
  echo wav.samples[0].len     # samples in channel 0
  let resampled = resampleLinear(wav.samples[0], wav.sampleRate, 48_000)
  echo resampled.len
