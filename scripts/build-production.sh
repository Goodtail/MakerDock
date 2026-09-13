#!/bin/bash
set -euo pipefail

# Local archive/export only. Notarization and publication are separate steps.
makerdock_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makerdock_build_dir="${1:-/private/tmp/MakerDockProduction}"
makerdock_export_dir="${2:-$makerdock_repo/../production}"
source "$makerdock_repo/scripts/signing-config.sh"
makerdock_load_signing

cd "$makerdock_repo"
xcodegen generate
mkdir -p "$makerdock_build_dir" "$makerdock_export_dir"
xcodebuild -scheme makerdock-desktop -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$makerdock_build_dir/DerivedData" \
    -archivePath "$makerdock_build_dir/MakerDock.xcarchive" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$makerdock_identity" \
    DEVELOPMENT_TEAM="$makerdock_team" OTHER_CODE_SIGN_FLAGS=--timestamp \
    ENABLE_HARDENED_RUNTIME=YES 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive

python3 - "$makerdock_repo/Config/ExportOptions-DeveloperID.plist" "$makerdock_build_dir/ExportOptions.plist" "$makerdock_identity" "$makerdock_team" <<'EXPORT'
import plistlib, sys
with open(sys.argv[1], 'rb') as f: options = plistlib.load(f)
options.update(signingCertificate=sys.argv[3], teamID=sys.argv[4])
with open(sys.argv[2], 'wb') as f: plistlib.dump(options, f)
EXPORT
xcodebuild -exportArchive \
    -archivePath "$makerdock_build_dir/MakerDock.xcarchive" \
    -exportOptionsPlist "$makerdock_build_dir/ExportOptions.plist" \
    -exportPath "$makerdock_export_dir"

makerdock_app="$makerdock_export_dir/MakerDock.app"
makerdock_info="$makerdock_app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$makerdock_info")" = com.ninepiece.app.mac.makerdock
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$makerdock_info")" = MakerDock
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$makerdock_info")" = AppIcon
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$makerdock_info")" = 13.0
codesign --verify --deep --strict "$makerdock_app"
makerdock_signature="$(codesign --display --verbose=4 "$makerdock_app" 2>&1)"
/usr/bin/grep -Fx "TeamIdentifier=$makerdock_team" <<< "$makerdock_signature"
/usr/bin/grep -Fx "Authority=$makerdock_signing_name" <<< "$makerdock_signature"
/usr/bin/grep -E '^CodeDirectory .*flags=.*runtime' <<< "$makerdock_signature"
/usr/bin/grep -E '^Timestamp=' <<< "$makerdock_signature"
lipo "$makerdock_app/Contents/MacOS/MakerDock" -verify_arch arm64 x86_64
lipo -archs "$makerdock_app/Contents/MacOS/MakerDock"
cmp "$makerdock_repo/licenses/ZIPFoundation.txt" "$makerdock_app/Contents/Resources/licenses/ZIPFoundation.txt"
cmp "$makerdock_repo/THIRD_PARTY_NOTICES.md" "$makerdock_app/Contents/Resources/THIRD_PARTY_NOTICES.md"
echo "Local production export complete. Notarization and public distribution have not run."
