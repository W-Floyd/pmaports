# Stage uinit for the Kia EV6 head unit, run by u-root's gosh as
# "gosh /etc/uinit.sh". gosh rules (see postmarketos-fogona/TRAPS.md): printf, not
# echo, for sysfs; no `exec > file`; end with `wait` so background jobs survive.

IP=172.16.42.1

say() {
	printf 'STAGE: %s\n' "$*" > /dev/kmsg
	printf '%s\n' "$*" >> /tmp/stage.log
}

say "uinit: starting"

# The micom resets the SoC if its CPU-alive requests go unanswered (about 3.5
# minutes after Android is gone). The Boot Manager answers them (-micom, which
# retries until the device exists) and shows the vehicle's state under
# Diagnostics; -micom-log keeps every frame, decoded where known. The Remote
# UI and Dev uploads (a dev build) start with it, reached through ssh -L.
printf 'remote dev\n' > /tmp/dev-once

# Give the panel to the Boot Manager UI: unbind fbcon from fb0.
if [ -e /sys/class/vtconsole/vtcon1/bind ]; then
	printf '0\n' > /sys/class/vtconsole/vtcon1/bind
fi

# No boot entries yet: keep the autoboot from running.
: > /tmp/hold

BB=/opt/ap/bin/busybox

# The stock eMMC is never written: every block device of it is set read-only
# in the kernel (BLKROSET) before anything mounts it, so even a mount that
# would replay a journal fails instead of writing. Waits a bounded time for
# the eMMC to enumerate; the loop keeps going in the background for late
# partitions.
emmc_ro() {
	for d in /dev/mmcblk[0-9] /dev/mmcblk[0-9]p[0-9]*; do
		[ -b "$d" ] && $BB blockdev --setro "$d"
	done
}
n=0
while [ ! -b /dev/mmcblk0 ] && [ "$n" -lt 8 ]; do
	sleep 1
	n=$((n + 1))
done
emmc_ro
say "eMMC set read-only: $($BB ls /dev | $BB grep mmcblk | $BB tr '\n' ' ')"

# The stick (it carries this stage, and the images the Boot Manager lists)
# enumerates a second or two after the eMMC. The Boot Manager scans once at
# start, and again only if that finds nothing, so it must not start before the
# stick is there: a scan without it saw only the eMMC and listed no image.
n=0
while [ ! -b /dev/sda1 ] && [ ! -b /dev/sdb1 ] && [ "$n" -lt 20 ]; do
	sleep 1
	n=$((n + 1))
done
say "usb stick after ${n}s: $($BB ls /dev | $BB grep '^sd' | $BB tr '\n' ' ')"

# The Boot Manager needs no network: start it at once. Its remote UI listens
# on localhost, reached through the sshd below (ssh -L 8080:127.0.0.1:8080).
bootmanager -panel /etc/bootmanager/kia-ev6.json -hold /tmp/hold -scan-retries 3 -android-boot boot -android-dtb dtb -android-cmdline /etc/bootmanager/android.cmdline -kexec "/opt/ap/bin/busybox ash /etc/kexec.sh" -kexec-prep "/opt/ap/bin/busybox ash /etc/kexec-prep.sh" -micom /dev/ttyAMA2 -micom-log /tmp/micomd.log -dev-once /tmp/dev-once -logs /tmp/stage.log,/tmp/wifi-dmesg.log,/tmp/wifi-tools.log,/tmp/hostapd.log,/tmp/wpa_supplicant.log,/tmp/micomd.log,/tmp/fwl.log -rekexec "/opt/ap/bin/busybox ash /etc/rekexec.sh" &

