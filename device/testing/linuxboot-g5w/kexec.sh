#!/opt/ap/bin/busybox ash
# kexec-tools with its libraries: the Boot Manager's -kexec for entries it
# cannot load itself (32-bit ARM). The kexec-tools here is a git build
# (device/testing/kexec-tools) that places the initramfs past the kernel's own
# TEXT_OFFSET; release 2.0.32 assumed 0x8000.
export LD_LIBRARY_PATH=/opt/ap/lib
exec /opt/ap/bin/kexec "$@"
