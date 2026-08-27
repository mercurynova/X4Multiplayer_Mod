@echo off
setlocal
cd /d "%~dp0"
title X4MP Launcher

REM ============================================================
REM  X4MP Launcher (Windows)
REM  Mirrors the Linux x4mp_launcher.sh: interactive prompts for
REM  role, universe/save (with save sync), transport, net mode,
REM  start mode, simulation mode, anti-flicker rendering, region
REM  streaming, debug and extra flags -- then launches X4.exe.
REM
REM  Written with flat goto flow (no nested if-blocks) so that
REM  variables set by a prompt are visible to the very next line.
REM ============================================================

set "SAVE_DIR=%USERPROFILE%\Documents\EgoSoft\X4\save"
set "DEFAULT_IP=192.168.1.16"
set "KEY_FILE=%~dp0x4mp_client.key"
set "EXTRA_FLAGS="
set "X4MP_DEBUG=0"

echo  ==================================================
echo    X4MP Launcher
echo  ==================================================
echo.
echo  Select role:
echo    1) HOST   start a universe on this machine
echo    2) CLIENT join a host by IP
set /p ROLE=Choice [1/2]: 
if "%ROLE%"=="" set "ROLE=1"
if "%ROLE%"=="2" goto client
goto host


REM ============================================================
REM  CLIENT
REM ============================================================
:client
set "ROLE_NAME=client"
set /p X4MP_SERVER_IP=Host IP [%DEFAULT_IP%]: 
if "%X4MP_SERVER_IP%"=="" set "X4MP_SERVER_IP=%DEFAULT_IP%"

REM --- persistent client identity (key + name) ---
if exist "%KEY_FILE%" goto have_identity
echo.
echo  First run: creating a persistent client identity.
set "DEF_NAME=%USERNAME%"
set /p CLIENT_NAME=Player name for this client [%DEF_NAME%]: 
if "%CLIENT_NAME%"=="" set "CLIENT_NAME=%DEF_NAME%"
set "CLIENT_NAME=%CLIENT_NAME: =_%"
for /f %%i in ('powershell -NoProfile -Command "[guid]::NewGuid().ToString()"') do set "NEW_KEY=%%i"
>"%KEY_FILE%" echo key=%NEW_KEY%
>>"%KEY_FILE%" echo name=%CLIENT_NAME%
echo  Created client identity: %KEY_FILE%
:have_identity
for /f "tokens=1,* delims==" %%a in ('findstr /b "key=" "%KEY_FILE%"') do set "X4MP_CLIENT_KEY=%%b"
for /f "tokens=1,* delims==" %%a in ('findstr /b "name=" "%KEY_FILE%"') do set "X4MP_CLIENT_NAME=%%b"
echo.
echo  Client identity: name=%X4MP_CLIENT_NAME% key=%X4MP_CLIENT_KEY%

REM --- which save must match the host ---
echo.
echo  The client MUST load the exact same save as the host.
set /p SAVE_BASE=Save name to use [save_010]: 
if "%SAVE_BASE%"=="" set "SAVE_BASE=save_010"
set "SAVE_BASE=%SAVE_BASE:.xml.gz=%"
set "X4MP_SAVE=%SAVE_BASE%"
set "SAVE_NAME=%SAVE_BASE%.xml.gz"
set "LOCAL_SAVE=%SAVE_DIR%\%SAVE_NAME%"
if exist "%LOCAL_SAVE%" goto save_present
echo.
echo  Save not found locally. Copy it from the host?
echo  (Windows 10/11 ships OpenSSH; you may be asked for the host password)
set /p DO_SCP=Transfer save from host via scp [Y/n]: 
if /i "%DO_SCP%"=="n" goto save_present
set /p REMOTE_SAVE=Full path to the save on the host: 
if "%REMOTE_SAVE%"=="" set "REMOTE_SAVE=%X4MP_SERVER_IP%:%SAVE_DIR%\%SAVE_NAME%"
scp -o ConnectTimeout=10 "%REMOTE_SAVE%" "%LOCAL_SAVE%"
if exist "%LOCAL_SAVE%" goto save_present
echo.
echo  ============================================================
echo   WARN: automatic save transfer failed.
echo   Copy it manually, e.g.:
echo     scp "%REMOTE_SAVE%" "%LOCAL_SAVE%"
echo   or place the save in: %SAVE_DIR%
echo  ============================================================
:save_present
echo  Save to load: %X4MP_SAVE%

