#!/bin/sh
# The unit has no console and no network of its own to read from, and what its
# system logs is lost when it resets. So the logs of this boot go to the stick
# (at /mnt/nura-stick, from the initramfs's hook), where they can be read from
# the phone when it is moved there, and again every 20 seconds.
D=/mnt/nura-stick/nura-logs
mkdir -p "$D" 2>/dev/null || exit 0
while :; do
	journalctl -b --no-pager > "$D/journal.txt" 2>&1
	dmesg > "$D/dmesg.txt" 2>&1
	systemctl --failed --no-pager > "$D/failed.txt" 2>&1
	ls -l /dev/dri /dev/fb0 /dev/input > "$D/devices.txt" 2>&1
	sync
	sleep 20
done
