#!/bin/sh
# Expose the BCM4361 WiFi/BT firmware from the phone's own vendor partition,
# so nothing proprietary has to be shipped in an aport.
#
# msm-firmware-loader mounts the vendor partition and points
# firmware_class.path at its target dir, but it only links from <part>/image
# and <part>/firmware. The Broadcom WiFi files live in vendor/etc/wifi under
# vendor names (bcmdhd_*), so link them into target/brcm/ under the names
# brcmfmac asks for. Must run before udev autoloads brcmfmac.
#
# NVRAM variants differ only in RF calibration and never log an error when
# wrong, so pick by board revision (the vendor's own selector) rather than by
# counting failures. androidboot.revision is forwarded by u-boot.
set -u

T=/run/msm-firmware-loader/target
V=/run/msm-firmware-loader/mnt/vendor/etc/wifi
BT=/run/msm-firmware-loader/mnt/vendor/firmware
BOARD="samsung,starqltechn"
BASE=brcmfmac4361-pcie
FALLBACK=nvram.txt_murata_r020_b2

[ -d "$V" ] || { echo "brcm-vendor-fw: $V not mounted, nothing to do" >&2; exit 0; }

rev=$(sed -n 's/.*androidboot\.revision=\([0-9]\{1,\}\).*/\1/p' /proc/cmdline)
case "${rev:-}" in
	12) nvram=nvram.txt_murata_r020_b2 ;;
	13) nvram=nvram.txt_murata_r031_b2 ;;
	14) nvram=nvram.txt_murata_r041_b2 ;;
	*)  nvram=$FALLBACK
	    echo "brcm-vendor-fw: board revision '${rev:-unset}' unmapped, using $FALLBACK" >&2 ;;
esac
[ -f "$V/$nvram" ] || { echo "brcm-vendor-fw: $nvram absent, falling back to $FALLBACK" >&2; nvram=$FALLBACK; }

mkdir -p "$T/brcm"

link() {  # link <source-file> <extension>
	[ -f "$V/$1" ] || { echo "brcm-vendor-fw: missing $V/$1" >&2; return 1; }
	ln -sf "$V/$1" "$T/brcm/$BASE.$2"
	ln -sf "$V/$1" "$T/brcm/$BASE.$BOARD.$2"
}

link bcmdhd_sta.bin_b2 bin
link bcmdhd_clm.blob   clm_blob
link "$nvram"          txt

# Bluetooth. The vendor ships one .hcd per module vendor; the NVRAM variants
# present are all murata, so this board is murata. btbcm maps the HCI
# subversion (0x4309) to BCM4361B2 and asks for brcm/BCM4361B2.hcd, so link it
# under that name. Needed by both the serdev and the btattach attach paths.
for _hcd in bcm4361B2_murata.hcd bcm4361B2_semco.hcd; do
	if [ -f "$BT/$_hcd" ]; then
		ln -sf "$BT/$_hcd" "$T/brcm/BCM4361B2.hcd"
		echo "brcm-vendor-fw: bluetooth firmware $_hcd"
		break
	fi
done

echo "brcm-vendor-fw: rev=${rev:-unset} nvram=$nvram"
