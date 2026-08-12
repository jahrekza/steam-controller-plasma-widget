import fcntl, struct, sys, os

HIDIOCGRDESCSIZE = 0x80044801
HIDIOCGRDESC = 0x90044802
HIDIOCGRAWINFO = 0x80084803

dev = sys.argv[1] if len(sys.argv) > 1 else "/dev/hidraw0"
fd = os.open(dev, os.O_RDWR)

size = struct.unpack("i", fcntl.ioctl(fd, HIDIOCGRDESCSIZE, b"\x00"*4))[0]
print(f"Descriptor size: {size}")

# struct hidraw_report_descriptor { __u32 size; __u8 value[4096]; }
buf = bytearray(struct.pack("I", size) + b"\x00"*4096)
fcntl.ioctl(fd, HIDIOCGRDESC, buf, True)
desc = bytes(buf[4:4+size])
print("Descriptor hex:")
print(desc.hex())

info = bytearray(8)
fcntl.ioctl(fd, HIDIOCGRAWINFO, info, True)
bustype, vendor, product = struct.unpack("ihh", info)
print(f"Bus: {bustype}, Vendor: {vendor:04x}, Product: {product:04x}")

os.close(fd)
