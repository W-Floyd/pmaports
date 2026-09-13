#!/bin/sh
# Reassemble and flash this device's boot partition whenever /boot changes.
#
# fogona cannot use boot-deploy's bootimg_override_* path (that layout puts the
# FIT in the ramdisk slot, which this bootloader does not hand over), so the
# two scripts below are the equivalent. Wiring them to a trigger is what makes
# `apk upgrade && reboot` pick up a new kernel, the way boot-deploy does on
# every other pmaports device.
#
# The trigger watches /boot rather than the kernel's module directory on
# purpose: the FIT embeds the kernel, the DTB *and* the initramfs, so a
# regenerated initramfs needs a reflash just as much as a new kernel does, and
# postmarketos-mkinitfs writes /boot/initramfs.
#
# Escape hatches, because a package install that rewrites a boot partition is a
# surprise worth being able to switch off:
#
#   /etc/fogona-no-autoflash   exists -> do nothing
#   FOGONA_NO_AUTOFLASH=1      set    -> do nothing
#
# Anything unexpected is a no-op rather than a failure. A trigger that exits
# non-zero makes the whole apk transaction report an error, and the partition
# not being rewritten is never worse than the transaction failing -- the
# previous boot image is still there and still boots.

# Not the handset: a build chroot or an image being assembled has no device
# tree, no boot partition and no u-boot payload. Do nothing, quietly.
compat=$(tr -d '\0' < /proc/device-tree/compatible 2>/dev/null || true)
case "$compat" in
	*motorola,fogona*) ;;
	*) exit 0 ;;
esac

[ -e /etc/fogona-no-autoflash ] && exit 0
[ "$FOGONA_NO_AUTOFLASH" = "1" ] && exit 0

# Both halves must be present and the partition must exist. fogona-flash-boot
# re-checks all of this itself; this is only so the common "not on a real
# device" case never reaches it.
command -v fogona-mkboot > /dev/null 2>&1 || exit 0
command -v fogona-flash-boot > /dev/null 2>&1 || exit 0

echo "==> fogona: reassembling and flashing the boot partition"
if ! fogona-mkboot; then
	echo "fogona: boot image assembly failed -- boot partition left alone" >&2
	exit 0
fi
if ! fogona-flash-boot; then
	echo "fogona: flashing failed -- previous boot image is still in place" >&2
	exit 0
fi
echo "==> fogona: boot partition updated; reboot to run it"

exit 0
