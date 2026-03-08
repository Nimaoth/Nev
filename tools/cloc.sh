#!/bin/bash
cloc --by-file --include-lang=Nim --exclude-list-file=tools/cloc-exclude-list-file.txt --exclude-dir=nimcache,fonts,temp,int,themes,modules2,deps,native_plugins,languages,logs,generated,patches,plugin_api,tests,plugins,ast .
