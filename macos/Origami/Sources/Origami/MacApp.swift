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

/// 1 回だけ：アプリの名札（バンドル ID）を io.github.nonisgh.origami → app.nonisapps.origami に変えた（2026-11-23）ので、
///   前の名札で保存していた設定（画面の並び・プリセット・ショートカットなど）を、新しい名札の保存場所へ写す。
///   新しい方にもうある項目は上書きしない。前の名札の保存はそのまま残す（もどしたくなった時のため）
func migrateOldBundleDefaults() {
    let ud = UserDefaults.standard, flag = "origami.migr.bundleID1"
    guard Bundle.main.bundleIdentifier == "app.nonisapps.origami", !ud.bool(forKey: flag) else { return }
    if let old = ud.persistentDomain(forName: "io.github.nonisgh.origami") {
        let cur = ud.persistentDomain(forName: "app.nonisapps.origami") ?? [:]
        for (k, v) in old where cur[k] == nil { ud.set(v, forKey: k) }
    }
    ud.set(true, forKey: flag)
}

@main
struct OrigamiMacApp: App {
    @NSApplicationDelegateAdaptor(OrigamiAppDelegate.self) var delegate
    init() {
        let args = CommandLine.arguments
        // 確かめで動かす時は、使っている人の保存（プリセット・基本・往復・ショートカット・設定）に一切書かない。
        //   確かめのアプリも同じ名札（バンドル ID）なので、同じ保存場所を使う＝書くと、使っている人のプリセットが確かめの物に置きかわり、
        //   そのまま同期でクラウドにも上がっていた（2026-11-23 に「開き直すとプリセットが消える」で見つかった）
        if ["--net5atlas", "--ogpng", "--smooth", "--icon", "--perftest", "--uipng"].contains(where: args.contains) { SaveGuard.off = true }
        if let i = args.firstIndex(of: "--net5atlas"), i + 1 < args.count { Net5Atlas.writeData(args[i + 1]); exit(0) }   // 5 次元の展開図を数えて表を書き出す
        if let i = args.firstIndex(of: "--ogpng"), i + 1 < args.count { NS4.syncAll = true }
        if let i = args.firstIndex(of: "--ogpng"), i + 1 < args.count { registerFonts(); OrigamiRenderer.png(args[i + 1]); exit(0) }
        if args.contains("--smooth") { registerFonts(); OrigamiRenderer.smoothTest(); exit(0) }
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count { OrigamiRenderer.icon(args[i + 1]); exit(0) }
        if args.contains("--perftest") { PerfTest.on = true }
        if args.contains("--ns4test") { NS4.selfTest(); exit(0) }
        if args.contains("--ns4free") {   // 遊ぶモード：半分の水を入れて、ふたを開けたまま Y‐W で傾けていく。0.5 秒ごとに傾き・体積・重力の向き
            NS4.syncAll = true
            let st = OrigamiState(); st.reset(); st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = 24
            st.waterFree = true; st.ay = -Double.pi / 2; st.xz = 0.35; st.yz = -0.3; st.tween = nil; st.updateMats()   // 口（ふた +W）を真上に・ふたは開いている
            st.waterFreeFill(-1)
            // はじめの 4 秒：口を上にして押している間 注ぐ → たまるか。次の 3 秒：何もしない → 減らないか。そのあと Y‐W で 3 秒かけて逆さに → こぼれるか
            for n in 0..<(13 * 60) {
                st.waterPourHold = n < 4 * 60
                if n >= 7 * 60 { st.ay = -Double.pi / 2 + min(Double.pi, Double(n - 420) / 60 / 3 * Double.pi); st.updateMats() }
                st.waterTick(1.0 / 60)
                if n % 30 == 29, let ns = st.ns4 {
                    let g = ns.par.gvec
                    print(String(format: "%4.1f 秒 傾き %3.0f° 体積 %.3f 重力 (%+.1f, %+.1f, %+.1f, %+.1f) 1 歩 %.1f ミリ秒", Double(n + 1) / 60, st.ay * 180 / .pi, ns.lastVol, g.x, g.y, g.z, g.w, ns.stepMs))
                }
            }
            exit(0)
        }
        if args.contains("--ns4full") {   // 遊ぶモード：口を上にして満タンまで注ぎ（14 秒）、2 秒おいて、3 秒で逆さにし、さらに 4 秒。1 秒ごとに体積・空気のマスの数・いちばん速い
            NS4.syncAll = true
            let st = OrigamiState(); st.reset(); st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = 24
            if ProcessInfo.processInfo.environment["NSGRAVDOWN"] != nil { st.waterGravMode = 1 }
            st.waterFree = true; st.ay = st.waterFreeAY(0); st.xz = 0.35; st.yz = -0.3; st.tween = nil; st.updateMats()
            let ay0 = st.ay
            if ProcessInfo.processInfo.environment["NSBOTTOM"] != nil { st.waterBottomSet = false }
            st.waterFreeFill(-1)
            for n in 0..<(23 * 60) {
                st.waterPourHold = n < 14 * 60
                if n == 16 * 60, ProcessInfo.processInfo.environment["NSBOTTOM"] != nil { st.waterBottomSet = true }
                if n >= 14 * 60 && n < 16 * 60 { st.xz = 0.35 + Double(n - 840) / 120 * 1.2; st.yz = -0.3 + Double(n - 840) / 120 * 0.8; st.updateMats() }   // 見回す（3D の回転）：画面の奥の重力なら、水は傾かない
                if n >= 16 * 60 && ProcessInfo.processInfo.environment["NSBOTTOM"] == nil { st.ay = ay0 + min(Double.pi, Double(n - 960) / 60 / 3 * Double.pi); st.updateMats() }
                st.waterTick(1.0 / 60)
                if n % 60 == 59, let ns = st.ns4 {
                    let air = ns.phiCPU.enumerated().filter { i, v in v >= 0 && { let M = ns.M, q = (i % M, (i / M) % M, (i / (M * M)) % M, i / (M * M * M)); return q.0 < ns.N && q.1 < ns.N && q.2 < ns.N && q.3 < ns.N }() }.count
                    let g = ns.par.gvec
                    print(String(format: "%4.0f 秒 傾き %4.0f° 見回し %.2f 体積 %.3f（目標 %.3f）空気のマス %d いちばん速い %.2f 重力 (%+.1f %+.1f %+.1f %+.1f)", Double(n + 1) / 60, st.ay * 180 / .pi, st.xz, ns.lastVol, st.nsVTarget, air, ns.maxSpeed(), g.x, g.y, g.z, g.w))
                }
            }
            exit(0)
        }
        if args.contains("--ns4vort") {   // 排水口で抜く時の「ぐるぐる」：x‐y の面で回る速さ（水の中の平均）と渦の強さのいちばん大きい所。NSEPS で強調の強さ
            NS4.syncAll = true
            let st = OrigamiState(); st.reset(); st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = 16; st.drainMode = 1; st.waterSwirl = 0.3
            st.waterVort = ProcessInfo.processInfo.environment["NSEPS"].flatMap { Double($0) } ?? 3
            for n in 0..<(22 * 60) {
                st.waterTick(1.0 / 60)
                if n % 30 == 29 && st.waterPhase == 4, let ns = st.ns4 {
                    let M = ns.M, MM = ns.MM, N = ns.N, u = ns.U.contents().bindMemory(to: Float.self, capacity: 4 * MM), h = Double(N) / 2
                    var tsum = 0.0, cnt = 0.0, wmax: Float = 0
                    let w = ns.vW.contents().bindMemory(to: Float.self, capacity: MM)
                    for l in 0..<N { for k in 0..<N { for j in 0..<N { for i in 0..<N {
                        let id = ((l * M + k) * M + j) * M + i
                        guard ns.phiCPU[id] < 0 else { continue }
                        let ux = 0.5 * Double(u[id] + u[id + 1]), uy = 0.5 * Double(u[MM + id] + u[MM + id + M])
                        let x = Double(i) + 0.5 - h, y = Double(j) + 0.5 - h, r = sqrt(x * x + y * y)
                        if r > 1 { tsum += (-y * ux + x * uy) / r; cnt += 1 }
                        wmax = max(wmax, w[id])
                    } } } }
                    print(String(format: "%5.1f 秒 体積 %.2f　x‐y で回る速さ（平均）%+.4f　渦の強さ いちばん %.2f", st.waterT, ns.lastVol, cnt > 0 ? tsum / cnt : 0, wmax))
                }
            }
            exit(0)
        }
        if args.contains("--ns4slosh") {   // 半分の水（重力 箱の −w）で、0.6 秒かけて X‐Z を 1 ラジアン回して止める → 水の速さ（いちばん・平均）が上がって、だんだん静かになるか。NSSLOSH で強さ
            NS4.syncAll = true
            let st = OrigamiState(); st.reset(); st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = 16
            st.waterSlosh = ProcessInfo.processInfo.environment["NSSLOSH"].flatMap { Double($0) } ?? 1
            st.waterFree = true; st.waterGravMode = 2; st.waterLidSet = false; st.ay = 0; st.xz = 0; st.tween = nil; st.updateMats(); st.waterFreeFill(0)
            for n in 0..<(8 * 60) {
                if n >= 60 && n < 96 { st.drag(.r3x, 0.05) }   // ドラッグ（3D の回転）で 0.6 秒ゆさぶって止める
                st.waterTick(1.0 / 60)
                if n % 15 == 14, let ns = st.ns4 {
                    let MM = ns.MM, u = ns.U.contents().bindMemory(to: Float.self, capacity: 4 * MM)
                    var e = 0.0, cnt = 0.0
                    for i in 0..<MM where ns.phiCPU[i] < 0 { let a = Double(u[i]), b = Double(u[MM + i]), c = Double(u[2 * MM + i]), d = Double(u[3 * MM + i]); e += a * a + b * b + c * c + d * d; cnt += 1 }
                    let g = ns.par.gvec
                    print(String(format: "%4.2f 秒 回転 %.2f　水の速さ 平均 %.3f　いちばん %.2f　体積 %.2f　重力 (%+.1f %+.1f %+.1f %+.1f)", Double(n + 1) / 60, st.xz, cnt > 0 ? sqrt(e / cnt) : 0, ns.maxSpeed(), ns.lastVol, g.x, g.y, g.z, g.w))
                }
            }
            exit(0)
        }
        if args.contains("--ns4grav") {   // 半分の水（重力 箱の −w）→ 2 秒で「画面の下」に切りかえ：見る向きは変わらず、重力がなめらかに回るか
            NS4.syncAll = true
            let st = OrigamiState(); st.reset(); st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true; st.waterNSRes = 16
            st.waterFree = true; st.waterGravMode = 2; st.waterLidSet = false; st.ay = 0; st.xz = 0.35; st.yz = -0.3; st.tween = nil; st.updateMats(); st.waterFreeFill(0)
            let ay0 = st.ay
            for n in 0..<(5 * 60) {
                if n == 120 { st.waterGravMode = 1 }
                st.waterTick(1.0 / 60)
                if n % 12 == 11 && n >= 108 && n < 240, let ns = st.ns4 {
                    let g = ns.par.gvec
                    print(String(format: "%4.2f 秒 見る向き ay %.2f（はじめ %.2f）重力 (%+.1f %+.1f %+.1f %+.1f) いちばん速い %.2f 体積 %.2f", Double(n + 1) / 60, st.ay, ay0, g.x, g.y, g.z, g.w, ns.maxSpeed(), ns.lastVol))
                }
            }
            exit(0)
        }
        if args.contains("--balls") {   // 玉を詰める：どんどん入れて、2 秒ごとに数・詰まり具合・入れているか
            let st = OrigamiState(); st.reset(); st.progress = 1; st.intOn = true; st.intMethod = 2; st.ballsAuto = true
            for n in 0..<(60 * 60) {
                st.ballsTick(1.0 / 60)
                if n % 120 == 119 { print(String(format: "%3.0f 秒 4D %d 個 %.0f%%（いっぱい %@）・3D %d 個 %.0f%%（いっぱい %@）・どんどん %@", Double(n + 1) / 60, st.balls4.p.count, st.balls4.fill * 100, st.balls4.isFull(st.ballsSeed) ? "はい" : "いいえ", st.balls3.p.count, st.balls3.fill * 100, st.balls3.isFull(st.ballsSeed) ? "はい" : "いいえ", st.ballsAuto ? "入れている" : "止まった")) }
                if !st.ballsAuto && n % 120 == 119 { break }
            }
            exit(0)
        }
        if args.contains("--ns4cycle") {   // 1 回り（注ぐ → いっぱい → 抜く）を、本物の 4D の水で。1 秒ごとに場面・水位・体積・三角形の数・1 歩の時間
            NS4.syncAll = true
            let st = OrigamiState(); st.reset(); st.progress = 1; st.intOn = true; st.intMethod = 1; st.waterNS = true
            st.drainMode = ProcessInfo.processInfo.environment["NSDRAIN"].flatMap { Int($0) } ?? 1
            for n in 0..<(40 * 60) {
                st.waterTick(1.0 / 60)
                if n == 299, let ns = st.ns4 {   // 5 秒：壁の胞ごとの、水と空気が入れかわるマスの数と、水の中の空気の泡・空気の中の水のしずくの数
                    let N = ns.N
                    for a in 0..<4 { for s in [0, N - 1] {
                        var cross = 0, minV: Float = 9, maxV: Float = -9
                        for t in 0..<(N - 1) { for v in 0..<(N - 1) { for u in 0..<(N - 1) {
                            var neg = 0
                            for b in 0..<8 { var q = [0, 0, 0, 0]; let oth = (0..<4).filter { $0 != a }; q[a] = s; q[oth[0]] = u + (b & 1); q[oth[1]] = v + ((b >> 1) & 1); q[oth[2]] = t + ((b >> 2) & 1); let x = ns.phiCPU[ns.at(q[0], q[1], q[2], q[3])]; if x < 0 { neg += 1 }; minV = min(minV, x); maxV = max(maxV, x) }
                            if neg > 0 && neg < 8 { cross += 1 }
                        } } }
                        print("  胞 \(["x", "y", "z", "w"][a])\(s == 0 ? "−" : "+")：入れかわるマス \(cross)・φ \(minV)〜\(maxV)")
                    } }
                    var wl: [String] = []
                    for l in stride(from: 0, to: N, by: 4) { wl.append(String(format: "%.3f", ns.phiCPU[ns.at(N / 2, N / 2, 3, l)])) }
                    print("  柱 (16,16,3) の φ（w の下から 4 マスおき）：" + wl.joined(separator: " "))
                }
                if n % 60 == 59, let ns = st.ns4 {
                    print(String(format: "  入れる所 %.0f マス目（%d マス中）・筋の柱の水面 %+.3f", ns.par.jetC.w, ns.N, ns.surfaceWorld(OrigamiState.wUS)))
                    ns.meshID = -1; let tm0 = CFAbsoluteTimeGetCurrent(); let mesh = ns.wallMesh(); let tm1 = CFAbsoluteTimeGetCurrent()
                    var acc = SIMD3<Double>.zero; let m4 = st.m4
                    for q in mesh.p { let v = m4 * SIMD4<Double>(Double(q.x), Double(q.y), Double(q.z), Double(q.w)); acc += SIMD3(v.x, v.y, v.z) / (1 + v.w * 0.01) }
                    let tm2 = CFAbsoluteTimeGetCurrent()
                    print(String(format: "%5.1f 秒 場面 %d 水位 %+.3f 体積 %.3f（目標 %.3f）三角形 %d 1 歩 %.2f ミリ秒・皮を作る %.1f・写す %.1f ミリ秒%@", st.waterT, st.waterPhase, st.waterH, ns.lastVol, st.nsVTarget, mesh.kind.count, ns.stepMs, (tm1 - tm0) * 1000, (tm2 - tm1) * 1000, acc.x > 1e30 ? "!" : ""))
                }
            }
            exit(0)
        }
        if let v = ProcessInfo.processInfo.environment["ORIGAMI_SCALE"], let k = Double(v) { PerfTest.scale = k }   // 確かめの描く細かさ（引数にすると Mac の設定と取りちがえられるので、環境変数で）
        if let i = args.firstIndex(of: "--uipng"), i + 1 < args.count { registerFonts(); uiPNG(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--livetest"), i + 1 < args.count { registerFonts(); liveTest(args[i + 1]) }
        migrateOldBundleDefaults()
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
/// 確かめ：右上の札（AxisLenCard）が、回し続けている間に本当に書きかわるか。画面に出さない窓に置き、0.5 秒と 1.5 秒で写す
@MainActor func liveTest(_ dir: String) {
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    let st = OrigamiState(); st.toggle6()
    let hv = NSHostingView(rootView: AxisLenCard(st: st).environment(\.colorScheme, .dark))
    let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 120), styleMask: [.borderless], backing: .buffered, defer: false)
    win.contentView = hv; win.alphaValue = 0.02; win.ignoresMouseEvents = true; win.orderFrontRegardless()   // ほぼ透明（画面の外だと書きかえが止まることがあるので、画面の中に）
    var n = 0, fires = 0
    let sub = st.live.objectWillChange.sink { _ in fires += 1 }
    func snap(_ name: String) {
        print(name, "知らせ", fires, "回・札の数", AxisLenCard.last); _ = sub
        hv.layoutSubtreeIfNeeded()
        guard let rep = hv.bitmapImageRepForCachingDisplay(in: hv.bounds) else { return }
        hv.cacheDisplay(in: hv.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir).appendingPathComponent(name + ".png"))
        let c = st.m4.columns, cs: [SIMD4<Double>] = [c.0, c.1, c.2, c.3]
        var out: [Int] = []
        for v in cs { let l: Double = (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot(); out.append(Int((min(1.0, l) * 100).rounded())) }
        print(name, out)
    }
    Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { _ in
        MainActor.assumeIsolated {
            st.tickOnce(CACurrentMediaTime()); st.updateMats(); n += 1
            if n == 30 { snap("札_0.5秒") }
            if n == 90 { snap("札_1.5秒"); exit(0) }
        }
    }
    RunLoop.main.run()
}

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
        save(NetAtlas5Sheet(st: st), "展開図図鑑5_画面")
        save(VStack(spacing: 4) {                                          // 5 次元の図鑑の絵（はじめ・まんなか・最後のあたり）
            ForEach([[1, 2, 3, 4, 5, 6], [29, 2401, 5000, 7000, 8000, 9000], [9689, 9690, 9691, 9692, 9693, 9694]], id: \.self) { row in
                HStack(spacing: 4) { ForEach(row, id: \.self) { k in VStack(spacing: 1) { NetThumb5(flat: Net5Atlas.flat(Net5Atlas.entries[k - 1].parent) ?? [], cols: st.cellColors(5).map { PaletteEditor.color($0) }).frame(width: 110, height: 92); Text("No.\(k)").font(.system(size: 10)).foregroundStyle(UIC.text) } } }
            }
        }.padding(8).background(UIC.bg), "展開図図鑑5_絵")
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
