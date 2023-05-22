const Parser = window.TreeSitter

let isEditorLoaded = false
function doLoadEditor() {
    if (isEditorLoaded)
        return
    isEditorLoaded = true

    jsLoadScript("ast.js")
}

var treeSitterInitialized = false
function doInitTreesitter() {
    try {
        return Parser.init().then(() => {
            treeSitterInitialized = true
            console.log("treesitter is ready")
            doLoadEditor()
        }, () => {
            alert("Couldn't initialize treesitter")
            console.error("Couldn't initialize treesitter")
            doLoadEditor()
        })
    } catch {
        alert("Couldn't initialize treesitter")
        console.error("Couldn't initialize treesitter")
        doLoadEditor()
    }
}

function loadAbsytree() {
    doInitTreesitter()
}

// Glue code needed by ast.js

function jsLoadScript(url) {
    return new Promise((resolve, reject) => {
        let script = document.createElement("script")
        script.setAttribute("src", url)
        script.onload = () => resolve(script)
        document.body.appendChild(script)
    })
}

function jsLoadScriptContent(content) {
    return new Promise((resolve, reject) => {
        let script = document.createElement("script")
        script.innerHTML = content
        script.onload = () => resolve(script)
        document.body.appendChild(script)
    })
}

function jsLoadFileSync(filePath) {
    var result = null;
    var xmlhttp = new XMLHttpRequest();
    xmlhttp.open("GET", filePath, false);
    xmlhttp.send();
    if (xmlhttp.status==200) {
        result = xmlhttp.responseText;
    }
    return result || "";
}

async function jsLoadFileAsync(filePath) {
    const response = await fetch(filePath)
    const content = await response.text()
    return content
}

async function jsLoadFileBinaryAsync(filePath) {
    const response = await fetch(filePath)
    const content = await response.arrayBuffer()
    return content
}

function jsGetAsync(url, authToken) {
    return new Promise((resolve, reject) => {
        var result = null;
        var xmlhttp = new XMLHttpRequest();
        xmlhttp.open("GET", url, true);
        if (authToken !== undefined) xmlhttp.setRequestHeader("Authorization", authToken)
        xmlhttp.onload = () => {
            resolve(xmlhttp.responseText || "")
        }
        xmlhttp.onerror = () => {
            reject("jsGetAsync: failed to load url " + url)
        }
        xmlhttp.send();
    })
}

function jsPostAsync(url, content, authToken) {
    return new Promise((resolve, reject) => {
        var result = null;
        var xmlhttp = new XMLHttpRequest();
        xmlhttp.open("POST", url, true);
        xmlhttp.setRequestHeader("Authorization", authToken)
        xmlhttp.setRequestHeader("Content-Type", "text/plain")
        xmlhttp.onload = () => {
            resolve(xmlhttp.responseText || "")
        }
        xmlhttp.onerror = () => {
            reject("jsPostAsync: failed to load url " + url)
        }
        xmlhttp.send(content)
    })
}

function jsPostBinaryAsync(url, content, authToken) {
    return new Promise((resolve, reject) => {
        var result = null;
        var xmlhttp = new XMLHttpRequest();
        xmlhttp.open("POST", url, true);
        xmlhttp.setRequestHeader("Authorization", authToken)
        xmlhttp.setRequestHeader("Content-Type", "application/octet-stream")
        // console.log("postBinaryAsync:", new Uint8Array(content))
        xmlhttp.onload = () => {
            resolve(xmlhttp.responseText || "")
        }
        xmlhttp.onerror = () => {
            reject("jsPostBinaryAsync: failed to load url " + url)
        }
        xmlhttp.send(content)
    })
}

function jsLoadTreesitterLanguage(path) {
    return new Promise((resolve, reject) => {
        Parser.Language.load(path).then(resolve, () => resolve(null))
    })
}

const encoder = new TextEncoder()
const decoder = new TextDecoder()
function jsEncodeString(str) {
    return encoder.encode(str)
}
function jsDecodeString(str) {
    return decoder.decode(str)
}

// These are prototype objects which are filled with wrapper functions for the respective
// nim types (Editor, TextDocumentEditor, ...) when loading ast.js
var editor_prototype = {}
var editor_ast_prototype = {}
var editor_model_prototype = {}
var editor_text_prototype = {}
var popup_selector_prototype = {}

