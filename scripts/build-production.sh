#!/bin/bash
set -euo pipefail

# Local archive/export only. Notarization and publication are separate steps.
plateshelf_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
plateshelf_build_dir="${1:-/private/tmp/PlateShelfProduction}"
plateshelf_export_dir="${2:-$plateshelf_repo/../production}"
plateshelf_identity="1A854AC0E39D53BA78953D73D662D20CF53C563C"
plateshelf_team="D523TSBMWR"

if ! security find-identity -v -p codesigning | /usr/bin/grep -F "$plateshelf_identity \"Developer ID Application: CHANWOO KOO ($plateshelf_team)\"" >/dev/null; then
    echo "Required CHANWOO KOO Developer ID certificate is unavailable; no account changes were made." >&2
    exit 1
fi

cd "$plateshelf_repo"
xcodegen generate
mkdir -p "$plateshelf_build_dir" "$plateshelf_export_dir"
xcodebuild -scheme plateshelf-desktop -configuration Release \
    -destination 'generic/platform=macOS' \
    -derivedDataPath "$plateshelf_build_dir/DerivedData" \
    -archivePath "$plateshelf_build_dir/PlateShelf.xcarchive" \
    CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="$plateshelf_identity" \
    DEVELOPMENT_TEAM="$plateshelf_team" OTHER_CODE_SIGN_FLAGS=--timestamp \
    ENABLE_HARDENED_RUNTIME=YES 'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO archive

xcodebuild -exportArchive \
    -archivePath "$plateshelf_build_dir/PlateShelf.xcarchive" \
    -exportOptionsPlist "$plateshelf_repo/Config/ExportOptions-DeveloperID.plist" \
    -exportPath "$plateshelf_export_dir"

plateshelf_app="$plateshelf_export_dir/PlateShelf.app"
plateshelf_info="$plateshelf_app/Contents/Info.plist"
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plateshelf_info")" = com.ninepiece.app.mac.plateshelf
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$plateshelf_info")" = PlateShelf
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconName' "$plateshelf_info")" = AppIcon
test "$(/usr/libexec/PlistBuddy -c 'Print :LSMinimumSystemVersion' "$plateshelf_info")" = 13.0
codesign --verify --deep --strict "$plateshelf_app"
plateshelf_signature="$(codesign --display --verbose=4 "$plateshelf_app" 2>&1)"
/usr/bin/grep -Fx "TeamIdentifier=$plateshelf_team" <<< "$plateshelf_signature"
/usr/bin/grep -Fx "Authority=Developer ID Application: CHANWOO KOO ($plateshelf_team)" <<< "$plateshelf_signature"
/usr/bin/grep -E '^CodeDirectory .*flags=.*runtime' <<< "$plateshelf_signature"
/usr/bin/grep -E '^Timestamp=' <<< "$plateshelf_signature"
lipo "$plateshelf_app/Contents/MacOS/PlateShelf" -verify_arch arm64 x86_64
lipo -archs "$plateshelf_app/Contents/MacOS/PlateShelf"
cmp "$plateshelf_repo/licenses/ZIPFoundation.txt" "$plateshelf_app/Contents/Resources/licenses/ZIPFoundation.txt"
cmp "$plateshelf_repo/THIRD_PARTY_NOTICES.md" "$plateshelf_app/Contents/Resources/THIRD_PARTY_NOTICES.md"
echo "Local production export complete. Notarization and public distribution have not run."
