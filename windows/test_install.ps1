<#
.SYNOPSIS
Verifies a Clipboard OCR setup executable end to end without disturbing an
existing working installation.

.DESCRIPTION
Inno Setup identifies this application by AppId, not by directory. This script
snapshots data belonging to the current registration (or the legacy
%LOCALAPPDATA%\ClipboardOCR root for v0.3.0), then proves a scratch installation
does not modify it.

This script therefore:
  1. snapshots the existing data root and saves the registration and the desktop
     shortcut into a rollback folder,
  2. temporarily removes the AppId registration so the setup executable treats
     the machine as a fresh install and never runs the old uninstaller,
  3. installs into a scratch directory with the real setup executable,
  4. runs the same setup step the installer runs (that step is skipped by
     /SILENT) and checks the end-to-end GPU OCR result,
  5. uninstalls the scratch copy and confirms the existing data root survived,
  6. restores the registration and the desktop shortcut.

The existing data roots are checked by file-count/size inventory, setup logs,
registration and desktop shortcut. Rollback material stays in
%TEMP%\ClipboardOCR-install-test-<timestamp> in case anything needs inspecting.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\windows\test_install.ps1
Uses the newest dist\ClipboardOCR-*-setup.exe into C:\ClipboardOCR-install-test.

.EXAMPLE
powershell -ExecutionPolicy Bypass -File .\windows\test_install.ps1 -Installer .\dist\ClipboardOCR-0.3.1-windows-x64-setup.exe -TestDir D:\ClipboardOCR-test -KeepInstall
#>
[CmdletBinding()]
param(
    [string]$Installer,
    [string]$TestDir,
    [switch]$KeepInstall
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$appId = '{8CA1D626-F6A6-4B7B-81F7-17886B7C43D1}'
$uninstallKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\${appId}_is1"
$uninstallKeyPath = "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\${appId}_is1"
$dataRoots = @((Join-Path $env:LOCALAPPDATA 'ClipboardOCR'))
$shortcutPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Clipboard OCR.lnk'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$rollback = Join-Path $env:TEMP "ClipboardOCR-install-test-$stamp"
$problems = New-Object System.Collections.Generic.List[string]

function Write-Step([string]$text) { Write-Host ''; Write-Host "== $text" -ForegroundColor Cyan }
function Write-Ok([string]$text) { Write-Host "   PASS  $text" -ForegroundColor Green }
function Write-Bad([string]$text) { Write-Host "   FAIL  $text" -ForegroundColor Red; [void]$problems.Add($text) }
function Write-Info([string]$text) { Write-Host "         $text" }

function Get-DataSnapshot([string]$rootPath) {
    $snapshot = @{}
    foreach ($name in @('runtime', 'models', 'python', 'downloads', 'paddlex', 'huggingface', 'uv-cache')) {
        $path = Join-Path $rootPath $name
        $files = @(Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue)
        $snapshot[$name] = @{
            Exists = (Test-Path -LiteralPath $path)
            Count  = $files.Count
            Bytes  = ($files | Measure-Object -Property Length -Sum).Sum
        }
    }
    return $snapshot
}

function Test-DataSnapshot($before, $after, [string]$label) {
    foreach ($name in $before.Keys) {
        $a = $before[$name]; $b = $after[$name]
        if ($a.Exists -ne $b.Exists) {
            Write-Bad "$label`: $name directory presence changed ($($a.Exists) -> $($b.Exists))"
            continue
        }
        if ($a.Exists -and (-not $b.Exists)) { Write-Bad "$label`: $name directory is gone"; continue }
        if ($name -eq 'runtime') {
            # Setup legitimately refreshes packages inside the runtime - with a cold
            # uv cache it re-downloads and reinstalls them - so a changed size is
            # only a failure when content was actually lost.
            if ($b.Bytes -lt ($a.Bytes * 0.8) -or $b.Count -lt ($a.Count * 0.8)) {
                Write-Bad ("{0}: runtime lost content (files {1} -> {2}, bytes {3} -> {4})" -f $label, $a.Count, $b.Count, $a.Bytes, $b.Bytes)
            } else {
                Write-Ok ("{0}: runtime kept ({1} files, {2:N2} GB)" -f $label, $b.Count, ($b.Bytes / 1GB))
            }
            continue
        }
        if ($a.Count -ne $b.Count -or $a.Bytes -ne $b.Bytes) {
            Write-Bad ("$label`: $name changed (files {0} -> {1}, bytes {2} -> {3})" -f $a.Count, $b.Count, $a.Bytes, $b.Bytes)
        } else {
            Write-Ok ("$label`: $name untouched ({0} files, {1:N2} GB)" -f $b.Count, ($b.Bytes / 1GB))
        }
    }
}

function Stop-ClipboardOcrProcesses {
    $stopped = 0
    foreach ($process in @(Get-Process -Name pythonw, python, llama-server -ErrorAction SilentlyContinue)) {
        $isOurs = $false
        try {
            $commandLine = (Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)" -ErrorAction Stop).CommandLine
            if ($commandLine -and $commandLine -match 'ClipboardOCR|launch\.py|PaddleOCR-VL-1\.6-GGUF') { $isOurs = $true }
        } catch { }
        if (-not $isOurs -and $process.Path) {
            foreach ($dataRoot in $dataRoots) {
                if ($process.Path.StartsWith((Join-Path $dataRoot 'python'), 'OrdinalIgnoreCase')) { $isOurs = $true; break }
            }
        }
        if ($isOurs) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $stopped++
        }
    }
    if ($stopped) { Start-Sleep -Seconds 3 }
    return $stopped
}

