# X4MP installer -- finds X4: Foundations, copies the extensions in, and sets
# up everything the launcher needs. Driven by Install.bat (double-click).
#
# Windows PowerShell 5.1 compatible: no ternary, no ??, no -AsHashtable.

$ErrorActionPreference = 'Stop'
$APPID = '392160'
$src = Split-Path -Parent $PSScriptRoot   # ...\x4mp_windows

function Say([string]$text, [string]$colour = 'Gray') { Write-Host $text -ForegroundColor $colour }
function Ok([string]$text)   { Write-Host "  [OK]   $text" -ForegroundColor Green }
function Warn([string]$text) { Write-Host "  [!]    $text" -ForegroundColor Yellow }
function Bad([string]$text)  { Write-Host "  [X]    $text" -ForegroundColor Red }

Say ''
Say '  ============================================================' Cyan
Say '    X4 Multiplayer (X4MP) - installer' Cyan
Say '  ============================================================' Cyan
Say ''

# ---------------------------------------------------------------- find X4
function Get-SteamRoots {
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try {
            $p = (Get-ItemProperty -Path $key -ErrorAction Stop).SteamPath
            if ($p) { $roots += $p.Replace('/', '\') }
        } catch { }
    }
    foreach ($guess in "$env:ProgramFiles(x86)\Steam", "$env:ProgramFiles\Steam", 'C:\Steam') {
        if ($guess -and (Test-Path $guess)) { $roots += $guess }
    }
    return $roots | Select-Object -Unique
}

function Get-LibraryFolders {
    $libs = @()
    foreach ($root in (Get-SteamRoots)) {
        $libs += $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($line in (Get-Content $vdf)) {
                if ($line -match '"path"\s+"([^"]+)"') {
                    $libs += $matches[1].Replace('\\', '\')
                }
            }
        }
    }
    return $libs | Select-Object -Unique
}

function Find-X4 {
    foreach ($lib in (Get-LibraryFolders)) {
        $candidate = Join-Path $lib 'steamapps\common\X4 Foundations'
        if (Test-Path (Join-Path $candidate 'X4.exe')) { return $candidate }
    }
    # Non-Steam / unusual installs: look for X4.exe near the usual roots.
    foreach ($drive in (Get-PSDrive -PSProvider FileSystem | Where-Object { $_.Used -ne $null })) {
        $guess = Join-Path $drive.Root 'Games\X4 Foundations'
        if (Test-Path (Join-Path $guess 'X4.exe')) { return $guess }
    }
    return $null
}

Say ' Looking for X4: Foundations ...'
$game = Find-X4

if ($game) {
    Ok "found: $game"
} else {
    Warn 'could not find it automatically.'
    Say ''
    Say '  Open the folder that contains X4.exe, copy its address from the'
    Say '  Explorer address bar, and paste it below (right-click pastes).'
    Say ''
    while (-not $game) {
        $typed = Read-Host '  Path to your X4 Foundations folder'
        if (-not $typed) { Say '  (nothing entered - press Ctrl+C to quit)'; continue }
        $typed = $typed.Trim('"').Trim()
        if (Test-Path (Join-Path $typed 'X4.exe')) {
            $game = $typed
            Ok "using: $game"
        } else {
            Bad "no X4.exe in: $typed"
        }
    }
}

$extDir = Join-Path $game 'extensions'
if (-not (Test-Path $extDir)) { New-Item -ItemType Directory -Path $extDir | Out-Null }

# ---------------------------------------------------------------- copy files
Say ''
Say ' Installing the extensions ...'
foreach ($name in 'x4native', 'x4mp', 'x4mp_stream') {
    $from = Join-Path $src "extensions\$name"
    $to = Join-Path $extDir $name
    if (-not (Test-Path $from)) { Bad "missing from this package: $name"; continue }
    if (Test-Path $to) { Remove-Item -Recurse -Force $to }
    Copy-Item -Recurse -Force $from $to
    Ok "$name"
}

# Files extracted from a downloaded zip carry a "came from the internet"
# tag (Mark-of-the-Web). Windows can refuse to load tagged unsigned DLLs
# into a process, which makes the mod silently never start. Strip it.
$unblocked = 0
foreach ($name in 'x4native', 'x4mp', 'x4mp_stream') {
    $to = Join-Path $extDir $name
    if (Test-Path $to) {
        Get-ChildItem -Path $to -Recurse -File | ForEach-Object {
            try { Unblock-File -Path $_.FullName -ErrorAction Stop; $unblocked++ } catch { }
        }
    }
}
Ok "unblocked $unblocked file(s) (clears the downloaded-from-internet tag)"

$vdb = Join-Path $extDir 'x4native\native\version_db'
if (Test-Path $vdb) {
    Ok 'version_db (needed for combat/boarding events)'
} else {
    Warn 'version_db missing - kills, captures and boarding will not work'
}

# ---------------------------------------------------------------- appid + launcher
Say ''
Say ' Setting up the launcher ...'
$appidFile = Join-Path $game 'steam_appid.txt'
if (Test-Path $appidFile) {
    Ok 'steam_appid.txt already present'
} else {
    Set-Content -Path $appidFile -Value $APPID -Encoding ascii -NoNewline
    Ok 'steam_appid.txt created (stops Steam discarding the settings)'
}

$bat = Join-Path $src 'x4mp.bat'
if (Test-Path $bat) {
    Copy-Item -Force $bat (Join-Path $game 'x4mp.bat')
    Ok 'x4mp.bat placed next to X4.exe'
} else {
    Bad 'x4mp.bat missing from this package'
}

# ---------------------------------------------------------------- prerequisites
Say ''
Say ' Checking prerequisites ...'
$missing = @()
foreach ($dll in 'MSVCP140.dll', 'VCRUNTIME140.dll', 'VCRUNTIME140_1.dll') {
    if (-not (Test-Path (Join-Path $env:SystemRoot "System32\$dll"))) { $missing += $dll }
}
if ($missing.Count -eq 0) {
    Ok 'Visual C++ 2015-2022 runtime present'
} else {
    Warn "Visual C++ runtime missing ($($missing -join ', '))"
    Say '         The mod will NOT load without it. Install this first:' Yellow
    Say '         https://aka.ms/vs/17/release/vc_redist.x64.exe' Yellow
}

# ---------------------------------------------------------------- shortcut
Say ''
$answer = Read-Host ' Put a "X4 Multiplayer" shortcut on your Desktop? [Y/n]'
if ($answer -notmatch '^[nN]') {
    try {
        $desktop = [Environment]::GetFolderPath('Desktop')
        $lnk = (New-Object -ComObject WScript.Shell).CreateShortcut((Join-Path $desktop 'X4 Multiplayer.lnk'))
        $lnk.TargetPath = Join-Path $game 'x4mp.bat'
        $lnk.WorkingDirectory = $game
        $lnk.IconLocation = Join-Path $game 'X4.exe'
        $lnk.Description = 'Launch X4: Foundations in multiplayer mode'
        $lnk.Save()
        Ok 'Desktop shortcut created'
    } catch {
        Warn "could not create the shortcut: $($_.Exception.Message)"
    }
}

# ---------------------------------------------------------------- what next
Say ''
Say '  ============================================================' Cyan
Say '    Installed.' Cyan
Say '  ============================================================' Cyan
Say ''
Say '  ONE more thing before you play - turn the mod on in the game:' White
Say ''
Say '    1. Start X4 normally (Steam).'
Say '    2. Main menu -> Settings -> Extensions.'
Say '    3. Tick:  x4native   x4mp   x4mp_stream'
Say '    4. Quit X4 completely and start it again.'
Say ''
Say '  Then, to play together:' White
Say ''
Say '    * Use the "X4 Multiplayer" shortcut (or x4mp.bat in the game folder).'
Say '    * ONE person is the HOST, everyone else is a CLIENT.'
Say '    * The host tells everyone their IP address - the launcher shows it.'
Say '    * EVERYONE must load the SAME savegame. The host sends their save'
Say '      file to the others; it goes in:'
Say '        Documents\Egosoft\X4\<a long number>\save\'
Say ''
Say '  If Windows asks whether to allow X4 through the firewall, say YES' White
Say '  (tick Private networks). That prompt only appears for the host.' White
Say ''
Say "  Game folder: $game"
Say ''
