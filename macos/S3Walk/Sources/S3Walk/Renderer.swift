// 描く仕組み：Metal のパイプラインと、毎コマのシェーダーへの値（ウェブ版の setRayUniforms・rebuildMarks にあたる）
import Foundation
import Metal
import MetalKit
import QuartzCore
import simd

/// シェーダーの Uni と同じ並び（256 バイト）
struct Uni {
    var P = SIMD4<Float>(), R = SIMD4<Float>(), U = SIMD4<Float>(), F = SIMD4<Float>()
    var L0 = SIMD4<Float>()
    var res = SIMD2<Float>(1, 1); var tanF: Float = 0; var maxD: Float = 0
    var fog: Float = 0, fade: Float = 0, uni: Float = 1, depth: Float = 0
    var shellOp: Float = 0, shellBack: Float = 0, shellRange: Float = 0, shMin: Float = 0
    var shellLum: Float = 0, gridSt: Float = 0; var shellN: Int32 = 11; var shell: Int32 = 1
    var shellSolid: Int32 = 0, shellBare: Int32 = 0, eq: Int32 = 1, nm: Int32 = 0
    var passes: Int32 = 4, orient: Int32 = 0, lite: Int32 = 0, webTies: Int32 = 0
    var glow: Float = 0, edr: Float = 1, band: Float = 0, nebStep: Float = 0.1
    var pic: Int32 = 0, ghostBack: Int32 = 0, lens: Int32 = 0, neb: Int32 = 0
    var fovY: Float = 0, picLine: Float = 0.3, nebK: Float = 1, wireFloor: Float = 0
    var circ: Int32 = 0, room: Int32 = 0, space: Int32 = 0, shAx: Int32 = 0
    var tube: Float = 0.02, pixAng: Float = 0.002, lineW: Float = 0, solidWire: Float = 0.35
}
/// 星の見え方の値（シェーダーの StarU と同じ並び、112 バイト）
struct StarU {
    var P = SIMD4<Float>(), R = SIMD4<Float>(), U = SIMD4<Float>(), F = SIMD4<Float>()
    var res = SIMD2<Float>(1, 1); var tanF: Float = 0; var fovY: Float = 0
    var lens: Int32 = 0; var fog: Float = 0, lum: Float = 1, maxD: Float = 0
    var edr: Float = 1, px: Float = 1, spad0: Float = 0, spad1: Float = 0
}
struct StarGPU { var p: SIMD4<Float>; var c: SIMD4<Float> }
/// 光の仕上げの値（シェーダーの PostU と同じ並び）
struct PostU {
    var src = SIMD2<Float>(1, 1), dst = SIMD2<Float>(1, 1)
    var thr: Float = 0.9, knee: Float = 0.5, inten: Float = 0.6, expo: Float = 1
    var head: Float = 1, grain: Float = 0, vign: Float = 0, time: Float = 0
    var first: Int32 = 0, ppad0: Int32 = 0, ppad1: Int32 = 0, ppad2: Int32 = 0
}
struct MkGPU { var c: SIMD4<Float>; var col: SIMD4<Float>; var info = SIMD4<Float>(-1, 0, 0, 0) }

/// 見え方の設定（ウェブ版の S のうち、球層の型に要るもの。既定はウェブ版の既定＋「球層の海」の場面）
struct Settings {
    var fov = 70.0
    var maxD = 5.9, fog = 0.22, fade = 0.25, depth = 0.5
    var passes = 4
    var shell = true, shellSolid = false, shellBare = false
    var solidWire = 0.6         // 立体の殻の時の網目（ワイヤー）の濃さ。ウェブ版は 0.35
    var shellN = 11, shellOp = 0.22, shellBack = 0.6, shellLum = 0.65, shellRange = 3.0
    var eq = true
    var lite = false            // 軽い線：アナ極を囲む 5 枚の殻（w ＝ 一定）に緯度・経度の線（ウェブ版の既定は ON、球層の型では OFF）
    var grand = false           // 壮大モード：網目 5° ごと・もや 1.6 倍・目印 7 割
    var poles = true            // 8 つの極の目印
    var hidePair = false        // 反対側の相棒（−の側の極）を隠す：遠回りの像が見えるように
    var orient = false          // 玉の右上に赤い点（像の向きの確かめ用）
    var selfBall = true         // 自分の玉（2π 先に自分の背中）
    var extra: [Marker] = []    // 確かめ用などで足す玉
    var hideLabels: Set<String> = []   // 確かめ用：この名前の玉を出さない
    var spd = 0.6
    var foot = true             // 足あと（0.6 進むごと）
    var marksOn = true          // 置いた目印を出す
    var roamK = 1.0             // 縦横無尽の曲がりやすさ
    var fps60 = true            // 60 fps 前後で描く（144Hz の画面では 72。OFF なら画面の速さ）
    var autoQ = true            // fps が足りない時だけ、描く細かさを自動で下げる
    var scale = 1.0             // 描く細かさ（画面の画素に対する割合）
    var webTies = false         // 確かめ用：同じ道のりの層の片方を落とす（ウェブ版と同じ）
    var haptics = true          // トラックパッドの触覚（赤道・極で「コツン」、殻を通るたびに「カチ」）
    var gamepad = true          // ゲームコントローラーで歩く
    var turns = 5.0, tilt = 0.6, prec = 15.0   // 螺旋：巻き数・傾き・歳差（度／周）
    var ringAxis = 2, ringStep = 10.0          // 回る輪：軸（0 x・1 y・2 z・3 w・4 全部）・1 周で回す角（度）
    var padGame = true          // ゲームのような操作（少し倒すとゆっくり・速めに回る・慣性つき）。ZL＋右スティックの見回し・加速はオン・オフによらない
    var padInvX = false, padInvY = false   // 右スティックの反転（左右・上下）
    var mk = 0                  // 目印の見せ方：0 玉・1 絵（絵文字）・2 色の点・3 なし（ウェブ版の P キー）
    var picLine = 0.3           // 絵・色の点の時の線の濃さ（0 で消す）
    var ghostBack = false       // 遠回りの像を、絵の裏から見た形に（左右を鏡に）
    var lens = 0                // 0 ふつう・1 魚眼・2 360°
    var circ = false            // 管：経線（x・y・z と w の大円）と赤道の輪（ウェブ版の既定は OFF。重い）
    var room = false            // 管：120 胞体の部屋の辺（いちばん重い）
    var lineCrisp = false       // 線の見え方：やわらか（標準。殻の上で決まった角度の太さで、近い線ほど太く遠近感が出る）／くっきり（網目の線と玉のふちを画面で lineW 画素）
    var lineW = 1.8             // くっきりの時の網目の線の太さ（画素）
    var glow = 0.4              // 光る線：線のまわりのにじみ（0 でウェブ版と同じ絵）
    var space = false           // 背景：false 深海（青灰色のもや。ウェブ版と同じ）／true 宇宙（暗闇・星・天の川）
    var stars = 1.0             // 宇宙の時の星の明るさ（0 で星なし）
    var band = 1.0              // 宇宙の時の天の川・星雲の明るさ
    var polePlanet = true       // 8 つの極を「惑星」に：極の色の、少し透けてつやのある大きな玉（角度 0.16、宇宙の大きさでは小さくしない＝広い宇宙ほど本当は大きい）。絵のモードの時は絵のまま
    var autoAccel = 1.2         // 自走（歩き続ける）の時、左スティックを前へ倒し続けた時の速くなり方（1 秒あたり）
    var autoMax = 8.0           // 自走の最高の速さ（ふつうの何倍か）
    var autoRewind = true       // 自走の時、手前へ倒し続けると止まったあと軌跡を逆にたどる（巻き戻し）
    var mapWidth = 520.0        // 地図の幅（景色との境目のつまみで。覚えておく）
    var mapSplit2 = 0.5, mapSplit3a = 0.34, mapSplit3b = 0.67   // 地図を上下に並べた時の境目（2 枚・3 枚）
    var free360 = true          // 上下（仰角・見回し）も 360° 回す（宙返り）。false でウェブ版と同じく ±89° で止める
    var wireFloor = 0.35        // 目印の線の濃さ：宇宙を大きくすると出てくる、殻の色の細い線（CG ソフトの補助線のよう。もやで消さない。0 で出さない＝ウェブ版と同じ）
    var shAxis = false          // 球層の色：false レインボー（w の殻）／true 軸の色（選んだ軸の極を囲む殻を、その軸の色で。ウェブ版の軸色）
    var shAxX = true, shAxY = true, shAxZ = true, shAxW = true   // 軸の色の時に、どの軸の殻を出すか
    var uniL = 0.0              // 宇宙の大きさ：S³ の半径 R ＝ 10^uniL（1〜1000 倍。ウェブ版の uniL）。場所は角度のまま、歩く速さ・目印の見かけは 1/R、距離・もやは R 倍。殻の網目の太さは変わらない
    var uniR: Double { pow(10, max(0, min(3, uniL))) }
    var nebula = true           // 宇宙の時、S³ に浮かぶ星雲（色のついたガス）
    var nebK = 1.0              // 星雲の濃さ
    var cine = true             // 映画のような光：明るさを切らずに描き（HDR）、あふれる光（ブルーム）を足し、色を締める（トーンマップ）。false でウェブ版と同じ絵
    var bloom = 0.5             // あふれる光の強さ
    var expo = 1.0              // 露出（明るさ）
    var grain = 0.4             // フィルムの粒
    var edrOn = true            // EDR の画面では、線の芯を画面の白より明るく光らせる
    // 地図（S³ → 3 次元）：x-w・y-w・z-w の回転（度）、遠近 D（k ＝ D／(D − w)）、自分を真ん中に、軸、軌跡
    var mapXW = 0.0, mapYW = 90.0, mapZW = 0.0, mapD = 2.5
    var mapFollow = false, mapAxes = true, mapTrail = true
    var mapRange = 0            // 殻の出し方：0 全体・1 今いる所（自分の殻ははっきり、となりはうっすら）・2 写る所（中の景色に写っている所だけ）
    // 2 枚目の地図（ウェブ版の左上の「地図 2」）：見方・範囲・4 次元の向きは 1 枚目と別。既定は自己中心
    var map2On = true
    var s2On = true             // S² の仲間の窓（ウェブ版の左の窓）
    var mapLeft = false         // 地図を景色の左に並べる（OFF なら右）
    var map2Follow = true, map2Range = 0
    var map2XW = 0.0, map2YW = 90.0, map2ZW = 0.0
}

