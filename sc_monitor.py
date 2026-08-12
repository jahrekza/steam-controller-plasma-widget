import sys, os

dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/hidraw0"
n = int(sys.argv[2]) if len(sys.argv) > 2 else 200

fd = os.open(dev, os.O_RDONLY)

samples = []
for i in range(n):
    data = os.read(fd, 64)
    samples.append(data)

os.close(fd)

# group by report ID (first byte)
from collections import defaultdict
groups = defaultdict(list)
for s in samples:
    groups[s[0]].append(s)

for rid, group in groups.items():
    print(f"\n=== Report ID 0x{rid:02x}, count={len(group)} ===")
    length = len(group[0])
    for byte_idx in range(length):
        vals = set(s[byte_idx] for s in group)
        if len(vals) == 1:
            print(f"  byte[{byte_idx:2d}] = CONST 0x{group[0][byte_idx]:02x} ({group[0][byte_idx]})")
        else:
            print(f"  byte[{byte_idx:2d}] = VARIES {sorted(vals)[:5]}{'...' if len(vals)>5 else ''} (range {min(vals)}-{max(vals)})")
