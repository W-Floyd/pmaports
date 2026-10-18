#!/bin/sh
# shellcheck disable=SC1091
# Boot from a postmarketOS disk image that is a file on a FAT USB stick.
#
# Runs before the initramfs looks for its partitions (mount_subpartitions, then
# find_root_partition): it finds a FAT file system holding nura/os.img and attaches
# the image as a loop device with its partitions scanned. The pmOS_boot and
# pmOS_root partitions inside it are then found by label, as on any other disk,
# and the boot continues the stock way. The stick stays mounted: the loop device
# reads the image through it.
. ./init_functions.sh

STICK=/run/nura-stick
IMAGE=nura/os.img

# The drivers the stick and the image need, if they are modules.
for m in loop vfat nls_cp437 nls_iso8859_1 usb_storage uas sd_mod; do
	modprobe "$m" 2>/dev/null || true
done

mkdir -p "$STICK"
attempt_start=$(get_uptime_seconds)
wait_seconds=30
echo "nura: looking for $IMAGE on a FAT stick for $wait_seconds seconds..."
while true; do
	# Whole disks (a stick without a partition table) and their partitions.
	for dev in /dev/sd[a-z][0-9]* /dev/sd[a-z]; do
		[ -b "$dev" ] || continue
		mount -t vfat -o rw,flush,noatime "$dev" "$STICK" 2>/dev/null || continue
		if [ -f "$STICK/$IMAGE" ]; then
			# -P: scan the partitions; --direct-io is what pmOS uses for its own
			# images, and not every file system takes it.
			loop="$(losetup --show -Pf --direct-io=on "$STICK/$IMAGE" 2>/dev/null)" ||
				loop="$(losetup --show -Pf "$STICK/$IMAGE" 2>/dev/null)"
			if [ -n "$loop" ]; then
				echo "nura: $dev:$IMAGE is $loop"
				exit 0
			fi
			echo "nura: cannot attach $STICK/$IMAGE"
		fi
		umount "$STICK"
	done
	[ "$(get_uptime_seconds)" -ge $((attempt_start + wait_seconds)) ] && break
	sleep 0.5
done
echo "nura: no $IMAGE found, continuing without it"