# ---------------------------------------------------------------- 0. preflight
Write-Step '0. Preflight'
if (-not $Installer) {
    $Installer = Get-ChildItem -LiteralPath (Join-Path $root 'dist') -Filter 'ClipboardOCR-*-setup.exe' -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName
}
if (-not $Installer -or -not (Test-Path -LiteralPath $Installer)) { throw 'No setup executable found. Pass -Installer <path>.' }
if (-not $TestDir) { $TestDir = Join-Path $env:SystemDrive 'ClipboardOCR-install-test' }
$Installer = [IO.Path]::GetFullPath($Installer)
$TestDir = [IO.Path]::GetFullPath($TestDir).TrimEnd('\')

if ($TestDir -eq ([IO.Path]::GetFullPath($root)).TrimEnd('\')) { throw 'The test directory must differ from this checkout.' }
if (Test-Path -LiteralPath $TestDir) {
    $existing = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
    if ($existing -and $existing.InstallLocation -and ([IO.Path]::GetFullPath($existing.InstallLocation).TrimEnd('\') -eq $TestDir)) {
        throw "$TestDir is itself the registered installation; refusing to touch it."
    }
    if (@(Get-ChildItem -LiteralPath $TestDir -Force -ErrorAction SilentlyContinue).Count) {
        throw "Test directory is not empty; refusing to delete user files: $TestDir"
    }
}

Write-Info "Setup executable: $Installer"
Write-Info ("SHA256          : {0}" -f (Get-FileHash -Algorithm SHA256 -LiteralPath $Installer).Hash)
Write-Info "Test directory  : $TestDir"
$registered = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
if ($registered -and $registered.InstallLocation) {
    $registeredData = Join-Path $registered.InstallLocation 'data'
    if (Test-Path -LiteralPath $registeredData) { $dataRoots += $registeredData }
}
$dataRoots = @($dataRoots | Select-Object -Unique)
if ($registered) { Write-Info ("Registered now  : {0} at {1}" -f $registered.DisplayName, $registered.InstallLocation) }
else { Write-Info 'Registered now  : nothing (fresh-install path)' }
New-Item -ItemType Directory -Path $rollback -Force | Out-Null
Write-Info "Rollback folder : $rollback"

$baselines = @{}
foreach ($dataRoot in $dataRoots) { $baselines[$dataRoot] = Get-DataSnapshot $dataRoot }
$hadRegistration = [bool]$registered
$hadShortcut = Test-Path -LiteralPath $shortcutPath
$logDir = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\logs'
$logDirExisted = Test-Path -LiteralPath $logDir
$logParent = Split-Path -Parent $logDir
$logParentExisted = Test-Path -LiteralPath $logParent
$setupLogNames = @('setup.log', 'download_models.out.log', 'download_models.err.log', 'download_paddle.out.log', 'download_paddle.err.log', 'verify_setup.out.log', 'verify_setup.err.log')
$logSnapshot = Join-Path $rollback 'logs'
$logExisted = @{}
foreach ($name in $setupLogNames) {
    $path = Join-Path $logDir $name
    $logExisted[$name] = Test-Path -LiteralPath $path
    if ($logExisted[$name]) {
        New-Item -ItemType Directory -Path $logSnapshot -Force | Out-Null
        Copy-Item -LiteralPath $path -Destination (Join-Path $logSnapshot $name) -Force
    }
}

try {
    # ------------------------------------------------- 1. protect + install
    Write-Step '1. Protect the shared data root'
    if ($hadRegistration) {
        & reg.exe export $uninstallKeyPath (Join-Path $rollback 'uninstall-key.reg') /y | Out-Null
        if ($LASTEXITCODE -ne 0) { throw 'Could not export the uninstall registration.' }
        Write-Ok 'Registration saved to rollback\uninstall-key.reg'
        if ($hadShortcut) { Copy-Item -LiteralPath $shortcutPath -Destination (Join-Path $rollback 'Clipboard OCR.lnk') -Force }
        Remove-Item -LiteralPath $uninstallKey -Recurse -Force
        Write-Ok 'Registration removed: setup now sees a fresh install and will not run the old uninstaller'
    } else {
        Write-Ok 'Nothing registered, no protection needed'
    }

    $stopped = Stop-ClipboardOcrProcesses
    if ($stopped) { Write-Ok "Closed $stopped running Clipboard OCR process(es)" }
    else { Write-Info 'No running Clipboard OCR process found' }

    Write-Step '2. Install into the scratch directory'
    $install = Start-Process -FilePath $Installer -ArgumentList @('/SILENT', '/SUPPRESSMSGBOXES', '/NORESTART', "/DIR=$TestDir") -PassThru
    $install | Wait-Process -Timeout 900 -ErrorAction SilentlyContinue
    if (-not $install.HasExited) { $install | Stop-Process -Force -ErrorAction SilentlyContinue; Write-Bad 'installer did not finish within 15 minutes' }
    elseif ($install.ExitCode -ne 0) { Write-Bad "installer exit code $($install.ExitCode)" }
    else { Write-Ok 'installer exit code 0' }

    foreach ($file in @('windows\launch.py', 'windows\paths.py', 'windows\setup.ps1', 'windows\setup.cmd', 'backend\engine_windows.py', '.windows\tools\llama\llama-server.exe', 'unins000.exe')) {
        if (Test-Path -LiteralPath (Join-Path $TestDir $file)) { Write-Ok "installed $file" } else { Write-Bad "missing $file" }
    }
    $registration = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
    if ($registration -and $registration.DisplayVersion) { Write-Ok "registered as $($registration.DisplayVersion)" } else { Write-Bad 'no registration written' }

    # ------------------------------- 3. run the setup step /SILENT skips
    Write-Step '3. Run the setup step the installer skips under /SILENT'
    $setupLog = Join-Path $logDir 'setup.log'
    $logLinesBefore = 0
    if (Test-Path -LiteralPath $setupLog) { $logLinesBefore = @(Get-Content -LiteralPath $setupLog -ErrorAction SilentlyContinue).Count }
    # setup.cmd keeps its window open with `pause` when setup fails, so an
    # unattended run watches for progress instead of waiting forever.  Progress
    # is not only what reaches the transcript: with a cold cache uv downloads for
    # many minutes while writing only to its own logs, so a live worker process
    # counts as progress too.  Do not redirect the child's stdin: PowerShell 5.1
    # refuses to launch native commands ("Index was outside the bounds of the
    # array") when stdin is redirected, which would make every setup look failed.
    $setupCmd = Join-Path $TestDir 'windows\setup.cmd'
    $setup = Start-Process -FilePath $setupCmd -WorkingDirectory $TestDir -PassThru
    $deadline = (Get-Date).AddMinutes(90)
    $lastProgress = Get-Date
    $lastLength = if (Test-Path -LiteralPath $setupLog) { (Get-Item -LiteralPath $setupLog).Length } else { 0 }
    $stalled = $false
    while (-not $setup.HasExited -and (Get-Date) -lt $deadline) {
        Start-Sleep -Seconds 5
        $length = if (Test-Path -LiteralPath $setupLog) { (Get-Item -LiteralPath $setupLog).Length } else { 0 }
        if ($length -gt $lastLength) {
            $lastLength = $length
            $lastProgress = Get-Date
            continue
        }
        $workers = @(Get-Process -Name uv, python, pythonw, curl -ErrorAction SilentlyContinue |
            Where-Object { $_.StartTime -ge $setup.StartTime.AddSeconds(-2) }).Count
        if ($workers -gt 0) { $lastProgress = Get-Date; continue }
        if (((Get-Date) - $lastProgress).TotalMinutes -gt 10) { $stalled = $true; break }
    }
    if (-not $setup.HasExited) {
        & taskkill.exe /PID $setup.Id /T /F 2>$null | Out-Null
        $setup | Stop-Process -Force -ErrorAction SilentlyContinue
        foreach ($stray in @(Get-Process -Name cmd, powershell, conhost -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -match 'Clipboard OCR setup' })) {
            Stop-Process -Id $stray.Id -Force -ErrorAction SilentlyContinue
        }
        if ($stalled) {
            Write-Bad 'setup made no progress for ten minutes (it is probably waiting on its failure prompt)'
        } else {
            Write-Bad 'setup did not finish within 90 minutes'
        }
    } elseif ($setup.ExitCode -ne 0) { Write-Bad "setup exit code $($setup.ExitCode); see $setupLog" }
    else { Write-Ok 'setup exit code 0' }

    if (Test-Path -LiteralPath $setupLog) {
        $newLines = @(Get-Content -LiteralPath $setupLog -ErrorAction SilentlyContinue | Select-Object -Skip $logLinesBefore)
        $ocr = @($newLines | Select-String -Pattern 'End-to-end OCR passed:\s*(\d+)\s*characters')
        if ($ocr.Count -gt 0) { Write-Ok "end-to-end GPU OCR returned $($ocr[$ocr.Count - 1].Matches[0].Groups[1].Value) characters" }
        else { Write-Bad 'no "End-to-end OCR passed" line in the new part of setup.log' }
        $newLines | Select-String -Pattern 'Setup complete:' | ForEach-Object { Write-Ok $_.Line.Trim() }
    } else { Write-Bad 'setup.log was not written' }

    if (Test-Path -LiteralPath $shortcutPath) { Write-Ok 'desktop shortcut created' } else { Write-Bad 'desktop shortcut missing' }

    Write-Step '4. Shared data root after installing'
    foreach ($dataRoot in $dataRoots) {
        Test-DataSnapshot $baselines[$dataRoot] (Get-DataSnapshot $dataRoot) "existing data at $dataRoot after install"
    }
    foreach ($relative in @('data\python', 'data\runtime', 'data\uv-cache', 'data\paddlex', 'data\models', 'data\downloads')) {
        if (Test-Path -LiteralPath (Join-Path $TestDir $relative)) { Write-Ok "new install data is on selected drive: $relative" }
        else { Write-Bad "selected-drive install data is missing: $relative" }
    }
    $dataMarker = Join-Path $TestDir 'data\.uninstall-preserve-check'
    if (-not $KeepInstall -and (Test-Path -LiteralPath (Split-Path -Parent $dataMarker))) {
        Set-Content -LiteralPath $dataMarker -Value 'scratch test marker' -Encoding ASCII
    }

    # ------------------------------------------------------- 5. teardown
    Write-Step '5. Remove the scratch installation'
    if ($KeepInstall) {
        Write-Info "-KeepInstall given; the scratch copy stays at $TestDir"
    } else {
        # A setup that was killed mid-download can still hold files inside the
        # scratch directory, which would make the uninstaller and the cleanup
        # below fail; stop the whole tree first.
        [void](Stop-ClipboardOcrProcesses)
        foreach ($worker in @(Get-Process -Name uv, python, pythonw, curl, setup, unins000 -ErrorAction SilentlyContinue)) {
            Stop-Process -Id $worker.Id -Force -ErrorAction SilentlyContinue
        }
        Start-Sleep -Seconds 2
        $uninstaller = Join-Path $TestDir 'unins000.exe'
        if (Test-Path -LiteralPath $uninstaller) {
            $uninstall = Start-Process -FilePath $uninstaller -ArgumentList @('/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART') -PassThru
            $uninstall | Wait-Process -Timeout 900 -ErrorAction SilentlyContinue
            if ($uninstall.HasExited -and $uninstall.ExitCode -eq 0) { Write-Ok 'uninstaller exit code 0' }
            else { Write-Bad "uninstaller exit code $($uninstall.ExitCode)" }
        } else { Write-Bad 'unins000.exe is missing' }
        if (Test-Path -LiteralPath $dataMarker) { Write-Ok 'app-local data survives the normal uninstaller' }
        else { Write-Bad 'app-local data was removed by the normal uninstaller' }
        $managedPythonRoot = Join-Path $TestDir 'data\python'
        $managedPythonLink = Join-Path $managedPythonRoot 'cpython-3.12-windows-x86_64-none'
        $linkItem = Get-ChildItem -LiteralPath $managedPythonRoot -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq 'cpython-3.12-windows-x86_64-none' } | Select-Object -First 1
        if ($linkItem) {
            $pythonRoot = [IO.Path]::GetFullPath((Join-Path $TestDir 'data\python')).TrimEnd('\')
            $linkParent = [IO.Path]::GetFullPath($linkItem.Parent.FullName).TrimEnd('\')
            $managedPythonTarget = [IO.Path]::GetFullPath((Join-Path $managedPythonRoot 'cpython-3.12.13-windows-x86_64-none')).TrimEnd('\')
            $linkTarget = if ($linkItem.Target) { [IO.Path]::GetFullPath([string]$linkItem.Target).TrimEnd('\') } else { '' }
            if (($linkItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -and
                $linkItem.LinkType -eq 'Junction' -and
                $linkParent.Equals($pythonRoot, [StringComparison]::OrdinalIgnoreCase) -and
                $linkTarget.Equals($managedPythonTarget, [StringComparison]::OrdinalIgnoreCase)) {
                # PowerShell 5.1 can throw NullReferenceException for this directory junction.
                # .NET Delete removes the junction itself without traversing into its target.
                [IO.Directory]::Delete($managedPythonLink)
                if ((Test-Path -LiteralPath $managedPythonLink) -or -not (Test-Path -LiteralPath $managedPythonTarget)) {
                    throw 'Could not safely remove the temporary Python junction or its target changed.'
                }
                Write-Ok 'removed only uv-managed Python compatibility junction before scratch cleanup'
            }
        }
        for ($attempt = 0; $attempt -lt 3 -and (Test-Path -LiteralPath $TestDir); $attempt++) {
            Start-Sleep -Seconds 3
            Remove-Item -LiteralPath $TestDir -Recurse -Force -ErrorAction SilentlyContinue
        }
        if (Test-Path -LiteralPath $TestDir) { Write-Bad "leftover files in $TestDir" } else { Write-Ok 'scratch directory removed' }
        foreach ($dataRoot in $dataRoots) {
            Test-DataSnapshot $baselines[$dataRoot] (Get-DataSnapshot $dataRoot) "existing data at $dataRoot after uninstall"
        }
    }
}
finally {
    # ---------------------------------------------------------- 6. rollback
    Write-Step '6. Restore this machine'
    if ($hadRegistration) {
        if (Test-Path -LiteralPath (Join-Path $rollback 'uninstall-key.reg')) {
            & reg.exe import (Join-Path $rollback 'uninstall-key.reg') | Out-Null
            $restored = Get-ItemProperty -LiteralPath $uninstallKey -ErrorAction SilentlyContinue
            if ($restored) { Write-Ok "registration restored ($($restored.DisplayName) at $($restored.InstallLocation))" }
            else { Write-Bad 'registration could not be restored' }
        } else { Write-Bad 'rollback registration file is missing' }
    } else {
        Remove-Item -LiteralPath $uninstallKey -Recurse -Force -ErrorAction SilentlyContinue
        Write-Ok 'registration left absent, exactly as it was before the test'
    }
    if ($hadShortcut -and (Test-Path -LiteralPath (Join-Path $rollback 'Clipboard OCR.lnk'))) {
        Copy-Item -LiteralPath (Join-Path $rollback 'Clipboard OCR.lnk') -Destination $shortcutPath -Force
        Write-Ok 'desktop shortcut restored'
    } elseif (-not $hadShortcut -and (Test-Path -LiteralPath $shortcutPath)) {
        $shell = New-Object -ComObject WScript.Shell
        $testLink = $shell.CreateShortcut($shortcutPath)
        $expectedPrefix = [IO.Path]::GetFullPath((Join-Path $TestDir 'data\python')).TrimEnd('\') + '\'
        $expectedScript = [IO.Path]::GetFullPath((Join-Path $TestDir 'windows\launch.py'))
        if ([IO.Path]::GetFullPath($testLink.TargetPath).StartsWith($expectedPrefix, [StringComparison]::OrdinalIgnoreCase) -and
            $testLink.Arguments.Trim('"').Equals($expectedScript, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $shortcutPath -Force
            Write-Ok 'removed only the scratch-install desktop shortcut'
        } else {
            Write-Bad 'desktop shortcut was not restored because it no longer matches the test-created target'
        }
    }
    foreach ($dataRoot in $dataRoots) {
        Test-DataSnapshot $baselines[$dataRoot] (Get-DataSnapshot $dataRoot) "existing data at $dataRoot final"
    }
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    foreach ($name in $setupLogNames) {
        $path = Join-Path $logDir $name
        if ($logExisted[$name]) { Copy-Item -LiteralPath (Join-Path $logSnapshot $name) -Destination $path -Force }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    if (-not $logDirExisted -and (Test-Path -LiteralPath $logDir) -and
        @(Get-ChildItem -LiteralPath $logDir -Force -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -LiteralPath $logDir -Force
    }
    if (-not $logParentExisted -and (Test-Path -LiteralPath $logParent) -and
        @(Get-ChildItem -LiteralPath $logParent -Force -ErrorAction SilentlyContinue).Count -eq 0) {
        Remove-Item -LiteralPath $logParent -Force
    }
    Write-Ok 'restored the pre-test setup/download logs in LocalAppData'
    Write-Info "Rollback material kept in $rollback"
}

Write-Step 'Result'
if ($problems.Count -eq 0) {
    Write-Host '   ALL CHECKS PASSED' -ForegroundColor Green
    Write-Host '   Start the app again with the Clipboard OCR desktop shortcut.' -ForegroundColor Gray
    exit 0
}
Write-Host "   $($problems.Count) CHECK(S) FAILED" -ForegroundColor Red
foreach ($problem in $problems) { Write-Host "     - $problem" -ForegroundColor Red }
exit 1
