#!/usr/bin/bash
ffmpeg -y -framerate 20 -i ./screenshots/video/$1%d.png -vf "palettegen" ./screenshots/palette.png
ffmpeg -y -framerate 20 -i ./screenshots/video/$1%d.png -i ./screenshots/palette.png -lavfi "paletteuse" $2
rm ./screenshots/video/$1*.png
