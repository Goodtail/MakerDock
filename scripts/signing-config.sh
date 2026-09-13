#!/bin/bash
# Resolve official signing details from ignored, maintainer-owned configuration.
makerdock_load_signing() {
    local config="$makerdock_repo/Config/Signing.local.env"
    if [[ -f "$config" ]]; then source "$config"; fi
    : "${MAKERDOCK_SIGNING_IDENTITY:?Configure the approved signing certificate locally}"
    : "${MAKERDOCK_TEAM_ID:?Configure the approved personal team locally}"
    : "${MAKERDOCK_SIGNING_NAME:?Configure the exact approved certificate name locally}"
    makerdock_identity="$MAKERDOCK_SIGNING_IDENTITY"
    makerdock_team="$MAKERDOCK_TEAM_ID"
    makerdock_signing_name="$MAKERDOCK_SIGNING_NAME"
    if ! security find-identity -v -p codesigning | /usr/bin/grep -F "$makerdock_identity \"$makerdock_signing_name\"" >/dev/null; then
        echo 'The approved local signing certificate is unavailable; no account changes were made.' >&2
        return 1
    fi
    case "$makerdock_signing_name" in
        "Developer ID Application: "*" ($makerdock_team)") ;;
        *) echo 'The configured signing certificate and team do not match.' >&2; return 1 ;;
    esac
}
