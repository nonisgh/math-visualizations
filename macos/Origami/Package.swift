// swift-tools-version:5.9
// 次元おりがみ（ネイティブ版）：ウェブ版 hypercube.html の超立方体を、Swift と Metal で。`swift build` で作り、`./make-app.sh` で Origami.app に包む
//   2026-11-13 に球面さんぽ（macos/S3Walk）の「試作」から切り分けた
import PackageDescription

let package = Package(
    name: "Origami",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "Origami", path: "Sources/Origami")
    ]
)
