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
# the managed interpreter in the user's trusted local profile; the app and its
# larger runtime/model files can remain in the selected install directory.
$pythonRoot = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\python'
$runtime = Join-Path $root '.windows\runtime'
$python = Join-Path $runtime 'Scripts\python.exe'
$bundledUv = Join-Path $root '.windows\tools\uv.exe'
$uv = if (Test-Path -LiteralPath $bundledUv) { $bundledUv } else { (Get-Command uv -ErrorAction Stop).Source }
$env:UV_LINK_MODE = 'copy'

if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    throw 'An NVIDIA GPU and current NVIDIA driver are required.'
}

$env:UV_PYTHON_INSTALL_DIR = $pythonRoot
New-Item -ItemType Directory -Path $pythonRoot -Force | Out-Null
Write-Host "Managed Python directory: $pythonRoot"
& $uv python install 3.12.13
$pythonInstallExit = $LASTEXITCODE
$basePython = (& $uv python find 3.12.13 --managed-python).Trim()
if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $basePython)) {
    throw "Managed Python 3.12.13 was not installed (uv exit code $pythonInstallExit)."
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
if (-not (Test-Path -LiteralPath $python)) {
    & $uv venv --python $basePython $runtime
    if ($LASTEXITCODE -ne 0) { throw "uv venv failed with exit code $LASTEXITCODE" }
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
& $python (Join-Path $PSScriptRoot 'download_models.py')
if ($LASTEXITCODE -ne 0) { throw "OCR model download failed with exit code $LASTEXITCODE" }
& $python (Join-Path $PSScriptRoot 'verify_setup.py')
if ($LASTEXITCODE -ne 0) { throw "GPU OCR verification failed with exit code $LASTEXITCODE" }

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
