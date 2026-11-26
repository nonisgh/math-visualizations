// 次元おりがみの画面（ウェブ版 hypercube.html と同じつくり）
//   左に立方体の窓・右に超立方体の窓（境目をドラッグして広さを変える）、窓の上の下のほうに回転バー、右（B キーで左）にパネル。
//   パネル：上に 4 つのタブ（折りたたみ・回転・見え方・点）、中は区切り（見出しと中身）。区切りの順番と名前はウェブ版と同じ。
//     まだ移していない区切りは見出しだけ（「これから移します」）。ネイティブ版だけのもの（質感・光・宇宙）は「見え方」の「視覚効果」に。
//   キー（Mac）：スペース＝パネルの開け閉め、B＝パネルを左右に
import SwiftUI
import simd
#if os(macOS)
import AppKit
#endif

/// ウェブ版の色（Tailwind の slate など）
enum UIC {
    static let bg = Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255)
    static let panel = Color(red: 0.06, green: 0.09, blue: 0.16)
    static let card = Color(red: 0.09, green: 0.12, blue: 0.20)
    static let line = Color(red: 0.2, green: 0.25, blue: 0.33)
    static let text = Color(red: 0.89, green: 0.91, blue: 0.94)
    static let sub = Color(red: 0.58, green: 0.64, blue: 0.72)
    static let cyan = Color(red: 0.13, green: 0.83, blue: 0.93)
    static let amber = Color(red: 0.98, green: 0.75, blue: 0.3)
    static let sky = Color(red: 0.73, green: 0.9, blue: 0.99)
}

struct OrigamiView: View {
    @StateObject private var st = OrigamiState()
    /// ドラッグ・つまむ途中の値（@State にすると、マウスが動くたびに画面全部を作り直してコマが飛ぶので、作り直しの起きない入れ物に）
    final class GestureBox { var last = CGSize.zero; var pinch0: Double? = nil; var split0: Double? = nil; var grav: Bool? = nil }
    @State private var gb = GestureBox()
    @ObservedObject private var ks = ShortcutStore.shared
    #if os(macOS)
    @State private var keyMon: Any? = nil
    #endif
    static let panelW: CGFloat = 330
    var body: some View {
        HStack(spacing: 0) {
            if st.panelOpen && st.panelLeft { OrigamiPanel(st: st).frame(width: Self.panelW) }
            ZStack(alignment: .bottom) {
                panes
                OrigamiRotBar(st: st).padding(.bottom, 12)
                if !st.panelOpen {
                    Button { st.panelOpen = true } label: { Label("パネル", systemImage: "sidebar.right") }
                        .buttonStyle(.bordered).padding(10)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: st.panelLeft ? .topLeading : .topTrailing)
                        .help("操作パネルを開く（スペース）")
                }
            }
            if st.panelOpen && !st.panelLeft { OrigamiPanel(st: st).frame(width: Self.panelW) }
        }
        .background(UIC.bg)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $ks.show) { ShortcutSheet() }
        .sheet(isPresented: $st.atlasOpen) { NetAtlasSheet(st: st) }
        .sheet(isPresented: $st.atlas5Open) { NetAtlas5Sheet(st: st) }
        .onAppear { DispatchQueue.global(qos: .utility).async { _ = NetAtlas.built } }   // 図鑑を先に作っておく
        // 保存してあった設定をもどして、変わったら保存する（確かめの時は使わない＝いつも同じ初めの形で測る）
        .onAppear { if !PerfTest.on { st.startSettings() } }
        #if os(macOS)
        .onAppear {
            if PerfTest.on {                                                 // 確かめ：全部を回し続けて、8 秒で結果を出して終わる
                if ProcessInfo.processInfo.environment["ORIGAMI_USERSET"] != nil { st.loadSettingsReadOnly() }   // 確かめ：使っている人の設定で（読むだけ）
                st.toggle6(); st.renderScale = PerfTest.scale
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_ZF"], let z = Double(v) { st.zfAsm = z }   // 確かめ：組み上がりの大きさ
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_TAB"], let t = Int(v) { st.panelTab = t }   // 確かめ：開いておくタブ
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_ZOOM"], let z = Double(v) { st.zoom = [z, z] }   // 確かめ：つまんで寄った倍率
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_REFL"], let z = Double(v) { st.reflSelf = z }   // 確かめ：形どうしの映り込み
                // 確かめ：マウスで右の超立方体をドラッグし続けているつもり（1 秒 ORIGAMI_MOUSE 回）
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_MOUSE"], let hz = Double(v) {
                    Timer.scheduledTimer(withTimeInterval: 1.0 / hz, repeats: true) { _ in st.drag(.r3x, 0.004); st.drag(.r3y, 0.002) }
                }
                // 確かめ：本物のマウスの知らせ（押す→ドラッグ）を窓に送り続ける（画面のカーソルは動かさない）。右の超立方体の真ん中あたり
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_MOUSEEV"], let hz = Double(v) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        guard let w = NSApp.windows.first(where: { $0.isVisible }) else { return }
                        let y0 = w.contentLayoutRect.midY, x0 = w.contentLayoutRect.width * 0.55
                        func ev(_ t: NSEvent.EventType, _ x: CGFloat) -> NSEvent? {
                            NSEvent.mouseEvent(with: t, location: NSPoint(x: x, y: y0), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)
                        }
                        if let e = ev(.leftMouseDown, x0) { w.sendEvent(e) }
                        var k = 0.0
                        Timer.scheduledTimer(withTimeInterval: 1.0 / hz, repeats: true) { _ in k += 1; if let e = ev(.leftMouseDragged, x0 + CGFloat(sin(k * 0.02)) * 150) { w.sendEvent(e) } }
                    }
                }
                // 確かめ：つまみを手で動かし続けているつもり（1 秒 120 回、組み上がりの大きさを 0.3〜0.85 で行ったり来たり）
                if ProcessInfo.processInfo.environment["ORIGAMI_DRAG"] != nil {
                    let t0 = CACurrentMediaTime()
                    Timer.scheduledTimer(withTimeInterval: 1.0 / (Double(ProcessInfo.processInfo.environment["ORIGAMI_DRAG"] ?? "") ?? 120), repeats: true) { _ in st.zfAsm = 0.575 + 0.275 * sin((CACurrentMediaTime() - t0) * 2) }
                }
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_LOOP"] { if v != "spin" { st.stopSpins() }; st.loop = true }   // 「spin」なら回したまま   // 確かめ：組み立てと展開を行ったり来たり
                if ProcessInfo.processInfo.environment["ORIGAMI_WHO"] != nil {   // 確かめ：パネル全部の作り直しの知らせを数えて、どこから来たかを出す
                    var cnt = 0
                    PerfTest.who = st.objectWillChange.sink { _ in
                        cnt += 1
                        if cnt % 50 == 1 { PerfTest.info.append("知らせ \(cnt)：" + Thread.callStackSymbols.dropFirst(7).prefix(5).map { String($0.split(separator: " ", omittingEmptySubsequences: true).dropFirst(3).joined(separator: " ").prefix(160)) }.joined(separator: " | ")) }
                    }
                }
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_INSPH"] { st.inSphere = true; if v == "all" { st.inSphereLat = true; st.inSphereLon = true; st.inSphereCone = true }; if v == "lat" { st.inSphereLat = true; st.inSphereLon = false; st.inSphereCone = false }; if v == "loncone" { st.inSphereLat = false; st.inSphereLon = true; st.inSphereCone = true }; if v == "none" { st.inSphere = false } }   // 「all」なら模様を 3 つとも   // 確かめ：内接球を出して
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_UIHZ"], let hz = Double(v) { OrigamiState.uiHz = hz }   // 確かめ：パネルの書きかえの回数
                if ProcessInfo.processInfo.environment["ORIGAMI_SOFT"] != nil { st.inSphereDentSharp = false }   // 確かめ：めりこみをふんわりに
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_DIM5"] {   // 確かめ：5 次元β で回す（値 v ＝ 4D展開の見え方、それ以外 ＝ 3D展開）
                    if !st.dim5 { st.toggleDim5() }; if v != "v" { st.view5(0) }; st.spin5 = true
                }
                if ProcessInfo.processInfo.environment["ORIGAMI_MORPH"] != nil {   // 確かめ：展開図を 1.6 秒ごとに切りかえ続ける（組み変わりのアニメ）
                    var k = 0
                    Timer.scheduledTimer(withTimeInterval: 1.6, repeats: true) { _ in
                        k += 1; st.netAnim = true
                        if st.dim5 { st.switchNet5(OrigamiState.net5Presets[k % OrigamiState.net5Presets.count].1) }
                        else { st.switchNet(OrigamiState.netPresets[k % OrigamiState.netPresets.count]) }
                        PerfTest.info.append(String(format: "切りかえ %d：組み変わり %@・組み具合 %.2f・バラし %.2f", k, st.netMorph != nil ? "中" : "なし", st.progress, st.explodeE))
                    }
                }
                if ProcessInfo.processInfo.environment["ORIGAMI_BARTEST"] != nil {   // 確かめ：下のバーの回転のボタンを、本物のマウスの知らせで 押す・押す・右クリック・長押し して、結果を記録
                    st.stopSpins()
                    func pops() -> Int { NSApp.windows.filter { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }.count }
                    func ev(_ t: NSEvent.EventType, _ rr: CGRect? = nil) {
                        guard let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !String(describing: type(of: $0)).contains("Popover") }) else { return }
                        let r = rr ?? PerfTest.rotPill, h = w.contentView!.bounds.height
                        if let e = NSEvent.mouseEvent(with: t, location: NSPoint(x: r.midX, y: h - r.midY), modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: w.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: t == .leftMouseUp || t == .rightMouseUp ? 0 : 1) { NSApp.postEvent(e, atStart: false) }
                    }
                    func log(_ s: String) { PerfTest.info.append(String(format: "%@：回っている %@・メニューの窓 %d（ボタン %.0f,%.0f）", s, [st.spinX, st.spinY, st.spinZW, st.spinXY, st.spinXZ, st.spinYZ].contains(true) ? "はい" : "いいえ", pops(), PerfTest.rotPill.midX, PerfTest.rotPill.midY)) }
                    let q = DispatchQueue.main
                    q.asyncAfter(deadline: .now() + 2.0) { log("はじめ"); ev(.leftMouseDown); ev(.leftMouseUp) }
                    q.asyncAfter(deadline: .now() + 2.6) { log("1 回押した"); ev(.leftMouseDown); ev(.leftMouseUp) }
                    q.asyncAfter(deadline: .now() + 3.2) { log("2 回押した"); ev(.rightMouseDown); ev(.rightMouseUp) }
                    q.asyncAfter(deadline: .now() + 3.8) { log("右クリック"); NSApp.windows.filter { String(describing: type(of: $0)).contains("Popover") }.forEach { $0.close() } }
                    q.asyncAfter(deadline: .now() + 4.4) { log("メニューを閉じた"); ev(.leftMouseDown) }
                    q.asyncAfter(deadline: .now() + 5.2) { ev(.leftMouseUp) }
                    q.asyncAfter(deadline: .now() + 5.8) { log("長押し（0.8 秒）"); PerfTest.info.append("内接球（ふつうのボタン）押す前：\(st.inSphere)"); ev(.leftMouseDown, PerfTest.sphPill); ev(.leftMouseUp, PerfTest.sphPill) }
                    q.asyncAfter(deadline: .now() + 6.4) { PerfTest.info.append("内接球 押した後：\(st.inSphere)") }
                }
                if let v = ProcessInfo.processInfo.environment["ORIGAMI_P"], let p = Double(v) { st.progress = p; st.target = p }   // 確かめ：組み具合
                if ProcessInfo.processInfo.environment["ORIGAMI_BIG"] != nil {   // 確かめ：画面いっぱいの窓で
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { if let w = NSApp.windows.first(where: { $0.isVisible }), let sc = w.screen { w.setFrame(sc.visibleFrame, display: true) } }
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 8) {
                    if let w = NSApp.windows.first(where: { $0.isVisible }) {
                        PerfTest.info.append(String(format: "窓 %.0f×%.0f・画面 %@ 最高 %d コマ", w.frame.width, w.frame.height, w.screen?.localizedName ?? "?", w.screen?.maximumFramesPerSecond ?? 0))
                    }
                    PerfTest.info.append(String(format: "GPU で 1 コマ：立方体 %.2f ミリ秒・超立方体 %.2f ミリ秒・数えたコマ %d・%d・細かさ %.0f%%・ドラッグ中 %@", st.gpuMs[0], st.gpuMs[1], st.fps[0], st.fps[1], st.effScale * 100, st.dragging ? "はい" : "いいえ"))
                    PerfTest.info.append(String(format: "時計：1 秒 %d 回・頭脳で 1 コマ %.2f ミリ秒・重さ %.2f ミリ秒", st.driver.rate, st.driver.cpuMs, st.driver.costMs))
                    PerfTest.report(); exit(0)
                }
            }
            // スペース＝パネルの開け閉め、B＝パネルを左右に（文字を打っている所では使わない）
            keyMon = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { e in
                // ショートカット（OrigamiKeys.swift）。文字を打っている所では使わない（キーを登録中の時は別）
                if NSApp.keyWindow?.firstResponder is NSTextView && ShortcutStore.shared.capturing == nil { return e }
                return ShortcutStore.shared.handle(e, st) ? nil : e
            }
        }
        .onDisappear { if let m = keyMon { NSEvent.removeMonitor(m) }; keyMon = nil }
        #endif
    }
    /// 2 つの窓と境目（表示モード：両方・超立方体＋右上に立方体のミニ・超立方体だけ・立方体だけ。左右の入れかえ）
    var panes: some View {
        GeometryReader { g in
            let W = g.size.width
            switch st.displayMode {
            case 1:
                ZStack(alignment: .topTrailing) {
                    hyperPane
                    cubePane.frame(width: max(160, W * 0.3), height: max(120, g.size.height * 0.32))
                        .clipShape(RoundedRectangle(cornerRadius: 10)).overlay(RoundedRectangle(cornerRadius: 10).stroke(UIC.line))
                        .padding(.top, 150).padding(.trailing, 10)
                }
            case 2: hyperPane
            case 3: cubePane
            default: if st.shapeOn && !st.dim5 { threePanes(W) } else { twoPanes(W) }
            }
        }
    }
    // 5 次元 β：左（cubePane の場所）に超立方体、右（hyperPane の場所）に 5 次元超立方体
    @ViewBuilder var cubePane: some View {
        if st.dim5 { pane(4, "超立方体（1 つ下の次元のたとえ）", "X-W・Y-W・Z-W は、5 次元の X-V・Y-V・Z-V と同じ角度").overlay(alignment: .topTrailing) { AxisLenCard(st: st).padding(10) } }
        else { pane(3, "立方体（2D 展開図 → 3D）", "折りたたみでできる新しい次元＝z") }
    }
    @ViewBuilder var hyperPane: some View {
        if st.dim5 { pane(5, "5 次元超立方体 β（4D 展開図 → 5D）", st.drag5Roll ? "折りたたみでできる新しい次元＝v（琥珀）。ドラッグ＝転がす（形はそのまま）" : "折りたたみでできる新しい次元＝v（琥珀）。ドラッグ＝5 次元だけの X-W・Y-W、⇧＝W-V") }
        else { pane(4, "超立方体（3D 展開図 → 4D）", "折りたたみでできる新しい次元＝w").overlay(alignment: .topTrailing) { AxisLenCard(st: st).padding(10) } }
    }
    /// 立体を見る：大きい窓（断面、または 4D の影）と、右に小さい窓 2 つ（3D のたとえ・4D の影＋切っている所、または断面）
    func threePanes(_ W: CGFloat) -> some View {
        let name = OrigamiState.shapeNames[max(1, min(5, st.shapeKind))], ana = OrigamiState.shapeAnalog[max(1, min(5, st.shapeKind))]
        let secT = "断面：\(name)を 3 次元の面で切った切り口", projT = "4D の影：\(name)（w の輪切りを重ねる）＋ 今切っている所"
        return HStack(spacing: 0) {
            pane(4, st.shapeMainProj ? projT : secT, "ドラッグ＝回す（4 次元で回すと切る向きが変わる）。色＝七色の帯（y）", role: 1).frame(width: W * 0.64)
            Rectangle().fill(UIC.line).frame(width: 5)
            VStack(spacing: 0) {
                pane(3, "3D のたとえ：\(ana)", "平面で切ると、切り口は線（赤）")
                Rectangle().fill(UIC.line).frame(height: 5)
                pane(4, st.shapeMainProj ? secT : projT, st.shapeMainProj ? "" : "光る所＝大きい窓の断面")
            }
        }
    }
    func twoPanes(_ W: CGFloat) -> some View {
        let lw = max(160, min(W - 160, W * st.split))
        return HStack(spacing: 0) {
                if st.swapViews { hyperPane.frame(width: lw) } else { cubePane.frame(width: lw) }
                // 境目：ドラッグで立方体の窓の広さを変える
                Rectangle().fill(UIC.line).frame(width: 5)
                    .overlay(Capsule().fill(UIC.sub.opacity(0.6)).frame(width: 2, height: 34))
                    .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                        if gb.split0 == nil { gb.split0 = st.split }
                        st.split = max(0.15, min(0.85, gb.split0! + Double(v.translation.width / max(1, W))))
                    }.onEnded { _ in gb.split0 = nil })
                    #if os(macOS)
                    .onHover { inside in if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() } }
                    #endif
                if st.swapViews { cubePane } else { hyperPane }
        }
    }
    func pane(_ n: Int, _ title: String, _ sub: String, role: Int = 0) -> some View {
        let i = role == 1 ? 2 : st.wix(n)
        return ZStack(alignment: .topLeading) {
            #if os(macOS)
            // Mac はマウス・つまみを絵の窓（OrigamiMTKView）が直接受ける
            OrigamiPane(n: n, st: st, role: role)
            #else
            OrigamiPane(n: n, st: st, role: role)
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    let dd = CGSize(width: g.translation.width - gb.last.width, height: g.translation.height - gb.last.height); gb.last = g.translation
                    // 重力ハンドル：さわり始めが矢印の先の玉の近くなら、その指は重力の向きを変える（形は回さない）
                    if gb.grav == nil { gb.grav = st.gravHandleOn(n) && st.gravHit(n, g.startLocation, size: st.paneSize[n] ?? .zero) }
                    if gb.grav == true { st.gravDrag(n, Double(dd.width), Double(dd.height), alt: false, size: st.paneSize[n] ?? .zero); return }
                    #if os(macOS)
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    #else
                    let shift = false
                    #endif
                    if n == 5 && st.drag5Roll { st.drag(.r3x, Double(dd.width) * 0.01); st.drag(.r3y, Double(dd.height) * 0.01) }   // 5 次元：転がす（形はゆがまない）
                    else if n == 5 { if shift { st.drag(.wv5, Double(dd.width) * 0.01) } else { st.drag(.x5, Double(dd.width) * 0.01); st.drag(.y5, Double(dd.height) * 0.01) } }
                    else if shift { st.drag(.zw, Double(dd.width) * 0.01) }
                    else if n == 3 || st.dim5 { st.drag(.l4x, Double(dd.width) * 0.01); st.drag(.l4y, Double(dd.height) * 0.01) }   // 左：X-W・Y-W（左は X-Z・Y-Z）
                    else { st.drag(.r3x, Double(dd.width) * 0.01); st.drag(.r3y, Double(dd.height) * 0.01) }            // 右：画面の縦・横の軸のまわりに形を回す
                }.onEnded { _ in gb.last = .zero; gb.grav = nil; st.dragging = false })
                .simultaneousGesture(MagnificationGesture().onChanged { k in
                    if gb.pinch0 == nil { gb.pinch0 = st.zoom[i] }
                    st.zoom[i] = max(0.3, min(8, gb.pinch0! * Double(k)))
                }.onEnded { _ in gb.pinch0 = nil })
            #endif
            if role == 0 && !(st.shapeOn && n == 4 && st.shapeMainProj) { OrigamiLabels(n: n, st: st).allowsHitTesting(false) }   // 立体を見る時の断面の窓・メインの窓には番号の札を出さない
            // 積分の式の欄（窓の下のまんなか）
            IntegralHUD(n: n, st: st).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom).allowsHitTesting(false)
            // 次に C を押すと何が起きるか（超立方体の窓の右下）
            if n == 4 { NextCLine(st: st, small: true).padding(10).frame(maxWidth: 260, alignment: .trailing).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing).allowsHitTesting(false) }
            // サイコロの出た目（ドン！）
            DiceHUD(n: n, st: st).allowsHitTesting(false)
            // 移動パッド（ウェブ版と同じ：窓の左のまんなかの丸）：ドラッグで図形を動かす（⌘／Ctrl＋ドラッグと同じ）・ダブルクリックで真ん中へ
            if st.panPad { PanPad(st: st, i: i).frame(maxHeight: .infinity, alignment: .center).padding(.leading, 12) }
            // 見出しの札（ウェブ版と同じ形）
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(UIC.text)
                Text(sub).font(.system(size: 10)).foregroundStyle(UIC.sub)
            }
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(UIC.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(UIC.line))
            .padding(10).allowsHitTesting(false)
        }
        .clipped()
        .id("pane\(n)r\(role)")                                                   // 5 次元 β の入り切りで、同じ場所の窓の次元が変わったら作り直す
    }
}