# The Wi-Fi access point (or joining a network) is the Boot Manager's, as is
# sshd (its ssh service, same keys). A wired interface (USB Ethernet dongle
# or tether) gets the static address when one shows up.
netup() {
	ifc=""
	while [ -z "$ifc" ]; do
		for d in /sys/class/net/*; do
			name="${d##*/}"
			[ "$name" = lo ] && continue
			[ "$name" = wlan0 ] && continue
			ifc="$name"
		done
		[ -z "$ifc" ] && sleep 2
	done
	say "network interface $ifc, address $IP/24"
	ip link set "$ifc" up
	ip addr add "$IP/24" dev "$ifc"
}
# Wi-Fi and Bluetooth firmware, read from the stock system partition. The
# loader (go-msm-firmware-loader, a subcommand of the Boot Manager) mounts it
# strictly read-only (MS_RDONLY, and ext4 with noload: no journal replay),
# finds each file by name wherever it is, copies it into RAM under the name the
# driver asks for, lets the partition go and points firmware_class.path at the
# copies. The rules are its generic vendor's: nothing here is Kia-specific
# knowledge of where the files are, only of what they are called. The Wi-Fi
# driver is a module so it loads after this, not before; the Bluetooth patch
# (bcm4349.hcd, the L2101 build, under the names hci_bcm asks for; the E0300
# build stays under its own, for bt-up.sh e0300) is read when the controller
# is opened.
FW=/run/fwl/target/brcm
fwstage() {
	for t in 1 2 3; do
		emmc_ro
		sleep 1
	done
	bootmanager msm-firmware-loader --vendor generic --partitions system --copy --base /run/fwl \
		--rule fw_bcmdhd.bin=brcm/brcmfmac4359-sdio.bin \
		--rule bcmdhd.cal=brcm/brcmfmac4359-sdio.txt \
		--rule 89359.clm_blob=brcm/brcmfmac4359-sdio.clm_blob \
		--rule bcm4349.hcd=brcm/BCM4349B1.hcd \
		--rule bcm4349.hcd=brcm/BCM.hcd \
		--rule bcm4349.hcd_E0300=brcm/bcm4349.hcd_E0300 >> /tmp/fwl.log 2>&1
	say "fw: loader: $($BB tail -n 1 /tmp/fwl.log)"
	if [ -s $FW/brcmfmac4359-sdio.bin ]; then
		$BB insmod /lib/modules/brcmutil.ko
		$BB insmod /lib/modules/brcmfmac.ko
		# The firmware's vendor glue (wcc) needs brcmfmac loaded, and the
		# driver looks for it once the firmware is up.
		$BB insmod /lib/modules/brcmfmac-wcc.ko
		say "fw: brcmfmac loaded"
		sleep 3
		if [ ! -e /sys/class/net/wlan0 ]; then
			# Lost the race: probe the SDIO functions again, now that wcc is in.
			for f in /sys/bus/sdio/devices/*; do
				n="${f##*/}"
				printf '%s' "$n" > /sys/bus/sdio/drivers/brcmfmac/unbind
				printf '%s' "$n" > /sys/bus/sdio/drivers/brcmfmac/bind
			done
			say "fw: re-probed brcmfmac"
			sleep 3
		fi
	else
		say "fw: no Wi-Fi firmware found on the eMMC"
	fi
	if [ -s $FW/BCM.hcd ]; then
		say "fw: Bluetooth patch staged ($($BB wc -c < $FW/BCM.hcd) bytes); /etc/bt-up.sh brings it up"
	else
		say "fw: no Bluetooth patch (bcm4349.hcd) found on the eMMC"
	fi
	sleep 5
	# Why there is (no) wlan0: what the MMC core, the SDIO host, the power
	# sequence's GPIO and the driver say. Shown on the Log screen.
	mount -t debugfs none /sys/kernel/debug 2>/dev/null
	{
		printf '== modules\n'
		$BB lsmod
		printf '== net\n'
		ls /sys/class/net
		printf '== dynamic loader\n'
		ls -l /lib /opt/ap/bin /opt/ap/lib
		export LD_LIBRARY_PATH=/opt/ap/lib
		/lib/ld-musl-armhf.so.1 --list /opt/ap/bin/wpa_supplicant 2>&1
		/opt/ap/bin/wpa_supplicant -v 2>&1
		/opt/ap/bin/hostapd -v 2>&1
		/opt/ap/bin/kexec --version 2>&1
		printf '== mmc hosts\n'
		ls /sys/class/mmc_host
		for h in /sys/kernel/debug/mmc*; do
			printf '== %s/ios\n' "$h"
			cat "$h/ios"
		done
		printf '== sdio devices / drivers\n'
		ls /sys/bus/sdio/devices /sys/bus/sdio/drivers
		printf '== mmc irqs\n'
		$BB grep -i mmc /proc/interrupts
		printf '== gpio\n'
		$BB grep -iE 'wl|reset|pwrseq|gpio-24 ' /sys/kernel/debug/gpio
		printf '== dmesg\n'
		$BB dmesg | $BB grep -iE 'mmc|sdh|sdio|brcm|pwrseq|gpio|firmware|cfg80211|clk|16460000' | $BB grep -vE 'EXT4-fs|FAT-fs|STAGE:' | $BB tail -n 60
		printf '== sdhc2 platform device\n'
		ls -l /sys/bus/platform/devices/16460000.mmc /sys/bus/platform/drivers/sdhci-tcc803x
		cat /sys/kernel/debug/devices_deferred
		printf '== dmesg, last 40 lines unfiltered\n'
		$BB dmesg | $BB grep -vE 'EXT4-fs|FAT-fs|STAGE:' | $BB tail -n 40
	} > /tmp/wifi-dmesg.log 2>&1
	usblog
	# Again once the access point has had time to come up (or a scan has
	# been tried from the UI), and a few more times: the Boot Manager's log
	# keeps growing, and what happened after a pick is the thing to read.
	sleep 60
	usblog
	for i in 1 2 3 4 5; do
		sleep 120
		usblog
	done
}

