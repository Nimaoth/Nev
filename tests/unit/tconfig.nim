import std/[unittest, options, json, sequtils, strformat, strutils]
import misc/[util]
import config_provider

var debug = true
template log(msg: untyped) =
  if debug:
    echo msg

var layer1 = ConfigStore.new(nil, "layer1", %*{
  "a": 1,
  "b": 2,
  "c": %*{
    "a": 1,
    "b": 2,
  },
  "d.a": 1,
  "d.b": 2,
  "d.c.a": 1,
  "d.c.b": %*{
    "a": 1,
    "b.a": 2,
  },
})

var layer2 = ConfigStore.new(layer1, "layer2", %*{
  "a": 2,
  "c": %*{
    "c": 3,
  },
  "+d": %*{
    "a": 2
  }
})

# var layer3 = ConfigStore.new(layer2, "layer3", %*{
# })

echo "================== layer 1 ===================="
echo layer1
