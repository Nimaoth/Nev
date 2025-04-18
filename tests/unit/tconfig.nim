import std/[unittest, options, sequtils, strformat, strutils]
import misc/[util, jsonex, timer, custom_logger]
import config_provider

logCategory "tconfig"

var layer1 = ConfigStore.new(nil, "layer1", %%*{
  "a": 1,
  "b": 2,
  "c": %%*{
    "a": 3,
    "b": 4,
  },
  "d.a": 1,
  "d.b": 2,
  "d.c.a": 1,
  "d.c.b": %%*{
    "a": 1,
    "b.a": 2,
  },
  "e": %%*{
    "a": %%*{
      "a": 1,
      "b": 2,
    },
    "b": 1,
  },
})

var layer2 = ConfigStore.new(layer1, "layer2", %%*{
  "a": 2,
  "c": %%*{
    "c": 5,
  },
  "+d": %%*{
    "a": 2,
    "+c": %%*{
      "a": 9,
      "f": 10,
    },
    "e": 3,
  },
  "e.+a": %%*{
    "c": 3,
  },
})

# var layer3 = ConfigStore.new(layer2, "layer3", %%*{
# })

echo "================== layer 1 ===================="
echo layer1

echo "================== layer 2 ===================="
echo layer2

proc test(store: ConfigStore, key: string, debug = false) =
  if debug:
    logGetValue = true
  defer:
    logGetValue = false

  echo "=================== ", store.name, ".", key
  let value = store.getValue(key)
  if value.isNil:
    echo "nil"
  else:
    echo value

test(layer1, "a")
test(layer1, "b")
test(layer1, "c")
test(layer1, "c.a")

test(layer2, "a")
test(layer2, "b")
test(layer2, "c")
test(layer2, "c.a")
test(layer2, "c.c")

test(layer2, "d")
test(layer2, "d.a")
test(layer2, "d.b")
test(layer2, "d.e")

test(layer2, "d.c")
test(layer2, "d.c.a")
test(layer2, "d.c.b")
test(layer2, "d.c.f")

test(layer1, "e")
test(layer1, "e.a")
test(layer1, "e.b")
test(layer2, "e")
test(layer2, "e.a")
test(layer2, "e.b")

layer1.set("a", 3)

echo "================== layer 1 ===================="
echo layer1

test(layer1, "a")
test(layer2, "a")

proc testSetting[T](setting: Setting[T]) =
  echo &"--- testSetting {setting.store.desc}.{setting.key}, cache: {setting.cache}, layers: {setting.layers.mapIt((it.revision, it.kind, it.store.desc))}"
  echo setting.get(nil)
  echo &"new layers: {setting.layers.mapIt((it.revision, it.kind, it.store.desc))}"

proc testSetting(key: string, changeLayer: ConfigStore, value: int, debug = false) =
  logSetting = debug
  defer:
    logSetting = false
  echo "=================== setting ", layer2.name, ".", key
  var s = layer2.setting(key, JsonNodeEx)
  testSetting(s)
  testSetting(s)
  changeLayer.set(key, value)
  testSetting(s)
  testSetting(s)

testSetting("d.c.f", layer2, 113)
testSetting("a", layer1, 114)
testSetting("a", layer2, 113)

# var t = startTimer()
# for i in 0..<1000:
#   discard layer2.getValue("d.c.f")
# echo "getValue took ", t.elapsed.ms

# var s = layer2.setting("d.c.f", JsonNodeEx)
# t = startTimer()
# for i in 0..<1000:
#   discard s.get(nil)
# echo "Setting.get took ", t.elapsed.ms
