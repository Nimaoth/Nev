#!/bin/bash
cloc --by-file --include-lang=Nim --exclude-list-file=tools/cloc-exclude-list-file.txt --exclude-dir=nimcache,fonts,temp,int,themes .
