// アプリの入口：SwiftUI の窓に MTKView（中の景色）と、設定のパネル。`S3Walk --verify` で確かめ、`--bench` で計測だけして終わる
import SwiftUI
import Combine
import AppKit
import MetalKit

@main
struct Main {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--verify") { exit(Verify.run() ? 0 : 1) }
        if args.contains("--bench4k") { Verify.bench(only4K: true); exit(0) }
        if args.contains("--bench") { Verify.bench(); exit(0) }
        if args.contains("--webprobe") { if let d = MTLCreateSystemDefaultDevice(), let r = Renderer(device: d) { Verify.webprobe(r) }; exit(0) }
        if args.contains("--webcmp") { if let d = MTLCreateSystemDefaultDevice(), let r = Renderer(device: d) { exit(Verify.webcmp(r) ? 0 : 1) }; exit(1) }
        if let i = args.firstIndex(of: "--png"), i + 1 < args.count { Verify.png(args[i + 1]); exit(0) }
        if args.contains("--picstats") { Verify.picStats(); exit(0) }
        if args.contains("--mapstats") { Verify.mapStats(); exit(0) }
        if args.contains("--mapbench") { Verify.mapBench(); exit(0) }
        if let i = args.firstIndex(of: "--mappng"), i + 1 < args.count { Verify.mapPNG(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--ref"), i + 2 < args.count { Verify.ref(args[i + 1], args[i + 2]); exit(0) }
        S3WalkApp.main()
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.regular)                 // 素の実行ファイルから起動しても、Dock とメニューのあるアプリに
        NSApp.appearance = NSAppearance(named: .darkAqua)   // いつもダーク（景色の暗い空になじむように。メニュー・浮いた地図の窓も）
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ s: NSApplication) -> Bool { true }
}

/// アプリの状態：描く仕組み（Renderer）と、パネル・表示。パネルの値は Renderer の設定をそのまま読み書きする
final class AppModel: ObservableObject {
    let r: Renderer
    /// 左上の表示と知らせは別の入れ物に（0.5 秒ごとの書きかえで、インスペクターなど画面ぜんぶを作り直さないように）
    let hudState = HUDState()
    /// パネルのドック（並び・たたみ）
    let dock = DockState()
    /// Tab で全部隠す前の、パネルと地図の置き方（もう一度 Tab で戻す）
    private var beforeHide: (panel: Bool, map: MapMode)?
    /// 浮いたパネルの窓（ドックの floating と同じ組）
    private var floatWindows: [UUID: NSPanel] = [:]
    private var dockSub: AnyCancellable?
    private var floatsHidden = false
    @Published var showHUD = true
    @Published var showPanel = true
    @Published var help = false
    @Published var mapMode: MapMode = .docked
    lazy var mapRenderer = MapRenderer(world: r, slot: 0)
    lazy var mapRenderer2 = MapRenderer(world: r, slot: 1)
    lazy var s2Renderer = MapRenderer(world: r, slot: 2)
    func renderer(_ slot: Int) -> MapRenderer { slot == 0 ? mapRenderer : slot == 1 ? mapRenderer2 : s2Renderer }
    private var mapPanel: NSPanel?
    private var noticeT = 0.0
    private var lastSaved = ""

