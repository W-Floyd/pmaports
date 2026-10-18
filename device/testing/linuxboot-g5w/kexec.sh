#!/opt/ap/bin/busybox ash
# kexec-tools with its libraries: the Boot Manager's -kexec for entries it
# cannot load itself (32-bit ARM).
export LD_LIBRARY_PATH=/opt/ap/lib
exec /opt/ap/bin/kexec "$@"
