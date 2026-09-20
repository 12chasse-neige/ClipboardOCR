$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path (Join-Path $logDir 'setup.log') -Append | Out-Null
trap {
    Write-Error $_
    try { Stop-Transcript | Out-Null } catch { }
    exit 1
}

# uv creates a minor-version link directory below UV_PYTHON_INSTALL_DIR.  A
# Steam/library volume can be reported by Windows as an untrusted mount point,
# which makes that link creation fail before dependencies are installed. Keep
# the managed interpreter, virtual environment and model files in the user's
# trusted local profile. The selected install directory only holds static app
# files and bundled tools, so a Steam/library mount cannot break uv inspection.
$dataRoot = Join-Path $env:LOCALAPPDATA 'ClipboardOCR'
$pythonRoot = Join-Path $dataRoot 'python'
$runtime = Join-Path $dataRoot 'runtime'
$python = Join-Path $runtime 'Scripts\python.exe'
$bundledUv = Join-Path $root '.windows\tools\uv.exe'
$uv = if (Test-Path -LiteralPath $bundledUv) { $bundledUv } else { (Get-Command uv -ErrorAction Stop).Source }
$env:UV_LINK_MODE = 'copy'

# Windows PowerShell 5.1 decodes native command output with the console code page
# and aborts with "Index was outside the bounds of the array" when a child process
# writes characters that code page cannot represent.  huggingface_hub and its Xet
# backend draw Unicode progress bars, and that crash killed setup right after the
# model download on a non-UTF-8 console.  The Python steps below therefore write
# straight to files that are read back with an explicit encoding, and the progress
# bars are switched off on top of that.
$env:PYTHONIOENCODING = 'utf-8'
$env:HF_HUB_DISABLE_PROGRESS_BARS = '1'
$env:TQDM_DISABLE = '1'

function Invoke-PythonStep([string]$name) {
    $stdout = Join-Path $logDir "$name.out.log"
    $stderr = Join-Path $logDir "$name.err.log"
    $process = Start-Process -FilePath $python `
        -ArgumentList @("`"$(Join-Path $PSScriptRoot "$name.py")`"") `
        -Wait -NoNewWindow -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    foreach ($file in @($stdout, $stderr)) {
        if ((Test-Path -LiteralPath $file) -and (Get-Item -LiteralPath $file).Length -gt 0) {
            Get-Content -LiteralPath $file -Encoding UTF8 | ForEach-Object { Write-Host $_ }
        }
    }
    return $process.ExitCode
}

if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    throw 'An NVIDIA GPU and current NVIDIA driver are required.'
}

