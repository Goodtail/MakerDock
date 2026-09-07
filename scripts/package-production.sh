#!/bin/bash
set -euo pipefail
makerdock_repo="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
makerdock_output="${1:-$makerdock_repo/../production}"
makerdock_app="$makerdock_output/MakerDock.app"
makerdock_identity="1A854AC0E39D53BA78953D73D662D20CF53C563C"
security find-identity -v -p codesigning | /usr/bin/grep -F "$makerdock_identity \"Developer ID Application: CHANWOO KOO (D523TSBMWR)\"" >/dev/null
test "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$makerdock_app/Contents/Info.plist")" = com.ninepiece.app.mac.makerdock
makerdock_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$makerdock_app/Contents/Info.plist")"
makerdock_build="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$makerdock_app/Contents/Info.plist")"
codesign --verify --deep --strict "$makerdock_app"
codesign -dv --verbose=4 "$makerdock_app" 2>&1 | /usr/bin/grep -Fx 'TeamIdentifier=D523TSBMWR'
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
cat > "$makerdock_output/설치 안내.txt" <<'EOF'
MakerDock — 받은 모델부터 출력 기록까지

MakerDock.app을 Applications 폴더로 옮겨 실행하세요.
macOS 13 이상 · Apple Silicon / Intel 공용

PlateShelf에서 이름이 바뀌었습니다. 기존 앱을 종료한 뒤 MakerDock을 실행하면
같은 환경의 보관함·분류·메모·출력 기록·휴지통과 웹 세션을 이어받습니다.
기존 데이터는 백업으로 유지되며 이미 만든 MakerDock 보관함은 덮어쓰지 않습니다.
이전 plateshelf 링크도 계속 지원합니다. 개발용은 MakerDock-dev입니다.

개인 Developer ID: CHANWOO KOO (D523TSBMWR)
이 파일은 서명된 로컬 운영 빌드입니다. Apple 공증·공개 배포는 아직 진행하지 않았습니다.
EOF
cp "$makerdock_output/설치 안내.txt" "$makerdock_work/stage/설치 안내.txt"
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
    architectures=['arm64','x86_64'], signingIdentity='Developer ID Application: CHANWOO KOO (D523TSBMWR)',
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
