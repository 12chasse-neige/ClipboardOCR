# Shared, side-effect-free helpers; covered by test_setup.ps1 on PowerShell 5.1.
function Get-CudaVariant([string]$Capability) {
    $value = 0.0
    if (-not [double]::TryParse($Capability.Trim(), [Globalization.NumberStyles]::Float,
        [Globalization.CultureInfo]::InvariantCulture, [ref]$value) -or $value -le 0) {
        throw 'Cannot identify GPU compute capability. Update the NVIDIA driver and rerun setup; no CUDA build was guessed.'
    }
    # cu129 contains [75,80,86,89,120] and correctly declares cuDNN 9.9.
    # cu126's metadata pins 9.5 but its binary warns it was compiled with 9.9.
    # One consistent wheel avoids both that conflict and same-version reuse.
    if (@(7.5, 8.0, 8.6, 8.9, 12.0) -contains $value) { return 'cu129' }
    throw "GPU capability $Capability is not covered by the pinned Windows wheels (7.5, 8.0, 8.6, 8.9, 12.0). Legacy CUDA 11 and other unlisted GPUs need a separately validated runtime."
}

function Invoke-UvInstall {
    param([string[]]$Packages, [string[]]$Indexes, [string[]]$ExtraArgs = @())
    # One index per attempt: uv gives extra-index-url higher priority, and
    # an HTTP/download failure is not a request to try the next index.
    foreach ($index in ($Indexes | Select-Object -Unique)) {
        for ($attempt = 1; $attempt -le 2; $attempt++) {
            Write-Host "Installing $($Packages -join ', ') from $index (attempt $attempt/2; cached files are reused)"
            & $uv pip install --python $python --index-url $index @ExtraArgs @Packages
            if ($LASTEXITCODE -eq 0) { return }
            Write-Warning "Package installation failed with exit code $LASTEXITCODE; retrying or switching source."
            if ($attempt -lt 2) { Start-Sleep -Seconds 2 }
        }
    }
    throw "Could not install $($Packages -join ', '). Rerun setup to reuse the cache. See $logDir\setup.log for the original error."
}
