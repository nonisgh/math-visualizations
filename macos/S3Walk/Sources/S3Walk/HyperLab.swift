// 超球（Metal 版の試作）：ウェブ版 hypersphere_beta.html の核を、Swift と Metal で描く。
//   左：3D の球をリング（緯度の円）を積んで作る。右：4D の超球を球殻（w 一定の 2 次元の球面）を積んで作り、4D で回して 3D へ遠近で写す。
//   左の「リング ↔ 右の球殻」が 1 つずつ対応する（2 次元とのアナロジー：円を積むと球、球を積むと超球）。
//   回転の対応はウェブ版と同じ：左の前後傾き（x 軸まわり）＝右の Y-W、左右傾き（y 軸まわり）＝右の X-W（向きは逆）、面内（z 軸まわり）＝右の X-Y。
//   Z-W 傾きは左の 3D には無い第 4 の軸への傾きで、左では「z′＝0 で切った断面」としてリングが動く・消える。
//   ウェブ版の角度・色・遠近（camW）・層の作り方はそのまま。切り欠き・4D カメラ・旅・学習などは、まだ（ウェブ版の窓で）
import SwiftUI
import MetalKit
import CoreVideo

struct HyperLabView: View {
    @StateObject var st = HyperLabState()
    @State var last: CGSize = .zero
    @State var pinch0: Double? = nil
    var body: some View {
        GeometryReader { full in
        VStack(spacing: 0) {
            if st.mainBarOn && !st.panelHidden, let bar = HyperLabState.mainBar { bar(st) }   // パネルを隠す時は、上のメインメニューも隠す
            // 並び：3 つの時は［左上・左下・右］、さんぽの景色を出さない時は［左・右］（order の順。⟳ で回す）
            let items = st.order.filter { ($0 != 1 || st.paneMap2 || (st.walkView && HyperLabState.walkRendererGet?() != nil)) && ($0 != 0 || st.show3D || st.paneBoth) }
            // 仕切りはドラッグで動かせる（位置は保存。ダブルクリックで半分に）。景色の画面を小さくすると、描く画素もそのぶん減って軽くなる
            HLSplitK(a: st.splitA) { sk in GeometryReader { g in
                let W = max(1, g.size.width), H = max(1, g.size.height), bar: CGFloat = 5
                let lw: CGFloat = min(W - 140, max(140, W * CGFloat(st.splitX))), th: CGFloat = min(H - bar - 90, max(90, (H - bar) * CGFloat(st.splitAt(sk))))
                HStack(spacing: 0) {
                    if items.count == 1 { fadeSlot(items[0]) }              // 4D の超球だけ
                    else if items.count == 3 {
                        VStack(spacing: 0) {
                            fadeSlot(items[0]).frame(height: th)
                            HLSplitBar(vertical: false, onDrag: { y in st.splitY = min(0.9, max(0.1, Double(y / H))) }, onReset: { st.splitY = 0.5 })
                            fadeSlot(items[1])
                        }.overlay(paneShade).frame(width: lw)
                    } else { fadeSlot(items[0]).overlay(paneShade).frame(width: lw) }
                    if items.count > 1 {
                        HLSplitBar(vertical: true, onDrag: { x in st.splitX = min(0.9, max(0.1, Double(x / W))) }, onReset: { st.splitX = 0.5 })
                        fadeSlot(items[items.count - 1])
                    }
                }
            } }
            .coordinateSpace(name: "hlsplit")
            .background(Color(red: 0.12, green: 0.16, blue: 0.23))
            // 画面のゲームパッド（下の真ん中。パネルを隠していても出す）
            .overlay(alignment: .bottom) {
                if st.padOn, let r = HyperLabState.walkRendererGet?() {
                    VirtualPad(game: r.game) { st.padOn = false; r.game.vClear() }.spaceControls()
                        .padding(.bottom, 14).onAppear { r.set.gamepad = true }
                }
            }
            // さんぽメニュー（右上の少し下に浮かぶ。✕ で隠す。パネルの「さんぽメニュー」でまた出す）
            .overlay(alignment: .topTrailing) {
                // 閉じている時は、右上に小さな「さんぽ」ボタンだけ（押すとまた出る）
                if !st.walkMenu, HyperLabState.walkRendererGet?() != nil {
                    Button { withAnimation(.easeInOut(duration: 0.15)) { st.walkMenu = true } } label: {
                        Label("さんぽ", systemImage: "figure.walk").font(.caption).padding(.horizontal, 9).padding(.vertical, 5)
                            .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.8), in: Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                    }.buttonStyle(.plain).foregroundStyle(Color(red: 0.55, green: 0.8, blue: 1.0)).padding(.top, 74).padding(.trailing, 12)
                    .help("さんぽメニューを出す")
                }
                if st.walkMenu, let r = HyperLabState.walkRendererGet?() {
                    VStack(alignment: .trailing, spacing: 8) {
                        HLWalkMenu(r: r, close: { withAnimation(.easeInOut(duration: 0.15)) { st.walkMenu = false } }, openPanels: { st.walkPanelOn.toggle() }, panelsOn: st.walkPanelOn, toggleBar: { st.mainBarOn.toggle(); st.bump() }, barOn: st.mainBarOn)
                        if st.walkPanelOn, HyperLabState.walkPanel != nil { HLWalkPanels(st: st) }
                    }.padding(.top, 74).padding(.trailing, 12)
                }
            }
            // パネルを隠している時：右下に小さな「パネル」ボタンだけ
            .overlay(alignment: .bottomTrailing) {
                if st.panelHidden {
                    Button { withAnimation(.easeInOut(duration: 0.18)) { st.panelHidden = false } } label: {
                        Label("パネル", systemImage: "slider.horizontal.3").font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.75), in: Capsule())
                            .overlay(Capsule().stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                    }.buttonStyle(.plain).foregroundStyle(.secondary).padding(12)
                    .help("パネルを出す（⌘⌥P）")
                }
            }
            if !st.panelHidden { HLScaled(s: CGFloat(st.uiScale), maxH: full.size.height * 0.42) { controls }.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        }
        // ⌘⌥P：パネルを隠す・出す（見えないボタンでキーだけ受ける）
        .background(Button("") { withAnimation(.easeInOut(duration: 0.18)) { st.panelHidden.toggle() } }.keyboardShortcut("p", modifiers: [.command, .option]).opacity(0).allowsHitTesting(false))
        // ⌘＋・⌘−・⌘0：パネルと隅の表示の大きさ
        .background(Button("") { st.zoomUI(1) }.keyboardShortcut("=", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Button("") { st.zoomUI(1) }.keyboardShortcut("+", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Button("") { st.zoomUI(-1) }.keyboardShortcut("-", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Button("") { st.zoomUI(0) }.keyboardShortcut("0", modifiers: .command).opacity(0).allowsHitTesting(false))
        .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255))
        .preferredColorScheme(.dark)
    }
    /// 左の窓をおおう黒
    var paneShade: some View {
        ZStack {
            Color.black.opacity(st.paneBlack ? 1 : 0).animation(.easeOut(duration: st.paneBlack ? HyperLabState.paneOut : HyperLabState.paneIn), value: st.paneBlack)
            SeePane().opacity(st.paneSee ? 1 : 0).animation(st.paneSee ? nil : .easeOut(duration: HyperLabState.seeOut), value: st.paneSee)   // 地図へは、そのまま重ねて入れかえる
        }.allowsHitTesting(false)
    }
    /// 画面の中身が変わる時（ダイブ ⇄ ダイブなし）：前の絵と次の絵を重ねて、スーッと切りかえる
    func fadeSlot(_ k: Int) -> some View {
        ZStack { slot(k).transition(.opacity) }.animation(st.paneBusy ? nil : .easeInOut(duration: 0.7), value: slotKey(k))   // 黒い間は重ねずに入れかえる
    }
    /// その場所に今どの画面が出ているか（slot と同じ決め方）
    func slotKey(_ k: Int) -> Int {
        switch k {
        case 0: return st.paneBoth ? (st.lowSwap ? 7 : 6) : st.diveOverview && st.paneDive ? 3 : 0
        case 1: return st.paneMap2 ? 4 : st.paneWipe ? 5 : st.paneBoth && st.lowSwap ? 6 : st.paneFirst ? 7 : 1
        default: return 2
        }
    }
    @ViewBuilder func slot(_ k: Int) -> some View {
        switch k {
        case 0:
            if st.paneBoth { if st.lowSwap { scenePane } else { bothDivePane } }
            else if st.diveOverview && st.paneDive {
                pane(.right, "自分地図\n自分が真ん中\n進む向きが上", overview: true).id(3)
            } else {
                pane(.left, "【操作側】3D の球（リングを積む）　ドラッグで傾ける・⇧＋横ドラッグで Z-W").id(0)
            }
        case 1:
            if st.paneMap2 { pane(.right, st.ovCaption, overview: true, motion: true).id(4) }
            else if st.paneWipe { pane(.right, "【ダイブ画面】今いる所のまわり　ドラッグで回り込む", wipe: true).id(5) }
            else if st.paneBoth && st.lowSwap { bothDivePane }
            else { scenePane }
        default: pane(.right, "【観察側】4D の超球（球殻を積む）　ドラッグで見る向き").id(2)
        }
    }
    /// 景色の場所：さんぽの景色か、一人称のダイブ画面
    @ViewBuilder var scenePane: some View {
        if st.paneFirst { pane(.right, "【ダイブ 1 人称】自分の目で見る　ドラッグで見回す", wipe: true, wipeFirst: true).id(7) }
        else { walkPane.id(1) }
    }
    /// 「両方」の時のダイブ画面
    var bothDivePane: some View { pane(.right, "【ダイブ画面】今いる所のまわり　ドラッグで回り込む", wipe: true, wipeMain: true).id(6) }
    /// さんぽの景色（さんぽの窓と同じ景色。ここでは見るだけ。歩くのはさんぽの窓・コントローラーで）
    var walkPane: some View {
        ZStack(alignment: .topLeading) {
            WalkScenePane()
            HLHandoffNote(live: st.live)
            Text("【さんぽの景色】今いる所から見た S³（歩くのはさんぽの窓・コントローラーで）").font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                .padding(8).padding(.trailing, 225).allowsHitTesting(false)
            lowSwitch
        }
    }
    /// ダイブしていない間の画面の切りかえ：さんぽの景色・ダイブ画面・両方
    var lowSwitch: some View {
        HStack(spacing: 3) {
            ForEach([(0, "景色"), (1, "ダイブ"), (2, "両方")], id: \.0) { v, n in
                Button { st.lowView = v; st.bump() } label: {
                    Text(n).font(.system(size: 11, weight: .semibold)).foregroundStyle(Color.white.opacity(st.lowView == v ? 1 : 0.7))
                        .frame(width: 44, height: 20).background(st.lowView == v ? Color.white.opacity(0.2) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(st.lowView == v ? 0.55 : 0.12), lineWidth: 1))
                }.buttonStyle(.plain)
            }
            Button { st.lowFirst.toggle(); st.bump() } label: {
                Text("1人称").font(.system(size: 11, weight: .semibold)).foregroundStyle(st.lowFirst ? Color(red: 0.55, green: 1, blue: 0.75) : Color.white.opacity(0.7))
                    .frame(width: 42, height: 20).background(st.lowFirst ? Color.white.opacity(0.2) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
            }.buttonStyle(.plain).help("さんぽの景色の場所を、一人称のダイブ画面にする（ダイブしていない間）")
            if st.lowView == 2 {
                Button { st.lowSwap.toggle(); st.bump() } label: {
                    Image(systemName: "arrow.up.arrow.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(st.lowSwap ? Color(red: 0.55, green: 1, blue: 0.75) : Color.white.opacity(0.7))
                        .frame(width: 26, height: 20).background(st.lowSwap ? Color.white.opacity(0.2) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                }.buttonStyle(.plain).help("さんぽの景色とダイブ画面の上下を入れかえる")
            }
        }
        .help("ダイブしていない間に出す画面。景色：さんぽの景色。ダイブ：景色の場所にダイブ画面。両方：上にダイブ画面、下にさんぽの景色（⇅ で上下を入れかえる。3D の球はその間消える。超球の窓のレイアウトの動画にも入る）")
        .frame(maxWidth: .infinity, alignment: .topTrailing).padding(8)
    }
    func pane(_ side: HyperLabRenderer.Side, _ tag: String, overview: Bool = false, motion: Bool = false, wipe: Bool = false, wipeMain: Bool = false, wipeFirst: Bool = false) -> some View {
        ZStack(alignment: .topLeading) {
            HyperPane(side: side, st: st, overview: overview, motion: motion, wipe: wipe, wipeMain: wipeMain, wipeFirst: wipeFirst)
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    let d = CGSize(width: g.translation.width - last.width, height: g.translation.height - last.height); last = g.translation
                    if side == .left {
                        #if os(macOS)
                        let shift = NSEvent.modifierFlags.contains(.shift)
                        #else
                        let shift = false
                        #endif
                        if shift { st.zw = HyperLabState.norm(st.zw + Double(d.width) * 0.012) }
                        else { st.pitch = HyperLabState.norm(st.pitch + Double(d.height) * 0.012); st.roll = HyperLabState.norm(st.roll + Double(d.width) * 0.012) }
                    } else if motion {                                 // 下の地図：手で回す（離すと元へ戻る）
                        st.ovDragging = true; st.ovDragYaw -= Double(d.width) * 0.008; st.ovDragPitch += Double(d.height) * 0.008
                    } else if (st.diveT > 0.05 || wipe) && !overview {
                        // ズーム中：自分のまわりを回す（鏡に合わせて左右の向きをそろえる）。離すと所定の角度へゆっくり戻る
                        st.diveDragging = true
                        st.diveYawOff += Double(d.width) * 0.008 * (st.diveLive > 0.65 ? 1 : -1); st.divePitchOff = max(-1.4, min(1.4, st.divePitchOff + Double(d.height) * 0.008))
                    } else if st.knifeOn && !overview && !wipe {        // ナイフモード：超球をドラッグすると、その経度から切れていく（見る向きは回さない）
                        st.knifeStart = g.startLocation; st.knifePtr = g.location; st.knifeDown = true
                    } else {
                        st.viewYaw -= Double(d.width) * 0.008; st.viewPitch = max(-1.5, min(1.5, st.viewPitch + Double(d.height) * 0.008))
                    }
                    st.bump()
                }.onEnded { _ in last = .zero; st.diveDragging = false; st.ovDragging = false; st.ovDragT = CACurrentMediaTime(); st.knifeDown = false; st.knifePtr = nil })
                .onContinuousHover { ph in                            // ナイフモード：押さずに指している所に刃の線を出す
                    guard side == .right && !overview && !wipe && !motion else { return }
                    if case .active(let p) = ph, st.knifeOn { st.knifeHover = p; st.bump() } else if st.knifeHover != nil { st.knifeHover = nil; st.bump() }
                }
                .simultaneousGesture(MagnificationGesture().onChanged { k in
                    guard !wipe else { return }
                    if pinch0 == nil { pinch0 = side == .left ? st.leftDist : st.viewDist }
                    let d = max(2.2, min(30, pinch0! / Double(k)))
                    if side == .left { st.leftDist = d } else { st.viewDist = d }
                    st.bump()
                }.onEnded { _ in pinch0 = nil })
            Text(tag).font(.system(size: 11)).padding(.horizontal, 10).padding(.vertical, 5)
                .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
                .padding(8).padding(.trailing, wipe ? 225 : 0).allowsHitTesting(false)
            if overview && !motion { HLNoteLabel(live: st.live) }
            if wipe { lowSwitch }
            if motion {                                                   // 下の地図の切りかえ：消失させる軸を選ぶ
                HStack(spacing: 3) {
                    ForEach([(1, "X", 0), (0, "Y", 1), (2, "Z", 2), (3, "W", 3)], id: \.0) { v, n, k in
                        let c = HyperLabRenderer.axisCol[k], on = st.ovView == v
                        Button { if st.ovView == v { st.ovFlip.toggle() } else { st.ovView = v; st.ovFlip = false } } label: {
                            Text(n).font(.system(size: 12, weight: .bold)).foregroundStyle(Color(red: Double(c.x), green: Double(c.y), blue: Double(c.z)))
                                .frame(width: 24, height: 20).background(on ? Color.white.opacity(0.2) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(Color.white.opacity(on ? 0.55 : 0.12), lineWidth: 1))
                        }.buttonStyle(.plain)
                    }
                    if st.ovView == 3 {
                        Menu {
                            Picker("切り方", selection: $st.ovFx) {
                                Text("おまかせ").tag(0); Text("半分に切る").tag(1); Text("くさびで開く").tag(2); Text("玉ねぎむき").tag(3); Text("ポリゴン崩し").tag(4); Text("回る断面").tag(5)
                            }
                        } label: {
                            Image(systemName: "scissors").font(.system(size: 11, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.8, blue: 0.55))
                                .frame(width: 26, height: 20).background(Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).menuIndicator(.hidden).fixedSize().help("W 消失地図の切り方。おまかせは、ほかの地図と同じく、走りに合わせて切ったり透かしたりする")
                        Button { st.ovZoom.toggle() } label: {
                            Image(systemName: st.ovZoom ? "minus.magnifyingglass" : "plus.magnifyingglass").font(.system(size: 11, weight: .semibold)).foregroundStyle(st.ovZoom ? Color(red: 1, green: 0.75, blue: 0.85) : Color.white.opacity(0.75))
                                .frame(width: 26, height: 20).background(st.ovZoom ? Color.white.opacity(0.2) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                        }.buttonStyle(.plain).help("真ん中へ寄って、赤玉と紫玉が重なっている所を見る")
                    }
                    Button { st.ovShuffle.toggle() } label: {
                        Image(systemName: "shuffle").font(.system(size: 11, weight: .semibold)).foregroundStyle(st.ovShuffle ? Color(red: 0.55, green: 1, blue: 0.75) : Color.white.opacity(0.7))
                            .frame(width: 26, height: 20).background(st.ovShuffle ? Color.white.opacity(0.2) : Color.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).help("消失させる軸を、14 秒ごとにランダムに切りかえる")
                }
                .help("下の地図で消失させる軸を選ぶ。選んでいるボタンをもう一度押すと、w の向きが反転する。Y：w が上で球層は水平。X：w が右で球層は縦。Z：w が手前でアナ極が正面。W：赤と紫が真ん中で重なり、走りに合わせて切ったり透かしたりして中を見せる")
                    .frame(maxWidth: .infinity, alignment: .topTrailing).padding(8)
            }
            if side == .right && !overview && !wipe {
                HLDiveOverlay(live: st.live)                                  // ダイブの最後：さんぽの景色へ溶け込む
                HLAnglesLabel(live: st.live)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading).padding(8).allowsHitTesting(false)
                HLLapLabel(live: st.live, scale: CGFloat(st.uiScale)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)   // 周回（右上の隅に小さく）
                HLPassLabel(live: st.live, scale: CGFloat(st.uiScale))
                HLCoordLabel(live: st.live, scale: CGFloat(st.uiScale)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)   // 走行中の座標（左上）
                HLMeterLabel(live: st.live, scale: CGFloat(st.uiScale)).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)   // 速度メーター（下）
            }
        }
    }
}

#if os(macOS)
/// Mac：Metal 版の試作を別の窓で
enum HyperLabWindow {
    static var window: NSWindow?
    /// 超球の窓とさんぽの窓を入れかえる（⇧⌘J）
    static func flip() {
        if let w = window, w.isKeyWindow, let wk = walkWindow { wk.makeKeyAndOrderFront(nil) } else { open() }
    }
    /// さんぽの窓（球面さんぽ）
    static var walkWindow: NSWindow? { NSApp.windows.first { $0 !== window && $0.isVisible && $0.title.hasPrefix("球面さんぽ") } }
    static func open() {
        if let w = window { w.makeKeyAndOrderFront(nil); return }
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820), styleMask: [.titled, .closable, .resizable, .miniaturizable], backing: .buffered, defer: false)
        w.title = "超球（Metal 版の試作）"; w.isReleasedWhenClosed = false; w.appearance = NSAppearance(named: .darkAqua)
        w.contentView = NSHostingView(rootView: HyperLabView())
        w.setFrameAutosaveName("S3WalkHyperLab"); if !w.setFrameUsingName("S3WalkHyperLab") { w.center() }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: w, queue: .main) { _ in
            window = nil; HyperLabState.walkShut = false
        }
        window = w; w.makeKeyAndOrderFront(nil)
    }
}
#endif
