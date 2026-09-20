param([string]$Version = '0.2.0-preview.3')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$stage = Join-Path $root 'build\windows-installer'
$dist = Join-Path $root 'dist'
$builderPython = if ($env:CLIPBOARD_OCR_BUILDER_PYTHON) { $env:CLIPBOARD_OCR_BUILDER_PYTHON } else { Join-Path $root '.windows\runtime\Scripts\python.exe' }
$uv = (Get-Command uv -ErrorAction Stop).Source
$llama = Get-ChildItem "$env:LOCALAPPDATA\Microsoft\WinGet\Packages" -Filter llama-server.exe -Recurse -ErrorAction Stop | Select-Object -First 1
$iscc = @(
    (Get-Command iscc.exe -ErrorAction SilentlyContinue).Source,
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1

if (-not $iscc) { throw 'Inno Setup 6 is required: winget install --id JRSoftware.InnoSetup --exact' }
if (-not (Test-Path -LiteralPath $builderPython)) { throw 'Set CLIPBOARD_OCR_BUILDER_PYTHON to a Python environment with Pillow.' }
$uvVersion = (& $uv --version) -join "`n"
$llamaVersion = (& $llama.FullName --version 2>&1) -join "`n"
if ($uvVersion -notmatch '^uv 0\.11\.19 ') { throw "Expected uv 0.11.19, found: $uvVersion" }
if ($llamaVersion -notmatch 'build 11026, commit b49650adb') { throw "Expected llama.cpp b11026/b49650adb, found: $llamaVersion" }

$stagePath = [IO.Path]::GetFullPath($stage)
$buildPath = [IO.Path]::GetFullPath((Join-Path $root 'build'))
if (-not $stagePath.StartsWith($buildPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Unsafe staging path.' }
if (Test-Path -LiteralPath $stage) { Remove-Item -LiteralPath $stage -Recurse -Force }
New-Item -ItemType Directory -Path $stage,$dist,"$stage\backend","$stage\windows","$stage\assets","$stage\validation","$stage\.windows\tools\llama","$stage\licenses" -Force | Out-Null

$files = @(
    'README.md', 'WINDOWS.md',
    'backend\engine.py', 'backend\engine_windows.py',
    'windows\app.py', 'windows\download_models.py', 'windows\launch_hidden.vbs', 'windows\setup.ps1', 'windows\verify_setup.py',
    'assets\AppIcon.png', 'validation\example-1.png'
)
foreach ($file in $files) {
    Copy-Item -LiteralPath (Join-Path $root $file) -Destination (Join-Path $stage $file) -Force
}
Copy-Item -LiteralPath $uv -Destination "$stage\.windows\tools\uv.exe" -Force
Copy-Item -Path (Join-Path $llama.DirectoryName '*') -Destination "$stage\.windows\tools\llama" -Recurse -Force
Copy-Item -LiteralPath (Join-Path $llama.DirectoryName 'LICENSE-LLVM-OpenMP') -Destination "$stage\licenses\LLVM-OpenMP-LICENSE" -Force
Invoke-WebRequest 'https://raw.githubusercontent.com/ggml-org/llama.cpp/b49650adb/LICENSE' -OutFile "$stage\licenses\llama.cpp-LICENSE"
Invoke-WebRequest 'https://raw.githubusercontent.com/astral-sh/uv/0.11.19/LICENSE-MIT' -OutFile "$stage\licenses\uv-LICENSE-MIT"
Invoke-WebRequest 'https://raw.githubusercontent.com/astral-sh/uv/0.11.19/LICENSE-APACHE' -OutFile "$stage\licenses\uv-LICENSE-APACHE"
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'THIRD_PARTY_NOTICES.md') -Destination "$stage\THIRD_PARTY_NOTICES.md" -Force
& $builderPython -c "from PIL import Image; Image.open(r'$root\assets\AppIcon.png').save(r'$stage\assets\AppIcon.ico', sizes=[(256,256),(128,128),(64,64),(48,48),(32,32),(16,16)])"
if ($LASTEXITCODE) { throw 'Icon generation failed.' }

& $iscc "/DStageDir=$stage" "/DOutputDir=$dist" "/DAppVersion=$Version" (Join-Path $PSScriptRoot 'installer.iss')
if ($LASTEXITCODE) { throw 'Installer build failed.' }
$installer = Join-Path $dist "ClipboardOCR-$Version-windows-x64-setup.exe"
if (-not (Test-Path -LiteralPath $installer)) { throw 'Installer output was not created.' }
Get-FileHash -Algorithm SHA256 -LiteralPath $installer
