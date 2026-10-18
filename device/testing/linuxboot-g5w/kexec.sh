#!/opt/ap/bin/busybox ash
# kexec-tools with its libraries: the Boot Manager's -kexec for entries it
# cannot load itself (32-bit ARM).
#
# --image-size: this kernel is linked at TEXT_OFFSET 0x208000 (multi_v7's
# ARCH_MESON), 0x200000 more than kexec-tools assumes, and it puts the initramfs
# right after its estimate of the kernel. The zImage decompressor copies itself
# to just past the decompressed kernel (over the initramfs: "Unable to mount
# root fs"). So the size is worked out for the kernel being loaded, from what a
# probe load of it prints: that offset, the decompressed text and data, and what
# the zImage needs, and 2 MiB over. 0x3800000 if that cannot be read.
export LD_LIBRARY_PATH=/opt/ap/lib
BB=/opt/ap/bin/busybox
KEXEC=/opt/ap/bin/kexec

kernel=
for a in "$@"; do
	case $a in -*) ;; *) [ -f "$a" ] && kernel=$a ;; esac
done

size=0x3800000
if [ -n "$kernel" ]; then
	out=$($KEXEC -d -l "$kernel" 2>&1)
	$KEXEC -u 2>/dev/null
	td=$(echo "$out" | $BB sed -n 's/.*text+data \(0x[0-9a-f]*\).*/\1/p')
	zr=$(echo "$out" | $BB sed -n 's/^zImage requires \(0x[0-9a-f]*\).*/\1/p')
	if [ -n "$td" ] && [ -n "$zr" ]; then
		need=$((0x200000 + td + zr + 0x200000))
		size=$(((need + 0xfffff) & ~0xfffff))
		size=$($BB printf 0x%x "$size")
	fi
fi
exec $KEXEC --image-size="$size" "$@"
