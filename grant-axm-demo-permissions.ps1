# Grant IIS Application Pool identity Read access to C:\inetpub\axm-demo
# RUN AS ADMINISTRATOR (Right-click PowerShell -> Run as administrator)

$path = "C:\inetpub\axm-demo"
$identity = "IIS AppPool\AXM Demo"   # Change "AXM Demo" if your app pool has a different name

if (-not (Test-Path $path)) {
    Write-Host "Path not found: $path" -ForegroundColor Red
    exit 1
}

$acl = Get-Acl $path
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    $identity,
    "Read,ReadAndExecute,ListDirectory",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl -Path $path -AclObject $acl

Write-Host "Granted Read access to '$identity' on $path" -ForegroundColor Green
Write-Host "Run Test Connection again in IIS Manager." -ForegroundColor Yellow
