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
#
# The image is copied to the stick small. Here it is first extended to the most a
# FAT32 file can be (or as far as the stick has room), the second partition is
# grown into the new space, and the stock initramfs then grows its file system
# (resize_root_filesystem). Nothing to do once the image is full size.
. ./init_functions.sh

# The micom (the vehicle's microcontroller) resets the SoC as hung when its
# CPU-alive requests go unanswered, about 3.5 minutes after the vendor Android is
# gone, and the grow below can take that long on its own. micomd answers them from
# here on. It keeps running after the switch to the real system, where
# mobis-g5w-micomd.service starts one only if there is none.
if [ -x /usr/bin/micomd ]; then
	i=0
	while [ ! -c /dev/ttyAMA2 ] && [ "$i" -lt 10 ]; do
		sleep 0.5
		i=$((i + 1))
	done
	/usr/bin/micomd -dev /dev/ttyAMA2 -stats 0 >/dev/null 2>&1 &
	echo "nura: micomd answering the micom on /dev/ttyAMA2"
fi

STICK=/run/nura-stick
IMAGE=nura/os.img
# 4 GiB - 1 MiB: under FAT32's 4 GiB - 1 byte file limit, on a MiB boundary.
MAX=4293918720
GROWN=0

# Extend $1 up to $MAX, keeping 64 MiB of the stick free. FAT allocates the new
# clusters now, so this takes a while the first time. A failure is not fatal.
grow_image() {
	local cur avail grow room
	cur="$(stat -c %s "$1")"
	[ "$cur" -lt "$MAX" ] || return 0
	avail=$(($(df -k "$STICK" | awk 'NR==2 {print $4}') * 1024))
	grow=$((MAX - cur))
	room=$((avail - 64 * 1024 * 1024))
	[ "$grow" -le "$room" ] || grow=$room
	grow=$((grow / 1048576 * 1048576))
	[ "$grow" -gt 0 ] || return 0
	echo "nura: growing $IMAGE by $((grow / 1048576)) MiB..."
	if truncate -s $((cur + grow)) "$1" 2>/dev/null ||
		dd if=/dev/zero of="$1" bs=1 count=0 seek=$((cur + grow)) 2>/dev/null; then
		GROWN=1
	else
		echo "nura: could not grow $IMAGE, using it as it is"
	fi
}

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
			grow_image "$STICK/$IMAGE"
			# -P: scan the partitions; --direct-io is what pmOS uses for its own
			# images, and not every file system takes it.
			loop="$(losetup --show -Pf --direct-io=on "$STICK/$IMAGE" 2>/dev/null)" ||
				loop="$(losetup --show -Pf "$STICK/$IMAGE" 2>/dev/null)"
			if [ -n "$loop" ]; then
				echo "nura: $dev:$IMAGE is $loop"
				if [ "$GROWN" = 1 ]; then
					echo "nura: growing the root partition"
					parted -f -s "$loop" resizepart 2 100% && partprobe "$loop"
				fi
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
