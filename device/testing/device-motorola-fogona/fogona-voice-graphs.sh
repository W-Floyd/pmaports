#!/bin/sh
# Build the voice-call graph files for this handset out of its own ACDB.
#
# WHY THIS EXISTS
#
# The call-audio PoC (/repo/investigations/call-audio.md) opens stock's voice
# graphs on the ADSP: the voice RX and TX sub-graphs, their connections and
# their calibration, as stock's audio HAL reads them from the ACDB in the
# vendor partition (etc/acdbdata/bengal_idp). They are Motorola's and
# Qualcomm's calibration data and cannot be shipped. So, as fogona-wlan-bdf
# does with the WLAN calibration blob, this builds them on the handset from
# the file the handset already carries: acdbdump (Qualcomm's open-source ACDB
# library behind a small CLI) reads the ACDB, and fogona-voice-graphs.py
# merges the pieces. Nothing is copied off the device and nothing is shipped.
#
# WHERE THE OUTPUT GOES
#
# The kernel's q6apm-voice-poc asks for qcom/sm6225/voice-*.bin with
# request_firmware(). msm-firmware-loader's search root is flat and has no
# qcom/ tree, so the lookup falls through to the default paths, of which
# /usr/lib/firmware/updates comes before /usr/lib/firmware: it is meant for
# local overrides and no package owns it, so generated files there collide
# with nothing and survive package upgrades.
#
# It runs on every boot (under a second): if a system update changes the
# vendor partition's ACDB, the graphs follow it.
set -eu

OUT=/usr/lib/firmware/updates/qcom/sm6225

# msm-firmware-loader mounts the active slot's vendor partition here.
ACDB=
for d in /run/msm-firmware-loader/mnt/vendor*/etc/acdbdata/bengal_idp; do
	[ -f "$d/IDP_acdb_cal.acdb" ] || continue
	ACDB=$d/IDP_acdb_cal.acdb
	QWSP=$d/IDP_workspaceFileXml.qwsp
	break
done
if [ -z "$ACDB" ]; then
	echo "fogona-voice-graphs: no ACDB under /run/msm-firmware-loader/mnt" >&2
	exit 1
fi

mkdir -p "$OUT"
exec /usr/libexec/fogona-voice-graphs.py --acdbdump /usr/bin/acdbdump \
	--acdb "$ACDB" --qwsp "$QWSP" --out "$OUT"
