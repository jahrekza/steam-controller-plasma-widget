#!/usr/bin/env python3
"""
Monitors charging progress via hidraw (Steam Controller 2, VID 28de:1304).
Auto-finds device, reconnects on I/O errors.
"""
import os, sys, time, select, fcntl, struct
from datetime import datetime

SC_VID      = 0x28de
SC_PID      = 0x1304
MAX_SECONDS = 3 * 3600
LOG_FILE    = sys.argv[1] if len(sys.argv) > 1 else \
    f"sc_logs/sc_charging_{datetime.now().strftime('%Y%m%d_%H%M')}.txt"

os.makedirs("sc_logs", exist_ok=True)

def log(msg, f):
    line = f"[{datetime.now().strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    f.write(line + "\n")
    f.flush()

def find_device():
    for i in range(20):
        dev = f"/dev/hidraw{i}"
        try:
            fd = os.open(dev, os.O_RDWR)
            buf = bytearray(8)
            fcntl.ioctl(fd, 0x80084803, buf, True)
            os.close(fd)
            _, vendor, product = struct.unpack("ihh", bytes(buf))
            if vendor == SC_VID and product == SC_PID:
                fd2 = os.open(dev, os.O_RDONLY | os.O_NONBLOCK)
                live = bool(select.select([fd2], [], [], 0.3)[0])
                os.close(fd2)
                if live:
                    return dev
        except Exception:
            pass
    return None

start    = time.time()
prev_7b  = None
prev_43  = None
last_7b  = 0

mode = "a" if os.path.exists(LOG_FILE) else "w"
with open(LOG_FILE, mode) as f:
    log(f"{'='*20} RESTART {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} {'='*20}", f)

    while True:
        elapsed = time.time() - start
        if elapsed > MAX_SECONDS:
            log("KONIEC — limit 3h", f)
            break

        elapsed_str = f"{int(elapsed//3600):02d}:{int((elapsed%3600)//60):02d}:{int(elapsed%60):02d}"

        dev = find_device()
        if not dev:
            log(f"[{elapsed_str}] Brak urządzenia — czekam (pad na pucku?)", f)
            time.sleep(10)
            continue

        log(f"[{elapsed_str}] Połączono: {dev}", f)
        try:
            fd = os.open(dev, os.O_RDONLY)
            silent = False
            while True:
                elapsed = time.time() - start
                elapsed_str = f"{int(elapsed//3600):02d}:{int((elapsed%3600)//60):02d}:{int(elapsed%60):02d}"

                r, _, _ = select.select([fd], [], [], 5.0)
                if not r:
                    if not silent:
                        log(f"[{elapsed_str}] Brak danych — pad na pucku lub uśpiony", f)
                        silent = True
                    continue
                silent = False

                data = os.read(fd, 64)

                if data[0] == 0x7b and len(data) >= 12:
                    b9, b11 = data[9], data[11]
                    changed = (b11 != prev_7b)
                    if changed or (time.time() - last_7b) >= 60:
                        msg = f"[{elapsed_str}] 0x7b | byte[9]={b9:3d}(0x{b9:02x}) byte[11]={b11:3d}(0x{b11:02x})"
                        if changed and prev_7b is not None:
                            msg += f"  {'▲' if b11>prev_7b else '▼'}{b11-prev_7b:+d} (było {prev_7b})"
                        log(msg, f)
                        prev_7b  = b11
                        last_7b  = time.time()

                elif data[0] == 0x43 and len(data) >= 15:
                    b13, b14 = data[13], data[14]
                    if b13 != prev_43:
                        log(f"[{elapsed_str}] 0x43 | byte[13]={b13:3d}(0x{b13:02x}) byte[14]={b14:3d}(0x{b14:02x})  (było {prev_43})", f)
                        prev_43 = b13

        except OSError as e:
            log(f"[{elapsed_str}] I/O error: {e} — szukam urządzenia ponownie", f)
        finally:
            try: os.close(fd)
            except: pass
        time.sleep(3)

    log("Monitorowanie zakończone.", f)