    init() {
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { fatalError("Metal が使えない") }
        self.r = r
        Store.restore(r)
        r.say = { [weak self] m in DispatchQueue.main.async { self?.say(m) } }
        r.onPad = { [weak self] k in self?.pad(k) }
        restoreMapMode()
        dockSub = dock.$floating.sink { [weak self] _ in DispatchQueue.main.async { self?.syncFloating() } }
        // 起動した時やアプリに戻った時も、浮いた窓を出し直す（起動の途中で作った窓は、アプリが前に出る前に隠れてしまうので）
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.syncFloating() }
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.syncFloating() }
        }
        if CommandLine.arguments.contains("--demo-float") {      // 確かめ用：球層と見え方をタブでまとめて浮かせる
            dock.reset(); dock.floatPanel(.shell); if let g = dock.floating.first { dock.addTab(.view, to: g.id) }
        }
    }
    func say(_ m: String) { hudState.notice = m; noticeT = CACurrentMediaTime() }
    /// Tab：パネル（ドック・浮いた窓）と地図を全部隠す／元に戻す（Photoshop と同じ）
    func toggleAllPanels() {
        if let b = beforeHide {
            beforeHide = nil; showPanel = b.panel; setMap(b.map); floatsHidden = false; syncFloating()
        } else if showPanel || mapMode != .hidden || !dock.floating.isEmpty {
            beforeHide = (showPanel, mapMode); showPanel = false; setMap(.hidden); floatsHidden = true; syncFloating()
        } else {
            showPanel = true                                    // 何も出ていない時は、ドックを出す
        }
    }
    /// 浮いたパネルの窓を、ドックの floating に合わせて作る・閉じる
    func syncFloating() {
        let ids = Set(dock.floating.map(\.id))
        for (gid, w) in floatWindows where !ids.contains(gid) { floatWindows[gid] = nil; w.delegate = nil; w.close() }
        for g in dock.floating {
            let w = floatWindows[g.id] ?? makeFloatWindow(g)
            w.title = g.tabs.map(\.title).joined(separator: "・")
            if floatsHidden { w.orderOut(nil) } else if NSApp.isActive || !w.isVisible { w.orderFront(nil) }
        }
    }
    private func makeFloatWindow(_ g: FloatGroup) -> NSPanel {
        let main = NSApp.windows.first { $0.isVisible && !($0 is NSPanel) }
        let n = CGFloat(floatWindows.count)
        let fr = dock.frames[g.id] ?? CGRect(x: (main?.frame.maxX ?? 1200) - 700 - 30 * n, y: (main?.frame.maxY ?? 900) - 520 - 30 * n, width: 330, height: 440)
        let p = NSPanel(contentRect: fr, styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true; p.hidesOnDeactivate = true; p.becomesKeyOnlyIfNeeded = true
        p.isReleasedWhenClosed = false; p.collectionBehavior = [.fullScreenAuxiliary, .managed]
        p.appearance = NSAppearance(named: .darkAqua)
        p.setFrame(fr, display: false)
        p.contentView = NSHostingView(rootView: FloatGroupView(model: self, dock: dock, gid: g.id).preferredColorScheme(.dark))
        let gid = g.id
        for name in [NSWindow.didMoveNotification, NSWindow.didEndLiveResizeNotification] {
            NotificationCenter.default.addObserver(forName: name, object: p, queue: .main) { [weak self, weak p] _ in
                guard let self, let p else { return }
                self.dock.frames[gid] = p.frame; self.dock.save()
            }
        }
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { [weak self] _ in
            guard let self, self.floatWindows[gid] != nil else { return }   // 赤い × で閉じた時：中のパネルをドックへ戻す
            self.floatWindows[gid] = nil
            self.dock.dockGroup(gid)
        }
        floatWindows[g.id] = p
        dock.frames[g.id] = fr
        return p
    }
    /// コントローラーのボタン
    func pad(_ k: String) {
        switch k {
        case "A": r.addMark()
        case "B": r.walking.toggle(); r.roaming = false
        case "X": r.roaming.toggle(); r.walking = false; say(r.roaming ? "縦横無尽：どこへ進んでも、いつか戻ってくる" : "縦横無尽をやめた")
        case "Y": r.padY()
        case "R3": r.levelView()
        case "up": r.set.shellRange = min(25.15, r.set.shellRange + 0.5)
        case "down": r.set.shellRange = max(0.3, r.set.shellRange - 0.5)
        case "menu": showPanel.toggle()
        default: break
        }
        changed()
    }
    /// 地図の置き方を変える。浮かせる時は、キーを奪わない浮いた窓（NSPanel のパレット）に地図を入れる
    func setMap(_ m: MapMode) {
        guard m != mapMode else { return }
        if mapMode == .floating { mapPanel?.close(); mapPanel = nil }
        mapMode = m
        UserDefaults.standard.set(m.rawValue, forKey: "s3walk.mapMode")
        if m == .floating {
            let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 820),
                            styleMask: [.titled, .closable, .resizable, .utilityWindow, .nonactivatingPanel, .fullSizeContentView], backing: .buffered, defer: false)
            p.title = "S³ の地図"; p.isFloatingPanel = true; p.hidesOnDeactivate = true; p.becomesKeyOnlyIfNeeded = true
            p.titlebarAppearsTransparent = true
            p.collectionBehavior = [.fullScreenAuxiliary, .managed]
            p.isReleasedWhenClosed = false
            p.setFrameAutosaveName("S3WalkMapPanel")
            p.appearance = NSAppearance(named: .darkAqua)
            p.contentView = NSHostingView(rootView: MapsArea(model: self, topInset: 28).preferredColorScheme(.dark))
            if p.frame.origin == .zero, let main = NSApp.mainWindow { p.setFrameTopLeftPoint(NSPoint(x: main.frame.maxX - 580, y: main.frame.maxY - 60)) }
            NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: p, queue: .main) { [weak self] _ in
                guard let self, self.mapMode == .floating, self.mapPanel === p else { return }
                self.mapPanel = nil; self.mapMode = .hidden; UserDefaults.standard.set(MapMode.hidden.rawValue, forKey: "s3walk.mapMode")
            }
            mapPanel = p; p.orderFront(nil)
        }
    }
    func restoreMapMode() {
        if let s = UserDefaults.standard.string(forKey: "s3walk.mapMode"), let m = MapMode(rawValue: s), m != .docked { DispatchQueue.main.async { self.setMap(m) } }
    }
    /// パネルの部品と設定をつなぐ
    func b<T>(_ kp: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.r.set[keyPath: kp] }, set: { self.objectWillChange.send(); self.r.set[keyPath: kp] = $0 })
    }
    func rb<T>(_ kp: ReferenceWritableKeyPath<Renderer, T>) -> Binding<T> {
        Binding(get: { self.r[keyPath: kp] }, set: { self.objectWillChange.send(); self.r[keyPath: kp] = $0 })
    }
    func changed() { objectWillChange.send() }
    /// 0.5 秒ごと：知らせを消す・3 秒ごとに、変わっていたら保存
    private var lastSaveT = 0.0
    func tick() {
        let now = CACurrentMediaTime()
        if !hudState.notice.isEmpty && now - noticeT > 4 { hudState.notice = "" }
        guard now - lastSaveT > 3 else { return }
        lastSaveT = now
        let snap = Store.snapshot(r)
        let key = (try? JSONSerialization.data(withJSONObject: snap, options: [.sortedKeys])).map { String(decoding: $0, as: UTF8.self) } ?? ""
        if key != lastSaved { lastSaved = key; UserDefaults.standard.set(snap, forKey: Store.key) }
    }
}

