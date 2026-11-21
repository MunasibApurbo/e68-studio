#!/bin/bash
# Signs "dist/E68 Studio.app" with Hardened Runtime + Developer ID, notarizes with Apple,
# staples the ticket, and verifies Gatekeeper acceptance.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT_DIR"

APP_PATH="${APP_PATH:-dist/E68 Studio.app}"
ENTITLEMENTS="${ENTITLEMENTS:-Scripts/E68Studio.entitlements}"
IDENTITY="${CODESIGN_IDENTITY:-}"
BUNDLE_ID="${BUNDLE_ID:-}"
FORMAT="${ARCHIVE_FORMAT:-zip}"
OUT_PATH="${OUT_PATH:-}"
KEYCHAIN_PROFILE="${NOTARY_KEYCHAIN_PROFILE:-}"
KEYCHAIN_PATH="${NOTARY_KEYCHAIN:-}"
SIGN_ONLY=0

usage() {
    cat <<'EOF'
Usage: Scripts/notarize-app.sh [options]

Options:
  --app <path>               Path to .app bundle (default: "dist/E68 Studio.app")
  --identity <name|sha1>     Developer ID Application signing identity
                             (or set CODESIGN_IDENTITY; auto-detected if unique)
  --bundle-id <id>           Set/override CFBundleIdentifier before signing
                             (or set BUNDLE_ID; must not be "local.*")
  --entitlements <path>      Entitlements plist (default: Scripts/E68Studio.entitlements)
  --format <zip|dmg>         Distributable archive format (default: zip)
  --out <path>               Output archive path (default: dist/E68-Studio-<ver>.<zip|dmg>)
  --keychain-profile <name>  notarytool keychain profile (or NOTARY_KEYCHAIN_PROFILE)
  --keychain <path>          Optional keychain path (or NOTARY_KEYCHAIN)
  --sign-only                Sign and verify locally only; skip notarytool submission
  -h, --help                 Show this help

Notary authentication (pick one, unless --sign-only):
  1. Keychain profile (recommended):
       xcrun notarytool store-credentials "e68-notary" \
         --apple-id "<you@example.com>" --team-id "<TEAMID>" --password "<app-specific-pw>"
       ./Scripts/notarize-app.sh --keychain-profile "e68-notary" --bundle-id "com.example.e68studio"
  2. Apple ID environment variables:
       APPLE_ID, APPLE_TEAM_ID (or TEAM_ID), APPLE_APP_PASSWORD (or NOTARY_PASSWORD)
  3. App Store Connect API key environment variables:
       APP_STORE_CONNECT_API_KEY_PATH, APP_STORE_CONNECT_KEY_ID, [APP_STORE_CONNECT_ISSUER_ID]
EOF
}

