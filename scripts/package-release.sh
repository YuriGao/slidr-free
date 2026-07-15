#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

APP_VERSION="${APP_VERSION:-0.4.0}"
BUILD_NUMBER="${BUILD_NUMBER:-4000}"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating app bundle structure..."
rm -rf "release/Slidr-Free.app"
mkdir -p "release/Slidr-Free.app/Contents/MacOS"
mkdir -p "release/Slidr-Free.app/Contents/Resources"

echo "==> Copying binary..."
cp ".build/release/SlidrFreeApp" "release/Slidr-Free.app/Contents/MacOS/SlidrFreeApp"

echo "==> Copying icon..."
cp "AppIcon.icns" "release/Slidr-Free.app/Contents/Resources/AppIcon.icns"
cp "Resources/MenuBarIcon.png" "release/Slidr-Free.app/Contents/Resources/MenuBarIcon.png"

echo "==> Copying license..."
cp "LICENSE" "release/Slidr-Free.app/Contents/Resources/LICENSE"

echo "==> Copying localizations..."
cp -R Resources/en.lproj "release/Slidr-Free.app/Contents/Resources/"
cp -R Resources/zh-Hans.lproj "release/Slidr-Free.app/Contents/Resources/"

echo "==> Writing Info.plist..."
cat > "release/Slidr-Free.app/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>SlidrFreeApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.slidr.free</string>
    <key>CFBundleName</key>
    <string>Slidr Free</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>CFBundleShortVersionString</key>
    <string>${APP_VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleLocalizations</key>
    <array>
        <string>en</string>
        <string>zh-Hans</string>
    </array>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

xattr -cr "release/Slidr-Free.app"
echo "==> Ad-hoc signing DEVELOPMENT-ONLY build..."
codesign --force --deep --sign - "release/Slidr-Free.app"
codesign --verify --verbose=2 "release/Slidr-Free.app"

echo "==> Packaging zip..."
cd release
rm -f "Slidr-Free.app.zip"
zip -r "Slidr-Free.app.zip" "Slidr-Free.app"
cd "$PROJECT_ROOT"

APP_VERSION="${APP_VERSION}" BUILD_NUMBER="${BUILD_NUMBER}" scripts/verify-release.sh

echo "==> Done: release/Slidr-Free.app.zip"
ls -lh "release/Slidr-Free.app.zip"
