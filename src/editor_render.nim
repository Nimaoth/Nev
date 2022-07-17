import std/[strformat, bitops, strutils, tables, algorithm, math, macros]
import boxy, times, windy
import sugar
import input, editor, rect_utils

let typeface = readTypeface("fonts/FiraCode-Regular.ttf")

proc renderCommandAutoCompletion*(ed: Editor, bounds: Rect) =
  let ctx = ed.ctx
  let nextPossibleInputs = dfa.autoComplete(state)

  var longestInput = 0
  var longestCommand = 0

  for kv in nextPossibleInputs:
    if kv[0].len > longestInput: longestInput = kv[0].len
    if kv[1].len > longestCommand: longestCommand = kv[1].len

  let lineSpacing: float32 = 2
  let horizontalSizeModifier: float32 = 0.65
  let gap: float32 = 10
  let commandsOrigin = vec2(bounds.w - (longestCommand.float32 * ctx.fontSize * horizontalSizeModifier), bounds.h - (nextPossibleInputs.len.float32 * (ctx.fontSize + lineSpacing)))
  let inputsOrigin = vec2(commandsOrigin.x.float32 - gap - (longestInput.float32 * ctx.fontSize * horizontalSizeModifier), commandsOrigin.y.float32)

  ctx.fillStyle = rgb(75, 75, 75)

  for i, kv in nextPossibleInputs:
    let (remainingInput, action) = kv

    ctx.fillText(remainingInput, vec2(bounds.x + inputsOrigin.x, bounds.y + inputsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))
    ctx.fillText(action, vec2(bounds.x + commandsOrigin.x, bounds.y + commandsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))

  ctx.strokeRect(rect(inputsOrigin + vec2(bounds.x, bounds.y), vec2(bounds.w - inputsOrigin.x, bounds.h - inputsOrigin.y)))
  ctx.beginPath()
  ctx.moveTo(bounds.x + commandsOrigin.x - gap * 0.5, bounds.y + commandsOrigin.y)
  ctx.lineTo(bounds.x + commandsOrigin.x - gap * 0.5, bounds.y + bounds.h)
  ctx.stroke()

proc renderStatusBar*(ed: Editor, bounds: Rect) =
  ed.ctx.fillStyle = rgb(255, 0, 0)
  ed.ctx.fillRect(bounds)

  ed.ctx.fillStyle = rgb(75, 75, 75)
  ed.ctx.fillText(ed.inputBuffer, vec2(bounds.x, bounds.y))

proc renderMainWindow*(ed: Editor, bounds: Rect) =
  ed.ctx.fillStyle = rgb(0, 255, 0)
  ed.ctx.fillRect(bounds)
  ed.renderCommandAutoCompletion(bounds)

proc render*(ed: Editor) =
  ed.ctx.image = newImage(ed.window.size.x, ed.window.size.y)
  let lineHeight = ed.ctx.fontSize
  let windowRect = rect(vec2(), ed.window.size.vec2)

  let (mainRect, statusRect) = if not ed.statusBarOnTop: windowRect.splitH(absolute(windowRect.h - lineHeight))
  else: windowRect.splitHInv(absolute(lineHeight))

  ed.renderMainWindow(mainRect)
  ed.renderStatusBar(statusRect)

  ed.boxy.addImage("main", ed.ctx.image)
  ed.boxy.drawImage("main", vec2(0, 0))