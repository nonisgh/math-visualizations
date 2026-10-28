// 球面さんぽ（iPad・iPhone 版）の入口：景色（MTKView）と S³ の地図、指の操作、コントローラー、設定のパネル。
//   景色・地図・4 次元の計算・設定のパネルは Mac 版と同じ Sources/S3Walk のファイルを使う（Renderer・MapRenderer・Shaders・Dock など）
import SwiftUI
import MetalKit
import CoreText

@main
struct S3WalkiOSApp: App {
    @StateObject private var model = MobileModel()
    var body: some Scene {
        WindowGroup { MobileRoot(model: model).preferredColorScheme(.dark).statusBarHidden(true) }
    }
}

/// Mac 版のパネル（Dock.swift の PanelContent など）は AppModel を使う。iPad・iPhone ではこのアプリの中身がその役
typealias AppModel = MobileModel

/// 地図の置き方：隠す・景色の横に並べる・景色のすみに小さく（Mac 版と同じ。すみと大きさは設定の mapCorner・mapMini）
enum MapMode: String, CaseIterable { case hidden, docked, corner }

/// アプリの中身：景色の Renderer と地図、パネル、保存、知らせ
final class MobileModel: ObservableObject {
    let r: Renderer
    let dock = DockState()
    lazy var mapRenderer = MapRenderer(world: r, slot: 0)
    lazy var mapRenderer2 = MapRenderer(world: r, slot: 1)
    lazy var s2Renderer = MapRenderer(world: r, slot: 2)
    func renderer(_ slot: Int) -> MapRenderer { slot == 0 ? mapRenderer : slot == 1 ? mapRenderer2 : s2Renderer }
    @Published var notice = ""
    @Published var showPanel = false
    @Published var showWeb = false                 // ウェブ版の数学アプリの一覧（シート）
    @Published var askProto = false                // 試作を選ぶ
    @Published var proto: String? = nil            // 開いている試作（hyper・tess）
    @Published var mapMode: MapMode = .docked
    @Published var hudText = ""
    /// 画面のゲームパッド（景色の下の方に出す）
    @Published var showPad = false { didSet { if showPad { r.set.gamepad = true } else { r.game.vClear() } } }
    /// パネルの大きさ（Mac 版のパネルを縮めて入れる。1 で Mac と同じ大きさ）
    @Published var uiScale: Double = UserDefaults.standard.object(forKey: "s3walk.ios.uiScale") as? Double ?? (UIDevice.current.userInterfaceIdiom == .pad ? 0.85 : 0.8) {
        didSet { UserDefaults.standard.set(uiScale, forKey: "s3walk.ios.uiScale") }
    }
    weak var sceneView: MTKView?
    /// − で地図を出す時の置き方（隠す前の置き方）
    var lastShownMap: MapMode = UIDevice.current.userInterfaceIdiom == .phone ? .corner : .docked
    private var noticeT = 0.0, lastSaved = ""
    init() {
        // 軸の名前の書体（KaTeX の数式用の斜体）
        if let u = Bundle.main.url(forResource: "KaTeX_Math-Italic", withExtension: "ttf") { CTFontManagerRegisterFontsForURL(u as CFURL, .process, nil) }
        guard let dev = MTLCreateSystemDefaultDevice(), let r = Renderer(device: dev) else { fatalError("Metal が使えない") }
        self.r = r
        HyperLabState.walkSource = { [unowned r] in .init(trail: r.journey.trail, pos: r.cam.w.p, marks: r.journey.marks, hit: r.journey.marks.map { r.journey.isHit($0) }, poles: r.journey.polesHit, lap: r.journey.lap, space: r.set.space, fwd: r.cam.w.f, vR: r.cam.viewFrame().R, vU: r.cam.viewFrame().U, vL: r.cam.viewFrame().L, fov: r.set.fov) }   // 超球の試作に、歩いた跡・今いる所・目印を
        if UserDefaults.standard.dictionary(forKey: Store.key) == nil { MobileModel.macLook(r) }   // 初めて開いた時は Mac 版の見え方で
        Store.restore(r)
        r.set.gamepad = true                                   // 指のスティックもコントローラーと同じ入れ方で
        r.set.scale = 0.7                                      // 描く細かさは粗めから（足りていれば自動で細かくなる）
        if let s = UserDefaults.standard.string(forKey: "s3walk.mapMode"), let m = MapMode(rawValue: s == "floating" ? "corner" : s) { mapMode = m }
        else if UIDevice.current.userInterfaceIdiom == .phone { mapMode = .corner }
        NativeSync.applyMapViews(maps, UserDefaults.standard.array(forKey: NativeSync.mapViewsKey))   // 地図の向き（前に回したまま）
        r.say = { [weak self] m in DispatchQueue.main.async { self?.say(m) } }
        r.onPad = { [weak self] k in self?.pad(k) }
        r.onStats = { [weak self] r in
            let c = r.cam, p = c.w.p
            let s0 = String(format: "%.0f fps・細かさ %.0f%%　アナ極から %.2f　方位 %+.0f° 仰角 %+.0f° 見回し %+.0f°/%+.0f°", r.fps, r.set.scale * 100, acos(max(-1, min(1, p.w))) * r.set.uniR, c.az, c.el, c.hy, c.hp)
            let s = r.journey.marks.count >= 2 ? s0 + "　\(r.journey.lap) 周目" : s0   // 周回（目印が 2 つ以上の時）
            DispatchQueue.main.async { self?.autoScale(r); if self?.hudText != s { self?.hudText = s }; self?.save(); if self?.boostSeen != HyperLabState.boostWalk || self?.shutSeen != HyperLabState.walkShut { self?.boostSeen = HyperLabState.boostWalk; self?.shutSeen = HyperLabState.walkShut; self?.applyScale() } }
        }
        setupSync()
        // 4D 球アナロジーの「球層の数をさんぽと連動」：読む・書く（書いたらパネルも描き直す。保存・同期はいつもの流れで）
        HyperLabState.walkRendererGet = { [weak r = self.r] in r }   // 4D 球アナロジーの「さんぽの景色」の画面が、同じ Renderer で描く
        HyperLabState.walkShells = (get: { [unowned self] in self.r.set.shellN }, set: { [weak self] n in self?.r.set.shellN = n; self?.changed() })
    }
    /// 同期（Supabase、NativeSync.swift）：共通の状態（と地図の向き）に、iPad か iPhone の画面の構成（パネルの並び・地図の置き方・パネルの大きさ・ゲームパッド・
    ///   静かモード）を足す。iPad どうし・iPhone どうしでそろう（iPad と iPhone は画面が違うので別々）
    func setupSync() {
        let sy = NativeSync.shared
        sy.core = { [weak self] in
            guard let self else { return [:] }
            var d = NativeSync.commonCore(self.r)
            d["maps"] = NativeSync.mapViews(self.maps)
            d[NativeSync.uiKey] = ["dock": self.dock.export(), "mapMode": self.mapMode.rawValue, "uiScale": self.uiScale, "showPad": self.showPad,
                                   "set": NativeSync.kindSettings(self.r)] as [String: Any]
            return d
        }
        sy.position = { [weak self] in self.map { NativeSync.position($0.r) } ?? [:] }
        sy.apply = { [weak self] d, withPos in
            guard let self else { return }
            NativeSync.applyCommon(self.r, d, withPos)
            NativeSync.applyMapViews(self.maps, d["maps"])
            if let u = NativeSync.ui(d) {
                NativeSync.applyKind(self.r, u)
                if let k = u["dock"] as? [String: Any] { var k2 = k; k2["floating"] = nil; self.dock.load(k2) }
                if let m = (u["mapMode"] as? String).flatMap(MapMode.init(rawValue:)) { self.setMap(m) }
                if let v = u["uiScale"] as? Double, v != self.uiScale { self.uiScale = v }
                if let v = u["showPad"] as? Bool, v != self.showPad { self.showPad = v }
            }
            self.r.set.gamepad = true
            self.applyScale(); self.save(); self.changed()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { sy.start() }
    }
    /// Mac 版で見ている見え方（MacLook.plist：Mac の設定をそのまま書き出したもの）にそろえる
    static func macLook(_ r: Renderer) {
        guard let u = Bundle.main.url(forResource: "MacLook", withExtension: "plist"), let d = NSDictionary(contentsOf: u) as? [String: Any] else { return }
        let sc = r.set.scale
        r.set.load(d); r.set.scale = sc
    }
    func loadMacLook() { MobileModel.macLook(r); r.set.gamepad = true; applyScale(); changed(); say("Mac 版の見え方にした") }
    func say(_ m: String) { notice = m; noticeT = CACurrentMediaTime(); let t = noticeT; DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in if self?.noticeT == t { self?.notice = "" } } }
    /// パネルの部品と設定をつなぐ（Mac 版の AppModel と同じ）
    func b<T>(_ kp: WritableKeyPath<Settings, T>) -> Binding<T> {
        Binding(get: { self.r.set[keyPath: kp] }, set: { self.objectWillChange.send(); self.r.set[keyPath: kp] = $0; let k = kp as AnyKeyPath; if k == \Settings.scale || k == \Settings.cine || k == \Settings.fps60 || k == \Settings.quiet || k == \Settings.quietScale || k == \Settings.rainbow4 || k == \Settings.shAxis || k == \Settings.shell { self.applyScale() } })
    }
    func rb<T>(_ kp: ReferenceWritableKeyPath<Renderer, T>) -> Binding<T> {
        Binding(get: { self.r[keyPath: kp] }, set: { self.objectWillChange.send(); self.r[keyPath: kp] = $0 })
    }
    func changed() { objectWillChange.send() }
    func setMap(_ m: MapMode) { mapMode = m; UserDefaults.standard.set(m.rawValue, forKey: "s3walk.mapMode") }
    func save() {
        let snap = Store.snapshot(r), key = "\(snap)"
        if key != lastSaved { lastSaved = key; UserDefaults.standard.set(snap, forKey: Store.key) }
        let v = NativeSync.mapViews(maps), k = NativeSync.json(v)                 // 地図の向き（前に回したまま）
        if k != lastMapViews { lastMapViews = k; UserDefaults.standard.set(v, forKey: NativeSync.mapViewsKey) }
    }
    private var lastMapViews = ""
    /// 地図 1・2・S² の仲間（地図の向きの同期・保存）
    var maps: [MapRenderer] { [mapRenderer, mapRenderer2, s2Renderer] }
    /// 描く細かさ：映画のような光の時は景色だけ粗く（星と仕上げは画面の細かさ）、それ以外は画面ごと粗く（Mac 版の applyScale と同じ）
    var boostSeen = false, shutSeen = false
    func applyScale() {
        guard let v = sceneView else { return }
        let sc = r.set.quiet ? r.set.quietScaleEff : r.set.scale, screen = v.window?.screen.scale ?? UIScreen.main.scale
        r.sceneScale = r.set.cine ? sc : 1
        let cs = r.set.cine ? screen : screen * sc
        if abs(v.contentScaleFactor - cs) > 0.001 { v.contentScaleFactor = cs }
        let hz = max(60, v.window?.screen.maximumFramesPerSecond ?? 60)
        let fps = r.set.quiet ? 30 : (r.set.fps60 || HyperLabState.walkShut) && !HyperLabState.boostWalk ? 60 : hz   // 4D 球アナロジーのダイブ・追う間は速く
        if v.preferredFramesPerSecond != fps { v.preferredFramesPerSecond = fps }
    }
    /// 細かさの自動（Mac 版と同じ考え）：fps が目標に 2 回続けて届かなければ粗く、4 秒続けて届いていれば少しずつ細かく
    private var okStreak = 0, badStreak = 0, cap = 1.0, capT = CACurrentMediaTime()
    func autoScale(_ r: Renderer) {
        guard r.set.autoQ, !r.set.quiet, r.fps > 0, !r.idle, let v = sceneView else { return }
        let target = Double(v.preferredFramesPerSecond), now = CACurrentMediaTime(), budget = 1000 / target
        if now - capT > 30 { cap = 1.0 }
        var sc = r.set.scale
        if r.fps < target * 0.9 {
            okStreak = 0; badStreak += 1
            if badStreak >= 2 { badStreak = 0; cap = max(0.35, sc - 0.02); capT = now; sc = max(0.35, sc * 0.9) }
        } else {
            badStreak = 0
            if r.fps >= target * 0.97 { okStreak += 1 }
            let up = min(1, cap, sc * 1.08)
            if okStreak >= 8 && sc < min(1, cap) && r.gpuMs * (up / sc) * (up / sc) < budget * 0.7 { sc = up; okStreak = 0 }
        }
        if abs(sc - r.set.scale) > 0.005 { r.set.scale = sc; applyScale() }
    }
    /// コントローラーのボタン（Mac 版と同じ）
    func pad(_ k: String) {
        if r.padDuringAuto(k) { changed(); return }                 // 自動走行の間：B 中止・Y 前を見る・十字の上下 ターボ入・切（Renderer）
        if r.padWalk(k) { changed(); return }                       // A アクセル・B ブレーキ・十字の上 ターボ入・下 ターボ切・右 ターボの切りかえ（Renderer。Mac 版と同じ）
        switch k {
        case "R3": r.levelView()
        case "ZR": break                                          // ZR はふだん「押している間だけ速く」（毎コマ読む）。自動走行の間だけ前を見る
        case "menu": showPanel.toggle(); say(showPanel ? "設定を開いた（＋）" : "設定を閉じた（＋）")
        case "options":                                       // −：地図を隠す・前の置き方（すみ・並べる）で出す
            if mapMode == .hidden { setMap(lastShownMap); say(lastShownMap == .corner ? "地図をすみに出した（−）" : "地図を並べた（−）") }
            else { lastShownMap = mapMode; setMap(.hidden); say("地図を隠した（−）") }
        default: break
        }
        changed()
    }
}
