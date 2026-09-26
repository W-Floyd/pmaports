# fogona LinuxBoot stage 1: u-root's uinit, run by gosh.
#
# Brings up USB networking exactly as pmOS's initramfs does (NCM, same IDs,
# 172.16.42.1, unudhcpd handing the host 172.16.42.2) and u-root's sshd on
# port 22 (public key only: out/linuxboot/ssh/id_ed25519), then boots the
# default entry through /etc/fogona-boot.sh after the menu's 10 s. To stay
# in the stage: ssh in and `touch /tmp/hold` before the countdown ends, then
# `gosh /etc/fogona-boot.sh` for the menu with a keyboard.
#
# Output goes to the console and /tmp/uinit.log. Each boot also leaves a
# record on the pmOS boot partition, read back from pmOS afterwards (the
# panel does not always come up): record_boot below.

# record_boot appends this boot's panel read-backs ("bl:" lines, from the
# panel driver) to linuxboot/backlight.log under a boot counter (the stage
# has no wall clock), and leaves this boot's dmesg as linuxboot/dmesg.txt.
# tools/backlight-log.sh reads it back with pmOS's own records.
#
# It runs before anything else, mounts the card read-write only for as long
# as it writes, and unmounts before the boot scan: ext4 refuses a read-only
# mount of a superblock already mounted read-write ("Can't mount, would
# change RO state") and the reverse, so a read-write mount held past this
# point hides the boot entries from the scan (it did, 2026-09-26), and one
# made after the scan fails. It waits up to 5 s for the panel driver's
# verdict, which on a good boot is already in by the time the uinit runs.
#
# TEMPORARY, for the display logging only: mmcblk0p1 is hardcoded, where the
# stage should log to the boot partition it discovers (the one holding
# extlinux.conf, by label or UUID) -- TODO.md, "LinuxBoot".
record_boot() {
	mkdir -p /mnt/boot
	mount -t ext4 /dev/mmcblk0p1 /mnt/boot || return
	for i in 1 2 3 4 5; do
		dmesg | grep -q "bl: settled|Failed to initialize panel" && break
		sleep 1
	done
	L=/mnt/boot/linuxboot
	mkdir -p $L
	n=$(cat $L/boot-count 2>/dev/null)
	n=$((${n:-0} + 1))
	printf '%s\n' $n > $L/boot-count
	{
		printf '== stage boot %s: %s\n' $n "$(uname -v)"
		dmesg | grep "bl: |panel init|Failed to initialize panel"
	} >> $L/backlight.log
	dmesg > $L/dmesg.txt
	# A one-shot request from pmOS (tools/linuxboot/dev.sh
	# stage-hold): stay in the Boot Manager this boot, with the services it
	# names switched on, for kexec testing. Consumed here, so the next boot
	# autoboots as usual.
	if [ -f $L/dev-once ]; then
		cp $L/dev-once /tmp/dev-once
		rm $L/dev-once
		touch /tmp/hold
	fi
	device_files $L
	sync
	umount /mnt/boot
}

# The device's own files, which a packaged stage (linuxboot-fogona) cannot
# carry: the touch controller's firmware (a vendor blob) and the SSH keys.
# The package's install script puts them in linuxboot/ on the boot
# partition; a stage built with its own (tools/linuxboot/build.sh) keeps
# those and takes these as well.
device_files() {
	if [ -f $1/authorized_keys ]; then
		mkdir -p /etc/ssh
		cat $1/authorized_keys >> /etc/ssh/authorized_keys
	fi
	[ -f /etc/ssh/ssh_host_rsa_key ] || [ ! -f $1/ssh_host_rsa_key ] ||
		cp $1/ssh_host_rsa_key /etc/ssh/ssh_host_rsa_key
	if [ ! -f /lib/firmware/chipone_firmware.bin ] && [ -f $1/chipone_firmware.bin ]; then
		mkdir -p /lib/firmware
		cp $1/chipone_firmware.bin /lib/firmware/
		touch_rebind
	fi
}

