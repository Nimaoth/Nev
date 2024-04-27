#!/bin/bash
cloc --by-file --include-lang=Nim --exclude-list-file=cloc-exclude-list-file.txt --exclude-dir=nimcache,fonts,temp,int,themes .
