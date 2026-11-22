// 次元おりがみの画面（ウェブ版 hypercube.html と同じつくり）
//   左に立方体の窓・右に超立方体の窓（境目をドラッグして広さを変える）、窓の上の下のほうに回転バー、右（B キーで左）にパネル。
//   パネル：上に 4 つのタブ（折りたたみ・回転・見え方・点）、中は区切り（見出しと中身）。区切りの順番と名前はウェブ版と同じ。
//     まだ移していない区切りは見出しだけ（「これから移します」）。ネイティブ版だけのもの（質感・光・宇宙）は「見え方」の「視覚効果」に。
//   キー（Mac）：スペース＝パネルの開け閉め、B＝パネルを左右に
import SwiftUI
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
    final class GestureBox { var last = CGSize.zero; var pinch0: Double? = nil; var split0: Double? = nil }
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
        .onAppear { DispatchQueue.global(qos: .utility).async { _ = NetAtlas.built } }   // 図鑑を先に作っておく
        // 保存してあった設定をもどして、変わったら保存する（確かめの時は使わない＝いつも同じ初めの形で測る）
        .onAppear { if !PerfTest.on { st.startSettings() } }
        #if os(macOS)
        .onAppear {
            if PerfTest.on {                                                 // 確かめ：全部を回し続けて、8 秒で結果を出して終わる
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
            default: twoPanes(W)
            }
        }
    }
    var cubePane: some View { pane(3, "立方体（2D 展開図 → 3D）", "折りたたみでできる新しい次元＝z") }
    var hyperPane: some View { pane(4, "超立方体（3D 展開図 → 4D）", "折りたたみでできる新しい次元＝w").overlay(alignment: .topTrailing) { AxisLenCard(st: st).padding(10) } }
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
    func pane(_ n: Int, _ title: String, _ sub: String) -> some View {
        let i = n == 3 ? 0 : 1
        return ZStack(alignment: .topLeading) {
            #if os(macOS)
            // Mac はマウス・つまみを絵の窓（OrigamiMTKView）が直接受ける
            OrigamiPane(n: n, st: st)
            #else
            OrigamiPane(n: n, st: st)
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    let dd = CGSize(width: g.translation.width - gb.last.width, height: g.translation.height - gb.last.height); gb.last = g.translation
                    #if os(macOS)
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    #else
                    let shift = false
                    #endif
                    if shift { st.drag(.zw, Double(dd.width) * 0.01) }
                    else if n == 3 { st.drag(.l4x, Double(dd.width) * 0.01); st.drag(.l4y, Double(dd.height) * 0.01) }   // 左：X-W・Y-W（左は X-Z・Y-Z）
                    else { st.drag(.r3x, Double(dd.width) * 0.01); st.drag(.r3y, Double(dd.height) * 0.01) }            // 右：画面の縦・横の軸のまわりに形を回す
                }.onEnded { _ in gb.last = .zero; st.dragging = false })
                .simultaneousGesture(MagnificationGesture().onChanged { k in
                    if gb.pinch0 == nil { gb.pinch0 = st.zoom[i] }
                    st.zoom[i] = max(0.3, min(8, gb.pinch0! * Double(k)))
                }.onEnded { _ in gb.pinch0 = nil })
            #endif
            OrigamiLabels(n: n, st: st).allowsHitTesting(false)
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
    }
}

