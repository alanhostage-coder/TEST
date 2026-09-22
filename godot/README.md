# PUA Godot migration

This directory is the new 3D implementation. The HTML/canvas build remains preserved as the design reference.

Acceptance rule: if a road, yard, light or transmitter makes the player think "I wonder what's over there?", they must be able to physically drive towards it.

First slice: Godot Mobile renderer, real 3D collision space, reversible free driving, chase camera, deterministic streamed world cells. No missions, scores, streaks or completion state. AI EYES remains identity-free.

## 0.76 geographic and projector baseline

- The start patch is `patches/eh15_2bz.json`, centred on the verified postcodes.io
  centroid `55.951507,-3.107122`. That origin is not a surveyed window position.
- Roads, junction topology, footprints, street names and mapped POIs come from
  source-dated OpenStreetMap data. OSM attribution remains visible.
- PC Max and Projector Max show the nearest genuine mapped road, its distance,
  source date and map-frame coordinate. Press `M` to hide or restore the map.
- Each road width and building height says whether it is OSM-tagged or estimated.
  Generic facade treatment is visual only and is not a claim about a real facade.
- ThinkPad and Projector Max retain the exact polygon footprint for every building
  in the packaged EH15 patch. Their in-world street and place labels are capped and
  distance-limited to protect the low-spec frame budget.
- Projector Max starts in five-surface mode: three bay shutters and two separate
  wall windows. `LAYOUT` switches to the optional three-bay-only mode. Driving
  controls fade after six idle seconds and return immediately on mouse movement.
- Projector instruments, sight marker and opening credit follow the calibrated
  forward shutter instead of the geometric centre of the complete 16:9 canvas.
- `CAL` supports mouse/touch corner warping, surface selection and whole-panorama
  yaw. Black gaps mask walls and frames. `SAVE` persists both layouts; `RESTORE`
  recovers the calibration that existed before the last save or reset.
- The layout is deliberately marked unmeasured until calibrated to the closed
  shutters. The supplied open-shutter photographs are references, not survey data.
- `F6` cycles live, clear, rain and fog; the HUD always names the active source.
  `F5` toggles projector driving view, `F7` switches the saved 3/5 layout and
  `F8` shows rolling average, P95 and hitch-count frame-pacing evidence.