$env:UV_PYTHON_INSTALL_DIR = $pythonRoot
New-Item -ItemType Directory -Path $pythonRoot -Force | Out-Null
Write-Host "Managed Python directory: $pythonRoot"
$uvInstallOutput = cmd.exe /d /c "`"$uv`" python install 3.12.13 2>&1"
$pythonInstallExit = $LASTEXITCODE
$basePython = (& $uv python find 3.12.13 --managed-python).Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $basePython)) {
    throw "Managed Python 3.12.13 was not installed (uv exit code $pythonInstallExit).`n$($uvInstallOutput -join "`n")"
}
$pythonRootPrefix = ([IO.Path]::GetFullPath($pythonRoot)).TrimEnd('\') + '\'
if (-not ([IO.Path]::GetFullPath($basePython)).StartsWith($pythonRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "uv selected a managed Python outside the expected directory: $basePython"
}
$basePythonw = Join-Path (Split-Path -Parent $basePython) 'pythonw.exe'
if (-not (Test-Path -LiteralPath $basePythonw)) { throw 'Managed GUI Python (pythonw.exe) is missing.' }
if ($pythonInstallExit -ne 0) {
    Write-Warning "uv reported exit code $pythonInstallExit after creating a usable managed Python; continuing with the verified interpreter."
}
# A previous interrupted or older run can leave a `uv venv` trampoline behind:
# its python.exe resolves a recorded base interpreter at start-up and dies with
# "uv trampoline failed to spawn Python child process" once that path is gone or
# the tree enforces Redirection Guard.  Treat an environment that cannot import
# at all as absent so the rebuild below repairs it instead of reusing it.
$runtimeReady = $false
if (Test-Path -LiteralPath $python) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    & $python -c "import sys" *> $null
    $runtimeReady = $LASTEXITCODE -eq 0
    $ErrorActionPreference = $previousPreference
    if (-not $runtimeReady) {
        Write-Warning 'The existing virtual environment cannot start; rebuilding it.'
        Remove-Item -LiteralPath $runtime -Recurse -Force -ErrorAction SilentlyContinue
    }
}
if (-not $runtimeReady) {
    # Build the environment with the standard library instead of `uv venv`.
    # uv writes a trampoline python.exe that resolves its base interpreter at
    # start-up through uv's junction layout (<pythonRoot>\cpython-3.12-windows-
    # x86_64-none -> cpython-3.12.13-...).  A process tree that runs with
    # Redirection Guard (EnforceRedirectionTrust, inherited by every child) may
    # not traverse a junction created by a non-elevated process, so uv fails with
    # ERROR_UNTRUSTED_MOUNT_POINT (os error 448) while creating the link
    # directory and again while inspecting the finished environment.  The
    # standard library creates a plain, relocatable environment with copied
    # executables, and `uv pip install` fills it normally even under that policy.
    & $basePython -m venv --without-pip $runtime
    if ($LASTEXITCODE -ne 0) { throw "python -m venv failed with exit code $LASTEXITCODE" }
}
& $uv pip install --python $python --index-url https://www.paddlepaddle.org.cn/packages/stable/cu126/ 'paddlepaddle-gpu==3.2.1'
if ($LASTEXITCODE -ne 0) { throw "PaddlePaddle GPU installation failed with exit code $LASTEXITCODE" }
& $uv pip install --python $python 'paddleocr[doc-parser]==3.7.0' 'PySide6==6.9.3' 'Pillow==12.1.0'
if ($LASTEXITCODE -ne 0) { throw "PaddleOCR/PySide6/Pillow installation failed with exit code $LASTEXITCODE" }
& $uv pip install --python $python 'nvidia-cudnn-cu12==9.9.0.52'
if ($LASTEXITCODE -ne 0) { throw "cuDNN installation failed with exit code $LASTEXITCODE" }
& $python -c "from PIL import Image; Image.open(r'$root\assets\AppIcon.png').save(r'$root\assets\AppIcon.ico', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])"
if ($LASTEXITCODE -ne 0) { throw "Icon preparation failed with exit code $LASTEXITCODE" }
$bundledLlama = Join-Path $root '.windows\tools\llama\llama-server.exe'
$wingetPackages = Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Packages'
$installedLlama = if (Test-Path -LiteralPath $wingetPackages) {
    Get-ChildItem -LiteralPath $wingetPackages -Filter llama-server.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
} else { $null }
if (-not (Test-Path -LiteralPath $bundledLlama) -and -not $installedLlama) {
    winget install --id ggml.llamacpp --version b11026 --exact --accept-package-agreements --accept-source-agreements --silent
    if ($LASTEXITCODE -ne 0) { throw "llama.cpp installation failed with exit code $LASTEXITCODE" }
}
$installedLlama = if (Test-Path -LiteralPath $wingetPackages) {
    Get-ChildItem -LiteralPath $wingetPackages -Filter llama-server.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
} else { $null }
if (-not (Test-Path -LiteralPath $bundledLlama) -and -not $installedLlama) {
    throw 'llama-server.exe is missing after installation.'
}
$modelExit = Invoke-PythonStep 'download_models'
if ($modelExit -ne 0) { throw "OCR model download failed with exit code $modelExit" }
$verifyExit = Invoke-PythonStep 'verify_setup'
if ($verifyExit -ne 0) { throw "GPU OCR verification failed with exit code $verifyExit" }

$shortcut = Join-Path ([Environment]::GetFolderPath('Desktop')) 'Clipboard OCR.lnk'
$shell = New-Object -ComObject WScript.Shell
$link = $shell.CreateShortcut($shortcut)
$link.TargetPath = $basePythonw
$link.Arguments = '"' + (Join-Path $PSScriptRoot 'launch.py') + '"'
$link.WorkingDirectory = $root
$link.IconLocation = Join-Path $root 'assets\AppIcon.ico'
$link.WindowStyle = 1
$link.Save()
Write-Host "Setup complete: $shortcut"
Stop-Transcript | Out-Null
