================================================================
 X4MP for LINUX -- install & usage
================================================================

WHAT THIS IS
  X4 Multiplayer: run one X4: Foundations as a HOST and connect other
  machines as CLIENTS over your LAN, without Steam. This folder holds the
  three extensions you need plus the launcher scripts.

CONTENTS
  extensions/x4native/      base loader (required dependency)
  extensions/x4mp/          main multiplayer host/client
  extensions/x4mp_stream/   client-side stream smoothing
  x4mp_launcher.sh          interactive launcher (recommended)
  x4mp_run.sh               env-driven launcher (automation)

REQUIREMENTS
  * Linux x86-64, X4: Foundations installed
  * libcurl / standard glibc (the .so files are built against them)

INSTALL
  1. Copy the three extension folders into your game's extensions dir:
         cp -r extensions/*  "/path/to/X4 Foundations/extensions/"
  2. Start X4 and open the extension manager (Options -> Extensions).
  3. Enable:  x4native,  x4mp,  x4mp_stream
  4. Restart the game.

LAUNCHING
  Point the launcher at your game dir, then run it:
      export X4MP_GAME_DIR="/path/to/X4 Foundations"
      ./x4mp_launcher.sh
  (Or place x4mp_launcher.sh in the folder that contains "X4 Foundations".)

  The launcher walks you through: role (host/client), universe or save,
  transport (tcp/udp), net mode, region streaming, simulation mode,
  anti-flicker rendering, debug logging, and extra X4 flags.

HOST vs CLIENT
  * HOST:   start a universe (new gamestart or load a save). It listens
            on the LAN; tell clients your IP.
  * CLIENT: enter the host IP and the SAME save the host is using. The
            launcher tries to scp the save from the host automatically;
            if that fails, copy it manually into your local save dir.

FIREWALL
  Allow incoming TCP/UDP on the game ports (default 7777/7778) on the host:
      sudo ufw allow 7777:7778/tcp
      sudo ufw allow 7777:7778/udp

TROUBLESHOOTING
  * Enable "verbose debug logging" in the launcher (X4MP_DEBUG=1) and watch
    the on-disk log for "x4mp: init" and socket messages.
  * Make sure BOTH machines run the SAME extension build/version.