// MARK: - 下の回転バー（ウェブ版の rot-bar）
//   回し続ける（W(X,Y,Z)・W(X,Y)・3D・全て）は「回転 ▾」の 1 つにまとめて、押すと小さな窓で選ぶ。
//   同じ形で「表示 ▾」（見せる胞：全部・表だけ・裏だけ）と「分解 ▾」（バラす・くっつける・数える・離し具合）も
struct OrigamiRotBar: View {
    @ObservedObject var st: OrigamiState
    @State var openRot = false
    @State var openSide = false
    @State var openXp = false
    @State var open5 = false
    @State var openSph = false
    @AppStorage("origami.rotBarLastSpin") var lastSpin = 0     // 回転のボタンを押した時に回す回し方（0 W(X,Y,Z)・1 W(X,Y)・2 3D・3 全て）。メニューで選んだものを覚える
    /// 回転のボタン：回っていれば止める、止まっていれば前に選んだ回し方で回す
    func tapSpin() {
        if anySpin { st.stopSpins(); return }
        switch lastSpin { case 1: st.toggleW2(); case 2: st.toggle3D(); case 3: st.toggle6(); default: st.toggleWAll() }
    }
    /// 今の回し方の名前（ボタンに出す）
    var rotName: String {
        if st.allW && st.all3D { return "全て" }
        if st.allW { return "W(X,Y,Z)" }
        if st.w2Only { return "W(X,Y)" }
        if st.all3D { return "3D" }
        return [st.spinX, st.spinY, st.spinZW, st.spinXY, st.spinXZ, st.spinYZ].contains(true) ? "一部" : "止まっている"
    }
    var anySpin: Bool { [st.spinX, st.spinY, st.spinZW, st.spinXY, st.spinXZ, st.spinYZ].contains(true) }
    var body: some View {
        HStack(spacing: 6) {
            popPill("回転：\(rotName)", anySpin, "回し続ける（もう一度で止める）。回し方（W の 3 面・W の 2 面・3D・全て）はメニューで", $openRot, tap: tapSpin) {
                Text("回し続ける").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
                pill("W(X,Y,Z)", st.allW, "W の絡む 3 面（X-W・Y-W・Z-W）を回し続ける＝中身がぐりぐり入れかわる 4D の回転") { lastSpin = 0; st.toggleWAll() }
                pill("W(X,Y)", st.w2Only, "X-W・Y-W の 2 面だけを回し続ける（Z-W は回さない）。立方体も X-Z・Y-Z で一緒に回る") { lastSpin = 1; st.toggleW2() }
                pill("3D", st.all3D, "X-Y・X-Z・Y-Z（w を含まない 3 面＝ふつうの 3D の回転）を回し続ける。形は変わらず転がる") { lastSpin = 2; st.toggle3D() }
                pill("全て", st.allW && st.all3D, "6 面すべてを同時に回し続ける") { lastSpin = 3; st.toggle6() }
                pill("止める", false, "回し続けるのを全部止める（角度はそのまま）") { st.stopSpins() }
            }
            .background(GeometryReader { g in Color.clear.onAppear { if PerfTest.on { PerfTest.rotPill = g.frame(in: .global) } } })
            .onAppear {   // 確かめ：起動して少ししたら回転のメニューを開く（環境変数 ORIGAMI_OPENPOP。iPad のシミュレーターで、メニューが上に出るかを見る）
                if ProcessInfo.processInfo.environment["ORIGAMI_OPENPOP"] != nil { DispatchQueue.main.asyncAfter(deadline: .now() + 2) { openRot = true } }
            }
            popPill("表示：" + ["全部", "表だけ", "裏だけ"][max(0, min(2, st.faceSide))], st.faceSide != 0, "見せる胞（立方体は面）：押すたびに 全部 → 表だけ → 裏だけ。表＝ひとつ上の次元の目から見て表を向いている胞", $openSide, tap: { st.faceSide = (st.faceSide + 1) % 3 }) {
                Text("見せる胞").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
                pill("全部", st.faceSide == 0, "全部の胞を見せる") { st.faceSide = 0 }
                pill("表だけ", st.faceSide == 1, "表を向いている胞だけ（超立方体は多くて 4 個、立方体は多くて 3 面）") { st.faceSide = 1 }
                pill("裏だけ", st.faceSide == 2, "裏を向いている胞だけ") { st.faceSide = 2 }
            }
            popPill(st.apart ? "分解：バラバラ" : "分解", st.apart, "押すと 1 つずつの形に分けて離す（バラす）・もう一度でくっつける。数える・時間差・つまみはメニューで", $openXp, tap: { if st.counting { st.endCount() }; st.startXp(st.apart ? 0 : 1) }) {
                Text("分解").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
                pill(st.apart ? "くっつける" : "バラす", st.apart, "1 つずつの形に分けて離す／元にくっつける") { if st.counting { st.endCount() }; st.startXp(st.apart ? 0 : 1) }
                pill(st.counting ? "数えるのをやめる" : "数える", st.counting, "バラして、1 個ずつ番号を付けて光らせながら数える") { if st.counting { st.endCount() } else { st.startCount() } }
                pill("時間差", st.xpStagger, "バラす・くっつける時に、番号の順に少しずつずらす") { st.xpStagger.toggle() }
                LiveRead(live: st.live) {
                    Slider(value: Binding(get: { st.xpAnim != nil ? max(0, min(1, st.explodeE)) : st.explodeRaw }, set: { st.xpAnim = nil; if st.counting { st.endCount() }; st.explodeRaw = $0 }), in: 0...1)
                        .frame(width: 140).help("くっついた ↔ バラバラ")
                }
            }
            pill("🎲", st.diceRolling, "超立方体サイコロを振る（⇧0）：①4D でころころ → 奥の胞が決まる ②その胞が飛び出して 3D でころころ → 手前の面が目（24 の目・48 の目は回転タブで）") { st.rollDice() }
            pill("5次元β", st.dim5, "5 次元 β：左に超立方体・右に 5 次元超立方体（10 個の超立方体の展開図を 5 次元で折りたたむ）。もう一度押すと元の立方体と超立方体に") { st.toggleDim5() }
            if st.dim5 {
                popPill("5D の見え方", st.spin5, "押すと 5 次元だけの 4 面を回す（もう一度で止める）。見え方のおすすめ（3D展開・4D展開）・展開図はメニューで", $open5, tap: { st.spin5.toggle(); st.tw5 = nil }) {
                    Text("見え方のおすすめ").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
                    pill("3D展開", false, "10 面とも 0°（w も v も目の方へつぶれる）＋ななめ・遠近：±W の胞が真ん中の手前と奥に重なった、真ん中が太い「3 次元の十字架」") { st.view5(0) }
                    pill("4D展開", false, "5 次元だけの X-W 45°・Y-W 35.3°・Z-W 30° ＋ななめ・平行投影：w が 3D に出てきて、8 方向の腕が全部見える「4 次元の十字架」") { st.view5(1) }
                    Text("5 次元だけの面（X-W・Y-W・Z-W・W-V）").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
                    pill("4 面とも回す", st.spin5, "5 次元だけの 4 面を回し続ける（左の超立方体は動かない）") { st.spin5.toggle(); st.tw5 = nil }
                    pill("4 面とも 0 へ", false, "5 次元だけの 4 面を 0° へもどす") { st.zero5() }
                    Net5Picker(st: st)
                    Text("右の窓のドラッグ").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
                    pill("転がす（形はそのまま）", st.drag5Roll, "ふつうの 3D の回転：形をゆがめずに、くるくる回してながめる（3D展開のハンマーの形も、そのままの形で回る）") { st.drag5Roll = true }
                    pill("5 次元の面（w がせり出す）", !st.drag5Roll, "5 次元だけの X-W・Y-W を回す（⇧ で W-V）。4 次元・5 次元の方向へ回すので、写した形は変わる") { st.drag5Roll = false }
                    Text("形を変えずに回し続けてながめたい時は、「回転 ▾」の 3D を選ぶと、ゆがまずに回り続けます").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
            popPill("内接球", st.inSphere, "押すと超立方体にぴったり内接する超球面（8 個の胞の真ん中に接する）を出す・消す。模様（緯度・経度・円錐、いくつでも）はメニューで。超立方体と一緒に回る", $openSph, tap: { st.inSphere.toggle() }) {
                Text("模様（いくつでも）").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
                pill("緯度（球殻）", st.inSphereLat, "w ＝ 一定で切った球殻（超球面アプリと同じ積み重ね）") { st.inSphereLat.toggle(); st.inSphere = true }
                pill("経度", st.inSphereLon, "経度が一定の面（大円の球の半分）を 8 枚") { st.inSphereLon.toggle(); st.inSphere = true }
                pill("円錐", st.inSphereCone, "y の軸からの角度 θ が一定の面を 5 枚（真ん中から見ると円錐）") { st.inSphereCone.toggle(); st.inSphere = true }
                pill(st.dim5 ? "正 120 胞体／正軸体" : "正 120 胞体", st.inSphere120, "正十二面体の部屋 120 個で超球面を埋めた形の、少し太いワイヤー。接点は部屋の真ん中。5 次元 β では正軸体（頂点が 10 個の接点）") { st.inSphere120.toggle(); st.inSphere = true }
                pill("全部", st.inSphereLat && st.inSphereLon && st.inSphereCone, "緯度・経度・円錐を全部") { st.inSphereLat = true; st.inSphereLon = true; st.inSphereCone = true; st.inSphere = true }
            }
                .background(GeometryReader { g in Color.clear.onAppear { if PerfTest.on { PerfTest.sphPill = g.frame(in: .global) } } })
            pill("ワイヤー", st.wireOnly, "面を描かず、辺の線だけで見せる（⇧M。もう一度でメッシュにもどる＝ M）") { st.wireOnly.toggle() }
            Divider().frame(height: 18)
            pill("補正", false, "z 軸を画面に垂直に立て直す（Z-W・X-Z・Y-Z を 0 に。回転は止めない）") { st.snap() }
            pill("まっすぐ", false, "画面の中に寝ている 2 本の軸を、いちばん近い縦・横にそろえる（絵を画面の中で回すだけ。⇧S）") { st.straighten() }
            pill("リセット", false, "回転を止めて、全部の角度を 0 に戻した正面の形にする") { st.resetAll() }
            Divider().frame(height: 18)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text("\(max(st.fps[0], st.fps[1])) コマ/秒").font(.system(size: 10).monospacedDigit()).foregroundStyle(UIC.sub).lineLimit(1).fixedSize()
                    .help(String(format: "1 秒に描いたコマの数（GPU で 1 コマ：立方体 %.1f ミリ秒・超立方体 %.1f ミリ秒）", st.gpuMs[0], st.gpuMs[1]))
            }
            Divider().frame(height: 18)
            LiveRead(live: st.live) { Text(st.projBlend > 0.5 ? "投影: 平行" : "投影: 遠近").font(.system(size: 11)).foregroundStyle(UIC.sub).lineLimit(1).fixedSize() }
                .help("今の投影（遠近＝いつも奥行きあり／平行＝W の角度が付いていれば平行投影）")
            pill(st.perspMode ? "→ 平行投影" : "→ 遠近投影", !st.perspMode, "投影の切りかえ。平行投影＝W の回転・面／辺／頂点から が、きれいな正多角形に（W の角度が 0 のままだと、外と内の立方体がぴったり重なって 1 つの立方体に見える）。遠近投影＝いつも奥行きあり") { st.perspMode.toggle() }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(UIC.panel.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(UIC.line))
    }
    /// 押すと tap（動かす／止める）、長押し（Mac は右クリックも）で小さな窓（ポップオーバー）が開くボタン（名前のうしろに ▾）。中は縦に並べる
    func popPill<C: View>(_ t: String, _ on: Bool, _ help: String, _ open: Binding<Bool>, tap: @escaping () -> Void, @ViewBuilder _ content: @escaping () -> C) -> some View {
        // 押す：ふつうのボタン（tap）。長押し（0.45 秒）：横で同時に見て、メニューを開く。
        //   長押しで開いた時は、指を離した時のボタンの押しは無視する（メニューが開いていたら tap しない）。
        //   （長押しを先に見て、だめならタップ、の組み合わせは Mac でクリックを受けとれなかった）
        Button { if !open.wrappedValue { tap() } } label: { pillLabel(t + " ▾", on || open.wrappedValue) }
            .buttonStyle(.plain)
            .simultaneousGesture(LongPressGesture(minimumDuration: 0.45).onEnded { _ in open.wrappedValue = true })
            #if os(macOS)
            .background(RightClickCatcher { open.wrappedValue = true })
            .help(help + "（右クリックでメニュー）")
            #else
            .help(help + "（長押しでメニュー）")
            #endif
            .popover(isPresented: open, arrowEdge: Self.popEdge) {
                VStack(alignment: .leading, spacing: 6) { content() }
                    .padding(12).frame(minWidth: 160, alignment: .leading)
                    .background(UIC.panel)
                    .preferredColorScheme(.dark)
                    #if os(iOS)
                    .presentationCompactAdaptation(.popover)
                    #endif
            }
    }
    /// 下のバーのメニューは、ボタンの上に出す。arrowEdge の意味が Mac と iPad で逆（Mac：ボタンのどの辺に出すか・iPad：メニューのどの辺に矢印を付けるか）。
    ///   iPad で .top にすると、メニューがボタンの下（画面の外）に出て選べなかった
    #if os(iOS)
    static let popEdge: Edge = .bottom
    #else
    static let popEdge: Edge = .top
    #endif
    func pill(_ t: String, _ on: Bool, _ help: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) { pillLabel(t, on) }.buttonStyle(.plain).help(help)
    }
    func pillLabel(_ t: String, _ on: Bool) -> some View {
        Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(on ? UIC.cyan : UIC.text)
            .lineLimit(1).fixedSize()
            .padding(.horizontal, 9).padding(.vertical, 4)
            .background(on ? UIC.cyan.opacity(0.18) : Color.white.opacity(0.06), in: Capsule())
            .overlay(Capsule().stroke(on ? UIC.cyan.opacity(0.8) : UIC.line))
    }
}

/// 内接球の模様：緯度（球殻）・経度・円錐。いくつでも同時に選べる（全部も）
struct InSphereModeRow: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        HStack(spacing: 6) {
            Text("模様").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
            Btn("緯度（球殻）", on: st.inSphereLat) { st.inSphereLat.toggle() }.help("w ＝ 一定で切った球殻を積んだ形（超球面アプリと同じ）。立方体の窓では緯度の輪。枚数は下の「層」で")
            Btn("経度", on: st.inSphereLon) { st.inSphereLon.toggle() }.help("経度が一定の面（大円の球の半分）を 8 枚。超球面アプリの経度の面と同じ考え")
            Btn("円錐", on: st.inSphereCone) { st.inSphereCone.toggle() }.help("y の軸からの角度 θ が一定の面を 5 枚（30°〜150°）。真ん中から見ると円錐、超球面の上では両はしの閉じたまゆ玉の形（90° だけ平らな大きな球）")
            Btn(st.dim5 ? "正 120 胞体／正軸体" : "正 120 胞体", on: st.inSphere120) { st.inSphere120.toggle() }.help("5 次元 β では正軸体（正 32 胞体）：頂点がちょうど 10 個の接点で、正単体の部屋 32 個で 4 次元の球面を埋める（5 次元には正 120 胞体の仲間がない）。" + "正十二面体の部屋 120 個で超球面をすき間なく埋めた形を、少し太いワイヤーで（点 600・辺 1200）。8 つの接点は、ちょうど部屋の真ん中。色はいちばん近い接点の色（「接点の色」の軸の色・胞の色）。立方体の窓は球面の正十二面体")
            Btn("全部", on: st.inSphereLat && st.inSphereLon && st.inSphereCone) { st.inSphereLat = true; st.inSphereLon = true; st.inSphereCone = true }.help("緯度・経度・円錐を全部出す。3 つそろうと超球面の座標の網がそろう")
        }
    }
}

