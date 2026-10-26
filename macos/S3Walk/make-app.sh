#!/bin/zsh
# swift build（release）して、S3Walk.app に包む（Xcode が無くても作れるように）。できた .app はこのフォルダに
set -e
cd "${0:A:h}"
swift build -c release
APP=S3Walk.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/S3Walk $APP/Contents/MacOS/S3Walk
cat > $APP/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>球面さんぽ</string>
  <key>CFBundleDisplayName</key><string>球面さんぽ</string>
  <key>CFBundleIdentifier</key><string>io.github.nonisgh.s3walk</string>
  <key>CFBundleExecutable</key><string>S3Walk</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>CADisableMinimumFrameDurationOnPhone</key><true/>
</dict></plist>
PLIST
codesign --force --sign - $APP >/dev/null 2>&1 || true
echo "できた：$PWD/$APP"
