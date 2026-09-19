# X4MP uninstaller -- removes everything Install.bat put in the game folder.
# Savegames are never touched.

$ErrorActionPreference = 'Stop'

function Say([string]$t, [string]$c = 'Gray') { Write-Host $t -ForegroundColor $c }
function Ok([string]$t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Warn([string]$t) { Write-Host "  [!]    $t" -ForegroundColor Yellow }

Say ''
Say '  ============================================================' Cyan
Say '    X4 Multiplayer (X4MP) - uninstaller' Cyan
Say '  ============================================================' Cyan
Say ''

function Get-SteamRoots {
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop).SteamPath
            if ($p) { $roots += $p.Replace('/', '\') }
        } catch { }
    }
    foreach ($guess in "$env:ProgramFiles(x86)\Steam", "$env:ProgramFiles\Steam") {
        if ($guess -and (Test-Path $guess)) { $roots += $guess }
    }
    return $roots | Select-Object -Unique
}

function Find-X4 {
    $libs = @()
    foreach ($root in (Get-SteamRoots)) {
        $libs += $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($line in (Get-Content $vdf)) {
                if ($line -match '"path"\s+"([^"]+)"') { $libs += $matches[1].Replace('\\', '\') }
            }
        }
    }
    foreach ($lib in ($libs | Select-Object -Unique)) {
        $c = Join-Path $lib 'steamapps\common\X4 Foundations'
        if (Test-Path (Join-Path $c 'X4.exe')) { return $c }
    }
    return $null
}

$game = Find-X4
if (-not $game) {
    $game = (Read-Host '  Path to your X4 Foundations folder').Trim('"').Trim()
}
if (-not (Test-Path (Join-Path $game 'X4.exe'))) {
    Warn "no X4.exe in: $game"
    Say ''
    return
}
Say "  Game folder: $game"
Say ''

$removed = 0
foreach ($name in 'x4native', 'x4mp', 'x4mp_stream') {
    $p = Join-Path $game "extensions\$name"
    if (Test-Path $p) { Remove-Item -Recurse -Force $p; Ok "removed extensions\$name"; $removed++ }
}
foreach ($file in 'x4mp.bat', 'steam_appid.txt', 'x4mp_client.key') {
    $p = Join-Path $game $file
    if (Test-Path $p) { Remove-Item -Force $p; Ok "removed $file"; $removed++ }
}
$lnk = Join-Path ([Environment]::GetFolderPath('Desktop')) 'X4 Multiplayer.lnk'
if (Test-Path $lnk) { Remove-Item -Force $lnk; Ok 'removed the Desktop shortcut'; $removed++ }

Say ''
if ($removed -eq 0) {
    Warn 'nothing to remove - X4MP was not installed here.'
} else {
    Say '  Done. Your savegames and the rest of the game are untouched.' Green
    Say '  (The mod also wrote logs to Documents\Egosoft\X4\<number>\x4native\' Gray
    Say '   - harmless, delete that folder too if you like.)' Gray
}
Say ''
