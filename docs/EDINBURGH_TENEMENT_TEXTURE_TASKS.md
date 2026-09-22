# Edinburgh Tenement Texture System — Repo Task List

Target: XPS 15 9530 build first. Preserve mapped geometry and provenance. Generic facade materials must never imply surveyed facade accuracy.

## Definition of done

The task is complete when:
- generic Edinburgh sandstone buildings no longer read as flat procedural boxes at normal driving distance;
- most ordinary tenement streets use a small reusable material/facade system with deterministic variation;
- named or protected landmarks are excluded from generic replacement;
- OSM footprint geometry, map placement and source metadata remain unchanged;
- projector continuity and calibration remain unchanged;
- the XPS 15 9530 build passes parse, soak, five-surface proof, XPS invariants, export and installer;
- Max-HD and projector screenshots show materially better facade rhythm without obvious tiling or clone repetition.

## Phase 0 — Guardrails

- [ ] Add a short provenance comment beside the facade assignment code: generic facade treatment is visual approximation only.
- [ ] Add a building metadata flag for generic facade treatment, e.g. `facade_visual_source = "generic_edinburgh_tenement_kit"`.
- [ ] Add or preserve a landmark/protected-building escape hatch. Named/iconic buildings must be able to opt out.
- [ ] Keep all existing OSM footprint, road, opening-anchor and source-date logic unchanged.
- [ ] Do not generate exact shop names, plaques, house numbers or landmark ornament unless sourced.
- [ ] Add a CI invariant that generic facade code does not alter mapped building counts or exact-footprint counts.

## Phase 1 — Asset folders and naming

Create:

```
godot/assets/edinburgh_tenement/
  walls/
  windows/
  doors/
  shopfronts/
  decals/
  normals/
  masks/
```

- [ ] Use texture naming pattern `edin_ten_[category]_[family]_[variant]_[maptype].png`.
- [ ] Map suffixes: `alb`, `nrm`, `rgh`, `ao`, `msk`.
- [ ] Keep v1 wall/window/shop atlases at 2048² maximum.
- [ ] Keep decal/detail-normal atlases at 1024² maximum.
- [ ] Store only game-ready PNG/WebP assets in the runtime folder. Keep source-generation prompts or working files outside the exported asset tree if large.
- [ ] Confirm import settings avoid unnecessary mip/VRAM waste on masks and decals.

## Phase 2 — Minimum v1 texture pack

### Walls
- [ ] `edin_ten_wall_clean_a_*`
- [ ] `edin_ten_wall_weathered_a_*`
- [ ] `edin_ten_wall_soot_a_*`
- [ ] `edin_ten_wall_damp_a_*`
- [ ] `edin_ten_wall_patched_a_*`

Each needs:
- [ ] albedo
- [ ] normal
- [ ] roughness
- [ ] optional AO if it survives visual testing

### Windows
- [ ] standard sash A
- [ ] standard sash B
- [ ] wider sash
- [ ] bay-panel window
- [ ] top-floor/attic variant
- [ ] lit/unlit mask variants
- [ ] curtain/blind mask variants

### Doors / closes
- [ ] common close entrance
- [ ] darker recessed close
- [ ] painted residential door
- [ ] simple service/basement door

### Shopfronts
- [ ] painted timber shopfront
- [ ] modern glazed shopfront
- [ ] roller shutter
- [ ] vacant/boarded frontage
- [ ] generic fascia mask with no invented business name

### Decals
- [ ] soot streaks
- [ ] damp streaks
- [ ] stone repair patches
- [ ] drainpipe
- [ ] cable/conduit
- [ ] base-course grime

## Phase 3 — Godot material layer

Create:
- [ ] `godot/edinburgh_tenement_material.gd` for material/atlas selection helpers.
- [ ] `godot/edinburgh_tenement_rules.gd` for deterministic building classification.
- [ ] Optional shader only if StandardMaterial3D cannot deliver the effect cheaply enough.

Material parameters:
- [ ] stone family
- [ ] stone tint
- [ ] roughness variation
- [ ] grime amount
- [ ] damp amount
- [ ] repair-patch amount
- [ ] lit-window probability
- [ ] window family
- [ ] ground-floor family
- [ ] deterministic seed