#if os(macOS)
/// 右クリックを受ける透明な下じき：その場所で右クリックされたら act（左クリックは上のボタンへそのまま通す）
struct RightClickCatcher: NSViewRepresentable {
    let act: () -> Void
    final class V: NSView {
        var act: () -> Void = {}
        private var mon: Any?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let m = mon { NSEvent.removeMonitor(m); mon = nil }
            guard window != nil else { return }
            mon = NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] e in
                guard let self, let w = self.window, e.window === w, !self.isHiddenOrHasHiddenAncestor else { return e }
                if self.bounds.contains(self.convert(e.locationInWindow, from: nil)) { self.act(); return nil }
                return e
            }
        }
        deinit { if let m = mon { NSEvent.removeMonitor(m) } }
        override func hitTest(_ p: NSPoint) -> NSView? { nil }                // 左クリックなどは通す
    }
    func makeNSView(context: Context) -> V { let v = V(); v.act = act; return v }
    func updateNSView(_ v: V, context: Context) { v.act = act }
}
#endif

// MARK: - 右のパネル（ウェブ版の ui-overlay）
struct OrigamiPanel: View {
    @ObservedObject var st: OrigamiState
    var noScroll = false                      // 確かめの絵（--uipng）を書き出す時は、スクロールの枠なしで（枠の中は絵にならないので）
    static let tabs: [(String, String)] = [("折りたたみ", "slider.horizontal.3"), ("回転", "rotate.3d"), ("見え方", "eye"), ("点", "mappin"), ("積分", "sum")]
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("次元おりがみ", systemImage: "cube.transparent").font(.system(size: 12, weight: .bold)).foregroundStyle(UIC.text)
                Spacer()
                Button { ShortcutStore.shared.show = true } label: { Image(systemName: "keyboard") }.buttonStyle(.plain).foregroundStyle(UIC.sub).help("ショートカットの設定（⇧K）")
                Button { st.panelLeft.toggle() } label: { Image(systemName: "arrow.left.arrow.right") }.buttonStyle(.plain).foregroundStyle(UIC.sub).help("パネルを左右どちらに置くか切りかえる（B キー）")
                Button { st.panelOpen = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain).foregroundStyle(UIC.sub).help("パネルを閉じて図形を広く（スペース）")
            }
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 6)
            HStack(spacing: 4) {
                ForEach(Self.tabs.indices, id: \.self) { k in
                    Button { TabTimer.open(st, k) } label: {
                        Label(Self.tabs[k].0, systemImage: Self.tabs[k].1).font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(st.panelTab == k ? UIC.cyan : UIC.sub)
                            .padding(.horizontal, 7).padding(.vertical, 4)
                            .background(st.panelTab == k ? UIC.cyan.opacity(0.15) : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal, 10).padding(.bottom, 8)
            Divider().overlay(UIC.line)
            if noScroll { tabBody; Spacer(minLength: 0) } else { ScrollView { tabBody } }
        }
        .background(UIC.panel)
        .overlay(alignment: st.panelLeft ? .trailing : .leading) { Rectangle().fill(UIC.line).frame(width: 1) }
        .controlSize(.small)
    }

    var tabBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch st.panelTab {
            case 0: foldTab
            case 1: rotTab
            case 2: viewTab
            case 3: ptsTab
            default: IntegralTab(st: st)
            }
        }
        .padding(10)
    }

    // ---- 折りたたみ ----
    @ViewBuilder var foldTab: some View {
        Sec("折りたたみ進行", "chart.bar.fill") {
            LiveRead(live: st.live) {
                HStack {
                    Slider(value: Binding(get: { st.progress }, set: { st.playing = false; st.loop = false; st.progress = $0 }), in: 0...1)
                    NumField(Binding(get: { st.progress }, set: { st.playing = false; st.loop = false; st.progress = $0 }), 0...1, "%.0f%%", scale: 100)
                }
            }
        }
        Sec("展開図のかたち", "square.grid.3x3.square") {
            // 見本の展開図とでたらめ。立方体の展開図も、合わせた形（アナロジー）に変わる
            HStack(spacing: 6) {
                ForEach(OrigamiState.netPresets.indices, id: \.self) { k in
                    let d = OrigamiState.netPresets[k]
                    Btn(d.name, on: st.net.p4 == d.p4) { st.switchNet(d) }
                }
            }
            HStack(spacing: 6) {
                Btn("🎲 でたらめな展開図") { st.switchNet(OrigamiState.randomNet()) }.help("超立方体の展開図を 1 つ、でたらめに作る（8 個の立方体の、くっつき方の木。平らにして重ならないものだけ）。立方体の展開図も合わせた形に")
                Text("今：" + st.net.name).font(.caption2).foregroundStyle(UIC.sub)
            }
            // 今の展開図が図鑑のどれか（でたらめ・見本の時に。押すと図鑑のその場所を開く）
            if let k = NetAtlas.number(of: st.net.p4), !st.net.name.hasPrefix("No.") {
                let e = NetAtlas.all[k - 1]
                Button { st.atlasOpen = true } label: {
                    HStack(spacing: 8) {
                        NetThumb(flat: e.flat, cols: st.cellColors(4).map { PaletteEditor.color($0) }).frame(width: 54, height: 46)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("「\(st.net.name)」＝ 図鑑の No.\(k)").font(.system(size: 12, weight: .bold)).foregroundStyle(UIC.cyan)
                            Text("いちばん長いつながり：胞 \(e.longest) 個。絵は図鑑の向き（今の展開図を回したり裏返したりした形）").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(6).background(UIC.cyan.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(UIC.cyan.opacity(0.4)))
                }
                .buttonStyle(.plain).help("図鑑のこの展開図の所を開く")
            }
            // 展開図図鑑（261 種類）と、番号の順に 1 つずつ
            HStack(spacing: 6) {
                if st.dim5 { Btn("📚 5 次元の図鑑（9694）", on: true) { st.atlas5Open = true }.help("5 次元超立方体の展開図 9,694 種類を全部並べた図鑑（5 次元 β の右の窓）。押すとその展開図になる") }
                Btn(st.dim5 ? "超立方体の図鑑（261）" : "📚 展開図図鑑（261）") { st.atlasOpen = true }.help("超立方体の展開図 261 種類を全部並べた図鑑。押すとその展開図になる")
                Btn("◀") { st.switchNet(NetAtlas.step(from: st.net.p4, -1)) }.help("図鑑の 1 つ前の展開図")
                Text(NetAtlas.number(of: st.net.p4).map { "No.\($0) / \(NetAtlas.count)" } ?? "—").font(.system(size: 11, weight: .semibold).monospacedDigit()).foregroundStyle(UIC.text)
                Btn("▶") { st.switchNet(NetAtlas.step(from: st.net.p4, 1)) }.help("図鑑の 1 つ次の展開図")
            }
            HStack(spacing: 6) {
                Btn(st.netAnim ? "組み変わりアニメ：入" : "組み変わりアニメ：切", on: st.netAnim) { st.netAnim.toggle() }
                    .help("展開図を切りかえる時に、胞が 1 つずつ 4 次元の方向へ浮いて、新しい場所へ動いて組み変わる（展開図が見えている時だけ。組み上がっている時は形が同じなので動かない）")
            }
            Text("どの展開図も、ちょうつがいごとに 90° ずつ折ると同じ超立方体になる。折る順は真ん中に近い所から少しずつ遅れて。左の立方体の展開図も、超立方体のくっつき方に合わせた形（アナロジー）").font(.caption2).foregroundStyle(UIC.sub)
        }
        Sec("再生", "play.fill") {
            HStack(spacing: 6) {
                Btn("▶ 組み立て", on: st.playing && st.target == 1) { st.playFold() }
                Btn("◀ 展開", on: st.playing && st.target == 0) { st.playUnfold() }
                if st.playing || st.loop { Btn("■ 止める") { st.playing = false; st.loop = false } }
            }
            HStack(spacing: 6) {
                Btn("往復", on: st.loop) { st.toggleLoop() }.help("往復の自動再生")
                Btn(String(format: "速度: %.1fx", st.speed)) { st.nextSpeed() }.help("再生の速さの切りかえ（0.5・1・1.5・2・3・4 倍）。回し続ける速さにもかかる")
            }
            // 折り方：いっしょ／多段階（最大 2〜4 段）／一筆（ころころ）
            HStack(spacing: 6) {
                Text("折り方").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                Btn("いっしょ", on: !st.foldStagger && !st.foldCourse) { st.foldStagger = false; st.foldCourse = false }.help("全部のちょうつがいをいっしょに折る")
                Btn("多段階", on: st.foldStagger && !st.foldCourse) { st.foldStagger = true; st.foldCourse = false; if st.foldMaxStages < 2 { st.foldMaxStages = 4 } }
                    .help("真ん中に近い段から順に折る（つながりが長い展開図ほど段が多い）")
                Btn("🌀 一筆", on: st.foldCourse) { st.foldCourse = true }
                    .help("いちばん長いつながりのはしっこから、ちょうつがいを 1 個ずつ巻いて、ゴールまでころころ転がる。最後に 90° ずつコロンと返っていつもの向きへ")
            }
            let D = OrigamiState.depths(st.net.p4).max() ?? 1
            if st.foldCourse {
                HStack(spacing: 6) {
                    Text("出発").font(.caption2).foregroundStyle(UIC.sub)
                    Btn("はし A から", on: !st.courseFromB) { st.courseFromB = false }
                    Btn("はし B から", on: st.courseFromB) { st.courseFromB = true }
                }
                Text("一筆：ちょうつがい \(st.net.p4.count - 1) 個を、はしから 1 個ずつ巻いてゴールまで転がる → 最後にコロンと返っていつもの向きへ（開く時は逆再生）").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            } else if st.foldStagger {
                HStack(spacing: 6) {
                    Text("最大").font(.caption2).foregroundStyle(UIC.sub)
                    ForEach(2...4, id: \.self) { k in
                        Btn("\(k) 段", on: st.foldMaxStages == k) { st.foldMaxStages = k }
                            .help("最大 \(k) 段に分けて折る（展開図の深さがこれより少なければ、その段数のまま）")
                    }
                }
                Text("この展開図：\(st.foldStages(D)) 段（深さ \(D)）。つながりが長い展開図ほど深い：ダリの十字架は 2、いちばん長い 8 個つながりは 4")
                    .font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            }
            // 組み上げる時・開く時の向き：2 × 2 の表（覚えた形へ ／ まっすぐ）。どちらも切なら、今の向きのまま
            AsmMatrix(st: st)
            NextCLine(st: st)
            LiveRead(live: st.live) { NumRow("開く速さ（組み立ての何倍か）", $st.unfoldK, 1...4, "×%.1f", scale: 1) }
        }
        Sec("向きと記憶", "cube.transparent") { AsmPoseSection(st: st) }
        Sec("分解（どんな形でできているか）", "square.split.2x2") {
            HStack {
                Text("くっついた").font(.caption2).foregroundStyle(UIC.sub)
                LiveRead(live: st.live) {
                    Slider(value: Binding(get: { st.xpAnim != nil ? max(0, min(1, st.explodeE)) : st.explodeRaw }, set: { st.xpAnim = nil; if st.counting { st.endCount() }; st.explodeRaw = $0 }), in: 0...1)
                }
                Text("バラバラ").font(.caption2).foregroundStyle(UIC.sub)
            }
            HStack(spacing: 6) {
                Btn(st.apart ? "→ くっつける" : "→ バラす") { if st.counting { st.endCount() }; st.startXp(st.apart ? 0 : 1) }.help("1 つずつの形に分けて離す／元にくっつける")
                Btn(st.counting ? "→ やめる" : "→ 数える", on: st.counting) { if st.counting { st.endCount() } else { st.startCount() } }.help("バラして、1 個ずつ番号を付けて光らせながら数える")
                Btn("時間差", on: st.xpStagger) { st.xpStagger.toggle() }.help("ボタンでバラす・くっつける時に、番号の順に少しずつずらす")
            }
            LiveRead(live: st.live) { NumRow("離す距離", $st.xpDistK, 0.3...2.5, "×%.1f", scale: 1) }
        }
    }

    // ---- 回転 ----
    @ViewBuilder var rotTab: some View {
        Sec("角度（スライダー・数値・↺・自動回転）", "dial.medium") {
            LiveRead(live: st.live) {
                VStack(alignment: .leading, spacing: 7) {
                    AngleRow("X-W（左 X-Z）", $st.ax, spin: $st.spinX)
                    AngleRow("Y-W（左 Y-Z）", $st.ay, spin: $st.spinY)
                    AngleRow("Z-W", $st.zw, spin: $st.spinZW)
                    Divider().overlay(UIC.line)
                    AngleRow("X-Y", $st.xy, spin: $st.spinXY)
                    AngleRow("X-Z", $st.xz, spin: $st.spinXZ)
                    AngleRow("Y-Z", $st.yz, spin: $st.spinYZ)
                }
            }
        }
        if st.dim5 {
            Sec("5 次元 β：5 次元だけの面", "hexagon") {
                LiveRead(live: st.live) {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("上の X-W・Y-W・Z-W は、5 次元超立方体では X-V・Y-V・Z-V（v＝折りたたみでできた次元）。ここの 4 面は 5 次元超立方体だけが回る（左の超立方体は動かない）。▶ は 4 面いっしょに回す")
                            .font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
                        AngleRow("X-W（5 次元）", $st.xw5, spin: $st.spin5)
                        AngleRow("Y-W（5 次元）", $st.yw5, spin: $st.spin5)
                        AngleRow("Z-W（5 次元）", $st.zw5, spin: $st.spin5)
                        AngleRow("W-V", $st.wv5, spin: $st.spin5)
                        HStack(spacing: 6) {
                            Btn("3D展開") { st.view5(0) }.help("10 面とも 0°＋ななめ・遠近：真ん中が太い「3 次元の十字架」")
                            Btn("4D展開") { st.view5(1) }.help("5 次元だけの X-W 45°・Y-W 35.3°・Z-W 30°＋ななめ・平行：8 方向の腕が全部見える「4 次元の十字架」")
                            Btn("4 面とも 0 へ") { st.zero5() }
                        }
                    }
                }
            }
        }
        Sec("立方体", "cube") {
            Picker("立方体の 3D 回転", selection: $st.left3DAll) { Text("X-Y だけ").tag(false); Text("全部").tag(true) }
            Text(st.left3DAll ? "全部：立方体も X-Y・X-Z・Y-Z で超立方体と同じように転がる" : "X-Y だけ：立方体は自分の平面（X-Y）の回転だけついてくる（低い次元から見た視界）")
                .font(.caption2).foregroundStyle(UIC.sub)
        }
        Sec("回転アニメ（入力した角度まで再生）", "play.circle") {
            HStack(spacing: 6) {
                ForEach([("X-W", $st.animXW), ("Y-W", $st.animYW), ("Z-W", $st.animZW)], id: \.0) { name, b in
                    VStack(alignment: .leading, spacing: 1) { Text(name).font(.caption2).foregroundStyle(UIC.sub); TextField("現状", text: b).textFieldStyle(.roundedBorder).frame(width: 64) }
                }
                Spacer()
                Btn("▶ 再生") { st.playRotAnim() }.help("今の回転から、入力した角度まで滑らかに移る（空欄は今のまま）")
            }
        }
        Sec("角度のプリセット", "bookmark") {
            HStack(spacing: 6) {
                TextField("名前（なくても可）", text: $st.presetName).textFieldStyle(.roundedBorder)
                Btn("今の角度を保存") { st.savePreset() }.help("今の X-W・Y-W・Z-W と 3D の回転（X-Y・X-Z・Y-Z）を保存（このアプリに覚える）")
            }
            if st.presets.isEmpty { Text("まだありません").font(.caption2).foregroundStyle(UIC.sub) }
            ForEach(st.presets.indices, id: \.self) { i in
                let p = st.presets[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Btn("▶ " + p.name) { st.animToAngles(p.deg) }.help("この角度へなめらかに移る")
                        Text(OrigamiState.degText(p.deg)).font(.caption2.monospacedDigit()).foregroundStyle(UIC.sub).lineLimit(1)
                        Spacer()
                        PresetTools(locked: p.locked, editing: st.editPreset == p.id,
                                    edit: { st.editPreset = st.editPreset == p.id ? nil : p.id }, lock: { st.toggleLockPreset(i) },
                                    up: { st.movePreset(i, -1) }, down: { st.movePreset(i, 1) }, del: { st.deletePreset(p) })
                    }
                    if st.editPreset == p.id {
                        // 編集：名前・6 つの角度（数字で）・今の角度で上書き
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("名前", text: Binding(get: { st.presets.indices.contains(i) ? st.presets[i].name : "" }, set: { if st.presets.indices.contains(i) { st.presets[i].name = $0; st.savePresets() } }))
                                .textFieldStyle(.roundedBorder)
                            DegGrid(deg: Binding(get: { st.presets.indices.contains(i) ? st.presets[i].deg : [0, 0, 0, 0, 0, 0] }, set: { if st.presets.indices.contains(i) { st.presets[i].deg = $0; st.savePresets() } }))
                            HStack(spacing: 6) {
                                Btn("今の角度で上書き") { st.overwritePreset(i) }.help("今の 6 つの角度を、このプリセットに入れる")
                                Btn("完了") { st.editPreset = nil }
                            }
                        }
                        .padding(8).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        Sec("角度の往復（A〜D）", "arrow.left.arrow.right") {
            ForEach(st.ppStops.indices, id: \.self) { i in
                HStack(spacing: 6) {
                    Text(OrigamiState.ppNames[i]).font(.system(size: 12, weight: .bold)).foregroundStyle(UIC.amber).frame(width: 14)
                    Text(OrigamiState.degText(st.ppStops[i])).font(.caption2.monospacedDigit()).foregroundStyle(UIC.text).lineLimit(1)
                    Spacer()
                    Btn("今の角度") { st.ppSetStop(i) }.help("今の角度を \(OrigamiState.ppNames[i]) に入れる")
                    if st.ppStops.count > 2 { Button { st.ppRemoveStop(i) } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).foregroundStyle(UIC.sub) }
                }
            }
            HStack(spacing: 6) {
                Btn("＋ 停留点") { st.ppAddStop() }.help("今の角度を、次の停留点として足す")
                Btn("並びを逆に") { st.ppReverse() }
                Btn("4 つの見方") { st.ppFillViews() }.help("A〜D に 胞から・面から・辺から・頂点から を入れる")
            }
            LiveRead(live: st.live) { NumRow("1 区間", $st.ppSec, 0.5...12, "%.1f 秒", scale: 1) }
            HStack(spacing: 6) {
                Btn(st.ppCycle ? "ぐるっと" : "往復", on: st.ppCycle) { st.ppCycle.toggle() }.help("動く順番：往復（A→B→C→D→C→B→A…）か、ぐるっと（A→B→C→D→A…）")
                Picker("動き方", selection: $st.ppEase) { ForEach(OrigamiState.ppEases, id: \.0) { Text($0.1).tag($0.0) } }.frame(width: 150)
            }
            if st.ppEase == "spring" { LiveRead(live: st.live) { NumRow("弾み", $st.ppSpring, 0...1, "%.2f", scale: 1) } }
            if st.ppEase == "turn" { LiveRead(live: st.live) { NumRow("ターンのきびきび", $st.ppTurn, 0...1, "%.2f", scale: 1) } }
            if st.ppEase == "sine" { LiveRead(live: st.live) { NumRow("単振動の緩やかさ", $st.ppSine, 0...1, "%.2f", scale: 1) } }
            HStack(spacing: 6) {
                Btn(st.ppOnceFwd ? "▶ A→B" : "▶ B→A", on: st.ppRunning && (st.pp?.once ?? false)) { st.ppOnce() }.help("片道を 1 回だけ（押すたびに A→B と B→A が交互）")
                Btn(st.ppRunning && !(st.pp?.once ?? true) ? "■ ストップ" : (st.ppCycle ? "▶ ぐるっとスタート" : "▶ 往復スタート"), on: st.ppRunning && !(st.pp?.once ?? true)) { st.ppToggle() }
            }
        }
        Sec("往復のプリセット", "bookmark.fill") {
            HStack(spacing: 6) {
                TextField("名前（なくても可）", text: $st.ppPresetName).textFieldStyle(.roundedBorder)
                Btn("今の往復を保存") { st.savePPPreset() }.help("今の停留点（A・B…）・1 区間の秒数・往復／ぐるっと・動き方を保存（このアプリに覚える）")
            }
            if st.ppPresets.isEmpty { Text("まだありません").font(.caption2).foregroundStyle(UIC.sub) }
            ForEach(st.ppPresets.indices, id: \.self) { i in
                let p = st.ppPresets[i]
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Btn("▶ " + p.name, on: st.ppRunning && st.ppStops == p.stops) { st.loadPPPreset(p, start: true) }.help("この往復を始める")
                        Text(p.summary).font(.caption2).foregroundStyle(UIC.sub).lineLimit(1)
                        Spacer()
                        PresetTools(locked: p.locked, editing: st.editPP == p.id,
                                    edit: { st.editPP = st.editPP == p.id ? nil : p.id }, lock: { st.toggleLockPP(i) },
                                    up: { st.movePP(i, -1) }, down: { st.movePP(i, 1) }, del: { st.deletePPPreset(p) })
                    }
                    if st.editPP == p.id {
                        // 編集：名前・停留点（数字で・今の角度を入れる・消す・足す）・秒数・往復／ぐるっと・動き方・今の往復で上書き
                        PPPresetEditor(st: st, i: i)
                            .padding(8).background(Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
        }
        Sec("サイコロ（超立方体サイコロ）", "dice") { DiceSection(st: st) }
        Sec("内接球（超球面）", "circle.circle") {
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Btn("内接球を出す", on: st.inSphere) { st.inSphere.toggle() }.help("超立方体にぴったり内接する超球面（8 個の胞の真ん中に接する）。回転バーの「内接球」と同じ")
                    Btn("接点", on: st.inSphereTouch) { st.inSphereTouch.toggle() }.help("超球が胞（立方体の窓は面）に接する点を、光の輪で。超球が触れるのは胞の真ん中の 1 点だけ。色は胞が垂直に立つ軸：x 赤・y 緑・z 青・w 紫（点のタブの「胞の中心 8 個」と同じ。その点を置くと輪の真ん中におさまる）")
                    Btn("めりこみ", on: st.inSphereDent) { st.inSphereDent.toggle() }.help("写した絵では、超球が奥の胞（立方体）にめりこんで見える（4 次元では真ん中の 1 点で触れているだけ）。そのめりこんで見える所を少し暗く")
                    Btn("くっきり", on: st.inSphereDentSharp) { st.inSphereDentSharp.toggle() }.disabled(!st.inSphereDent).help("めりこみの境目をくっきり：奥の胞（立方体）の平らな壁のところで、パキッと明るさを分ける。壁は平らなので、横から見ると境目はまっすぐ。切るとふんわりしたグラデーション")
                    Btn("油膜", on: st.inSphereFilm) { st.inSphereFilm.toggle() }.help("緯度の殻を油の膜（シャボン玉）のように：色（胞の色）はそのまま少し暗い透けた玉で、うしろの立方体が見える。ふちほど、膜の厚みのむらと見る角度で虹色がゆらぐ。トーンは下の「油膜のトーン」で")
                    Btn("ガラス（反射）", on: st.inSphereGlass) { st.inSphereGlass.toggle() }.help("超立方体と同じようなシースルーのガラスに：まんなかはすけて、ふちほど光を反射して明るく、表に光のつや。切ると前の見え方（ふちほど暗い）")
                }
                InSphereModeRow(st: st)
                LiveRead(live: st.live) { NumRow("油膜のトーン", $st.inSphereTone, 0.3...1, "%.0f%%", scale: 100) }.disabled(!st.inSphereFilm)
                    .help("油膜の殻の色の強さ。下げると落ち着いた色で、うしろの立方体がよく透ける")
                LiveRead(live: st.live) { NumRow("遠近（手前を明るく太く）", $st.inSphereDepth, 0...1, "%.0f%%", scale: 100) }
                    .help("内接球の手前の膜と線は明るく・線は太く、奥はうすく・細く（球の手前の面と奥の面が見分けられる）。0 で今まで通り")
                LiveRead(live: st.live) { NumRow("ワイヤーの太さ", $st.inSphereWireW, 0.5...4, "%.2f 倍", scale: 1) }
                    .help("内接球の線（緯度の輪・網目・正 120 胞体・5 次元の正軸体・ホップの輪）の太さ。見え方タブの「線の太さ」とは別に決められる。正 120 胞体・正軸体は、これのさらに 1.6 倍")
                HStack(spacing: 6) {
                    Text("色").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                    Btn("アプリの色", on: st.inSphereColor == 0) { st.inSphereColor = 0 }.help("超立方体の胞の色に合わせる：球の上の点ごとに、いちばん近い胞（接している胞）の色。パレットを変えると一緒に変わる")
                    Btn("レインボー", on: st.inSphereColor == 1) { st.inSphereColor = 1 }.help("超球面アプリと同じ層ごとの色（北 紫 → 水色、南 赤 → 緑）")
                }
                HStack(spacing: 6) {
                    Text("接点の色").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                    Btn("軸の色", on: st.inSphereTouchCol == 0) { st.inSphereTouchCol = 0 }.help("胞が垂直に立つ軸の色：x 赤・y 緑・z 青・w 紫（＋と−は同じ色）。点のタブの「胞の中心 8 個」と同じ")
                    Btn("胞の色", on: st.inSphereTouchCol == 1) { st.inSphereTouchCol = 1 }.help("接している胞の色（パレットの色）。＋と−で別の色にできるので、たとえば −w を黄色にしておくと、手前の胞と奥の胞の接点が見分けられる")
                }.disabled(!st.inSphereTouch)
                HStack(spacing: 6) {
                    Text("層").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                    ForEach([6, 10, 14], id: \.self) { k in
                        Btn("\(2 * k - 1) 枚", on: st.inSphereLayers == k) { st.inSphereLayers = k }.help("w ＝ 一定で切った球殻の枚数（北と南と赤道）")
                    }
                }
                InSphereSpinRows(st: st)
                Text("アプリの色では、球が胞に接する所がその胞の色になり、胞と胞のあいだは色がまざる。4D で回すと、どの胞に近いかが入れかわって色が流れる").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            }
        }
        Sec("軸の操作", "move.3d") { Later() }
        Sec("説明（立方体と超立方体の対応）", "info.circle") {
            Text("同じ角度を立方体と超立方体に同時にかけています。立方体はただ回るだけ。超立方体は内側の胞と外側の胞が入れかわり、裏返るように見えます。操作は同じで、1 次元ちがうだけです。")
            Text("立方体の窓のドラッグ＝X-W・Y-W（立方体は X-Z・Y-Z）。超立方体の窓のドラッグ＝つかんだ形を画面の縦横の軸のまわりに回す（回した向きは X-Y・X-Z・Y-Z の数字に出ます）。⇧＋横ドラッグ＝Z-W。")
            Text("Z-W は立方体が追いつけない回転です。立方体の回転面は 3 枚（XY・XZ・YZ）、超立方体は 6 枚（XY・XZ・YZ・XW・YW・ZW）。Z-W は超立方体にしか無いので、立方体は止まったまま。これが次元の差です。")
        }
    }

    // ---- 見え方 ----
    @ViewBuilder var viewTab: some View {
        Sec("どこから見る", "scope") {
            HStack(spacing: 6) {
                ForEach(OrigamiState.views.indices, id: \.self) { k in
                    Btn(OrigamiState.views[k].name, on: st.viewSel == k) { st.goView(k, animated: false) }.help(OrigamiState.views[k].note)
                }
            }
            Picker("投影", selection: $st.viewProj) { Text("おまかせ").tag(0); Text("遠近").tag(1); Text("平行").tag(2) }.pickerStyle(.segmented)
                .help("見方を選んだ時の投影。おまかせ＝胞からは遠近、面・辺・頂点からは平行（ウェブ版と同じ）。遠近＝ふだん目で見る見え方（遠い所ほど小さい）。平行＝遠さで大きさが変わらず、形がそろってきれい。周回にも使う")
            if st.viewSel >= 0 { Text(OrigamiState.views[st.viewSel].note).font(.caption2).foregroundStyle(UIC.amber) }
            HStack(spacing: 6) {
                Btn(st.cycling ? "■ 周回をやめる" : "▶ 周回", on: st.cycling) { st.toggleCycle() }.help("胞 → 面 → 辺 → 頂点 を自動でなめらかに周回する")
                Text("一周").font(.caption2).foregroundStyle(UIC.sub)
                LiveRead(live: st.live) { Slider(value: $st.cyclePeriod, in: 2...60) }
                LiveRead(live: st.live) { NumField($st.cyclePeriod, 2...60, "%.0f 秒") }
            }
            Text("角度を 1 つずつ足していくだけで順に移れる（足した角度の数＝視線が使う軸の数）").font(.caption2).foregroundStyle(UIC.sub)
        }
        Sec("4 次元の立体を見る（3 つの窓）", "square.stack.3d.up") { ShapePanel(st: st) }
        Sec("断面（3 次元の包丁で切る）", "scissors") { SectionPanel(st: st) }
        Sec("プリセットへ移行（アニメ）", "wand.and.stars") {
            HStack(spacing: 6) {
                ForEach(OrigamiState.views.indices, id: \.self) { k in
                    Btn(OrigamiState.views[k].name) { st.goView(k, animated: true) }.help(OrigamiState.views[k].name + " へなめらかに移る（3D の回転は 0 へ）")
                }
            }
        }
        Sec("垂直軸", "arrow.up.and.down") { Later() }
        Sec("視覚効果", "sparkles") {
            Text("ここはネイティブ版だけのもの（ウェブ版を移したあとで飾る用）").font(.caption2).foregroundStyle(UIC.sub)
            Picker("質感", selection: $st.look) { ForEach(Glass.looks.indices, id: \.self) { Text(Glass.looks[$0].name).tag($0) } }
            Toggle("照り返しライト", isOn: $st.shine)
            LiveRead(live: st.live) { NumRow("強さ", $st.shineK, 0...4, "%.1f", scale: 1) }
            LiveRead(live: st.live) { NumRow("広さ", $st.shineSpread, -1...1, "%+.1f", scale: 1) }
            LiveRead(live: st.live) { NumRow("左右", $st.shineAz, -180...180, "%+.0f°", scale: 1) }
            LiveRead(live: st.live) { NumRow("上下", $st.shineEl, -85...85, "%+.0f°", scale: 1) }
            LiveRead(live: st.live) { NumRow("グレア", $st.glare, 0...1, "%.2f", scale: 1) }
            LiveRead(live: st.live) { NumRow("鮮やかさ", $st.vivid, 0...1, "%.2f", scale: 1) }
            LiveRead(live: st.live) { NumRow("映り込み", $st.envK, 0...1.5, "%.2f", scale: 1) }
            LiveRead(live: st.live) { NumRow("奥の濃さ", $st.deep, 0...1, "%.2f", scale: 1) }
            LiveRead(live: st.live) { NumRow("内側の濃さ", $st.inner, 0...1, "%.2f", scale: 1) }
            Divider().overlay(UIC.line)
            Picker("宇宙", selection: $st.spaceMode) { Text("組み立てに合わせる").tag(0); Text("入").tag(1); Text("切").tag(2) }
            LiveRead(live: st.live) { NumRow("星の数", $st.starsPct, 5...100, "%.0f%%", scale: 1) }.disabled(st.spaceMode == 2)
            Toggle("面の網目", isOn: $st.meshOn).disabled(st.spaceMode == 2)
            LiveRead(live: st.live) { NumRow("網目", $st.gridN, 2...16, "%.0f 升", scale: 1) }.disabled(st.spaceMode == 2 || !st.meshOn)
            Toggle("背景も宇宙", isOn: $st.bgSpace).disabled(st.spaceMode == 2)
        }
        Sec("表示", "display") {
            Toggle("座標軸（X・Y・Z・W）", isOn: $st.showAxes)
            Picker("見せる胞", selection: $st.faceSide) { Text("全部").tag(0); Text("表だけ").tag(1); Text("裏だけ").tag(2) }.pickerStyle(.segmented)
                .help("表だけ＝4 次元目（w）の向こうの目から見て、表を向いている立方体だけ（多くて 4 個。立方体の窓では、カメラから見て表の正方形＝多くて 3 面）。裏だけ＝その反対。遠近のときは見える数が減ります（正面からだと蓋の 1 個だけ）")
            LiveRead(live: st.live) { NumRow("4D の遠近", $st.camW, 2.5...9, "%.1f", scale: 1) }
            LiveRead(live: st.live) { NumRow("3D の奥を暗く", $st.depth3, 0...1, "%.0f%%", scale: 100) }
                .help("カメラから遠い所ほど面を暗く（手前 1.25 倍 → 奥 0.6 倍）＝立体感。ウェブ版と同じ。展開図では奥をさらに暗く")
            LiveRead(live: st.live) { NumRow("3D の奥を色濃く", $st.depthDeep, 0...1, "%.0f%%", scale: 100) }
                .help("カメラから遠い所ほど、暗くするだけでなく自分の色を掛けて色を深く（3D の投影図らしく、奥へ沈む）。0 で今まで通り")
            LiveRead(live: st.live) { NumRow("斜めの面の照り返し", $st.slantSheen, 0...1, "%.0f%%", scale: 100) }
                .help("目から見て斜めに立つ面（4D の遠近で台形になった胞の横の面など）ほど、光の来る向きでふんわり光る。さらさらの質感のまま、面の傾きが見えて立体に。正面を向いた面には出ない。0 で今まで通り")
            LiveRead(live: st.live) { NumRow("線の太さ（展開図）", $st.lineWidthNet, 0.5...3, "%.2f 倍", scale: 1) }
                .help("展開図の時の線（辺・軸）の太さの倍率。組み立てる間に、下の「組み上がり」の太さへなめらかに変わる。内接球のワイヤーは内接球の欄で別に")
            LiveRead(live: st.live) { NumRow("線の太さ（組み上がり）", $st.lineWidthSolid, 0.5...3, "%.2f 倍", scale: 1) }
                .help("組み上がった時の線の太さの倍率。線を胞の色・画面の色でなじませる時に、太めにすると色がよく見える")
            Picker("線の 4D の奥行き（濃さ）", selection: $st.line4) { Text("同じ").tag(0); Text("奥ほどうすく").tag(1); Text("奥ほど濃く").tag(2) }
                .help("超立方体の線の濃さを、4 次元の奥行きで変える。奥ほどうすく＝手前の線がはっきり、奥は背景に沈む（ウェブ版の濃淡）。奥ほど濃く＝4 次元の奥に何かあるのが線で浮かぶ。太さは下の「太さ」で別に。1 本の辺の中でもなめらかに変わる")
            LiveRead(live: st.live) { NumRow("線の 4D の奥行き（濃さ）の強さ", $st.line4K, 0...1, "%.0f%%", scale: 100) }.disabled(st.line4 == 0)
            LiveRead(live: st.live) { NumRow("線の 3D の奥行き（太さ）", $st.line3W, -1...1, "%+.0f%%", scale: 100) }
                .help("線の太さを、画面の奥行き（カメラからの遠さ）で変える。−：奥ほど細く（手前の線が最大 2 倍）・＋：奥ほど太く・0：同じ。面の「3D の奥を暗く」と同じ物差し。1 本の線の中でもなめらかに変わる")
            LiveRead(live: st.live) { NumRow("線の 3D の奥行き（濃さ）", $st.line3K, 0...1, "%.0f%%", scale: 100) }
                .help("画面の奥の線ほどうすく（100% で奥の線は 4 分の 1 の濃さ）。手前の線ははっきりのまま。0 で今まで通り")
            LiveRead(live: st.live) { NumRow("線の 4D の奥行き（太さ）", $st.line4W, -1...1, "%+.0f%%", scale: 100) }
                .help("超立方体の線の太さを、4 次元の奥行きで変える。−：奥ほど細く（手前の線が最大 2 倍）・＋：奥ほど太く（奥の線が最大 2 倍）・0：同じ太さ。濃さとは別に決められる")
            LiveRead(live: st.live) { NumRow("色温度（青み ↔ 暖かみ）", $st.warmth, -1...1, "%+.0f%%", scale: 100) }
                .help("画面全体の色を、明るさを変えずに青み（−）↔ 暖かみ（＋）へずらす。写真の色温度と同じ。全体が青みがかって目がつかれる時は ＋ へ")
            LiveRead(live: st.live) { NumRow("ファンタジーの強さ", $st.fantasy, 0...1, "%.0f%%", scale: 100) }
                .help("組み上がった時の特別な効果（4D の手前を光らせる・奥の乗算・色ガラス・つぶれ／斜めの乗算・形どうしの映り込み・光の帯）をまとめて強く・弱く。0 で、展開図のふつうの見え方のまま組み上がる（濃さだけウェブ版のようにうすくなる）")
            LiveRead(live: st.live) { NumRow("展開図の色で乗算", $st.netMul, 0...1, "%.0f%%", scale: 100) }
                .help("組み上がるにつれて、面が展開図の時の自分の色のまま、色つきセロハンのように重なる（乗算）。色が急に変わらない")
            LiveRead(live: st.live) { NumRow("展開図はふつうの立体（すけない）", $st.netSolid, 0...1, "%.0f%%", scale: 100) }
                .help("超立方体の展開図は 3 次元のふつうの物：すけない十字架の立体に見せる。折りはじめると、組み上がるにつれてガラス（ファンタジー）へ。0 で展開図もガラス")
            LiveRead(live: st.live) { NumRow("線を立体になじませる（賢く）", $st.smartLine, 0...1, "%.0f%%", scale: 100) }
                .help("線の色を、その辺を持つ胞の色を混ぜた「角」の色に（光の来る側ほど明るく）。形の外の輪郭ははっきり、立体の中を通る線はうすく。0 で今までの線")
            LiveRead(live: st.live) { NumRow("線を胞の色でなじませる", $st.lineTint, 0...1, "%.0f%%", scale: 100) }
                .help("線をその胞の色に寄せて、乗算で重ねる（ウェブ版の線色「面と同系色（乗算）」）。白い線が浮かず、ガラスのふちの厚みが濃く見えるような線に。0 で今までの白っぽい線")
            Picker("なじませる色", selection: $st.lineTintMode) { Text("その胞の色").tag(0); Text("重なりの乗算色").tag(1); Text("画面の色を濃く").tag(2) }.pickerStyle(.segmented)
                .help("画面の色を濃く：線の下に見えている立体の色（赤と紫が重なって見えていれば、その重なった色）をそのまま暗くして線に。どんな重なりでも立体と同じ色合いの濃い線になる。なじませる強さで、ふつうの線とまぜる。重なりの乗算色：組み上がって 2〜3 個の胞が重なる辺を、その胞の色を掛け合わせた色（色つきセロハンを重ねた時の色）に。明るさはそろえて、色合いだけ。「賢く」の線の色も同じ色に")
            LiveRead(live: st.live) { NumRow("つぶれた胞ほど乗算（4D）", $st.squash4, 0...1, "%.0f%%", scale: 100) }
                .help("4 次元で回して、胞が薄い板のようにつぶれて写っているほど、色を深く掛ける（同じガラスがせまく押しこまれて密度が高い）。W に回すと、つぶれた胞が濃く、ふくらんだ胞が透ける")
            LiveRead(live: st.live) { NumRow("斜めの面ほど乗算（3D）", $st.slant3, 0...1, "%.0f%%", scale: 100) }
                .help("斜めから見て細くつぶれて見える面ほど、ガラスを通る道が長いので色を深く掛ける")
            LiveRead(live: st.live) { NumRow("外の胞は色ガラス（角度で濃く）", $st.glass4, 0...1, "%.0f%%", scale: 100) }
                .help("4 次元で手前の、外から包む胞を本物の色ガラスに：正面はうすい色で中の胞の色がそのまま見え、斜めの面・ふちほど自分の色で濃く染まる（ガラスを通る道が長いほど色を吸う）。展開図では効かず、組み上がるほど効く")
            LiveRead(live: st.live) { NumRow("4D の手前を光らせる", $st.glow4, 0...1, "%.0f%%", scale: 100) }
                .help("4 次元の奥行きを頂点ごとに：手前ほど光を足して光る。W に回すと光る所が流れる。展開図では効かず、組み上がるほど効く")
            LiveRead(live: st.live) { NumRow("スタジオの光の帯（つや）", $st.stripK, 0...1.5, "%.0f%%", scale: 100) }
                .help("カメラのうしろ・少し左上に、ななめの細長いライトが 2 本あることに。正面を向いたガラスに、光の帯としてつやっと映る（商品写真のアクリルのよう）。ライトはカメラについてくる")
            LiveRead(live: st.live) { NumRow("形どうしの映り込み（ツルピカ）", $st.reflSelf, 0...1.5, "%.0f%%", scale: 100) }
                .help("面がつやのあるガラスのように、まわりの胞や中の立方体を映す（ふちほど強く映る）。形の真ん中から 6 方向を撮った絵を、面が鏡の向きで読む")
            LiveRead(live: st.live) { NumRow("4D の奥を乗算", $st.mul4, 0...1, "%.0f%%", scale: 100) }
                .help("4 次元の奥にある胞ほど、色つきのセロハンのように後ろの色に掛け合わせる。胞ごとに同じ濃さ（いちばん奥の胞 100%・横の歪んだ胞 6 割くらい・手前 0）。いちばん奥の胞は色を濃くして、手前のガラスの上からも深く沈む。展開図では効かず、組み上がるほど効く")
            LiveRead(live: st.live) { NumRow("やわらかい乗算（目にやさしく）", $st.softMul, 0...1, "%.0f%%", scale: 100) }
                .help("乗算で掛ける色を、少し灰色と白へ寄せてから掛ける。色は分かるまま、重なっても暗く沈みにくい（明るい所との差が小さくなって、目がつかれにくい）。0 で今までの乗算")
            Picker("投影", selection: $st.perspMode) { Text("遠近投影").tag(true); Text("平行投影").tag(false) }
            Picker("表示", selection: $st.displayMode) { Text("両方").tag(0); Text("超立方体（右上に立方体のミニ）").tag(1); Text("超立方体だけ").tag(2); Text("立方体だけ").tag(3) }
            Toggle("左右を入れかえる（超立方体を左に）", isOn: $st.swapViews).disabled(st.displayMode != 0)
            Toggle("移動パッド（窓の左の丸）を出す", isOn: $st.panPad)
                .help("丸をドラッグすると図形を動かせる（Mac は ⌘ か Ctrl を押しながら図形をドラッグしても同じ）。丸をダブルクリックで真ん中へ戻す")
            Picker("描き方", selection: $st.wireOnly) { Text("メッシュ").tag(false); Text("ワイヤー").tag(true) }
            Toggle("自動ズーム（組み上げ・展開・分解で大きさを合わせる）", isOn: $st.autoZoom)
                .help("切ると、今の大きさのまま折りたたむ・バラす")
            if st.autoZoom {
                LiveRead(live: st.live) { NumRow("大きさ：展開図", $st.zfNet, 0.5...1, "%.0f%%", scale: 100) }
                LiveRead(live: st.live) { NumRow("大きさ：組み上がり", $st.zfAsm, 0.25...0.85, "%.0f%%", scale: 100) }
                LiveRead(live: st.live) { NumRow("大きさ：分解", $st.zfXp, 0.5...1, "%.0f%%", scale: 100) }
                Btn("大きさを既定に") { st.zfNet = 0.85; st.zfAsm = 0.5; st.zfXp = 0.86 }
            }
            Picker("描く道具", selection: $st.raster) { Text("三角形（なめらか・軽い）").tag(true); Text("光の道（宇宙・網目つき）").tag(false) }
                .help("三角形＝超立方体向け。4 倍のぼかしで、ふちも線もなめらか。光の道＝画素ごとに光を飛ばす描き方（宇宙の背景・面の網目が使える。重いので 75% がおすすめ）")
            Picker("描く細かさ", selection: $st.renderScale) { Text("自動（なめらか優先）").tag(0.0); Text("100%（くっきり）").tag(1.0); Text("85%").tag(0.85); Text("75%（軽く）").tag(0.75) }
                .help("画面の細かさの何割で描くか。下げると描く仕事が減って、1 秒 144 コマに届きやすくなる（少しやわらかい絵に）")
        }
        Sec("胞の色（パレット）", "paintpalette") { PaletteEditor(st: st) }
        Sec("同期（Google でログイン）", "arrow.triangle.2.circlepath") { CloudSection() }
        Sec("お遊び", "gamecontroller") { Later() }
        Sec("24面サイコロ（お遊び）", "die.face.5") { Later() }
    }

    // ---- 点 ----
    @ViewBuilder var ptsTab: some View {
        Sec("辺を色で強調（手前・奥・好きな胞）", "highlighter") {
            Toggle("強調する", isOn: $st.ehOn)
            Text("手前＝折りたたみでできた次元の＋側の胞（ふた）、奥＝−側の胞（真ん中）。超立方体なら w の＋と −、立方体なら z の＋と −。下の表で、ほかの胞にも好きな色をつけられます").font(.caption2).foregroundStyle(UIC.sub)
            HStack {
                Toggle("", isOn: $st.ehNearOn).labelsHidden().help("手前（ふた）の胞の辺を強調する")
                ColorPicker("手前", selection: colorBinding($st.ehNear)).disabled(!st.ehNearOn)
                Spacer(minLength: 8)
                Toggle("", isOn: $st.ehFarOn).labelsHidden().help("奥（真ん中）の胞の辺を強調する")
                ColorPicker("奥", selection: colorBinding($st.ehFar)).disabled(!st.ehFarOn)
            }.disabled(!st.ehOn)
            LiveRead(live: st.live) { NumRow("手前の太さ", $st.ehWidthNear, 1...16, "%.1f 画素", scale: 1) }.disabled(!st.ehOn)
            LiveRead(live: st.live) { NumRow("奥の太さ", $st.ehWidthFar, 1...16, "%.1f 画素", scale: 1) }.disabled(!st.ehOn)
            EdgeHiCells(st: st).disabled(!st.ehOn)
            LiveRead(live: st.live) { NumRow("ほかの胞の太さ", $st.ehWidthOther, 1...16, "%.1f 画素", scale: 1) }.disabled(!st.ehOn)
            Btn("既定に戻す") { st.ehNear = SIMD3(1.0, 0.267, 0.867); st.ehFar = SIMD3(0.2, 0.898, 1.0); st.ehWidthNear = 3; st.ehWidthFar = 3; st.ehWidthOther = 3; st.ehNearOn = true; st.ehFarOn = true; st.ehCells = [:] }
        }
        Sec("手前と奥の目印（頂点の玉）", "circle.circle") {
            Text("手前＝(1, 1, 1, 1)、奥＝(−1, −1, −1, −1) の頂点の玉。立方体の窓の手前・奥も同じ色と大きさ").font(.caption2).foregroundStyle(UIC.sub)
            HStack {
                ColorPicker("手前", selection: colorBinding($st.markNear))
                Btn(st.markShowNear ? "隠す" : "表示") { st.markShowNear.toggle() }
                Spacer(minLength: 8)
                ColorPicker("奥", selection: colorBinding($st.markFar))
                Btn(st.markShowFar ? "隠す" : "表示") { st.markShowFar.toggle() }
            }
            LiveRead(live: st.live) { NumRow("大きさ", $st.markSize, 0.3...1.6, "×%.2f", scale: 1) }
            Toggle("重なった所は色を掛け合わせる（乗算）", isOn: $st.markGlue)
                .help("手前と奥の玉が画面で重なった所だけ、色を掛け合わせて描く。切ると手前の玉が上に重なるだけ（片方を隠している時は掛け合わせない）")
            Toggle("同じ大きさに見せる（遠近で大きさを変えない）", isOn: $st.markSame)
                .help("手前の玉も奥の玉も、画面の上で同じ大きさに。ぴったり重なると、皆既日食のように 1 つの玉になる")
            Toggle("重なりそうになったら、ぴたっと吸いつく（磁石）", isOn: $st.markMagnet)
                .help("手前と奥の玉は、4D でどう回しても、写すと真ん中を通る 1 本の直線の上にある。手を離した時にその直線をのぞく向きから 2.5° 以内なら、3D の向きだけを少し回して、ちょうど重なる向きへ吸いつく（4D のかたむきは変えない）")
            Toggle("ぴったり重なった瞬間に光る", isOn: $st.markFlash)
                .help("手前と奥の玉がちょうど重なった瞬間に、光の輪が広がる")
            Btn("既定に戻す（ピンク・水色・×0.65）") { st.markNear = OrigamiState.markNearDef; st.markFar = OrigamiState.markFarDef; st.markSize = 0.65; st.markShowNear = true; st.markShowFar = true; st.markGlue = true; st.markSame = true; st.markMagnet = true; st.markFlash = true }
        }
        Sec("座標を指定して点を置く", "mappin.and.ellipse") { PointAdder(st: st) }
        Sec("頂点のプリセット（16個）", "circle.grid.3x3") { VertexGrid(st: st) }
        Sec("注目点のプリセット", "star") { FocusPresets(st: st) }
        Sec("置いた点", "list.bullet") { PointList(st: st) }
    }
}

