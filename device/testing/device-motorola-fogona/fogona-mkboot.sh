#!/bin/sh
# Assemble fogona's boot image ON THE DEVICE and write it to boot_a.
#
# Why this exists: fogona's ABL will not boot a mainline kernel directly. It
# substitutes its own devicetree, does not publish the ramdisk location
# (/chosen/linux,initrd-start is absent, so U-Boot's $prevbl_initrd_start_addr is
# empty), and applies dtbo overlays that fault against a non-stock base DTB.
# Every direct-boot variant was tried and fails identically -- see
# /repo/investigations/boot-chain.md. The only layout that boots is U-Boot
# chainloaded with the FIT welded into its own payload at a fixed offset, so
# U-Boot finds the FIT by arithmetic rather than trusting the bootloader.
#
# That layout is not expressible with boot-deploy's bootimg_override_* options
# (those put the FIT in the ramdisk slot, which is the layout ABL breaks), and
# boot-deploy's hooks run before image creation, so this runs standalone.
#
# The point is that it runs HERE rather than on a workstation: the device can
# write its own boot partition, so `apk upgrade && reboot` replaces a manual
# fastboot cycle. That is what boot-deploy does for 47 other pmaports devices
# (findfs PARTLABEL -> dd) and what Droidian's flash-bootimage does.
set -e

KERNEL="${KERNEL:-/boot/vmlinuz}"
DTB="${DTB:-/boot/dtbs/qcom/sm6225-motorola-fogona-icnl9916c.dtb}"
INITRAMFS="${INITRAMFS:-/boot/initramfs}"
UBOOT="${UBOOT:-/usr/share/u-boot/fogona/u-boot-txt0.bin}"
OUT="${OUT:-/tmp/fogona-boot.img}"

# Addresses: the free run above removed_mem (ends 0x63900000) and below rmtfs
# (0x89b01000). Must match what the kernel and DTB expect.
KERNEL_ADDR="${KERNEL_ADDR:-0x64000000}"
FDT_ADDR="${FDT_ADDR:-0x68000000}"
RAMDISK_ADDR="${RAMDISK_ADDR:-0x68100000}"

# Where U-Boot's bootcmd probes for the FIT, relative to the payload start.
FIT_OFFSET=$((8 * 1024 * 1024))
# The boot partition size; the AVB footer is padded to match.
PART_SIZE=100663296

for f in "$KERNEL" "$DTB" "$INITRAMFS" "$UBOOT"; do
	[ -f "$f" ] || { echo "missing: $f" >&2; exit 1; }
done
for c in mkimage mkbootimg avbtool; do
	command -v "$c" >/dev/null || { echo "missing command: $c" >&2; exit 1; }
done

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# /boot/vmlinuz is already gzip (the kernel APKBUILD uses `make zinstall`), which
# is what the FIT wants for compression="gzip". Don't re-compress it.
if [ "$(head -c2 "$KERNEL" | od -An -tx1 | tr -d ' \n')" = "1f8b" ]; then
	cp "$KERNEL" "$WORK/Image.gz"
else
	gzip -9 -c "$KERNEL" > "$WORK/Image.gz"
fi

# The initramfs needs one transformation before it can be booted: the DTB's
# /chosen/bootargs boots `rdinit=/init.pmos`, because when ABL supplies a ramdisk
# the GKI generic one clobbers pmOS's /init. So /init.pmos has to exist. Packing
# /boot/initramfs verbatim produces a kernel that cannot exec its init, falls
# through to mounting a real root, finds none, and panics with
# "VFS: unable to mount root fs on unknown-block" -- which looks like a storage
# problem and is not one.
mkdir -p "$WORK/ir"
zcat "$INITRAMFS" | (cd "$WORK/ir" && cpio -idm 2>/dev/null)
[ -f "$WORK/ir/init" ] || { echo "initramfs has no /init" >&2; exit 1; }
cp -a "$WORK/ir/init" "$WORK/ir/init.pmos"
chmod 755 "$WORK/ir/init.pmos"
(cd "$WORK/ir" && find . | cpio -o -H newc -R root:root 2>/dev/null | gzip -9) \
	> "$WORK/initramfs.gz"

cp "$DTB" "$WORK/fdt.dtb"

cat > "$WORK/fit.its" <<EOF
/dts-v1/;
/ {
	description = "fogona";
	#address-cells = <1>;
	images {
		kernel {
			data = /incbin/("$WORK/Image.gz");
			type = "kernel";
			arch = "arm64";
			os = "linux";
			compression = "gzip";
			load = <$KERNEL_ADDR>;
			entry = <$KERNEL_ADDR>;
		};
		fdt-1 {
			data = /incbin/("$WORK/fdt.dtb");
			type = "flat_dt";
			arch = "arm64";
			compression = "none";
			load = <$FDT_ADDR>;
		};
		ramdisk-1 {
			data = /incbin/("$WORK/initramfs.gz");
			type = "ramdisk";
			arch = "arm64";
			os = "linux";
			compression = "gzip";
			load = <$RAMDISK_ADDR>;
		};
	};
	configurations {
		default = "conf-1";
		conf-1 {
			kernel = "kernel";
			fdt = "fdt-1";
			ramdisk = "ramdisk-1";
		};
	};
};
EOF

mkimage -f "$WORK/fit.its" "$WORK/fit.itb" >/dev/null

# payload = U-Boot, zero-padded to FIT_OFFSET, then the FIT. U-Boot's bootcmd
# probes candidate addresses for exactly this.
ub_size=$(stat -c %s "$UBOOT")
[ "$ub_size" -le "$FIT_OFFSET" ] || {
	echo "u-boot is $ub_size bytes, larger than the $FIT_OFFSET FIT offset" >&2
	exit 1
}
cp "$UBOOT" "$WORK/payload.bin"
# truncate, not `dd bs=1 seek=... count=...`: extending a file with truncate
# zero-fills it in one call, while the dd form issues one write syscall per byte
# -- 6.6 million of them for this gap, which takes minutes on this SoC and looks
# exactly like a hang.
truncate -s "$FIT_OFFSET" "$WORK/payload.bin"
cat "$WORK/fit.itb" >> "$WORK/payload.bin"

mkbootimg --header_version 4 --kernel "$WORK/payload.bin" \
	--pagesize 4096 --base 0x00000000 --kernel_offset 0x00008000 \
	--ramdisk_offset 0x01000000 --tags_offset 0x00000100 \
	--output "$WORK/boot.img"

# The bootloader wants an AVB footer padded to the partition size. vbmeta has
# verification disabled on this unit, but the footer still has to be there.
avbtool add_hash_footer --image "$WORK/boot.img" \
	--partition_name boot --partition_size "$PART_SIZE"

cp "$WORK/boot.img" "$OUT"
echo "built: $OUT ($(stat -c %s "$OUT") bytes)"