struct S3WalkApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject var model = AppModel()
    var body: some Scene {
        WindowGroup("球面さんぽ") {
            ContentView(model: model).frame(minWidth: 720, minHeight: 440).preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
            // メニューのキーは表示のため（押したキーは景色の窓が先に受ける）
            CommandMenu("歩く") {
                Toggle("歩き続ける", isOn: model.rb(\.walking)).keyboardShortcut("k", modifiers: [])
                Toggle("縦横無尽", isOn: model.rb(\.roaming)).keyboardShortcut("u", modifiers: [])
                Divider()
                Button("ここに目印を置く") { model.r.addMark(); model.changed() }.keyboardShortcut("m", modifiers: [])
                Button("アナ極へ戻る") { model.r.resetNorth(); model.changed() }.keyboardShortcut("r", modifiers: [])
                Button("見回しを戻す") { model.r.cam.hy = 0; model.r.cam.hp = 0 }.keyboardShortcut("h", modifiers: [])
                Button("見回した向きへ進む") { model.r.cam.headGo() }.keyboardShortcut(.return, modifiers: [])
            }
            CommandMenu("地図") {
                Button("景色だけ") { model.setMap(.hidden) }.keyboardShortcut("1", modifiers: .command)
                Button("地図を並べる") { model.setMap(.docked) }.keyboardShortcut("2", modifiers: .command)
                Button("地図を浮かせる") { model.setMap(.floating) }.keyboardShortcut("3", modifiers: .command)
                Toggle("地図を景色の左に", isOn: model.b(\.mapLeft)).keyboardShortcut("4", modifiers: .command)
                Divider()
                Toggle("自分を真ん中に", isOn: model.b(\.mapFollow))
                Button("地図を元の向きに") { model.mapRenderer.home(); model.mapRenderer2.home(); model.s2Renderer.home() }
                Toggle("2 枚目の地図", isOn: model.b(\.map2On))
            }
            CommandGroup(after: .sidebar) {
                Toggle("設定のパネル", isOn: Binding(get: { model.showPanel }, set: { model.showPanel = $0 })).keyboardShortcut("i", modifiers: [.command, .option])
                Button("パネルと地図を全部隠す／戻す") { model.toggleAllPanels() }.keyboardShortcut(.tab, modifiers: [])
                Button("パネルをすべてたたむ") { model.dock.collapsed = Set(PanelID.allCases) }
                Button("パネルをすべてひらく") { model.dock.collapsed = [] }
                Button("パネルの並びを元に戻す") { model.dock.reset() }
                Toggle("fps などの表示", isOn: Binding(get: { model.showHUD }, set: { model.showHUD = $0 }))
                Divider()
            }
        }
    }
}

let HELP = """
W/S 前・後　A/D 右・左　Q/E 上・下（Shift で 3 倍）　K 歩き続ける　U 縦横無尽
←→ 方位　↑↓ 仰角　ドラッグ・2 本指 見回し（Shift＋ドラッグ 進む向き）　Enter 見回した向きへ進む　H 見回しを戻す
R アナ極へ戻る　M ここに目印を置く　F 足あと　L 球層　T 立体の殻　B 網目　G 壮大　J 軽い線　Y 赤道の膜
O 向きの赤い点　P 目印の見せ方（玉→絵→色の点→なし）　X 地図の軸　C 線の見え方（くっきり⇄やわらか）　- / = 殻の見える距離　[ / ] 描く細かさ　V 60fps 前後 ⇄ 画面の速さ
Space 設定のパネル　Tab パネルと地図を全部隠す／戻す　I 表示　? この説明　⌘1・⌘2・⌘3 地図を隠す・並べる・浮かせる　⌃⌘F 全画面
"""