# The touch driver asked for its firmware when it probed, before this ran,
# and got none. Probing again registers it with the panel afresh, and the
# panel being up makes it load the firmware at once.
touch_rebind() {
	D=/sys/bus/spi/drivers/chipone_icnl9916_spi
	for dev in /sys/bus/spi/devices/*; do
		case "$(cat $dev/modalias 2>/dev/null)" in
		*icnl9916*) ;;
		*) continue ;;
		esac
		name=${dev##*/}
		[ -e $D/$name ] && printf '%s' $name > $D/unbind
		printf '%s' $name > $D/bind
		echo "touch: rebound $name with the boot partition's firmware"
	done
}
echo "=== fogona LinuxBoot uinit started ==="
record_boot > /tmp/record_boot.log 2>&1

# Every configfs write goes through put, never echo: gosh's echo writes each
# argument and the newline with separate write() calls, and configfs takes
# each call as a whole new value. "echo 4e00000.usb > UDC" therefore bound
# the gadget and then, on the bare "\n", unbound it again -- silently, with
# the controller left halted and the UDC "not attached" -- and every string
# attribute ended up empty. printf formats first and writes once.
put() {
	printf '%s\n' "$2" > "$1"
}

# A function, not `exec > file`: gosh accepts that and then drops every
# later line of output.
setup() {
mount -t configfs configfs /sys/kernel/config

G=/sys/kernel/config/usb_gadget/g1
mkdir $G
put $G/idVendor 0x18D1
put $G/idProduct 0xD001
mkdir $G/strings/0x409
put $G/strings/0x409/manufacturer Motorola
put $G/strings/0x409/serialnumber postmarketOS
put $G/strings/0x409/product "Motorola Moto G Play (2024) LinuxBoot"
mkdir $G/functions/ncm.usb0
mkdir $G/configs/c.1
mkdir $G/configs/c.1/strings/0x409
put $G/configs/c.1/strings/0x409/configuration "USB network"
ln -s $G/functions/ncm.usb0 $G/configs/c.1/ncm.usb0
for u in /sys/class/udc/*; do
	put $G/UDC ${u##*/}
done

ip addr add 172.16.42.1/16 dev usb0
ip link set usb0 up
/usr/bin/unudhcpd -i usb0 -s 172.16.42.1 -c 172.16.42.2 > /tmp/unudhcpd.log 2>&1 &
# With the boot manager in the image, it runs sshd (it can switch it off
# and on); without, it is started here.
[ -e /bbin/bootmanager ] ||
	sshd -port 22 -keys /etc/ssh/authorized_keys -privatekey /etc/ssh/ssh_host_rsa_key > /tmp/sshd.log 2>&1 &
}
setup 2>&1 | tee /tmp/uinit.log

# postmarketOS Boot Manager (BOOTMANAGER=1 builds): it shows the entries,
# runs the same 10 s autoboot (a key press or /tmp/hold stops it) and never
# returns. Its repo, ~/bootmanager (README.md), has the rest.
# Should it ever exit, carry on as a stage without it: sshd and the menu.
if [ -e /bbin/bootmanager ]; then
	echo "fogona LinuxBoot: Boot Manager, booting the default entry in 10 s."
	# What is fogona's: Remote UI on the USB network, the panel (not in
	# its generated set yet), this stage's logs, and in a dev build the
	# one-shot request record_boot copied.
	BMARGS="-listen 172.16.42.1 -panel /etc/bootmanager/motorola-fogona.json"
	BMARGS="$BMARGS -logs /tmp/uinit.log,/tmp/record_boot.log"
	[ -e /etc/bootmanager/dev ] && BMARGS="$BMARGS -dev-once /tmp/dev-once"
	bootmanager $BMARGS 2>&1 | tee -a /tmp/uinit.log
	echo "fogona LinuxBoot: bootmanager exited, falling back"
	sshd -port 22 -keys /etc/ssh/authorized_keys -privatekey /etc/ssh/ssh_host_rsa_key > /tmp/sshd.log 2>&1 &
fi

echo "fogona LinuxBoot: booting the default entry in 10 s."
echo "To stay: ssh -i out/linuxboot/ssh/id_ed25519 root@172.16.42.1 'touch /tmp/hold'"
gosh /etc/fogona-boot.sh 2>&1 | tee -a /tmp/uinit.log

# Reached only when held or when the boot failed. gosh kills its background
# jobs when it exits, sshd and unudhcpd included, so it must not exit.
wait
