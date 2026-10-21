# Vehnora installed production artwork

Approved source: `source/Vehnora-V-Master.png` (1312 x 1199 RGBA).
The source is retained unchanged. SHA-256 and export dimensions/hashes are in
`android/asset_manifest.json`. Visible alpha > 8 bounds: (95,244)-(1234,1049).
Exports crop to (91,240)-(1238,1053), removing surrounding nearly invisible dust
and padding. Real transparency is preserved; no background-removal guesswork,
redrawing, recolouring or generative image edits were applied to full-colour art.
The supplied green edge fringe and gradients remain; inspect them physically.

## Installed assets

- `drawable-xxxhdpi/vehnora_launcher_foreground.png`: 432px/108dp transparent
  adaptive foreground, essential artwork contained within radius 32dp (inside
  the 66dp-diameter safe zone). Both v26/v33 icon XML use the centralized teal
  `brand_launcher_background`. `drawable/ic_launcher_foreground.xml` wraps it.
- Legacy mipmap PNGs: mdpi 48, hdpi 72, xhdpi 96, xxhdpi 144, xxxhdpi 192px,
  composited onto the same teal background without stretching.
- `drawable-xxxhdpi/vehnora_launcher_monochrome.png`: source-derived alpha
  silhouette with neutral white road markings cut out as negative space. Only
  this export is simplified. Android 13+ v33 XML includes its monochrome wrapper.
- `drawable-xxxhdpi/vehnora_splash.png`: 1152px/288dp static transparent canvas;
  visible mark stays within radius 90dp (inside the 192dp-diameter native mask).
  Both Android 12+ styles use it on existing light/dark brand surfaces.
- `flutter/vehnora_mark.png`: 64px base, 128px 2.0x, 192px 3.0x, registered in
  pubspec and used only as the welcome-screen brand mark. Standard Material
  icons elsewhere remain unchanged. No SVG dependency or Flutter intro added.

Reproduce using `tool/generate_brand_assets.py` with Pillow and numpy. It performs
premultiplied-alpha Lanczos scaling, writes an asset manifest and checks circle,
squircle and rounded-square mask containment. `android/brand_qa.png` previews
those masks, light/dark splash surfaces and the system-tinted themed silhouette.
No additional source asset is required for this integration.

Temporary launcher/splash artwork and populated-directory .gitkeep staging
files have been removed. Production assets still need physical Android QA,
particularly the dark stroke on teal, fine road marks at mdpi and supplied edge
fringing. The preview does not replace on-device launcher/splash validation.

Persistent technical identity, signing architecture, notification channels/IDs,
SQLite schema 4, backup format 1 and legacy .dtbackup identity are unchanged.
