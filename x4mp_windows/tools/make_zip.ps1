# Packs this folder into a single zip you can send to a friend.

$ErrorActionPreference = 'Stop'
$src = Split-Path -Parent $PSScriptRoot
$out = Join-Path ([Environment]::GetFolderPath('Desktop')) 'X4-Multiplayer.zip'

Write-Host ''
Write-Host '  Packing X4 Multiplayer for sharing ...' -ForegroundColor Cyan
Write-Host ''

if (Test-Path $out) { Remove-Item -Force $out }

# Staged copy so build leftovers never end up in the zip.
$stage = Join-Path $env:TEMP ('x4mp_zip_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
New-Item -ItemType Directory -Path $stage | Out-Null
$dest = Join-Path $stage 'X4-Multiplayer'
New-Item -ItemType Directory -Path $dest | Out-Null

foreach ($item in (Get-ChildItem -Path $src)) {
    if ($item.Name -in @('patches')) { continue }   # developer-only
    Copy-Item -Recurse -Force $item.FullName (Join-Path $dest $item.Name)
}

Compress-Archive -Path $dest -DestinationPath $out -CompressionLevel Optimal
Remove-Item -Recurse -Force $stage

$mb = [math]::Round((Get-Item $out).Length / 1MB, 1)
Write-Host "  Created: $out  ($mb MB)" -ForegroundColor Green
Write-Host ''
Write-Host '  Send that file to your friend and tell them:' -ForegroundColor White
Write-Host '    1. Right-click the zip -> Extract All (anywhere you like)'
Write-Host '    2. Open the folder and read "READ ME FIRST.txt"'
Write-Host '    3. Double-click Install.bat'
Write-Host ''
Write-Host '  They need their own copy of X4: Foundations on Steam.' -ForegroundColor Gray
Write-Host ''