// MARK: - 下の回転バー（ウェブ版の rot-bar）
struct OrigamiRotBar: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        HStack(spacing: 6) {
            Text("回転").font(.system(size: 11, weight: .bold)).foregroundStyle(UIC.sub).lineLimit(1).fixedSize()
            pill("W(X,Y,Z)", st.allW, "W の絡む 3 面（X-W・Y-W・Z-W）を回し続ける＝中身がぐりぐり入れかわる 4D の回転") { st.toggleWAll() }
            pill("W(X,Y)", st.w2Only, "X-W・Y-W の 2 面だけを回し続ける（Z-W は回さない）。立方体も X-Z・Y-Z で一緒に回る") { st.toggleW2() }
            pill("3D", st.all3D, "X-Y・X-Z・Y-Z（w を含まない 3 面＝ふつうの 3D の回転）を回し続ける。形は変わらず転がる") { st.toggle3D() }
            pill("全て", st.allW && st.all3D, "6 面すべてを同時に回し続ける") { st.toggle6() }
            pill("🎲", st.diceRolling, "超立方体サイコロを振る（⇧0）：①4D でころころ → 奥の胞が決まる ②その胞が飛び出して 3D でころころ → 手前の面が目（24 の目・48 の目は回転タブで）") { st.rollDice() }
            pill("内接球", st.inSphere, "超立方体にぴったり内接する超球面（8 個の胞の真ん中に接する）を、超球面アプリと同じ「w 一定の球殻を積んだ形」で中に出す。超立方体と一緒に回る（立方体の窓は内接する球の緯度の輪）") { st.inSphere.toggle() }
            Divider().frame(height: 18)
            pill("補正", false, "z 軸を画面に垂直に立て直す（Z-W・X-Z・Y-Z を 0 に。回転は止めない）") { st.snap() }
            pill("リセット", false, "回転を止めて、全部の角度を 0 に戻した正面の形にする") { st.resetAll() }
            Divider().frame(height: 18)
            TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                Text("\(max(st.fps[0], st.fps[1])) コマ/秒").font(.system(size: 10).monospacedDigit()).foregroundStyle(UIC.sub).lineLimit(1).fixedSize()
                    .help(String(format: "1 秒に描いたコマの数（GPU で 1 コマ：立方体 %.1f ミリ秒・超立方体 %.1f ミリ秒）", st.gpuMs[0], st.gpuMs[1]))
            }
            Divider().frame(height: 18)
            LiveRead(live: st.live) { Text(st.projBlend > 0.5 ? "投影: 平行" : "投影: 遠近").font(.system(size: 11)).foregroundStyle(UIC.sub).lineLimit(1).fixedSize() }
                .help("今の投影（遠近＝いつも奥行きあり／平行＝W の角度が付いていれば平行投影）")
            pill(st.perspMode ? "→ 平行投影" : "→ 遠近投影", !st.perspMode, "投影の切りかえ。平行投影＝W の回転・面／辺／頂点から が、きれいな正多角形に。遠近投影＝いつも奥行きあり") { st.perspMode.toggle() }
        }
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(UIC.panel.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(UIC.line))
    }
    func pill(_ t: String, _ on: Bool, _ help: String, _ act: @escaping () -> Void) -> some View {
        Button(action: act) {
            Text(t).font(.system(size: 11, weight: .semibold)).foregroundStyle(on ? UIC.cyan : UIC.text)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(on ? UIC.cyan.opacity(0.18) : Color.white.opacity(0.06), in: Capsule())
                .overlay(Capsule().stroke(on ? UIC.cyan.opacity(0.8) : UIC.line))
        }.buttonStyle(.plain).help(help)
    }
}

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
                Btn("📚 展開図図鑑（261）") { st.atlasOpen = true }.help("超立方体の展開図 261 種類を全部並べた図鑑。押すとその展開図になる")
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
            // 開いた時：向きを保つ ／ まっすぐ（W 消失の 3D 空間）。次に C を押すと何が起きるか
            HStack(spacing: 6) {
                Text("開いた時").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                Btn("向きを保つ", on: st.unfPose == 0) { st.unfPose = 0 }.help("開いても今の向きのまま")
                Btn("まっすぐ（ゆがみなし）", on: st.unfPose == 1) { st.unfPose = 1 }.help("開きながら 4 次元のかたむきを取る＝W 消失の 3D 空間に開く（3D の向きは保つ）")
                if st.unfPose >= 2 { Text("（\(OrigamiState.unfPoseNames[min(6, st.unfPose)])）").font(.caption2).foregroundStyle(UIC.sub) }
            }
            NextCLine(st: st)
            // 多段階：最大の段数（1＝全部いっしょ）。展開図の深さがこれより多い時は、近い深さをまとめる
            HStack(spacing: 6) {
                Text("多段階").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text)
                Text("最大").font(.caption2).foregroundStyle(UIC.sub)
                ForEach(1...4, id: \.self) { k in
                    let cur = st.foldStagger ? st.foldMaxStages : 1
                    Btn("\(k) 段", on: cur == k) { st.foldMaxStages = k; st.foldStagger = k > 1 }
                        .help(k == 1 ? "全部いっしょに折る" : "真ん中に近い段から順に、最大 \(k) 段に分けて折る（展開図の深さがこれより少なければ、その段数のまま）")
                }
            }
            // 一筆（くるくる）
            HStack(spacing: 6) {
                Btn("🌀 一筆（くるくる）", on: st.foldCourse) { st.foldCourse.toggle() }
                    .help("いちばん長いつながりのはしっこから、ちょうつがいを 1 個ずつ順に折る。反対のはし（ゴール）の胞を床に止めて、巻いたかたまりがゴールまでころころ転がっていく。転がり終わると 90° ずつコロンと返って、いつもの真ん中・いつもの向きへ。枝の胞はコースが根元に来た時に折る。入の間は多段階より優先")
                if st.foldCourse {
                    Btn("はし A から", on: !st.courseFromB) { st.courseFromB = false }
                    Btn("はし B から", on: st.courseFromB) { st.courseFromB = true }
                }
            }
            let D = OrigamiState.depths(st.net.p4).max() ?? 1
            if st.foldCourse { Text("一筆：ちょうつがい \(st.net.p4.count - 1) 個を、はしから 1 個ずつ巻いてゴールまで転がる → 最後にコロンと返っていつもの向きへ（開く時は逆再生）").font(.caption2).foregroundStyle(UIC.sub) }
            Text("この展開図：\(st.foldStages(D)) 段（深さ \(D)・最大 \(st.foldStagger ? st.foldMaxStages : 1) 段）。つながりが長い展開図ほど深い：ダリの十字架は 2、いちばん長い 8 個つながりは 4")
                .font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            LiveRead(live: st.live) { NumRow("開く速さ（組み立ての何倍か）", $st.unfoldK, 1...4, "×%.1f", scale: 1) }
        }
        Sec("組み上がりの向き", "cube.transparent") { AsmPoseSection(st: st) }
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
            Picker("線の 4D の奥行き", selection: $st.line4) { Text("同じ").tag(0); Text("奥ほどうすく").tag(1); Text("奥ほど濃く").tag(2) }
                .help("超立方体の線を、4 次元の奥行きで変える。奥ほどうすく＝手前の線が太くはっきり、奥は背景に沈む（ウェブ版の濃淡）。奥ほど濃く＝4 次元の奥に何かあるのが線で浮かぶ。1 本の辺の中でもなめらかに変わる")
            LiveRead(live: st.live) { NumRow("線の 4D の奥行きの強さ", $st.line4K, 0...1, "%.0f%%", scale: 100) }.disabled(st.line4 == 0)
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
                .help("4 次元の奥行きを頂点ごとに：奥ほど色つきのセロハンのように後ろの色に掛け合わせる（乗算の面は最後に描いて、手前のガラスにも色をかける）。展開図では効かず、組み上がるほど効く")
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
        Sec("お遊び", "gamecontroller") { Later() }
        Sec("24面サイコロ（お遊び）", "die.face.5") { Later() }
    }

    // ---- 点 ----
    @ViewBuilder var ptsTab: some View {
        Sec("手前と奥の辺を色で強調", "highlighter") {
            Toggle("強調する", isOn: $st.ehOn)
            Text("手前＝折りたたみでできた次元の＋側の胞（ふた）、奥＝−側の胞（真ん中）。超立方体なら w の＋と −、立方体なら z の＋と −").font(.caption2).foregroundStyle(UIC.sub)
            HStack {
                ColorPicker("手前", selection: colorBinding($st.ehNear)).disabled(!st.ehOn)
                ColorPicker("奥", selection: colorBinding($st.ehFar)).disabled(!st.ehOn)
            }
            LiveRead(live: st.live) { NumRow("手前の太さ", $st.ehWidthNear, 1...16, "%.1f 画素", scale: 1) }.disabled(!st.ehOn)
            LiveRead(live: st.live) { NumRow("奥の太さ", $st.ehWidthFar, 1...16, "%.1f 画素", scale: 1) }.disabled(!st.ehOn)
            Btn("既定に戻す") { st.ehNear = SIMD3(1.0, 0.267, 0.867); st.ehFar = SIMD3(0.2, 0.898, 1.0); st.ehWidthNear = 3; st.ehWidthFar = 3 }
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
    var body: some View {
        // 書きかえは角度の知らせ（1 秒 15 回まで）で。TimelineView(.animation) は間隔をあけても毎コマ画面全体の並べ直しが走って、絵のコマが落ちる
        LiveRead(live: st.live) {
            VStack(alignment: .leading, spacing: 3) {
                Text("3D に出ている軸の長さ").font(.system(size: 10, weight: .bold)).foregroundStyle(UIC.text)
                ForEach(0..<4, id: \.self) { k in
                    let c = st.m4.columns, col = [c.0, c.1, c.2, c.3][k], v = min(1, sqrt(col.x * col.x + col.y * col.y + col.z * col.z))
                    HStack(spacing: 5) {
                        Text(Glass.axisNames[k]).font(.custom("KaTeX_Math-Italic", size: 12)).foregroundStyle(st.axisColorUI(k, 4)).frame(width: 10)
                        ZStack(alignment: .leading) {
                            Capsule().fill(Color.white.opacity(0.08)).frame(width: 64, height: 5)
                            Capsule().fill(st.axisColorUI(k, 4)).frame(width: 64 * v, height: 5)
                        }
                        Text(String(format: "%.0f%%", v * 100)).font(.system(size: 9).monospacedDigit()).foregroundStyle(UIC.sub).frame(width: 30, alignment: .trailing)
                    }
                }
            }
            .padding(.horizontal, 9).padding(.vertical, 6)
            .background(UIC.panel.opacity(0.9), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).stroke(UIC.line))
        }
        .allowsHitTesting(false)
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
