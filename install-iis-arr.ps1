# Install IIS + WebSocket, URL Rewrite, ARR (run as Administrator)
# Usage: Right-click PowerShell -> Run as Administrator, then:
#   Set-ExecutionPolicy Bypass -Scope Process -Force; & ".\install-iis-arr.ps1"

# Require admin
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Please run PowerShell as Administrator, then run this script again." -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = 'Stop'

# --- 1. IIS with WebSocket ---
Write-Host "Step 1: Installing IIS and WebSocket Protocol..." -ForegroundColor Cyan
$iisFeatures = @(
    'IIS-WebServerRole',
    'IIS-WebServer',
    'IIS-CommonHttpFeatures',
    'IIS-StaticContent',
    'IIS-DefaultDocument',
    'IIS-DirectoryBrowsing',
    'IIS-HttpErrors',
    'IIS-ApplicationDevelopment',
    'IIS-WebSockets',
    'IIS-HealthAndDiagnostics',
    'IIS-HttpLogging',
    'IIS-Security',
    'IIS-RequestFiltering',
    'IIS-Performance',
    'IIS-WebServerManagementTools',
    'IIS-ManagementConsole'
)
foreach ($f in $iisFeatures) {
    try {
        $state = Get-WindowsOptionalFeature -Online -FeatureName $f -ErrorAction Stop
        if ($state.State -ne 'Enabled') {
            Enable-WindowsOptionalFeature -Online -FeatureName $f -NoRestart -All | Out-Null
            Write-Host "  Enabled: $f"
        }
    } catch {
        Write-Host "  Skip/Error $f : $_" -ForegroundColor Yellow
    }
}

# --- 2. URL Rewrite (must be before ARR) ---
Write-Host "`nStep 2: Installing URL Rewrite 2.1..." -ForegroundColor Cyan
$urlRewriteMsi = "https://download.microsoft.com/download/1/2/8/128E2E22-C1B9-44A4-BE2A-5859ED1D4592/rewrite_amd64_en-US.msi"
$urlRewritePath = "$env:TEMP\rewrite_amd64_en-US.msi"
if (-not (Test-Path $urlRewritePath)) {
    Invoke-WebRequest -Uri $urlRewriteMsi -OutFile $urlRewritePath -UseBasicParsing
}
Start-Process msiexec.exe -ArgumentList "/i `"$urlRewritePath`" /quiet /norestart" -Wait -Verb RunAs
Write-Host "  URL Rewrite installed."

# --- 3. Application Request Routing ---
Write-Host "`nStep 3: Installing Application Request Routing 3.0..." -ForegroundColor Cyan
$arrMsi = "https://go.microsoft.com/fwlink/?LinkID=615136"
$arrPath = "$env:TEMP\arr_amd64_en-US.msi"
if (-not (Test-Path $arrPath)) {
    Invoke-WebRequest -Uri $arrMsi -OutFile $arrPath -UseBasicParsing
}
Start-Process msiexec.exe -ArgumentList "/i `"$arrPath`" /quiet /norestart" -Wait -Verb RunAs
Write-Host "  ARR installed."

Write-Host "`nDone. You may need to restart the computer for IIS changes to fully apply." -ForegroundColor Green
Write-Host "Next: Open IIS Manager -> Server -> Application Request Routing Cache -> Server Proxy Settings -> Enable proxy." -ForegroundColor Yellow
