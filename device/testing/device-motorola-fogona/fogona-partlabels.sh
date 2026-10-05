#!/bin/sh
# Create /dev/disk/by-partlabel for the UFS partitions from sysfs, for what runs
# before udev: msm-firmware-loader asks qbootctl for the A/B slot, and qbootctl
# opens /dev/disk/by-partlabel. udev normally creates the links, and the
# initramfs used to run it (the links survived the switch to the real root);
# with deviceinfo_initfs_skip_udev they do not exist at that point, qbootctl
# finds no slots, and the loader then looks for "modem" instead of "modem_a":
# no vendor_a, so no venus.mbn, GPU or touch firmware. udev replaces these
# links with its own when it runs.
#
# Usage: fogona-partlabels [DIR]   (DIR defaults to /dev/disk/by-partlabel)
dir=${1:-/dev/disk/by-partlabel}
mkdir -p "$dir"
for u in /sys/block/sd*/sd*/uevent; do
	[ -e "$u" ] || continue
	devname="" partname=""
	while IFS== read -r key val; do
		case $key in
		DEVNAME) devname=$val ;;
		PARTNAME) partname=$val ;;
		esac
	done < "$u"
	[ -n "$devname" ] && [ -n "$partname" ] && ln -sf "../../$devname" "$dir/$partname"
done
exit 0
