# Package

version       = "0.1.0"
author        = "Nimaoth"
description   = "Programming language + editor"
license       = "MIT"
srcDir        = "src"
bin           = @["ast"]


# Dependencies

requires "nim >= 1.6.4"
requires "boxy >= 0.4.0"
requires "windy >= 0.0.0"
requires "winim >= 3.8.1"
requires "fusion >= 1.1"
requires "print >= 1.0.2"