final class Renderer: NSObject, MTKViewDelegate {
    let device: MTLDevice
    let queue: MTLCommandQueue
    private var pipes: [MTLPixelFormat: MTLRenderPipelineState] = [:]
    private let library: MTLLibrary

    var cam = Camera()
    var set = Settings()
    var keys = Set<UInt16>()
    var walking = false
    var roaming = false         // 縦横無尽（歩き続けながら、向きがゆっくり変わる）
    var shiftFast = false
    private var padMove = SIMD3<Double>(0, 0, 0), padVel = SIMD3<Double>(0, 0, 0)
    // 左スティックの加速：倒しきったまま少し待つと、だんだん速く（最大 2.5 倍）
    private(set) var padRun = 1.0
    /// 最後に歩いた向きと時刻（地図の黄色の円すいが、歩いている間はこの向きを指す。ウェブ版の W.lastDir）
    var lastDir: V4?, lastDirT = 0.0
    /// 前を見ている途中（leveling：見回しを 0 へ。levelEl なら仰角も 0 へ）・この向きへ進む途中（headGoing）
    private(set) var leveling = false, levelEl = false, headGoing = false
    /// 前を見る（ウェブ版の「↺ 前を見る」）：見回しを 0 へ、なめらかに（ほとんどは 0.3 秒）。もう前を見ている時は、仰角も 0 へ（水平に）
    func levelView() {
        headGoing = false
        levelEl = abs(cam.hy) < 0.5 && abs(cam.hp) < 0.5; leveling = true
        say?(levelEl ? "水平に戻す（進む方位はそのまま）" : "前を見る（進む向きに目を戻す）")
    }
    /// コントローラーの Y：前を見る（進む向きは変えない。もう一度で水平にも）。ZL を押しながらなら、この向きへ進む
    func padY() { if padLookOnly { zlUsed = true; headGoPad() } else { levelView() } }
    /// この向きへ進む（ウェブ版の Enter）：見ている向きを進む向きにする。景色はそのまま、地図の黄色の円すいがなめらかに回って水色に重なる
    func headGoPad() {
        guard abs(cam.hy) > 0.01 || abs(cam.hp) > 0.01 else { return }
        leveling = false; headGoing = true; say?("この向きへ進む（Enter と同じ）")
    }
    private var padHold = 0.0, padPushWas = false
    /// 自走（歩き続ける）の速さの倍率・巻き戻し中か・巻き戻しの速さ（左スティックの前後で。アクセル・ブレーキ・巻き戻し）
    private(set) var autoSpeed = 1.0, rewinding = false, rewindSpeed = 0.0
    private var walkingWas = false, padThrottle = 0.0
    /// ZL を押している（見回しだけ）。パネルの表示用
    private(set) var padLookOnly = false
    /// ZL を押している間に、右スティックか Y を使ったか（使わずに離したら「前を見る」）
    private var zlUsed = false
    var journey = Journey()
    var pathMode: PathMode = .none     // 決まった道（螺旋・回る輪）
    var path = PathWalk()
    let game = GameInput()
    var onPad: ((String) -> Void)?           // コントローラーのボタン（A・B・X・Y・十字・メニュー）
    private var lastBand = -1
    var edrHead = 1.0           // 画面の明るさの余白（EDR）。1 なら普通の画面
    /// 線の芯の明るさの倍率：EDR の余白の範囲で、光る線の強さに合わせて（最大 3 倍）
    var edrBoost: Double { self.set.edrOn ? 1 + (min(edrHead, 3) - 1) * self.set.glow : 1 }
    var say: ((String) -> Void)?

    // 計測
    private(set) var fps: Double = 0
    private(set) var gpuMs: Double = 0
    private(set) var maxGap: Double = 0         // 0.5 秒の間で、コマとコマのいちばん長い間（ミリ秒）。引っかかりの目安
    private var gapRun = 0.0
    private var fpsN = 0, fpsT0 = CACurrentMediaTime(), gpuSum = 0.0, gpuN = 0
    private var lastT = CACurrentMediaTime()
    private let gpuLock = NSLock()
    var onStats: ((Renderer) -> Void)?
    private(set) var drawSize = CGSize(width: 1, height: 1)
    var frameCount = 0

