# DesktopPush macOS App Icon

This package contains a production-ready, opaque macOS application icon source and raster renditions.

- `DesktopPush.svg` — editable, grouped SVG source (backplate, desktop Mac, push rays, iPhone, and notification).
- `DesktopPush.iconset/` — the PNG naming convention accepted by `iconutil`.
- `DesktopPush.icns` — Finder/Xcode-ready icon bundle.
- `AppIcon.appiconset/` — drop-in macOS Xcode asset-catalog set.

The PNG canvas is intentionally fully opaque. The rounded-square field is part of the artwork; it is not a transparent cutout. This avoids haloing against Finder/Dock backgrounds and lets macOS apply its standard treatment consistently.

For an Xcode asset catalog, add `DesktopPush.icns` to the target, or import the PNG renditions into a macOS AppIcon set. The 1024px source has been used for every rendition, not upscaled from a smaller asset.
