// swift-tools-version:5.9
// 球面さんぽ（S³ を進む）の macOS 版・実験。`swift build` で作り、`./make-app.sh` で S3Walk.app に包む
import PackageDescription

let package = Package(
    name: "S3Walk",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "S3Walk", path: "Sources/S3Walk")
    ]
)
