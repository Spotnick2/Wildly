# Wildly Changelog

## v0.1.0

Initial Wildly release (Druid fork based on Priestly architecture).

### Added

- Druid-only class gate (addon exits for non-Druid characters).
- Mark of the Wild / Gift of the Wild tracker row.
- Thorns tracker row with configurable eligibility modes:
  - Default (tanks in group/raid, self while solo)
  - Tanks only
  - Self only
  - Everyone
  - Disabled
- Group/single secure click-cast behavior adapted for Druid buffs.
- Popover target list behavior adapted for Druid buff maintenance.
- Gift reagent rank detection and footer reagent count display:
  - Wild Berries
  - Wild Thornroot
  - Wild Quillvine
- Druid-focused options panel:
  - Track Mark/Gift toggle
  - Thorns mode selector
  - Solo visibility, pet tracking, and frame opacity settings
- Druid accent styling (`#FF7C0A`) for core UI elements.
- Druid spec icon logic for Feral Bear, Feral Cat, Balance, and Restoration.

### Removed

- Priest-specific buff logic and Shadow Protection instance mode configuration.
- Priest-specific reagent handling (candles/feather) and related UI copy.
