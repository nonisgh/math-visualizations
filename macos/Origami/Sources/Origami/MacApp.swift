// 次元おりがみ（ネイティブ版）の Mac の入口：窓 1 つに、左の立方体と右の超立方体（OrigamiView）
//   確かめ用：--ogpng 出力先（確かめの絵と速さ）、--icon 出力先.png（アイコンの絵）、--uipng 出力先（パネルの 4 つのタブと回転バーの絵）
#if os(macOS)
import SwiftUI
import Combine
import AppKit
import CoreText
import MetalKit

/// 軸の名前の書体（KaTeX の数式用の斜体）を使えるようにする。アプリの中（Resources）か、作っている時はソースの横の Fonts から
func registerFonts() {
    let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fonts/KaTeX_Math-Italic.ttf")
    for u in [Bundle.main.url(forResource: "KaTeX_Math-Italic", withExtension: "ttf"), src].compactMap({ $0 }) where FileManager.default.fileExists(atPath: u.path) {
        CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil); return
    }
}

@main
struct OrigamiMacApp: App {
    @NSApplicationDelegateAdaptor(OrigamiAppDelegate.self) var delegate
    init() {
        let args = CommandLine.arguments
        if let i = args.firstIndex(of: "--ogpng"), i + 1 < args.count { registerFonts(); OrigamiRenderer.png(args[i + 1]); exit(0) }
        if args.contains("--smooth") { registerFonts(); OrigamiRenderer.smoothTest(); exit(0) }
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count { OrigamiRenderer.icon(args[i + 1]); exit(0) }
        if args.contains("--perftest") { PerfTest.on = true }
        if let v = ProcessInfo.processInfo.environment["ORIGAMI_SCALE"], let k = Double(v) { PerfTest.scale = k }   // 確かめの描く細かさ（引数にすると Mac の設定と取りちがえられるので、環境変数で）
        if let i = args.firstIndex(of: "--uipng"), i + 1 < args.count { registerFonts(); uiPNG(args[i + 1]); exit(0) }
        registerFonts()
    }
    var body: some Scene {
        WindowGroup("次元おりがみ") { OrigamiView().frame(minWidth: 900, minHeight: 600) }
            .defaultSize(width: 1400, height: 900)
    }
}

final class OrigamiAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) { NSApp.setActivationPolicy(.regular); NSApp.activate(ignoringOtherApps: true) }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

