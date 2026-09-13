# Agents Chat brand

`agentschat-mark.svg` is the canonical source for the approved three-bubble logo.
`approved-reference.png` records the user's selected artwork. The lower-right
bubble intentionally has **two tips**. Do not "correct" it to a single tail.

- Web and light backgrounds: cyan `#00BCD4` with transparent surroundings.
- App launchers: white mark on charcoal `#11161C`.
- Keep all three bubbles and the lower-right bubble's two tips at every size.
- Audio waveforms used by audio controls are functional icons, not brand marks.

Run `node tool/generate-brand-assets.mjs` from the repository root after
installing the existing Web dependencies (`npm ci` in `web/`). The generator
uses Web's `sharp` dependency and writes the inventory in `asset-manifest.json`:
Web SVG/PNG/ICO, install icons, React path data, Flutter assets, Android legacy /
adaptive / monochrome icons, iOS icon and launch-image catalogs, Windows ICO,
and README branding. No credentials or image generation API are needed.

Android adaptive artwork is contained in the central safe area of a 108dp layer;
see [Android's adaptive icon guidance](https://developer.android.com/develop/ui/compose/system/icon_design_adaptive).
iOS launcher PNGs are opaque, with platform-owned corner masking. Historical
audit screenshots, third-party research assets, and unrelated UI icons are not
current brand resources.
