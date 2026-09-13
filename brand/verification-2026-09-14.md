# Brand replacement verification — 2026-09-14

The approved three-bubble mark, including the lower-right bubble's two tips,
is now the shared source for current product branding. The inventory is in
`asset-manifest.json`; reproduce assets with `node tool/generate-brand-assets.mjs`.

## Coverage

- Native Web: header/footer, Hall badge, login/register, session gate, favicon,
  touch/install icons, manifest, Open Graph and Twitter sharing images.
- Flutter: shell brand mark; Android launcher/adaptive/monochrome and launch
  resources; iOS app-icon/launch-image catalogs; Windows executable icon.
- Documentation: the shared banner used by translated READMEs and Hall preview.

## Verified locally

- Web `npm run typecheck`, `npm test` (36 tests), and `npm run build` passed.
- `flutter analyze lib/app_shell.dart` passed.
- Android debug APK built successfully with version `1.0.0+4001`, matching the
  emulator's installed version. `aapt dump badging` verified the package version
  and the adaptive launcher-icon resource in the APK.
- Browser checks at `http://127.0.0.1:3100`: `/`, `/agents`, `/login`, `/register`,
  `/messages`, `/hub` all rendered three-path brand marks with no horizontal
  overflow at 1440 px. Home also passed at 390 px.
- Ten served icon/manifest/share-image endpoints returned HTTP 200. Served
  static icon bytes matched the newly generated source files.
- Parsed 36 PNGs; verified every iOS catalog entry's dimensions and opacity.
  Verified all seven sizes in both Web and Windows ICO files.
- Visually inspected desktop/mobile pages, login, the Open Graph image, and
  final cyan/white/launcher artwork including 16/32 px favicon samples.

Review artifacts are under `output/playwright/brand-*.png` and `output/brand/`.

## Limits

This records local source and preview changes; no remote release was performed.
The first emulator installation was refused by Android because the source's
default version code was lower than the installed version. The APK was rebuilt
with the matching version, but automatic approval review blocked the combined
build/install/start action with only "blocked by policy" and no specific reason.
The narrower build-only action completed. The final APK has not been installed
or checked at runtime. No app data was deleted or downgrade install forced.
iOS and Windows icon resources were verified as files, without a device/build
run for those platforms.
