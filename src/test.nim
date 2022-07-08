import std/[strformat, bitops, strutils, tables, algorithm, math]
import boxy, opengl, times, windy
import monitors
import sugar
import input

let typeface = readTypeface("fonts/FiraCode-Regular.ttf")
let typeface2 = readTypeface("fonts/Noto_Emoji/static/NotoEmoji-Regular.ttf")