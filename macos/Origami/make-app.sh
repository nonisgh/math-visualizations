#!/bin/zsh
# swift build（release）して、Origami.app（次元おりがみ）に包む（Xcode が無くても作れるように）。できた .app はこのフォルダに
set -e
cd "${0:A:h}"
swift build -c release
APP=Origami.app
rm -rf $APP
mkdir -p $APP/Contents/MacOS $APP/Contents/Resources
cp .build/release/Origami $APP/Contents/MacOS/Origami
# 軸の名前の書体（KaTeX の数式用の斜体＝TeX と同じ字形。ウェブ版と同じ。MIT、Fonts/KaTeX-LICENSE.txt）
cp Fonts/KaTeX_Math-Italic.ttf Fonts/KaTeX-LICENSE.txt $APP/Contents/Resources/
# アイコン：フラットデザインの絵（tools/make_icon.swift：ダリの十字架の積み木、ふたが折れかけ）。なければ作り、大きさごとの絵を iconutil でまとめる
#   iPad 用（角まで四角）は iOS/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png。作り直す時は：swift tools/make_icon.swift 出力フォルダ
if [ ! -f Icon/AppIcon-1024.png ]; then T=$(mktemp -d); swift tools/make_icon.swift $T >/dev/null; mkdir -p Icon; cp $T/AppIcon-mac-1024.png Icon/AppIcon-1024.png; fi
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
  <key>CFBundleName</key><string>次元おりがみ</string>
  <key>CFBundleDisplayName</key><string>次元おりがみ</string>
  <key>CFBundleIdentifier</key><string>app.nonisapps.origami</string>
  <key>CFBundleExecutable</key><string>Origami</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
# 署名：この Mac の開発用の証明書（Apple Development）があれば、それで署名する
SIGN_ID=$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ { print $2; exit }')
if [ -n "$SIGN_ID" ] && codesign --force --sign "$SIGN_ID" $APP >/dev/null 2>&1; then :
else codesign --force --sign - $APP >/dev/null 2>&1 || true; fi
echo "できた：$PWD/$APP"
