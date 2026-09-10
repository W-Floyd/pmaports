# One override remains, and it is load-bearing for a reason that took two
# wrong explanations to pin down.
#
# Removed and staying removed (r17) -- both were consequences of the Adreno
# 610 being disabled in the device tree, and both are gone now that it works:
#
#   MESA_LOADER_DRIVER_OVERRIDE=kms_swrast
#     Mesa selected freedreno by kernel driver and failed on a GPU that was
#     not there -- "get_param:235: get-param failed! -6", then no EGL, then
#     wlroots gave up and the compositor never started. LIBGL_ALWAYS_SOFTWARE
#     does not substitute: wlroots hands Mesa an explicit GBM device, so
#     selection follows the kernel driver regardless.
#
#   GSK_RENDERER=cairo
#     GTK4's GSK renderer defaults to GL and segfaulted under kms_swrast --
#     gsk_renderer_render -> libgtk-4 -> libEGL -> dri2_query_image.
#
# WLR_DRM_NO_MODIFIERS is a different story, and the first two explanations
# for it were both wrong:
#
#   1. "A correctness measure for software rendering's linear buffers." That
#      was the original guess, and it made the flag look like a workaround
#      that would retire with the GPU.
#   2. "Vestigial now that the GPU renders." That was the conclusion when the
#      full-screen black blocks cleared on their own -- it looked like the
#      flag had never done anything.
#
# Removing it in r18 disproved both. With modifiers enabled the compositor
# takes a GPU fault
#
#   adreno 5900000.gpu: [drm:a6xx_irq] *ERROR* gpu fault ring 0 fence 1a72
#     status 00ED14E5
#   msm_dpu: [drm:recover_worker] *ERROR* hangcheck recover!
#     offending task: phoc
#
# and the wallpaper renders black -- a full-screen surface, which is exactly
# what takes a UBWC-compressed modifier. The GPU recovers, so this is a
# corruption/fault pair rather than a hang, and it is reproducible across a
# session restart.
#
# So: UBWC modifiers are mishandled somewhere in the A610 path on this stack.
# Worth chasing properly -- the DPU's UBWC parameters were measured to match
# sm6115_data (see TODO.md 7b history), so the mismatch is more likely on the
# GPU/Mesa side than in the display controller's configuration. Until then
# this flag stays, and it is NOT a software-rendering leftover.
export WLR_DRM_NO_MODIFIERS=1
