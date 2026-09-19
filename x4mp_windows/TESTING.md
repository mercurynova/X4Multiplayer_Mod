# X4MP on Windows — two-machine bring-up checklist

Status as of 2026-09-18: a Windows **host** has been verified to start, bind
TCP 7778 and simulate (92k ships streamed, `heartbeat — HOST active`) on a
single machine. **No client has ever connected to it.** Everything below the
"First session" heading is therefore untested, and the first real run should be
treated as debugging, not as play.

Full evidence and the defect analysis are in the `2026-09-18` entry of
[`../STATE.md`](../STATE.md).

---

## Per machine (do this on BOTH)

- [ ] **Same X4 build** on both machines (verified on 9.00 / 611726). Check the
      version in the bottom corner of the start menu — a mismatch will look like
      a sync bug later.
- [ ] **Same extension build** — copy the same `x4mp_windows/` package to both.
      Do not mix a newer `x4mp.dll` on one side with an older one on the other.
- [ ] **Vanilla install** plus the three x4mp extensions and your `ego_dlc_*`
      folders. Nothing else. See the README's "RECOMMENDED — run multiplayer on
      an UNMODDED copy" section for how to keep your modded install as well.
- [ ] **VC++ 2015-2022 Redistributable (x64)** installed
      (`https://aka.ms/vs/17/release/vc_redist.x64.exe`) — x4native needs it.
- [ ] **`steam_appid.txt`** containing `392160` next to `X4.exe`. `x4mp.bat`
      creates this for you and says so in its launch summary. Without it X4
      relaunches itself through Steam and every `X4MP_*` setting is discarded.
- [ ] **Extensions enabled** in Options → Extensions: `x4native`, `x4mp`,
      `x4mp_stream`. Restart the game after enabling.
- [ ] **Only one X4 instance per machine.**

## Host machine only

- [ ] **Firewall:** allow inbound **TCP 7778** from the local network. X4 should
      prompt on first listen — if that prompt was dismissed once, Windows
      remembers the "block" answer and the client will simply time out. Check
      with `netstat -ano | findstr 7778` while hosting: you want `LISTENING`.
- [ ] **Know your LAN IP** (`ipconfig`) — the client needs it.

## The savegame (the part that trips people up first)

Both machines must load the **exact same save file**. A consequence that is easy
to miss:

> **You cannot host a NEW GAME and have a client join it** — the client would
> need a save that does not exist yet.

So the first session goes:

1. Host starts a new game once (any gamestart), plays far enough to be out of
   the intro, and **saves**.
2. That save file is copied to the client, into
   `%USERPROFILE%\Documents\Egosoft\X4\<account id>\save\`.
3. Both sides then launch with that save selected.

`x4mp.bat` offers to fetch the save over `scp`. Note that Windows ships the
OpenSSH **client** by default but **not the server** — to pull a save *from* a
Windows host you must first install it there (Settings → Optional features →
OpenSSH Server) and start the `sshd` service. A network share or a USB stick is
an equally valid transfer; only the bytes matter.

## First session

Start the host first, then the client.

- [ ] **Host:** run `x4mp.bat` → role `1` → `2` LOAD SAVE → pick the save →
      **start mode `2` AUTO-START**.
- [ ] **Client:** run `x4mp.bat` → role `2` → host IP → same save name →
      **start mode `2` AUTO-START**.

> **Use AUTO-START, not the in-game menu.** The "Host Multiplayer" /
> "Join Multiplayer" menu entries currently lose their socket when the universe
> loads (x4native re-discovers and shuts down the extensions; the reloaded
> extension does not remember the request). Auto-start survives because it
> re-reads `X4MP_AUTO` from the environment on every init. See STATE.md.

### What to check, in order

1. **Host is listening** — `netstat -ano | findstr 7778` shows `LISTENING`, and
   the host log has `x4mp: net: HOST listening on TCP port 7778`.
2. **Host is simulating** — `HOST refreshed ALL ships: <n>` with n in the tens of
   thousands, and `heartbeat — HOST active`.
3. **Client connected** — the host log should show the client; the client log
   should stop retrying. `netstat` on the host shows an `ESTABLISHED` 7778
   connection from the client's IP.
4. **Both see the same universe** — fly the client and watch the host: the
   client's ship should appear as a ghost, and vice versa.
5. **Ships agree** — pick a busy sector and compare; the client log's `[FLK]`
   line should show `drift=0` in ghost-rendering mode.

### Logs (Windows)

The launcher's log option does **not** apply on Windows — `X4MP_LOG` is not read
by this build. The mod writes its own logs to:

```
%USERPROFILE%\Documents\Egosoft\X4\<account id>\x4native\
    x4native.log                  core + both extensions (start here)
    x4mp\x4mp.log                 host/client
    x4mp_stream\x4mp_stream.log   client reconciliation
```

X4's own log needs `-debug all -logfile <name>.txt` and lands in the same
per-account folder.

## Known not to work on Windows 9.00

- **Combat kills, boarding captures, boarding inert-exemptions.** x4native
  cannot resolve the MD event hook (`EventQueue_InsertOrDispatch`) for build
  900, and all of these ride on MD events. Expect them to be silently absent —
  this is not something the mod can work around.
- **The in-game menu host/join path** — see above.
- `X4_FrameTick` is also unresolved on this build, which may affect per-frame
  pinning.

Realistic expectation for a first clean session: **shared player positions,
ships and stations** (the ✅ core features) — and nothing that depends on MD
events.