/// 地図の置き方：隠す・景色の横に並べる・浮いた窓（Photoshop のパレットのように、いつも前に）
enum MapMode: String, CaseIterable { case hidden, docked, floating }

struct ContentView: View {
    @ObservedObject var model: AppModel
    var body: some View {
        // 地図は景色の右か左に（地図 1 の右上のボタン・インスペクター・メニューで入れかえ）
        HSplitView {
            if model.mapMode == .docked && model.r.set.mapLeft {
                MapsArea(model: model).frame(minWidth: 260, idealWidth: 520)
            }
            ZStack(alignment: .topLeading) {
                MetalView(model: model)
                HUDView(model: model)
            }
            .frame(minWidth: 360)
            if model.mapMode == .docked && !model.r.set.mapLeft {
                MapsArea(model: model).frame(minWidth: 260, idealWidth: 520)
            }
        }
        .inspector(isPresented: $model.showPanel) {
            DockColumn(model: model, dock: model.dock).inspectorColumnWidth(min: 280, ideal: 330, max: 480)
        }
        .toolbar { MainToolbar(model: model) }
        .navigationTitle("球面さんぽ")
        .navigationSubtitle("3 次元球面 S³ を進む")
    }
}

final class HUDState: ObservableObject {
    @Published var text = ""
    @Published var notice = ""
}

struct HUDView: View {
    @ObservedObject var model: AppModel
    var body: some View { HUDInner(model: model, hud: model.hudState) }
}
struct HUDInner: View {
    @ObservedObject var model: AppModel
    @ObservedObject var hud: HUDState
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if model.showHUD {
                VStack(alignment: .leading, spacing: 6) {
                    Text(hud.text)
                    if model.help { Text(HELP).foregroundStyle(.secondary) } else { Text("? で操作の説明").foregroundStyle(.secondary) }
                }
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                .padding(8).background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 6))
            }
            if !hud.notice.isEmpty {
                Text(hud.notice).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(.black.opacity(0.55), in: Capsule())
            }
        }
        .padding(10).allowsHitTesting(false)
    }
}

/// 地図の場所：1 枚目と 2 枚目（ウェブ版の真ん中と左上）を上下に。境目はドラッグで動かせる
struct MapsArea: View {
    @ObservedObject var model: AppModel
    var topInset: CGFloat = 0
    var body: some View {
        VSplitView {
            if model.r.set.s2On { OneMap(model: model, slot: 2, topInset: topInset) }
            OneMap(model: model, slot: 0, topInset: model.r.set.s2On ? 0 : topInset)
            if model.r.set.map2On { OneMap(model: model, slot: 1, topInset: 0) }
        }
    }
}
/// 地図 1 枚：隅に、見方（ふつう・自分中心）・範囲（全体・今いる所・写る所）・元の向き・浮かせる（ウェブ版の窓の右下の切り替え）
/// 地図の右上：軸 x・y・z・w が地図に写る長さの割合（ウェブ版の axlen と同じ）。自分中心では歩くと変わる
struct AxisLengths: View {
    let map: MapRenderer
    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.15)) { _ in
            let L = map.axisLengths()
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 3) {
                        Text(["x", "y", "z", "w"][i]).italic().foregroundStyle(Color(red: Double(AXIS_RGB[i].x), green: Double(AXIS_RGB[i].y), blue: Double(AXIS_RGB[i].z)))
                        Text("\(Int((L[i] * 100).rounded()))%").monospacedDigit().foregroundStyle(.white.opacity(0.85))
                    }
                }
            }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.35), in: Capsule())
            .help("軸が地図に写る長さ（4 次元の軸のうち、3 次元に見えている割合）。自分中心では、今いる所の向きの軸ほど自分の方（奥行き）を向いて短くなる")
        }
    }
}

