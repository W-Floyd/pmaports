# The Adreno 610 is disabled in fogona's device tree -- the zap shader it needs
# is vendor firmware we cannot load yet -- but msm still registers a render
# node. Mesa then selects freedreno by kernel driver and fails on a GPU that
# is not there:
#
#   MESA: error: get_param:235: get-param failed! -6 (No such device or address)
#   MESA-EGL: warning: egl: failed to create dri2 screen
#
# wlroots gets no EGL, falls through to Vulkan, fails there too and gives up,
# so the compositor never starts. Point Mesa at the software KMS driver
# instead. Note LIBGL_ALWAYS_SOFTWARE does not help here: wlroots hands Mesa an
# explicit GBM device, so driver selection follows the kernel driver regardless.
export MESA_LOADER_DRIVER_OVERRIDE=kms_swrast
# Kept as a correctness measure for software rendering, which produces linear
# buffers, not as a fix for anything proven. It was added on the theory that
# mismatched tiling against the DPU's compressed modifiers caused the black
# blocks and tearing seen on this device -- and it did NOT resolve them, which
# also rules out client-buffer tiling as the cause. The real cause is still
# open; see TODO.md.
export WLR_DRM_NO_MODIFIERS=1
