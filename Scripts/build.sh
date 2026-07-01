#!/bin/bash
set -euo pipefail

PRODUCT_NAME="DisplayToggle"
BUILD_DIR=".build/release"
APP_DIR="dist/${PRODUCT_NAME}.app"

cd "$(dirname "$0")/.."

echo "==> Building ${PRODUCT_NAME}..."
swift build -c release

echo "==> Assembling .app bundle..."
rm -rf "dist"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

cp "${BUILD_DIR}/${PRODUCT_NAME}" "${APP_DIR}/Contents/MacOS/"
cp "Resources/Info.plist" "${APP_DIR}/Contents/"
cp "Resources/AppIcon.icns" "${APP_DIR}/Contents/Resources/"

echo "==> Ad-hoc code signing..."
codesign --force --sign - "${APP_DIR}"

echo "==> Done: ${APP_DIR}"
echo "    Run with: open dist/${PRODUCT_NAME}.app"
