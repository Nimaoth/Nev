<#
.SYNOPSIS
  Runs nev's SDL UI and writes per-frame captures for debugging layout.

.DESCRIPTION
  Starts `nev -g` with NEV_SDL_WINDOW_SIZE set to -Size and NEV_SDL_DEBUG_DIR set
  to -Dir. Every rendered frame writes into -Dir:
    screen.png   the rendered UI
    layout.txt   node tree with absolute rects, flags, padding, border, gap, text
    frame.txt    frame counter, written last
  Lines written to <Dir>\commands are executed as nev commands on the next frame,
  results are appended to <Dir>\commands.log.

  -Commands entries are executed one after another; each waits for a new frame.
  Use `input-keys "<keys>"` to send key input, e.g. 'input-keys ":"', or
  `sdl.screenshot "<path>"` / `sdl.start-recording "<dir>" <seconds>` for extra captures.

.EXAMPLE
  ./tools/sdl_capture.ps1 -Size 1280x720 -Commands 'input-keys "<ESCAPE>:"' -KeepRunning
#>
param(
  [string]$Dir = (Join-Path $env:TEMP "nev-sdl-capture"),
  [string]$Size = "1280x720",
  [string[]]$Commands = @(),
  [int]$StartupMs = 10000,
  [int]$FrameTimeoutMs = 3000,
  [string]$Exe = (Join-Path $PSScriptRoot "..\nev.exe"),
  [string[]]$NevArgs = @(),
  [switch]$KeepRunning
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $Dir | Out-Null
Remove-Item (Join-Path $Dir "*") -Recurse -Force -ErrorAction SilentlyContinue

function Get-Frame {
  $path = Join-Path $Dir "frame.txt"
  if (Test-Path $path) { return [int](Get-Content $path -Raw) }
  return 0
}

function Wait-NewFrame([int]$after, [int]$timeoutMs) {
  $sw = [Diagnostics.Stopwatch]::StartNew()
  while ($sw.ElapsedMilliseconds -lt $timeoutMs) {
    try { if ((Get-Frame) -gt $after) { return $true } } catch {}
    Start-Sleep -Milliseconds 100
  }
  return $false
}

$env:NEV_SDL_DEBUG_DIR = $Dir
$env:NEV_SDL_WINDOW_SIZE = $Size
$argList = @("-g") + $NevArgs
$process = Start-Process -FilePath (Resolve-Path $Exe) -ArgumentList $argList `
  -WorkingDirectory (Split-Path (Resolve-Path $Exe)) -PassThru

if (-not (Wait-NewFrame 0 $StartupMs)) { Write-Warning "No frame rendered within $StartupMs ms" }
# Let startup work (sessions, LSPs, git) settle before sending commands.
Start-Sleep -Milliseconds 1500

foreach ($command in $Commands) {
  $before = Get-Frame
  [IO.File]::WriteAllText((Join-Path $Dir "commands"), $command)
  if (-not (Wait-NewFrame $before $FrameTimeoutMs)) { Write-Warning "No new frame after command '$command'" }
  Start-Sleep -Milliseconds 300
}

# Encoding runs on background threads; wait for the latest frame's files.
Start-Sleep -Milliseconds 500
Write-Output "pid=$($process.Id) frame=$(Get-Frame) dir=$Dir"
if (-not $KeepRunning) {
  Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
}