struct OneMap: View {
    @ObservedObject var model: AppModel
    let slot: Int
    var topInset: CGFloat
    var body: some View {
        let follow = slot == 1 ? model.b(\.map2Follow) : model.b(\.mapFollow)
        let range = slot == 1 ? model.b(\.map2Range) : model.b(\.mapRange)
        ZStack {
            MapPane(model: model, slot: slot)
            VStack {
                HStack {
                    Text(slot == 0 ? "S³ の地図" : slot == 1 ? "地図 2" : "S² の仲間（同じ操作を球面で）").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.8))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.35), in: Capsule())
                    Spacer()
                    if slot != 2 && model.r.set.mapAxes { AxisLengths(map: model.renderer(slot)) }
                    HStack(spacing: 6) {
                        Button { model.renderer(slot).home() } label: { Image(systemName: "scope") }.help("地図を元の向きに（ダブルクリックでも）")
                        if slot == 0 {
                            if model.mapMode == .docked {
                                Button { model.r.set.mapLeft.toggle(); model.changed() } label: { Image(systemName: "arrow.left.arrow.right") }.help(model.r.set.mapLeft ? "地図を景色の右へ" : "地図を景色の左へ")
                                Button { model.setMap(.floating) } label: { Image(systemName: "macwindow.on.rectangle") }.help("地図を浮いた窓に切り離す")
                            } else {
                                Button { model.setMap(.docked) } label: { Image(systemName: "rectangle.split.2x1") }.help("地図を景色の横に戻す")
                            }
                            Button { model.r.set.map2On.toggle(); model.changed() } label: { Image(systemName: model.r.set.map2On ? "rectangle.split.1x2.fill" : "rectangle.split.1x2") }.help("2 枚目の地図を出す・隠す")
                            Button { model.r.set.s2On.toggle(); model.changed() } label: { Image(systemName: model.r.set.s2On ? "circle.circle.fill" : "circle.circle") }.help("S² の仲間を出す・隠す")
                        }
                    }
                    .buttonStyle(.borderless).padding(5).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
                }
                Spacer()
                if slot != 2 { HStack {
                    Spacer()
                    Picker("見方", selection: follow) { Text("ふつう").tag(false); Text("自分中心").tag(true) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().help("ふつう：4 次元の向きを決めて写す／自分中心：自分を真ん中に、体の向きのまま写す")
                    Picker("範囲", selection: range) { Text("全体").tag(0); Text("今いる所").tag(1); Text("写る所").tag(2) }
                        .pickerStyle(.segmented).labelsHidden().fixedSize().help("球層の殻：全体／今いる所（自分の殻ははっきり、となりはうっすら）／写る所（中の景色に写っている所だけ）")
                }
                .controlSize(.small).padding(5).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7)) }
            }
            .padding(8).padding(.top, topInset)
        }
        .frame(minHeight: 160)
    }
}

struct MainToolbar: ToolbarContent {
    @ObservedObject var model: AppModel
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Toggle(isOn: model.rb(\.walking)) { Label("歩き続ける", systemImage: "figure.walk") }.help("歩き続ける（K）")
            Toggle(isOn: model.rb(\.roaming)) { Label("縦横無尽", systemImage: "wind") }.help("縦横無尽：向きがゆっくり変わりながら歩く（U）")
            Button { model.r.addMark(); model.changed() } label: { Label("目印を置く", systemImage: "mappin.and.ellipse") }.help("ここに目印を置く（M）")
            Button { model.r.resetNorth(); model.say("アナ極に戻った"); model.changed() } label: { Label("アナ極へ", systemImage: "house") }.help("アナ極へ戻る（R）")
        }
        ToolbarItem(placement: .principal) {
            Picker("地図", selection: Binding(get: { model.mapMode }, set: { model.setMap($0) })) {
                Label("景色だけ", systemImage: "rectangle").tag(MapMode.hidden)
                Label("地図を並べる", systemImage: "rectangle.split.2x1").tag(MapMode.docked)
                Label("地図を浮かせる", systemImage: "macwindow.on.rectangle").tag(MapMode.floating)
            }
            .pickerStyle(.segmented).help("S³ の地図：隠す・景色の横に並べる・浮いた窓に")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.showPanel.toggle() } label: { Label("設定", systemImage: "sidebar.right") }.help("設定のインスペクター（Space）")
        }
    }
}

struct MetalView: NSViewRepresentable {
    let model: AppModel
    func makeNSView(context: Context) -> WalkView {
        let v = WalkView(frame: .zero, device: model.r.device)
        v.model = model
        v.setup()
        return v
    }
    func updateNSView(_ v: WalkView, context: Context) { v.applyScale() }
}

