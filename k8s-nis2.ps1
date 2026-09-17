#Requires -Version 5.1
<#
.SYNOPSIS
  One-line bootstrap for the NIS2 Compliance Platform installer.

.DESCRIPTION
  Logs in to the private registry, pulls and unpacks the current release
  chart, then hands off to the chart's own interactive installer
  (install-k8s-nis2.ps1) so you never have to run helm/kubectl by hand.

    irm https://raw.githubusercontent.com/Besion22/k8s-nis2-installer/main/k8s-nis2.ps1 | iex

  To pass extra flags through to the installer (e.g. -Namespace), download
  it first instead of piping straight into iex:

    iwr https://raw.githubusercontent.com/Besion22/k8s-nis2-installer/main/k8s-nis2.ps1 -OutFile k8s-nis2.ps1
    .\k8s-nis2.ps1 -Namespace my-ns
#>
param(
    [string]$Version,
    [string]$Registry = "k8snis2.azurecr.io",
    [string]$ChartPath = "helm/nis2-platform",
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = "Continue"
$VersionUrl = "https://raw.githubusercontent.com/Besion22/k8s-nis2-installer/main/VERSION"

function Info($msg) { Write-Host "`n==> $msg" -ForegroundColor Cyan }
function Fail($msg) { Write-Host "FAIL: $msg" -ForegroundColor Red; exit 1 }

foreach ($cmd in "helm", "kubectl") {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) { Fail "$cmd not found on PATH -- install it first" }
}

if (-not $Version) {
    Info "checking latest version"
    try {
        $Version = (Invoke-RestMethod $VersionUrl).Trim()
    } catch {
        Fail "could not fetch latest version from $VersionUrl -- pass -Version explicitly"
    }
}
Write-Host "    using version $Version"

Info "registry login ($Registry)"
$AcrUser = Read-Host "ACR username"
$SecurePw = Read-Host "ACR password" -AsSecureString
$Bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePw)
try {
    $AcrPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($Bstr)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($Bstr)
}

$AcrPassword | & helm registry login $Registry --username $AcrUser --password-stdin
if ($LASTEXITCODE -ne 0) { Fail "helm registry login failed" }

$TempDir = Join-Path ([System.IO.Path]::GetTempPath()) "nis2-install-$(Get-Random)"
New-Item -ItemType Directory -Path $TempDir | Out-Null

Info "pulling $ChartPath version $Version"
& helm pull "oci://$Registry/$ChartPath" --version $Version --untar --untardir $TempDir
if ($LASTEXITCODE -ne 0) { Fail "helm pull failed" }

$ScriptsDir = Join-Path $TempDir "nis2-platform\scripts"
$FrontDoor = Join-Path $ScriptsDir "install-k8s-nis2.ps1"
if (-not (Test-Path $FrontDoor)) { Fail "expected $FrontDoor after pull -- chart layout changed?" }

Set-Location $ScriptsDir
& $FrontDoor @Rest
exit $LASTEXITCODE
