#!/opt/ap/bin/busybox ash
# Quiet everything that can touch RAM on its own before the jump: the new
# kernel reuses this memory, and a live DMA engine (the Wi-Fi chip's SDIO
# host, the USB controllers) or a mount still being read can corrupt it.
# Run after kexec -l has loaded the kernel, by rekexec.sh and by the Boot
# Manager (-kexec-prep).

BB=/opt/ap/bin/busybox
for f in /tmp/hostapd.pid /tmp/dnsmasq.pid /tmp/wpa.pid /tmp/udhcpc.pid; do
	[ -s "$f" ] && $BB kill $($BB cat "$f") 2>/dev/null
done
$BB sleep 1
$BB ifconfig wlan0 down 2>/dev/null
$BB rmmod brcmfmac_wcc 2>/dev/null
$BB rmmod brcmfmac 2>/dev/null
$BB rmmod brcmutil 2>/dev/null
for m in $($BB grep -E '^/dev/(sd|mmcblk)' /proc/mounts | $BB cut -d' ' -f2); do
	$BB umount -l "$m" 2>/dev/null
done
$BB sync
exit 0
