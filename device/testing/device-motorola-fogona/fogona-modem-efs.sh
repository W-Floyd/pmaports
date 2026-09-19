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
# <storage_dir>/modem_fs1, modem_fs2, modem_fsc. modem_fsg is deliberately
# absent -- this modem never asks rmtfs for fsg, it fetches it over tqftpserv.
set -eu

EFS_DIR="/var/lib/rmtfs"

# One copy, ever. Re-copying would discard everything the modem has persisted
# since, which is the whole point of this script.
[ -e "$EFS_DIR/.copied" ] && exit 0

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

copy_one modemst1 modem_fs1
copy_one modemst2 modem_fs2
copy_one fsc      modem_fsc

sync
touch "$EFS_DIR/.copied"
