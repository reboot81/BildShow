# Release procedure

1. Update the version and build number in `packaging/Info.plist`.
2. Run `swift test` and verify normal app flows.
3. Build with an installed Developer ID Application certificate:

   ```sh
   SIGN_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build.sh release
   python3 scripts/archive.py
   ```

4. Adjust `packaging/ExportOptions.plist` and the archive metadata for your team when forking. Submit with the existing signed-in Xcode account:

   ```sh
   xcodebuild -exportArchive -archivePath build/BildShow.xcarchive \
     -exportOptionsPlist packaging/ExportOptions.plist \
     -exportPath build/export -allowProvisioningUpdates
   ```

   Alternatively, open the archive in Xcode Organizer and use Direct Distribution. A `notarytool` keychain profile can also be used to submit a ZIP of the signed app. Never commit credentials or signing keys.

5. After Apple accepts the app, export the notarized archive with `xcodebuild -exportNotarizedApp`, or staple the accepted app with `xcrun stapler staple`.
6. Verify `codesign --verify --deep --strict`, `xcrun stapler validate`, and `spctl --assess --type execute --verbose=2` on the final app.
7. Package with `ditto -c -k --sequesterRsrc --keepParent`, compute SHA-256 and upload the ZIP to the matching GitHub release. Do not publish an unnotarized build as a notarized release.

The app uses App Sandbox, user-selected read/write access for optional Trash operations, app-scoped bookmarks, and hardened runtime. No JIT, library-validation exemption, debugger entitlement or network entitlement is needed.