REM --- simulation mode (client) ---
echo.
echo  Simulation mode:
echo    1) THIN-CLIENT  ships driven by the host, no local AI  [standard]
echo    2) HYBRID       local sim runs for ships, reconciled to host
set /p SIM_INPUT=Simulation mode [1]: 
if "%SIM_INPUT%"=="2" goto sim_hybrid
set "X4MP_INERT=1"
set "SIM_MODE=thin-client"
echo   -^> THIN-CLIENT mode (X4MP_INERT=1) [standard]
goto sim_done
:sim_hybrid
set "X4MP_INERT=0"
set "SIM_MODE=hybrid"
echo   -^> HYBRID mode (X4MP_INERT=0)
:sim_done
set "X4MP_GLIDE_SPEED=1500"
set "X4MP_GLIDE_MAX=20000"

REM --- anti-flicker rendering (client) ---
echo.
echo  Anti-flicker rendering:
echo    1) Ghost rendering  host-authoritative, suppresses local ships [recommended]
echo    2) Pin + glide      reconcile local ships with per-frame pinning
echo    3) Original         reconcile without per-frame pinning
set /p FLK_INPUT=Anti-flicker mode [1]: 
if "%FLK_INPUT%"=="2" goto flk_pin
if "%FLK_INPUT%"=="3" goto flk_orig
set "X4MP_GHOSTS=1"
set "X4MP_PIN_INTERVAL=1"
if "%SIM_MODE%"=="hybrid" goto flk_switch
echo   -^> Ghost rendering [recommended]
goto flk_done
:flk_switch
set "X4MP_INERT=1"
set "SIM_MODE=thin-client"
echo   -^> Ghost rendering; switched to thin-client
goto flk_done
:flk_pin
set "X4MP_GHOSTS=0"
set "X4MP_PIN_INTERVAL=1"
echo   -^> Pin + glide
goto flk_done
:flk_orig
set "X4MP_GHOSTS=0"
set "X4MP_PIN_INTERVAL=3"
echo   -^> Original reconcile
:flk_done
goto common


REM ============================================================
REM  HOST
REM ============================================================
:host
set "ROLE_NAME=host"
echo.
echo  Host universe source:
echo    1) NEW GAME  choose a gamestart
echo    2) LOAD SAVE continue an existing savegame
set /p HOST_SRC=Choice [1/2]: 
if "%HOST_SRC%"=="" set "HOST_SRC=1"
if "%HOST_SRC%"=="2" goto host_loadsave
goto host_newgame

:host_loadsave
echo.
echo  Available savegames in %SAVE_DIR%:
set /a n=0
for %%f in ("%SAVE_DIR%\*.xml.gz") do call :list_save %%~nxf
echo.
set /p SAVE_BASE=Save name to load [save_010]: 
if "%SAVE_BASE%"=="" set "SAVE_BASE=save_010"
set "SAVE_BASE=%SAVE_BASE:.xml.gz=%"
set "X4MP_SAVE=%SAVE_BASE%"
echo   -^> LOAD save '%X4MP_SAVE%'
goto host_done

:host_newgame
echo.
echo  Available gamestarts:
echo    1) x4ep1_gamestart_boron1      Boron 1
echo    2) x4ep1_gamestart_boron2      Boron 2
echo    3) x4ep1_gamestart_terran1     Terran 1
echo    4) x4ep1_gamestart_terran2     Terran 2
echo    5) x4ep1_gamestart_split1      Split 1
echo    6) x4ep1_gamestart_split2      Split 2
echo    7) x4ep1_gamestart_pirate1     Pirate 1
echo    8) x4ep1_gamestart_pirate2     Pirate 2
echo    9) x4ep1_gamestart_trade       The Young Gun
echo   10) x4ep1_gamestart_fight       The Fighter
echo   11) x4ep1_gamestart_discover    The Explorer
echo   12) x4ep1_gamestart_scientist   The Scientist
echo   13) x4ep1_gamestart_boso        Boso Ta
echo   14) x4ep1_gamestart_hyperion    Hyperion
echo   15) x4ep1_gamestart_workshop    Workshop
echo   16) x4ep1_gamestart_hub         The Hub
echo    C) custom gamestart id
set /p GS=Select gamestart [1]: 
if "%GS%"=="" set "GS=1"
call :pick_gamestart %GS%
echo   -^> NEW game '%X4MP_MODULE%'
goto host_done

:host_done
echo.
echo  Tell each client to connect to this machine's LAN IP.
goto common


