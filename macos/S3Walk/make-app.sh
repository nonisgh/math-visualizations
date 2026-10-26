#!/bin/zsh
# swift build（release）して、S3Walk.app に包む（Xcode が無くても作れるように）。できた .app はこのフォルダに
set -e
cd "${0:A:h}"
# 設定の検索の索引（Dock.swift の項目から）
python3 -I tools/gen_search_index.py
swift build -c release
APP=S3Walk.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/S3Walk $APP/Contents/MacOS/S3Walk
# 軸の名前の書体（KaTeX の数式用の斜体＝TeX と同じ字形。次元おりがみ・ウェブ版と同じ。MIT、Fonts/KaTeX-LICENSE.txt）
cp Fonts/KaTeX_Math-Italic.ttf Fonts/KaTeX-LICENSE.txt $APP/Contents/Resources/
# アイコン：アプリ自身の地図から作る（--icon）。なければ作り、大きさごとの絵を iconutil でまとめる
if [ ! -f Icon/AppIcon-1024.png ]; then mkdir -p Icon; .build/release/S3Walk --icon Icon/AppIcon-1024.png >/dev/null; fi
ICS=$(mktemp -d)/AppIcon.iconset; mkdir -p $ICS
for s in 16 32 128 256 512; do
  sips -z $s $s Icon/AppIcon-1024.png --out $ICS/icon_${s}x${s}.png >/dev/null
  sips -z $((s * 2)) $((s * 2)) Icon/AppIcon-1024.png --out $ICS/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $ICS -o $APP/Contents/Resources/AppIcon.icns
cat > $APP/Contents/Info.plist <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>球面さんぽ</string>
  <key>CFBundleDisplayName</key><string>球面さんぽ</string>
  <key>CFBundleIdentifier</key><string>io.github.nonisgh.s3walk</string>
  <key>CFBundleExecutable</key><string>S3Walk</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
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
