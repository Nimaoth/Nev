console.log("scripting_runtime.js")

var lambdaActions = {}

function addCommand(context, keys, action, ...args) {
    let argsString = args.map(a => JSON.stringify(a)).join(" ")
    // console.log("addCommand", context, "    ", keys, "    ", action)
    gEditor.addCommandScript(context, keys, action, argsString)
}

function setHandleInputs(context, handleInputs) {
    // console.log("addCommand", context, "    ", keys, "    ", action)
    gEditor.setHandleInputs(context, handleInputs)
}

function addCommandLambda(context, keys, lambda) {
    let key = context + keys
    lambdaActions[key] = lambda
    gEditor.addCommandScript(context, keys, "lambda-action", JSON.stringify(key))
}

function handleLambdaAction(action, args) {
    if (action == "lambda-action" && args.length == 1 && typeof(lambdaActions[args[0]]) == "function") {
        lambdaActions[args[0]]()
        return true
    }

    return false
}

function addTextCommand(mode, keys, action, ...args) {
    let context = "editor.text" + (mode.length == 0 ? "" : "." + mode)
    if (typeof(action) == "function") {
        addCommandLambda(context, keys, action)
    } else {
        addCommand(context, keys, action, ...args)
    }
}