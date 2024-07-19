const inDir {.strdefine.} = ""
const outDir {.strdefine.} = ""

echo "[copy_wasmtime_dll.nims] Copy dll from '", inDir, "' to '", outDir, "'"
cpFile inDir, outDir
