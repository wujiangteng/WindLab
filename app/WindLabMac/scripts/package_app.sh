#!/usr/bin/env bash
set -euo pipefail

APP_NAME="WindLab"
BUNDLE_ID="com.windlab.mac"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_MACOS="14.0"
MACOSICONS_PAGE_URL="https://macosicons.com/?icon=JS6Srjibi5"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
DIST_DIR="${PROJECT_DIR}/dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
LOCAL_ICON="${PROJECT_DIR}/assets/AppIcon.icns"
DOWNLOADED_ICON="${PROJECT_DIR}/assets/AppIcon.downloaded.icns"

export CLANG_MODULE_CACHE_PATH="${PROJECT_DIR}/.build/clang-module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="${PROJECT_DIR}/.build/swiftpm-module-cache"
mkdir -p "${CLANG_MODULE_CACHE_PATH}" "${SWIFTPM_MODULECACHE_OVERRIDE}"

echo "==> Building release binary"
cd "${PROJECT_DIR}"
swift build -c release

BUILD_DIR="$(swift build -c release --show-bin-path)"
BINARY_PATH="${BUILD_DIR}/WindLabMac"
RESOURCE_BUNDLE="${BUILD_DIR}/WindLabMac_WindLabMac.bundle"

if [[ ! -x "${BINARY_PATH}" ]]; then
  echo "Release binary not found: ${BINARY_PATH}" >&2
  exit 1
fi

if [[ ! -d "${RESOURCE_BUNDLE}" ]]; then
  echo "Resource bundle not found: ${RESOURCE_BUNDLE}" >&2
  exit 1
fi

echo "==> Creating ${APP_DIR}"
rm -rf "${APP_DIR}"
mkdir -p "${MACOS_DIR}" "${RESOURCES_DIR}"

cp "${BINARY_PATH}" "${MACOS_DIR}/${APP_NAME}"
cp -R "${RESOURCE_BUNDLE}" "${RESOURCES_DIR}/"

ICON_FILE=""
if [[ -f "${LOCAL_ICON}" ]]; then
  ICON_FILE="${LOCAL_ICON}"
elif [[ -n "${WINDLAB_ICON_URL:-}" ]]; then
  echo "==> Downloading icon from WINDLAB_ICON_URL"
  curl -L "${WINDLAB_ICON_URL}" -o "${DOWNLOADED_ICON}"
  ICON_FILE="${DOWNLOADED_ICON}"
else
  echo "==> No icon found at assets/AppIcon.icns"
  echo "    Download the icon from ${MACOSICONS_PAGE_URL}"
  echo "    Save it as ${LOCAL_ICON}"
  echo "    Or run with WINDLAB_ICON_URL=<direct .icns url> ${BASH_SOURCE[0]}"
fi

if [[ -n "${ICON_FILE}" ]]; then
  cp "${ICON_FILE}" "${RESOURCES_DIR}/AppIcon.icns"
fi

echo "==> Writing Info.plist"
cat > "${CONTENTS_DIR}/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
 "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleVersion</key>
  <string>${BUILD_NUMBER}</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleExecutable</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>${MIN_MACOS}</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>Copyright © 2026 WindLab.</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Windographer File</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Owner</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>com.windlab.windog</string>
      </array>
    </dict>
    <dict>
      <key>CFBundleTypeName</key>
      <string>Text Wind Data</string>
      <key>CFBundleTypeRole</key>
      <string>Viewer</string>
      <key>LSHandlerRank</key>
      <string>Alternate</string>
      <key>LSItemContentTypes</key>
      <array>
        <string>public.plain-text</string>
        <string>public.comma-separated-values-text</string>
        <string>public.tab-separated-values-text</string>
      </array>
    </dict>
  </array>
  <key>UTExportedTypeDeclarations</key>
  <array>
    <dict>
      <key>UTTypeIdentifier</key>
      <string>com.windlab.windog</string>
      <key>UTTypeDescription</key>
      <string>Windographer File</string>
      <key>UTTypeConformsTo</key>
      <array>
        <string>public.data</string>
      </array>
      <key>UTTypeTagSpecification</key>
      <dict>
        <key>public.filename-extension</key>
        <array>
          <string>windog</string>
        </array>
      </dict>
    </dict>
  </array>
EOF

if [[ -n "${ICON_FILE}" ]]; then
  cat >> "${CONTENTS_DIR}/Info.plist" <<EOF
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
EOF
fi

cat >> "${CONTENTS_DIR}/Info.plist" <<EOF
</dict>
</plist>
EOF

echo "==> Signing locally"
codesign --force --deep --sign - "${APP_DIR}"

echo "==> Done"
echo "App: ${APP_DIR}"
echo "Run: open '${APP_DIR}'"