// This function is used when instantiating (Editor, TextDocumentEditor, ...)
function jsCreateWithPrototype(prototype, template) {
    var result = Object.create(prototype)
    for (const k of Object.keys(template)) {
        result[k] = template[k]
    }
    return result
}

function orDefaultJs(value, d) {
    return value === undefined ? d : value;
}

async function jsLoadWasmModuleAsync(path, importObject) {
    console.log("Loading wasm module ", path, " with imports ", importObject)
    const module = await WebAssembly.instantiateStreaming(fetch(path), importObject)
    let mem = module.instance.exports['memory']
    return module.instance
}

async function jsLoadWasmModuleSync(wasmData, importObject) {
    console.log("Loading wasm module ", wasmData, " with imports ", importObject)
    let module = await WebAssembly.instantiate(wasmData, importObject)
    console.log(module)
    let mem = module.instance.exports['memory']
    return module.instance
}

// WASI

var out = console.log.bind(console);
var err = console.warn.bind(console);

/**
 * Given a pointer 'idx' to a null-terminated UTF8-encoded string in the given
 * array that contains uint8 values, returns a copy of that string as a
 * Javascript String object.
 * heapOrArray is either a regular array, or a JavaScript typed array view.
 * @param {number} idx
 * @param {number=} maxBytesToRead
 * @return {string}
 */
function UTF8ArrayToString(heapOrArray, idx, maxBytesToRead) {
    var endIdx = idx + maxBytesToRead;
    var endPtr = idx;
    // TextDecoder needs to know the byte length in advance, it doesn't stop on
    // null terminator by itself.  Also, use the length info to avoid running tiny
    // strings through TextDecoder, since .subarray() allocates garbage.
    // (As a tiny code save trick, compare endPtr against endIdx using a negation,
    // so that undefined means Infinity)
    while (heapOrArray[endPtr] && !(endPtr >= endIdx)) ++endPtr;

    if (endPtr - idx > 16 && heapOrArray.buffer && UTF8Decoder) {
        return UTF8Decoder.decode(heapOrArray.subarray(idx, endPtr));
    }
    var str = '';
    // If building with TextDecoder, we have already computed the string length
    // above, so test loop end condition against that
    while (idx < endPtr) {
        // For UTF8 byte structure, see:
        // http://en.wikipedia.org/wiki/UTF-8#Description
        // https://www.ietf.org/rfc/rfc2279.txt
        // https://tools.ietf.org/html/rfc3629
        var u0 = heapOrArray[idx++];
        if (!(u0 & 0x80)) { str += String.fromCharCode(u0); continue; }
        var u1 = heapOrArray[idx++] & 63;
        if ((u0 & 0xE0) == 0xC0) { str += String.fromCharCode(((u0 & 31) << 6) | u1); continue; }
        var u2 = heapOrArray[idx++] & 63;
        if ((u0 & 0xF0) == 0xE0) {
        u0 = ((u0 & 15) << 12) | (u1 << 6) | u2;
        } else {
        if ((u0 & 0xF8) != 0xF0) warnOnce('Invalid UTF-8 leading byte ' + ptrToString(u0) + ' encountered when deserializing a UTF-8 string in wasm memory to a JS string!');
        u0 = ((u0 & 7) << 18) | (u1 << 12) | (u2 << 6) | (heapOrArray[idx++] & 63);
        }

        if (u0 < 0x10000) {
        str += String.fromCharCode(u0);
        } else {
        var ch = u0 - 0x10000;
        str += String.fromCharCode(0xD800 | (ch >> 10), 0xDC00 | (ch & 0x3FF));
        }
    }
    return str;
}


var printCharBuffers = [null,[],[]];
function printChar(stream, curr) {
    var buffer = printCharBuffers[stream];
    if (curr === 0 || curr === 10) {
        (stream === 1 ? out : err)(UTF8ArrayToString(buffer, 0));
        buffer.length = 0;
    } else {
        buffer.push(curr);
    }
}

function js_fd_write(context, fd, iov, iovcnt, pnum) {
    // hack to support printf in SYSCALLS_REQUIRE_FILESYSTEM=0
    var num = 0;
    for (var i = 0; i < iovcnt; i++) {
        var ptr = context.HEAPU32[((iov)>>2)];
        var len = context.HEAPU32[(((iov)+(4))>>2)];
        iov += 8;
        for (var j = 0; j < len; j++) {
        printChar(fd, context.HEAPU8[ptr+j]);
        }
        num += len;
    }
    context.HEAPU32[((pnum)>>2)] = num;
    return 0;
}