/// パネルの 4 つのタブと回転バーを絵に（Metal の窓は入らない。並び・文字の確かめ用）
@MainActor func uiPNG(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let st = OrigamiState(); st.spinX = true; st.spinY = true
    func save<V: View>(_ v: V, _ name: String) {
        let r = ImageRenderer(content: v.environment(\.colorScheme, .dark)); r.scale = 2
        guard let img = r.cgImage, let d = CGImageDestinationCreateWithURL(URL(fileURLWithPath: dir).appendingPathComponent(name + ".png") as CFURL, "public.png" as CFString, 1, nil) else { print("書けなかった", name); return }
        CGImageDestinationAddImage(d, img, nil); CGImageDestinationFinalize(d); print(name, img.width, "×", img.height)
    }
    for (k, t) in OrigamiPanel.tabs.enumerated() {
        st.panelTab = k
        let t0 = CACurrentMediaTime()
        save(OrigamiPanel(st: st, noScroll: true).frame(width: OrigamiView.panelW, height: 1100), "パネル_\(k + 1)_\(t.0)")
        print(String(format: "  （作るのに %.0f ミリ秒）", (CACurrentMediaTime() - t0) * 1000))
    }
    save(OrigamiRotBar(st: st).padding(8).background(UIC.bg), "回転バー")
    do {   // 展開図図鑑：261 種類の小さな絵を全部（スクロールなしで並べる）と、図鑑の画面
        let cols = st.cellColors(4).map { PaletteEditor.color($0) }
        let A = NetAtlas.all, W = 18
        save(VStack(alignment: .leading, spacing: 4) {
            ForEach(0..<((A.count + W - 1) / W), id: \.self) { r in
                HStack(spacing: 4) {
                    ForEach(A[(r * W)..<min(A.count, (r + 1) * W)]) { e in
                        VStack(spacing: 1) { NetThumb(flat: e.flat, cols: cols).frame(width: 72, height: 60); Text(e.def.name).font(.system(size: 9)).foregroundStyle(UIC.text) }
                    }
                }
            }
        }.padding(8).background(UIC.bg), "展開図図鑑_全部")
        save(NetAtlasSheet(st: st), "展開図図鑑_画面")
    }
    do {   // 組み上がりの向きの欄（自由・プリセットつき）
        let s6 = OrigamiState(); s6.asmPose = 5; s6.asmVanish = 0; s6.asmFree = [30, -20, 45, 0, 15, 0]
        s6.asmPresets = [AsmPreset(name: "X 消失の等角", pose: 4, vanish: 0, free: [0, 0, 0, 0, 0, 0], toW: true, lock: true), AsmPreset(name: "向き 2", pose: 2, vanish: 3, free: [0, 0, 0, 0, 0, 0], toW: false)]
        save(AsmPoseSection(st: s6).padding(10).frame(width: OrigamiView.panelW).background(UIC.panel), "組み上がりの向き_欄")
        let keepD = UserDefaults.standard.object(forKey: "asmDetailOpen"); UserDefaults.standard.set(true, forKey: "asmDetailOpen")
        save(AsmPoseSection(st: s6).padding(10).frame(width: OrigamiView.panelW).background(UIC.panel), "組み上がりの向き_欄_くわしく")
        if let keepD { UserDefaults.standard.set(keepD, forKey: "asmDetailOpen") } else { UserDefaults.standard.removeObject(forKey: "asmDetailOpen") }
    }
    do {   // サイコロ：出た目の札（24・48）と、回転タブの欄（記録つき）
        let s5 = OrigamiState()
        for (k, m) in [24, 48].enumerated() {
            s5.diceRes = OrigamiState.diceResult(3 + k * 2, 2 + k, m); s5.diceFlash = true
            save(DiceHUD(n: 4, st: s5).frame(width: 520, height: 300).background(UIC.bg), "サイコロ_出た目_\(m)")
        }
        for i in 0..<40 { let r = OrigamiState.diceResult(i % 8, (i * 5) % 6, 24); s5.diceHist.insert(r, at: 0); s5.diceCount24[r.n24 - 1] += 1; s5.diceCount48[r.n48 - 1] += 1 }
        s5.diceHist = Array(s5.diceHist.prefix(12))
        save(DiceSection(st: s5).padding(10).frame(width: OrigamiView.panelW).background(UIC.panel), "サイコロ_欄")
        do { let s4 = OrigamiState(); s4.net = OrigamiState.randomNet(); s4.panelTab = 0
            save(OrigamiPanel(st: s4, noScroll: true).frame(width: OrigamiView.panelW, height: 1100), "展開図図鑑_でたらめ") }
    }
    do {   // 積分の式の欄
        let s3 = OrigamiState(); s3.intOn = true; s3.intT = 5; s3.intItems = s3.intUpdate()
        save(IntegralHUD(n: 4, st: s3).frame(width: 520, height: 220).background(UIC.bg), "積分の式の欄")
    }
    do {   // 見せる胞の札（表だけ）
        let s2 = OrigamiState(); s2.faceSide = 1; s2.sideShown = [[3, 6], [4, 8]]
        save(OrigamiLabels(n: 4, st: s2).frame(width: 520, height: 160).background(UIC.bg), "見せる胞の札")
    }
    // 動いている間に、パネル全体の作り直しの合図（@Published）が何回出るか（1 秒 = 144 コマ）
    do {
        let cases: [(String, (OrigamiState) -> Void)] = [
            ("止まっている", { _ in }), ("4D に回し続ける", { $0.spinX = true; $0.spinY = true }), ("3D に回し続ける", { $0.spinXZ = true }),
            ("組み立て中", { $0.progress = 0; $0.playFold() }), ("くり返し", { $0.toggleLoop() }), ("周回", { $0.toggleCycle() }),
            ("角度の往復", { $0.startPP([[0, 0, 0, 0, 0, 0], [1, 0.5, 0, 0, 0, 0]], once: false) }), ("分解", { $0.startXp(1) }),
        ]
        for (name, f) in cases {
            let s2 = OrigamiState(); f(s2)
            var n = 0, nl = 0
            let c1 = s2.objectWillChange.sink { _ in n += 1 }, c2 = s2.live.objectWillChange.sink { _ in nl += 1 }
            var t = 100.0
            for _ in 0..<144 { t += 1.0 / 144; s2.tickOnce(t) }
            print("作り直しの合図（\(name)、1 秒）：パネル全体 \(n) 回・数字の所 \(nl) 回")
            c1.cancel(); c2.cancel()
        }
    }
    // 点のタブの部品ごと
    func timeView<V: View>(_ name: String, _ v: V) {
        let t0 = CACurrentMediaTime()
        let hv = NSHostingView(rootView: v.frame(width: OrigamiView.panelW).environment(\.colorScheme, .dark))
        hv.frame = NSRect(x: 0, y: 0, width: OrigamiView.panelW, height: 600); hv.layoutSubtreeIfNeeded()
        print(String(format: "  部品「%@」：%.0f ミリ秒", name, (CACurrentMediaTime() - t0) * 1000))
    }
    timeView("ためし（空）", Text("a"))
    timeView("座標で置く", PointAdder(st: st)); timeView("頂点", VertexGrid(st: st)); timeView("注目点", FocusPresets(st: st)); timeView("一覧", PointList(st: st))
    timeView("色選び 1 つ", ColorPicker("色", selection: .constant(Color.red)))
    timeView("文字の入力欄 1 つ", TextField("0", text: .constant("0")).textFieldStyle(.roundedBorder))
    timeView("NumRow 1 つ", NumRow("大きさ", .constant(0.5), 0...1, "%.2f", scale: 1))
    // 本物の部品（文字の入力欄・色選び）で、タブを開く時間をはかる（画面には出さない）
    do {
        st.panelTab = 0
        let hv = NSHostingView(rootView: OrigamiPanel(st: st, noScroll: ProcessInfo.processInfo.environment["NOSCROLL"] != nil).frame(width: OrigamiView.panelW, height: 900).environment(\.colorScheme, .dark))
        hv.frame = NSRect(x: 0, y: 0, width: OrigamiView.panelW, height: 900); hv.layoutSubtreeIfNeeded()
        func open(_ k: Int) -> Double {
            let t0 = CACurrentMediaTime()
            st.panelTab = k
            for _ in 0..<3 { RunLoop.main.run(until: Date().addingTimeInterval(0.001)); hv.layoutSubtreeIfNeeded() }
            return (CACurrentMediaTime() - t0) * 1000
        }
        for r in 0..<2 {
            if r == 1 { st.addAllVertices(); st.addEdgeMids(); st.addFaceCtrs(); print("点 \(st.userPts.count) 個で") }
            for (k, t) in OrigamiPanel.tabs.enumerated() where k > 0 {
                let a = open(k); _ = open(0)
                print(String(format: "本物の部品で「%@」を開く：%.0f ミリ秒", t.0, a))
            }
        }
    }
    save(ShortcutSheet(), "ショートカット")
}