# What goes on the stick: the stage's logs, the Boot Manager's own (its scan of
# the stick's images is in it) and the state a scan depends on.
usblog_body() {
	cat /tmp/stage.log /tmp/bootmanager.log /tmp/wifi-dmesg.log /tmp/wifi-tools.log /tmp/hostapd.log /tmp/wpa_supplicant.log /tmp/fwl.log 2>/dev/null
	printf '== partitions\n'
	cat /proc/partitions
	printf '== mounts\n'
	cat /proc/mounts
	printf '== loop devices\n'
	$BB losetup -a 2>&1
	printf '== removable flags\n'
	for d in /sys/block/sd*; do
		printf '%s %s\n' "$d" "$(cat "$d/removable")"
	done
	printf '== dmesg: loop, file systems, usb storage\n'
	$BB dmesg | $BB grep -iE 'loop|EXT4-fs|FAT-fs|usb-storage|sd[a-z]' | $BB tail -n 60
}

# Leaves the stage's log on the USB stick (the one holding NEMESIS.sh), for
# reading off the phone: the screen is the only other way out. Only /dev/sd*
# is ever mounted read-write here, never the eMMC.
usblog() {
	mkdir -p /mnt/usb
	say "usb: block devices: $($BB ls /dev | $BB grep '^sd' | $BB tr '\n' ' ')"
	for p in /dev/sd[a-z]1 /dev/sd[a-z]; do
		[ -b "$p" ] || continue
		# The Boot Manager may hold the stick mounted already (read-only): a
		# second mount of the same filesystem is refused, so use that mount.
		mp=$($BB grep "^$p " /proc/mounts | $BB head -n 1 | $BB cut -d' ' -f2)
		if [ -n "$mp" ]; then
			if $BB mount -o remount,rw "$mp" 2>/tmp/usb.err && [ -e "$mp/NEMESIS.sh" ]; then
				usblog_body > "$mp/stagelog.txt" 2>/dev/null
				$BB sync
				$BB mount -o remount,ro "$mp"
				say "log written to $mp ($p) as stagelog.txt"
				return
			fi
			say "usb: $p held at $mp: $(cat /tmp/usb.err)"
			$BB mount -o remount,ro "$mp" 2>/dev/null
			continue
		fi
		for t in vfat exfat ext4; do
			if $BB mount -t "$t" -o rw,sync "$p" /mnt/usb 2>/tmp/usb.err; then
				if [ -e /mnt/usb/NEMESIS.sh ]; then
					usblog_body > /mnt/usb/stagelog.txt 2>/dev/null
					$BB sync
					$BB umount /mnt/usb
					say "log written to $p as stagelog.txt"
					return
				fi
				say "usb: $p ($t) has no NEMESIS.sh"
				$BB umount /mnt/usb
			else
				say "usb: $p as $t: $(cat /tmp/usb.err)"
			fi
		done
	done
	say "no USB stick found to write the log to"
}
fwstage &

netup &

wait
