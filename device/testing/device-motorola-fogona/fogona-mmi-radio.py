#!/usr/bin/env python3
"""Tell the modem this handset's radio SKU, from ABL's own detection.

WHY THIS EXISTS
---------------
Motorola's modem firmware takes its RF hardware id from a unit info block the
AP publishes in SMEM before the modem boots (the kernel's mmi-unit-info
driver). It needs the device name and the radio SKU; without the SKU it
resolves RF hardware id 0 and never brings RF up, while otherwise booting.

fogona ships in two radio variants, ATT and RET. ABL tells them apart from a
hardware id and passes the result to its own kernels as androidboot.radio;
a mainline kernel never sees it (our ABL -> U-Boot -> systemd-boot chain
drops it, and the built-in DTB replaces ABL's /chosen). So the driver takes
the SKU from userspace, and this reads it where ABL keeps its result.

WHERE THE SKU COMES FROM
------------------------
Motorola's `hw` partition, in the same record format as `utags` (see
fogona-bt-addr): a `radio` record holding the effective value, next to
`radio/.auto` ("key=hwid;index=2;map=1:ATT,2:RET", how ABL detects it),
`radio/.range` ("ATT,RET") and `radio/.cmdline` ("androidboot.", how ABL
passes it on). The value is checked against `radio/.range`, so a damaged
partition fails loudly instead of handing the modem a wrong SKU.

Record layout (all fields packed):
    name[32]     NUL-padded ASCII
    size         u32 big-endian, payload length including its NUL
    flags[8]
    payload      `size` bytes, NUL-terminated ASCII, padded to 4 bytes

HOW IT IS APPLIED
-----------------
Written to the driver's `radio` attribute, which publishes the block. The
unit runs before rmtfs, and rmtfs is what starts the modem (`-s`), so the
block is in place before the modem's RF init reads it.
"""

import struct
import sys

HW = "/dev/disk/by-partlabel/hw"
ATTR = "/sys/bus/platform/devices/mmi-unit-info/radio"
NAME_LEN = 32
PAYLOAD_OFFSET = 44
MAX_PAYLOAD = 4096
READ_LIMIT = 1 << 20


def log(msg):
    print("fogona-mmi-radio: %s" % msg, file=sys.stderr)


def records(blob):
    """Yield (name, value) for each record, walking the partition in order."""
    at = 0
    while at + PAYLOAD_OFFSET <= len(blob):
        name = blob[at:at + NAME_LEN].split(b"\0", 1)[0]
        if not name or not all(0x20 <= c < 0x7f for c in name):
            return
        (size,) = struct.unpack_from(">I", blob, at + NAME_LEN)
        if size > MAX_PAYLOAD:
            return
        payload = blob[at + PAYLOAD_OFFSET:at + PAYLOAD_OFFSET + size]
        yield (name.decode("ascii"),
               payload.split(b"\0", 1)[0].decode("ascii", "replace"))
        at += PAYLOAD_OFFSET + ((size + 3) & ~3)


def main():
    try:
        with open(HW, "rb") as f:
            tags = dict(records(f.read(READ_LIMIT)))
    except OSError as e:
        log("%s: %s" % (HW, e))
        return 1

    radio = tags.get("radio")
    allowed = [r for r in tags.get("radio/.range", "").split(",") if r]
    if not radio or radio not in allowed:
        log("no usable radio record (radio=%r, range=%r)" % (radio, allowed))
        return 1

    try:
        with open(ATTR, "w") as f:
            f.write(radio)
    except OSError as e:
        log("%s: %s" % (ATTR, e))
        return 1

    log("published radio %s" % radio)
    return 0


if __name__ == "__main__":
    sys.exit(main())
