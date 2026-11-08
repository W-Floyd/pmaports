#!/bin/sh
# Wi-Fi and Bluetooth firmware for the Mobis G5W head unit, read from the stock
# system partition. The stock eMMC is never written: every block device of it is
# set read-only in the kernel before anything mounts it, and the loader mounts
# strictly read-only (ext4 with noload: no journal replay).
set -u

for d in /dev/mmcblk[0-9] /dev/mmcblk[0-9]p[0-9]*; do
	[ -b "$d" ] && blockdev --setro "$d"
done

# The FM1288 voice processor's tuning, one file per group of modes, searched as
# the stock audio HAL does: this car's directory (ro.product.name), then ext/,
# common/ and etc/ itself. The first found wins: later rules keep it.
set --
for f in HF ICC VR FAC Siri VM VRRear; do
	dst=fm1288/kia-ev6/$(echo "$f" | tr 'A-Z' 'a-z').bin
	for d in etc/tunning_param/wp_daudioplus_cvev_us etc/tunning_param/ext etc/tunning_param/common etc; do
		set -- "$@" --rule "$d/${f}_DSP_PARAM.bin=$dst"
	done
done

msm-firmware-loader --vendor generic --partitions system --copy --base /run/fwl \
	"$@" \
	--rule fw_bcmdhd.bin=brcm/brcmfmac4359-sdio.bin \
	--rule bcmdhd.cal=brcm/brcmfmac4359-sdio.txt \
	--rule 89359.clm_blob=brcm/brcmfmac4359-sdio.clm_blob \
	--rule bcm4349.hcd=brcm/BCM4349B1.hcd \
	--rule bcm4349.hcd=brcm/BCM.hcd \
	--rule bcm4349.hcd_E0300=brcm/bcm4349.hcd_E0300 \
	--rule 'vpu_lib.ko@bit_code_319=vpu/tcc803x/bit_code_319?prefix=4d580000000000000000000000000000' \
	--rule 'hevc_lib.ko@bit_code=vpu/tcc803x/hevc_bit_code'

# The firmware's vendor glue (wcc) needs brcmfmac loaded first.
for m in brcmutil brcmfmac brcmfmac-wcc; do
	modprobe "$m" 2>/dev/null || true
done

# coda_vpu probes before this runs and gives up without its firmware: probe it
# again now that the image is there. coda checks only the header's "MX".
modprobe -r coda_vpu 2>/dev/null
modprobe coda_vpu 2>/dev/null || true
# The same for the Wave410 HEVC decoder (wave4). Its image has no header.
modprobe -r wave4 2>/dev/null
modprobe wave4 2>/dev/null || true

# hci_bcm (built in) set the Bluetooth controller up at boot without its patch
# RAM, and on the ROM firmware the setup fails (LE Read Maximum Data Length)
# and no adapter registers. Bind it again: it now downloads the patch.
bt=/sys/bus/serial/drivers/hci_uart_bcm
if [ -e "$bt/serial0-0" ]; then
	echo serial0-0 > "$bt/unbind"
	echo serial0-0 > "$bt/bind"
fi
