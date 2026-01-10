import chroma, flatty/binny, pixie/common, pixie/images, std/math, std/strutils, std/strformat,
    vmath, zippy/bitstreams

# See: https://www.w3.org/Graphics/GIF/spec-gif89a.txt

let gifSignatures* = @["GIF87a", "GIF89a"]

type
  Gif* = ref object
    frames*: seq[Image]
    intervals*: seq[float32] # Floating point seconds
    duration*: float32

  ControlExtension = object
    fields: uint8
    delayTime: uint16
    transparentColorIndex: uint8

template failInvalid() =
  raise newException(PixieError, "Invalid GIF buffer, unable to load")

when defined(release):
  {.push checks: off.}


func readUint8*(s: openArray[char], i: int): uint8 {.inline.} =
  cast[uint8](s[i])

func readUint16*(s: openArray[char], i: int): uint16 {.inline.} =
  copyMem(result.addr, s[i].unsafeAddr, 2)

func readUint32*(s: openArray[char], i: int): uint32 {.inline.} =
  copyMem(result.addr, s[i].unsafeAddr, 4)

func readUint64*(s: openArray[char], i: int): uint64 {.inline.} =
  copyMem(result.addr, s[i].unsafeAddr, 8)

func readInt8*(s: openArray[char], i: int): int8 {.inline.} =
  cast[int8](s.readUint8(i))

func readInt16*(s: openArray[char], i: int): int16 {.inline.} =
  cast[int16](s.readUint16(i))

func readInt32*(s: openArray[char], i: int): int32 {.inline.} =
  cast[int32](s.readUint32(i))

func readInt64*(s: openArray[char], i: int): int64 {.inline.} =
  cast[int64](s.readUint64(i))

func readFloat32*(s: openArray[char], i: int): float32 {.inline.} =
  cast[float32](s.readUint32(i))

func readFloat64*(s: openArray[char], i: int): float64 {.inline.} =
  cast[float64](s.readUint64(i))

