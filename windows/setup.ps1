param([switch]$SkipShortcut)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'setup_helpers.ps1')
$root = Split-Path -Parent $PSScriptRoot
$logDir = Join-Path $env:LOCALAPPDATA 'ClipboardOCR\logs'
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
Start-Transcript -Path (Join-Path $logDir 'setup.log') -Append | Out-Null
trap {
    Write-Error $_ -ErrorAction Continue
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

# Respect explicit source choices. Otherwise try domestic mirrors then PyPI;
# source selection is proven by real installs, not a misleading tiny speed probe.
$officialIndex = 'https://pypi.org/simple'
$packageIndexes = @($officialIndex)
if ($env:CLIPBOARD_OCR_PYPI_INDEX) {
    $packageIndexes = @($env:CLIPBOARD_OCR_PYPI_INDEX)
} elseif ($env:CLIPBOARD_OCR_DISABLE_MIRROR -ne '1') {
    $packageIndexes = @('https://pypi.tuna.tsinghua.edu.cn/simple', 'https://mirrors.cloud.tencent.com/pypi/simple', $officialIndex)
}
# Inherited uv extra indexes would silently outrank the selected source.
foreach ($name in @('UV_INDEX', 'UV_EXTRA_INDEX_URL')) {
    if (Test-Path "Env:$name") { Remove-Item "Env:$name" }
}
$env:UV_NO_CONFIG = '1'
if (-not $env:UV_HTTP_TIMEOUT) { $env:UV_HTTP_TIMEOUT = '120' }
if (-not $env:UV_HTTP_CONNECT_TIMEOUT) { $env:UV_HTTP_CONNECT_TIMEOUT = '10' }
if (-not $env:UV_HTTP_RETRIES) { $env:UV_HTTP_RETRIES = '3' }
if (-not $env:UV_CONCURRENT_DOWNLOADS) { $env:UV_CONCURRENT_DOWNLOADS = '2' }
Write-Host "Package sources (in order): $($packageIndexes -join ', ')"

# Preflight before any large download. The runtime currently uses NVIDIA GPU 0.
if (-not [Environment]::Is64BitOperatingSystem -or $env:PROCESSOR_ARCHITECTURE -eq 'ARM64') {
    throw 'This installer requires native Windows x64; Windows ARM64 is not supported.'
}
if (-not (Get-Command nvidia-smi -ErrorAction SilentlyContinue)) {
    throw 'An NVIDIA GPU and NVIDIA driver are required. AMD/Intel-only and CPU-only machines are not supported by this GPU runtime.'
}
$gpuOutput = & nvidia-smi --query-gpu=name,compute_cap,driver_version --format=csv,noheader --id=0
if ($LASTEXITCODE -ne 0) { throw 'NVIDIA GPU detection failed. Update/reinstall the NVIDIA driver and rerun setup.' }
$gpuFields = "$gpuOutput" -split ','
if ($gpuFields.Count -ne 3) { throw "Unexpected NVIDIA GPU response: $gpuOutput" }
$gpuName = $gpuFields[0].Trim()
$cudaVariant = Get-CudaVariant $gpuFields[1]
$driverVersion = $gpuFields[2].Trim()
Write-Host "GPU 0: $gpuName (compute capability $($gpuFields[1].Trim()), driver $driverVersion)"
Write-Host "Selected Paddle CUDA build: $cudaVariant"
$driver = $null
if (-not [version]::TryParse($driverVersion, [ref]$driver)) {
    throw "Cannot identify NVIDIA driver version: $driverVersion"
}
if ($driver -lt [version]'576.02') {
    throw "Update the NVIDIA Windows driver to 576.02 or newer before setup (installed: $driverVersion). The unified cu129 runtime supports GTX 16 / RTX 20-50 with a current driver."
}
if ($packageIndexes.Count -gt 1 -and (Get-Command curl.exe -ErrorAction SilentlyContinue)) {
    $reachable = @()
    $unreachable = @()
    foreach ($index in $packageIndexes) {
        # Probe a real dependency's larger index page, not the tiny six wheel.
        & curl.exe -s -f -L --max-time 8 -o NUL "$index/charset-normalizer/"
        if ($LASTEXITCODE -eq 0) { $reachable += $index } else { $unreachable += $index }
    }
    $packageIndexes = @($reachable) + @($unreachable)
    Write-Host "Reachable package sources first: $($packageIndexes -join ', ')"
}

# Windows PowerShell 5.1 decodes native command output with the console code page
# and aborts with "Index was outside the bounds of the array" when a child process
# writes characters that code page cannot represent.  huggingface_hub and its Xet
# backend draw Unicode progress bars, and that crash killed setup right after the
# model download on a non-UTF-8 console.  The Python steps below therefore write
# straight to files that are read back with an explicit encoding, and the progress
# bars are switched off on top of that.
$env:PYTHONIOENCODING = 'utf-8'
$env:PYTHONUNBUFFERED = '1'
$env:HF_HUB_DISABLE_PROGRESS_BARS = '1'
$env:TQDM_DISABLE = '1'

function Invoke-PythonStep([string]$name, [string[]]$Arguments = @()) {
    $stdout = Join-Path $logDir "$name.out.log"
    $stderr = Join-Path $logDir "$name.err.log"
    $process = Start-Process -FilePath $python `
        -ArgumentList (@("`"$(Join-Path $PSScriptRoot "$name.py")`"") + $Arguments) `
        -WindowStyle Hidden -PassThru `
        -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    # Keep the native handle open; PowerShell 5.1 otherwise may return a null
    # ExitCode after a short child process has already exited.
    $null = $process.Handle
    while (-not $process.WaitForExit(15000)) {
        Write-Host "$name is still running; download cache is retained. Logs: $logDir"
        if (Test-Path -LiteralPath $stdout) { Get-Content -LiteralPath $stdout -Encoding UTF8 -Tail 2 | ForEach-Object { Write-Host $_ } }
    }
    $process.WaitForExit()
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
# Keep cu126/cu129 artifacts separate although both have package version 3.2.1.
# Ordinary dependencies use PyPI mirrors rather than Paddle's specialized index.
$paddleRequirement = 'paddlepaddle-gpu==3.2.1'
$paddleIndexes = $packageIndexes
# Old index installations lack direct_url metadata. Reinstall only when the
# installed CUDA build cannot be verified, or differs from the selected build.
$expectedCuda = '12.9'
$installedCuda = & $python -c "import importlib.util; s=importlib.util.find_spec('paddle'); print('missing' if s is None else 'installed')" 2>$null
$paddleArgs = @()
$paddleReady = $false
if ($installedCuda -eq 'installed') {
    # Read build metadata without importing CUDA DLLs (which can fail before repair).
    $versionFile = Join-Path $runtime 'Lib\site-packages\paddle\version\__init__.py'
    $cudaMatch = if (Test-Path -LiteralPath $versionFile) {
        Select-String -LiteralPath $versionFile -Pattern "^cuda_version\s*=\s*'$([regex]::Escape($expectedCuda))'"
    } else { $null }
    if (-not $cudaMatch) {
        $paddleArgs = @('--reinstall-package', 'paddlepaddle-gpu')
        Write-Host "Replacing an unverified or different Paddle CUDA build with $expectedCuda"
    } else {
        $paddleReady = [bool](Select-String -LiteralPath $versionFile -Pattern "^full_version\s*=\s*'3\.2\.1'")
    }
}
if (-not $env:CLIPBOARD_OCR_PADDLE_INDEX) {
    if ($paddleReady) {
        $paddleRequirement = 'paddlepaddle-gpu==3.2.1'
        Write-Host "Reusing installed Paddle 3.2.1 / CUDA $expectedCuda"
    } else {
        $wheelExit = Invoke-PythonStep 'download_paddle' @($cudaVariant)
        if ($wheelExit -ne 0) { throw 'Paddle wheel download failed. Rerun setup to resume; see download_paddle.err.log.' }
        $paddleRequirement = Join-Path $dataRoot "downloads\$cudaVariant\paddlepaddle_gpu-3.2.1-cp312-cp312-win_amd64.whl"
    }
} else {
    # Extra indexes outrank the default: intentional for this explicit override,
    # while ordinary dependencies remain available on the chosen PyPI source.
    $paddleArgs += @('--index', $env:CLIPBOARD_OCR_PADDLE_INDEX)
}
# PaddleOCR/PaddleX 3.7 requires safetensors >=0.7.0. The old Blackwell
# 0.6.2.dev0 workaround is incompatible and must not be installed.
# The unified cu129 wheel's cuDNN 9.9.0.52 dependency agrees with its binary.
$appPackages = @('paddleocr[doc-parser]==3.7.0', 'paddlex[ocr]==3.7.2', 'safetensors==0.7.0', 'PySide6==6.9.3', 'Pillow==12.1.0')
Invoke-UvInstall -Packages (@($paddleRequirement) + $appPackages) -Indexes $paddleIndexes -ExtraArgs $paddleArgs
& $uv pip check --python $python
if ($LASTEXITCODE -ne 0) { throw 'Installed dependencies are inconsistent. See setup.log.' }
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
if ($SkipShortcut) {
    Write-Host 'Setup complete: verification passed; shortcut creation skipped.'
    Stop-Transcript | Out-Null
    exit 0
}

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
