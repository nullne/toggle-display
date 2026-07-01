#!/bin/bash
set -euo pipefail

APP_NAME="DisplayToggle"
APP_PATH="dist/${APP_NAME}.app"
DMG_PATH="dist/${APP_NAME}.dmg"

cd "$(dirname "$0")/.."

if [ ! -d "${APP_PATH}" ]; then
    echo "Error: ${APP_PATH} not found. Run build.sh first."
    exit 1
fi

echo "==> Creating DMG..."
rm -f "${DMG_PATH}"

DMG_STAGING="dist/dmg-staging"
rm -rf "${DMG_STAGING}"
mkdir -p "${DMG_STAGING}"
cp -R "${APP_PATH}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create \
    -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov \
    -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_STAGING}"

echo "==> Done: ${DMG_PATH}"