/// 中の景色の上の 8 つの極（ウェブ版の poleLabels・placeDots）：直径 12 の色の点（暗いふち、遠いほど小さく 5 まで）と、右に「名前 距離」。
///   点が重なる時は手前の点だけ。名前はアナ極を先に、あとは手前から順に、点の右・左・上・下で空いている所へ（どこも空いていなければ隠す）
final class PoleOverlay: NSView {
    private var dots: [CALayer] = [], labs: [CATextLayer] = []
    override var isFlipped: Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ ls: [Renderer.PoleLab]) {
        guard let root = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let sc = window?.backingScaleFactor ?? 2, font = NSFont.boldSystemFont(ofSize: 11)
        while dots.count < 8 {
            let d = CALayer(); d.borderWidth = 2; d.borderColor = NSColor(srgbRed: 8 / 255, green: 12 / 255, blue: 28 / 255, alpha: 0.85).cgColor
            let t = CATextLayer(); t.contentsScale = sc; t.font = font; t.fontSize = 11; t.alignmentMode = .left
            t.shadowColor = NSColor.black.cgColor; t.shadowOpacity = 1; t.shadowRadius = 2; t.shadowOffset = .zero
            root.addSublayer(d); root.addSublayer(t); dots.append(d); labs.append(t)
        }
        let w = bounds.width, h = bounds.height
        struct It { var k: Int; var x: CGFloat; var y: CGFloat; var lab: Renderer.PoleLab }
        var items = ls.prefix(8).enumerated().map { It(k: $0.offset, x: CGFloat(0.5 + 0.5 * $0.element.x) * w, y: CGFloat(0.5 - 0.5 * $0.element.y) * h, lab: $0.element) }
        items.sort { $0.lab.d < $1.lab.d }
        for i in 0..<8 { dots[i].isHidden = true; labs[i].isHidden = true }
        var shown: [It] = []
        for (z, it) in items.enumerated() {
            let d = dots[it.k], col = NSColor(srgbRed: CGFloat(it.lab.col.x), green: CGFloat(it.lab.col.y), blue: CGFloat(it.lab.col.z), alpha: 1).cgColor
            d.zPosition = CGFloat(100 - z); labs[it.k].zPosition = CGFloat(200 - z)
            if shown.contains(where: { hypot($0.x - it.x, $0.y - it.y) < 9 }) { continue }
            let q = min(1, it.lab.d / (Double.pi / 2)), r = CGFloat(12 - 7 * q * q * (3 - 2 * q))   // 距離 0 で 12、90° で 5
            d.isHidden = false; d.backgroundColor = col; d.cornerRadius = r / 2; d.frame = CGRect(x: it.x - r / 2, y: it.y - r / 2, width: r, height: r)
            shown.append(it)
        }
        var rects: [CGRect] = []
        for it in items.sorted(by: { ($0.lab.isN ? 0 : 1, $0.lab.d) < ($1.lab.isN ? 0 : 1, $1.lab.d) }) {
            let t = labs[it.k], bw = ceil((it.lab.name as NSString).size(withAttributes: [.font: font]).width) + 2, bh: CGFloat = 14
            for (dx, dy) in [(CGFloat(8), CGFloat(-8)), (-8 - bw, -8), (-bw / 2, -23), (-bw / 2, 8)] {
                let r = CGRect(x: it.x + dx, y: it.y + dy, width: bw, height: bh)
                if r.minX < 0 || r.maxX > w || r.minY < 0 || r.maxY > h { continue }
                if rects.contains(where: { $0.intersects(r) }) { continue }
                if shown.contains(where: { $0.k != it.k && $0.x > r.minX - 4 && $0.x < r.maxX + 4 && $0.y > r.minY - 4 && $0.y < r.maxY + 4 }) { continue }
                t.isHidden = false; t.string = it.lab.name
                t.foregroundColor = NSColor(srgbRed: CGFloat(it.lab.col.x), green: CGFloat(it.lab.col.y), blue: CGFloat(it.lab.col.z), alpha: 1).cgColor
                t.frame = r.insetBy(dx: 0, dy: -1); rects.append(r); break
            }
        }
        CATransaction.commit()
    }
}

/// 中の景色の窓。キーとマウスを受けて、Renderer に渡す
final class WalkView: MTKView {
    weak var model: AppModel?
    var renderer: Renderer { model!.r }
    private var dragLast: NSPoint?
    private var keyMonitor: Any?

