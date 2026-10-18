#!/bin/sh
# The last step before the switch to the real system: keep the stick, which
# holds the image's backing file, reachable from it at /mnt/nura-stick, for
# mobis-g5w-logs. (Mounts in the initramfs are not carried over otherwise.)
STICK=/run/nura-stick
# The initramfs's kernel log copier (nura-loop.sh) is done: its last copy stays.
[ -f /run/nura-dmesg.pid ] && kill "$(cat /run/nura-dmesg.pid)" 2>/dev/null
if grep -q " $STICK " /proc/mounts; then
	mkdir -p /sysroot/mnt/nura-stick
	mount --move "$STICK" /sysroot/mnt/nura-stick ||
		echo "nura: could not move the stick into the system"
fi
