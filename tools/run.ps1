param()

$exitCode = 123
while ($exitCode -eq 123) {
    Write-Host "Copy ast.exe to ast-temp.exe"
    &cp ast.exe ast-temp.exe
    Write-Host "Launch ast-temp.exe"
    $argString = $args -join " "
    if ($argString -eq "") {
        $process = Start-Process -FilePath "ast-temp.exe" -NoNewWindow -PassThru
    } else {
        $process = Start-Process -FilePath "ast-temp.exe" -NoNewWindow -PassThru -ArgumentList $argString
    }
    Wait-Process -Id $process.Id
    # For some reason $process.ExitCode returns nothing, but the reflection access works, BUT only if we use $process.ExitCode first???
    $exitCode = $process.ExitCode
    $exitCode = $process.GetType().GetField('exitCode', 'NonPublic, Instance').GetValue($process)
    Write-Host "Exited with code $exitCode"
}