<#
.SYNOPSIS
  Runs nev's terminal UI headlessly and writes per-frame captures for debugging layout.

.DESCRIPTION
  Starts `nev -t` with stdout/stdin redirected, NEV_TERMINAL_SIZE set to -Size and
  NEV_TERMINAL_DEBUG_DIR set to -Dir. Every rendered frame writes into -Dir:
    screen.txt   character grid with row/column rulers
    colors.txt   background/foreground color maps with legends
    screen.html  colored rendering (open in a browser / screenshot)
    layout.txt   node tree with absolute rects, flags, padding, border, gap, text
    frame.txt    frame counter, written last
  Bytes written to <Dir>\input are consumed as terminal input on the next poll.

  -Keys entries are sent one after another; each waits for a new frame. Escapes:
  \e = ESC, \r = Enter, \t = Tab, \n = LF, \\ = backslash.

.EXAMPLE
  ./tools/terminal_capture.ps1 -Size 100x30 -Keys '\e', ':' -KeepRunning
#>
param(
  [string]$Dir = (Join-Path $env:TEMP "nev-terminal-capture"),
  [string]$Size = "120x40",
  [string[]]$Keys = @(),
  [int]$StartupMs = 8000,
  [int]$FrameTimeoutMs = 3000,
  [string]$Exe = (Join-Path $PSScriptRoot "..\nev.exe"),
  [string[]]$NevArgs = @(),
  [switch]$KeepRunning
)

$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $Dir | Out-Null
Remove-Item (Join-Path $Dir "*") -Force -ErrorAction SilentlyContinue
$stdin = Join-Path $Dir "stdin.empty"
Set-Content -Path $stdin -Value "" -NoNewline

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

function Convert-Keys([string]$keys) {
  $sb = New-Object System.Text.StringBuilder
  for ($i = 0; $i -lt $keys.Length; $i++) {
    $c = $keys[$i]
    if ($c -eq '\' -and $i + 1 -lt $keys.Length) {
      $i++
      switch -CaseSensitive ($keys[$i]) {
        'e' { [void]$sb.Append([char]27) }
        'r' { [void]$sb.Append([char]13) }
        'n' { [void]$sb.Append([char]10) }
        't' { [void]$sb.Append([char]9) }
        default { [void]$sb.Append($keys[$i]) }
      }
    } else {
      [void]$sb.Append($c)
    }
  }
  $sb.ToString()
}

$env:NEV_TERMINAL_DEBUG_DIR = $Dir
$env:NEV_TERMINAL_SIZE = $Size
$argList = @("-t") + $NevArgs
$process = Start-Process -FilePath (Resolve-Path $Exe) -ArgumentList $argList `
  -WorkingDirectory (Split-Path (Resolve-Path $Exe)) `
  -RedirectStandardOutput (Join-Path $Dir "stdout.ansi") `
  -RedirectStandardError (Join-Path $Dir "stderr.txt") `
  -RedirectStandardInput $stdin -WindowStyle Hidden -PassThru

if (-not (Wait-NewFrame 0 $StartupMs)) { Write-Warning "No frame rendered within $StartupMs ms" }
# Let startup work (sessions, LSPs, git) settle before sending input.
Start-Sleep -Milliseconds 1500

foreach ($key in $Keys) {
  $before = Get-Frame
  [IO.File]::WriteAllText((Join-Path $Dir "input"), (Convert-Keys $key))
  if (-not (Wait-NewFrame $before $FrameTimeoutMs)) { Write-Warning "No new frame after input '$key'" }
  Start-Sleep -Milliseconds 300
}

Write-Output "pid=$($process.Id) frame=$(Get-Frame) dir=$Dir"
if (-not $KeepRunning) {
  Stop-Process -Id $process.Id -ErrorAction SilentlyContinue
}
