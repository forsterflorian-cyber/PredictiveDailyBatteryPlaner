param(
    [string]$Device = "fr955",
    [string]$Key = "developer_key.der",
    [string]$OutDir = "dist",
    [switch]$Clean
)

$ErrorActionPreference = "Stop"

function Ensure-Tool($name) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        throw "Required tool not found in PATH: $name"
    }
}

function Invoke-Monkeyc([string[]]$MonkeycArgs) {
    & monkeyc @MonkeycArgs | Out-Host
    if ($LASTEXITCODE -ne 0) {
        throw "monkeyc failed (exit=$LASTEXITCODE): monkeyc $($MonkeycArgs -join ' ')"
    }
}

Ensure-Tool "monkeyc"

if (-not (Test-Path $Key)) {
    throw "Signing key not found: $Key (download your Connect IQ developer key .der, or pass -Key)"
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if ($Clean) {
    Get-ChildItem -Path $OutDir -File -ErrorAction SilentlyContinue | ForEach-Object {
        try { $_.Delete() } catch { }
    }
}

$iqOut = Join-Path $OutDir "BatteryBudget.iq"
$prgOut = Join-Path $OutDir "BatteryBudget.prg"

Write-Host "Building device PRG ($Device) -> $prgOut"
Invoke-Monkeyc @('-f','monkey.jungle','-o',$prgOut,'-y',$Key,'-d',$Device,'-w')

Write-Host "Building store package IQ -> $iqOut"
Invoke-Monkeyc @('-f','monkey.jungle','-o',$iqOut,'-y',$Key,'-e','-r','-w')

Write-Host "Done. Outputs:"
Write-Host "- $prgOut"
Write-Host "- $iqOut"