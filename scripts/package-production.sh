#!/bin/bash
set -euo pipefail
makerdock_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makerdock_output="${1:-$makerdock_repo/../production}"
makerdock_app="$makerdock_output/MakerDock.app"
makerdock_identity="YOUR_SIGNING_CERTIFICATE_SHA1"
security find-identity -v -p codesigning | /usr/bin/grep -F "$makerdock_identity \"Developer ID Application: MakerDock maintainer (YOUR_PERSONAL_TEAM_ID)\"" >/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$makerdock_app/Contents/Info.plist")" = com.ninepiece.app.mac.makerdock
makerdock_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$makerdock_app/Contents/Info.plist")"
makerdock_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$makerdock_app/Contents/Info.plist")"
codesign --verify --deep --strict "$makerdock_app"
codesign -dv --verbose=4 "$makerdock_app" 2>&1 | /usr/bin/grep -Fx 'TeamIdentifier=YOUR_PERSONAL_TEAM_ID'
makerdock_work="$(mktemp -d /private/tmp/MakerDock-Package.XXXXXX)"
makerdock_mount="$makerdock_work/mount"
makerdock_mounted=false
cleanup() {
    if $makerdock_mounted; then hdiutil detach "$makerdock_mount" >/dev/null; fi
    rm -rf "$makerdock_work"
}
trap cleanup EXIT
mkdir -p "$makerdock_work/stage" "$makerdock_mount"
ditto "$makerdock_app" "$makerdock_work/stage/MakerDock.app"
ln -s /Applications "$makerdock_work/stage/Applications"
cat > "$makerdock_work/stage/Install.txt" <<'EOF'
MakerDock — Your 3D prints, remembered.

Drag MakerDock.app into Applications, then open it.
Requires macOS 13 or later. Universal app for Apple Silicon and Intel.

Import your 3MF files or choose folders to watch. Open stored models in the
separately installed official Bambu Studio. Track completed prints, time,
filament, and notes. English, Korean, Japanese, and Simplified Chinese included.

Add models to Print Queue, set their order, and plan around your available time.
Record completion directly from the queue. Sort the library by print duration.
For an active print, completion uses editable start/end times to calculate elapsed
time. Optional local printer status is available in Settings > Printer connection:
enter the printer IP, serial number and LAN access code. Link its live job to a
queued model to use reported remaining time. MakerDock sends no printer commands.

Browse MakerWorld and open source links inside the app. Sign in on MakerWorld
to access My Collections. Downloads started inside the app retain the observed
source page. The Chrome companion extension is planned separately.

Source, updates, documentation, and license:
https://github.com/Goodtail/MakerDock

Developer ID: MakerDock maintainer (YOUR_PERSONAL_TEAM_ID)
EOF
cp "$makerdock_repo/LICENSE" "$makerdock_work/stage/LICENSE.txt"
makerdock_dmg="$makerdock_output/MakerDock-$makerdock_version-universal.dmg"
hdiutil create -volname "MakerDock $makerdock_version" -srcfolder "$makerdock_work/stage" -ov -format UDZO -fs HFS+ "$makerdock_dmg"
codesign --force --sign "$makerdock_identity" --timestamp "$makerdock_dmg"
codesign --verify --verbose=2 "$makerdock_dmg"
hdiutil verify "$makerdock_dmg"
hdiutil attach "$makerdock_dmg" -readonly -nobrowse -mountpoint "$makerdock_mount"
makerdock_mounted=true
codesign --verify --deep --strict "$makerdock_mount/MakerDock.app"
cmp "$makerdock_app/Contents/MacOS/MakerDock" "$makerdock_mount/MakerDock.app/Contents/MacOS/MakerDock"
hdiutil detach "$makerdock_mount"
makerdock_mounted=false
python3 - "$makerdock_output" "$makerdock_version" "$makerdock_build" <<'PY'
import hashlib, json, pathlib, sys
out, version, build = pathlib.Path(sys.argv[1]), sys.argv[2], sys.argv[3]
dmg = out / f'MakerDock-{version}-universal.dmg'
digest = hashlib.sha256(dmg.read_bytes()).hexdigest()
(out/'SHA256SUMS.txt').write_text(f'{digest}  {dmg.name}\n')
info = dict(version=version, build=build, appName='MakerDock',
    bundleIdentifier='com.ninepiece.app.mac.makerdock', minimumMacOS='13.0',
    architectures=['arm64','x86_64'], signingIdentity='Developer ID Application: MakerDock maintainer (YOUR_PERSONAL_TEAM_ID)',
    hardenedRuntime=True, secureTimestamp=True, appSignatureVerified=True,
    dmgSignatureVerified=True, dmgMountedAndVerified=True, dmg=dmg.name,
    dmgBytes=dmg.stat().st_size, dmgSHA256=digest,
    notarization='pending_credentials', publicDistribution='not_published',
    installedPath='/Applications/MakerDock.app')
(out/'BUILD-INFO.json').write_text(json.dumps(info, ensure_ascii=False, indent=2)+'\n')
previous = out/'previous'; previous.mkdir(exist_ok=True)
for old in out.glob('*.dmg'):
    if old != dmg and not (previous/old.name).exists(): old.rename(previous/old.name)
print(f'Verified package: {dmg.name}')
PY