Performance rules:
- [ ] Prefer shared materials/atlases over one material instance per window.
- [ ] Avoid per-building shader permutations that explode draw calls.
- [ ] Keep secondary facade geometry shadowless on XPS five-view mode unless it is visibly useful.
- [ ] Use distance limits for decals/detail planes.
- [ ] No transparent material where alpha-tested/cutout or opaque atlas geometry can do the same job.

## Phase 4 — Deterministic classification

Integrate into `godot/world.gd` near the existing Edinburgh building generation path, especially `_add_edinburgh_building(...)`.

Add classes:
- [ ] `TENEMENT_STD`
- [ ] `TENEMENT_SHOPGROUND`
- [ ] `TENEMENT_BAY`
- [ ] `TENEMENT_CORNER`
- [ ] `CIVIC_STONE`
- [ ] `LANDMARK_CUSTOM`

Classification inputs may use only source-backed or geometric facts already available:
- [ ] building kind/use
- [ ] footprint dimensions
- [ ] road-facing frontage
- [ ] corner condition from mapped geometry
- [ ] named/protected status
- [ ] floor/height data when sourced

Do not infer:
- [ ] exact historic style
- [ ] exact shop identity
- [ ] exact facade age
- [ ] exact stone quarry/material provenance

## Phase 5 — Stable variation

- [ ] Derive one deterministic visual seed from the OSM building identifier or stable mapped geometry key.
- [ ] Never use frame time or `Time.get_ticks_msec()` for facade selection.
- [ ] Seed chooses wall family, tint, window family, grime, damp, patching and shopfront family.
- [ ] Nearby buildings should not all receive the same wall family.
- [ ] Prevent high-frequency random noise. Variation should read building-by-building, not window-by-window chaos.
- [ ] Add a repeat suppressor so identical neighbouring facade combinations are re-rolled deterministically.

Suggested weighted wall distribution for ordinary tenements:
- [ ] weathered neutral: 40%
- [ ] warm/clean: 20%
- [ ] soot dark: 18%
- [ ] damp: 12%
- [ ] patched/mixed: 10%

These are visual starting weights only, not historic claims.

## Phase 6 — Facade rhythm geometry

Refactor the current procedural frontage detail so it works in modules:

Vertical bands:
- [ ] ground-floor band
- [ ] repeated mid-floor band
- [ ] top-floor/cornice band
- [ ] parapet/roofline band

Horizontal modules:
- [ ] one sash bay
- [ ] one close-door bay
- [ ] one shop bay
- [ ] optional bay-window module

Requirements:
- [ ] Module count derives from mapped frontage width.
- [ ] Windows remain subordinate to the mapped building shell.
- [ ] Ground floor gets higher detail density than upper floors.
- [ ] Rear/hidden facades use cheaper treatment.
- [ ] Small or distant buildings may use texture-only facades.
- [ ] Large close-up buildings may use shallow geometric sills/cornices.

## Phase 7 — Stone material treatment

- [ ] Replace large flat colour blocks with tiled sandstone material.
- [ ] Add subtle per-building tint within a restrained range.
- [ ] Add darker plinth/base-course treatment.
- [ ] Add soot/damp overlays biased toward edges, downpipes and lower courses.
- [ ] Keep normals shallow enough to avoid a fake brick-wall look.
- [ ] Add mild roughness variation.
- [ ] Rain mode should darken stone slightly and increase specular response without turning sandstone into plastic.

## Phase 8 — Windows

- [ ] Use shared sash atlas.
- [ ] Keep window proportions consistent with existing storey spacing.
- [ ] Add deterministic curtain/blind/lit masks.
- [ ] Use emissive windows only at appropriate lighting states.
- [ ] Cap lit-window density so every block does not glow.
- [ ] Avoid fully transparent glass on every window if it harms five-view performance.
- [ ] Add shallow sill/lintel geometry only within driver-detail radius.

## Phase 9 — Ground-floor shop/close treatment

