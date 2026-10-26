# Verification — 1.0.4

Development machine: Apple M2 Max, Xcode 27. Minimum deployment target: macOS 14.

- Debug and release builds complete, arm64 only.
- Fourteen XCTest core tests pass: folder-tree exclusions, recursion and legacy decoding, full-screen defaults, progressive soft edges, inheritance, smart cropping, scale caps, portrait fit, near-size rule, dimension filters, shuffle reconciliation, loop order and preset round trip.
- Native UI: main window, global settings, demo rendering, image orientation, pause/navigation, filename/path overlay cycle, preset creation through the toolbar and ⌘N, folder authorization, recursive counts, Ctrl+Z folder undo and saving.
- A folder-editor sizing defect and unstable cache-key encoding were found and corrected during verification.
- The enlarged two-pane folder selector was visually checked with the selected-folder list on the left and Finder-visible internal and external disks in a hierarchical checkbox tree on the right, including home-folder focus, deep browsing, selected-folder reveal, counts and dates.
- Full-screen startup now waits until the selected display has completed its first layout. Metal rendering retries if that display's drawable is temporarily unavailable and redraws after display or backing-scale changes.
- Xcode Direct Distribution: Apple notarization succeeded. Final exported app passes strict code-signature verification and stapler validation; Gatekeeper reports `accepted`, `source=Notarized Developer ID`.
- Hardened runtime is enabled. The direct-distribution build intentionally does not use App Sandbox so the disk-rooted folder tree can browse mounted volumes; macOS privacy controls still apply to protected locations.

Not exercised in this pass: damaged files, locked files, slow/disconnected external volumes, 5000-image load, all image formats/animation variants, the reported two-display hardware arrangement, macOS 14 hardware, and destructive cleanup execution. Cleanup UI, original-change safeguards and display-change recovery are implemented; the fault, volume and display matrix remains follow-up work.
