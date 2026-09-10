# Nothing is overridden here any more, and that is the point of this file.
#
# fogona carried three Mesa/wlroots overrides through bringup. All three were
# consequences of the Adreno 610 being disabled in the device tree, and all
# three are gone now that it renders. Kept as a record so nobody reintroduces
# them from another device's config:
#
#   MESA_LOADER_DRIVER_OVERRIDE=kms_swrast  (removed r17)
#     Mesa selected freedreno by kernel driver and failed on a GPU that was
#     not there -- "get_param:235: get-param failed! -6", then no EGL, then
#     wlroots gave up and the compositor never started. LIBGL_ALWAYS_SOFTWARE
#     does not substitute: wlroots hands Mesa an explicit GBM device, so
#     selection follows the kernel driver regardless.
#
#   GSK_RENDERER=cairo  (removed r17)
#     GTK4's GSK renderer defaults to GL and segfaulted under kms_swrast --
#     gsk_renderer_render -> libgtk-4 -> libEGL -> dri2_query_image. Every
#     GTK4 app that drew a frame died the same way.
#
#   WLR_DRM_NO_MODIFIERS=1  (removed r18)
#     A correctness measure for software rendering, which produces linear
#     buffers. It was also tried against the full-screen black blocks and did
#     not resolve them. Those turned out to be a software-rendering artifact
#     and cleared on their own when the GPU came up -- with this flag still
#     set, which is what ruled out client-buffer tiling for good. With real
#     hardware rendering it only costs bandwidth, since it denies the DPU
#     UBWC compression, so it is dropped.
#
# If any of these symptoms return, the GPU has regressed. Check
# `dmesg | grep adreno` and msm's debugfs before re-adding an override --
# restoring one hides the regression instead of fixing it. See HANDOFF.md 7a.
