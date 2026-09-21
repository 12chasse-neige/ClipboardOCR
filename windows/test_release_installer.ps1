param([Parameter(Mandatory=$true)][string]$Installer)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$scratch = Join-Path $root ('build\package-check-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $scratch | Out-Null
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8CA1D626-F6A6-4B7B-81F7-17886B7C43D1}_is1'
$nativeKey = 'HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8CA1D626-F6A6-4B7B-81F7-17886B7C43D1}_is1'
$backup = Join-Path $scratch 'registration.reg'
$hadKey = Test-Path -LiteralPath $key
if ($hadKey) {
    & reg.exe export $nativeKey $backup /y | Out-Null
    if ($LASTEXITCODE) { throw 'Cannot back up app registration.' }
}
try {
    $target = Join-Path $scratch 'app'
    $process = Start-Process -FilePath ([IO.Path]::GetFullPath($Installer)) -WindowStyle Hidden -Wait -PassThru `
        -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/NOICONS', '/NOCLOSEAPPLICATIONS', "/DIR=`"$target`"")
    if ($process.ExitCode -ne 0) { throw "Installer exit code: $($process.ExitCode)" }
    foreach ($file in @('windows\setup.ps1', 'windows\setup_helpers.ps1', 'windows\download_models.py', 'windows\download_paddle.py', 'windows\verify_setup.py', 'backend\engine_windows.py', 'README.md', 'WINDOWS.md')) {
        $actual = (Get-FileHash -LiteralPath (Join-Path $target $file) -Algorithm SHA256).Hash
        $expected = (Get-FileHash -LiteralPath (Join-Path $root $file) -Algorithm SHA256).Hash
        if ($actual -ne $expected) { throw "Packaged file differs from source: $file" }
    }
    $version = (Get-ItemProperty -LiteralPath $key).DisplayVersion
    if ($version -ne '0.2.0-preview.14') { throw "Wrong installed version: $version" }
    Write-Host "PASS: real installer exit 0, version $version, all changed packaged files match source"
    $python = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\runtime\Scripts\python.exe'
    $env:PYTHONIOENCODING = 'utf-8'
    & $python (Join-Path $target 'windows\verify_setup.py')
    if ($LASTEXITCODE) { throw 'Installed package GPU OCR check failed.' }
    Write-Host 'PASS: installed package real GPU OCR'
} finally {
    if ($hadKey) {
        & reg.exe import $backup | Out-Null
        if ($LASTEXITCODE) { throw "Restore registration from $backup" }
    } elseif (Test-Path -LiteralPath $key) {
        # Only remove the exact registration written by this test installation.
        $installedPath = (Get-ItemProperty -LiteralPath $key).InstallLocation
        if ($installedPath.TrimEnd('\') -ne $target.TrimEnd('\')) { throw 'Unexpected app registration; leaving it untouched.' }
        Remove-Item -LiteralPath $key -Recurse -Force
    }
    Write-Host "Test files kept for inspection: $scratch"
}