REM ============================================================
REM  COMMON OPTIONS
REM ============================================================
:common
echo.
echo  Start mode:
echo    1) IN-GAME MENU  game opens to main menu; click Host/Join Multiplayer
echo    2) AUTO-START    begin hosting/joining immediately on load
set /p START_MODE=Choice [2]: 
if "%START_MODE%"=="" set "START_MODE=2"
if "%START_MODE%"=="2" goto auto_start
set "X4MP_AUTO="
set "START_MODE_DESC=in-game menu"
goto start_done
:auto_start
if "%ROLE_NAME%"=="client" goto auto_client
set "X4MP_AUTO=host"
set "START_MODE_DESC=auto-start"
goto start_done
:auto_client
set "X4MP_AUTO=client"
set "START_MODE_DESC=auto-start"
:start_done

echo.
echo  Extra launch flags:
echo    1) -showfps          2) -nocputhrottle
echo    or type flags directly, e.g. "-showfps -windowed"
set /p FLAG_INPUT=Extra launch options [Enter = none]: 
if "%FLAG_INPUT%"=="" goto flags_done
set "FLAG_INPUT=%FLAG_INPUT:,= %"
for %%t in (%FLAG_INPUT%) do call :add_flag "%%t"
:flags_done

echo.
set /p X4MP_TRANSPORT=Data-stream transport - tcp or udp [tcp]: 
if "%X4MP_TRANSPORT%"=="" set "X4MP_TRANSPORT=tcp"
if /i "%X4MP_TRANSPORT%"=="udp" goto transport_udp
set "X4MP_TRANSPORT=tcp"
goto transport_done
:transport_udp
set "X4MP_TRANSPORT=udp"
:transport_done

echo.
echo  Region streaming (experimental, enable on BOTH sides):
echo    1) ON   pre-sync neighbouring sectors
echo    2) OFF  released behavior [default]
set /p REGION_INPUT=Region streaming [2]: 
if "%REGION_INPUT%"=="1" goto region_on
set "X4MP_REGION=0"
goto region_done
:region_on
set "X4MP_REGION=1"
set /p X4MP_REGION_M=Region radius in meters [120000]: 
if "%X4MP_REGION_M%"=="" set "X4MP_REGION_M=120000"
:region_done

echo.
echo  Net mode:
echo    1) consolidated  one port per transport [recommended]
echo    2) legacy        split ports (UDP 7777 control + 7778 data)
set /p NETMODE=Net mode [1]: 
if "%NETMODE%"=="2" goto net_legacy
set "X4MP_LEGACY_NET=0"
goto net_done
:net_legacy
set "X4MP_LEGACY_NET=1"
:net_done

set /p DBG=Enable verbose debug logging [y/N]: 
if /i "%DBG%"=="y" goto dbg_on
set "X4MP_DEBUG=0"
goto dbg_done
:dbg_on
set "X4MP_DEBUG=1"
:dbg_done
goto defaults


REM ============================================================
REM  SAFE DEFAULTS (tuning; override by editing this file)
REM ============================================================
:defaults
set "X4MP_PORT=7777"
set "X4MP_STREAM_PORT=7778"
if not defined X4MP_MODULE set "X4MP_MODULE=x4ep1_gamestart_boron1"
set "X4MP_DIFFICULTY=easy"
set "X4MP_OBJMODE=cache"
set "X4MP_STREAMSHIPS=0"
set "X4MP_CLEANUP=0"
set "X4MP_STREAMS=0"
set "X4MP_PAUSE=0"
set "X4MP_FULLSIM=0"
set "X4MP_TELEPORT=0"
if not defined X4MP_INERT set "X4MP_INERT=1"
set "X4MP_CONVERGE_GREEDY=1"
set "X4MP_BIND_RADIUS=1000"
set "X4MP_CONVERGE_RADIUS=20000"
set "X4MP_MAX_LAG_M=300"
set "X4MP_UPDATE_HZ=15"
set "X4MP_DELTA_M=0.5"
set "X4MP_HOST_TIMEOUT=30"
set "X4MP_CLIENT_TIMEOUT=15"
set "X4MP_UNIVERSE_TIMEOUT=180"
set "X4MP_RELEVANCE_M=20000"
if not defined X4MP_GHOSTS set "X4MP_GHOSTS=0"
if not defined X4MP_PIN_INTERVAL set "X4MP_PIN_INTERVAL=1"
set "X4MP_FRAME_DIAG_S=5"
set "X4MP_RENDER_INTERVAL=3"
set "X4MP_SMOOTH_TAU=0.12"
set "X4MP_HYBRID_GHOST=1"
set "X4MP_HYBRID_GHOST_M=3000"
set "X4MP_SOFT_PIN_SPEED=3000"
set "X4MP_SOFT_PIN_MIN=50"
set "X4MP_DRIFT_ALERT_M=5"
set "X4MP_DRIFT_VERBOSE_M=1000"
goto summary


