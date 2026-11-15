# Siloy UKI Apps official brand source

This directory contains the eight **exact SVG files provided by Siloy** for the SUKI app suite. The official vector marks replace photographic signage/logo crops. Do not redraw the Siloy wordmark in a generic sans-serif font.

## Product system

- **Siloy Notes**: secure-context note capture, review and follow-up. Use the black Siloy logo on a pale CRM card; label internal-only content explicitly without implying the label enforces access control.
- **Siloy Time**: time logs, billing and projects. Use the same lockup size, colour rail and native card rhythm as Notes.
- **Siloy Surface**: visual workroom. Use the same logo and palette, but the full browser canvas may load CSS fonts.

All three use one wordmark, a separate product name, consistent muted supporting copy, rounded cards and clear primary actions. Avoid making the whole HubSpot CRM page look like a new application skin; native HubSpot controls should remain familiar.

**Colours:** Ink `#010103`, charcoal `#2B2B2B`, blue `#DAEAFF`, yellow `#FEF5AC`, mint `#EAFDD6`.

**Fonts:** Instrument Sans (interface), Instrument Serif Italic (product-name/display treatments) and Inter Tight (dense labels/data). The user-provided family packages contain OFL licences. The font binaries are not committed or distributed here. For externally hosted apps, use an approved font service or self-hosted fonts under the organisation's licensing and hosting rules. HubSpot UI extension components do not support arbitrary custom font injection.

**Logo variants:** `siloy-logo-black.svg` for light surfaces; `siloy-logo-white.svg` for dark surfaces; `siloy-we-mark-*.svg` for compact icon treatments; `siloy-we-relate-*.svg` for separate brand contexts. Do not use the tagline as an app title or force it into the narrow CRM sidebar.

## Development hygiene

- The official vector files under `brand/official/` are preserved exactly as uploaded.
- Reuse the SUKI portal-scoped installer and resolve custom object IDs per portal.
- Keep the app names and products independent.
- Validate logo visibility, WCAG-readable controls, all supported HubSpot record placements and dark/light usage.
- Never describe a card as access-restricted just because its label reads “Internal only”.