// MARK: - パネルの部品
/// 区切り（ウェブ版の sb-sec：見出しと中身）
struct Sec<C: View>: View {
    let title: String, icon: String, content: C
    init(_ title: String, _ icon: String, @ViewBuilder _ content: () -> C) { self.title = title; self.icon = icon; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label(title, systemImage: icon).font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sky)
            content.font(.system(size: 11)).foregroundStyle(UIC.text).fixedSize(horizontal: false, vertical: true)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(UIC.card, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).stroke(UIC.line.opacity(0.7)))
    }
}
/// まだ移していない区切りの中身
struct Later: View {
    var body: some View { Text("これから移します（ウェブ版と同じに）").font(.caption2).foregroundStyle(UIC.sub) }
}
/// ボタン（入っている時は水色）
struct Btn: View {
    let t: String, on: Bool, act: () -> Void
    init(_ t: String, on: Bool = false, _ act: @escaping () -> Void) { self.t = t; self.on = on; self.act = act }
    var body: some View {
        Button(action: act) {
            Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(on ? UIC.cyan : UIC.text)
                .padding(.horizontal, 9).padding(.vertical, 5)
                .background(on ? UIC.cyan.opacity(0.16) : Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? UIC.cyan.opacity(0.7) : UIC.line))
        }.buttonStyle(.plain).focusable(false)                          // Tab は数字の欄だけを順に移る（ボタンには止まらない）
    }
}
/// 名前・値・つまみの 1 行
struct Row<C: View>: View {
    let name: String, value: String, content: C
    init(_ name: String, _ value: String, @ViewBuilder _ content: () -> C) { self.name = name; self.value = value; self.content = content() }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack { Text(name); Spacer(); Text(value).monospacedDigit().foregroundStyle(UIC.sub) }.font(.system(size: 11))
            content
        }
    }
}
/// 数字を打ちこめる欄：ふだんは今の値（単位つき）を出し、クリックして数字を打って Enter（か、ほかをクリック）で入る。
///   単位（% ° 秒 × 画素 升）はあってもなくてもよい。範囲の外は端にそろえる。scale：見せる数字＝値×scale（% の時は 100）
struct NumField: View {
    @Binding var v: Double
    let range: ClosedRange<Double>, fmt: String, scale: Double
    @State private var text = ""
    @FocusState private var focused: Bool
    init(_ v: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String, scale: Double = 1) { _v = v; self.range = range; self.fmt = fmt; self.scale = scale }
    var shown: String { String(format: fmt, v * scale) }
    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain).multilineTextAlignment(.trailing)
            .font(.system(size: 11).monospacedDigit()).foregroundStyle(focused ? UIC.text : UIC.sub)
            .frame(width: 62)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 4).fill(focused ? Color.white.opacity(0.10) : Color.white.opacity(0.03)))
            .focused($focused)
            .onAppear { text = shown }
            .onChange(of: v) { _, _ in if !focused { text = shown } }
            .onChange(of: focused) { _, f in if f { text = Self.number(shown) } else { commit() } }
            .onSubmit { commit(); focused = false }
            .help("クリックして数字を打てる（Enter で決定）")
    }
    /// 単位をはずした数字だけ（打ちやすいように）
    static func number(_ s: String) -> String { String(s.filter { "0123456789.-+".contains($0) }) }
    func commit() {
        let t = Self.number(text).replacingOccurrences(of: "+", with: "")
        if let x = Double(t), x.isFinite { v = min(range.upperBound, max(range.lowerBound, x / scale)) }
        text = shown
    }
}
/// プリセットの行の小さな道具：編集・ロック・上下・消す（ロック中は消せない）
struct PresetTools: View {
    let locked: Bool, editing: Bool, edit: () -> Void, lock: () -> Void, up: () -> Void, down: () -> Void, del: () -> Void
    var body: some View {
        HStack(spacing: 7) {
            Button(action: edit) { Image(systemName: editing ? "pencil.circle.fill" : "pencil.circle") }.help("編集")
            Button(action: lock) { Image(systemName: locked ? "lock.fill" : "lock.open") }.help(locked ? "ロック中（消せない）。押すと外す" : "ロックして消せないようにする")
            Button(action: up) { Image(systemName: "chevron.up") }.help("上へ")
            Button(action: down) { Image(systemName: "chevron.down") }.help("下へ")
            Button(action: del) { Image(systemName: "xmark.circle") }.disabled(locked).help(locked ? "ロック中は消せない" : "消す")
        }
        .buttonStyle(.plain).focusable(false).foregroundStyle(UIC.sub).font(.system(size: 12))
    }
}
/// 6 つの角度（度）を数字で打ちこむ欄（X-W・Y-W・Z-W ／ X-Y・X-Z・Y-Z）
struct DegGrid: View {
    @Binding var deg: [Double]
    static let names = ["X-W", "Y-W", "Z-W", "X-Y", "X-Z", "Y-Z"]
    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(0..<2, id: \.self) { row in
                HStack(spacing: 6) {
                    ForEach(0..<3, id: \.self) { c in
                        let k = row * 3 + c
                        Text(Self.names[k]).font(.system(size: 10)).foregroundStyle(UIC.sub).frame(width: 26, alignment: .leading)
                        NumField(Binding(get: { deg.count == 6 ? deg[k] : 0 }, set: { var d = deg; if d.count == 6 { d[k] = $0; deg = d } }), -180...180, "%+.1f°")
                    }
                }
            }
        }
    }
}
/// 往復のプリセットの編集
struct PPPresetEditor: View {
    @ObservedObject var st: OrigamiState
    let i: Int
    func get<T>(_ k: KeyPath<PingPongPreset, T>, _ d: T) -> T { st.ppPresets.indices.contains(i) ? st.ppPresets[i][keyPath: k] : d }
    func set(_ f: (inout PingPongPreset) -> Void) { if st.ppPresets.indices.contains(i) { f(&st.ppPresets[i]); st.savePPPresets() } }
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField("名前", text: Binding(get: { get(\.name, "") }, set: { v in set { $0.name = v } })).textFieldStyle(.roundedBorder)
            let stops = get(\.stops, [])
            ForEach(stops.indices, id: \.self) { k in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(OrigamiState.ppNames[min(k, OrigamiState.ppNames.count - 1)]).font(.system(size: 12, weight: .bold)).foregroundStyle(UIC.amber)
                        Spacer()
                        Btn("今の角度") { let a = st.angles6Deg; set { if $0.stops.indices.contains(k) { $0.stops[k] = a } } }.help("今の角度をこの停留点に入れる")
                        if stops.count > 2 { Button { set { if $0.stops.indices.contains(k) { $0.stops.remove(at: k) } } } label: { Image(systemName: "xmark.circle") }.buttonStyle(.plain).focusable(false).foregroundStyle(UIC.sub) }
                    }
                    DegGrid(deg: Binding(get: { let s = get(\.stops, []); return s.indices.contains(k) ? s[k] : [0, 0, 0, 0, 0, 0] }, set: { v in set { if $0.stops.indices.contains(k) { $0.stops[k] = v } } }))
                }
            }
            HStack(spacing: 6) {
                if stops.count < OrigamiState.ppNames.count { Btn("＋ 停留点（今の角度）") { let a = st.angles6Deg; set { $0.stops.append(a) } } }
                Btn("並びを逆に") { set { $0.stops.reverse() } }
            }
            HStack {
                Text("1 区間").font(.system(size: 11)); Spacer()
                NumField(Binding(get: { get(\.sec, 3) }, set: { v in set { $0.sec = v } }), 0.5...12, "%.1f 秒")
            }
            HStack(spacing: 6) {
                Btn(get(\.cycle, false) ? "ぐるっと" : "往復", on: get(\.cycle, false)) { set { $0.cycle.toggle() } }
                Picker("動き方", selection: Binding(get: { get(\.ease, "spring") }, set: { v in set { $0.ease = v } })) { ForEach(OrigamiState.ppEases, id: \.0) { Text($0.1).tag($0.0) } }.frame(width: 150)
            }
            HStack(spacing: 6) {
                Btn("今の往復で上書き") { st.overwritePPPreset(i) }.help("今の往復（停留点・秒数・動き方）をこのプリセットに入れる")
                Btn("今の往復に入れる") { if st.ppPresets.indices.contains(i) { st.loadPPPreset(st.ppPresets[i], start: false) } }.help("始めずに、上の「角度の往復」に入れる")
                Btn("完了") { st.editPP = nil }
            }
        }
    }
}
/// 名前・打ちこめる数字・スライダーの 1 行
struct NumRow: View {
    let name: String; @Binding var v: Double; let range: ClosedRange<Double>, fmt: String, scale: Double
    init(_ name: String, _ v: Binding<Double>, _ range: ClosedRange<Double>, _ fmt: String, scale: Double = 1) { self.name = name; _v = v; self.range = range; self.fmt = fmt; self.scale = scale }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack { Text(name).font(.system(size: 11)); Spacer(); NumField($v, range, fmt, scale: scale) }
            Slider(value: $v, in: range).focusable(false)
        }
    }
}
/// 角度の 1 行：名前・スライダー（−180°〜180°）・数字・↺（0 に戻す）・回し続ける
struct AngleRow: View {
    let name: String; @Binding var a: Double; @Binding var spin: Bool
    init(_ name: String, _ a: Binding<Double>, spin: Binding<Bool>) { self.name = name; _a = a; _spin = spin }
    var deg: Binding<Double> {
        Binding(get: { var x = (a * 180 / .pi + 180).truncatingRemainder(dividingBy: 360); if x < 0 { x += 360 }; return x - 180 }, set: { a = $0 * .pi / 180 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 6) {
                Text(name).font(.system(size: 11, weight: .semibold))
                Spacer()
                NumField(deg, -180...180, "%+.0f°")
                // ↺ と ▶ は Tab で止まらない（Tab は角度の数字の欄を順に移る）
                Button { a = 0 } label: { Image(systemName: "arrow.counterclockwise") }.buttonStyle(.plain).focusable(false).foregroundStyle(UIC.sub).help("0 に戻す")
                Button { spin.toggle() } label: { Image(systemName: spin ? "pause.circle.fill" : "play.circle") }.buttonStyle(.plain).focusable(false)
                    .foregroundStyle(spin ? UIC.cyan : UIC.sub).help("この面を回し続ける")
            }
            Slider(value: deg, in: -180...180).focusable(false)
        }
    }
}

