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
# Software rendering produces linear buffers while the DPU advertises
# compressed modifiers; mismatched tiling shows up as black blocks and tearing.
export WLR_DRM_NO_MODIFIERS=1
