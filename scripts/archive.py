#!/usr/bin/env python3
"""Wrap the signed SwiftPM application in an Xcode distribution archive."""
import datetime, os, pathlib, plistlib, shutil
root = pathlib.Path(__file__).resolve().parent.parent
build_root = pathlib.Path(os.environ.get('BUILD_ROOT', root / 'build'))
app = build_root / 'BildShow.app'
archive = build_root / 'BildShow.xcarchive'
products = archive / 'Products/Applications'
products.mkdir(parents=True, exist_ok=True)
shutil.copytree(app, products / app.name, dirs_exist_ok=True)
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
metadata = {'ArchiveVersion': 2, 'CreationDate': datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None), 'Name': 'BildShow', 'SchemeName': 'BildShow', 'ApplicationProperties': {'ApplicationPath': 'Applications/BildShow.app', 'CFBundleIdentifier': info['CFBundleIdentifier'], 'CFBundleShortVersionString': info['CFBundleShortVersionString'], 'CFBundleVersion': info['CFBundleVersion'], 'SigningIdentity': 'Developer ID Application: Bo Saurage (47KJQ2J862)', 'Team': '47KJQ2J862', 'Architectures': ['arm64']}}
(archive / 'Info.plist').write_bytes(plistlib.dumps(metadata))
print(archive)
