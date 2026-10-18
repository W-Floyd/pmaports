#!/opt/ap/bin/busybox ash
# kexec-tools with its libraries: the Boot Manager's -kexec for entries it
# cannot load itself (32-bit ARM).
#
# --image-size: this kernel is linked at TEXT_OFFSET 0x208000 (multi_v7's
# ARCH_MESON), but kexec-tools assumes 0x8000 and puts the initramfs right
# after its estimate of the kernel. The zImage decompressor then copies itself
# to just past the real kernel end, over the start of the initramfs ("Unable to
# mount root fs"). 0x3200000 puts the initramfs clear of it (see rekexec.sh).
export LD_LIBRARY_PATH=/opt/ap/lib
exec /opt/ap/bin/kexec --image-size=0x3200000 "$@"
