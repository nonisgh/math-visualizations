// アプリの入口：SwiftUI の窓に MTKView（中の景色）と、設定のパネル。`S3Walk --verify` で確かめ、`--bench` で計測だけして終わる
import SwiftUI
import Combine
import AppKit
import MetalKit

/// 軸の名前の書体（KaTeX の数式用の斜体）を使えるようにする。アプリの中（Resources）か、作っている時はソースの横の Fonts から
func registerFonts() {
    let src = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Fonts/KaTeX_Math-Italic.ttf")
    for u in [Bundle.main.url(forResource: "KaTeX_Math-Italic", withExtension: "ttf"), src].compactMap({ $0 }) where FileManager.default.fileExists(atPath: u.path) {
        CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil); return
    }
}

@main
struct Main {
    static func main() {
        registerFonts()
        let args = CommandLine.arguments
        if args.contains("--verify") { exit(Verify.run() ? 0 : 1) }
        if args.contains("--bench4k") { Verify.bench(only4K: true); exit(0) }
        if args.contains("--bench") { Verify.bench(); exit(0) }
        if args.contains("--webprobe") { if let d = MTLCreateSystemDefaultDevice(), let r = Renderer(device: d) { Verify.webprobe(r) }; exit(0) }
        if args.contains("--webcmp") { if let d = MTLCreateSystemDefaultDevice(), let r = Renderer(device: d) { exit(Verify.webcmp(r) ? 0 : 1) }; exit(1) }
        if let i = args.firstIndex(of: "--png"), i + 1 < args.count { Verify.png(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--walkpng"), i + 1 < args.count { Verify.walkPNG(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--mapuser"), i + 1 < args.count { Verify.mapUserPNG(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--bigflip"), i + 1 < args.count { Verify.bigFlip(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--thumbs"), i + 1 < args.count { Verify.thumbs(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--hyperpng"), i + 1 < args.count { Verify.hyperPNG(args[i + 1]); exit(0) }
        if args.contains("--picstats") { Verify.picStats(); exit(0) }
        if args.contains("--mapstats") { Verify.mapStats(); exit(0) }
        if args.contains("--mapbench") { Verify.mapBench(); exit(0) }
        if args.contains("--mapssbench") { Verify.mapSSBench(); exit(0) }
        if args.contains("--hyperbench") { Verify.hyperBench(); exit(0) }
        if args.contains("--mapcolor") { Verify.mapColorCompare(""); exit(0) }
        if args.contains("--quietbench") { Verify.quietBench(); exit(0) }
        if let i = args.firstIndex(of: "--mappng"), i + 1 < args.count { Verify.mapPNG(args[i + 1]); exit(0) }
        if let i = args.firstIndex(of: "--turndump"), i + 5 < args.count { Verify.turnDump(args[i + 1], args[i + 2] == "sharp", Int(args[i + 3])!, Double(args[i + 4])!, Int(args[i + 5])!); exit(0) }
        if let i = args.firstIndex(of: "--icon"), i + 1 < args.count { Verify.icon(args[i + 1]); exit(0) }
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
    /// 画面のゲームパッド（景色の下の方に出す。出す時はコントローラーで歩くをオンに）
    @Published var showPad = false { didSet { if showPad { r.set.gamepad = true } else { r.game.vClear() } } }
    @Published var showPanel = true
    @Published var isFull = false              // 全画面の間は、上のバー（ツールバー）を隠す
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
        HyperLabState.walkSource = { [unowned r] in .init(trail: r.journey.trail, pos: r.cam.w.p, marks: r.journey.marks, hit: r.journey.marks.map { r.journey.isHit($0) }, poles: r.journey.polesHit, lap: r.journey.lap, head: r.cam.lookFrame().L, space: r.set.space, fwd: r.cam.w.f, vR: r.cam.viewFrame().R, vU: r.cam.viewFrame().U, vL: r.cam.viewFrame().L, fov: r.set.fov) }   // 超球の試作に、歩いた跡・今いる所・目印を
        r.say = { [weak self] m in DispatchQueue.main.async { self?.say(m) } }
        r.onPad = { [weak self] k in self?.pad(k) }
        restoreMapMode()
        NativeSync.applyMapViews(maps, UserDefaults.standard.array(forKey: NativeSync.mapViewsKey))   // 地図の向き（前に回したまま）
        dockSub = dock.$floating.sink { [weak self] _ in DispatchQueue.main.async { self?.syncFloating() } }
        // 起動した時やアプリに戻った時も、浮いた窓を出し直す（起動の途中で作った窓は、アプリが前に出る前に隠れてしまうので）
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in self?.syncFloating() }
        NotificationCenter.default.addObserver(forName: NSWindow.willEnterFullScreenNotification, object: nil, queue: .main) { [weak self] _ in self?.isFull = true }
        NotificationCenter.default.addObserver(forName: NSWindow.willExitFullScreenNotification, object: nil, queue: .main) { [weak self] _ in self?.isFull = false }
        NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self?.syncFloating() }
        }
        if CommandLine.arguments.contains("--demo-float") {      // 確かめ用：球層と見え方をタブでまとめて浮かせる
            dock.reset(); dock.floatPanel(.shell); if let g = dock.floating.first { dock.addTab(.view, to: g.id) }
        }
        setupSync()
        // 4D 球アナロジーの「球層の数をさんぽと連動」：読む・書く（書いたらパネルも描き直す。保存・同期はいつもの流れで）
        HyperLabState.walkRendererGet = { [weak r = self.r] in r }   // 4D 球アナロジーの「さんぽの景色」の画面が、同じ Renderer で描く
        HyperLabState.walkShells = (get: { [unowned self] in self.r.set.shellN }, set: { [weak self] n in self?.r.set.shellN = n; self?.changed() })
    }
    /// 同期（Supabase、NativeSync.swift）：共通の状態（と地図の向き）に、Mac の画面の構成（パネルの並び・浮いた窓・地図の置き方・パネル・表示・ゲームパッド・
    ///   窓の大きさと場所・浮いた地図の窓・静かモードとコントローラーで歩く）を足す。Mac が 2 台あれば、レイアウトもそろう（窓は、その画面に収まるように）
    private func setupSync() {
        let sy = NativeSync.shared
        sy.core = { [weak self] in
            guard let self else { return [:] }
            var d = NativeSync.commonCore(self.r)
            d["maps"] = NativeSync.mapViews(self.maps)
            var u: [String: Any] = ["dock": self.dock.export(), "mapMode": self.mapMode.rawValue, "showPanel": self.showPanel, "showHUD": self.showHUD, "showPad": self.showPad,
                                    "set": NativeSync.kindSettings(self.r)]
            if let w = self.mainWindow, !w.styleMask.contains(.fullScreen), !self.isFull { u["window"] = Self.rect(w.frame) }   // 全画面の間は書かない（全画面の大きさを、ふつうの窓に当てないように）
            if let p = self.mapPanel { u["mapWindow"] = Self.rect(p.frame) }
            d[NativeSync.uiKey] = u
            return d
        }
        sy.position = { [weak self] in self.map { NativeSync.position($0.r) } ?? [:] }
        sy.apply = { [weak self] d, withPos in
            guard let self else { return }
            NativeSync.applyCommon(self.r, d, withPos)
            NativeSync.applyMapViews(self.maps, d["maps"])
            if let u = NativeSync.ui(d) {
                NativeSync.applyKind(self.r, u)                   // 静かモードなど（描く細かさは changed で当て直す）
                if let k = u["dock"] as? [String: Any] { self.dock.load(k); self.syncFloating() }
                if let m = (u["mapMode"] as? String).flatMap(MapMode.init(rawValue:)) { self.setMap(m) }
                if let f = Self.rect(u["mapWindow"]), let p = self.mapPanel { p.setFrame(Self.fit(f), display: true) }
                if let f = Self.rect(u["window"]), let w = self.mainWindow, !w.styleMask.contains(.fullScreen), !self.isFull { w.setFrame(Self.fit(f), display: true, animate: false) }   // 全画面の窓は動かさない
                if let v = u["showPanel"] as? Bool, v != self.showPanel { self.showPanel = v }
                if let v = u["showHUD"] as? Bool, v != self.showHUD { self.showHUD = v }
                if let v = u["showPad"] as? Bool, v != self.showPad { self.showPad = v }
            }
            Store.save(self.r); self.saveMapViews(); self.changed()
        }
        // 窓ができてから（浮いた窓・地図の窓を出し直せるように）、まず読み込む
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sy.start() }
    }
    /// 地図 1・2・S² の仲間（地図の向きの同期・保存）
    var maps: [MapRenderer] { [mapRenderer, mapRenderer2, s2Renderer] }
    /// 地図の向きを手元に覚えておく（変わった時だけ。tick から）
    private var lastMapViews = ""
    func saveMapViews() {
        let v = NativeSync.mapViews(maps), k = NativeSync.json(v)
        if k != lastMapViews { lastMapViews = k; UserDefaults.standard.set(v, forKey: NativeSync.mapViewsKey) }
    }
    /// 景色の窓（浮いたパネル・地図の窓ではない方）
    var mainWindow: NSWindow? { NSApp.windows.first { !($0 is NSPanel) && $0.isVisible && $0.contentView != nil && $0.frame.width >= 360 } }
    static func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
    static func rect(_ a: Any?) -> CGRect? { guard let v = a as? [Double], v.count == 4, v.allSatisfy(\.isFinite) else { return nil }; return CGRect(x: v[0], y: v[1], width: v[2], height: v[3]) }
    /// 窓の場所を、この Mac の画面に収める（画面の大きさが違う Mac から来た時）
    static func fit(_ f: CGRect) -> CGRect {
        let scr = NSScreen.screens.first { $0.visibleFrame.intersects(f) } ?? NSScreen.main
        guard let v = scr?.visibleFrame else { return f }
        let w = min(f.width, v.width), h = min(f.height, v.height)
        return CGRect(x: max(v.minX, min(f.minX, v.maxX - w)), y: max(v.minY, min(f.minY, v.maxY - h)), width: w, height: h)
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
        if r.padDuringAuto(k) { changed(); return }                 // 自動走行の間：B 中止・Y 前を見る・十字の上下 ターボ入・切（Renderer）
        if r.padWalk(k) { changed(); return }                       // A アクセル・B ブレーキ・十字の上 ターボ入・下 ターボ切・右 ターボの切りかえ（Renderer）
        switch k {
        case "R3": r.levelView()
        case "ZR": break                                          // ZR はふだん「押している間だけ速く」（毎コマ読む）。自動走行の間だけ前を見る
        case "menu": showPanel.toggle()
        case "options": toggleMap()
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
    /// 地図を出す・隠す（コントローラーの −）。出す時は前に出していた置き方（並べる・浮かせる）で
    private var lastShownMap: MapMode = .docked
    func toggleMap() {
        if mapMode == .hidden { setMap(lastShownMap); say("地図を出した") } else { lastShownMap = mapMode; setMap(.hidden); say("地図を隠した") }
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
        saveMapViews()
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
                Button("地図を景色のすみに") { model.setMap(.corner) }.keyboardShortcut("5", modifiers: .command)
                Toggle("地図を景色の左に", isOn: model.b(\.mapLeft)).keyboardShortcut("4", modifiers: .command)
                Divider()
                Toggle("自分を真ん中に", isOn: model.b(\.mapFollow))
                Button("地図を元の向きに") { model.mapRenderer.home(); model.mapRenderer2.home(); model.s2Renderer.home() }
                Toggle("2 枚目の地図", isOn: model.b(\.map2On))
            }
            // 試作（Metal で描き直しているもの）
            CommandMenu("試作") {
                Button("超球アナロジー（Metal 版）") { HyperLabWindow.open() }.keyboardShortcut("j", modifiers: [.command, .shift])
                Button("次元おりがみ（光で描く）") { ProtoWindows.open("tess", "次元おりがみ（光で描く試作）", TessLabView()) }.keyboardShortcut("k", modifiers: [.command, .shift])
                Button("次元おりがみ（ネイティブ版・移植の第 1 歩）") { ProtoWindows.open("origami", "次元おりがみ（ネイティブ版）", OrigamiView()) }.keyboardShortcut("o", modifiers: [.command, .shift])
            }
            CommandMenu("数学") {
                Button("超球（2 次元とのアナロジー）") { WebLabWindows.shared.open("hypersphere_beta", title: WebLab.hypersphereTitle) }.keyboardShortcut("h", modifiers: [.command, .shift])
                // ウェブ版の数学アプリ（サイトの一覧に載っているもの全部）：まとまりごとに、別の窓で開く
                ForEach(WebLab.groups, id: \.self) { g in
                    Divider()
                    Section(g) {
                        ForEach(WebLab.apps.filter { $0.group == g }) { a in Button(a.title) { WebLabWindows.shared.open(a.id, title: a.title) } }
                    }
                }
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


/// 地図の置き方：隠す・景色の横に並べる・浮いた窓（Photoshop のパレットのように、いつも前に）
enum MapMode: String, CaseIterable { case hidden, docked, floating, corner }   // corner：景色のすみに小さく

struct ContentView: View {
    @State private var sceneDrop = false
    @ObservedObject var model: AppModel
    var body: some View {
        // 地図は景色の右か左に（地図 1 の右上のボタン・インスペクター・メニューで入れかえ）。境目のつまみをドラッグした幅は覚えておく
        let showMaps = model.mapMode == .docked
        GeometryReader { geo in
        let w = CGFloat(max(220, min(model.r.set.mapWidth, Double(geo.size.width) - 360)))
        HStack(spacing: 0) {
            if showMaps && model.r.set.mapLeft {
                MapsArea(model: model).frame(width: w)
                SplitHandle(vertical: false) { d in model.r.set.mapWidth = max(220, Double(w) + Double(d)); model.changed() } onEnd: { model.changed() }
            }
            ZStack(alignment: .topLeading) {
                MetalView(model: model)
                HUDView(model: model)
                if model.mapMode == .corner {
                    CornerMap(corner: model.b(\.mapCorner), size: model.b(\.mapMini), home: { model.mapRenderer.home() }, dock: { model.setMap(.docked) }) {
                        MapPane(model: model, slot: 0)
                    }
                }
                if model.showPad {
                    VirtualPad(game: model.r.game) { model.showPad = false }.spaceControls()
                        .padding(.bottom, 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)   // 景色の下の方に
                }
                if sceneDrop {                                           // パネルの見出しを景色の上へドラッグしている間：ここに落とすと浮かぶ
                    RoundedRectangle(cornerRadius: 14).stroke(Space.violet.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [8, 6])).padding(10)
                        .overlay(Text("ここに落とすと、パネルが浮いた窓になる").font(.system(size: 13, weight: .semibold)).foregroundStyle(Space.lilac)
                            .padding(.horizontal, 14).padding(.vertical, 7).background(Space.panel.opacity(0.9), in: Capsule()))
                        .allowsHitTesting(false)
                }
            }
            .frame(minWidth: 360, maxWidth: .infinity)
            // パネルの見出し（ドックでも浮いた窓のタブでも）を景色の上へドラッグして落とすと、その場所に浮いた窓として出す
            .dropDestination(for: String.self) { items, _ in
                guard let str = items.first, let p = PanelID(rawValue: str) else { return false }
                let m = NSEvent.mouseLocation
                withAnimation(.easeOut(duration: 0.15)) { model.dock.floatPanel(p, frame: CGRect(x: m.x - 60, y: m.y - 420, width: 330, height: 440)) }
                return true
            } isTargeted: { sceneDrop = $0 }
            if showMaps && !model.r.set.mapLeft {
                SplitHandle(vertical: false) { d in model.r.set.mapWidth = max(220, Double(w) - Double(d)); model.changed() } onEnd: { model.changed() }
                MapsArea(model: model).frame(width: w)
            }
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
                    if model.help { Text(Keymap.shared.helpText()).foregroundStyle(.secondary) } else { Text(Keymap.shared.label(.help).isEmpty ? "操作の説明は設定の「ショートカットキー」で" : "\(Keymap.shared.label(.help).components(separatedBy: " / ")[0]) で操作の説明").foregroundStyle(.secondary) }
                }
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(.white)
                .padding(.horizontal, 10).padding(.vertical, 7)
                .background(Space.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Space.line))   // ウェブ版の .hud
            }
            if !hud.notice.isEmpty {
                Text(hud.notice).font(.system(size: 15, weight: .semibold)).foregroundStyle(.white)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(Space.panel.opacity(0.88), in: Capsule())
                    .overlay(Capsule().stroke(Space.violet.opacity(0.45)))
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
        // 地図を上下に（S² の仲間・S³ の地図・地図 2）。境目のつまみをドラッグした割合は覚えておく
        let slots = (model.r.set.s2On ? [2] : []) + [0] + (model.r.set.map2On ? [1] : [])
        GeometryReader { geo in
            let H = max(1, Double(geo.size.height)), n = slots.count
            // どの地図も 170 点より低くしない（低すぎると地図の中身がはみ出して、境目のつまみを隠してしまい、戻せなくなっていた）
            let m = min(0.9 / Double(n), 170 / H)
            let raw: [Double] = n == 3 ? [model.r.set.mapSplit3a, model.r.set.mapSplit3b] : n == 2 ? [model.r.set.mapSplit2] : []
            let cuts: [Double] = raw.enumerated().reduce(into: []) { c, e in
                c.append(min(1 - m * Double(raw.count - e.offset), max((c.last ?? 0) + m, e.element)))
            }
            VStack(spacing: 0) {
                ForEach(Array(slots.enumerated()), id: \.element) { k, slot in
                    let lo = k == 0 ? 0 : cuts[k - 1], hi = k == n - 1 ? 1 : cuts[k]
                    OneMap(model: model, slot: slot, topInset: k == 0 ? topInset : 0).frame(height: max(1, CGFloat((hi - lo) * H) - (k < n - 1 ? 5 : 0))).clipped()
                    if k < n - 1 {
                        SplitHandle(vertical: true) { d in
                            let f = min((k + 1 < cuts.count ? cuts[k + 1] : 1) - m, max(lo + m, cuts[k] + Double(d) / H))
                            if n == 2 { model.r.set.mapSplit2 = f } else if k == 0 { model.r.set.mapSplit3a = f } else { model.r.set.mapSplit3b = f }
                            model.changed()
                        } onEnd: { model.changed() }
                    }
                }
            }
        }
    }
}
/// 境目のつまみ（細い線。ドラッグで動かす）。vertical：上下に並んだ境目（横長のつまみ）
struct SplitHandle: View {
    let vertical: Bool
    let change: (CGFloat) -> Void
    let onEnd: () -> Void
    @State private var hover = false
    @State private var last: CGFloat = 0
    var body: some View {
        Rectangle().fill(hover ? Space.violet.opacity(0.7) : Space.line.opacity(0.7))
            .frame(width: vertical ? nil : 5, height: vertical ? 5 : nil)
            .contentShape(Rectangle())
            .onHover { h in hover = h; if h { (vertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push() } else { NSCursor.pop() } }
            .gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { g in
                let t = vertical ? g.translation.height : g.translation.width
                change(t - last); last = t
            }.onEnded { _ in last = 0; onEnd() })
    }
}
/// 地図 1 枚：隅に、見方（ふつう・自分中心）・範囲（全体・今いる所・写る所）・元の向き・浮かせる（ウェブ版の窓の右下の切り替え）
/// 地図の右上：軸 x・y・z・w が地図に写る長さの割合（ウェブ版の axlen と同じ）。自分中心では歩くと変わる
/// 地図の右上：今いる所の座標（x・y・z・w、それぞれ −1〜1。S³ の点なので 2 乗の和は 1）
struct PosReadout: View {
    let r: Renderer
    var body: some View {
        // 書きかえは 0.1 秒ごと（静かモードは 0.5 秒ごと：書きかえるたびに窓全体の並べ直しが走って CPU を使うので）
        TimelineView(.periodic(from: .now, by: r.set.quiet ? 0.5 : 0.1)) { _ in
            let p = r.cam.w.p
            HStack(spacing: 7) {
                Text("位置").foregroundStyle(Space.slate)
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 2) {
                        Text(["x", "y", "z", "w"][i]).font(.custom(MapLabel.axisFontName, size: 15)).foregroundStyle(Color(red: Double(AXIS_RGB[i].x), green: Double(AXIS_RGB[i].y), blue: Double(AXIS_RGB[i].z)))
                        Text(String(format: "%+.3f", p[i])).monospacedDigit().foregroundStyle(.white.opacity(0.9)).lineLimit(1).fixedSize()   // 地図が細い時も折り返さない
                    }
                }
            }
            .font(.caption).padding(.horizontal, 9).padding(.vertical, 3)
            .background(Space.panel.opacity(0.85), in: Capsule()).overlay(Capsule().stroke(Space.line))
            .help("今いる所の座標（S³ の点：x² ＋ y² ＋ z² ＋ w² ＝ 1）。アナ極は (0, 0, 0, +1)、カタ極は (0, 0, 0, −1)")
        }
    }
}

/// 向きの表示（地図の右上、位置の下）：方位・仰角（進む向き）と、見回し（頭だけ、横 / 縦）。リアルタイムに
struct AngleReadout: View {
    let r: Renderer
    var body: some View {
        TimelineView(.periodic(from: .now, by: r.set.quiet ? 0.5 : 0.1)) { _ in
            let c = r.cam
            HStack(spacing: 8) {
                item("方位", c.az); item("仰角", c.el)
                HStack(spacing: 3) {
                    Text("見回し").foregroundStyle(Space.slate)
                    Text(String(format: "%+.0f° / %+.0f°", c.hy, c.hp)).monospacedDigit().foregroundStyle(abs(c.hy) > 0.5 || abs(c.hp) > 0.5 ? Space.sky : .white.opacity(0.9)).lineLimit(1).fixedSize()
                }
            }
            .font(.caption).padding(.horizontal, 9).padding(.vertical, 3)
            .background(Space.panel.opacity(0.85), in: Capsule()).overlay(Capsule().stroke(Space.line))
            .help("方位・仰角：進む向き（体の前からの左右・上下）。見回し：頭だけ回した角度（横 / 縦。進む向きは変えない）")
        }
    }
    func item(_ name: String, _ v: Double) -> some View {
        HStack(spacing: 3) {
            Text(name).foregroundStyle(Space.slate)
            Text(String(format: "%+.0f°", v)).monospacedDigit().foregroundStyle(.white.opacity(0.9)).lineLimit(1).fixedSize()
        }
    }
}

struct AxisLengths: View {
    let map: MapRenderer
    var model: AppModel? = nil
    @State private var editing: Int? = nil
    @State private var text = ""
    @FocusState private var focused: Bool
    var body: some View {
        TimelineView(.periodic(from: .now, by: map.world.set.quiet ? 0.5 : 0.15)) { _ in
            let L = map.axisLengths(), canEdit = !map.config.follow
            HStack(spacing: 8) {
                ForEach(0..<4, id: \.self) { i in
                    HStack(spacing: 3) {
                        Text(["x", "y", "z", "w"][i]).font(.custom(MapLabel.axisFontName, size: 15)).foregroundStyle(Color(red: Double(AXIS_RGB[i].x), green: Double(AXIS_RGB[i].y), blue: Double(AXIS_RGB[i].z)))
                        if editing == i {
                            TextField("", text: $text).textFieldStyle(.roundedBorder).frame(width: 46).focused($focused)
                                .onSubmit { commit(i) }
                                .onChange(of: focused) { _, f in if !f { commit(i) } }
                                .onExitCommand { editing = nil }
                        } else {
                            // 10% より短い時は小数 1 桁まで（X-W 1° なら w は sin 1° ＝ 1.7%。整数に丸めると 2% に見えてしまう）
                            Text(L[i] < 0.1 && L[i] > 0.0005 ? String(format: "%.1f%%", L[i] * 100) : "\(Int((L[i] * 100).rounded()))%").monospacedDigit().foregroundStyle(.white.opacity(0.85))
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    guard canEdit else { model?.say("自分中心の時は、軸の長さは決められない（ふつうの見方で）"); return }
                                    text = String(format: "%g", (L[i] * 1000).rounded() / 10); editing = i; DispatchQueue.main.async { focused = true }
                                }
                        }
                    }
                }
            }
            .font(.caption).padding(.horizontal, 8).padding(.vertical, 3).background(.black.opacity(0.35), in: Capsule())
            .help("軸が地図に写る長さ（4 次元の軸のうち、3 次元に見えている割合）。数字をクリックして % を打ち込むと、その長さになるよう地図の傾きを決める（x・y・z は X-W・Y-W・Z-W、w は 3 つの傾きを同じ割合で）。自分中心では、今いる所の向きの軸ほど自分の方（奥行き）を向いて短くなる")
        }
    }
    func commit(_ i: Int) {
        defer { editing = nil }
        guard let v = Double(text.filter { "0123456789.".contains($0) }) else { return }
        if map.setAxisLength(i, v / 100) { model?.changed() }
    }
}

