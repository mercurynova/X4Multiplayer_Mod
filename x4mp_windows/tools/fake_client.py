#!/usr/bin/env python3
"""
x4mp fake client -- exercise a running x4mp HOST without a second copy of X4.

It speaks the same consolidated-TCP protocol a real client uses:

    client -> JOIN x4mp <key> <name>
    host   -> WELCOME <id>
    client -> PLAYER <x> <y> <z> <yaw> <pitch> <roll> <ship_macro> [sector_macro]
    host   -> FULL / OBJ / STA / PLAYER / KILL / CARGO / CAPTURE / TRADE ...

That covers the host half of a session: accept, client registration, ghost
faction assignment, sector selection and the object stream. It does NOT
exercise any client-side logic (binding, pinning, ghost rendering,
reconciliation) -- only a real X4 client can do that.

Usage:
    python fake_client.py                         # localhost, 30 s
    python fake_client.py --host 192.168.1.16 --duration 60
    python fake_client.py --sector cluster_01_sector001_macro --verbose

Exit status is 0 when the host welcomed us AND streamed at least one object.
"""

import argparse
import collections
import socket
import sys
import time
import uuid

DEFAULT_MACRO = "ship_arg_s_scout_01_a_macro"


def parse_args():
    p = argparse.ArgumentParser(description="Synthetic x4mp client for host-side testing.")
    p.add_argument("--host", default="127.0.0.1", help="host IP (default: 127.0.0.1)")
    p.add_argument("--port", type=int, default=7778, help="consolidated TCP port (default: 7778)")
    p.add_argument("--duration", type=float, default=30.0, help="seconds to stay connected (default: 30)")
    p.add_argument("--name", default="fakeclient", help="player name sent in JOIN")
    p.add_argument("--key", default=None, help="persistent client key (default: random)")
    p.add_argument("--macro", default=DEFAULT_MACRO, help="ship macro the host should ghost-spawn")
    p.add_argument("--sector", default=None, help="sector macro to claim (default: let the host pick)")
    p.add_argument("--pos", default="0,0,0", help="x,y,z in metres (default: 0,0,0)")
    p.add_argument("--rate", type=float, default=2.0, help="PLAYER updates per second (default: 2)")
    p.add_argument("--orbit", type=float, default=0.0, help="metres/s of synthetic movement (default: 0 = stand still)")
    p.add_argument("--verbose", action="store_true", help="print every line received")
    return p.parse_args()


def main():
    a = parse_args()
    try:
        x, y, z = (float(v) for v in a.pos.split(","))
    except ValueError:
        print("--pos must look like 12000,0,-3400", file=sys.stderr)
        return 2

    key = a.key or uuid.uuid4().hex[:16]
    deadline = time.time() + a.duration

    print(f"connecting to {a.host}:{a.port} ...")
    try:
        sock = socket.create_connection((a.host, a.port), timeout=10)
    except OSError as e:
        print(f"FAIL: could not connect: {e}")
        print("      is the host actually listening?  netstat -ano | findstr 7778")
        return 1
    sock.settimeout(0.25)
    print(f"connected. JOIN as name={a.name} key={key}")
    sock.sendall(f"JOIN x4mp {key} {a.name}\n".encode())

    counts = collections.Counter()
    samples = {}
    bytes_by_verb = collections.Counter()
    total_rx = 0
    rx_window = []
    obj_ids = set()
    welcome_id = None
    buf = b""
    next_player = 0.0
    players_sent = 0
    t0 = time.time()

    while time.time() < deadline:
        now = time.time()
        if now >= next_player:
            next_player = now + (1.0 / a.rate if a.rate > 0 else 1.0)
            if a.orbit:
                x += a.orbit / max(a.rate, 0.001)
            line = (f"PLAYER {x:.3f} {y:.3f} {z:.3f} 0.000 0.000 0.000 {a.macro}"
                    + (f" {a.sector}" if a.sector else "") + "\n")
            try:
                sock.sendall(line.encode())
                players_sent += 1
            except OSError as e:
                print(f"send failed after {players_sent} PLAYER lines: {e}")
                break

        try:
            chunk = sock.recv(65536)
            if not chunk:
                print("host closed the connection")
                break
            buf += chunk
            total_rx += len(chunk)
            rx_window.append((time.time(), len(chunk)))
        except socket.timeout:
            continue
        except OSError as e:
            print(f"recv failed: {e}")
            break

        while b"\n" in buf:
            raw, buf = buf.split(b"\n", 1)
            line = raw.decode("utf-8", "replace").strip()
            if not line:
                continue
            verb = line.split(" ", 1)[0]
            counts[verb] += 1
            bytes_by_verb[verb] += len(raw) + 1
            samples.setdefault(verb, line)
            if a.verbose:
                print(f"  < {line[:160]}")
            if verb == "WELCOME" and welcome_id is None:
                parts = line.split()
                welcome_id = parts[1] if len(parts) > 1 else "?"
                print(f"host welcomed us as client id {welcome_id}")
            elif verb == "OBJ":
                parts = line.split()
                if len(parts) > 1:
                    obj_ids.add(parts[1])
            elif verb == "PING":
                try:
                    sock.sendall(b"PONG\n")
                except OSError:
                    pass

    elapsed = time.time() - t0
    try:
        sock.close()
    except OSError:
        pass

    print()
    print("=" * 58)
    print(f" {elapsed:.0f}s connected, {players_sent} PLAYER lines sent")
    print("=" * 58)
    if not counts:
        print(" host sent NOTHING")
    for verb, n in counts.most_common():
        print(f"   {verb:<12} {n:>7}  {bytes_by_verb[verb]/1024.0:>9.1f} KB  avg {bytes_by_verb[verb]//max(n,1):>4} B   e.g. {samples[verb][:55]}")
    if obj_ids:
        print(f"   distinct object ids streamed: {len(obj_ids)}")
    if elapsed > 0:
        kbs = total_rx / 1024.0 / elapsed
        print()
        print(f"   BANDWIDTH  {total_rx/1048576.0:.1f} MB in {elapsed:.0f}s  =  {kbs:,.0f} KB/s  =  {kbs*8/1024:.2f} Mbit/s  (ONE client)")
        if rx_window:
            t0w = rx_window[0][0]
            buckets = collections.Counter()
            for ts, nbytes in rx_window:
                buckets[int(ts - t0w)] += nbytes
            peak = max(buckets.values()) / 1024.0
            print(f"   PEAK       {peak:,.0f} KB/s  =  {peak*8/1024:.2f} Mbit/s in the busiest second")
    print()

    ok_welcome = welcome_id is not None
    ok_stream = bool(obj_ids) or counts.get("FULL", 0) > 0
    print(f" handshake (WELCOME):   {'PASS' if ok_welcome else 'FAIL'}")
    print(f" object stream:         {'PASS' if ok_stream else 'FAIL'}")
    if ok_welcome and not ok_stream:
        print()
        print(" The host registered us but streamed no objects. Usual causes:")
        print("   * the host is still at the main menu / loading -- it can only")
        print("     stream once its universe exists;")
        print("   * the sector macro we claimed is unknown to the host and its")
        print("     own player sector has nothing in it. Try --sector with a")
        print("     macro from the host's universe, or omit it.")
    return 0 if (ok_welcome and ok_stream) else 1


if __name__ == "__main__":
    sys.exit(main())
