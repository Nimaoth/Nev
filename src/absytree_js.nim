
import misc/custom_logger

logCategory "main-js"

logger.enableConsoleLogger()

import std/[strformat, dom, macros]
import misc/[util, timer, event, custom_async]
import platform/[platform, browser_platform]
import ui/[widget_builders]
import text/text_document
import text/language/language_server
from scripting_api import Backend
import app

import ui/node

createNimScriptContextConstructorAndGenerateBindings()

# Initialize renderer
var rend: BrowserPlatform = new BrowserPlatform
rend.init()

var initializedEditor = false
var hasRequestedRerender = false
var isRenderInProgress = false

var frameIndex = 0

var advanceFrame = false
var start: float = -1
var previousTimestep: float = 0

proc requestRender(redrawEverything = false)

proc doRender(timestep: float) =
  # echo "requestAnimationFrame ", time

  if timestep == previousTimestep:
    # echo "multiple per frame"
    return

  if start < 0 or rend.builder.animatingNodes.len == 0:
    start = timestep
    rend.builder.frameTime = 0
  else:
    rend.builder.frameTime = timestep - previousTimestep
  previousTimestep = timestep

  defer:
    if rend.builder.animatingNodes.len > 0:
      requestRender()

  hasRequestedRerender = false
  isRenderInProgress = true
  defer: isRenderInProgress = false
  defer: inc frameIndex

  var layoutTime, updateTime, renderTime: float
  var frameTime = 0.0
  block:
    gEditor.frameTimer = startTimer()

    let updateTimer = startTimer()
    if advanceFrame:
      rend.builder.beginFrame(rend.size)
      gEditor.updateWidgetTree(frameIndex)
      rend.builder.endFrame()
    elif rend.builder.animatingNodes.len > 0:
      rend.builder.frameIndex.inc
      rend.builder.postProcessNodes()
    updateTime = updateTimer.elapsed.ms

    # if logRoot:
    #   echo "frame ", rend.builder.frameIndex
    #   echo rend.builder.root.dump(true)

    let renderTimer = startTimer()
    rend.render()
    renderTime = renderTimer.elapsed.ms

    frameTime = gEditor.frameTimer.elapsed.ms

  if frameTime > 10:
  # if logFrameTime:
    echo fmt"Frame: {frameTime:>5.2}ms (u: {updateTime:>5.2}ms, l: {layoutTime:>5.2}ms, r: {renderTime:>5.2}ms)"


proc requestRender(redrawEverything = false) =
  advanceFrame = true

  if not initializedEditor:
    return
  if hasRequestedRerender:
    return
  if isRenderInProgress:
    return

  discard window.requestAnimationFrame doRender

proc runApp(): Future[void] {.async.} =
  discard await newEditor(Backend.Browser, rend)

  discard rend.onKeyPress.subscribe proc(event: auto): void = requestRender()
  discard rend.onKeyRelease.subscribe proc(event: auto): void = requestRender()
  discard rend.onRune.subscribe proc(event: auto): void = requestRender()
  discard rend.onMousePress.subscribe proc(event: auto): void = requestRender()
  discard rend.onMouseRelease.subscribe proc(event: auto): void = requestRender()
  # discard rend.onMouseMove.subscribe proc(event: auto): void = requestRender()
  discard rend.onScroll.subscribe proc(event: auto): void = requestRender()
  discard rend.onCloseRequested.subscribe proc(_: auto) = requestRender()
  discard rend.onResized.subscribe proc(redrawEverything: bool) = requestRender(redrawEverything)

  initializedEditor = true
  requestRender()

asyncCheck runApp()

# Useful for debugging nim strings in the browser
# Just turns a nim string to a javascript string
proc nimStrToCStr(str: string): cstring {.exportc, used.} = str

