#!/opt/ap/bin/busybox ash
# Bring the Bluetooth controller up and show what it says, for the first tries
# on the head unit: run it over ssh, then read /tmp/bt-up.log (also shown on the
# Boot Manager's Log screen). hci_bcm holds the chip in reset (BT_RESET, gpc 13)
# from probe and powers it on when the controller is opened here; the patch is
# downloaded from /run/fwl/target/brcm/ (firmware_class.path) at 115200
# (BCM4349B1.hcd or BCM.hcd). The stage's uinit has the firmware loader copy
# them off the stock system partition (read-only) at boot: the stock
# bcm4349.hcd = L2101, and bcm4349.hcd_E0300 beside it for "e0300".
#
#   bt-up.sh            bring hci0 up, print its state and the kernel's lines
#   bt-up.sh e0300      try the E0300 patch instead of L2101

export LD_LIBRARY_PATH=/opt/ap/lib
BB=/opt/ap/bin/busybox
LOG=/tmp/bt-up.log

if [ "$1" = e0300 ]; then
	# The patch files are copies in RAM, where firmware_class.path points.
	$BB cp /run/fwl/target/brcm/bcm4349.hcd_E0300 /run/fwl/target/brcm/BCM4349B1.hcd
	$BB cp /run/fwl/target/brcm/bcm4349.hcd_E0300 /run/fwl/target/brcm/BCM.hcd
fi

{
	echo "--- $($BB date) hci_bcm / uart1:"
	$BB ls /sys/class/bluetooth 2>&1
	$BB ls -l /dev/ttyAMA1 2>&1
	echo "--- hciconfig hci0 up"
	/opt/ap/bin/hciconfig hci0 up 2>&1
	$BB sleep 3
	echo "--- hciconfig -a"
	/opt/ap/bin/hciconfig -a 2>&1
	echo "--- kernel"
	dmesg | $BB grep -i "bluetooth\|bcm\|hci\|ttyAMA1\|serial@16610000\|1661" | $BB tail -n 30
} > $LOG 2>&1
$BB cat $LOG
