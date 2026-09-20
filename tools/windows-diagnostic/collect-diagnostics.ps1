$ErrorActionPreference = 'Continue'
$packageRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$reportRoot = Join-Path $packageRoot "ClipboardOCR-diagnostic-$stamp"
$reportDir = Join-Path $reportRoot 'report'
New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
$lines = [System.Collections.Generic.List[string]]::new()
function Add-Line([string]$text = '') { [void]$lines.Add($text) }
function Save-Text([string]$name, [string]$text) { $text | Set-Content -LiteralPath (Join-Path $reportDir $name) -Encoding UTF8 }
function Redact([string]$text) {
    if ($null -eq $text) { return '' }
    return [regex]::Replace($text, '(?i)(--api-key\s+)\S+', '$1<redacted>')
}

Add-Line 'Clipboard OCR Windows diagnostic'
Add-Line "Collected: $(Get-Date -Format o)"
Add-Line "Computer: $env:COMPUTERNAME"
Add-Line "User: $env:USERNAME"
Add-Line "OS: $([Environment]::OSVersion.VersionString)"
Add-Line "PowerShell: $($PSVersionTable.PSVersion)"
Add-Line "LOCALAPPDATA: $env:LOCALAPPDATA"
Add-Line ''

$shortcutText = [System.Collections.Generic.List[string]]::new()
$roots = [System.Collections.Generic.List[string]]::new()
$shell = New-Object -ComObject WScript.Shell
$shortcutPaths = @(
    (Join-Path ([Environment]::GetFolderPath('Desktop')) 'Clipboard OCR.lnk'),
    (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\Clipboard OCR.lnk')
)
foreach ($shortcutPath in $shortcutPaths) {
    if (-not (Test-Path -LiteralPath $shortcutPath)) { continue }
    try {
        $link = $shell.CreateShortcut($shortcutPath)
        [void]$shortcutText.Add("[$shortcutPath]")
        [void]$shortcutText.Add("TargetPath=$($link.TargetPath)")
        [void]$shortcutText.Add("Arguments=$($link.Arguments)")
        [void]$shortcutText.Add("WorkingDirectory=$($link.WorkingDirectory)")
        [void]$shortcutText.Add("WindowStyle=$($link.WindowStyle)")
        [void]$shortcutText.Add('')
        if ($link.Arguments -match '"([^"]*launch\.py)"') {
            [void]$roots.Add((Split-Path -Parent (Split-Path -Parent $matches[1])))
        }
    } catch { [void]$shortcutText.Add("ERROR=$($_.Exception.Message)") }
}
Save-Text 'shortcuts.txt' ($shortcutText -join "`r`n")

[void]$roots.Add((Join-Path $env:LOCALAPPDATA 'Programs\ClipboardOCR'))
$uniqueRoots = $roots | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -Unique
Add-Line 'Shortcut and installation roots:'
if (-not $uniqueRoots) { Add-Line '  NONE FOUND' }
foreach ($root in $uniqueRoots) {
    Add-Line "  ROOT: $root"
    $managedPythonRoot = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\python'
    Add-Line "    Managed Python root: $managedPythonRoot"
    $dataRoot = Join-Path $env:LOCALAPPDATA 'ClipboardOCR'
    $expected = @(
        'windows\app.py', 'windows\launch.py', 'windows\setup.ps1',
        (Join-Path $dataRoot 'runtime\Scripts\python.exe'),
        (Join-Path $dataRoot 'models\PaddleOCR-VL-1.6-GGUF\PaddleOCR-VL-1.6-GGUF.gguf'),
        (Join-Path $dataRoot 'models\PaddleOCR-VL-1.6-GGUF\PaddleOCR-VL-1.6-GGUF-mmproj.gguf')
    )
    foreach ($relative in $expected) {
        $path = if ([IO.Path]::IsPathRooted($relative)) { $relative } else { Join-Path $root $relative }
        if (Test-Path -LiteralPath $path) {
            $item = Get-Item -LiteralPath $path
            if ($item.PSIsContainer) {
                $size = (Get-ChildItem -LiteralPath $path -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                Add-Line "    PASS $path (directory, $([math]::Round($size/1MB,2)) MiB)"
            } else { Add-Line "    PASS $path ($([math]::Round($item.Length/1MB,2)) MiB)" }
        } else { Add-Line "    MISSING $path" }
    }
    $managedPython = Get-ChildItem -LiteralPath $managedPythonRoot -Filter pythonw.exe -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($managedPython) {
        Add-Line "    PASS managed Python $($managedPython.FullName) ($([math]::Round($managedPython.Length/1MB,2)) MiB)"
    } else {
        Add-Line "    MISSING managed Python under $managedPythonRoot"
    }
    $layout = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\paddlex\official_models\PP-DocLayoutV3'
    if (Test-Path -LiteralPath $layout) {
        $size = (Get-ChildItem -LiteralPath $layout -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        Add-Line "    PASS layout cache $layout ($([math]::Round($size/1MB,2)) MiB)"
    } else { Add-Line "    MISSING layout cache $layout" }
    $runtimePython = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\runtime\Scripts\python.exe'
    if (Test-Path -LiteralPath $runtimePython) {
        & $runtimePython -c "import sys; print('python=' + sys.executable); print('version=' + sys.version.replace(chr(10),' ')); import paddle; print('paddle=' + getattr(paddle,'__version__','unknown')); print('cuda_compiled=' + str(paddle.is_compiled_with_cuda())); print('cuda_devices=' + str(paddle.device.cuda.device_count()))" 2>&1 | Set-Content -LiteralPath (Join-Path $reportDir 'runtime-import.txt') -Encoding UTF8
        break
    }
}

try { & nvidia-smi.exe -L 2>&1 | Set-Content -LiteralPath (Join-Path $reportDir 'nvidia-smi-L.txt') -Encoding UTF8 } catch { Save-Text 'nvidia-smi-L.txt' $_.Exception.Message }
try { & nvidia-smi.exe --query-gpu=name,driver_version,memory.total,compute_cap --format=csv,noheader 2>&1 | Set-Content -LiteralPath (Join-Path $reportDir 'nvidia-smi-query.txt') -Encoding UTF8 } catch { Save-Text 'nvidia-smi-query.txt' $_.Exception.Message }
try { Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion,AdapterRAM,VideoModeDescription | Format-List | Out-String | Set-Content -LiteralPath (Join-Path $reportDir 'video-controller.txt') -Encoding UTF8 } catch { }

$llama = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter llama-server.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
if ($llama) { & $llama.FullName --version 2>&1 | Set-Content -LiteralPath (Join-Path $reportDir 'llama-version.txt') -Encoding UTF8 }

$processes = Get-CimInstance Win32_Process | Where-Object { $_.CommandLine -and $_.CommandLine -match 'ClipboardOCR|Clipboard OCR' } | ForEach-Object {
    "PID=$($_.ProcessId) Parent=$($_.ParentProcessId) Name=$($_.Name) CommandLine=$(Redact $_.CommandLine)"
}
Save-Text 'processes.txt' ($processes -join "`r`n")

$log = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\logs\app.log'
if (Test-Path -LiteralPath $log) {
    Get-Content -LiteralPath $log -Tail 150 | ForEach-Object { $_ -replace [regex]::Escape($env:USERNAME), '<user>' } | Set-Content -LiteralPath (Join-Path $reportDir 'app.log.tail.txt') -Encoding UTF8
}
$setupLog = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\logs\setup.log'
if (Test-Path -LiteralPath $setupLog) {
    Get-Content -LiteralPath $setupLog -Tail 250 | ForEach-Object { $_ -replace [regex]::Escape($env:USERNAME), '<user>' } | Set-Content -LiteralPath (Join-Path $reportDir 'setup.log.tail.txt') -Encoding UTF8
}

$lines | Set-Content -LiteralPath (Join-Path $reportDir 'summary.txt') -Encoding UTF8
$zip = Join-Path $packageRoot "ClipboardOCR-diagnostic-$stamp.zip"
Compress-Archive -LiteralPath $reportRoot -DestinationPath $zip -Force
Remove-Item -LiteralPath $reportRoot -Recurse -Force
Write-Host "Diagnostic archive: $zip"