struct OneMap: View {
    @ObservedObject var model: AppModel
    let slot: Int
    var topInset: CGFloat
    var body: some View {
        let follow = slot == 1 ? model.b(\.map2Follow) : model.b(\.mapFollow)
        let range = slot == 1 ? model.b(\.map2Range) : model.b(\.mapRange)
        // 札やボタンは地図の上に重ねるだけ（地図の大きさを決めない。地図を低くしても、地図の窓が境目のつまみの上にはみ出さない）
        MapPane(model: model, slot: slot).overlay {
            VStack {
                HStack {
                    // ウェブ版の地図の札：S³ の地図はすみれ色、S² の仲間は水色
                    let bc = slot == 2 ? Color(red: 103 / 255, green: 232 / 255, blue: 249 / 255) : Color(red: 216 / 255, green: 180 / 255, blue: 254 / 255)
                    let uR = model.r.set.uniR, uTxt = uR > 1.05 && slot != 2 ? "・半径 ×" + (uR < 10 ? String(format: "%.1f", uR) : String(format: "%.0f", uR)) : ""
                    Text((slot == 0 ? "S³ の地図" : slot == 1 ? "地図 2" : "S² の仲間（同じ操作を球面で）") + uTxt).font(.caption.weight(.bold)).foregroundStyle(bc)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Space.panel.opacity(0.85), in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(bc.opacity(0.3)))
                    Spacer()
                    HStack(spacing: 6) {
                        Button { model.renderer(slot).home() } label: { Image(systemName: "scope") }.help("地図を元の向きに（ダブルクリックでも）")
                        if slot == 0 { MapBrightButton(model: model) }
                        if slot != 2 {
                            let s = model.r.set, alt = slot == 0 ? [s.mapAltXW, s.mapAltYW, s.mapAltZW] : [s.map2AltXW, s.map2AltYW, s.map2AltZW]
                            Button { if model.renderer(slot).swapTilt() { model.changed() } else { model.say("自分中心の時は傾きを入れかえられない（ふつうの見方で）") } } label: { Image(systemName: "arrow.triangle.2.circlepath") }
                                .help(String(format: "傾き（X-W・Y-W・Z-W）を、もう一つの組（%.0f°・%.0f°・%.0f°）と入れかえる。もう一度押すと戻る", alt[0], alt[1], alt[2]))
                        }
                        if slot == 0 {
                            if model.mapMode == .docked {
                                Button { model.r.set.mapLeft.toggle(); model.changed() } label: { Image(systemName: "arrow.left.arrow.right") }.help(model.r.set.mapLeft ? "地図を景色の右へ" : "地図を景色の左へ")
                                Button { model.setMap(.floating) } label: { Image(systemName: "macwindow.on.rectangle") }.help("地図を浮いた窓に切り離す")
                            } else {
                                Button { model.setMap(.docked) } label: { Image(systemName: "rectangle.split.2x1") }.help("地図を景色の横に戻す")
                            }
                            // 球層の色の切りかえ（二重丸）：レインボー → 4 方向レインボー → 軸の色 → レインボー …
                            let st = model.r.set, mode = st.shAxis ? 2 : st.rainbow4 ? 1 : 0
                            Button {
                                let next = (mode + 1) % 3
                                model.r.set.shAxis = next == 2; model.r.set.rainbow4 = next == 1
                                model.say(["球層：レインボー（w の 1 方向）", "球層：4 方向レインボー（x・y・z・w に重ねる・重い）", "球層：軸の色（囲む軸の色・重い）"][next]); model.changed()
                            } label: {
                                ZStack {
                                    Image(systemName: "circle.circle")
                                    if mode == 1 { Text("4").font(.system(size: 7, weight: .heavy)).offset(x: 6, y: 6) }
                                    if mode == 2 { Text("軸").font(.system(size: 6, weight: .heavy)).offset(x: 6, y: 6) }
                                }
                                .foregroundStyle(mode == 0 ? Color.primary : mode == 1 ? Space.sky : Space.violet)
                            }
                            .help("球層の色：" + ["レインボー", "4 方向レインボー", "軸の色"][mode] + "（押すたびに レインボー → 4 方向レインボー → 軸の色）")
                            Button { model.r.set.map2On.toggle(); model.changed() } label: { Image(systemName: model.r.set.map2On ? "rectangle.split.1x2.fill" : "rectangle.split.1x2") }.help("2 枚目の地図を出す・隠す")
                            Button { model.r.set.s2On.toggle(); model.changed() } label: { Image(systemName: model.r.set.s2On ? "circle.circle.fill" : "circle.circle") }.help("S² の仲間を出す・隠す")
                        }
                    }
                    .buttonStyle(.borderless).padding(5).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 7))
                }
                // 軸の長さ・位置・向き：見出しの下の右に、1 つずつの行で（地図が細くても縮めない）
                HStack {
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 4) {
                        if slot != 2 && model.r.set.mapAxes { AxisLengths(map: model.renderer(slot), model: model).fixedSize() }
                        if slot == 0 { PosReadout(r: model.r).fixedSize(); AngleReadout(r: model.r).fixedSize() }
                    }
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
    }
}

