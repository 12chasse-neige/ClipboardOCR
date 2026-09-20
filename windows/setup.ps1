$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$pythonRoot = Join-Path $root '.windows\python'
$runtime = Join-Path $root '.windows\runtime'
$python = Join-Path $runtime 'Scripts\python.exe'
$bundledUv = Join-Path $root '.windows\tools\uv.exe'
$uv = if (Test-Path -LiteralPath $bundledUv) { $bundledUv } else { (Get-Command uv -ErrorAction Stop).Source }
$env:UV_LINK_MODE = 'copy'

if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    throw 'An NVIDIA GPU and current NVIDIA driver are required.'
}

$env:UV_PYTHON_INSTALL_DIR = $pythonRoot
& $uv python install 3.12.13
$basePython = (& $uv python find 3.12.13 --managed-python).Trim()
$basePythonw = Join-Path (Split-Path -Parent $basePython) 'pythonw.exe'
if (-not (Test-Path -LiteralPath $python)) {
    & $uv venv --python $basePython $runtime
}
& $uv pip install --python $python --index-url https://www.paddlepaddle.org.cn/packages/stable/cu126/ 'paddlepaddle-gpu==3.2.1'
& $uv pip install --python $python 'paddleocr[doc-parser]==3.7.0' 'PySide6==6.9.3' 'Pillow==12.1.0'
& $uv pip install --python $python 'nvidia-cudnn-cu12==9.9.0.52'
& $python -c "from PIL import Image; Image.open(r'$root\assets\AppIcon.png').save(r'$root\assets\AppIcon.ico', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])"
$bundledLlama = Join-Path $root '.windows\tools\llama\llama-server.exe'
if (-not (Test-Path -LiteralPath $bundledLlama) -and -not (Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter llama-server.exe -Recurse -ErrorAction SilentlyContinue)) {
    winget install --id ggml.llamacpp --version b11026 --exact --accept-package-agreements --accept-source-agreements --silent
}
& $python (Join-Path $PSScriptRoot 'download_models.py')
& $python (Join-Path $PSScriptRoot 'verify_setup.py')

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