/// 色（SIMD3）と SwiftUI の Color のつなぎ
func colorBinding(_ b: Binding<SIMD3<Float>>) -> Binding<Color> {
    Binding(get: { Color(red: Double(b.wrappedValue.x), green: Double(b.wrappedValue.y), blue: Double(b.wrappedValue.z)) },
            set: { c in
                #if os(macOS)
                guard let n = NSColor(c).usingColorSpace(.sRGB) else { return }
                b.wrappedValue = SIMD3(Float(n.redComponent), Float(n.greenComponent), Float(n.blueComponent))
                #else
                var r: CGFloat = 0, g: CGFloat = 0, bl: CGFloat = 0, a: CGFloat = 0
                UIColor(c).getRed(&r, green: &g, blue: &bl, alpha: &a); b.wrappedValue = SIMD3(Float(r), Float(g), Float(bl))
                #endif
            })
}

/// 3D に出ている軸の長さ（ウェブ版の右上の札）：x・y・z・w の軸が、画面の 3D にどれだけ残っているか（4 本目へ回った分だけ短く）
struct AxisLenCard: View {
    @ObservedObject var st: OrigamiState
    static var last = [0, 0, 0, 0]                                         // 確かめ用：最後に出した数（%）
    /// 4 本の軸が x・y・z に残っている長さ（0〜1）
    static func lens(_ m: simd_double4x4) -> [Double] {
        let c = m.columns, cs: [SIMD4<Double>] = [c.0, c.1, c.2, c.3]
        return cs.map { v in min(1.0, (v.x * v.x + v.y * v.y + v.z * v.z).squareRoot()) }
    }
    var body: some View {
        // 書きかえは角度の知らせ（1 秒 15 回まで）で。TimelineView(.animation) は間隔をあけても毎コマ画面全体の並べ直しが走って、絵のコマが落ちる
        //   前は ForEach(0..<4) の中で長さを計算していて、並びが変わらないので行の作り直しが飛ばされ、最初の数のまま止まっていた。
        //   長さは先に計算して、1 行ずつ値として渡す（値が変われば行も変わる）
        LiveRead(live: st.live) {
            let vs = Self.lens(st.m4)
            let _ = { AxisLenCard.last = vs.map { Int(($0 * 100).rounded()) } }()
            VStack(alignment: .leading, spacing: 3) {
                Text("3D に出ている軸の長さ").font(.system(size: 10, weight: .bold)).foregroundStyle(UIC.text)
                AxisLenRow(name: Glass.axisNames[0], col: st.axisColorUI(0, 4), v: vs[0])
                AxisLenRow(name: Glass.axisNames[1], col: st.axisColorUI(1, 4), v: vs[1])
                AxisLenRow(name: Glass.axisNames[2], col: st.axisColorUI(2, 4), v: vs[2])
                AxisLenRow(name: Glass.axisNames[3], col: st.axisColorUI(3, 4), v: vs[3])
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(UIC.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(UIC.line))
        }
        .allowsHitTesting(false)
    }
}

/// 札の 1 行：軸の名前・棒・%
struct AxisLenRow: View {
    let name: String, col: Color, v: Double
    var body: some View {
        HStack(spacing: 5) {
            Text(name).font(.custom("KaTeX_Math-Italic", size: 12)).foregroundStyle(col).frame(width: 10)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08)).frame(width: 64, height: 5)
                Capsule().fill(col).frame(width: 64 * v, height: 5)
            }
            Text(String(format: "%.0f%%", v * 100)).font(.system(size: 9).monospacedDigit()).foregroundStyle(UIC.sub).frame(width: 30, alignment: .trailing)
        }
    }
}