extension OrigamiRenderer {
    /// アイコンの絵：組み上がった超立方体を少し回して、1024 × 1024 で
    static func icon(_ path: String) {
        guard let d = MTLCreateSystemDefaultDevice() else { return }
        let st = OrigamiState(); st.reset(); st.ax = 0.55; st.ay = 0.4; st.xz = 0.35; st.yz = -0.3; st.spaceMode = 2; st.progress = 1
        guard let r = OrigamiRenderer(n: 4, state: st, device: d) else { return }
        let n = 1024, td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: n, height: n, mipmapped: false)
        td.usage = [.renderTarget, .shaderRead]; td.storageMode = .managed
        guard let t = d.makeTexture(descriptor: td) else { return }
        for _ in 0..<3 {
            let rpd = MTLRenderPassDescriptor(); rpd.colorAttachments[0].texture = t; rpd.colorAttachments[0].loadAction = .dontCare; rpd.colorAttachments[0].storeAction = .store
            let cb = r.queue.makeCommandBuffer()!; r.encode(cb, rpd, n, n, now: 1, dt: 0.3)
            let bl = cb.makeBlitCommandEncoder()!; bl.synchronize(resource: t); bl.endEncoding(); cb.commit(); cb.waitUntilCompleted()
        }
        var px = [UInt8](repeating: 0, count: n * n * 4)
        t.getBytes(&px, bytesPerRow: n * 4, from: MTLRegionMake2D(0, 0, n, n), mipmapLevel: 0)
        let cs = CGColorSpace(name: CGColorSpace.sRGB)!, ctx = CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4, space: cs, bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
        if let dd = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) { CGImageDestinationAddImage(dd, ctx.makeImage()!, nil); CGImageDestinationFinalize(dd) }
    }
}
#endif