# Override some functions with more optimized versions
{.emit: """
const hiXorLoJs_override_mask = BigInt("0xffffffffffffffff");
const hiXorLoJs_override_shift = BigInt("64");
function hiXorLoJs_override(a, b) {
    var prod = (a * b);
    return ((prod >> hiXorLoJs_override_shift) ^ (prod & hiXorLoJs_override_mask));
}

var hashWangYi1_override_c1 = BigInt("0xa0761d6478bd642f");
var hashWangYi1_override_c2 = BigInt("0xe7037ed1a0b428db");
var hashWangYi1_override_c3 = BigInt("0xeb44accab455d16d");

function hashWangYi1_override(x) {
    if (typeof BigInt != 'undefined') {
        var res = hiXorLoJs_override(hiXorLoJs_override(hashWangYi1_override_c1, (BigInt(x) ^ hashWangYi1_override_c2)), hashWangYi1_override_c3);
        return Number(BigInt.asIntN(32, res));
    }
    else {
        return (x & 4294967295);
    }
}

function imul_override(a_1342177593, b_1342177594) {
  var result_1342177595 = 0;

    var mask_1342177596 = 65535;
    var aHi_1342177601 = (((a_1342177593 >>> 16) & mask_1342177596) >>> 0);
    var aLo_1342177602 = ((a_1342177593 & mask_1342177596) >>> 0);
    var bHi_1342177607 = (((b_1342177594 >>> 16) & mask_1342177596) >>> 0);
    var bLo_1342177608 = ((b_1342177594 & mask_1342177596) >>> 0);
    result_1342177595 = ((((aLo_1342177602 * bLo_1342177608) >>> 0) + ((((((aHi_1342177601 * bLo_1342177608) >>> 0) + ((aLo_1342177602 * bHi_1342177607) >>> 0)) >>> 0) << 16) >>> 0)) >>> 0);

  return result_1342177595;

}

function rotl32_override(x_1342177614, r_1342177615) {
  var result_1342177616 = 0;

    result_1342177616 = ((((x_1342177614 << r_1342177615) >>> 0) | (x_1342177614 >>> (32 - r_1342177615))) >>> 0);

  return result_1342177616;

}

function murmurHash_override(x_1342177626) {
  var result_1342177627 = 0;

  BeforeRet: {
    var size_1342177636 = (x_1342177626).length;
    var stepSize_1342177637 = 4;
    var n_1342177638 = Math.trunc(size_1342177636 / stepSize_1342177637);
    var h1_1342177639 = 0;
    var i_1342177640 = 0;
    Label1: {
        Label2: while (true) {
        if (!(i_1342177640 < (n_1342177638 * stepSize_1342177637))) break Label2;
          var k1_1342177641 = 0;
          var j_1342177642 = stepSize_1342177637;
          Label3: {
              Label4: while (true) {
              if (!(0 < j_1342177642)) break Label4;
                j_1342177642 -= 1;
                k1_1342177641 = ((((k1_1342177641 << 8) >>> 0) | x_1342177626[(i_1342177640 + j_1342177642)]) >>> 0);
              }
          };
          i_1342177640 += stepSize_1342177637;
          k1_1342177641 = imul_override(k1_1342177641, 3432918353);
          k1_1342177641 = rotl32_override(k1_1342177641, 15);
          k1_1342177641 = imul_override(k1_1342177641, 461845907);
          h1_1342177639 = ((h1_1342177639 ^ k1_1342177641) >>> 0);
          h1_1342177639 = rotl32_override(h1_1342177639, 13);
          h1_1342177639 = ((((h1_1342177639 * 5) >>> 0) + 3864292196) >>> 0);
        }
    };
    var k1_1342177661 = 0;
    var rem_1342177662 = Math.trunc(size_1342177636 % stepSize_1342177637);
    Label5: {
        Label6: while (true) {
        if (!(0 < rem_1342177662)) break Label6;
          rem_1342177662 -= 1;
          k1_1342177661 = ((((k1_1342177661 << 8) >>> 0) | x_1342177626[(i_1342177640 + rem_1342177662)]) >>> 0);
        }
    };
    k1_1342177661 = imul_override(k1_1342177661, 3432918353);
    k1_1342177661 = rotl32_override(k1_1342177661, 15);
    k1_1342177661 = imul_override(k1_1342177661, 461845907);
    h1_1342177639 = ((h1_1342177639 ^ k1_1342177661) >>> 0);
    h1_1342177639 = ((h1_1342177639 ^ size_1342177636) >>> 0);
    h1_1342177639 = ((h1_1342177639 ^ (h1_1342177639 >>> 16)) >>> 0);
    h1_1342177639 = imul_override(h1_1342177639, 2246822507);
    h1_1342177639 = ((h1_1342177639 ^ (h1_1342177639 >>> 13)) >>> 0);
    h1_1342177639 = imul_override(h1_1342177639, 3266489909);
    h1_1342177639 = ((h1_1342177639 ^ (h1_1342177639 >>> 16)) >>> 0);
    result_1342177627 = h1_1342177639 & 0xffffffff;
    break BeforeRet;
  };

  return result_1342177627;

}


let nimCopyCounters = new Map();
let nimCopyTimers = new Map();
let breakOnCopyType = null;
let stats = []

function clearNimCopyStats() {
    nimCopyCounters.clear();
    nimCopyTimers.clear();
}

function dumpNimCopyStatsImpl(desc, map, sortBy, setBreakOnCopyTypeIndex) {
    let values = []
    for (let entry of map.entries()) {
        values.push(entry)
    }

    values.sort((a, b) => b[1][sortBy] - a[1][sortBy])

    stats = values

    console.log(desc)

    let i = 0;
    for (let [type, stat] of values) {
        if (i == setBreakOnCopyTypeIndex) {
            breakOnCopyType = type
        }
        console.log(stat, ": ", type)
        i++
        if (i > 20) {
          break
        }
    }
}

function selectType(setBreakOnCopyTypeIndex) {
    if (setBreakOnCopyTypeIndex < stats.length) {
        breakOnCopyType = stats[setBreakOnCopyTypeIndex][0]
    }
}

function dumpNimCopyStats(sortBy, setBreakOnCopyTypeIndex) {
    //dumpNimCopyStatsImpl("Counts: ", nimCopyCounters)
    dumpNimCopyStatsImpl("Times: ", nimCopyTimers, sortBy || 0, setBreakOnCopyTypeIndex)
}

function nimCopyOverride(dest, src, ti) {
    if (ti === breakOnCopyType) {
      debugger;
    }

    let existing = nimCopyCounters.get(ti) || 0;
    nimCopyCounters.set(ti, existing + 1)

    let start = Date.now()
    let result = window._old_nimCopy(dest, src, ti);
    let elapsed = Date.now() - start

    let existingTime = nimCopyTimers.get(ti) || [0, 0];
    nimCopyTimers.set(ti, [existingTime[0] + elapsed, existingTime[1] + 1])

    return result;
}

function overrideFunction(name, original, override) {
    window["_old_" + name] = original
    window[name] = override
}

for (name of Object.keys(window)) {
    if (name.startsWith("murmurHash_") && name != "murmurHash_override") {
        let original = window[name]
        overrideFunction(name, original, murmurHash_override)
    }
}
""".}

import hashes

macro overrideFunction(body: typed, override: untyped): untyped =
  # echo body.treeRepr
  let original = case body.kind
  of nnkCall: body[0]
  of nnkStrLit: body
  else: body

  return quote do:
    {.emit: ["overrideFunction(\"", `original`, "\", ", `original`, ", ", `override`, ");"].}

overrideFunction(hashWangYi1(1.int64), "hashWangYi1_override")
overrideFunction(hashWangYi1(2.uint64), "hashWangYi1_override")
overrideFunction(hashWangYi1(3.Hash), "hashWangYi1_override")

# overrideFunction("nimCopy", "nimCopyOverride")