# BildShow

A native macOS slideshow viewer for talks, exhibitions and everyday image viewing. Apple Silicon, macOS 14 or later. Swedish and English follow the system language.

Download the signed and Apple-notarized app from [Releases](https://github.com/reboot81/BildShow/releases/latest), unzip it, and move BildShow to Applications.

Create a preset, add folders, and click its card to start. Images remain in their original folders. Each preset remembers its position, shuffle sequence, settings overrides and cleanup marks.

## Features

- Two-pane folder selection: the preset's selected folders on the left and a CCC-style hierarchy with checkboxes, disclosure rows, image counts and modification dates on the right. Includes subtree exclusions, drag and drop, and undo.
- Full screen on the app's display, optional display selection and windowed playback.
- Direct cuts, crossfades and fades through the background.
- Proportional fit, fill, width, height and smart cropping, with separate portrait/landscape choices.
- Size-dependent Lanczos/bicubic scaling, sharpening, enlargement limits and soft edges.
- ImageIO decoding, Core Image processing and Metal presentation; configurable prefetching and bounded texture caching.
- Configurable keyboard and mouse bindings; pause, navigate, zoom, filename overlays and Finder reveal.
- Mark images during playback; review thumbnails and move selected originals to Trash in a separate cleanup window.
- Global defaults with individual preset overrides. Import/export presets as JSON.
- Built-in demo with three source sizes; no network connection or AI processing during playback.

GIF is excluded by default; WebP is included. JPEG, PNG, HEIC, TIFF, BMP and AVIF are also discovered. Actual decoding support depends on macOS ImageIO. Animated GIF/WebP playback uses the frames exposed by ImageIO.

The default interval is 2.5 seconds, including a 0.5-second crossfade. Shuffle is on. At the end, BildShow returns to its main window; continuous looping is optional.

## Quick start

1. Choose **New preset**, enter a name, and click **Browse**.
2. Select a folder to grant access. Select folders in the right-hand tree and click **«** to include them.
3. Save the preset, then click its card.
4. Use Space to pause, arrow keys to navigate or change the interval, and Esc to end.

The folder tree shows recursive candidate-file counts before format and dimension filters. The bottom total and preset cards show indexed images after filtering. Overlapping folders are deduplicated.

## Default keys

| Key | Action |
| --- | --- |
| Space | Pause / resume |
| ← / → | Previous / next image |
| ↑ / ↓ | Increase / decrease interval |
| X | Mark for cleanup and advance |
| ⌘Z | Undo the last cleanup mark in this playback session |
| I | Filename for the current image |
| ⇧I | Persistent filename overlay |
| F | Toggle full screen |
| 1 | Actual size / fit |
| + / − | Zoom |
| ⌘R | Reveal in Finder |
| Esc | End slideshow |

Bindings can be changed in Settings. Esc always remains an exit key. Folder edits support both ⌘Z and Ctrl+Z. Manual navigation preserves pause state and restarts the display interval.

## Privacy and persistence

BildShow runs in App Sandbox with hardened runtime. It requests access through the standard folder picker and stores security-scoped bookmarks. It has no network entitlement, analytics, account or cloud service. No Full Disk Access is required.

Preferences and one JSON directory per preset live in the app's Application Support/BildShow directory. Image indexes and demo derivatives live in Caches/BildShow. About shows the actual paths. Exported presets omit access bookmarks; after importing, browse to their folders again to grant access. Exports contain folder paths and preset state, so review them before sharing.

Cleanup uses macOS Trash and checks that an indexed original has not changed before moving it. Taking an image out of a preset does not remove it from disk. Trash behavior depends on the volume.

## Build

Requires Xcode with Swift 5.9 or later and the macOS 14 SDK or later. No third-party package dependencies.

```sh
swift test
./scripts/build.sh release
open build/BildShow.app
```

The script builds arm64 only and creates a locally signed sandboxed application. For Developer ID distribution, set `SIGN_IDENTITY` to your installed Developer ID Application identity. See [release instructions](docs/RELEASING.md).

## Verification and limits

Core tests cover proportional layout, smart crop limits, size rules, filters, preset coding, inheritance and shuffle reconciliation. Normal native UI flows are checked on the development Mac. Fault injection for damaged images, stalled external disks and disconnected volumes is deferred for a later validation pass; macOS 14 hardware and multi-display configurations have not yet been exercised directly.

Failed or timed-out reads are skipped. The last rendered image stays visible during loading. If no playable candidates remain, the slideshow ends. Read workers are bounded and a four-second timeout releases the slideshow's wait; an operating-system read already in progress cannot always be interrupted. Prefetch is intended to hide ordinary read latency, not to guarantee uninterrupted operation on an unresponsive volume.

The demo portrait is independently AI-generated, not Lenna or USC 4.1.04. Its source resolution is 1672 × 941; the demo also creates smaller samples. See [asset notes](docs/ASSETS.md).
