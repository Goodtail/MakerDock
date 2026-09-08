# Official release procedure

Official MakerDock releases belong only to **CHANWOO KOO (D523TSBMWR)**. Verify the active personal team before any Apple Developer or App Store Connect mutation. Do not use a company certificate, provider, API key, or provisioning profile.

## Version numbering

The initial public version is **0.1.0**. Routine development changes increment the internal build number, not the public version. Keep `MARKETING_VERSION` unchanged until the user requests a new public version or release. The internal `CURRENT_PROJECT_VERSION` remains monotonically increasing, including when public version labels are corrected.

The former 1.6.x releases used premature version numbers and have been withdrawn from public downloads. Their Git refs and local checkpoints remain available for rollback.

## Build and package

1. Commit the verified implementation and update `Config/Version.xcconfig`.
2. Run the relevant tests in [development](development.md), including the public-configuration boundary test.
3. Run `bash scripts/build-production.sh`. The script checks the exact personal Developer ID identity, builds an arm64/x86_64 archive with hardened runtime and a secure timestamp, exports the app, and verifies the signature and production identity.
4. Check `codesign --display --verbose=4` reports `TeamIdentifier=D523TSBMWR` and `com.ninepiece.app.mac.makerdock`. Keep the development app separate.
5. Complete notarization as below. Do not describe an artifact as notarized before acceptance and ticket validation.

## Personal notarization credentials

A Developer ID certificate signs software but is not a notarization login. Use a Keychain credential profile explicitly created for the personal team. Never commit passwords, API private keys, or exported certificates.

For Apple ID authentication, the maintainer can create a dedicated profile in their own terminal:

```sh
xcrun notarytool store-credentials makerdock-personal \
  --apple-id YOUR_PERSONAL_APPLE_ID --team-id D523TSBMWR
```

Enter the app-specific password only at the secure prompt. Do not put it in the repository, command examples, chat, or a shell history. If using an App Store Connect API key instead, verify its issuing personal team first; a key filename alone does not identify its team. Use Apple's documented key/issuer authentication flow and save it as a dedicated Keychain profile.

## Notarize, staple, and validate

Run these steps only with a credential profile whose personal-team ownership has been verified:

1. ZIP the signed `MakerDock.app` with `ditto -c -k --keepParent` into a temporary location.
2. Submit it using `xcrun notarytool submit <zip> --keychain-profile makerdock-personal --output-format json`. Save the returned submission ID locally. Use `notarytool info` and `notarytool log` for that ID until Apple reports `Accepted`; do not resubmit on an uncertain response.
3. Staple and validate the app: `xcrun stapler staple <app>` and `xcrun stapler validate <app>`.
4. Run `bash scripts/package-production.sh` to make the signed DMG with the stapled app inside.
5. Submit the final signed DMG using the same verified profile. After `Accepted`, staple and validate the DMG.
6. Mount the final DMG read-only, verify the app's signature and stapled ticket again, and assess it with Gatekeeper. Detach the image afterward.
7. Recalculate `SHA256SUMS.txt` after stapling changes the DMG bytes. Update the local build metadata with acceptance IDs, validation results, and the final digest.

The packaging script initially marks notarization as pending. That is a truthful intermediate state, not an instruction to publish the package. Its output folder defaults to `../production`, outside this source repository. Private notarization responses stay outside Git.

## Publish on GitHub

The official source repository is `Goodtail/MakerDock`. Review tracked files and reachable history for credentials, private data, and unauthorized assets before the first push. Keep the four localized README screenshots and feature descriptions in sync with the actual public build.

Create an annotated `vVERSION` tag only at the verified source commit. Upload the accepted and stapled universal DMG plus final `SHA256SUMS.txt` to the matching GitHub release. State macOS requirements, public-build integration limits, and changes from the previous version. Do not publish a development app or private build logs as a release asset.

References: [Apple Developer ID](https://developer.apple.com/developer-id/), [Apple notarization](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
