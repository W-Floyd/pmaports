#!/bin/sh
# Write a freshly assembled boot image to this device's own boot partition.
#
# This is the step that removes the host from the loop: `apk upgrade && reboot`
# instead of a manual `fastboot flash`. boot-deploy does the same thing for 47
# other pmaports devices -- findfs PARTLABEL, then dd -- and Droidian's
# flash-bootimage does it for Halium devices. fogona only needs its own script
# because its boot image is a U-Boot+FIT payload rather than a plain Android
# boot.img (see fogona-mkboot.sh for why).
set -e

GUARD="${GUARD:-1}"

# Refuse to run on anything that is not this device. Droidian's flash-bootimage
# checks Android properties for the same reason; the compatible string is the
# equivalent here, and a wrong write here is a brick-shaped mistake.
if [ "$GUARD" = "1" ]; then
	compat=$(tr -d '\0' < /proc/device-tree/compatible 2>/dev/null || true)
	case "$compat" in
		*motorola,fogona*) ;;
		*)
			echo "refusing: /proc/device-tree/compatible is '$compat', not motorola,fogona" >&2
			echo "set GUARD=0 to override" >&2
			exit 1
			;;
	esac
fi

# A/B: the slot suffix matters. Nothing marks a RAM-booted slot successful, so
# the active slot is the one to write; boot-deploy resolves this the same way.
slot=$(tr -d '\0' < /proc/device-tree/chosen/bootargs 2>/dev/null |
       sed -n 's/.*androidboot\.slot_suffix=\([_a-z]*\).*/\1/p')
[ -n "$slot" ] || slot="_a"

part="/dev/disk/by-partlabel/boot${slot}"
[ -b "$part" ] || { echo "no such partition: $part" >&2; exit 1; }

img="${1:-/tmp/fogona-boot.img}"
[ -f "$img" ] || { echo "no image: $img (run fogona-mkboot.sh first)" >&2; exit 1; }

img_size=$(stat -c %s "$img")
part_size=$(blockdev --getsize64 "$part")
[ "$img_size" -le "$part_size" ] || {
	echo "image ($img_size) larger than partition ($part_size)" >&2
	exit 1
}

echo "writing $img -> $part (slot '$slot')"
dd if="$img" of="$part" bs=1M conv=fsync
sync
echo "done; reboot to run it"
