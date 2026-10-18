#!/bin/sh
# Wi-Fi and Bluetooth firmware for the Mobis G5W head unit, read from the stock
# system partition. The stock eMMC is never written: every block device of it is
# set read-only in the kernel before anything mounts it, and the loader mounts
# strictly read-only (ext4 with noload: no journal replay).
set -u

for d in /dev/mmcblk[0-9] /dev/mmcblk[0-9]p[0-9]*; do
	[ -b "$d" ] && blockdev --setro "$d"
done

msm-firmware-loader --vendor generic --partitions system --copy --base /run/fwl \
	--rule fw_bcmdhd.bin=brcm/brcmfmac4359-sdio.bin \
	--rule bcmdhd.cal=brcm/brcmfmac4359-sdio.txt \
	--rule 89359.clm_blob=brcm/brcmfmac4359-sdio.clm_blob \
	--rule bcm4349.hcd=brcm/BCM4349B1.hcd \
	--rule bcm4349.hcd=brcm/BCM.hcd \
	--rule bcm4349.hcd_E0300=brcm/bcm4349.hcd_E0300

# The firmware's vendor glue (wcc) needs brcmfmac loaded first.
for m in brcmutil brcmfmac brcmfmac-wcc; do
	modprobe "$m" 2>/dev/null || true
done
