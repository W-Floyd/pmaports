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
# WLR_DRM_NO_MODIFIERS is GONE as of r21, and this file is now empty of
# overrides. It took four explanations to get there, three of them wrong:
#
#   1. "A correctness measure for software rendering's linear buffers." The
#      original guess, which made it look like a workaround that would retire
#      with the GPU.
#   2. "Vestigial now that the GPU renders." The conclusion when the
#      full-screen black blocks cleared on their own.
#   3. "UBWC modifiers are mishandled in the A610 path." Removing it in r18
#      produced a GPU fault and a black wallpaper, which looked like proof:
#
#        adreno 5900000.gpu: [drm:a6xx_irq] *ERROR* gpu fault ring 0
#          fence 1a72 status 00ED14E5
#        msm_dpu: [drm:recover_worker] *ERROR* hangcheck recover!
#          offending task: phoc
#
#   4. The actual answer (2026-09-11): that fault was the zonda PLL bug, not
#      the modifiers. zonda_pll_adjust_l_val() wrote a frequency in Hz into
#      the PLL's L field, so three of the six GPU OPPs ran at the wrong clock
#      -- the 600 MHz one at 14.4 MHz -- which tripped the drm hangcheck. The
#      black wallpaper was the *consequence*: recovery loses the client's
#      rendering context and a wallpaper is drawn once and never re-damaged,
#      so it stays black. It was never a UBWC symptom.
#
# With the PLL fixed, a real phosh session runs with modifiers enabled, the
# stock A610 highest_bank_bit of 13, a correct screen and zero GPU faults.
# Verified further with a live A/B on a runtime override: hbb 13 renders
# clean, hbb 14 corrupts, same session, nothing else changed. So upstream's
# a610 value is right for a Mesa stack, even though the vendor driver uses 14
# for its own blob.
#
# If this ever needs a workaround again, prefer FD_MESA_DEBUG=noubwc over this
# flag: it keeps tiling and disables only compression, where this forces a
# linear scanout buffer.
