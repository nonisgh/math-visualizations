// 次元おりがみ（iPad・iPhone 版）の入口：Mac 版と同じ Sources/Origami のファイル（OrigamiView など）を使う
import SwiftUI
import CoreText

@main
struct OrigamiiOSApp: App {
    init() {
        // 軸の名前の書体（KaTeX の数式用の斜体）
        if let u = Bundle.main.url(forResource: "KaTeX_Math-Italic", withExtension: "ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
    }
    var body: some Scene {
        WindowGroup { OrigamiView().statusBarHidden(true) }
    }
}