struct MainToolbar: ToolbarContent {
    @ObservedObject var model: AppModel
    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Toggle(isOn: model.rb(\.walking)) { Label("歩き続ける", systemImage: "figure.walk") }.help("歩き続ける" + Keymap.shared.hint(.walk))
            Toggle(isOn: model.rb(\.roaming)) { Label("縦横無尽", systemImage: "wind") }.help("縦横無尽：向きがゆっくり変わりながら歩く" + Keymap.shared.hint(.roam))
            Button { model.r.addMark(); model.changed() } label: { Label("目印を置く", systemImage: "mappin.and.ellipse") }.help("ここに目印を置く" + Keymap.shared.hint(.mark))
            Button { model.r.resetNorth(); model.say("アナ極に戻った"); model.changed() } label: { Label("アナ極へ", systemImage: "house") }.help("アナ極へ戻る" + Keymap.shared.hint(.home))
        }
        ToolbarItem(placement: .principal) {
            Picker("地図", selection: Binding(get: { model.mapMode }, set: { model.setMap($0) })) {
                Label("景色だけ", systemImage: "rectangle").tag(MapMode.hidden)
                Label("地図を並べる", systemImage: "rectangle.split.2x1").tag(MapMode.docked)
                Label("地図を浮かせる", systemImage: "macwindow.on.rectangle").tag(MapMode.floating)
                Label("地図を景色のすみに", systemImage: "rectangle.inset.topright.filled").tag(MapMode.corner)
            }
            .pickerStyle(.segmented).help("S³ の地図：隠す・景色の横に並べる・浮いた窓に")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: model.b(\.quiet)) { Label("静か", systemImage: "leaf") }.help("静かモード（ファンを回さない）：景色は 30 fps・描く細かさを下げる。画質は後回し")
        }
        ToolbarItem(placement: .primaryAction) {
            Button { WebLabWindows.shared.open("hypersphere_beta", title: WebLab.hypersphereTitle) } label: { Label("超球", systemImage: "circle.circle") }
                .help("超球（3D リング球 ↔ 4D 超球、2 次元とのアナロジー）を別の窓で開く")
        }
        ToolbarItem(placement: .primaryAction) {
            Toggle(isOn: $model.showPad) { Label("ゲームパッド", systemImage: "gamecontroller") }.help("画面のゲームパッド（コントローラーと同じボタン）" + Keymap.shared.hint(.vpad))
        }
        ToolbarItem(placement: .primaryAction) {
            Button { model.showPanel.toggle() } label: { Label("設定", systemImage: "sidebar.right") }.help("設定のインスペクター" + Keymap.shared.hint(.panel))
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
    var serif = false                                                 // 名前をセリフ体で（4D 球アナロジーの英語モード）
    override var isFlipped: Bool { true }
    override func hitTest(_ p: NSPoint) -> NSView? { nil }
    override init(frame: NSRect) { super.init(frame: frame); wantsLayer = true }
    required init?(coder: NSCoder) { fatalError() }
    func update(_ ls: [Renderer.PoleLab]) {
        guard let root = layer else { return }
        CATransaction.begin(); CATransaction.setDisableActions(true)
        let sc = window?.backingScaleFactor ?? 2, font = serif ? (NSFont(name: "Baskerville-SemiBold", size: 11) ?? NSFont(name: "Georgia", size: 11)!) : NSFont.boldSystemFont(ofSize: 11)
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
                t.isHidden = false; t.string = it.lab.name; t.font = font
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
        // 窓が完全に隠れたら景色を描かない（歩く計算は続ける）
        NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: nil, queue: .main) { [weak self] n in
            guard let self, let w = self.window, (n.object as? NSWindow) === w else { return }
            self.renderer.skipEncode = !w.occlusionState.contains(.visible)
        }
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
            // ショートカットキーの設定でキーを待っている時：次に押したキーをその操作のキーに（Esc でやめる、⌫ でキーなし）
            let km = Keymap.shared
            if let a = km.recording {
                if e.type == .keyDown { self.record(e, a) }
                return nil
            }
            if self.window?.firstResponder is NSText { return e }   // 数字を入力している間は、キーを入力欄へ（景色の操作にしない）
            // 選んだスライダー：← → ↑ ↓ で動かす（⇧ 10 倍・⌥ 0.1 倍）、数字か Return で直接入力、Esc で外す
            let sf = SliderFocus.shared
            if sf.key != nil, e.type == .keyDown, !e.modifierFlags.contains(.command), !e.modifierFlags.contains(.control) {
                let k = e.modifierFlags.contains(.shift) ? 10.0 : e.modifierFlags.contains(.option) ? 0.1 : 1.0
                switch e.keyCode {
                case 123, 125: sf.nudge?(-k); self.model?.changed(); return nil
                case 124, 126: sf.nudge?(k); self.model?.changed(); return nil
                case 36, 76: sf.edit?(nil); return nil
                case 53: sf.clear(); return nil
                default:
                    if let c = e.charactersIgnoringModifiers, c.count == 1, "0123456789.-".contains(c) { sf.edit?(c); return nil }
                }
            }
            if e.type == .keyUp, sf.key != nil, [123, 124, 125, 126].contains(e.keyCode) { return nil }
            // ⌘F：設定を探す（パネルを出して、検索の欄へ）
            if e.type == .keyDown, e.modifierFlags.contains(.command), !e.modifierFlags.contains(.control), e.charactersIgnoringModifiers?.lowercased() == "f" {
                self.model?.showPanel = true; DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { SettingSearch.shared.focusTick += 1 }; return nil
            }
            // ⌃F：全画面の切りかえ（⌘ は付けない。⌃⌘F もそのまま使える）
            if e.type == .keyDown, e.modifierFlags.contains(.control), !e.modifierFlags.contains(.command), e.charactersIgnoringModifiers?.lowercased() == "f" {
                if !e.isARepeat { self.window?.toggleFullScreen(nil) }; return nil
            }
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
            // 全画面の間は上のバー（ツールバー）を隠す。全画面のまま起動した時も
            NotificationCenter.default.addObserver(forName: NSWindow.didEnterFullScreenNotification, object: w, queue: .main) { _ in w.toolbar?.isVisible = false }
            NotificationCenter.default.addObserver(forName: NSWindow.willExitFullScreenNotification, object: w, queue: .main) { _ in w.toolbar?.isVisible = true }
            for t in [0.3, 1.5] { DispatchQueue.main.asyncAfter(deadline: .now() + t) { if w.styleMask.contains(.fullScreen) { w.toolbar?.isVisible = false } } }
        }
        applyScale()
    }
    override func setFrameSize(_ s: NSSize) { super.setFrameSize(s); applyScale() }
    override func viewDidChangeBackingProperties() { super.viewDidChangeBackingProperties(); applyScale() }

    /// 描く細かさ：窓の画素 × 倍率（1 で画面の画素そのまま。LG の全画面なら 4096×2304）。コマの速さも合わせる
    func applyScale() {
        guard model != nil else { return }
        // 映画のような光の時は、画面は画面の細かさのまま、景色だけ「描く細かさ」で描く（星と仕上げは細かく）。それ以外は画面ごと細かさを下げる
        //   静かモードの時は、細かさは静かモードの値に決め打ち・景色は 30 fps（ファンを回さない）
        let quiet = renderer.set.quiet
        let bs = window?.backingScaleFactor ?? 2, sc = quiet ? renderer.set.quietScaleEff : renderer.set.scale, whole = renderer.set.cine ? 1.0 : sc
        renderer.sceneScale = renderer.set.cine ? sc : 1
        let sz = CGSize(width: max(1, (bounds.width * bs * whole).rounded()), height: max(1, (bounds.height * bs * whole).rounded()))
        if sz != drawableSize { drawableSize = sz }
        // 60 fps の時は、画面の速さを割り切れる速さのうち 60 以上でいちばん遅いもの（144Hz → 72、120Hz → 60、60Hz → 60）。
        //   60 のままだと 144Hz の画面では 3 コマに 1 回（48 fps）になる
        let hz = max(60, window?.screen?.maximumFramesPerSecond ?? 60)
        let fps = quiet ? hz / max(1, hz / 30) : (renderer.set.fps60 || HyperLabState.walkShut) && !HyperLabState.boostWalk ? hz / max(1, hz / 60) : hz   // 4D 球アナロジーのダイブ・追う間は速く
        if preferredFramesPerSecond != fps { preferredFramesPerSecond = fps }
    }

    /// 細かさの自動：実際の fps が目標（60 など）に 2 回続けて届かなければ粗く、4 回（2 秒）続けて届いていれば少しずつ細かく（いちばん細かいのは 1）。
    ///   GPU の時間では決めない（軽いと Mac が GPU を遅くするので、時間が長く見えて、細かさを下げ続けてしまう）
    private var okStreak = 0, badStreak = 0, cap = 1.0, capT = CACurrentMediaTime(), boostSeen = false
    let logFPS = CommandLine.arguments.contains("--log")
    func autoScale(_ r: Renderer) {
        guard r.set.autoQ, !r.set.quiet, r.fps > 0, !r.idle else { return }   // 止まって描き直していない時・静かモードの時は、細かさを変えない
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
        if boostSeen != HyperLabState.boostWalk { boostSeen = HyperLabState.boostWalk; applyScale() }
        applyScale()
        if logFPS { print(String(format: "fps %.1f / %d  最長 %.1f ms  GPU %.2f ms  %d×%d  細かさ %.2f", r.fps, preferredFramesPerSecond, r.maxGap, r.gpuMs, Int(drawableSize.width), Int(drawableSize.height), r.set.scale)); fflush(stdout) }
        let p = r.cam.w.p, fromN = acos(max(-1, min(1, p.w)))
        let mode = [r.pathMode != .none ? (r.pathMode == .spiral ? "螺旋" : r.pathMode == .ring ? "回る輪" : r.pathMode == .half ? "半周 180° のターン" : r.pathMode == .cube ? "超立方体の辺めぐり" : r.pathMode == .cell24 ? "二十四胞体の辺めぐり" : r.pathMode == .custom ? "自分の道「" + r.cr.title + "」" : "極めぐり") + (abs(r.pathSpeed - 1) > 0.01 ? String(format: " ×%.1f", r.pathSpeed) : "") : r.roaming ? "縦横無尽" : r.rewinding ? String(format: "巻き戻し ×%.1f", max(0.3, r.rewindSpeed)) : r.walking ? (abs(r.autoSpeed - 1) > 0.01 ? String(format: "歩き続ける ×%.1f", r.autoSpeed) : "歩き続ける") : "", r.set.shell ? (r.set.shellSolid ? "球層（立体）" : "球層") : "", r.set.lite ? "軽い線" : ""].filter { !$0.isEmpty }.joined(separator: "・")
        let UR = r.set.uniR, big = UR >= 10, opp = big ? String(format: "πR ≈ %.0f", Double.pi * UR) : String(format: "π ≈ %.2f", Double.pi * UR)
        let s = String(format: "%.0f fps（目標 %d、いちばん長い間 %.0f ms）　GPU %.1f ms/コマ　%d×%d（細かさ %.0f%%%@）\nアナ極から %@（%@ で反対側）　進んだ距離 %@（%.2f 周）\n方位 %.0f°　仰角 %.0f°　見回し %.0f° / %.0f°　%@",
                       r.fps, preferredFramesPerSecond, r.maxGap, r.gpuMs, Int(drawableSize.width), Int(drawableSize.height), r.set.scale * 100, (r.set.autoQ ? "・自動" : "") + (r.idle ? "・止まっているので描き直さない" : ""),
                       String(format: big ? "%.0f" : "%.2f", fromN * UR), opp, String(format: big ? "%.0f" : "%.2f", r.journey.dist * UR), r.journey.dist / (2 * Double.pi),
                       r.cam.az, r.cam.el, r.cam.hy, r.cam.hp, mode)
        let j = r.journey, s2 = j.marks.count >= 2 || !j.polesHit.isEmpty || j.lap > 1 ? s + "　\(j.lap) 周目" : s   // 周回（目印 2 つ以上、なければ 8 つの極で数える）
        DispatchQueue.main.async { if self.model?.hudState.text != s2 { self.model?.hudState.text = s2 }; self.model?.tick() }
    }

    // ---- キー ----
    func key(_ e: NSEvent) {
        renderer.shiftFast = e.modifierFlags.contains(.shift)
        if e.isARepeat { return }
        renderer.keys.insert(e.keyCode)
        let r = renderer
        // キーは設定の「ショートカットキー」で変えられる（Keymap）
        guard let c = e.charactersIgnoringModifiers?.lowercased(), let act = Keymap.shared.action(for: c) else { return }
        switch act {
        case .panel: model?.showPanel.toggle()
        case .allPanels: model?.toggleAllPanels()
        case .walk: r.walking.toggle(); r.roaming = false; r.pathMode = .none
        case .roam: r.roaming.toggle(); r.walking = false; r.pathMode = .none; model?.say(r.roaming ? "縦横無尽：どこへ進んでも、いつか戻ってくる" : "縦横無尽をやめた")
        case .headGo: r.cam.headGo()
        case .lookReset: r.cam.hy = 0; r.cam.hp = 0
        case .home: r.resetNorth(); model?.say("アナ極に戻った")
        case .mark: r.addMark()
        case .foot: r.set.foot.toggle()
        case .shell: r.set.shell.toggle()
        case .solid: r.set.shellSolid.toggle()
        case .bare: r.set.shellBare.toggle()
        case .grand: r.set.grand.toggle()
        case .lite: r.set.lite.toggle()
        case .eq: r.set.eq.toggle()
        case .orient: r.set.orient.toggle()
        case .space: r.set.space.toggle(); model?.say(r.set.space ? "背景：宇宙（暗闇・星・天の川）" : "背景：深海（青灰色のもや）")
        case .crisp: r.set.lineCrisp.toggle(); model?.say(r.set.lineCrisp ? "線：くっきり" : "線：やわらか（標準）")
        case .mapAxes: r.set.mapAxes.toggle()
        case .markStyle: r.set.mk = (r.set.mk + 1) % 5; model?.say(["目印：玉", "目印：絵（絵文字）", "目印：色の点", "目印：なし", "目印：模型（3D）"][r.set.mk])
        case .fps: r.set.fps60.toggle(); applyScale()
        case .rangeDown: r.set.shellRange = max(0.3, r.set.shellRange - 0.5)
        case .rangeUp: r.set.shellRange = min(25.15, r.set.shellRange + 0.5)
        case .scaleDown: r.set.autoQ = false; r.set.scale = max(0.3, r.set.scale - 0.1); applyScale()
        case .scaleUp: r.set.autoQ = false; r.set.scale = min(1.0, r.set.scale + 0.1); applyScale()
        case .turbo: r.turboPress(key: e.keyCode)
        case .hud: model?.showHUD.toggle()
        case .help: model?.help.toggle()
        case .vpad: model?.showPad.toggle()
        }
        model?.changed()
    }
    /// ショートカットキーを決める（設定でキーの札を押した後の 1 つ）
    func record(_ e: NSEvent, _ a: KeyAction) {
        let km = Keymap.shared
        if e.modifierFlags.contains(.command) || e.modifierFlags.contains(.control) { model?.say("⌘・⌃ の付いたキーはメニュー用（ほかのキーを押す）"); return }
        switch e.keyCode {
        case 53: km.recording = nil; return
        case 51, 117: km.clear(a); km.recording = nil; model?.say("「\(a.title)」のキーをなしに"); return
        case 123, 124, 125, 126: model?.say("矢印は向きのキー（変えられない）"); return
        default: break
        }
        guard let c = e.charactersIgnoringModifiers?.lowercased(), c.count == 1 else { return }
        if Keymap.fixed.contains(c) { model?.say("W A S D Q E は歩くキー（変えられない）"); return }
        let lost = km.assign(c, to: a)
        km.recording = nil
        model?.say("「\(a.title)」を \(Keymap.label(c)) に" + (lost.map { "（「\($0.title)」からは外した）" } ?? ""))
        model?.changed()
    }
    func flags(_ e: NSEvent) {
        renderer.shiftFast = e.modifierFlags.contains(.shift)
        if e.modifierFlags.contains(.command) { renderer.keys.removeAll() }   // ⌘ を押している間は keyUp が来ないことがある
    }

    // ---- マウス：ドラッグで見回し（Shift＋ドラッグで進む向き）。0.3°/点（ウェブ版と同じ）。2 本指のスクロールでも見回し ----
    override func mouseDown(with e: NSEvent) { dragLast = e.locationInWindow; window?.makeFirstResponder(self); SliderFocus.shared.clear(); Keymap.shared.recording = nil }
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
        r.cam.clampAngles(free: r.set.free360)
        if r.set.free360 && abs(r.cam.el) > 60 { r.rebaseBody() }
    }
}
