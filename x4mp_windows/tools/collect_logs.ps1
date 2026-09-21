# Zips the mod's logs to the Desktop so they can be sent to whoever is helping.

$ErrorActionPreference = 'Stop'

Write-Host ''
Write-Host '  Collecting X4 Multiplayer logs ...' -ForegroundColor Cyan
Write-Host ''

$userRoot = Join-Path $env:USERPROFILE 'Documents\Egosoft\X4'
if (-not (Test-Path $userRoot)) {
    Write-Host "  No X4 player folder found at $userRoot" -ForegroundColor Red
    Write-Host ''
    return
}

$stage = Join-Path $env:TEMP ('x4mp_logs_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage | Out-Null
$found = 0

foreach ($acct in (Get-ChildItem -Path $userRoot -Directory | Where-Object { $_.Name -match '^\d+$' })) {
    $logDir = Join-Path $acct.FullName 'x4native'
    if (Test-Path $logDir) {
        $dest = Join-Path $stage $acct.Name
        Copy-Item -Recurse -Force $logDir $dest
        $found++
        Write-Host "  [OK]   logs from player folder $($acct.Name)" -ForegroundColor Green
    }
    # X4's own log, if the launcher wrote one
    foreach ($f in (Get-ChildItem -Path $acct.FullName -Filter 'x4mp_*.txt' -File -ErrorAction SilentlyContinue)) {
        $dest = Join-Path $stage $acct.Name
        if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
        Copy-Item -Force $f.FullName $dest
        Write-Host "  [OK]   game log $($f.Name)" -ForegroundColor Green
    }
    # what the game thinks is enabled, and whether Protected UI is off
    foreach ($cfg in 'content.xml', 'config.xml') {
        $src = Join-Path $acct.FullName $cfg
        if (Test-Path $src) {
            $dest = Join-Path $stage $acct.Name
            if (-not (Test-Path $dest)) { New-Item -ItemType Directory -Path $dest | Out-Null }
            Copy-Item -Force $src $dest
        }
    }
}

if ($found -eq 0) {
    Write-Host '  [!]    no mod logs found - the mod has never run on this machine.' -ForegroundColor Yellow
    Write-Host '         Run Check Install.bat instead.' -ForegroundColor Gray
    Remove-Item -Recurse -Force $stage
    Write-Host ''
    return
}

$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'X4MP-logs.zip'
if (Test-Path $out) { Remove-Item -Force $out }
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $out
Remove-Item -Recurse -Force $stage

$kb = [math]::Round((Get-Item $out).Length / 1KB, 0)
Write-Host ''
Write-Host "  Created: $out  ($kb KB)" -ForegroundColor Green
Write-Host '  Send that file to whoever is helping you.' -ForegroundColor White
Write-Host ''
