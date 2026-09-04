# FIXME: Console enabled to workaround a race condition with display initialisation
# See https://gitlab.freedesktop.org/drm/msm/-/issues/46

# prevbl_revision is the board revision the primary bootloader read from
# hardware, forwarded by u-boot's save_prev_bl_data. Nothing else can tell one
# board revision from another once the primary bootloader is gone, and the wifi
# NVRAM is per-revision RF calibration, so pass it on to the OS.
#
# Substituted unconditionally on purpose: if u-boot did not set it this expands
# to an empty value, which the kernel ignores. Guarding it with "test" would
# risk failing the whole boot on a build where that command is absent.
setenv bootargs "console=ttyMSM0,115200 androidboot.revision=${prevbl_revision}"
setenv bootm_size 0x5000000

bootm $prevbl_initrd_start_addr
