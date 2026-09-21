# X4MP install checker -- answers "why don't I have the multiplayer menu?"
# Run it (Check Install.bat) and send whoever is helping you the output.

$ErrorActionPreference = 'Continue'

function Head([string]$t) { Write-Host ''; Write-Host "  $t" -ForegroundColor Cyan; Write-Host ('  ' + ('-' * 56)) -ForegroundColor DarkGray }
function Ok([string]$t)   { Write-Host "  [OK]   $t" -ForegroundColor Green }
function Bad([string]$t)  { Write-Host "  [X]    $t" -ForegroundColor Red }
function Warn([string]$t) { Write-Host "  [!]    $t" -ForegroundColor Yellow }
function Info([string]$t) { Write-Host "         $t" -ForegroundColor Gray }

$problems = New-Object System.Collections.ArrayList

Write-Host ''
Write-Host '  ============================================================' -ForegroundColor Cyan
Write-Host '    X4 Multiplayer - install check' -ForegroundColor Cyan
Write-Host '  ============================================================' -ForegroundColor Cyan

# ------------------------------------------------------------------ find X4
function Get-SteamRoots {
    $roots = @()
    foreach ($key in 'HKCU:\Software\Valve\Steam', 'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam', 'HKLM:\SOFTWARE\Valve\Steam') {
        try { $p = (Get-ItemProperty -Path $key -ErrorAction Stop).SteamPath; if ($p) { $roots += $p.Replace('/', '\') } } catch { }
    }
    foreach ($g in "$env:ProgramFiles(x86)\Steam", "$env:ProgramFiles\Steam") { if ($g -and (Test-Path $g)) { $roots += $g } }
    return $roots | Select-Object -Unique
}
function Find-AllX4 {
    $libs = @()
    foreach ($root in (Get-SteamRoots)) {
        $libs += $root
        $vdf = Join-Path $root 'steamapps\libraryfolders.vdf'
        if (Test-Path $vdf) {
            foreach ($line in (Get-Content $vdf)) { if ($line -match '"path"\s+"([^"]+)"') { $libs += $matches[1].Replace('\\', '\') } }
        }
    }
    $found = @()
    $seen = @{}
    foreach ($lib in $libs) {
        $c = Join-Path $lib 'steamapps\common\X4 Foundations'
        if (Test-Path (Join-Path $c 'X4.exe')) {
            # Windows paths ignore case: d:\steam and D:\Steam are ONE install.
            $full = (Resolve-Path $c).Path
            $norm = $full.ToLowerInvariant()
            if (-not $seen.ContainsKey($norm)) { $seen[$norm] = $true; $found += $full }
        }
    }
    return $found
}

Head 'The game'
$games = @(Find-AllX4)
if ($games.Count -eq 0) {
    Bad 'no X4: Foundations install found via Steam'
    Info 'If X4 is installed somewhere unusual, this check cannot see it.'
    [void]$problems.Add('X4 install not found')
    $game = $null
} else {
    if ($games.Count -gt 1) {
        Warn "more than one X4 install found - the mod must go in the one you PLAY:"
        foreach ($g in $games) { Info $g }
        [void]$problems.Add('multiple X4 installs - the mod may be in the wrong one')
    }
    $game = $games[0]
    Ok "game folder: $game"
    $verFile = Join-Path $game 'version.dat'
    if (Test-Path $verFile) {
        $ver = (Get-Content $verFile -Raw).Trim()
        Ok "game build: $ver   (this package is built for 900)"
        if ($ver -ne '900') {
            Warn "your build ($ver) is not 900 - the mod may refuse to load"
            [void]$problems.Add("game build $ver, package expects 900")
        }
    }
}

# ------------------------------------------------------------------ files
if ($game) {
    Head 'Mod files in the game folder'
    $need = @{
        'extensions\x4native\content.xml'                          = 'x4native (loader)'
        'extensions\x4native\native\x4native_64.dll'               = 'x4native lua dll'
        'extensions\x4native\native\x4native_core.dll'             = 'x4native core dll'
        'extensions\x4native\native\version_db\internal_functions.json' = 'version_db (combat/boarding events)'
        'extensions\x4native\ui\x4native.lua'                      = 'x4native ui script'
        'extensions\x4mp\native\x4mp.dll'                          = 'x4mp dll'
        'extensions\x4mp\ui\x4mp_menu.lua'                         = 'x4mp MENU script  <-- the menu entries'
        'extensions\x4mp_stream\native\x4mp_stream.dll'            = 'x4mp_stream dll'
        'steam_appid.txt'                                          = 'steam_appid.txt'
        'x4mp.bat'                                                 = 'launcher'
    }
    $missingFiles = 0
    foreach ($rel in ($need.Keys | Sort-Object)) {
        if (Test-Path (Join-Path $game $rel)) { Ok $need[$rel] } else { Bad "MISSING: $rel"; $missingFiles++ }
    }
    if ($missingFiles -gt 0) {
        [void]$problems.Add("$missingFiles mod file(s) missing - run Install.bat")
    }

    # Mark-of-the-Web: the tag Windows puts on files that came out of a
    # downloaded zip. It can stop unsigned DLLs loading into a process,
    # which looks exactly like "the mod does nothing".
    $blocked = @()
    foreach ($rel in 'extensions\x4native\native\x4native_64.dll',
                     'extensions\x4native\native\x4native_core.dll',
                     'extensions\x4mp\native\x4mp.dll',
                     'extensions\x4mp_stream\native\x4mp_stream.dll') {
        $f = Join-Path $game $rel
        if (Test-Path $f) {
            try {
                Get-Item -Path $f -Stream Zone.Identifier -ErrorAction Stop | Out-Null
                $blocked += $rel
            } catch { }
        }
    }
    if ($blocked.Count -gt 0) {
        Bad "$($blocked.Count) DLL(s) tagged 'downloaded from the internet'"
        Info 'Windows may refuse to load them, so the mod never starts.'
        Info 'Fix: run Install.bat again - it strips the tag.'
        [void]$problems.Add('DLLs blocked by Mark-of-the-Web - re-run Install.bat')
    } else {
        Ok 'DLLs are not blocked by Windows (no internet tag)'
    }
}

# ------------------------------------------------------------------ runtime
Head 'Windows prerequisites'
$missingRt = @()
foreach ($dll in 'MSVCP140.dll', 'VCRUNTIME140.dll', 'VCRUNTIME140_1.dll') {
    if (-not (Test-Path (Join-Path $env:SystemRoot "System32\$dll"))) { $missingRt += $dll }
}
if ($missingRt.Count -eq 0) {
    Ok 'Visual C++ 2015-2022 runtime present'
} else {
    Bad "Visual C++ runtime MISSING: $($missingRt -join ', ')"
    Info 'The mod cannot load without it. Install:'
    Info 'https://aka.ms/vs/17/release/vc_redist.x64.exe'
    [void]$problems.Add('Visual C++ runtime missing')
}

# ------------------------------------------------------------------ enabled?
Head 'Is the mod switched on in the game?'
$userRoot = Join-Path $env:USERPROFILE 'Documents\Egosoft\X4'
$accounts = @()
if (Test-Path $userRoot) {
    $accounts = Get-ChildItem -Path $userRoot -Directory | Where-Object { $_.Name -match '^\d+$' }
}
if ($accounts.Count -eq 0) {
    Warn "no player folder under $userRoot"
    Info 'Start X4 once, then run this check again.'
} else {
    foreach ($acct in $accounts) {
        Info "player folder: $($acct.FullName)"
        $content = Join-Path $acct.FullName 'content.xml'
        $disabled = @()
        if (Test-Path $content) {
            $xml = Get-Content $content -Raw
            foreach ($id in 'x4native', 'x4mp', 'x4mp_stream') {
                if ($xml -match "<extension\s+id=`"$id`"[^>]*enabled=`"false`"") { $disabled += $id }
            }
        }
        if ($disabled.Count -gt 0) {
            Bad "TURNED OFF in game: $($disabled -join ', ')"
            Info 'Fix: start X4 -> Settings -> Extensions -> tick them -> restart X4.'
            [void]$problems.Add('extensions disabled in the Extensions menu')
        } else {
            Ok 'not switched off in content.xml (should be active once the game sees them)'
        }

        # --- did the mod actually run?
        $logDir = Join-Path $acct.FullName 'x4native'
        $log = Join-Path $logDir 'x4native.log'
        if (-not (Test-Path $logDir)) {
            Bad 'the mod has NEVER run (no x4native log folder)'
            Info 'That means the game never loaded the DLLs - see the problems listed at the end.'
            [void]$problems.Add('mod never initialised - no log folder')
        } elseif (Test-Path $log) {
            Ok "log found: $log"
            Write-Host ''
            Write-Host '         --- first lines of the log ---' -ForegroundColor DarkGray
            Get-Content $log -TotalCount 12 | ForEach-Object { Write-Host "         $_" -ForegroundColor DarkGray }
            $all = Get-Content $log -Raw
            Write-Host ''
            if ($all -match 'main-menu buttons installed') {
                Ok 'the multiplayer menu entries WERE installed'
                Info 'If you still cannot see them, look at the very bottom of the'
                Info 'start menu list, under "Exit to Desktop".'
            } else {
                Bad 'the menu entries were never installed'
                [void]$problems.Add('x4mp loaded but the menu was not injected')
            }
            if ($all -match 'not resolved \(missing RVA') {
                Warn 'some game hooks did not resolve - combat/boarding events will not work'
                Info '(usually means version_db is missing or your game build is different)'
            }
        }
    }
}

# ------------------------------------------------------------------ verdict
Head 'Verdict'
if ($problems.Count -eq 0) {
    Write-Host '  Everything checks out.' -ForegroundColor Green
    Write-Host '  The Host/Join Multiplayer entries are at the BOTTOM of the start' -ForegroundColor Gray
    Write-Host '  menu, below "Exit to Desktop".' -ForegroundColor Gray
} else {
    Write-Host '  Problems found, most important first:' -ForegroundColor Yellow
    $i = 1
    foreach ($p in $problems) { Write-Host "    $i. $p" -ForegroundColor Yellow; $i++ }
    Write-Host ''
    Write-Host '  Send this whole window to whoever gave you the mod:' -ForegroundColor Gray
    Write-Host '  right-click the title bar -> Edit -> Select All, then Enter to copy.' -ForegroundColor Gray
}
Write-Host ''