/// 毎コマ変わる値を出す所だけを、知らせ（LiveTick、1 秒 15 回まで）で作り直す入れ物
struct LiveRead<C: View>: View {
    @ObservedObject var live: LiveTick
    @ViewBuilder let content: () -> C
    var body: some View { content() }
}

/// タブを開くのにかかった時間を記録する（重い時に原因を探すため）：~/Library/Logs/Origami/tabs.log
//   押した時から、パネルを作り直して画面に出すまで（次の次の回り）
enum TabTimer {
    @MainActor static func open(_ st: OrigamiState, _ k: Int) {
        let t0 = CACurrentMediaTime()
        st.panelTab = k
        DispatchQueue.main.async { DispatchQueue.main.async {
            let ms = (CACurrentMediaTime() - t0) * 1000, name = k < OrigamiPanel.tabs.count ? OrigamiPanel.tabs[k].0 : "\(k)"
            let dir = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Logs/Origami")
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let line = String(format: "%@ %@ %.0f ms（点 %d 個）\n", ISO8601DateFormatter().string(from: Date()), name, ms, st.userPts.count)
            let url = dir.appendingPathComponent("tabs.log")
            if let h = try? FileHandle(forWritingTo: url) { h.seekToEndOfFile(); h.write(line.data(using: .utf8)!); try? h.close() }
            else { try? line.data(using: .utf8)!.write(to: url) }
        } }
    }
}