iterator decodeGif*(data: openArray[char], loop: bool = false): tuple[image: Image, timestamp: float] {.raises: [PixieError].} =
  ## Decodes GIF data.
  if data.len < 13:
    failInvalid()

  if not equalMem(gifSignatures[0][0].addr, data[0].addr, 5) and not equalMem(gifSignatures[1][0].addr, data[0].addr, 5):
    raise newException(PixieError, "Invalid GIF file signature")

  let
    screenWidth = data.readInt16(6).int
    screenHeight = data.readInt16(8).int
    globalFlags = data.readUint8(10).int
    hasGlobalColorTable = (globalFlags and 0b10000000) != 0
    globalColorTableSize = 2 ^ ((globalFlags and 0b00000111) + 1)
    bgColorIndex = data.readUint8(11).int
    pixelAspectRatio = data.readUint8(12)

  var colorIndexes: seq[int]
  var table: seq[(int, int)]
  var lzwDataBlocks: seq[(int, int)] # (offset, len)

  if bgColorIndex > globalColorTableSize:
    failInvalid()

  if pixelAspectRatio != 0:
    raise newException(PixieError, "Unsupported GIF, pixel aspect ratio")

  var pos = 13

  if pos + globalColorTableSize * 3 > data.len:
    failInvalid()

  var
    globalColorTable: seq[ColorRGBX]
    bgColor: ColorRGBX
  if hasGlobalColorTable:
    globalColorTable.setLen(globalColorTableSize)
    for i in 0 ..< globalColorTable.len:
      globalColorTable[i] = rgbx(
        data.readUint8(pos + 0),
        data.readUint8(pos + 1),
        data.readUint8(pos + 2),
        255
      )
      pos += 3
    bgColor = globalColorTable[bgColorIndex]

  proc skipSubBlocks(data: openArray[char], pos: var int) =
    while true: # Skip data sub-blocks
      if pos + 1 > data.len:
        failInvalid()

      let subBlockSize = data.readUint8(pos).int
      inc pos

      if subBlockSize == 0:
        break

      pos += subBlockSize

  var finalImage = newImage(screenWidth, screenHeight)

  var lzwData = ""
  var localColorTable: seq[ColorRGBX]
  var controlExtension: ControlExtension
  let streamStartPos = pos
  while true:
    if pos + 1 > data.len:
      failInvalid()

    let blockType = data.readUint8(pos)
    inc pos

    case blockType:
    of 0x2c: # Image
      if pos + 9 > data.len:
        failInvalid()

      let
        imageLeftPos = data.readUint16(pos + 0).int
        imageTopPos = data.readUint16(pos + 2).int
        imageWidth = data.readUint16(pos + 4).int
        imageHeight = data.readUint16(pos + 6).int
        imageFlags = data.readUint16(pos + 8)
        hasLocalColorTable = (imageFlags and 0b10000000) != 0
        interlaced = (imageFlags and 0b01000000) != 0
        localColorTableSize = 2 ^ ((imageFlags and 0b00000111) + 1)

      pos += 9

      if imageWidth > screenWidth or imageHeight > screenHeight:
        raise newException(PixieError, "Invalid GIF frame dimensions")

      if pos + localColorTableSize * 3 > data.len:
        failInvalid()

      if hasLocalColorTable:
        localColorTable.setLen(localColorTableSize)
        for i in 0 ..< localColorTable.len:
          localColorTable[i] = rgbx(
            data.readUint8(pos + 0),
            data.readUint8(pos + 1),
            data.readUint8(pos + 2),
            255
          )
          pos += 3
      else:
        localColorTable.setLen(0)

      if pos + 1 > data.len:
        failInvalid()

      let minCodeSize = data.readUint8(pos).int
      inc pos

      if minCodeSize > 11:
        failInvalid()

      # The image data is contained in a sequence of sub-blocks
      lzwDataBlocks.setLen(0)
      while true:
        if pos + 1 > data.len:
          failInvalid()

        let subBlockSize = data.readUint8(pos).int
        inc pos

        if subBlockSize == 0:
          break

        if pos + subBlockSize > data.len:
          failInvalid()

        lzwDataBlocks.add((pos, subBlockSize))

        pos += subBlockSize

      var lzwDataLen: int
      for (_, len) in lzwDataBlocks:
        lzwDataLen += len

      var
        i: int
      lzwData.setLen(lzwDataLen)
      for (offset, len) in lzwDataBlocks:
        copyMem(lzwData[i].addr, data[offset].unsafeAddr, len)
        i += len

      let
        clearCode = 1 shl minCodeSize
        endCode = clearCode + 1

      var
        b = BitStreamReader(
          src: cast[ptr UncheckedArray[uint8]](lzwData[0].addr),
          len: lzwData.len
        )
        codeSize = minCodeSize + 1
        prev: tuple[offset, len: int]

      colorIndexes.setLen(0)
      table.setLen(endCode + 1)

      while true:
        let code = b.readBits(codeSize).int
        if b.bitsBuffered < 0:
          failInvalid()
        if code == endCode:
          break

        if code == clearCode:
          codeSize = minCodeSize + 1
          table.setLen(endCode + 1)
          prev = (0, 0)
          continue

        # Increase the code size if needed
        if table.len == (1 shl codeSize) - 1 and codeSize < 12:
          inc codeSize

        let start = colorIndexes.len
        if code < table.len: # If we have seen the code before
          if code < clearCode:
            colorIndexes.add(code)
            if prev.len > 0:
              table.add((prev.offset, prev.len + 1))
            prev = (start, 1)
          else:
            let (offset, len) = table[code]
            for i in 0 ..< len:
              colorIndexes.add(colorIndexes[offset + i])
            table.add((prev.offset, prev.len + 1))
            prev = (start, len)
        else:
          if prev[1] == 0:
            failInvalid()
          for i in 0 ..< prev[1]:
            colorIndexes.add(colorIndexes[prev[0] + i])
          colorIndexes.add(colorIndexes[prev[0]])
          table.add((start, prev.len + 1))
          prev = (start, prev.len + 1)

      if colorIndexes.len != imageWidth * imageHeight:
        failInvalid()

      let image = newImage(imageWidth, imageHeight)

      var transparentColorIndex = -1
      if (controlExtension.fields and 1) != 0: # Transparent index flag
        transparentColorIndex = controlExtension.transparentColorIndex.int

      let timestamp = controlExtension.delayTime.float32 / 100
      let disposalMethod = (controlExtension.fields and 0b00011100) shr 2
      if disposalMethod == 2:
        let frame = newImage(screenWidth, screenHeight)
        frame.fill(bgColor)
        yield (frame, timestamp)
      else:
        if hasLocalColorTable:
          for i, colorIndex in colorIndexes:
            if colorIndex >= localColorTable.len:
              # failInvalid()
              continue
            if colorIndex != transparentColorIndex:
              image.data[i] = localColorTable[colorIndex]
        else:
          for i, colorIndex in colorIndexes:
            if colorIndex >= globalColorTable.len:
              # failInvalid()
              continue
            if colorIndex != transparentColorIndex:
              image.data[i] = globalColorTable[colorIndex]

        if interlaced:
          # Just copyMem the rows into the right place. I've only ever seen
          # interlaced for the first frame so this is unlikely to be a hot path.
          let deinterlaced = newImage(image.width, image.height)
          var
            y: int
            i: int
          while i < image.height:
            copyMem(
              deinterlaced.data[deinterlaced.dataIndex(0, i)].addr,
              image.data[image.dataIndex(0, y)].addr,
              image.width * 4
            )
            i += 8
            inc y
          i = 4
          while i < image.height:
            copyMem(
              deinterlaced.data[deinterlaced.dataIndex(0, i)].addr,
              image.data[image.dataIndex(0, y)].addr,
              image.width * 4
            )
            i += 8
            inc y
          i = 2
          while i < image.height:
            copyMem(
              deinterlaced.data[deinterlaced.dataIndex(0, i)].addr,
              image.data[image.dataIndex(0, y)].addr,
              image.width * 4
            )
            i += 4
            inc y
          i = 1
          while i < image.height:
            copyMem(
              deinterlaced.data[deinterlaced.dataIndex(0, i)].addr,
              image.data[image.dataIndex(0, y)].addr,
              image.width * 4
            )
            i += 2
            inc y

          image.data = move deinterlaced.data

        if imageWidth != screenWidth or imageHeight != screenHeight or
          imageTopPos != 0 or imageLeftPos != 0:
          let frame = newImage(screenWidth, screenHeight)
          frame.draw(
            image,
            translate(vec2(imageLeftPos.float32, imageTopPos.float32))
          )
          finalImage.draw(
            frame,
            translate(vec2(0, 0))
          )
          yield (finalImage, timestamp)
        else:
          finalImage.draw(
            image,
            translate(vec2(0, 0)),
            OverwriteBlend,
          )
          yield (finalImage, timestamp)

      # result.intervals.add(controlExtension.delayTime.float32 / 100)

      # Reset the control extension since it only applies to one image
      controlExtension = ControlExtension()

    of 0x21: # Extension
      if pos + 1 > data.len:
        failInvalid()

      let extensionType = data.readUint8(pos + 0)
      inc pos

      case extensionType:
      of 0xf9:
        # Graphic Control Extension
        if pos + 1 > data.len:
          failInvalid()

        let blockSize = data.readUint8(pos).int
        inc pos

        if blockSize != 4:
          failInvalid()

        if pos + blockSize > data.len:
          failInvalid()

        controlExtension.fields = data.readUint8(pos + 0)
        controlExtension.delayTime = data.readUint16(pos + 1)
        controlExtension.transparentColorIndex = data.readUint8(pos + 3)

        pos += blockSize
        inc pos # Block terminator

      of 0xfe:
        # Comment
        skipSubBlocks(data, pos)

      # of 0x01:
      #   # Plain Text

      of 0xff:
        # Application Specific
        if pos + 1 > data.len:
          failInvalid()

        let blockSize = data.readUint8(pos).int
        inc pos

        if blockSize != 11:
          failInvalid()

        if pos + blockSize > data.len:
          failInvalid()

        pos += blockSize

        skipSubBlocks(data, pos)

      else:
        raise newException(
          PixieError,
          "Unexpected GIF extension type " & toHex(extensionType)
        )

    of 0x3b: # Trailer
      if loop:
        pos = streamStartPos
        continue
      break

    else:
      raise newException(
        PixieError,
        "Unexpected GIF block type " & toHex(blockType)
      )

proc decodeGifDimensions*(
  data: pointer, len: int
): ImageDimensions {.raises: [PixieError].} =
  ## Decodes the GIF dimensions.
  if len < 10:
    failInvalid()

  let data = cast[ptr UncheckedArray[uint8]](data)

  let startsWithSignature =
    equalMem(data, gifSignatures[0].cstring, 6) or
    equalMem(data, gifSignatures[1].cstring, 6)

  if not startsWithSignature:
    raise newException(PixieError, "Invalid GIF file signature")

  result.width = data.readInt16(6).int
  result.height = data.readInt16(8).int

proc decodeGifDimensions*(
  data: string
): ImageDimensions {.raises: [PixieError].} =
  decodeGifDimensions(data.cstring, data.len)

proc newImage*(gif: Gif): Image {.raises: [].} =
  gif.frames[0].copy()

when defined(release):
  {.pop.}