- [ ] Detect suitable road-facing fronts.
- [ ] Add generic shopfront modules to likely commercial buildings.
- [ ] Keep signage generic/abstract unless sourced.
- [ ] Add recessed close entrances to residential tenements.
- [ ] Add shutters/boarded variants sparingly.
- [ ] Keep shopfront materials visually varied but within a muted Edinburgh street palette.
- [ ] Prevent shopfronts on obviously unsuitable mapped building kinds.

## Phase 10 — Decal system

- [ ] Add a small reusable decal/quad pool.
- [ ] Deterministically place damp, soot, repairs, pipes and cables.
- [ ] Cap decals per facade.
- [ ] Apply distance culling.
- [ ] Keep decals out of landmark/custom buildings unless explicitly allowed.
- [ ] No invented graffiti/text in this system.

## Phase 11 — XPS 15 9530 performance budget

Target the active reference build only for visual tuning.

- [ ] Measure before/after render proof sizes and runtime soak.
- [ ] Keep five-surface XPS pixel allocation unchanged unless separately justified.
- [ ] Keep centre-pane priority.
- [ ] Disable secondary facade shadows in XPS five-view mode.
- [ ] Cull expensive detail outside driver-relevant radius.
- [ ] Prefer texture detail over geometry on peripheral wall panes.
- [ ] Do not lower mapped building count to pay for facade work.
- [ ] Do not reduce source-backed landmark visibility to pay for facade work.
- [ ] Add a simple runtime counter/meta field for high-detail facade count if useful for proof diagnostics.

## Phase 12 — Max-HD laptop presentation

- [ ] Capture a 1920×1080 laptop screenshot after v1 facade integration.
- [ ] Compare against the existing `pua-xps-laptop-max-hd.png` proof.
- [ ] Check: stone reads as stone, not coloured boxes.
- [ ] Check: repeated windows feel architectural rather than procedurally noisy.
- [ ] Check: ground floors break repetition.
- [ ] Check: road remains the strongest forward visual cue.
- [ ] Check: no generic facade falsely resembles a protected/named landmark.

## Phase 13 — Projector presentation

- [ ] Capture updated five-surface proof.
- [ ] Check facade texture continuity across panel seams.
- [ ] Check distant facade aliasing on narrow wall panes.
- [ ] Check centre pane remains the sharpest perceptual area.
- [ ] Check no decal or texture treatment creates obvious seam discontinuity.
- [ ] Check wet-weather stone remains legible under projection.

## Phase 14 — CI / regression gates

Update the XPS workflow to verify:
- [ ] strict parse
- [ ] runtime soak
- [ ] five-surface proof
- [ ] Max-HD screenshot exists and is nonblank
- [ ] mapped road count unchanged
- [ ] mapped building count unchanged
- [ ] exact footprint count still equals mapped building count
- [ ] XPS five-view pixel budget remains inside current tolerance
- [ ] generic facade system reports at least one treated tenement in the proof scene
- [ ] landmark/protected override path remains present
- [ ] installer and portable build succeed

## Phase 15 — Visual acceptance pass

At normal driving speed:
- [ ] no obvious texture tiling at 15–60 m
- [ ] no identical neighbour clones
- [ ] no implausibly bright colours
- [ ] no giant normals or fake brick relief
- [ ] no floating windows/doors
- [ ] no shopfronts spanning corners incorrectly
- [ ] no facade changes to mapped footprint geometry
- [ ] sandstone palette reads plausibly under clear, rain and fog
- [ ] frame pacing remains good on the XPS 15 9530

## Recommended implementation sequence

Do these as separate, reviewable commits:

1. [ ] asset folders + provenance guard + stable seed helper
2. [ ] wall atlas + sandstone material assignment
3. [ ] window atlas + deterministic window family selection
4. [ ] modular facade rhythm in `world.gd`
5. [ ] ground-floor close/shop modules
6. [ ] grime/damp/repair decals
7. [ ] wet-weather material response
8. [ ] XPS performance pass
9. [ ] Max-HD + five-surface proof updates
10. [ ] visual regression corrections until green

## First playable milestone

Stop and test after:
- one weathered sandstone wall family,
- one warm sandstone family,
- two sash window variants,
- one close entrance,
- one shopfront,
- soot/damp overlay,
- deterministic per-building selection.

That is enough to decide whether the architectural direction works before producing the full asset pack.
