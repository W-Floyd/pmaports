# fogona LinuxBoot stage 1: pick a boot entry and hand over to it. Run by
# gosh, from the uinit or by hand over SSH (`gosh /etc/fogona-boot.sh`).
#
# u-root's boot finds the entries -- pmOS's extlinux.conf on the microSD
# card -- and shows its menu: the entries, then Reboot and Shell. It reads
# the console, which has no keyboard on this phone, so on the console it
# takes the default entry after 10 s; over SSH it is an ordinary menu. With
# -no-exec it only loads the chosen kernel; kexec -e below starts it.
#
# Everything the handover on this SoC needs happens in the stage kernel
# during kexec -e (investigations/boot-chain.md, "LinuxBoot"): the normal
# device_shutdown() -- msm's shutdown hands the display over cleanly -- and
# then, from syscore shutdown, qcom_glink_ssr's do_cleanup for "apss", which
# makes RPM open rpm_requests afresh for the next kernel.
#
# touch /tmp/hold (over SSH, during the menu's countdown) to stop after the
# load: the entry is loaded but not started, and `kexec -e` is up to you.

boot -no-exec || exit 1

if [ -e /tmp/hold ]; then
	echo "fogona-boot: /tmp/hold exists, not handing over"
	exit 0
fi

sync
kexec -e