REM ============================================================
REM  SUMMARY
REM ============================================================
:summary
echo.
echo  ==================================================
echo    Launch summary
echo  ==================================================
echo    Role       : %ROLE_NAME%
echo    Start mode : %START_MODE_DESC%
if "%ROLE_NAME%"=="client" goto sum_client
goto sum_host
:sum_client
echo    Host IP    : %X4MP_SERVER_IP%
echo    Save       : %X4MP_SAVE%
echo    Player     : %X4MP_CLIENT_NAME%
echo    Sim mode   : %SIM_MODE%
echo    Anti-flick : ghosts=%X4MP_GHOSTS% pin_interval=%X4MP_PIN_INTERVAL%
goto sum_common
:sum_host
if defined X4MP_SAVE goto sum_host_save
echo    Source     : NEW game '%X4MP_MODULE%'
goto sum_common
:sum_host_save
echo    Source     : LOAD save '%X4MP_SAVE%'
:sum_common
echo    Transport  : %X4MP_TRANSPORT%
echo    Net mode   : legacy=%X4MP_LEGACY_NET%
echo    Region     : %X4MP_REGION%
echo    Debug      : %X4MP_DEBUG%
if not "%EXTRA_FLAGS%"=="" echo    Extra flags: %EXTRA_FLAGS%
echo  ==================================================
set /p GO=Start X4 now [Y/n]: 
if /i "%GO%"=="n" goto aborted
echo.
echo  Launching X4.exe -nologo ...
echo.
X4.exe -nologo %EXTRA_FLAGS%
endlocal & goto :eof
:aborted
echo  Aborted.
endlocal & goto :eof


REM ============================================================
REM  SUBROUTINES
REM ============================================================
:pick_gamestart
set "GS_ID=%~1"
if "%GS_ID%"=="1" set "X4MP_MODULE=x4ep1_gamestart_boron1"
if "%GS_ID%"=="2" set "X4MP_MODULE=x4ep1_gamestart_boron2"
if "%GS_ID%"=="3" set "X4MP_MODULE=x4ep1_gamestart_terran1"
if "%GS_ID%"=="4" set "X4MP_MODULE=x4ep1_gamestart_terran2"
if "%GS_ID%"=="5" set "X4MP_MODULE=x4ep1_gamestart_split1"
if "%GS_ID%"=="6" set "X4MP_MODULE=x4ep1_gamestart_split2"
if "%GS_ID%"=="7" set "X4MP_MODULE=x4ep1_gamestart_pirate1"
if "%GS_ID%"=="8" set "X4MP_MODULE=x4ep1_gamestart_pirate2"
if "%GS_ID%"=="9" set "X4MP_MODULE=x4ep1_gamestart_trade"
if "%GS_ID%"=="10" set "X4MP_MODULE=x4ep1_gamestart_fight"
if "%GS_ID%"=="11" set "X4MP_MODULE=x4ep1_gamestart_discover"
if "%GS_ID%"=="12" set "X4MP_MODULE=x4ep1_gamestart_scientist"
if "%GS_ID%"=="13" set "X4MP_MODULE=x4ep1_gamestart_boso"
if "%GS_ID%"=="14" set "X4MP_MODULE=x4ep1_gamestart_hyperion"
if "%GS_ID%"=="15" set "X4MP_MODULE=x4ep1_gamestart_workshop"
if "%GS_ID%"=="16" set "X4MP_MODULE=x4ep1_gamestart_hub"
if not defined X4MP_MODULE set "X4MP_MODULE=%GS_ID%"
if not defined X4MP_MODULE set "X4MP_MODULE=x4ep1_gamestart_boron1"
goto :eof

:add_flag
if "%~1"=="" goto :eof
if "%~1"=="1" set "EXTRA_FLAGS=%EXTRA_FLAGS% -showfps" & goto :eof
if "%~1"=="2" set "EXTRA_FLAGS=%EXTRA_FLAGS% -nocputhrottle" & goto :eof
REM any other token that starts with a dash is passed through as-is
for %%c in ("%~1") do if "%%~c1"=="-" set "EXTRA_FLAGS=%EXTRA_FLAGS% %~1"
goto :eof

:list_save
set /a n+=1
echo    %n%) %~1
goto :eof
