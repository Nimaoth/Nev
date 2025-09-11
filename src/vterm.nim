import misc/[custom_unicode]

{.compile: "./libvterm/encoding.c".}
{.compile: "./libvterm/keyboard.c".}
{.compile: "./libvterm/mouse.c".}
{.compile: "./libvterm/parser.c".}
{.compile: "./libvterm/pen.c".}
{.compile: "./libvterm/screen.c".}
{.compile: "./libvterm/state.c".}
{.compile: "./libvterm/unicode.c".}
{.compile: "./libvterm/vterm.c".}

{.passC: "-Ilibvterm".}
{.push header: "./libvterm/vterm.h".}

# {.compile: "./vterm/encoding.c".}
# {.compile: "./vterm/keyboard.c".}
# {.compile: "./vterm/mouse.c".}
# {.compile: "./vterm/parser.c".}
# {.compile: "./vterm/pen.c".}
# {.compile: "./vterm/screen.c".}
# {.compile: "./vterm/state.c".}
# {.compile: "./vterm/vterm.c".}
# {.passC: "-Ivterm".}

# {.push header: "./vterm/vterm.h".}

const VTERM_MAX_CHARS_PER_CELL = 6
type
  VTerm* {.importc.} = object
  VTermState* {.importc.} = object
  VTermScreen* {.importc.} = object

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
    dim* {.bitsize: 1.}: cuint

  VTermScreenCell* {.bycopy, importc.} = object
    chars*: array[VTERM_MAX_CHARS_PER_CELL, uint32]
    # schar*: uint32
    width*: char
    attrs*: VTermScreenCellAttrs
    fg*: VTermColor
    bg*: VTermColor
    # uri*: cint

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
    VTERM_ATTR_DIM,           ##  number: 2, 22
    # VTERM_ATTR_URI,           ##  number

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
    # VTERM_PROP_THEMEUPDATES,  ##  bool

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
    # schar*: uint32
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
    control*: proc (control: char; user: pointer): cint {.cdecl.}
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
    control*: proc (control: char; user: pointer): cint {.cdecl.}
    csi*: proc (leader: cstring; args: ptr clong; argcount: cint; intermed: cstring; command: char; user: pointer): cint {.cdecl.}
    osc*: proc (command: cint; frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    dcs*: proc (command: cstring; commandlen: csize_t; frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    apc*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    pm*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    sos*: proc (frag: VTermStringFragment; user: pointer): cint {.cdecl.}

  VTermScreenCallbacks* {.bycopy, importc.} = object
    damage*: proc (rect: VTermRect; user: pointer): cint {.cdecl.}
    erase*: proc (rect: VTermRect; user: pointer): cint {.cdecl.}
    moverect*: proc (dest: VTermRect; src: VTermRect; user: pointer): cint {.cdecl.}
    movecursor*: proc (pos: VTermPos; oldpos: VTermPos; visible: cint; user: pointer): cint {.cdecl.}
    settermprop*: proc (prop: VTermProp; val: ptr VTermValue; user: pointer): cint {.cdecl.}
    bell*: proc (user: pointer): cint {.cdecl.}
    resize*: proc (rows: cint; cols: cint; user: pointer): cint {.cdecl.}
    # theme*: proc (dark: ptr bool; user: pointer): cint {.cdecl.}
    sb_pushline*: proc (cols: cint; cells: ptr UncheckedArray[VTermScreenCell]; user: pointer): cint {.cdecl.}
    sb_popline*: proc (cols: cint; cells: ptr UncheckedArray[VTermScreenCell]; user: pointer): cint {.cdecl.}
    sb_clear*: proc (user: pointer): cint {.cdecl.}

  VTermSelectionCallbacks* {.bycopy, importc.} = object
    set*: proc (mask: VTermSelectionMask; frag: VTermStringFragment; user: pointer): cint {.cdecl.}
    query*: proc (mask: VTermSelectionMask; user: pointer): cint {.cdecl.}

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
    VTERM_ATTR_DIM_MASK = 1 shl 12,
    VTERM_ALL_ATTRS_MASK = (1 shl 13) - 1

  VTermSelectionMask* = enum
    VTERM_SELECTION_CLIPBOARD = (1 shl 0),
    VTERM_SELECTION_PRIMARY = (1 shl 1),
    VTERM_SELECTION_SECONDARY = (1 shl 2),
    VTERM_SELECTION_SELECT = (1 shl 3),
    VTERM_SELECTION_CUT0 = (1 shl 4)

const
  VTERM_PROP_CURSORSHAPE_BLOCK* = 1
  VTERM_PROP_CURSORSHAPE_UNDERLINE* = 2
  VTERM_PROP_CURSORSHAPE_BAR_LEFT* = 3

########## VTerm ###########
proc new*(_: typedesc[VTerm], rows, cols: c_int): ptr VTerm {.importc: "vterm_new".}
proc writeInput*(vt: ptr VTerm; bytes: cstring; len: csize_t): csize_t {.importc: "vterm_input_write".}
proc key*(vt: ptr VTerm; key: VTermKey; modifiers: uint32) {.importc: "vterm_keyboard_key".}
proc uniChar*(vt: ptr VTerm; c: uint32; modifiers: uint32) {.importc: "vterm_keyboard_unichar".}

proc startPaste*(vt: ptr VTerm) {.importc: "vterm_keyboard_start_paste".}
proc endPaste*(vt: ptr VTerm) {.importc: "vterm_keyboard_end_paste".}
proc mouseMove*(vt: ptr VTerm; row: cint; col: cint; modifiers: uint32) {.importc: "vterm_mouse_move".}
proc mouseButton*(vt: ptr VTerm; button: cint; pressed: bool; modifiers: uint32) {.importc: "vterm_mouse_button".}

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
proc moveCursor*(state: ptr VTermState; cols: cint; rows: cint) {.importc: "vterm_state_move_cursor".}
proc setCursor*(state: ptr VTermState; col: cint; row: cint) {.importc: "vterm_state_set_cursor".}
proc getCursorpos*(state: ptr VTermState; cursorpos: ptr VTermPos) {.importc: "vterm_state_get_cursorpos".}
proc getDefaultColors*(state: ptr VTermState; default_fg: ptr VTermColor; default_bg: ptr VTermColor) {.importc: "vterm_state_get_default_colors".}
proc getPaletteColor*(state: ptr VTermState; index: cint; col: ptr VTermColor) {.importc: "vterm_state_get_palette_color".}
proc setDefaultColors*(state: ptr VTermState; default_fg: ptr VTermColor; default_bg: ptr VTermColor) {.importc: "vterm_state_set_default_colors".}
proc setPaletteColorRaw*(state: ptr VTermState; index: cint; col: ptr VTermColor) {.importc: "vterm_state_set_palette_color".}
proc setBoldHighbright*(state: ptr VTermState; bold_is_highbright: cint) {.importc: "vterm_state_set_bold_highbright".}
proc getPenattr*(state: ptr VTermState; attr: VTermAttr; val: ptr VTermValue): cint {.importc: "vterm_state_get_penattr".}
proc setTermprop*(state: ptr VTermState; prop: VTermProp; val: ptr VTermValue): cint {.importc: "vterm_state_set_termprop".}
proc focusIn*(state: ptr VTermState) {.importc: "vterm_state_focus_in".}
proc focusOut*(state: ptr VTermState) {.importc: "vterm_state_focus_out".}
proc getLineinfo*(state: ptr VTermState; row: cint): ptr VTermLineInfo {.importc: "vterm_state_get_lineinfo".}

proc setSelectionCallbacks*(state: ptr VTermState; callbacks: ptr VTermSelectionCallbacks; user: pointer; buffer: cstring; buflen: csize_t) {.importc: "vterm_state_set_selection_callbacks".}
proc sendSelection*(state: ptr VTermState; mask: VTermSelectionMask; frag: VTermStringFragment) {.importc: "vterm_state_send_selection".}

{.pop.}

proc vtermRgb*(r, g, b: uint8): VTermColor =
  result.`type` = VTERM_COLOR_RGB.ord.uint8
  result.rgb.red = r
  result.rgb.green = g
  result.rgb.blue = b

proc setPaletteColor*(state: ptr VTermState; index: int; color: tuple[r, g, b: uint8]) =
  var color: VTermColor = vtermRgb(color.r, color.g, color.b)
  state.setPaletteColorRaw(index.cint, color.addr)

const VTERM_COLOR_TYPE_MASK = 1.uint8

proc isIndexed*(col: VTermColor): bool =
  ((col.`type` and VTERM_COLOR_TYPE_MASK) == ord(VTERM_COLOR_INDEXED).uint8)

proc isRGB*(col: VTermColor): bool =
  ((col.`type` and VTERM_COLOR_TYPE_MASK) == ord(VTERM_COLOR_RGB).uint8)

proc isDefaultFg*(col: VTermColor): bool =
  (col.`type` and ord(VTERM_COLOR_DEFAULT_FG).uint8) != 0

proc isDefaultBg*(col: VTermColor): bool =
  (col.`type` and ord(VTERM_COLOR_DEFAULT_BG).uint8) != 0

proc `$`*(frag: VTermStringFragment): string =
  result.setLen(frag.len.int)
  copyMem(result[0].addr, frag.str[0].addr, frag.len.int)