/// 移動パッド：丸をドラッグすると、その窓の図形がつかんだ向きへ動く。ダブルクリック（ダブルタップ）で真ん中へ戻す
//   動かしている間は、絵の窓の見る所（pan）だけを書きかえる（パネルの作り直しは起きない）
struct PanPad: View {
    @ObservedObject var st: OrigamiState
    let i: Int
    final class Box { var last: CGSize = .zero }
    @State private var box = Box()
    @State private var active = false
    var body: some View {
        Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
            .font(.system(size: 17, weight: .medium))
            .foregroundStyle(active ? Color(red: 0.91, green: 0.84, blue: 1.0) : UIC.sub)
            .frame(width: 46, height: 46)
            .background(Circle().fill(active ? Color(red: 0.23, green: 0.11, blue: 0.36).opacity(0.85) : UIC.panel.opacity(0.75)))
            .overlay(Circle().stroke(active ? Color(red: 0.66, green: 0.33, blue: 0.97) : UIC.line))
            .contentShape(Circle())
            .onTapGesture(count: 2) { st.pan[i] = .zero }
            .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                if !active { active = true }
                let d = CGSize(width: g.translation.width - box.last.width, height: g.translation.height - box.last.height); box.last = g.translation
                st.panBy(i, Double(d.width), Double(d.height))
            }.onEnded { _ in box.last = .zero; active = false })
            .help("移動パッド：ドラッグで図形を動かす（⌘／Ctrl＋ドラッグと同じ）。ダブルクリックで真ん中へ戻す")
    }
}

