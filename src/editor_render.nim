import std/[strformat, bitops, strutils, tables, algorithm, math]
import boxy, times, windy
import sugar
import input, editor

let typeface = readTypeface("fonts/FiraCode-Regular.ttf")

proc renderCommandAutoCompletion*(ed: Editor, ctx: Context) =
  let nextPossibleInputs = dfa.autoComplete(state)

  var longestInput = 0
  var longestCommand = 0

  for kv in nextPossibleInputs:
    if kv[0].len > longestInput: longestInput = kv[0].len
    if kv[1].len > longestCommand: longestCommand = kv[1].len

  let lineSpacing: float32 = 2
  let horizontalSizeModifier: float32 = 0.65
  let gap: float32 = 10
  let commandsOrigin = vec2(ed.window.size.x.float32 - (longestCommand.float32 * ctx.fontSize * horizontalSizeModifier), ed.window.size.y.float32 - (nextPossibleInputs.len.float32 * (ctx.fontSize + lineSpacing)))
  let inputsOrigin = vec2(commandsOrigin.x.float32 - gap - (longestInput.float32 * ctx.fontSize * horizontalSizeModifier), commandsOrigin.y.float32)

  for i, kv in nextPossibleInputs:
    let (remainingInput, action) = kv

    ctx.fillText(remainingInput, vec2(inputsOrigin.x, inputsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))
    ctx.fillText(action, vec2(commandsOrigin.x, commandsOrigin.y + i.float * (ctx.fontSize + lineSpacing)))

  ctx.strokeRect(rect(inputsOrigin, vec2(ed.window.size.x.float32 - inputsOrigin.x, ed.window.size.y.float32 - inputsOrigin.y)))
  ctx.beginPath()
  ctx.moveTo(commandsOrigin.x - gap * 0.5, commandsOrigin.y)
  ctx.lineTo(commandsOrigin.x - gap * 0.5, ed.window.size.y.float32)
  ctx.stroke()


proc render*(ed: Editor) =
  let image = newImage(ed.window.size.x, ed.window.size.y)
  let ctx = newContext(image)
  ctx.fillStyle = rgb(255, 255, 255)
  ctx.strokeStyle = rgb(255, 255, 255)
  ctx.font = "fonts/FiraCode-Regular.ttf" 
  ctx.fontSize = ed.fontSize
  ctx.textBaseline = TopBaseline

  ctx.strokeRect(rect(vec2(0, 0), vec2(ed.window.size.x.float32, ctx.fontSize)))
  ctx.fillText(ed.inputBuffer, vec2(0, 0))

  ed.renderCommandAutoCompletion(ctx)

  ed.boxy.addImage("main", image)
  ed.boxy.drawImage("main", vec2(0, 0))