    func setup() {
        delegate = renderer
        colorPixelFormat = .rgba16Float
        colorspace = CGColorSpace(name: CGColorSpace.extendedSRGB)   // 0〜1 はブラウザと同じ色、1 より上は EDR の明るさ
        (layer as? CAMetalLayer)?.wantsExtendedDynamicRangeContent = true
        layer?.isOpaque = true                                           // 宇宙の時はアルファに「透けて残った割合」を書くので、窓は透かさない
        let po = PoleOverlay(frame: bounds); po.autoresizingMask = [.width, .height]; addSubview(po)
        renderer.onPoles = { [weak po] ls in po?.update(ls) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in self?.renderer.prewarm() }
        preferredFramesPerSecond = 60
        framebufferOnly = true
        autoResizeDrawable = false
        renderer.onStats = { [weak self] r in self?.stats(r) }
        // パネルの部品を押した後も、キーはいつも景色の操作に（⌘・⌃ の付いたキーはメニューへ）
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { [weak self] e in
            guard let self, self.window?.isKeyWindow == true else { return e }
            if e.type == .flagsChanged { self.flags(e); return e }
            if self.window?.firstResponder is NSText { return e }   // 数字を入力している間は、キーを入力欄へ（景色の操作にしない）
            if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) { self.renderer.keys.removeAll(); return e }
            if e.type == .keyDown { self.key(e) } else { self.renderer.keys.remove(e.keyCode) }
            return nil
        }
    }
    deinit { if let m = keyMonitor { NSEvent.removeMonitor(m) } }
    override var acceptsFirstResponder: Bool { true }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        window?.collectionBehavior.insert(.fullScreenPrimary)
        if let w = window {
            NotificationCenter.default.addObserver(forName: NSWindow.didResignKeyNotification, object: w, queue: .main) { [weak self] _ in self?.renderer.keys.removeAll() }
            NotificationCenter.default.addObserver(forName: NSWindow.didChangeScreenNotification, object: w, queue: .main) { [weak self] _ in self?.applyScale() }
        }
        applyScale()
    }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); applyScale() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); applyScale() }

    /// 描く細かさ：窓の画素 × 倍率（1 で画面の画素そのまま。LG の全画面なら 4096×2304）。コマの速さも合わせる
    func applyScale() {
        guard model != nil else { return }
        let bs = window?.backingScaleFactor ?? 2, sc = renderer.set.scale
        let sz = CGSize(width: max(1, (bounds.width * bs * sc).rounded()), height: max(1, (bounds.height * bs * sc).rounded()))
        if sz != drawableSize { drawableSize = sz }
        // 60 fps の時は、画面の速さを割り切れる速さのうち 60 以上でいちばん遅いもの（144Hz → 72、120Hz → 60、60Hz → 60）。
        //   60 のままだと 144Hz の画面では 3 コマに 1 回（48 fps）になる
        let hz = max(60, window?.screen?.maximumFramesPerSecond ?? 60)
        let fps = renderer.set.fps60 ? hz / max(1, hz / 60) : hz
        if preferredFramesPerSecond != fps { preferredFramesPerSecond = fps }
    }

    /// 細かさの自動：実際の fps が目標（60 など）に 2 回続けて届かなければ粗く、4 回（2 秒）続けて届いていれば少しずつ細かく（いちばん細かいのは 1）。
    ///   GPU の時間では決めない（軽いと Mac が GPU を遅くするので、時間が長く見えて、細かさを下げ続けてしまう）
    private var okStreak = 0, badStreak = 0, cap = 1.0, capT = CACurrentMediaTime()
    let logFPS = CommandLine.arguments.contains("--log")
    func autoScale(_ r: Renderer) {
        guard r.set.autoQ, r.fps > 0 else { return }
        let target = Double(preferredFramesPerSecond), now = CACurrentMediaTime(), budget = 1000 / target
        if now - capT > 30 { cap = 1.0 }                        // 上限は 30 秒で忘れる（場面が軽くなったら、また細かく）
        var sc = r.set.scale
        if r.fps < target * 0.9 {
            okStreak = 0; badStreak += 1
            if badStreak >= 2 { badStreak = 0; cap = max(0.5, sc - 0.02); capT = now; sc = max(0.5, sc * 0.9) }
        } else {
            badStreak = 0
            if r.fps >= target * 0.97 { okStreak += 1 }
            // 細かくするのは、4 秒続けて間に合っていて、細かくしても GPU の時間が 1 コマの 7 割に収まりそうな時だけ（上げ下げをくり返すと、そのたびに引っかかる）
            let up = min(1, cap, sc * 1.08)
            if okStreak >= 8 && sc < min(1, cap) && r.gpuMs * (up / sc) * (up / sc) < budget * 0.7 { sc = up; okStreak = 0 }
        }
        if abs(sc - r.set.scale) > 0.005 { r.set.scale = sc; applyScale() }
    }

    func stats(_ r: Renderer) {
        let head = Double(window?.screen?.maximumExtendedDynamicRangeColorComponentValue ?? 1)
        if abs(head - r.edrHead) > 0.01 { r.edrHead = head; model?.changed() }
        autoScale(r)
        applyScale()
        if logFPS { print(String(format: "fps %.1f / %d  最長 %.1f ms  GPU %.2f ms  %d×%d  細かさ %.2f", r.fps, preferredFramesPerSecond, r.maxGap, r.gpuMs, Int(drawableSize.width), Int(drawableSize.height), r.set.scale)); fflush(stdout) }
        let p = r.cam.w.p, fromN = acos(max(-1, min(1, p.w)))
        let mode = [r.pathMode == .spiral ? "螺旋" : r.pathMode == .ring ? "回る輪" : r.roaming ? "縦横無尽" : r.walking ? "歩き続ける" : "", r.set.shell ? (r.set.shellSolid ? "球層（立体）" : "球層") : "", r.set.lite ? "軽い線" : ""].filter { !$0.isEmpty }.joined(separator: "・")
        let UR = r.set.uniR, big = UR >= 10, opp = big ? String(format: "πR ≈ %.0f", Double.pi * UR) : String(format: "π ≈ %.2f", Double.pi * UR)
        let s = String(format: "%.0f fps（目標 %d、いちばん長い間 %.0f ms）　GPU %.1f ms/コマ　%d×%d（細かさ %.0f%%%@）\nアナ極から %@（%@ で反対側）　進んだ距離 %@（%.2f 周）\n方位 %.0f°　仰角 %.0f°　見回し %.0f° / %.0f°　%@",
                       r.fps, preferredFramesPerSecond, r.maxGap, r.gpuMs, Int(drawableSize.width), Int(drawableSize.height), r.set.scale * 100, r.set.autoQ ? "・自動" : "",
                       String(format: big ? "%.0f" : "%.2f", fromN * UR), opp, String(format: big ? "%.0f" : "%.2f", r.journey.dist * UR), r.journey.dist / (2 * Double.pi),
                       r.cam.az, r.cam.el, r.cam.hy, r.cam.hp, mode)
        DispatchQueue.main.async { if self.model?.hudState.text != s { self.model?.hudState.text = s }; self.model?.tick() }
    }

    // ---- キー ----
    func key(_ e: NSEvent) {
        renderer.shiftFast = e.modifierFlags.contains(.shift)
        if e.isARepeat { return }
        renderer.keys.insert(e.keyCode)
        let r = renderer
        var touched = true
        switch e.charactersIgnoringModifiers?.lowercased() {
        case " ": model?.showPanel.toggle()
        case "\t": model?.toggleAllPanels()
        case "k": r.walking.toggle(); r.roaming = false; r.pathMode = .none
        case "u": r.roaming.toggle(); r.walking = false; r.pathMode = .none; model?.say(r.roaming ? "縦横無尽：どこへ進んでも、いつか戻ってくる" : "縦横無尽をやめた")
        case "\r": r.cam.headGo()
        case "h": r.cam.hy = 0; r.cam.hp = 0
        case "r": r.resetNorth(); model?.say("アナ極に戻った")
        case "m": r.addMark()
        case "f": r.set.foot.toggle()
        case "l": r.set.shell.toggle()
        case "t": r.set.shellSolid.toggle()
        case "b": r.set.shellBare.toggle()
        case "g": r.set.grand.toggle()
        case "j": r.set.lite.toggle()
        case "y": r.set.eq.toggle()
        case "o": r.set.orient.toggle()
        case "n": r.set.space.toggle(); model?.say(r.set.space ? "背景：宇宙（暗闇・星・天の川）" : "背景：深海（青灰色のもや）")
        case "c": r.set.lineCrisp.toggle(); model?.say(r.set.lineCrisp ? "線：くっきり" : "線：やわらか（標準）")
        case "x": r.set.mapAxes.toggle()
        case "p": r.set.mk = (r.set.mk + 1) % 4; model?.say(["目印：玉", "目印：絵（絵文字）", "目印：色の点", "目印：なし"][r.set.mk])
        case "v": r.set.fps60.toggle(); applyScale()
        case "-": r.set.shellRange = max(0.3, r.set.shellRange - 0.5)
        case "=", "+": r.set.shellRange = min(25.15, r.set.shellRange + 0.5)
        case "[": r.set.autoQ = false; r.set.scale = max(0.3, r.set.scale - 0.1); applyScale()
        case "]": r.set.autoQ = false; r.set.scale = min(1.0, r.set.scale + 0.1); applyScale()
        case "i": model?.showHUD.toggle()
        case "?", "/": model?.help.toggle()
        default: touched = false
        }
        if touched { model?.changed() }
    }
    func flags(_ e: NSEvent) {
        renderer.shiftFast = e.modifierFlags.contains(.shift)
        if e.modifierFlags.contains(.command) { renderer.keys.removeAll() }   // ⌘ を押している間は keyUp が来ないことがある
    }

    // ---- マウス：ドラッグで見回し（Shift＋ドラッグで進む向き）。0.3°/点（ウェブ版と同じ）。2 本指のスクロールでも見回し ----
    override func mouseDown(with e: NSEvent) { dragLast = e.locationInWindow; window?.makeFirstResponder(self) }
    override func mouseUp(with e: NSEvent) { dragLast = nil }
    override func mouseDragged(with e: NSEvent) {
        guard let last = dragLast else { return }
        let p = e.locationInWindow; dragLast = p
        look(Double(p.x - last.x) * 0.3, Double(p.y - last.y) * 0.3, steer: e.modifierFlags.contains(.shift))   // AppKit の y は上向き
    }
    override func scrollWheel(with e: NSEvent) {
        let k = e.hasPreciseScrollingDeltas ? 0.15 : 3.0
        look(-Double(e.scrollingDeltaX) * k, Double(e.scrollingDeltaY) * k, steer: e.modifierFlags.contains(.shift))
    }
    func look(_ dx: Double, _ dy: Double, steer: Bool) {
        let r = renderer
        if steer { r.cam.az += dx; r.cam.el += dy } else { r.cam.hy += dx; r.cam.hp += dy }
        r.cam.clampAngles()
    }
}