/// 4 次元の立体を見る：3 つの窓（3D のたとえ・4D の影＋切っている所・メインに断面）。ウェブ版の「柱の見本」から
struct ShapePanel: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("4 次元の立体を見る（窓を 3 つに）", isOn: $st.shapeOn)
            Text("大きい窓：4 次元の立体を、3 次元の面で切った切り口（断面）。右上：1 つ下の次元のたとえ（3D の立体を平面で切ると、切り口は線）。右下：4D の影と、今切っている所（光る所）。4 次元で回すと、切る向きが変わります").font(.caption2).foregroundStyle(UIC.sub)
            Picker("立体", selection: $st.shapeKind) { ForEach(1..<OrigamiState.shapeNames.count, id: \.self) { k in Text(OrigamiState.shapeNames[k]).tag(k) } }
            LiveRead(live: st.live) { NumRow("切る位置", $st.shapeCut, -1...1, "%+.0f%%", scale: 100) }
            HStack {
                Btn(st.shapePlay ? "⏸ 止める" : "▶ 自動で動かす", on: st.shapePlay) { st.shapePlay.toggle(); if st.shapePlay { st.shapeOn = true } }
                Btn("まんなか") { st.shapeCut = 0 }
                Btn(st.shapeMainProj ? "大きい窓：4D の影" : "大きい窓：断面", on: st.shapeMainProj) { st.shapeMainProj.toggle() }.help("断面 ⇄ 投影：大きい窓と右下の窓の中身を入れかえる")
            }
            HStack {
                Toggle("影の中に断面を出す", isOn: $st.shapeGlowOn).help("切ると、4D の影の窓は全体像だけになる（今切っている所の光を消す）")
                LiveRead(live: st.live) { NumRow("断面の濃さ", $st.shapeGlowAlpha, 0...1, "%.0f%%", scale: 100) }.disabled(!st.shapeGlowOn)
            }
            Picker("4D の影", selection: $st.shapeShadowMode) { Text("輪切りを重ねる").tag(0); Text("積分の積み上げ").tag(1); Text("本物の影（立体）").tag(2) }.pickerStyle(.segmented)
                .help("輪切りを重ねる：w の輪切り 9 枚をうすい殻で。積分の積み上げ：積分タブと同じ絵（輪切りの形を w の −1 〜 ＋1 に段ごとに積む。色は積む順。大きさは積分タブの形）。本物の影：4 次元の光で照らした 3 次元の影を、中身のつまった立体で（回すたびに作り直す）")
            Text("3D のたとえ：" + OrigamiState.shapeAnalog[max(1, min(5, st.shapeKind))]).font(.caption2).foregroundStyle(UIC.sub)
        }
    }
}

/// 断面のパネル：出す・包丁の位置・自動で動かす・包丁の向き（どこから見る）・切り口の形の名前
struct SectionPanel: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("断面を出す", isOn: $st.secOn)
            Text("組み上がった形を、平らな包丁で切った切り口。超立方体は w に垂直な 3 次元の包丁（わたしたちの 3 次元の世界）、立方体は z に垂直な包丁。4 次元で回すと包丁がななめになって、切り口の形が変わります。面の色は、もとの胞の色").font(.caption2).foregroundStyle(UIC.sub)
            LiveRead(live: st.live) { NumRow("包丁の位置", $st.secPos, -1...1, "%+.0f%%", scale: 100) }.disabled(!st.secOn)
            HStack {
                Btn(st.secPlay ? "⏸ 止める" : "▶ 自動で動かす", on: st.secPlay) { st.secPlay.toggle(); if st.secPlay { st.secOn = true } }
                Btn("まんなか") { st.secPos = 0 }
            }
            Text("包丁の向き（どこから見るへ回す）").font(.caption2).foregroundStyle(UIC.sub)
            HStack {
                Btn("胞から") { st.goView(0, animated: true) }.help("いつも立方体（立方体の窓は正方形）")
                Btn("面から") { st.goView(1, animated: true) }.help("立方体の窓は長方形、超立方体は四角柱のなかま")
                Btn("辺から") { st.goView(2, animated: true) }.help("三角柱のなかま")
                Btn("頂点から") { st.goView(3, animated: true) }.help("点 → 正四面体 → 切頂四面体 → 正八面体（まんなか）。立方体の窓は 三角形 → 正六角形")
            }
            LiveRead(live: st.live) {
                VStack(alignment: .leading, spacing: 2) {
                    if st.secOn {
                        Text("超立方体の切り口：" + (st.secInfo[1].isEmpty ? "—" : st.secInfo[1])).font(.system(size: 11, weight: .semibold))
                        Text("立方体の切り口：" + (st.secInfo[0].isEmpty ? "—" : st.secInfo[0])).font(.system(size: 11))
                        if st.progress < 0.999 { Text("組み上がっている時だけ出ます").font(.caption2).foregroundStyle(UIC.sub) }
                    }
                }
            }
        }
    }
}

/// 辺の強調：手前・奥のほかの胞（超立方体）・面（立方体）を選んで、好きな色で。行 ±X〜±Z（±W は手前・奥）、列 4D・3D
struct EdgeHiCells: View {
    @ObservedObject var st: OrigamiState
    static let rows: [(String, String)] = [("px", "+X"), ("nx", "−X"), ("py", "+Y"), ("ny", "−Y"), ("pz", "+Z"), ("nz", "−Z")]
    func used(_ d: Int, _ k: String) -> Bool { d == 4 || (k != "pz" && k != "nz") }       // 立方体の ±Z の面は手前・奥
    /// 選んだ時の最初の色：その胞（面）のパレットの色
    func palCol(_ d: Int, _ k: String) -> SIMD3<Float> { OrigamiState.rgb(st.effPal(d)[k] ?? 0x888888) }
    func onB(_ key: String, _ d: Int, _ k: String) -> Binding<Bool> {
        Binding(get: { st.ehCells[key] != nil }, set: { v in st.ehCells[key] = v ? palCol(d, k) : nil })
    }
    func colB(_ key: String, _ d: Int, _ k: String) -> Binding<SIMD3<Float>> {
        Binding(get: { st.ehCells[key] ?? palCol(d, k) }, set: { st.ehCells[key] = $0 })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(alignment: .leading, horizontalSpacing: 10, verticalSpacing: 3) {
                GridRow { Text(""); Text("4D（超立方体の胞）").font(.system(size: 10, weight: .bold)).foregroundStyle(UIC.sub); Text("3D（立方体の面）").font(.system(size: 10, weight: .bold)).foregroundStyle(UIC.sub) }
                ForEach(Self.rows, id: \.0) { k, L in
                    GridRow {
                        Text(L).font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.text)
                        ForEach([4, 3], id: \.self) { d in
                            if used(d, k) { cell(d, k) } else { Text("（手前・奥）").font(.system(size: 10)).foregroundStyle(UIC.sub.opacity(0.5)) }
                        }
                    }
                }
            }
            HStack {
                Btn("全部つける（パレットの色）") { for d in [4, 3] { for (k, _) in Self.rows where used(d, k) { st.ehCells["\(d):\(k)"] = palCol(d, k) } } }
                Btn("全部はずす") { st.ehCells = [:] }
            }
        }
    }
    func cell(_ d: Int, _ k: String) -> some View {
        let key = "\(d):\(k)"
        return HStack(spacing: 4) {
            Toggle("", isOn: onB(key, d, k)).labelsHidden()
            ColorPicker("", selection: colorBinding(colB(key, d, k))).labelsHidden().disabled(st.ehCells[key] == nil)
        }.help("\(d)D の \(k.first == "p" ? "＋" : "−")\(k.last!.uppercased()) の辺を強調する（色は右の見本で）")
    }
}

/// 組み上げ・展開の向き：おまかせ 1・2 か、表（4D の角度・3D の角度を、組んだ時の向きと開いた時の向きで別々にするか共通にするか）
struct AsmMatrix: View {
    @ObservedObject var st: OrigamiState
    func row(_ t: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
            Text(sub).font(.system(size: 8)).foregroundStyle(UIC.sub)
        }
    }
    /// 「別々（往復）・共通」の 2 つの丸ボタン
    func pick(_ v: Binding<Bool>, _ hSep: String, _ hCom: String) -> some View {
        HStack(spacing: 10) {
            ForEach([true, false], id: \.self) { k in
                Button { v.wrappedValue = k } label: {
                    HStack(spacing: 4) {
                        Image(systemName: v.wrappedValue == k ? "largecircle.fill.circle" : "circle").font(.system(size: 10))
                        Text(k ? "別々（往復）" : "共通").font(.system(size: 11))
                    }.foregroundStyle(v.wrappedValue == k ? UIC.cyan : UIC.sub).contentShape(Rectangle())
                }.buttonStyle(.plain).focusable(false).help(k ? hSep : hCom)
            }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Btn("🪄 おまかせ 1", on: st.autoMode == 1) { st.autoMode = 1 }
                    .help("ゆがみなし：4D は別々・3D は共通。はじめて開く時は、今の見た目にいちばん近いまっすぐへ。組むと組んだ時の 4D のかたむきへもどる。4D の回し続けるは、開くと 3D に置きかわる")
                Btn("🪄 おまかせ 2", on: st.autoMode == 2) { st.autoMode = 2 }
                    .help("ゆがみも：4D も 3D も共通＝開く時も組む時も今の向きのまま（4D のゆがみもそのまま展開図に）")
                Btn("表で決める", on: st.autoMode == 0) { st.autoMode = 0 }.help("4D・3D の角度を、2 つの向きで別々にするか共通にするか、下の表で決める")
            }
            if st.autoMode == 1 {
                Text("1（ゆがみなし）＝4D 別々・3D 共通：組んだ時の 4D のかたむきと、開いた時の 4D のかたむき（はじめはまっすぐ）を往復。開いている間に 3D で回した分は、組んだ時の向きにも持ちこむ").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            } else if st.autoMode == 2 {
                Text("2（ゆがみも）＝4D も 3D も共通：開く時も組む時も今の向きのまま。4D で回したゆがみも、そのまま展開図に").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            } else { table }
            if st.asmPose != 0 || st.asmVanish != 3 || st.unfPose >= 2 {
                Text("※「向きと記憶」のくわしくで決めた向きが優先されています").font(.caption2).foregroundStyle(.orange)
            }
        }
    }
    @ViewBuilder var table: some View {
        VStack(alignment: .leading, spacing: 4) {
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    row("4D の角度", "X-W・Y-W・Z-W")
                    pick($st.sep4, "組んだ時と開いた時で、4D のかたむきを別々に持つ（開いた時は、はじめはいちばん近いまっすぐ）。C で往復すると、それぞれの続きにもどる", "4D のかたむきは今のまま持ちこむ（開くと 4D のゆがみも展開図に）")
                }
                GridRow {
                    row("3D の角度", "X-Y・X-Z・Y-Z")
                    pick($st.sep3, "組んだ時と開いた時で、3D の見る向きも別々に持つ", "3D の見る向きは共通：開いている間に回した分は、組んだ時の向きにも持ちこむ（逆も同じ）")
                }
            }
            Text("組み上がっている時の向きと、開いている時の向きを別々に持つ。回すと今いる方が変わり、C でもう一方の続きへ").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
        }
    }
}


/// 内接球の回転の欄：なし・3D（層ごとの速さ）・4D の二重回転（速さの比・ホップの輪）
struct InSphereSpinRows: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text("回転").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                Btn("なし", on: st.inSphereSpin == 0) { st.inSphereSpin = 0 }.help("模様を回さない")
                Btn("🌍 3D", on: st.inSphereSpin == 1) { st.inSphereSpin = 1 }.help("w ＝ 一定の層ごとに、層の中で y の軸のまわりに回す（地球儀）。赤道の層ほど速くすると、膜がねじれてうずまきに。球はまんまるなので、形と接点は変わらず模様だけが動く")
                Btn("🌀 4D 二重回転", on: st.inSphereSpin == 2) { st.inSphereSpin = 2 }.help("X-Y の面と Z-W の面を同時に回す。1 : 1 なら止まる点が 1 つもなく、どの点も大円を走り、その道どうしは鎖のようにからみ合う（ホップの輪）。Z-W が回るので、層がかたむいて流れ出す")
            }
            if st.inSphereSpin != 0 {
                LiveRead(live: st.live) { NumRow("速さ", $st.inSphereSpinSpeed, 0.1...3, "×%.1f", scale: 1) }
                if st.inSphereSpin == 1 {
                    LiveRead(live: st.live) { NumRow("層ごとの差", $st.inSphereDiff, 0...1, "%.2f", scale: 1) }
                    Text("0＝全部いっしょ（地球儀）・1＝赤道だけ回って極は止まる（太陽や木星の差動回転のように、膜がねじれる）").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(spacing: 6) {
                        Text("速さの比").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                        ForEach(0..<OrigamiState.sphRatios.count, id: \.self) { k in
                            Btn(OrigamiState.sphRatios[k].name, on: st.inSphereRatio == k) { st.inSphereRatio = k }.help("X-Y の面 : Z-W の面 の回る速さ")
                        }
                    }
                    Btn("🔗 ホップの輪", on: st.inSphereHopf) { st.inSphereHopf.toggle() }.help("模様の上の 9 個の点が 1 周で走る道を、光る輪で（今いる所に小さな玉）。1 : 1 ではどれも大円で、どの 2 本も鎖のようにからみ合う")
                    Text("3 次元の回転にはかならず止まった軸があるが、4 次元では 2 枚の面を同時に回せる。1 : 1 の時は、止まっている点が 1 つもない").font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
                }
                Toggle("経線が接点を通るとチカッと光る", isOn: $st.inSphereFlash)
                    .help("模様の経線（経度の膜）が、胞に接する点の光の輪を通りすぎる瞬間に、輪が明るく大きくなる。超球が胞に触れているのは、その 1 点だけ")
            }
        }
    }
}

/// 5 次元の展開図をえらぶ（見本・でたらめ・図鑑の番号）
struct Net5Picker: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        let E = Net5Atlas.entries
        VStack(alignment: .leading, spacing: 6) {
            Text("展開図（5 次元は全部で \(E.isEmpty ? 9694 : E.count) 種類）").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub)
            HStack(spacing: 6) {
                ForEach(OrigamiState.net5Presets, id: \.0) { name, p in
                    Btn(name, on: st.net5 == p) { st.setNet5(p); show() }.help("超立方体の見本「\(name)」と同じ考えの 5 次元の展開図")
                }
            }
            if !E.isEmpty {
                HStack(spacing: 6) {
                    Btn("📚 図鑑") { st.atlas5Open = true }.help("9,694 種類を全部並べた 5 次元の図鑑を開く")
                    Btn("🎲 でたらめ") { st.net5Random(); show() }.help("9,694 種類から 1 つ、でたらめに")
                    Btn("◀◀") { st.net5Step(-100); show() }.help("100 番もどる")
                    Btn("◀") { st.net5Step(-1); show() }.help("前の番号")
                    Text(st.net5No > 0 ? "No. \(st.net5No) / \(E.count)" : "図鑑の外").font(.system(size: 11, weight: .semibold).monospacedDigit()).frame(minWidth: 92)
                    Btn("▶") { st.net5Step(1); show() }.help("次の番号")
                    Btn("▶▶") { st.net5Step(100); show() }.help("100 番すすむ")
                }
                if st.net5No > 0 {
                    let e = E[st.net5No - 1]
                    Text("いちばん長いつながり \(e.longest) 個・1 つの胞にくっつく数 最大 \(e.maxDeg) 個（番号は、長いつながりの短い順）")
                        .font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    /// 組み上がっている時にえらんだら、開いて形を見せる
    func show() { if st.progress > 0.5 && !st.playing { st.playUnfold() } }
}
