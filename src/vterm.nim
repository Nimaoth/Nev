import std/[os, streams, strutils, sequtils, strformat, typedthreads, tables, json, colors]
# import std/winlean
import winim/lean
import nimsumtree/arc
import misc/[async_process, custom_logger, util, custom_unicode, custom_async, event]
import dispatch_tables, config_provider, events, view, layout, service, platform_service
import scripting/expose
import platform/[tui, platform]

logCategory "vterm"

const WIDTH = 110
const HEIGHT = 50

type HPCON* = HANDLE

{.compile: "./libvterm/src/encoding.c".}
{.compile: "./libvterm/src/keyboard.c".}
{.compile: "./libvterm/src/mouse.c".}
{.compile: "./libvterm/src/parser.c".}
{.compile: "./libvterm/src/pen.c".}
{.compile: "./libvterm/src/screen.c".}
{.compile: "./libvterm/src/state.c".}
{.compile: "./libvterm/src/unicode.c".}
{.compile: "./libvterm/src/vterm.c".}

{.passC: "-Ilibvterm/include".}
{.push header: "./libvterm/include/vterm.h".}

const VTERM_MAX_CHARS_PER_CELL = 6
type
  VTerm {.importc.} = object
  VTermState {.importc.} = object
  VTermScreen {.importc.} = object

  VTermDamageSize* {.importc.} = enum
    VTERM_DAMAGE_CELL,        ##  every cell
    VTERM_DAMAGE_ROW,         ##  entire rows
    VTERM_DAMAGE_SCREEN,      ##  entire screen
    VTERM_DAMAGE_SCROLL,      ##  entire screen + scrollrect
    VTERM_N_DAMAGES

  VTermColorType* {.importc.} = enum
    VTERM_COLOR_RGB = 0x00,
    VTERM_COLOR_INDEXED = 0x01,
    VTERM_COLOR_DEFAULT_FG = 0x02,
    VTERM_COLOR_DEFAULT_BG = 0x04,
    VTERM_COLOR_DEFAULT_MASK = 0x06

  VTermColorTypeRgb* {.bycopy.} = object
    `type`*: uint8
    red*: uint8
    green*: uint8
    blue*: uint8

  VTermColorTypeIndexed* {.bycopy.} = object
    `type`*: uint8
    idx*: uint8

  VTermColor* {.bycopy, union, importc.} = object
    `type`*: uint8
    rgb*: VTermColorTypeRgb
    indexed*: VTermColorTypeIndexed

  VTermScreenCellAttrs* {.bycopy, importc.} = object
    bold* {.bitsize: 1.}: cuint
    underline* {.bitsize: 2.}: cuint
    italic* {.bitsize: 1.}: cuint
    blink* {.bitsize: 1.}: cuint
    reverse* {.bitsize: 1.}: cuint
    conceal* {.bitsize: 1.}: cuint
    strike* {.bitsize: 1.}: cuint
    font* {.bitsize: 4.}: cuint
    ##  0 to 9
    dwl* {.bitsize: 1.}: cuint
    ##  On a DECDWL or DECDHL line
    dhl* {.bitsize: 2.}: cuint
    ##  On a DECDHL line (1=top 2=bottom)
    small* {.bitsize: 1.}: cuint
    baseline* {.bitsize: 2.}: cuint

  VTermScreenCell* {.bycopy, importc.} = object
    chars*: array[VTERM_MAX_CHARS_PER_CELL, uint32]
    width*: char
    attrs*: VTermScreenCellAttrs
    fg*: VTermColor
    bg*: VTermColor

  VTermPos* {.bycopy, importc.} = object
    row*: cint
    col*: cint

  VTermRect* {.bycopy, importc.} = object
    start_row*: cint
    end_row*: cint
    start_col*: cint
    end_col*: cint

  VTermAttr* {.importc.} = enum
    VTERM_ATTR_BOLD = 1,        ##  bool:   1, 22
    VTERM_ATTR_UNDERLINE,     ##  number: 4, 21, 24
    VTERM_ATTR_ITALIC,        ##  bool:   3, 23
    VTERM_ATTR_BLINK,         ##  bool:   5, 25
    VTERM_ATTR_REVERSE,       ##  bool:   7, 27
    VTERM_ATTR_CONCEAL,       ##  bool:   8, 28
    VTERM_ATTR_STRIKE,        ##  bool:   9, 29
    VTERM_ATTR_FONT,          ##  number: 10-19
    VTERM_ATTR_FOREGROUND,    ##  color:  30-39 90-97
    VTERM_ATTR_BACKGROUND,    ##  color:  40-49 100-107
    VTERM_ATTR_SMALL,         ##  bool:   73, 74, 75
    VTERM_ATTR_BASELINE,      ##  number: 73, 74, 75

  VTermProp* {.importc.} = enum
    VTERM_PROP_CURSORVISIBLE = 1, ##  bool
    VTERM_PROP_CURSORBLINK,   ##  bool
    VTERM_PROP_ALTSCREEN,     ##  bool
    VTERM_PROP_TITLE,         ##  string
    VTERM_PROP_ICONNAME,      ##  string
    VTERM_PROP_REVERSE,       ##  bool
    VTERM_PROP_CURSORSHAPE,   ##  number
    VTERM_PROP_MOUSE,         ##  number
    VTERM_PROP_FOCUSREPORT,   ##  bool

  VTermValueType* {.importc.} = enum
    VTERM_VALUETYPE_BOOL = 1,
    VTERM_VALUETYPE_INT,
    VTERM_VALUETYPE_STRING,
    VTERM_VALUETYPE_COLOR,
    VTERM_N_VALUETYPES

  VTermStringFragment* {.bycopy, importc.} = object
    str*: cstring
    len* {.bitsize: 30.}: csize_t
    initial* {.bitsize: 1.}: bool
    final* {.bitsize: 1.}: bool

  VTermValue* {.bycopy, union, importc.} = object
    boolean*: cint
    number*: cint
    string*: VTermStringFragment
    color*: VTermColor

  VTermGlyphInfo* {.bycopy, importc.} = object
    chars*: ptr uint32
    width*: cint
    protected_cell* {.bitsize: 1.}: cuint ##  DECSCA-protected against DECSEL/DECSED
    dwl* {.bitsize: 1.}: cuint ##  DECDWL or DECDHL double-width line
    dhl* {.bitsize: 2.}: cuint ##  DECDHL double-height line (1=top 2=bottom)

  VTermLineInfo* {.bycopy, importc.} = object
    doublewidth* {.bitsize: 1.}: cuint ##  DECDWL or DECDHL line
    doubleheight* {.bitsize: 2.}: cuint ##  DECDHL line (1=top 2=bottom)
    continuation* {.bitsize: 1.}: cuint ##  Line is a flow continuation of the previous

  VTermStateFields* {.bycopy, importc.} = object
    pos*: VTermPos ##  current cursor position
    lineinfos*: array[2, ptr VTermLineInfo] ##  [1] may be NULL

  VTermOutputCallback* {.importc.} = proc (s: cstring; len: csize_t; user: pointer): void {.cdecl.}

  VTermParserCallbacks* {.bycopy, importc.} = object
    text*: proc (bytes: cstring; len: csize_t; user: pointer): cint {.cdecl.}
    control*: proc (control: cuchar; user: pointer): cint {.cdecl.}
    escape*: proc (bytes: cstring; len: csize_t; user: pointer): cint {.cdecl.}
    csi*: proc (leader: cstring; args: ptr clong; argcount: cint; intermed: cstring; command: char; user: pointer): cint {.cdecl.}
    osc*: proc (command: cint; frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    dcs*: proc (command: cstring; commandlen: csize_t; frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    apc*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    pm*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    sos*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    resize*: proc (rows: cint; cols: cint; user: pointer): cint {.cdecl.}

  VTermStateCallbacks* {.bycopy, importc.} = object
    putglyph*: proc (info: ptr VTermGlyphInfo; pos: VTermPos; user: pointer): cint {.cdecl.}
    movecursor*: proc (pos: VTermPos; oldpos: VTermPos; visible: cint; user: pointer): cint {.cdecl.}
    scrollrect*: proc (rect: VTermRect; downward: cint; rightward: cint; user: pointer): cint {.cdecl.}
    moverect*: proc (dest: VTermRect; src: VTermRect; user: pointer): cint {.cdecl.}
    erase*: proc (rect: VTermRect; selective: cint; user: pointer): cint {.cdecl.}
    initpen*: proc (user: pointer): cint {.cdecl.}
    setpenattr*: proc (attr: VTermAttr; val: ptr VTermValue; user: pointer): cint {.cdecl.}
    settermprop*: proc (prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.}
    bell*: proc (user: pointer): cint {.cdecl.}
    resize*: proc (rows: cint; cols: cint; fields: ptr VTermStateFields; user: pointer): cint {.cdecl.}
    setlineinfo*: proc (row: cint; newinfo: ptr VTermLineInfo; oldinfo: ptr VTermLineInfo; user: pointer): cint {.cdecl.}
    sb_clear*: proc (user: pointer): cint {.cdecl.}

  VTermStateFallbacks* {.bycopy, importc.} = object
    control*: proc (control: cuchar; user: pointer): cint {.cdecl.}
    csi*: proc (leader: cstring; args: ptr clong; argcount: cint; intermed: cstring; command: char; user: pointer): cint {.cdecl.}
    osc*: proc (command: cint; frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    dcs*: proc (command: cstring; commandlen: csize_t; frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    apc*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    pm*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    sos*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}

  VTermScreenCallbacks* {.bycopy, importc.} = object
    damage*: proc (rect: VTermRect; user: pointer): cint {.cdecl.}
    moverect*: proc (dest: VTermRect; src: VTermRect; user: pointer): cint {.cdecl.}
    movecursor*: proc (pos: VTermPos; oldpos: VTermPos; visible: cint; user: pointer): cint {.cdecl.}
    settermprop*: proc (prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.}
    bell*: proc (user: pointer): cint {.cdecl.}
    resize*: proc (rows: cint; cols: cint; user: pointer): cint {.cdecl.}
    sb_pushline*: proc (cols: cint; cells: ptr VTermScreenCell; user: pointer): cint {.cdecl.}
    sb_popline*: proc (cols: cint; cells: ptr VTermScreenCell; user: pointer): cint {.cdecl.}
    sb_clear*: proc (user: pointer): cint {.cdecl.}

  VTermModifier* {.importc.} = enum
    VTERM_MOD_NONE = 0x00,
    VTERM_MOD_SHIFT = 0x01,
    VTERM_MOD_ALT = 0x02,
    VTERM_MOD_CTRL = 0x04,
    VTERM_ALL_MODS_MASK = 0x07

  VTermKey* {.importc.} = enum
    VTERM_KEY_NONE,
    VTERM_KEY_ENTER,
    VTERM_KEY_TAB,
    VTERM_KEY_BACKSPACE,
    VTERM_KEY_ESCAPE,
    VTERM_KEY_UP,
    VTERM_KEY_DOWN,
    VTERM_KEY_LEFT,
    VTERM_KEY_RIGHT,
    VTERM_KEY_INS,
    VTERM_KEY_DEL,
    VTERM_KEY_HOME,
    VTERM_KEY_END,
    VTERM_KEY_PAGEUP,
    VTERM_KEY_PAGEDOWN,
    VTERM_KEY_FUNCTION_0 = 256,
    VTERM_KEY_FUNCTION_1 = 257,
    VTERM_KEY_FUNCTION_2 = 258,
    VTERM_KEY_FUNCTION_3 = 259,
    VTERM_KEY_FUNCTION_4 = 260,
    VTERM_KEY_FUNCTION_5 = 261,
    VTERM_KEY_FUNCTION_6 = 262,
    VTERM_KEY_FUNCTION_7 = 263,
    VTERM_KEY_FUNCTION_8 = 264,
    VTERM_KEY_FUNCTION_9 = 265,
    VTERM_KEY_FUNCTION_10 = 266,
    VTERM_KEY_FUNCTION_11 = 267,
    VTERM_KEY_FUNCTION_12 = 268,
    VTERM_KEY_FUNCTION_MAX = 256 + 255,
    VTERM_KEY_KP_0,
    VTERM_KEY_KP_1,
    VTERM_KEY_KP_2,
    VTERM_KEY_KP_3,
    VTERM_KEY_KP_4,
    VTERM_KEY_KP_5,
    VTERM_KEY_KP_6,
    VTERM_KEY_KP_7,
    VTERM_KEY_KP_8,
    VTERM_KEY_KP_9,
    VTERM_KEY_KP_MULT,
    VTERM_KEY_KP_PLUS,
    VTERM_KEY_KP_COMMA,
    VTERM_KEY_KP_MINUS,
    VTERM_KEY_KP_PERIOD,
    VTERM_KEY_KP_DIVIDE,
    VTERM_KEY_KP_ENTER,
    VTERM_KEY_KP_EQUAL,
    VTERM_KEY_MAX

  VTermAttrMask* = enum
    VTERM_ATTR_BOLD_MASK = 1 shl 0, VTERM_ATTR_UNDERLINE_MASK = 1 shl 1,
    VTERM_ATTR_ITALIC_MASK = 1 shl 2, VTERM_ATTR_BLINK_MASK = 1 shl 3,
    VTERM_ATTR_REVERSE_MASK = 1 shl 4, VTERM_ATTR_STRIKE_MASK = 1 shl 5,
    VTERM_ATTR_FONT_MASK = 1 shl 6, VTERM_ATTR_FOREGROUND_MASK = 1 shl 7,
    VTERM_ATTR_BACKGROUND_MASK = 1 shl 8, VTERM_ATTR_CONCEAL_MASK = 1 shl 9,
    VTERM_ATTR_SMALL_MASK = 1 shl 10, VTERM_ATTR_BASELINE_MASK = 1 shl 11,
    VTERM_ALL_ATTRS_MASK = (1 shl 12) - 1

########## VTerm ###########
proc new*(_: typedesc[VTerm], rows, cols: c_int): ptr VTerm {.importc: "vterm_new".}
proc writeInput*(vt: ptr VTerm; bytes: cstring; len: csize_t): csize_t {.importc: "vterm_input_write".}
proc key*(vt: ptr VTerm; key: VTermKey; modifiers: uint32) {.importc: "vterm_keyboard_key".}
proc uniChar*(vt: ptr VTerm; c: uint32; modifiers: uint32) {.importc: "vterm_keyboard_unichar".}
proc setOutputCallback*(vt: ptr VTerm; f: VTermOutputCallback; user: pointer) {.importc: "vterm_output_set_callback".}
proc setParserCallbacks*(vt: ptr VTerm; callbacks: ptr VTermParserCallbacks; user: pointer) {.importc: "vterm_parser_set_callbacks".}

proc free*(vt: ptr VTerm) {.importc: "vterm_free".}
proc getSize*(vt: ptr VTerm; rowsp: ptr cint; colsp: ptr cint) {.importc: "vterm_get_size".}
proc setSize*(vt: ptr VTerm; rows: cint; cols: cint) {.importc: "vterm_set_size".}
proc getUtf8*(vt: ptr VTerm): cint {.importc: "vterm_get_utf8".}
proc setUtf8*(vt: ptr VTerm; is_utf8: cint) {.importc: "vterm_set_utf8".}

########## VTermScreen ###########
proc screen*(vt: ptr VTerm): ptr VTermScreen {.importc: "vterm_obtain_screen".}
proc setCallbacks*(screen: ptr VTermScreen; callbacks: ptr VTermScreenCallbacks; user: pointer) {.importc: "vterm_screen_set_callbacks".}
proc getCbdata*(screen: ptr VTermScreen): pointer {.importc: "vterm_screen_get_cbdata".}
proc setUnrecognisedFallbacks*(screen: ptr VTermScreen; fallbacks: ptr VTermStateFallbacks; user: pointer) {.importc: "vterm_screen_set_unrecognised_fallbacks".}
proc getUnrecognisedFbdata*(screen: ptr VTermScreen): pointer {.importc: "vterm_screen_get_unrecognised_fbdata".}
proc enableReflow*(screen: ptr VTermScreen; reflow: bool) {.importc: "vterm_screen_enable_reflow".}
proc enableAltscreen*(screen: ptr VTermScreen; altscreen: cint) {.importc: "vterm_screen_enable_altscreen".}
proc flushDamage*(screen: ptr VTermScreen) {.importc: "vterm_screen_flush_damage".}
proc setDamageMerge*(screen: ptr VTermScreen; size: VTermDamageSize) {.importc: "vterm_screen_set_damage_merge".}
proc reset*(screen: ptr VTermScreen; hard: cint) {.importc: "vterm_screen_reset".}
proc getChars*(screen: ptr VTermScreen; chars: ptr uint32; len: csize_t; rect: VTermRect): csize_t {.importc: "vterm_screen_get_chars".}
proc getText*(screen: ptr VTermScreen; str: cstring; len: csize_t; rect: VTermRect): csize_t {.importc: "vterm_screen_get_text".}
proc getAttrsExtent*(screen: ptr VTermScreen; extent: ptr VTermRect; pos: VTermPos; attrs: VTermAttrMask): cint {.importc: "vterm_screen_get_attrs_extent".}
proc getCell*(screen: ptr VTermScreen; pos: VTermPos; cell: ptr VTermScreenCell): cint {.importc: "vterm_screen_get_cell".}
proc isEol*(screen: ptr VTermScreen; pos: VTermPos): cint {.importc: "vterm_screen_is_eol".}
proc convertColorToRgb*(screen: ptr VTermScreen; col: ptr VTermColor) {.importc: "vterm_screen_convert_color_to_rgb".}
proc setDefaultColors*(screen: ptr VTermScreen; default_fg: ptr VTermColor; default_bg: ptr VTermColor) {.importc: "vterm_screen_set_default_colors".}

########## VTermState ###########
proc state*(vt: ptr VTerm): ptr VTermState {.importc: "vterm_obtain_state".}
proc setCallbacks*(state: ptr VTermState; callbacks: ptr VTermStateCallbacks; user: pointer) {.importc: "vterm_state_set_callbacks".}
proc getCbdata*(state: ptr VTermState): pointer {.importc: "vterm_state_get_cbdata".}
proc setUnrecognisedFallbacks*(state: ptr VTermState; fallbacks: ptr VTermStateFallbacks; user: pointer) {.importc: ":".}
proc getUnrecognisedFbdata*(state: ptr VTermState): pointer {.importc: "vterm_state_get_unrecognised_fbdata".}
proc reset*(state: ptr VTermState; hard: cint) {.importc: "vterm_state_reset".}
proc getCursorpos*(state: ptr VTermState; cursorpos: ptr VTermPos) {.importc: "vterm_state_get_cursorpos".}
proc getDefaultColors*(state: ptr VTermState; default_fg: ptr VTermColor; default_bg: ptr VTermColor) {.importc: "vterm_state_get_default_colors".}
proc getPaletteColor*(state: ptr VTermState; index: cint; col: ptr VTermColor) {.importc: "vterm_state_get_palette_color".}
proc setDefaultColors*(state: ptr VTermState; default_fg: ptr VTermColor; default_bg: ptr VTermColor) {.importc: "vterm_state_set_default_colors".}
proc setPaletteColor*(state: ptr VTermState; index: cint; col: ptr VTermColor) {.importc: "vterm_state_set_palette_color".}
proc setBoldHighbright*(state: ptr VTermState; bold_is_highbright: cint) {.importc: "vterm_state_set_bold_highbright".}
proc getPenattr*(state: ptr VTermState; attr: VTermAttr; val: ptr VTermValue): cint {.importc: "vterm_state_get_penattr".}
proc setTermprop*(state: ptr VTermState; prop: VTermProp; val: ptr VTermValue): cint {.importc: "vterm_state_set_termprop".}
proc focusIn*(state: ptr VTermState) {.importc: "vterm_state_focus_in".}
proc focusOut*(state: ptr VTermState) {.importc: "vterm_state_focus_out".}
proc getLineinfo*(state: ptr VTermState; row: cint): ptr VTermLineInfo {.importc: "vterm_state_get_lineinfo".}

{.pop.}

const VTERM_COLOR_TYPE_MASK = 1.uint8

proc isIndexed*(col: VTermColor): bool =
  ((col.`type` and VTERM_COLOR_TYPE_MASK) == ord(VTERM_COLOR_INDEXED).uint8)

proc isRGB*(col: VTermColor): bool =
  ((col.`type` and VTERM_COLOR_TYPE_MASK) == ord(VTERM_COLOR_RGB).uint8)

proc isDefaultFg*(col: VTermColor): bool =
  (col.`type` and ord(VTERM_COLOR_DEFAULT_FG).uint8) != 0

proc isDefaultBg*(col: VTermColor): bool =
  (col.`type` and ord(VTERM_COLOR_DEFAULT_BG).uint8) != 0


############################# end of vterm #############################

proc inputToVtermKey(input: int64): VTermKey =
  return case input
  of INPUT_ENTER: VTERM_KEY_ENTER
  of INPUT_ESCAPE: VTERM_KEY_ESCAPE
  of INPUT_BACKSPACE: VTERM_KEY_BACKSPACE
  of INPUT_DELETE: VTERM_KEY_DEL
  of INPUT_TAB: VTERM_KEY_TAB
  of INPUT_LEFT: VTERM_KEY_LEFT
  of INPUT_RIGHT: VTERM_KEY_RIGHT
  of INPUT_UP: VTERM_KEY_UP
  of INPUT_DOWN: VTERM_KEY_DOWN
  of INPUT_HOME: VTERM_KEY_HOME
  of INPUT_END: VTERM_KEY_END
  of INPUT_PAGE_UP: VTERM_KEY_PAGEUP
  of INPUT_PAGE_DOWN: VTERM_KEY_PAGEDOWN
  of INPUT_F1: VTERM_KEY_FUNCTION_1
  of INPUT_F2: VTERM_KEY_FUNCTION_2
  of INPUT_F3: VTERM_KEY_FUNCTION_3
  of INPUT_F4: VTERM_KEY_FUNCTION_4
  of INPUT_F5: VTERM_KEY_FUNCTION_5
  of INPUT_F6: VTERM_KEY_FUNCTION_6
  of INPUT_F7: VTERM_KEY_FUNCTION_7
  of INPUT_F8: VTERM_KEY_FUNCTION_8
  of INPUT_F9: VTERM_KEY_FUNCTION_9
  of INPUT_F10: VTERM_KEY_FUNCTION_10
  of INPUT_F11: VTERM_KEY_FUNCTION_11
  of INPUT_F12: VTERM_KEY_FUNCTION_12
  else: VTERM_KEY_NONE

proc toVtermModifiers(modifiers: Modifiers): uint32 =
  if Modifier.Shift in modifiers:
    result = result or VTERM_MOD_SHIFT.ord.uint32
  if Modifier.Control in modifiers:
    result = result or VTERM_MOD_CTRL.ord.uint32
  if Modifier.Alt in modifiers:
    result = result or VTERM_MOD_ALT.ord.uint32

const PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE: DWORD = 131094

proc CreatePseudoConsole*(size: wincon.COORD, hInput: HANDLE, hOutput: HANDLE, dwFlags: DWORD, phPC: ptr HPCON): HRESULT {.winapi, stdcall, dynlib: "kernel32", importc.}
proc ClosePseudoConsole*(hPC: HPCON) {.winapi, stdcall, dynlib: "kernel32", importc.}

proc prepareStartupInformation*(hpc: HPCON): STARTUPINFOEX =
  ZeroMemory(addr(result), sizeof((result)))
  result.StartupInfo.cb = sizeof((STARTUPINFOEX)).DWORD

  var bytesRequired: SIZE_T
  InitializeProcThreadAttributeList(nil, 1, 0, addr(bytesRequired))

  result.lpAttributeList = cast[PPROC_THREAD_ATTRIBUTE_LIST](HeapAlloc(GetProcessHeap(), 0, bytesRequired))

  if result.lpAttributeList == nil:
    raiseOSError(14.OSErrorCode)

  if InitializeProcThreadAttributeList(result.lpAttributeList, 1, 0, addr(bytesRequired)) == 0:
    HeapFree(GetProcessHeap(), 0, result.lpAttributeList)
    raiseOSError(osLastError())

  if UpdateProcThreadAttribute(result.lpAttributeList, 0,
                                 PROC_THREAD_ATTRIBUTE_PSEUDOCONSOLE, cast[LPVOID](hpc),
                                 sizeof((hpc)), nil, nil) == 0:
    HeapFree(GetProcessHeap(), 0, result.lpAttributeList)
    raiseOSError(osLastError())

type
  FileHandleStream = ref object of StreamObj
    handle: Handle
    atTheEnd: bool

proc closeHandleCheck(handle: Handle) {.inline.} =
  if handle.CloseHandle() == 0:
    raiseOSError(osLastError())

proc fileClose[T: Handle | FileHandle](h: var T) {.inline.} =
  if h > 4:
    closeHandleCheck(h)
    h = INVALID_HANDLE_VALUE.T

proc hsClose(s: Stream) =
  FileHandleStream(s).handle.fileClose()

proc hsAtEnd(s: Stream): bool = return FileHandleStream(s).atTheEnd

proc hsReadData(s: Stream, buffer: pointer, bufLen: int): int =
  var s = FileHandleStream(s)
  if s.atTheEnd: return 0
  var br: int32
  var a = ReadFile(s.handle, buffer, bufLen.cint, addr br, nil)
  # TRUE and zero bytes returned (EOF).
  # TRUE and n (>0) bytes returned (good data).
  # FALSE and bytes returned undefined (system error).
  if a == 0 and br != 0: raiseOSError(osLastError())
  s.atTheEnd = br == 0 #< bufLen
  result = br

proc hsWriteData(s: Stream, buffer: pointer, bufLen: int) =
  var s = FileHandleStream(s)
  var bytesWritten: int32
  var a = WriteFile(s.handle, buffer, bufLen.cint,
                            addr bytesWritten, nil)
  if a == 0: raiseOSError(osLastError())

proc newFileHandleStream(handle: Handle): owned FileHandleStream =
  result = FileHandleStream(handle: handle, closeImpl: hsClose, atEndImpl: hsAtEnd,
    readDataImpl: hsReadData, writeDataImpl: hsWriteData)

# proc createPipeHandles(rdHandle, wrHandle: var Handle) =
#   var sa: SECURITY_ATTRIBUTES
#   sa.nLength = sizeof(SECURITY_ATTRIBUTES).cint
#   sa.lpSecurityDescriptor = nil
#   sa.bInheritHandle = 1
#   if createPipe(rdHandle, wrHandle, sa, 0) == 0'i32:
#     raiseOSError(osLastError())

proc createTerminalBuffer*(screen: ptr VTermScreen, width: int, height: int): TerminalBuffer =
  result.initTerminalBuffer(width, height)
  var cell: VTermScreenCell
  var pos: VTermPos
  for row in 0..<height:
    var col: cint = 0
    for col in 0..<width:
      pos.row = row.cint
      pos.col = col.cint
      if screen.getCell(pos, addr(cell)):
        var c = TerminalChar(
          ch: cell.chars[0].Rune,
          fg: fgNone,
          bg: bgNone,
          # style: set[Style],
          # forceWrite: bool,
          # previousWideGlyph bool,
        )
        let fg = cell.fg
        if cell.fg.isRGB:
          c.fg = fgRGB
          c.fgColor = rgb(cell.fg.rgb.red, cell.fg.rgb.green, cell.fg.rgb.blue)
        elif cell.fg.isIndexed:
          c.fg = fgRGB
          let idx = cell.fg.indexed.idx
          screen.convertColorToRgb(cell.fg.addr)
          c.fgColor = rgb(cell.fg.rgb.red, cell.fg.rgb.green, cell.fg.rgb.blue)

        if cell.bg.isRGB:
          c.bg = bgRGB
          c.bgColor = rgb(cell.bg.rgb.red, cell.bg.rgb.green, cell.bg.rgb.blue)
        elif cell.bg.isIndexed:
          c.bg = bgRGB
          let idx = cell.bg.indexed.idx
          screen.convertColorToRgb(cell.bg.addr)
          c.bgColor = rgb(cell.bg.rgb.red, cell.bg.rgb.green, cell.bg.rgb.blue)

        result[col, row] = c

type
  InputEvent = object
    input: int64
    modifiers: Modifiers
    text: string

  OutputEventKind {.pure.} = enum TerminalBuffer, Size, Cursor
  OutputEvent = object
    case kind: OutputEventKind
    of OutputEventKind.TerminalBuffer:
      buffer: TerminalBuffer
    of OutputEventKind.Size:
      width: int
      height: int
    of OutputEventKind.Cursor:
      row: int
      col: int
      visible: bool

  ThreadState = object
    vterm: ptr VTerm
    screen: ptr VTermScreen
    inputWriteHandle: HANDLE
    outputReadHandle: HANDLE
    inputChannel: ptr Channel[InputEvent]
    outputChannel: ptr Channel[OutputEvent]
    sizeChannel: ptr Channel[tuple[width, height: int]]
    width: int
    height: int
    cursorVisible: bool

  Terminal* = ref object
    command: string
    hpcon: HPCON
    inputWriteHandle: HANDLE
    outputReadHandle: HANDLE
    vterm: ptr VTerm
    screen: ptr VTermScreen
    thread: Thread[ThreadState]
    inputChannel: ptr Channel[InputEvent] # todo: free this
    outputChannel: ptr Channel[OutputEvent] # todo: free this
    sizeChannel: ptr Channel[tuple[width, height: int]]
    terminalBuffer*: TerminalBuffer
    cursor*: tuple[row, col: int, visible: bool]
    onUpdated: Event[void]

proc handleOutputChannel(self: Terminal) {.async.} =
  # todo: cancel when closed
  while true:
    await sleepAsync(10.milliseconds)

    var updated = false
    while self.outputChannel[].peek() > 0:
      let event = self.outputChannel[].recv()
      # debugf"output event {event.kind}"
      case event.kind
      of OutputEventKind.TerminalBuffer:
        self.terminalBuffer = event.buffer
      of OutputEventKind.Size:
        discard
      of OutputEventKind.Cursor:
        self.cursor = (event.row, event.col, event.visible)

      updated = true

    if updated:
      self.onUpdated.invoke()

proc terminalThread(s: ThreadState) {.thread, nimcall.} =
  var state = s

  var inputWriteStream = newFileHandleStream(FileHandle(state.inputWriteHandle))
  var outputReadStream = newFileHandleStream(FileHandle(state.outputReadHandle))

  proc handleOutput(s: cstring; len: csize_t; user: pointer) {.cdecl.} =
    var str = newSeq[uint8]()
    for i in 0..<len.int:
      str.add s[i].uint8

    if len > 0:
      let state = cast[ptr ThreadState](user)
      var bytesWritten: int32
      if WriteFile(state[].inputWriteHandle, s[0].addr, len.cint, bytesWritten.addr, nil) == 0:
        echo "Failed to write data to shell: ", newOSError(osLastError()).msg
      if bytesWritten.int < len.int:
        echo "--------------------------------------------"
        echo "failed to write all bytes to shell"

  var callbacks = VTermScreenCallbacks(
    # damage: (proc(rect: VTermRect; user: pointer): cint {.cdecl.} = discard),
    # moverect: (proc(dest: VTermRect; src: VTermRect; user: pointer): cint {.cdecl.} = discard),
    movecursor: (proc(pos: VTermPos; oldpos: VTermPos; visible: cint; user: pointer): cint {.cdecl.} =
      let visible = visible != 0
      let state = cast[ptr ThreadState](user)
      # echo &"movecursor {oldpos} -> {pos}, {visible}"
      if state.cursorVisible != visible or (visible and pos != oldpos):
        state.outputChannel[].send OutputEvent(kind: OutputEventKind.Cursor, row: pos.row.int, col: pos.col.int, visible: visible != 0)
      state.cursorVisible = visible
    ),
    # settermprop: (proc(prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.} = discard),
    # bell: (proc(user: pointer): cint {.cdecl.} = discard),
    resize: (proc(rows: cint; cols: cint; user: pointer): cint {.cdecl.} =
      let state = cast[ptr ThreadState](user)
      state.outputChannel[].send OutputEvent(kind: OutputEventKind.Size, width: cols.int, height: rows.int)
    ),
    # sb_pushline: (proc(cols: cint; cells: ptr VTermScreenCell; user: pointer): cint {.cdecl.} = discard),
    # sb_popline: (proc(cols: cint; cells: ptr VTermScreenCell; user: pointer): cint {.cdecl.} = discard),
    # sb_clear: (proc(user: pointer): cint {.cdecl.} = discard),
  )

  state.vterm.setOutputCallback(handleOutput, state.addr)
  state.vterm.screen.setCallbacks(callbacks.addr, state.addr)

  var line = newStringOfCap(120)
  var last = '\n'
  var eof = false
  var buffer = ""
  while not outputReadStream.atEnd:
    var bytesAvailable: DWORD = 0
    if PeekNamedPipe(state.outputReadHandle, nil, 0, nil, bytesAvailable.addr, nil) == 0:
      echo "Failed to peek named pipe", newOSError(osLastError()).msg

    if bytesAvailable > 0:
      buffer.setLen(bytesAvailable)
      outputReadStream.readStr(buffer.len, buffer)
      let written = state.vterm.writeInput(buffer.cstring, buffer.len.csize_t).int
      if written != buffer.len:
        echo "fix me: vterm.nim.terminalThread vterm.writeInput"
        assert written == buffer.len, "fix me: vterm.nim.terminalThread vterm.writeInput"

      state.screen.flushDamage()
      state.outputChannel[].send OutputEvent(
        kind: OutputEventKind.TerminalBuffer,
        buffer: state.screen.createTerminalBuffer(state.width, state.height))

    while state.sizeChannel[].peek() > 0:
      let (newWidth, newHeight) = state.sizeChannel[].recv()
      state.width = newWidth
      state.height = newHeight
      state.vterm.setSize(state.height.cint, state.width.cint)
      state.screen.flushDamage()
      state.outputChannel[].send OutputEvent(
        kind: OutputEventKind.TerminalBuffer,
        buffer: state.screen.createTerminalBuffer(state.width, state.height))

    while state.inputChannel[].peek() > 0:
      let event = state.inputChannel[].recv()
      try:
        if event.text.len > 0:
          inputWriteStream.write(event.text)
        elif event.input > 0:
          # echo "write input key to shell: ", event.input, ", ", event.modifiers.toVtermModifiers
          # inputWriteStream.write($event.input.Rune)
          state.vterm.uniChar(event.input.uint32, event.modifiers.toVtermModifiers)
        elif event.input < 0:
          case event.input
          of INPUT_SPACE:
            state.vterm.uniChar(' '.uint32, event.modifiers.toVtermModifiers)
          else:
            # echo "write key to shell: ", event.input.inputToVtermKey, ", ", event.modifiers.toVtermModifiers
            state.vterm.key(event.input.inputToVtermKey, event.modifiers.toVtermModifiers)
      except:
        echo &"Failed to send input: {getCurrentExceptionMsg()}"

proc createTerminal*(width: int, height: int, command: string): Terminal =
  var
    inputReadSide: HANDLE
    outputWriteSide: HANDLE

  var
    outputReadSide: HANDLE
    inputWriteSide: HANDLE

  var sa: SECURITY_ATTRIBUTES
  sa.nLength = sizeof(sa).DWORD
  sa.lpSecurityDescriptor = nil
  sa.bInheritHandle = true
  if CreatePipe(addr(inputReadSide), addr(inputWriteSide), sa.addr, 0) == 0:
    raiseOSError(osLastError())

  if CreatePipe(addr(outputReadSide), addr(outputWriteSide), sa.addr, 0) == 0:
    raiseOSError(osLastError())

  var hPC: HPCON
  if CreatePseudoConsole(wincon.COORD(X: width.SHORT, Y: height.SHORT), inputReadSide, outputWriteSide, 0, addr(hPC)) != S_OK:
    raiseOSError(osLastError())

  var siEx: STARTUPINFOEX = prepareStartupInformation(hPC)
  var pi: PROCESS_INFORMATION
  ZeroMemory(addr(pi), sizeof((pi)))

  let cmd = newWideCString(command)
  if CreateProcessW(nil, cmd, nil, nil, FALSE, EXTENDED_STARTUPINFO_PRESENT, nil, nil, siEx.StartupInfo.addr, pi.addr) == 0:
    raiseOSError(osLastError())

  CloseHandle(inputReadSide)
  CloseHandle(outputWriteSide)

  let vterm = VTerm.new(height.cint, width.cint)
  if vterm == nil:
    raise newException(IOError, "Failed to init VTerm")

  vterm.setUtf8(1)

  let screen = vterm.screen()
  screen.reset(1)
  screen.setDamageMerge(VTERM_DAMAGE_SCROLL)

  result = Terminal(
    command: command,
    hpcon: hPC,
    inputWriteHandle: inputWriteSide,
    outputReadHandle: outputReadSide,
    vterm: vterm,
    screen: screen,
  )

  proc createChannel[T](channel: var ptr[Channel[T]]) =
    channel = cast[ptr Channel[T]](allocShared0(sizeof(Channel[T])))
    channel[].open()

  result.inputChannel.createChannel()
  result.outputChannel.createChannel()
  result.sizeChannel.createChannel()

  result.terminalBuffer.initTerminalBuffer(width, height)
  asyncSpawn result.handleOutputChannel()

  let threadState = ThreadState(
    vterm: vterm,
    screen: screen,
    inputWriteHandle: inputWriteSide,
    outputReadHandle: outputReadSide,
    inputChannel: result.inputChannel,
    outputChannel: result.outputChannel,
    sizeChannel: result.sizeChannel,
    width: width,
    height: height,
    cursorVisible: true,
  )
  result.thread.createThread(terminalThread, threadState)

proc terminate*(self: Terminal) =
  # echo &"terminate {self.command}"
  ClosePseudoConsole(self.hpcon)

{.push gcsafe.}
{.push raises: [].}

type
  TerminalService* = ref object of Service
    events: EventHandlerService
    config: ConfigService
    layout: LayoutService
    terminal: Terminal

  TerminalView* = ref object of View
    eventHandler: EventHandler
    modeEventHandler: EventHandler
    mode*: string
    size*: tuple[width, height: int]
    terminal*: Terminal

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[JsonNode]

method getEventHandlers*(self: TerminalView, inject: Table[string, EventHandler]): seq[EventHandler] =
  result = @[self.eventHandler]
  if self.modeEventHandler != nil:
    result.add self.modeEventHandler

func serviceName*(_: typedesc[TerminalService]): string = "TerminalService"
addBuiltinService(TerminalService, LayoutService, EventHandlerService, ConfigService)

method init*(self: TerminalService): Future[Result[void, ref CatchableError]] {.async: (raises: []).} =
  log lvlInfo, &"TerminalService.init"

  self.events = self.services.getService(EventHandlerService).get
  self.layout = self.services.getService(LayoutService).get
  self.config = self.services.getService(ConfigService).get

  return ok()

proc requestRender(self: TerminalService) =
  self.services.getService(PlatformService).get.platform.requestRender()

proc handleInput(self: TerminalService, view: TerminalView, input: string) =
  # debugf"handleInput '{input}'"
  view.terminal.inputChannel[].send(InputEvent(text: input))

proc handleKey(self: TerminalService, view: TerminalView, input: int64, modifiers: Modifiers) =
  # debugf"handleKey {inputToString(input, modifiers)}"
  view.terminal.inputChannel[].send(InputEvent(input: input, modifiers: modifiers))

proc updateModeEventHandlers(self: TerminalService, view: TerminalView) =
  if view.mode.len == 0:
    view.modeEventHandler = nil
  else:
    let config = self.events.getEventHandlerConfig("terminal." & view.mode)
    assignEventHandler(view.modeEventHandler, config):
      onAction:
        if self.handleAction(view, action, arg).isSome:
          Handled
        else:
          Ignored

      onInput:
        self.handleInput(view, input)
        Handled

      onKey:
        self.handleKey(view, input, mods)
        Handled

proc setSize*(self: TerminalView, width: int, height: int) =
  if self.size != (width, height):
    discard
    # self.size = (width, height)
    # if self.terminal != nil:
    #   self.terminal.sizeChannel[].send self.size

proc createTerminalView(self: TerminalService): TerminalView =
  try:
    let shell = self.config.runtime.get("terminal.shell", "C:/WINDOWS/System32/WindowsPowerShell/v1.0/powershell.exe")
    let term = createTerminal(WIDTH, HEIGHT, shell)
    let view = TerminalView(terminal: term)
    assignEventHandler(view.eventHandler, self.events.getEventHandlerConfig("terminal")):
      onAction:
        if self.handleAction(view, action, arg).isSome:
          Handled
        else:
          Ignored

      onInput:
        self.handleInput(view, input)
        Handled

      onKey:
        self.handleKey(view, input, mods)
        Handled

      view.mode = self.config.runtime.get("terminal.default-mode", "normal")
      self.updateModeEventHandlers(view)

    discard term.onUpdated.subscribe proc() =
      self.services.getService(PlatformService).get.platform.requestRender()

    self.terminal = term

    return view
  except:
    log lvlError, &"Failed to create terminal: {getCurrentExceptionMsg()}"

proc getTerminalService*(): Option[TerminalService] =
  {.gcsafe.}:
    if gServices.isNil: return TerminalService.none
    return gServices.getService(TerminalService)

static:
  addInjector(TerminalService, getTerminalService)

proc setTerminalMode*(self: TerminalService, mode: string) {.expose("terminal").} =
  if self.layout.tryGetCurrentView().getSome(v) and v of TerminalView:
    let view = v.TerminalView
    view.mode = mode
    self.updateModeEventHandlers(view)
    self.requestRender()

proc createTerminal*(self: TerminalService) {.expose("terminal").} =
  self.layout.addView(self.createTerminalView())

genDispatcher("terminal")
addGlobalDispatchTable "terminal", genDispatchTable("terminal")

proc handleActionInternal(self: TerminalService, view: TerminalView, action: string, args: JsonNode): Option[JsonNode] =
  # if self.plugins.invokeAnyCallback(action, args).isNotNil:
  #   return Handled

  try:
    if dispatch(action, args).getSome(res):
      return res.some
  except:
    let argsText = if args.isNil: "nil" else: $args
    log(lvlError, fmt"Failed to dispatch command '{action} {argsText}': {getCurrentExceptionMsg()}")
    return JsonNode.none

  log lvlError, fmt"Unknown command '{action}'"
  return JsonNode.none

proc handleAction(self: TerminalService, view: TerminalView, action: string, arg: string): Option[JsonNode] =
  try:
    var args = newJArray()
    try:
      for a in newStringStream(arg).parseJsonFragments():
        args.add a

      return self.handleActionInternal(view, action, args)
    except CatchableError:
      log(lvlError, fmt"handleCommmand: {action}, Failed to parse args: '{arg}'")
      return JsonNode.none
  except:
    discard
