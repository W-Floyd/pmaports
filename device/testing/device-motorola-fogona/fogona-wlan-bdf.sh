#!/bin/sh
# Build ath10k board data for this handset out of its own calibration blob.
#
# WHY THIS EXISTS
#
# ath10k reads WLAN board data from one board-2.bin, a container indexed by
# board name. Upstream linux-firmware ships one with 36 WCN3990 entries and
# none of them is fogona's: this handset resolves the generic
# "bus=snoc,qmi-board-id=ff" fallback, which is board data for somebody else's
# radio. The right blob is already on the device -- Motorola ships it in the
# modem partition as bdwlan_fogona_ipa.bin, and msm-firmware-loader links it
# flat into the firmware search path. It is 26328 bytes, exactly the payload
# size of every WCN3990 entry upstream ships, because it is the same kind of
# blob; putting it to use is a container operation and nothing more.
#
# It cannot be packaged. Motorola publishes no redistributable firmware bundle,
# so unlike Thundercomm's RB2 -- whose board file was accepted upstream as
# "bus=snoc,qmi-board-id=ff,qmi-chip-id=150,variant=Thundercomm_RB2", the same
# chip id as this device -- fogona's blob may not be shipped in a package or
# submitted to linux-firmware. Repacking it here, on the handset, from the file
# the handset already carries, is what keeps that true: nothing is copied and
# nothing leaves.
#
# ORDERING: this must run before anything starts the modem. ath10k_snoc loads
# early but does not fetch board data until the WLFW QMI service appears, and
# WLFW appears only once the modem boots -- which rmtfs does. So "before rmtfs"
# is the real deadline, not "before the ath10k module", and that is what the
# unit orders against.
#
# The output goes in the firmware search root rather than /usr/lib/firmware, so
# it shadows any packaged board-2.bin without owning or deleting the file --
# the search path is consulted first. Read the root from sysfs rather than
# hardcoding it, the way tqftpserv derives its own prefix.
set -eu

# WHICH PA VARIANT
#
# fogona ships in two hardware builds and the modem image carries a calibration
# blob for each: _ipa (internal power amplifier) and _epa (external). They are
# not interchangeable -- they differ in 2606 bytes, the ePA file carrying a
# populated amplifier gain curve where the iPA file is zeroed, and TX gain
# entries about 5 units higher throughout.
#
# Which one a unit needs is NOT discoverable from the radio. It follows the
# carrier SKU, and the vendor partition's own cnss-daemon carries the table:
#
#     rhode    all   ipa
#     fogona   ATT   ipa
#     fogona   RET   epa
#
# So: AT&T units are internal-PA, everything else external. The per-unit SKU is
# in Motorola's utags partition, which is readable straight from Linux. Derive
# it rather than hardcoding, because a hardcoded guess is exactly what was wrong
# here before -- this device is RET and the port assumed _ipa for months.
# The utag is stored as the name string "ro.carrier:str" followed by its value
# as the next string in the blob, so take the line after the name, not the name.
carrier=$(strings /dev/disk/by-partlabel/utags 2>/dev/null |
          grep -A1 -m1 '^ro\.carrier:' | tail -1)
case "$carrier" in
	att*|ATT*) BDF_NAME=bdwlan_fogona_ipa.bin ;;
	*)         BDF_NAME=bdwlan_fogona_epa.bin ;;
esac

SEARCH_ROOT=$(cat /sys/module/firmware_class/parameters/path 2>/dev/null || true)
[ -n "$SEARCH_ROOT" ] || SEARCH_ROOT=/run/msm-firmware-loader/target

BDF="$SEARCH_ROOT/$BDF_NAME"
OUT_DIR="$SEARCH_ROOT/ath10k/WCN3990/hw1.0"
OUT="$OUT_DIR/board-2.bin"

# Not an error worth failing the boot over: without the vendor partition
# mounted there is simply no blob to repack, and ath10k falls back to whatever
# generic board-2.bin is installed. Say so and leave.
if [ ! -r "$BDF" ]; then
	echo "fogona-wlan-bdf: $BDF not readable, leaving board data alone" >&2
	exit 0
fi

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Two names for one blob. The first is what ath10k asks for once the board DTS
# carries qcom,calibration-variant; the second is the board-id-only fallback it
# asks for without one, which is also what it resolves today. Carrying both
# means this file works either side of that DTS change.
cat > "$WORK/board.json" <<EOF
[
	{
		"names": [
			"bus=snoc,qmi-board-id=ff,qmi-chip-id=150,variant=Motorola_fogona",
			"bus=snoc,qmi-board-id=ff"
		],
		"data": "$BDF_NAME"
	}
]
EOF

cp "$BDF" "$WORK/$BDF_NAME"
(cd "$WORK" && ath10k-bdencoder --create board.json --output board-2.bin)

mkdir -p "$OUT_DIR"
cp "$WORK/board-2.bin" "$OUT"
echo "fogona-wlan-bdf: wrote $OUT from $BDF_NAME (carrier '${carrier:-unknown}')"
