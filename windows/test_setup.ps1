$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'setup_helpers.ps1')
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
$culture = [Threading.Thread]::CurrentThread.CurrentCulture
try {
    [Threading.Thread]::CurrentThread.CurrentCulture = [Globalization.CultureInfo]'de-DE'
    foreach ($cap in @('7.5', '8.0', '8.6', '8.9')) {
        Assert ((Get-CudaVariant $cap) -eq 'cu129') "Incorrect unified build for $cap"
    }
    foreach ($cap in @('12.0')) {
        Assert ((Get-CudaVariant $cap) -eq 'cu129') "Incorrect Blackwell build for $cap"
    }
    foreach ($cap in @('', 'N/A', '0', '6.1', '9.0', '10.0', '12.1', 'NaN', 'Infinity', '8,9')) {
        $rejected = $false
        try { Get-CudaVariant $cap | Out-Null } catch { $rejected = $true }
        Assert $rejected "Invalid/unsupported capability accepted: $cap"
    }
} finally { [Threading.Thread]::CurrentThread.CurrentCulture = $culture }

# Fault injection without installing anything or sleeping.
function Start-Sleep { param($Seconds) }
$python = 'test-python'
$logDir = 'test-logs'
$script:calls = @()
$uv = {
    $script:calls += ,@($args)
    $global:LASTEXITCODE = if ($args -contains 'https://second.example/simple') { 0 } else { 1 }
}
Invoke-UvInstall -Packages @('example==1') -Indexes @('https://first.example/simple', 'https://second.example/simple')
Assert ($script:calls.Count -eq 3) 'Retry/failover did not make 2+1 attempts'
Assert ($script:calls[0] -contains 'https://first.example/simple') 'Preferred index not first'
Assert (-not ($script:calls[0] -contains '--extra-index-url')) 'Index priority regressed'
$script:calls = @()
$rejected = $false
try { Invoke-UvInstall -Packages @('example==1') -Indexes @('https://first.example/simple') } catch { $rejected = $true }
Assert ($rejected -and $script:calls.Count -eq 2) 'Permanent failure must stop after bounded retries'
Write-Host 'PASS: GPU matrix, locale-independent parsing, invalid detection, retries, source order, terminal failure'
