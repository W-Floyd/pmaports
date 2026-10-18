#!/opt/ap/bin/busybox ash
# Re-kexec from the USB stick, without going back to the vendor Android: run
# by the Boot Manager's stage.rekexec. Loads the stick's zImage and
# tcc803x-avn.dtb, with the initramfs initrd.sel names (default
# stage.cpio.gz), and the command line of the kernel running now, then jumps.
# Prints a reason and exits non-zero when it cannot; on success it never
# returns. The stick is only read.

AP=/opt/ap
BB=$AP/bin/busybox
export LD_LIBRARY_PATH=$AP/lib

# Where the stick is mounted (the Boot Manager may hold it), else mount it.
dir=""
for p in /dev/sd[a-z]1 /dev/sd[a-z]; do
	[ -b "$p" ] || continue
	mp=$($BB grep "^$p " /proc/mounts | $BB head -n 1 | $BB cut -d' ' -f2)
	if [ -z "$mp" ]; then
		$BB mkdir -p /mnt/rekexec
		for t in vfat exfat ext4; do
			$BB mount -t "$t" -o ro "$p" /mnt/rekexec 2>/dev/null && { mp=/mnt/rekexec; break; }
		done
	fi
	if [ -n "$mp" ] && [ -s "$mp/zImage" ]; then
		dir="$mp"
		break
	fi
done
[ -n "$dir" ] || { echo "no USB stick with a zImage found"; exit 1; }

initrd=stage.cpio.gz
[ -s "$dir/initrd.sel" ] && initrd=$($BB head -n 1 "$dir/initrd.sel" | $BB tr -d '\r\n ')
[ -s "$dir/$initrd" ] || { echo "$dir/$initrd is missing or empty"; exit 1; }
[ -s "$dir/tcc803x-avn.dtb" ] || { echo "$dir/tcc803x-avn.dtb is missing or empty"; exit 1; }

# Copy to RAM first: the stick's mount goes away under the new kernel.
$BB mkdir -p /tmp/rekexec
$BB cp "$dir/zImage" "$dir/tcc803x-avn.dtb" "$dir/$initrd" /tmp/rekexec/ || { echo "copy from $dir failed"; exit 1; }

cmdline=$($BB cat /proc/cmdline)
# A try with another command line: put it in /tmp/rekexec.cmdline (RAM, gone
# with this boot, so a bad one costs one reset and is never the next boot's).
[ -s /tmp/rekexec.cmdline ] && cmdline=$($BB head -n 1 /tmp/rekexec.cmdline)
out=$($BB ash /etc/kexec.sh -l /tmp/rekexec/zImage --dtb=/tmp/rekexec/tcc803x-avn.dtb --initrd=/tmp/rekexec/"$initrd" --append="$cmdline" 2>&1) || { echo "kexec -l: $out"; exit 1; }
$BB sync

# Quiet what can touch RAM on its own before the jump (kexec-prep.sh).
$BB ash /etc/kexec-prep.sh

$AP/bin/kexec -e
echo "kexec -e returned"
exit 1