die() {
    echo "error: $*" >&2
    exit 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --app)
            [[ $# -ge 2 ]] || die "--app requires a path"
            APP_PATH="$2"; shift 2 ;;
        --identity)
            [[ $# -ge 2 ]] || die "--identity requires a value"
            IDENTITY="$2"; shift 2 ;;
        --bundle-id)
            [[ $# -ge 2 ]] || die "--bundle-id requires a value"
            BUNDLE_ID="$2"; shift 2 ;;
        --entitlements)
            [[ $# -ge 2 ]] || die "--entitlements requires a path"
            ENTITLEMENTS="$2"; shift 2 ;;
        --format)
            [[ $# -ge 2 ]] || die "--format requires zip or dmg"
            FORMAT="$2"; shift 2 ;;
        --out)
            [[ $# -ge 2 ]] || die "--out requires a path"
            OUT_PATH="$2"; shift 2 ;;
        --keychain-profile)
            [[ $# -ge 2 ]] || die "--keychain-profile requires a profile name"
            KEYCHAIN_PROFILE="$2"; shift 2 ;;
        --keychain)
            [[ $# -ge 2 ]] || die "--keychain requires a path"
            KEYCHAIN_PATH="$2"; shift 2 ;;
        --sign-only)
            SIGN_ONLY=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            die "unknown option: $1 (use --help for usage)" ;;
    esac
done

case "$FORMAT" in
    zip|dmg) ;;
    *) die "unsupported --format '$FORMAT' (expected 'zip' or 'dmg')" ;;
esac

# Strip trailing slash (e.g. from shell tab-completion) so ditto/codesign paths stay clean.
[[ "$APP_PATH" != "/" ]] && APP_PATH="${APP_PATH%/}"

[[ -d "$APP_PATH" ]] || die "app bundle not found: $APP_PATH (run ./Scripts/build-app.sh first)"
INFO_PLIST="$APP_PATH/Contents/Info.plist"
[[ -f "$INFO_PLIST" ]] || die "Info.plist not found at $INFO_PLIST"
[[ -f "$ENTITLEMENTS" ]] || die "entitlements file not found: $ENTITLEMENTS"

plutil -lint "$ENTITLEMENTS" >/dev/null || die "invalid entitlements plist: $ENTITLEMENTS"

# Resolve signing identity.
if [[ -z "$IDENTITY" ]]; then
    DEV_ID_MATCHES=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && DEV_ID_MATCHES+=("$line")
    done < <(security find-identity -v -p codesigning 2>/dev/null | sed -n 's/.*"\(Developer ID Application:[^"]*\)".*/\1/p')

    if [[ ${#DEV_ID_MATCHES[@]} -eq 0 ]]; then
        echo "Available codesigning identities:" >&2
        security find-identity -v -p codesigning >&2 || true
        die "no 'Developer ID Application' identity found; pass --identity or set CODESIGN_IDENTITY"
    elif [[ ${#DEV_ID_MATCHES[@]} -gt 1 ]]; then
        echo "Multiple 'Developer ID Application' identities found:" >&2
        printf '  %s\n' "${DEV_ID_MATCHES[@]}" >&2
        die "specify one with --identity or CODESIGN_IDENTITY"
    fi
    IDENTITY="${DEV_ID_MATCHES[0]}"
fi

if [[ "$IDENTITY" == "-" || "$IDENTITY" == "ad-hoc" || "$IDENTITY" == "E68StudioLocal" ]]; then
    die "identity '$IDENTITY' cannot be used for Hardened Runtime distribution / notarization; use a 'Developer ID Application' certificate"
fi

RESOLVED_ID_LINE="$(security find-identity -v -p codesigning 2>/dev/null | grep -F "$IDENTITY" | head -n 1 || true)"
if [[ -z "$RESOLVED_ID_LINE" ]]; then
    die "signing identity '$IDENTITY' not found in keychain (run: security find-identity -v -p codesigning)"
fi
if [[ "$RESOLVED_ID_LINE" != *"Developer ID Application:"* ]]; then
    if [[ "$SIGN_ONLY" -eq 1 ]]; then
        echo "warning: '$IDENTITY' is not a Developer ID Application certificate; Apple notarization will reject it." >&2
    else
        die "identity '$IDENTITY' is not a 'Developer ID Application' certificate (found: $RESOLVED_ID_LINE)"
    fi
fi

# Check what CFBundleIdentifier will be used (before mutating Info.plist).
CURRENT_BUNDLE_ID="$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null || true)"
EFFECTIVE_BUNDLE_ID="${BUNDLE_ID:-$CURRENT_BUNDLE_ID}"
if [[ -n "$BUNDLE_ID" ]]; then
    if [[ "$BUNDLE_ID" == local.* || ! "$BUNDLE_ID" =~ ^[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; then
        die "invalid release bundle ID '$BUNDLE_ID' (must be reverse-DNS and must not start with 'local.')"
    fi
fi

if [[ -z "$EFFECTIVE_BUNDLE_ID" || "$EFFECTIVE_BUNDLE_ID" == "local.e68studio" || "$EFFECTIVE_BUNDLE_ID" == local.* ]]; then
    if [[ "$SIGN_ONLY" -eq 1 ]]; then
        echo "warning: CFBundleIdentifier is '$EFFECTIVE_BUNDLE_ID'; pass --bundle-id <reverse-dns-id> before notarizing." >&2
    else
        die "CFBundleIdentifier is '$EFFECTIVE_BUNDLE_ID'; notarization requires a non-'local.' reverse-DNS bundle ID (pass --bundle-id com.<your-domain>.e68studio or set BUNDLE_ID)"
    fi
fi

# Validate notarytool credentials before modifying Info.plist or signing.
NOTARY_AUTH_ARGS=()
if [[ "$SIGN_ONLY" -eq 0 ]]; then
    if [[ -n "$KEYCHAIN_PROFILE" ]]; then
        NOTARY_AUTH_ARGS=(--keychain-profile "$KEYCHAIN_PROFILE")
        [[ -n "$KEYCHAIN_PATH" ]] && NOTARY_AUTH_ARGS+=(--keychain "$KEYCHAIN_PATH")
    elif [[ -n "${APP_STORE_CONNECT_API_KEY_PATH:-}" && -n "${APP_STORE_CONNECT_KEY_ID:-}" ]]; then
        [[ -f "$APP_STORE_CONNECT_API_KEY_PATH" ]] || die "App Store Connect API key not found: $APP_STORE_CONNECT_API_KEY_PATH"
        NOTARY_AUTH_ARGS=(--key "$APP_STORE_CONNECT_API_KEY_PATH" --key-id "$APP_STORE_CONNECT_KEY_ID")
        [[ -n "${APP_STORE_CONNECT_ISSUER_ID:-}" ]] && NOTARY_AUTH_ARGS+=(--issuer "$APP_STORE_CONNECT_ISSUER_ID")
    elif [[ -n "${APPLE_ID:-}" && -n "${APPLE_TEAM_ID:-${TEAM_ID:-}}" ]]; then
        RESOLVED_TEAM_ID="${APPLE_TEAM_ID:-${TEAM_ID:-}}"
        RESOLVED_PW="${APPLE_APP_PASSWORD:-${NOTARY_PASSWORD:-}}"
        NOTARY_AUTH_ARGS=(--apple-id "$APPLE_ID" --team-id "$RESOLVED_TEAM_ID")
        if [[ -n "$RESOLVED_PW" ]]; then
            NOTARY_AUTH_ARGS+=(--password "$RESOLVED_PW")
        fi
    else
        die "no notarization credentials configured; pass --keychain-profile <name> (or set NOTARY_KEYCHAIN_PROFILE, APPLE_ID+APPLE_TEAM_ID+APPLE_APP_PASSWORD, or APP_STORE_CONNECT_API_KEY_PATH+APP_STORE_CONNECT_KEY_ID)"
    fi
fi

if [[ -n "$BUNDLE_ID" ]]; then
    plutil -replace CFBundleIdentifier -string "$BUNDLE_ID" "$INFO_PLIST"
    CURRENT_BUNDLE_ID="$BUNDLE_ID"
    echo "Updated CFBundleIdentifier -> $CURRENT_BUNDLE_ID"
fi

APP_VERSION="$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$INFO_PLIST" 2>/dev/null || echo "1.0")"
if [[ -z "$OUT_PATH" ]]; then
    OUT_PATH="dist/E68-Studio-${APP_VERSION}.${FORMAT}"
fi

echo "==> Signing '$APP_PATH' ($CURRENT_BUNDLE_ID) with '$IDENTITY' (Hardened Runtime + timestamp)..."
find "$APP_PATH" -name '.DS_Store' -delete
xattr -cr "$APP_PATH"
codesign --force --options runtime --timestamp --entitlements "$ENTITLEMENTS" --sign "$IDENTITY" "$APP_PATH"

echo "==> Verifying strict code signature..."
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=2 "$APP_PATH" 2>&1 | grep -E "^(Identifier|Format|CodeDirectory|Authority|Timestamp|Runtime Version)=" || true

if [[ "$SIGN_ONLY" -eq 1 ]]; then
    echo "Sign-only complete: '$APP_PATH' signed and verified."
    exit 0
fi

TMP_DIR="$(mktemp -d)"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

mkdir -p "$(dirname "$OUT_PATH")"

if [[ "$FORMAT" == "zip" ]]; then
    SUBMIT_ARCHIVE="$TMP_DIR/E68-Studio-submit.zip"
    echo "==> Creating submission zip..."
    ditto -c -k --keepParent "$APP_PATH" "$SUBMIT_ARCHIVE"

    echo "==> Submitting to Apple Notary Service (waiting for completion)..."
    xcrun notarytool submit "$SUBMIT_ARCHIVE" "${NOTARY_AUTH_ARGS[@]}" --wait

    echo "==> Stapling notarization ticket to '$APP_PATH'..."
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"

    echo "==> Verifying Gatekeeper acceptance on '$APP_PATH'..."
    spctl -a -vvv -t exec "$APP_PATH"

    echo "==> Packaging stapled distributable zip -> '$OUT_PATH'..."
    rm -f "$OUT_PATH"
    ditto -c -k --keepParent "$APP_PATH" "$OUT_PATH"
else
    STAGE_DIR="$TMP_DIR/dmg-stage"
    mkdir -p "$STAGE_DIR"
    APP_BASENAME="$(basename "$APP_PATH")"
    ditto "$APP_PATH" "$STAGE_DIR/$APP_BASENAME"
    ln -s /Applications "$STAGE_DIR/Applications"

    echo "==> Creating compressed DMG -> '$OUT_PATH'..."
    rm -f "$OUT_PATH"
    hdiutil create -volname "E68 Studio" -srcfolder "$STAGE_DIR" -ov -format UDZO "$OUT_PATH" >/dev/null

    echo "==> Signing DMG..."
    codesign --force --timestamp --sign "$IDENTITY" "$OUT_PATH"

    echo "==> Submitting DMG to Apple Notary Service (waiting for completion)..."
    xcrun notarytool submit "$OUT_PATH" "${NOTARY_AUTH_ARGS[@]}" --wait

    echo "==> Stapling notarization ticket to '$OUT_PATH' and '$APP_PATH'..."
    xcrun stapler staple "$OUT_PATH"
    xcrun stapler validate "$OUT_PATH"
    xcrun stapler staple "$APP_PATH"
    xcrun stapler validate "$APP_PATH"

    echo "==> Verifying Gatekeeper acceptance..."
    spctl -a -vvv -t exec "$APP_PATH"
    spctl -a -vvv -t open --context context:primary-signature "$OUT_PATH"
fi

echo "Done! Notarized distributable ready at: $OUT_PATH"
