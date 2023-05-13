const ignore = require('ignore')
const express = require('express')
var bodyParser = require('body-parser')
const fs = require('fs')
const pth = require('path')
const cors = require('cors')

const app = express()
app.use(bodyParser.json({limit: "500mb"}))
app.use(bodyParser.text({limit: "500mb"}))
app.use(cors({
    origin: '*'
}));

let localFolderPath = process.cwd()
let localFolderName = pth.basename(localFolderPath)

let ig = ignore()
try {
    let files = fs.readFileSync(".gitignore").toString().split("\n").filter(s => s.length > 0)
    console.log("Ignore: ", files)
    ig.add(files)
} catch(e) {
    console.info("no .gitignore")
}

ig = ig.add(".git")

async function readDir(path) {
    let result = {
        files: [],
        folders: []
    }
    try {
        const files = await fs.promises.readdir(path)
        // console.log(files)
        for (_f of files) {
            const f = _f
            let file = pth.join(path, f)
            if (ig.ignores(file))
            {
                console.log(`ignoring '${file}'`)
                continue
            }

            // console.log(file)
            if ((await fs.promises.lstat(file)).isFile()) {
                result.files.push(f)
            } else {
                result.folders.push(f)
            }
        }
    } catch (e) {
        console.error(e)
    }

    return result
}

app.get('/list', async (req, res) => {
    console.log(`list files in '.'`)
    let result = await readDir(".")
    console.log(result)
    res.send(JSON.stringify(result))
})

app.get('/list/*', async (req, res) => {
    const path = req.path.substring("/list/".length)

    if (pth.isAbsolute(path) || path.includes("..")) {
        res.sendStatus(403)
        return;
    }

    console.log(`list files in '${path}'`)
    let result = await readDir(path)
    // console.log(result)
    res.send(JSON.stringify(result))
})

app.get('/contents/*', async (req, res) => {
    const path = req.path.substring("/contents/".length)

    if (pth.isAbsolute(path) || path.includes("..")) {
        res.sendStatus(403)
        return;
    }

    console.log(`get content of '${path}'`)
    try {
        let result = await fs.promises.readFile(path)
        res.send(result)
    } catch (e) {
        console.error(e)
        res.send("")
    }
})

app.post('/contents/*', async (req, res) => {
    const path = req.path.substring("/contents/".length)

    if (pth.isAbsolute(path) || path.includes("..")) {
        res.sendStatus(403)
        return;
    }

    console.log(`set content of '${path}'`)
    try {
        await fs.promises.writeFile(path, req.body)
        res.sendStatus(200)
    } catch (e) {
        console.error(e)
        res.sendStatus(403)
    }
})

app.get('/info/name', async (req, res) => {
    res.send(localFolderName)
})

app.listen(3000, () => console.log(`Serving ${localFolderPath} on port 3000`));
