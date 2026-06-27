#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$PROJECT_ROOT"

echo "==> Building release binary..."
swift build -c release

echo "==> Creating app bundle structure..."
mkdir -p "release/Slidr-Free.app/Contents/MacOS"

echo "==> Copying binary..."
cp ".build/release/SlidrFreeApp" "release/Slidr-Free.app/Contents/MacOS/SlidrFreeApp"

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
    <string>0.1.0</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSUIElement</key>
    <true/>
</dict>
</plist>
EOF

echo "==> Packaging zip..."
cd release
zip -r "Slidr-Free.app.zip" "Slidr-Free.app"
cd "$PROJECT_ROOT"

echo "==> Done: release/Slidr-Free.app.zip"
ls -lh "release/Slidr-Free.app.zip"
