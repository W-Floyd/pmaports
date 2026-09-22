#!/usr/bin/env python3
"""Give the Bluetooth controller this handset's own address, from `utags`.

WHY THIS EXISTS
---------------
WCN3988 has no per-device Bluetooth address of its own. The address it reports
after firmware download is whatever the NVM file carried -- on this handset
`qca/apnv11.bin` out of the `bluetooth` partition, which every fogona ships
identically. `hci_qca` knows this: qca_check_bdaddr() compares the controller's
address against the one it parsed out of that NVM file, and when they match it
sets HCI_QUIRK_USE_BDADDR_PROPERTY, meaning "this address is a default, get the
real one from the device tree".

We have no such property -- a DTS literal would pin one handset's address into
a tree meant to boot any fogona -- so hci_dev_setup_sync() marks the
controller HCI_UNCONFIGURED. BlueZ hides unconfigured controllers, which is why
`bluetoothctl` reports "No default controller available" even though the
firmware loaded and HCI is answering.

WHERE THE ADDRESS COMES FROM
----------------------------
Motorola's `utags` partition -- the same factory store ABL reads to produce
`androidboot.btmacaddr` on a stock boot. It holds a `bt_mac:str` record whose
payload is the address as ASCII, with `wifi_mac:str` (the WLAN and P2P pair)
next to it. `utagsBackup` is an identical second copy.

Reading it here, on the handset, is what makes this portable: nothing is baked
in, a different unit gets its own, and a reflash cannot lose it.

Record layout, derived from the partition (all fields packed):

    name[32]     NUL-padded ASCII, e.g. "bt_mac:str"
    size         u32 big-endian, payload length including its NUL
    flags[8]
    payload      `size` bytes, NUL-terminated ASCII

HOW IT IS APPLIED
-----------------
`btmgmt public-addr`, which is the mgmt-API call for exactly this case, wrapped
in the power-off/power-on dance that postmarketOS's own `bootmac` uses for
SDM845 devices. The `yes |` is bootmac's workaround too -- btmgmt wants a
terminal and hangs without it (bootmac issue #3).

Setting the address clears HCI_UNCONFIGURED: the kernel emits
MGMT_EV_UNCONF_INDEX_REMOVED followed by an ordinary index-added, and BlueZ
then picks the controller up as usual. The unit runs Before=bluetooth.service
so bluetoothd never sees the unconfigured state at all.

The alternative, and the more native one, is a `local-bd-address` property
filled in by the bootloader -- U-Boot does this for another Qualcomm board in
board/qualcomm/dragonboard410c.c, and upstream DTS files commit a zeroed
placeholder for the bootloader to overwrite. That needs the fixup to survive
our U-Boot -> EFI -> systemd-boot handover, which is untested; see
/repo/investigations/bluetooth.md.
"""

import re
import struct
import subprocess
import sys

UTAGS = ("/dev/disk/by-partlabel/utags", "/dev/disk/by-partlabel/utagsBackup")
TAG_NAME = b"bt_mac:str\0"
SIZE_OFFSET = 32
PAYLOAD_OFFSET = 44
MAX_PAYLOAD = 64
READ_LIMIT = 1 << 20

MAC_RE = re.compile(r"^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$")


def log(msg):
    print("fogona-bt-addr: %s" % msg, file=sys.stderr)


def read_bt_mac(path):
    with open(path, "rb") as f:
        blob = f.read(READ_LIMIT)

    at = blob.find(TAG_NAME)
    if at < 0:
        return None

    (size,) = struct.unpack_from(">I", blob, at + SIZE_OFFSET)
    if not 0 < size <= MAX_PAYLOAD:
        log("%s: bt_mac payload length %d out of range" % (path, size))
        return None

    payload = blob[at + PAYLOAD_OFFSET:at + PAYLOAD_OFFSET + size]
    return payload.split(b"\0", 1)[0].decode("ascii", "replace")


def usable(addr):
    """Reject anything that would leave the controller worse off than unset."""
    if not addr or not MAC_RE.match(addr):
        return False
    first = int(addr[0:2], 16)
    if first & 1:  # multicast bit -- never a valid device address
        return False
    octets = [int(x, 16) for x in addr.split(":")]
    return any(octets) and not all(o == 0xFF for o in octets)


def btmgmt(index, *args):
    # `yes |` per bootmac: btmgmt expects a terminal and otherwise hangs.
    cmd = "yes | btmgmt -i %s %s" % (index, " ".join(args))
    return subprocess.run(["sh", "-c", cmd], capture_output=True, text=True)


def current_addr(index):
    out = btmgmt(index, "info").stdout
    found = re.search(r"addr\s+(([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2})", out)
    return found.group(1).upper() if found else None


def main():
    index = sys.argv[1] if len(sys.argv) > 1 else "hci0"
    if not re.match(r"^hci[0-9]+$", index):
        log("refusing bad controller name %r" % index)
        return 1

    addr = None
    for path in UTAGS:
        try:
            addr = read_bt_mac(path)
        except OSError as e:
            log("%s: %s" % (path, e))
            continue
        if usable(addr):
            log("read %s from %s" % (addr, path))
            break
        if addr is not None:
            log("%s: unusable bt_mac %r" % (path, addr))
        addr = None

    if addr is None:
        # Deliberately not falling back to a generated address: postmarketOS
        # ships `bootmac` for handsets that genuinely have none, and silently
        # inventing one here would hide a broken/erased utags partition.
        log("no usable bt_mac utag; leaving %s unconfigured" % index)
        return 1

    addr = addr.upper()
    if current_addr(index) == addr:
        log("%s already set to %s" % (index, addr))
        return 0

    btmgmt(index, "power", "off")
    done = btmgmt(index, "public-addr", addr)
    if done.returncode != 0:
        log("btmgmt public-addr failed: %s" % (done.stderr or done.stdout).strip())
        return 1

    # Setting the address re-registers the controller, so power-on is a
    # separate transaction; bluetoothd turns it on anyway once it adopts it.
    subprocess.run(["rfkill", "unblock", "bluetooth"], check=False)
    btmgmt(index, "power", "on")

    log("%s set to %s" % (index, addr))
    return 0


if __name__ == "__main__":
    sys.exit(main())
