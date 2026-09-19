================================================================
 X4MP for WINDOWS -- install & usage
================================================================

WHAT THIS IS
  X4 Multiplayer: run one X4: Foundations as a HOST and connect other
  machines as CLIENTS over your LAN, without Steam. This folder holds the
  three extensions (Windows .dll builds) plus an interactive launcher.

CONTENTS
  extensions\x4native\      base loader (required dependency)
  extensions\x4mp\          main multiplayer host/client
  extensions\x4mp_stream\   client-side stream smoothing
  x4mp.bat                  interactive launcher (double-click to run)

REQUIREMENTS
  * Windows 10 or 11 (64-bit)
  * X4: Foundations installed
  * Microsoft Visual C++ 2015-2022 Redistributable (x64). The x4mp and
    x4mp_stream DLLs are self-contained, but x4native_64.dll /
    x4native_core.dll import MSVCP140.dll and VCRUNTIME140.dll. Without
    the redist the extension silently fails to load.
    Get it from: https://aka.ms/vs/17/release/vc_redist.x64.exe

INSTALL
  1. Copy the three extension folders into your game's extensions dir:
         extensions\*   ->   "C:\...\X4 Foundations\extensions\"
  2. Start X4 and open the extension manager (Options -> Extensions).
  3. Enable:  x4native,  x4mp,  x4mp_stream
  4. Restart the game.

LAUNCHING
  Double-click x4mp.bat (it sits next to X4.exe). It walks you through:
  role (host/client), universe or save, transport (tcp/udp), net mode,
  region streaming, simulation mode, anti-flicker rendering, debug
  logging, and extra X4 flags -- then starts X4.exe.

  Savegames are read from %USERPROFILE%\Documents\Egosoft\X4\<account
  id>\save -- the launcher finds that folder itself; set X4MP_SAVE_DIR to
  override it.

  Your client identity is stored in x4mp_client.key next to the launcher
  (created on first client run). Keep it if you want the host to remember
  you across sessions.

HOST vs CLIENT
  * HOST:   start a universe (new gamestart or load a save). It listens
            on the LAN; tell clients your IP.
  * CLIENT: enter the host IP and the SAME save the host is using. The
            launcher tries to scp the save from the host automatically
            (Windows 10/11 ships OpenSSH); if that fails, copy the save
            manually into your local save dir.

FIREWALL  (important -- the #1 cause of "can't connect")
  Windows Firewall blocks LAN games by default. When X4.exe starts it
  should pop up a prompt -- choose "Allow access" for both Private and
  Public networks. Or add it manually:
      Windows Defender Firewall -> Allow an app -> X4.exe -> allow on
      private AND public networks.
  Also allow the ports (default 7777/7778, tcp and udp).

TROUBLESHOOTING
  * Make sure BOTH machines run the SAME extension build/version.
  * Enable "verbose debug logging" in the launcher and watch the console
    for "x4mp: init" and socket messages.
  * If the client connects but objects flicker/desync, try the
    anti-flicker "Ghost rendering" option (recommended) and make sure
    region streaming is set the SAME on both sides.