    init?(device: MTLDevice) {
        self.device = device
        guard let q = device.makeCommandQueue() else { return nil }
        queue = q
        var opts = MTLCompileOptions()
        if ProcessInfo.processInfo.environment["S3_PRECISE"] != nil { opts.fastMathEnabled = false }   // 確かめ用：速い近似の数学関数を使わない
        var src = shaderSource
        switch ProcessInfo.processInfo.environment["S3_NEBTEST"] {      // 確かめ用：星雲のどこが重いか
        case "notex": src = src.replacingOccurrences(of: "float4 nn = nz.sample(sm, P * 0.3);", with: "float4 nn = float4(0.6, 0.5, 0.4, 0.0);")
        case "one": src = src.replacingOccurrences(of: "int n = clamp(int(ceil((t1 - t0) / u.nebStep)), 1, 28);", with: "int n = 1;")
        case "noblob": src = src.replacingOccurrences(of: "if (dens < 0.015) return o;", with: "return o;")
        default: break
        }
        shaderSrc = src; compileOpts = opts
        opts.preprocessorMacros = ["NEB": NSNumber(value: 0), "AXIS": NSNumber(value: 0)]
        do { library = try device.makeLibrary(source: src, options: opts); libs["00"] = library } catch {
            fputs("シェーダーの組み立てに失敗：\(error)\n", stderr); return nil
        }
        precondition(MemoryLayout<Uni>.stride == 256, "Uni の並びがシェーダーと合わない")
        super.init()
        game.onButton = { [weak self] k in DispatchQueue.main.async { self?.onPad?(k) } }
    }

