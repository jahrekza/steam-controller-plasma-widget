import sys, os

dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/hidraw0"
n = int(sys.argv[2]) if len(sys.argv) > 2 else 5000
target_id = int(sys.argv[3], 16) if len(sys.argv) > 3 else 0x43

fd = os.open(dev, os.O_RDONLY)

count = 0
for i in range(n):
    data = os.read(fd, 64)
    if data[0] == target_id:
        count += 1
        print(f"#{count}: {data.hex()}")

os.close(fd)
print(f"\nTotal 0x{target_id:02x} reports out of {n}: {count}")
