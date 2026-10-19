# Verification — 1.0.0

Development machine: Apple M2 Max, Xcode 27. Minimum deployment target: macOS 14.

- Debug and release builds complete, arm64 only.
- Twelve XCTest core tests pass: folder-tree exclusions, recursion and legacy decoding, inheritance, smart cropping, scale caps, portrait fit, near-size rule, dimension filters, shuffle reconciliation, loop order and preset round trip.
- Native UI: main window, global settings, demo rendering, image orientation, pause/navigation, filename overlay, preset creation, folder authorization, recursive counts, Ctrl+Z folder undo and saving.
- A folder-editor sizing defect and unstable cache-key encoding were found and corrected during verification.
- The two-pane folder selector was visually checked with the selected-folder list on the left and a hierarchical checkbox tree on the right, including nested folders, subtree exclusion, re-inclusion, counts, dates and root normalization.
- Xcode Direct Distribution: Apple notarization succeeded. Final exported app passes strict code-signature verification and stapler validation; Gatekeeper reports `accepted`, `source=Notarized Developer ID`.
- Sandbox entitlements verified: App Sandbox, app-scoped bookmarks and user-selected read/write files. Hardened runtime is enabled.

Not exercised in this pass: damaged files, locked files, slow/disconnected external volumes, 5000-image load, all image formats/animation variants, multiple displays, macOS 14 hardware, and destructive cleanup execution. Cleanup UI and original-change safeguards are implemented; the fault and volume matrix remains follow-up work.