    // ---- 景色のシェーダーの種類：星雲（NEB）・軸色の球層（AXIS）を使う時だけ、そのコードの入ったものを組み立てる ----
    private var shaderSrc = "", compileOpts = MTLCompileOptions(), libs: [String: MTLLibrary] = [:], pipesV: [String: MTLRenderPipelineState] = [:]
    var variant: String { (set.space && set.nebula && set.nebK > 0 ? "1" : "0") + (set.shAxis && set.shell ? "1" : "0") }
    /// ほかの種類（星雲・軸色）を裏で組み立てておく（切りかえた時に止まらないように）
    func prewarm() {
        for v in ["10", "01", "11"] where libs[v] == nil {
            let o = MTLCompileOptions(); o.fastMathEnabled = compileOpts.fastMathEnabled
            o.preprocessorMacros = ["NEB": NSNumber(value: v.first == "1" ? 1 : 0), "AXIS": NSNumber(value: v.last == "1" ? 1 : 0)]
            device.makeLibrary(source: shaderSrc, options: o) { [weak self] l, _ in
                guard let l else { return }
                DispatchQueue.main.async { if self?.libs[v] == nil { self?.libs[v] = l } }
            }
        }
    }
    func lib(_ v: String) -> MTLLibrary {
        if let l = libs[v] { return l }
        let o = MTLCompileOptions(); o.fastMathEnabled = compileOpts.fastMathEnabled
        o.preprocessorMacros = ["NEB": NSNumber(value: v.first == "1" ? 1 : 0), "AXIS": NSNumber(value: v.last == "1" ? 1 : 0)]
        let l = (try? device.makeLibrary(source: shaderSrc, options: o)) ?? library
        libs[v] = l; return l
    }
    func pipeline(_ fmt: MTLPixelFormat) -> MTLRenderPipelineState {
        let v = variant, key = "\(fmt.rawValue)-\(v)"
        if let p = pipesV[key] { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib(v).makeFunction(name: "vmain")
        d.fragmentFunction = lib(v).makeFunction(name: "fmain")
        d.colorAttachments[0].pixelFormat = fmt
        let p = try! device.makeRenderPipelineState(descriptor: d)
        pipesV[key] = p; return p
    }

    // ---- シェーダーへの値 ----
    /// 目印の玉の大きさの倍率（絵 1.5・色の点 1.9）
    var markBig: Double { self.set.mk == 1 ? 1.5 : self.set.mk == 2 ? 1.9 : 1.0 }
    /// いちばん内側の殻の、極からの距離（極の目印の玉より外に。ウェブ版の shellMinTheta）
    var shellMinTheta: Double { max(0.13 * markBig + 0.06, set.polePlanet && set.poles && set.mk != 1 ? Renderer.planetR + 0.05 : 0) }   // 惑星の時は惑星より外に
    static let planetR = 0.16
    lazy var atlas: MTLTexture? = Atlas.make(device)
    static let roomPlanes: [SIMD4<Float>] = Cell120.shared.planes.map { SIMD4<Float>($0) }
    func markers() -> [MkGPU] {
        var out: [MkGPU] = []
        let big = markBig * (set.grand ? 0.7 : 1.0) / set.uniR    // 絵・色の点の時は玉を大きめに。壮大モードは 7 割。宇宙が大きいほど、本当の大きさは同じなので角度では小さく
        func put(_ c: V4, _ col: SIMD3<Float>, _ r: Double, _ pic: String? = nil, planet: Bool = false) {
            guard out.count < 64 else { return }
            out.append(MkGPU(c: SIMD4<Float>(c), col: SIMD4<Float>(col.x, col.y, col.z, Float(r)), info: SIMD4(planet ? -1 : Float(pic.map { PIC.index($0) } ?? -1), planet ? 1 : 0, 0, 0)))
        }
        let none = set.mk == 3
        let planets = set.poles && set.polePlanet && set.mk != 1          // 極の惑星（見せ方が「なし」でも出す）
        if set.poles && (!none || planets) {
            for (k, m) in FIXED.enumerated() {
                if set.hideLabels.contains(m.label) { continue }
                if set.hidePair && m.pole && (0..<4).contains(where: { m.c[$0] < -0.5 }) { continue }
                if planets { put(m.c, poleCol(k), Renderer.planetR, planet: true) } else { put(m.c, m.col, m.r * big, PIC.poles[k]) }
            }
        }
        if set.marksOn && !none { for (i, p) in journey.marks.enumerated() { put(p, Journey.markColor(i), 0.1 * big, PIC.mark(i)) } }
        if set.foot { for p in journey.foot { put(p, [0.8, 0.85, 1], 0.03 * big, PIC.foot) } }
        for m in set.extra where !set.hideLabels.contains(m.label) { put(m.c, m.col, m.r) }
        if set.selfBall { put(cam.w.p, [1, 1, 1], (set.mk == 0 ? 0.09 : 0.13) / set.uniR, PIC.selfPic) }
        return out
    }
    func uniforms(width: Int, height: Int) -> Uni {
        let F = cam.viewFrame()
        var u = Uni()
        u.P = SIMD4<Float>(cam.w.p); u.R = SIMD4<Float>(F.R); u.U = SIMD4<Float>(F.U); u.F = SIMD4<Float>(F.L)
        u.L0 = SIMD4<Float>(nrm(F.R * -0.45 + F.U * 0.75 - F.L * 0.5))
        u.res = SIMD2(Float(width), Float(height))
        u.tanF = Float(tan(min(150, set.fov) * d2r / 2)); u.maxD = Float(set.maxD)
        // もや・透けは決まった距離でかかる（宇宙の大きさ R 倍）
        u.fog = Float(set.fog * (set.grand ? 1.6 : 1) * set.uniR); u.fade = Float(set.fade * set.uniR); u.uni = Float(set.uniR); u.depth = Float(set.depth)
        u.shellOp = Float(set.shellOp); u.shellBack = Float(set.shellBack); u.shellRange = Float(set.shellRange)
        u.shMin = Float(shellMinTheta)                              // いちばん内側の殻（極の玉より外に。ウェブ版の shellMinTheta）
        u.shellLum = Float(set.shellLum); u.gridSt = Float(set.grand ? Double.pi / 36 : Double.pi / 12)
        u.shellN = Int32(max(2, min(21, set.shellN))); u.shell = set.shell ? 1 : 0
        u.shellSolid = set.shellSolid ? 1 : 0; u.shellBare = set.shellBare ? 1 : 0; u.eq = set.eq ? 1 : 0
        u.passes = Int32(set.passes); u.orient = set.orient ? 1 : 0; u.lite = set.lite ? 1 : 0; u.webTies = set.webTies ? 1 : 0
        u.glow = Float(set.glow); u.edr = Float(edrBoost)
        u.pic = Int32(set.mk == 1 ? 1 : set.mk == 2 ? 2 : 0); u.ghostBack = set.ghostBack ? 1 : 0; u.picLine = Float(set.picLine)
        u.lens = Int32(set.lens)
        let fov = set.lens == 0 ? min(150, set.fov) : set.lens == 1 ? set.fov : 180
        u.fovY = Float(fov * d2r); u.tanF = Float(tan(min(150, set.fov) * d2r / 2))
        u.space = set.space ? 1 : 0; u.band = Float(set.band); u.wireFloor = Float(set.wireFloor)
        u.shAx = set.shAxis ? Int32((set.shAxX ? 1 : 0) | (set.shAxY ? 2 : 0) | (set.shAxZ ? 4 : 0) | (set.shAxW ? 8 : 0)) : 0
        if set.shAxis && u.shAx == 0 { u.shAx = 8 }                  // 軸を 1 つも選んでいない時は w だけ
        u.neb = set.space && set.nebula && set.nebK > 0 ? 1 : 0; u.nebK = Float(set.nebK); u.nebStep = 0.08
        if set.cine { u.edr = max(u.edr, 1.2) }                    // 映画のような光：線の芯は白より少し明るく（色の締めで丸め、あふれる光にもなる）
        u.circ = set.circ ? 1 : 0; u.room = set.room ? 1 : 0; u.lineW = set.lineCrisp ? Float(set.lineW) : 0; u.solidWire = Float(set.solidWire)
        u.pixAng = Float((set.lens == 2 ? Double.pi : fov * d2r) / Double(max(1, height)))
        return u
    }
    /// 殻の表：i 番目の殻の w の値（±cos θ）と色（ウェブ版のシェーダーの shellW・shellCol と同じ式を、1 コマに 1 回だけ）
    func shellTable() -> [SIMD4<Float>] {
        let n = max(2, min(21, set.shellN)), shMin = shellMinTheta
        func hsl2rgb(_ h: Double, _ s: Double, _ l: Double) -> SIMD3<Double> {
            func ch(_ o: Double) -> Double { let x = (h * 6 + o).truncatingRemainder(dividingBy: 6); return min(1, max(0, abs((x < 0 ? x + 6 : x) - 3) - 1)) }
            let rgb = SIMD3(ch(0), ch(4), ch(2))
            return l + s * (rgb - 0.5) * (1 - abs(2 * l - 1))
        }
        return (0..<(2 * n - 1)).map { i in
            let j = i < n ? i : 2 * n - 2 - i, t = Double(j) / Double(n - 1)
            let th = shMin + t * (Double.pi / 2 - shMin), wc = i < n ? cos(th) : -cos(th)
            let c = hsl2rgb(i < n ? t * 0.5 : 0.8 - t * 0.3, 0.95, 0.52)
            let lum = c.x * 0.299 + c.y * 0.587 + c.z * 0.114
            let k = min(0.55, max(0, (set.shellLum - lum) / (1 - lum)))
            let cc = c + (SIMD3(1, 1, 1) - c) * k
            return SIMD4<Float>(Float(wc), Float(cc.x), Float(cc.y), Float(cc.z))
        }
    }
    func encode(_ cb: MTLCommandBuffer, _ rpd: MTLRenderPassDescriptor, _ fmt: MTLPixelFormat, _ w: Int, _ h: Int) {
        guard set.cine else { encodeScene(cb, rpd, fmt, w, h); return }
        // 映画のような光：景色 → HDR の絵 → 明るい所を半分ずつ小さく集める → 大きくしながら足し戻す → 色を締めて画面へ
        let tx = postTextures(w, h)
        let srpd = MTLRenderPassDescriptor()
        srpd.colorAttachments[0].texture = tx.hdr; srpd.colorAttachments[0].loadAction = .dontCare; srpd.colorAttachments[0].storeAction = .store
        srpd.colorAttachments[1].texture = tx.neb; srpd.colorAttachments[1].loadAction = .clear; srpd.colorAttachments[1].clearColor = MTLClearColorMake(0, 0, 0, 0); srpd.colorAttachments[1].storeAction = .store
        encodeScene(cb, srpd, .rgba16Float, w, h, split: true)
        var pu = PostU(); pu.thr = 1.0; pu.knee = 0.35
        func pass(_ dst: MTLTexture, _ pipe: MTLRenderPipelineState, _ load: MTLLoadAction, _ srcs: [MTLTexture], _ p: PostU, _ r: MTLRenderPassDescriptor? = nil) {
            let d = r ?? { let d = MTLRenderPassDescriptor(); d.colorAttachments[0].texture = dst; d.colorAttachments[0].loadAction = load; d.colorAttachments[0].storeAction = .store; return d }()
            guard let e = cb.makeRenderCommandEncoder(descriptor: d) else { return }
            var q = p
            e.setRenderPipelineState(pipe)
            for (i, t) in srcs.enumerated() { e.setFragmentTexture(t, index: i) }
            e.setFragmentBytes(&q, length: MemoryLayout<PostU>.stride, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
            e.endEncoding()
        }
        var src = tx.hdr
        for (k, m) in tx.mips.enumerated() {
            pu.src = SIMD2(Float(src.width), Float(src.height)); pu.dst = SIMD2(Float(m.width), Float(m.height)); pu.first = k == 0 ? 1 : 0
            pass(m, postPipe("fdown", .rgba16Float, add: false), .dontCare, [src], pu); src = m
        }
        for k in stride(from: tx.mips.count - 1, to: 0, by: -1) {
            let a = tx.mips[k], b = tx.mips[k - 1]
            pu.src = SIMD2(Float(a.width), Float(a.height)); pu.dst = SIMD2(Float(b.width), Float(b.height)); pu.first = 0
            pass(b, postPipe("fup", .rgba16Float, add: true), .load, [a], pu)
        }
        pu.dst = SIMD2(Float(w), Float(h)); pu.inten = Float(set.bloom) / Float(tx.mips.count) * 2.2; pu.expo = Float(set.expo)
        pu.head = set.edrOn ? Float(max(1, min(edrHead, 4))) : 1; pu.grain = Float(set.grain); pu.vign = 0.22
        pu.time = Float(CACurrentMediaTime().truncatingRemainder(dividingBy: 100))
        pass(tx.hdr, postPipe("fcomp", fmt, add: false), .dontCare, [tx.hdr, tx.mips.first ?? tx.hdr, tx.neb], pu, rpd)
    }
    // ---- 光の仕上げの道具 ----
    private var postPipes: [String: MTLRenderPipelineState] = [:]
    private var postTex: (w: Int, h: Int, hdr: MTLTexture, neb: MTLTexture, mips: [MTLTexture])?
    func postPipe(_ f: String, _ fmt: MTLPixelFormat, add: Bool) -> MTLRenderPipelineState {
        let key = "\(f)-\(fmt.rawValue)-\(add)"
        if let p = postPipes[key] { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "vmain"); d.fragmentFunction = library.makeFunction(name: f)
        let c = d.colorAttachments[0]!; c.pixelFormat = fmt
        if add { c.isBlendingEnabled = true; c.sourceRGBBlendFactor = .one; c.destinationRGBBlendFactor = .one; c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .one }
        let p = try! device.makeRenderPipelineState(descriptor: d)
        postPipes[key] = p; return p
    }
    /// HDR の絵（画面と同じ大きさ）、星雲の光だけの絵、ブルームの段（半分ずつ、6 段まで）
    func postTextures(_ w: Int, _ h: Int) -> (hdr: MTLTexture, neb: MTLTexture, mips: [MTLTexture]) {
        if let t = postTex, t.w == w, t.h == h { return (t.hdr, t.neb, t.mips) }
        func tex(_ a: Int, _ b: Int) -> MTLTexture {
            let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba16Float, width: max(1, a), height: max(1, b), mipmapped: false)
            d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private
            return device.makeTexture(descriptor: d)!
        }
        let hdr = tex(w, h), neb = tex(w, h); var mips: [MTLTexture] = []; var a = w, b = h
        while mips.count < 6 && min(a, b) >= 16 { a /= 2; b /= 2; mips.append(tex(a, b)) }
        postTex = (w, h, hdr, neb, mips); return (hdr, neb, mips)
    }
    // ---- 星雲のかたまり（中心・色・広がり）と、模様のノイズの箱 ----
    /// 8 つ。アナ極（出発点）からは 0.8〜2.6 離して置く（出発してすぐガスの中、にならないように）。いつも同じ並び
    static let nebBlobs: [SIMD4<Float>] = {
        var x: UInt64 = 0x5DEECE66D
        func rnd() -> Double { x = x &* 6364136223846793005 &+ 1442695040888963407; return Double(x >> 11) / Double(1 << 53) }
        func gauss() -> Double { sqrt(-2 * log(max(1e-12, rnd()))) * cos(2 * Double.pi * rnd()) }
        let cols: [SIMD3<Float>] = [[1.0, 0.30, 0.62], [0.22, 0.72, 0.85], [1.0, 0.52, 0.22], [0.55, 0.32, 1.0], [1.0, 0.34, 0.36], [0.30, 0.52, 1.0], [0.32, 0.92, 0.62], [1.0, 0.80, 0.42]]
        var out: [SIMD4<Float>] = []
        var k = 0
        while k < 8 {
            let p = nrm(V4(gauss(), gauss(), gauss(), gauss())); let d = acos(max(-1, min(1, p.w)))
            if d < 0.8 || d > 2.6 { continue }
            out.append(SIMD4<Float>(p)); out.append(SIMD4(cols[k], Float(0.22 + 0.3 * rnd()))); k += 1
        }
        return out
    }()
    /// 64³ のくり返すノイズ（なめらかな値のノイズを 3 段重ね）を 3 つ、色の r・g・b に（r：大きなふさ、g：2 倍細かいすじ、b：ちり）。0〜1
    lazy var noise3D: MTLTexture? = {
        let N = 64
        var x: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Float { x ^= x << 13; x ^= x >> 7; x ^= x << 17; return Float(x % 1_000_000) / 1_000_000 }
        func fbm(_ octs: [(Int, Float)]) -> [Float] {
            var vol = [Float](repeating: 0, count: N * N * N)
            for (per, amp) in octs {
                let lat = (0..<(per * per * per)).map { _ in rnd() }
                func L(_ i: Int, _ j: Int, _ k: Int) -> Float { lat[((k % per) * per + (j % per)) * per + (i % per)] }
                let sc = Float(per) / Float(N)
                func sm(_ t: Float) -> Float { t * t * (3 - 2 * t) }
                func lerp(_ a: Float, _ b: Float, _ t: Float) -> Float { a + (b - a) * t }
                for k in 0..<N { for j in 0..<N { for i in 0..<N {
                    let fx = Float(i) * sc, fy = Float(j) * sc, fz = Float(k) * sc
                    let ix = Int(fx), iy = Int(fy), iz = Int(fz)
                    let tx = sm(fx - Float(ix)), ty = sm(fy - Float(iy)), tz = sm(fz - Float(iz))
                    let c00 = lerp(L(ix, iy, iz), L(ix + 1, iy, iz), tx), c10 = lerp(L(ix, iy + 1, iz), L(ix + 1, iy + 1, iz), tx)
                    let c01 = lerp(L(ix, iy, iz + 1), L(ix + 1, iy, iz + 1), tx), c11 = lerp(L(ix, iy + 1, iz + 1), L(ix + 1, iy + 1, iz + 1), tx)
                    vol[(k * N + j) * N + i] += amp * lerp(lerp(c00, c10, ty), lerp(c01, c11, ty), tz)
                } } }
            }
            return vol
        }
        let r = fbm([(8, 0.5), (16, 0.3), (32, 0.2)]), g = fbm([(16, 0.5), (32, 0.3), (64, 0.2)]), b = fbm([(16, 0.55), (32, 0.3), (64, 0.15)])
        var bytes = [UInt8](repeating: 255, count: N * N * N * 4)
        for i in 0..<(N * N * N) {
            bytes[4 * i] = UInt8(max(0, min(255, r[i] * 255))); bytes[4 * i + 1] = UInt8(max(0, min(255, g[i] * 255))); bytes[4 * i + 2] = UInt8(max(0, min(255, b[i] * 255)))
        }
        let d = MTLTextureDescriptor(); d.textureType = .type3D; d.pixelFormat = .rgba8Unorm; d.width = N; d.height = N; d.depth = N; d.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: d) else { return nil }
        bytes.withUnsafeBytes { t.replace(region: MTLRegionMake3D(0, 0, 0, N, N, N), mipmapLevel: 0, slice: 0, withBytes: $0.baseAddress!, bytesPerRow: N * 4, bytesPerImage: N * N * 4) }
        return t
    }()
    /// 景色（と星）を rpd に描く
    func encodeScene(_ cb: MTLCommandBuffer, _ rpd: MTLRenderPassDescriptor, _ fmt: MTLPixelFormat, _ w: Int, _ h: Int, split: Bool = false) {
        var u = uniforms(width: w, height: h)
        var mk = markers(); u.nm = Int32(mk.count)
        if mk.isEmpty { mk.append(MkGPU(c: .zero, col: .zero)) }
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(split ? pipelineMRT() : pipeline(fmt))
        enc.setFragmentBytes(&u, length: MemoryLayout<Uni>.stride, index: 0)
        enc.setFragmentBytes(mk, length: MemoryLayout<MkGPU>.stride * mk.count, index: 1)
        let sh = shellTable()
        enc.setFragmentBytes(sh, length: MemoryLayout<SIMD4<Float>>.stride * sh.count, index: 2)
        enc.setFragmentTexture(atlas, index: 0)
        enc.setFragmentBytes(Renderer.roomPlanes, length: MemoryLayout<SIMD4<Float>>.stride * 12, index: 3)
        enc.setFragmentBytes(Renderer.nebBlobs, length: MemoryLayout<SIMD4<Float>>.stride * Renderer.nebBlobs.count, index: 4)
        enc.setFragmentTexture(noise3D, index: 1)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if set.space && set.stars > 0, let sb = starBuf {             // 星：景色の透けて残った所（アルファ）にだけ足す
            var su = StarU(P: u.P, R: u.R, U: u.U, F: u.F, res: u.res, tanF: u.tanF, fovY: u.fovY, lens: u.lens, fog: Float(set.fog),   // 星は遠くの光：宇宙の大きさでもやを濃くしない
                          
                           lum: Float(set.stars), maxD: u.maxD, edr: set.cine ? 8 : Float(max(1, min(edrHead, 4))), px: max(1, Float(h) / 1000))
            enc.setRenderPipelineState(starPipeline(fmt, split: split))
            enc.setVertexBuffer(sb, offset: 0, index: 0)
            enc.setVertexBytes(&su, length: MemoryLayout<StarU>.stride, index: 1)
            enc.setFragmentBytes(&su, length: MemoryLayout<StarU>.stride, index: 0)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Renderer.starN * 2)
        }
        enc.endEncoding()
    }
    // ---- 星（宇宙の時）----
    static let starN = 12000
    private var starPipes: [MTLPixelFormat: MTLRenderPipelineState] = [:], starPipeMRT: MTLRenderPipelineState?, sceneMRT: MTLRenderPipelineState?
    /// 映画の光の時の景色：色（HDR の絵）と星雲の光（別の絵）を同時に書く
    func pipelineMRT() -> MTLRenderPipelineState {
        let v = variant, key = "mrt-\(v)"
        if let p = pipesV[key] { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = lib(v).makeFunction(name: "vmain"); d.fragmentFunction = lib(v).makeFunction(name: "fmainMRT")
        d.colorAttachments[0].pixelFormat = .rgba16Float; d.colorAttachments[1].pixelFormat = .rgba16Float
        let p = try! device.makeRenderPipelineState(descriptor: d)
        pipesV[key] = p; return p
    }
    lazy var starBuf: MTLBuffer? = { let s = Renderer.makeStars(Renderer.starN); return device.makeBuffer(bytes: s, length: MemoryLayout<StarGPU>.stride * s.count) }()
    func starPipeline(_ fmt: MTLPixelFormat, split: Bool = false) -> MTLRenderPipelineState {
        if !split, let p = starPipes[fmt] { return p }
        if split, let p = starPipeMRT { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "vstar"); d.fragmentFunction = library.makeFunction(name: "fstar")
        let c = d.colorAttachments[0]!; c.pixelFormat = fmt; c.isBlendingEnabled = true
        c.rgbBlendOperation = .add; c.sourceRGBBlendFactor = .destinationAlpha; c.destinationRGBBlendFactor = .one   // 色 += 星 × 透けて残った割合
        c.alphaBlendOperation = .add; c.sourceAlphaBlendFactor = .zero; c.destinationAlphaBlendFactor = .one
        if split { d.colorAttachments[1].pixelFormat = .rgba16Float; d.colorAttachments[1].writeMask = [] }   // 星雲の光の絵には書かない
        let p = try! device.makeRenderPipelineState(descriptor: d)
        if split { starPipeMRT = p } else { starPipes[fmt] = p }
        return p
    }
    /// 星を S³ にまく（いつも同じ並び）：半分ほどは天の川（大円 y・z のまわり）、1 割は星雲（もう 1 つの大円のまわり）、残りは一様。
    ///   色は青白・白・黄・橙、明るさはほとんど暗く、ごく一部が明るい。8 つの極のすぐそばには置かない
    static func makeStars(_ n: Int) -> [StarGPU] {
        var x: UInt64 = 0x9E3779B97F4A7C15
        func rnd() -> Double { x &+= 0x9E3779B97F4A7C15; var z = x; z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9; z = (z ^ (z >> 27)) &* 0x94D049BB133111EB; z ^= z >> 31; return Double(z >> 11) / Double(1 << 53) }
        func gauss() -> Double { sqrt(-2 * log(max(1e-12, rnd()))) * cos(2 * Double.pi * rnd()) }
        let h = 0.5.squareRoot()
        var out: [StarGPU] = []
        while out.count < n {
            let k = rnd(), s = rnd() * 2 * Double.pi
            var p: V4
            if k < 0.45 { p = V4(gauss() * 0.11, cos(s), sin(s), gauss() * 0.11) }
            else if k < 0.55 { let g1 = gauss() * 0.22, g2 = gauss() * 0.22; p = V4(h * (cos(s) + g1), h * (cos(s) - g1), h * (sin(s) + g2), h * (-sin(s) + g2)) }
            else { p = V4(gauss(), gauss(), gauss(), gauss()) }
            p = nrm(p)
            if FIXED.contains(where: { dot4($0.c, p) > cos(0.2) }) { continue }
            let t = rnd()
            let col: SIMD3<Float> = t < 0.5 ? [0.78, 0.86, 1] : t < 0.78 ? [1, 1, 1] : t < 0.92 ? [1, 0.9, 0.72] : [1, 0.72, 0.52]
            out.append(StarGPU(p: SIMD4<Float>(p), c: SIMD4(col, Float(0.3 + 2.4 * pow(rnd(), 6)))))
        }
        return out
    }

    // ---- 歩く（ウェブ版の loop の一部）----
    func step(_ dt: Double) {
        var sp = 0.9 * set.spd * dt * (shiftFast ? 3 : 1) / set.uniR   // 宇宙が大きいほど、同じ速さで進む角度は小さい
        var mv = SIMD3<Double>(0, 0, 0)
        if roaming { journey.roam(&cam, dt, set.roamK) }
        if pathMode != .none {                                   // 決まった道：自動で進む（キー・スティックで歩いたらやめる）
            let manual = keys.contains(where: { [13, 1, 0, 2, 12, 14].contains($0) }) || (set.gamepad && game.read().move != .zero)
            if manual { pathMode = .none; say?("決まった道をやめた（歩いた）") }
            else { pathStep(0.9 * set.spd * dt * (shiftFast ? 3 : 1) / set.uniR); return }
        }
        // ゲームコントローラー：スティックの倒し具合で速さも変わる
        var padMul = 1.0
        if set.gamepad {
            let g = game.read()
            let lx = g.look.x * (set.padInvX ? -1 : 1), ly = g.look.y * (set.padInvY ? -1 : 1)   // 右スティックの反転（左右・上下それぞれ）
            // 右スティック：進む向きを変える（矢印キー・Shift＋ドラッグ。地図も回る）。ZL を押しながらだと見回しだけ（頭だけ＝マウスのドラッグ。
            //   地図は回らず、水色の円すいが見ている向きを指す）。左スティックは進む向きへ歩く（W・S・A・D）。Y・右スティックの押し込みで前を見る（進む向きは変えない）、
            //   ZL を押して離すだけでも前を見る。ZL を押しながら Y で見ている向きを進む向きに（Enter）。見回しと進む向きは別（ウェブ版と同じ仕組み）。ここまでは「ゲームのような操作」のオン・オフによらない。
            //   ゲームのような操作：少し倒した時はゆっくり（倒し具合の 2 乗）・速めに回る・動き出し・止まりに慣性
            let game = set.padGame
            let cx = game ? lx * abs(lx) : lx, cy = game ? ly * abs(ly) : ly
            let turnX = game ? 140.0 : 90.0, turnY = game ? 100.0 : 60.0
            if cx != 0 || cy != 0 { leveling = false; headGoing = false }   // スティックを動かしたら、前を見る・この向きへ進むの途中はやめる
            if g.lookOnly {
                cam.hy += cx * turnX * dt; cam.hp += cy * turnY * dt
            } else {
                cam.az += cx * turnX * dt; cam.el += cy * turnY * dt
            }
            var target = g.move
            // 自走（歩き続ける）の時は、左スティックの前後はアクセル・ブレーキ・巻き戻し（前後には歩かない。左右は横歩きのまま）
            padThrottle = walking ? target.z : 0
            if walking { target.z = 0 }
            if game {
                padVel += (target - padVel) * min(1, dt * 6)
                if simd_length(padVel) < 0.02 && target == .zero { padVel = .zero }
            } else { padVel = target }
            // 加速：前でも後ろでも横でも、倒しきって（0.93 以上）0.3 秒たつと、1〜2 秒かけて 2.5 倍へ。戻すと早めに元へ
            let mag = (target.x * target.x + target.z * target.z).squareRoot()
            if g.push && !padPushWas { clearTrail() }                        // 左スティックの押し込み（L3）：軌跡（道すじ・足あと）を消す
            padPushWas = g.push
            padHold = mag > 0.93 ? padHold + dt : 0
            let goal = padHold > 0.3 ? 2.5 : 1.0
            padRun += (goal - padRun) * min(1, dt * (goal > padRun ? 1.6 : 5))
            if g.fast { padMul *= 3 }
            padMul *= padRun
            // ZL：押している間は右スティックで見回し。右スティックも Y も使わずに離したら、前を見る（進む向きへ目を戻す。進む向きは変えない）
            if g.lookOnly { if !padLookOnly { zlUsed = false }; if cx != 0 || cy != 0 { zlUsed = true } }
            else if padLookOnly && !zlUsed { levelView() }
            padLookOnly = g.lookOnly
            padMove = padVel
        } else { padMove = .zero; padVel = .zero; padRun = 1 }
        // 自走の速さ：前へ倒し続けるとだんだん速く（離すとその速さのまま）、手前へ倒すとブレーキ、止まってもまだ倒していると軌跡を巻き戻す
        if walking && !walkingWas { autoSpeed = 1; rewinding = false; rewindSpeed = 0 }
        walkingWas = walking
        if walking && set.gamepad {
            let th = padThrottle
            if th > 0.2 {
                if rewinding { rewinding = false; rewindSpeed = 0; autoSpeed = 0 }
                autoSpeed = min(set.autoMax, autoSpeed + set.autoAccel * th * dt * max(1, autoSpeed * 0.6))
            } else if th < -0.2 {
                if autoSpeed > 0.02 { autoSpeed = max(0, autoSpeed - 2.5 * -th * dt * max(1, autoSpeed)) }
                else if set.autoRewind {
                    if !rewinding { say?("巻き戻し：通ってきた軌跡を逆にたどる") }
                    autoSpeed = 0; rewinding = true; rewindSpeed = min(6, rewindSpeed + 1.5 * -th * dt)
                }
            } else if rewinding { rewinding = false; rewindSpeed = 0 }
            sp *= autoSpeed
        } else { rewinding = false }
        if rewinding { rewindStep(0.9 * set.spd * dt * max(0.3, rewindSpeed) / set.uniR) }
        // W（または歩き続ける・縦横無尽）。自動で進んでいる時に左スティックを倒すと、自動の前進はスティックに入れかわる
        //   （手前に倒すと後ろへ。足し合わせると前後が打ち消し合い、残った少しの横の傾きが全速の横歩きになってしまっていた）
        let keyWalk = keys.contains(where: { [13, 1, 0, 2, 12, 14].contains($0) })
        if keys.contains(13) { mv.z += 1 } else if (walking || roaming) && !rewinding { mv.z += max(0, 1 - min(1, simd_length(padMove))) }
        if keys.contains(1) { mv.z -= 1 }                     // S
        if keys.contains(0) { mv.x -= 1 }                     // A
        if keys.contains(2) { mv.x += 1 }                     // D
        if keys.contains(12) { mv.y += 1 }                    // Q
        if keys.contains(14) { mv.y -= 1 }                    // E
        mv += padMove
        // スティックの時の速さ：倒し具合（自動の前進と混ぜた長さ）× 加速。キーで歩いている時は倒し具合を見ない
        let padScale = padMove == .zero ? 1 : (keyWalk ? 1 : min(1, simd_length(mv))) * padMul
        let turn = 60 * dt * (shiftFast ? 2 : 1)
        if keys.contains(123) { cam.az -= turn }              // ←
        if keys.contains(124) { cam.az += turn }              // →
        if keys.contains(126) { cam.el += turn }              // ↑
        if keys.contains(125) { cam.el -= turn }              // ↓
        if leveling {
            let k = max(0, 1 - dt * 10); cam.hy *= k; cam.hp *= k; if levelEl { cam.el *= k }
            if (!levelEl || abs(cam.el) < 0.05) && abs(cam.hy) < 0.05 && abs(cam.hp) < 0.05 { if levelEl { cam.el = 0 }; cam.hy = 0; cam.hp = 0; leveling = false }
        }
        if headGoing && alignHeading(dt) { headGoing = false }
        cam.clampAngles(free: set.free360)
        if set.free360 && abs(cam.el) > 60 { rebaseBody() }               // 真上・真下へ近づいたら体の上下を整え直す（宙返りしても左右が逆にならない）
        if mv != .zero {
            // S³ と、S² の仲間を同じだけ進める（ウェブ版の walkStep：上下の成分は S² に無いので、斜めに上下する時は少しだけ進む）
            var s2 = sp * (padMove != .zero ? padScale : 1)
            let F = cam.lookFrame(), d = nrm(F.R * mv.x + F.U * mv.y + F.L * mv.z)   // 進む向きへ（見回していても。ウェブ版と同じ）
            let ca = cos(cam.az * d2r), sa = sin(cam.az * d2r), w2 = journey.w2
            let L2 = w2.f * ca + w2.r * sa, R2 = simd_normalize(w2.f * -sa + w2.r * ca), h2 = (mv.x * mv.x + mv.z * mv.z).squareRoot()
            if h2 > 1e-6 { s2 *= h2 / simd_length(mv); moveAlong2(&journey.w2, simd_normalize(R2 * mv.x + L2 * mv.z), s2) }
            moveAlong(&cam.w, d, s2)
            lastDir = nrm(d - cam.w.p * dot4(d, cam.w.p)); lastDirT = CACurrentMediaTime()
            journey.walked(cam.w.p, s2, footOn: set.foot) { [weak self] m in
                if self?.set.haptics == true { Haptic.milestone() }
                self?.say?(m)
            }
            // 球層の殻を通ったら、かすかな触覚（今いる殻と殻の間の番号が変わった時）
            if set.haptics && set.shell {
                let w = Float(cam.w.p.w), band = shellTable().filter { $0.x > w }.count
                if lastBand >= 0 && band != lastBand { Haptic.tick() }
                lastBand = band
            }
        }
    }
    /// 巻き戻し：通ってきた軌跡の点を、新しい方から順に ds だけ逆にたどる（体の向きはそのまま＝後ろ向きに戻る）。S² の仲間も同じ割合で
    func rewindStep(_ ds: Double) {
        var left = ds, n = 0
        while left > 1e-9 && n < 64 {
            n += 1
            guard let tgt = journey.trail.last else { rewinding = false; rewindSpeed = 0; say?("軌跡のはじまりまで戻った"); return }
            let p = cam.w.p, c = max(-1, min(1, dot4(p, tgt))), a = acos(c)
            if a < 1e-7 { journey.trail.removeLast(); if !journey.trail2.isEmpty { journey.trail2.removeLast() }; continue }
            let st = min(left, a), d = nrm(tgt - p * c)
            moveAlong(&cam.w, d, st)
            if let t2 = journey.trail2.last {
                let p2 = journey.w2.p, c2 = max(-1, min(1, simd_dot(p2, t2))), a2 = acos(c2)
                if a2 > 1e-7 { moveAlong2(&journey.w2, simd_normalize(t2 - p2 * c2), a2 * st / a) }
            }
            journey.dist = max(0, journey.dist - st); journey.lastTrail = journey.dist
            left -= st
            if st >= a - 1e-9 { journey.trail.removeLast(); if !journey.trail2.isEmpty { journey.trail2.removeLast() } }
        }
    }
    /// 体の枠を進む向きの枠に合わせ直す。S² の仲間は方位 az で進むので、その分だけ S² の枠も回して向きを保つ
    func rebaseBody() {
        let a = cam.az * d2r, w2 = journey.w2
        journey.w2.f = w2.f * cos(a) + w2.r * sin(a); journey.w2.r = w2.f * -sin(a) + w2.r * cos(a)
        cam.rebase()
    }
    /// 進む向きを、見ている向きへ少し回す（1 秒に 200° まで）。見ている向きは動かさない（見回しの角を新しい枠で出し直す）。そろったら true
    @discardableResult func alignHeading(_ dt: Double) -> Bool {
        let v = cam.viewFrame().L
        let taz = atan2(dot4(v, cam.w.r), dot4(v, cam.w.f)) / d2r, tel = asin(max(-1, min(1, dot4(v, cam.w.u)))) / d2r
        let da = (taz - cam.az + 540).truncatingRemainder(dividingBy: 360) - 180, de = tel - cam.el
        let turn = (da * da + de * de).squareRoot()
        if turn < 0.05 { cam.face(v); return true }
        let k = min(1, 200 * dt / turn)
        cam.az += da * k; cam.el = max(-89, min(89, cam.el + de * k))
        let F = cam.lookFrame()
        cam.hp = asin(max(-1, min(1, dot4(v, F.U)))) / d2r; cam.hy = atan2(dot4(v, F.R), dot4(v, F.L)) / d2r
        return false
    }
    // ---- 中の景色の上の 8 つの極（ウェブ版の poleLabels）：色の点と「名前 距離」。遠い極ほど点が小さい ----
    struct PoleLab { var x: Double; var y: Double; var name: String; var col: SIMD3<Float>; var d: Double; var isN: Bool }
    var onPoles: (([PoleLab]) -> Void)?
    /// 極の点の色（ウェブ版の dotCss）：軸の色の球層の時はその軸の色、ふだんは地図と同じ色
    func poleCol(_ k: Int) -> SIMD3<Float> {
        if set.shAxis { let i = FIXED[k].c.indices.first { abs(FIXED[k].c[$0]) > 0.5 } ?? 3; return AXIS_RGB[i] }
        return MapRenderer.poleDotCol(k)
    }
    /// 自分の枠での向き（右・上・前）→ 画面の位置（−1〜1、ウェブ版の poleScreen）。写らなければ nil
    func screenPos(_ dr: Double, _ du: Double, _ dl: Double, aspect: Double) -> (Double, Double)? {
        if set.lens == 1 {
            let ang = acos(max(-1, min(1, dl))), r = ang / (set.fov * d2r / 2), l = max(1e-9, (dr * dr + du * du).squareRoot())
            return ang < Double.pi - 1e-3 ? (r * dr / l / aspect, r * du / l) : nil
        }
        if set.lens == 2 { return (atan2(dr, dl) / Double.pi, asin(max(-1, min(1, du))) / (Double.pi / 2)) }
        guard dl > 1e-3 else { return nil }
        let tf = tan(set.fov * d2r / 2)
        return (dr / dl / (tf * aspect), du / dl / tf)
    }
    func poleLabels(aspect: Double) -> [PoleLab] {
        guard set.poles && set.mk != 1 else { return [] }                 // 絵のモードでは、極はいつもの絵のまま（ウェブ版と同じ）
        let F = cam.viewFrame(), p = cam.w.p
        var out: [PoleLab] = []
        for (k, m) in FIXED.enumerated() {
            let c = max(-1, min(1, dot4(p, m.c))), t = acos(c)
            let dv = m.c - p * c, l = simd_length(dv)
            guard l > 1e-6, t <= set.maxD, let sp = screenPos(dot4(dv, F.R) / l, dot4(dv, F.U) / l, dot4(dv, F.L) / l, aspect: aspect),
                  abs(sp.0) <= 1.02, abs(sp.1) <= 1.02 else { continue }
            out.append(PoleLab(x: sp.0, y: sp.1, name: MapRenderer.poleName(m) + " " + String(format: "%.2f", t), col: poleCol(k), d: t, isN: m.label == "N"))
        }
        return out
    }
    /// 軌跡（道すじと足あと）を消す。場所はそのまま（ウェブ版の「道すじを消す」）
    func clearTrail() {
        journey.trail = []; journey.trail2 = []; journey.foot = []; journey.foot2 = []
        say?("軌跡（道すじ・足あと）を消した")
    }
    /// アナ極に戻る（ウェブ版の resetNorth・R キー）。置いた目印は残す
    func resetNorth() {
        let marks = journey.marks, marks2 = journey.marks2
        cam = Camera(); journey = Journey(); journey.marks = marks; journey.marks2 = marks2
        walking = false; roaming = false; pathMode = .none
    }
    /// ここに目印を置く（ウェブ版の addMark・M キー）
    func addMark() {
        journey.marks.append(cam.w.p); journey.marks2.append(journey.w2.p)
        say?("目印 \(journey.marks.count) を置いた（ぐるっと回って戻ってくると、また会える）")
    }

    // ---- MTKViewDelegate ----
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) { drawSize = size }

    func draw(in view: MTKView) {
        let now = CACurrentMediaTime(); gapRun = max(gapRun, (now - lastT) * 1000); let dt = min(0.05, now - lastT); lastT = now
        step(dt)
        onPoles?(poleLabels(aspect: view.drawableSize.width / max(1, view.drawableSize.height)))
        guard let rpd = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let cb = queue.makeCommandBuffer() else { return }
        let w = Int(view.drawableSize.width), h = Int(view.drawableSize.height)
        encode(cb, rpd, view.colorPixelFormat, w, h)
        cb.addCompletedHandler { [weak self] cb in
            guard let self else { return }
            let g = (cb.gpuEndTime - cb.gpuStartTime) * 1000
            self.gpuLock.lock(); if g > 0 { self.gpuSum += g; self.gpuN += 1 }; self.gpuLock.unlock()
        }
        cb.present(drawable)
        cb.commit()
        frameCount += 1; fpsN += 1
        if now - fpsT0 >= 0.5 {
            fps = Double(fpsN) / (now - fpsT0); fpsN = 0; fpsT0 = now; maxGap = gapRun; gapRun = 0
            gpuLock.lock(); if gpuN > 0 { gpuMs = gpuSum / Double(gpuN) }; gpuSum = 0; gpuN = 0; gpuLock.unlock()
            onStats?(self)
        }
    }

    // ---- 画面の外に描いて画素を読む（確かめ・計測用）----
    func renderOffscreen(width: Int, height: Int) -> [Float] {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget]; td.storageMode = .shared
        let tex = device.makeTexture(descriptor: td)!
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex; rpd.colorAttachments[0].loadAction = .clear; rpd.colorAttachments[0].storeAction = .store
        let cb = queue.makeCommandBuffer()!
        encode(cb, rpd, .rgba32Float, width, height)
        cb.commit(); cb.waitUntilCompleted()
        var px = [Float](repeating: 0, count: width * height * 4)
        tex.getBytes(&px, bytesPerRow: width * 16, from: MTLRegionMake2D(0, 0, width, height), mipmapLevel: 0)
        return px
    }
    /// 画面の外に n コマ続けて描いて、1 コマの GPU の時間（ミリ秒）。1 コマずつ待つと GPU が休んで遅く出るので、続けて流す
    func benchmark(width: Int, height: Int, frames n: Int = 120) -> Double {
        let td = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: width, height: height, mipmapped: false)
        td.usage = [.renderTarget]; td.storageMode = .private
        let tex = device.makeTexture(descriptor: td)!
        let rpd = MTLRenderPassDescriptor()
        rpd.colorAttachments[0].texture = tex; rpd.colorAttachments[0].loadAction = .dontCare; rpd.colorAttachments[0].storeAction = .store
        func run(_ k: Int) -> Double {
            var cbs: [MTLCommandBuffer] = []
            for _ in 0..<k {
                let cb = queue.makeCommandBuffer()!
                encode(cb, rpd, .bgra8Unorm, width, height); cb.commit(); cbs.append(cb)
                cam.walk([0, 0, 1], 0.004)                    // 少しずつ歩きながら（同じ絵ばかりにならないように）
            }
            cbs.last!.waitUntilCompleted()
            return (cbs.last!.gpuEndTime - cbs.first!.gpuStartTime) * 1000 / Double(k)
        }
        _ = run(20)                                           // 暖める
        return run(n)
    }
}
