param()

$exitCode = 123
while ($exitCode -eq 123) {
    Write-Host "Copy nev.exe to nev-temp.exe"
    &cp nev.exe nev-temp.exe
    $argString = $args -join " "
    # $argString = "-p:editor.prompt-before-quit=true -p:editor.watch-app-config=false -p:editor.watch-user-config=false -p:editor.watch-workspace-config=false $argString"
    $argString = "-p:editor.prompt-before-quit=true -p:editor.watch-app-config=true -p:editor.watch-user-config=false -p:editor.watch-workspace-config=false $argString"
    Write-Host "Launch nev-temp.exe $argString"
    if ($argString -eq "") {
        $process = Start-Process -FilePath "nev-temp.exe" -NoNewWindow -PassThru
    } else {
        $process = Start-Process -FilePath "nev-temp.exe" -NoNewWindow -PassThru -ArgumentList $argString
    }
    Wait-Process -Id $process.Id
    # For some reason $process.ExitCode returns nothing, but the reflection access works, BUT only if we use $process.ExitCode first???
    $exitCode = $process.ExitCode
    $exitCode = $process.GetType().GetField('exitCode', 'NonPublic, Instance').GetValue($process)
    Write-Host "Exited with code $exitCode"
}