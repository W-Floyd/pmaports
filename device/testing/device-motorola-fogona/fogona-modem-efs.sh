#!/bin/sh
# Give the modem a writable copy of its EFS.
#
# rmtfs ships with -r, which does NOT make writes fail -- storage.c keeps them
# in a RAM shadow buffer and storage_sync() returns success without touching
# storage. The modem therefore believes it persisted state that is thrown away
# at reboot, and nothing logs an error. The visible symptom here was the carrier
# MCFG: activating it answered SUCCESS, the modem wrote its selection to EFS,
# and the config still read "Pending" forever instead of "Active".
#
# The fix is NOT to point rmtfs at the real partitions with -P and no -r.
# Writing them is what stock Android does, but it also means our modem and
# Android share mutable state, which pmaports MR !4674 (caleb/sdm845-rw-efs)
# deliberately avoids. Copy the EFS out once instead and let rmtfs write the
# copies; the accompanying drop-in points it here with -o.
#
# Names come from storage.c's partition_table: without -P, rmtfs resolves
# <storage_dir>/modem_fs1, modem_fs2, modem_fsc, modem_fsg.
#
# modem_fsg USED to be left out, on the grounds that this modem fetches fsg
# over tqftpserv and never asks rmtfs for it. That was true of the Consumer
# Cellular MPSS .91 build and is FALSE of the retail .98 one, which asks rmtfs
# directly -- and the failure is brutal rather than graceful: the modem takes
# an ERR_FATAL and the kernel restarts it, forever.
#
#     fs_rmts_pm.c:997:[3, 1] rmts_read_iovec failed      x81 in one boot
#     rmtfs: failed to open '/var/lib/rmtfs/modem_fsg': No such file or directory
#
# Measured 2026-09-21: 59 modem restarts in one boot, ModemManager saw no modem
# at all, and **WiFi was dead as collateral** -- ath10k_snoc binds but waits for
# the WLFW QMI service, which a crash-looping modem never publishes, so wlan0
# never appeared. Adding modem_fsg took it to 0 failures and wlan0 came back.
# Do not "simplify" this back out.
#
# fsg is the one that is slot-suffixed (fsg_a / fsg_b); modemst1, modemst2 and
# fsc are not.
set -eu

EFS_DIR="/var/lib/rmtfs"

mkdir -p "$EFS_DIR"

copy_one() {
	_src="/dev/disk/by-partlabel/$1"
	_dst="$EFS_DIR/$2"

	if [ ! -e "$_src" ]; then
		echo "fogona-modem-efs: $_src missing, skipping" >&2
		return 0
	fi

	dd if="$_src" of="$_dst.tmp" bs=64k status=none
	mv "$_dst.tmp" "$_dst"
}

# fsg first, and NOT behind the .copied guard, so that an install predating
# this addition picks it up on its next boot instead of crash-looping. Guarded
# on the file being absent rather than on .copied: fsg is reference data the
# modem reads, but it is still reached through rmtfs and may be written, so it
# gets copied once and then left alone.
if [ ! -e "$EFS_DIR/modem_fsg" ]; then
	_slot=$(sed -n 's/.*androidboot\.slot_suffix=\([a-z_]*\).*/\1/p' /proc/cmdline)
	copy_one "fsg${_slot:-_a}" modem_fsg
	sync
fi

# One copy, ever, for the rest. Re-copying would discard everything the modem
# has persisted since, which is the whole point of this script.
[ -e "$EFS_DIR/.copied" ] && exit 0

copy_one modemst1 modem_fs1
copy_one modemst2 modem_fs2
copy_one fsc      modem_fsc

sync
touch "$EFS_DIR/.copied"
