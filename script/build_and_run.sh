#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Doll"
PROJECT_NAME="Doll"
SCHEME="Doll"
BUNDLE_ID="com.xiaogd.Doll"
# Xcode 27 warns about the project's historical 11.0 target. Keep the
# project's declared minimum unchanged and downgrade that SDK diagnostic to a
# warning for this local build invocation.
BUILD_DEPLOYMENT_TARGET="11.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECKOUT_KEY="$(printf '%s' "$ROOT_DIR" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"

if [ -d /Volumes/T5/Codex ] && [ -w /Volumes/T5/Codex ]; then
    DERIVED_DATA_DIR="/Volumes/T5/Codex/DerivedData/${PROJECT_NAME}-${CHECKOUT_KEY}"
else
    DERIVED_DATA_DIR="${HOME}/Library/Developer/Xcode/DerivedData/Codex-${PROJECT_NAME}-${CHECKOUT_KEY}"
fi

APP_BUNDLE="$DERIVED_DATA_DIR/Build/Products/Debug/${APP_NAME}.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/${APP_NAME}"

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

xcodebuild \
    -project "$ROOT_DIR/${PROJECT_NAME}.xcodeproj" \
    -scheme "$SCHEME" \
    -configuration Debug \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    MACOSX_DEPLOYMENT_TARGET="$BUILD_DEPLOYMENT_TARGET" \
    __DIAGNOSE_INVALID_DEPLOYMENT_TARGET_AS_ERROR=NO \
    build

open_app() {
    /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
    run)
        open_app
        ;;
    --debug|debug)
        lldb -- "$APP_BINARY"
        ;;
    --logs|logs)
        open_app
        /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
        ;;
    --telemetry|telemetry)
        open_app
        /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
        ;;
    --verify|verify)
        open_app
        sleep 1
        pgrep -x "$APP_NAME" >/dev/null
        ;;
    *)
        echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
        exit 2
        ;;
esac
