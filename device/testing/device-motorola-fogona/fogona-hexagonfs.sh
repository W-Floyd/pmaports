#!/bin/sh
# Build the tree hexagonrpcd serves to the ADSP's sensors process (sensorspd),
# from this handset's own stock partitions as msm-firmware-loader mounts them.
# Nothing is redistributed: configs are symlinked from vendor, the registry is
# seeded once from persist into a writable directory (the ADSP writes to it).
#
# hexagonrpcd maps the ADSP's Android paths onto the root it is given (-R):
#   /mnt/vendor/persist/sensors/registry/  -> <root>/sensors/registry/
#   /vendor/etc/sensors/config/             -> <root>/sensors/config/
#   /vendor/etc/sensors/sns_reg_config      -> <root>/sensors/sns_reg.conf
#   /sys/devices/soc0/                      -> <root>/socinfo/
# Without it the sensor registry cannot read sns_reg_version and the ADSP
# crash-loops (err_qdi fatal in sensor_process / SNS_REG_TASK).
set -e
FW=/run/msm-firmware-loader/mnt
ROOT=/run/hexagonfs
STATE=/var/lib/fogona-hexagonfs

[ -d "$FW/vendor_a/etc/sensors/config" ] || { echo "vendor sensors config not mounted"; exit 1; }

rm -rf "$ROOT"
mkdir -p "$ROOT/sensors" "$ROOT/socinfo"
ln -s "$FW/vendor_a/etc/sensors/config" "$ROOT/sensors/config"
ln -s "$FW/vendor_a/etc/sensors/sns_reg_config" "$ROOT/sensors/sns_reg.conf"

if [ ! -d "$STATE/registry" ] && [ -d "$FW/persist/sensors/registry" ]; then
	mkdir -p "$STATE"
	cp -a "$FW/persist/sensors/registry" "$STATE/registry"
fi
chown -R fastrpc:fastrpc "$STATE"
ln -s "$STATE/registry" "$ROOT/sensors/registry"

# hexagonrpcd serves <root>/socinfo/ for the ADSP's reads of
# /sys/devices/soc0/. Mainline's soc0 has soc_id and revision but not
# hw_platform, platform_subtype or platform_version, so the set is written out
# with stock's values (out/modem/soc0-stock-20260924.txt in the fogona repo),
# as FP5's and pipa's hexagonfs trees do with theirs.
echo IDP > "$ROOT/socinfo/hw_platform"
echo Unknown > "$ROOT/socinfo/platform_subtype"
echo 0 > "$ROOT/socinfo/platform_subtype_id"
echo 65536 > "$ROOT/socinfo/platform_version"
echo 1.0 > "$ROOT/socinfo/revision"
echo 518 > "$ROOT/socinfo/soc_id"
