#!/bin/sh
# Keep this boot's display bring-up record in a small file of its own:
# /var/log/fogona-display/<boot id>.txt, the panel driver's brightness
# read-backs ("bl:"), its init retries and failures, and the DSI/DPU errors
# of the intermittent stall (/repo/investigations/
# display-vblank-boot-stall.md).
#
# The journal has all of this too, but reading one boot back from it takes
# ~15 s on this card and the archive is meant to grow for months; this file
# reads back at once (/repo/tools/backlight-log.sh). A stalled boot still
# gets well past local-fs, so it is recorded. Snapshots every 10 s for two
# minutes, merged and de-duplicated (the lines carry kernel timestamps), so
# the early lines are kept even if the ring buffer wraps later.
PAT='bl: |panel init|Failed to initialize panel|dsi_cmds2buf_tx|vblank|frame done timeout|ctl .* reset failure'
d=/var/log/fogona-display
mkdir -p "$d"
f=$d/$(cat /proc/sys/kernel/random/boot_id).txt
for i in 1 2 3 4 5 6 7 8 9 10 11 12; do
	{
		cat "$f" 2>/dev/null
		echo "# kernel $(uname -v)"
		dmesg | grep -E "$PAT"
	} | sort -u > "$f.tmp" && mv "$f.tmp" "$f"
	sleep 10
done
