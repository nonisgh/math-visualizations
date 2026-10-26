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
    var glow: Float = 0, edr: Float = 1, band: Float = 0, gpad1: Float = 0
    var pic: Int32 = 0, ghostBack: Int32 = 0, lens: Int32 = 0, upad0: Int32 = 0
    var fovY: Float = 0, picLine: Float = 0.3, upad1: Float = 0, upad2: Float = 0
    var circ: Int32 = 0, room: Int32 = 0, space: Int32 = 0, tpad1: Int32 = 0
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
        let opts = MTLCompileOptions()
        if ProcessInfo.processInfo.environment["S3_PRECISE"] != nil { opts.fastMathEnabled = false }   // 確かめ用：速い近似の数学関数を使わない
        do { library = try device.makeLibrary(source: shaderSource, options: opts) } catch {
            fputs("シェーダーの組み立てに失敗：\(error)\n", stderr); return nil
        }
        precondition(MemoryLayout<Uni>.stride == 256, "Uni の並びがシェーダーと合わない")
        super.init()
        game.onButton = { [weak self] k in DispatchQueue.main.async { self?.onPad?(k) } }
    }

    func pipeline(_ fmt: MTLPixelFormat) -> MTLRenderPipelineState {
        if let p = pipes[fmt] { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "vmain")
        d.fragmentFunction = library.makeFunction(name: "fmain")
        d.colorAttachments[0].pixelFormat = fmt
        let p = try! device.makeRenderPipelineState(descriptor: d)
        pipes[fmt] = p; return p
    }

    // ---- シェーダーへの値 ----
    /// 目印の玉の大きさの倍率（絵 1.5・色の点 1.9）
    var markBig: Double { self.set.mk == 1 ? 1.5 : self.set.mk == 2 ? 1.9 : 1.0 }
    /// いちばん内側の殻の、極からの距離（極の目印の玉より外に。ウェブ版の shellMinTheta）
    var shellMinTheta: Double { 0.13 * markBig + 0.06 }
    lazy var atlas: MTLTexture? = Atlas.make(device)
    static let roomPlanes: [SIMD4<Float>] = Cell120.shared.planes.map { SIMD4<Float>($0) }
    func markers() -> [MkGPU] {
        var out: [MkGPU] = []
        let big = markBig * (set.grand ? 0.7 : 1.0)               // 絵・色の点の時は玉を大きめに。壮大モードは 7 割
        func put(_ c: V4, _ col: SIMD3<Float>, _ r: Double, _ pic: String? = nil) {
            guard out.count < 64 else { return }
            out.append(MkGPU(c: SIMD4<Float>(c), col: SIMD4<Float>(col.x, col.y, col.z, Float(r)), info: SIMD4(Float(pic.map { PIC.index($0) } ?? -1), 0, 0, 0)))
        }
        let none = set.mk == 3
        if set.poles && !none {
            for (k, m) in FIXED.enumerated() {
                if set.hideLabels.contains(m.label) { continue }
                if set.hidePair && m.pole && (0..<4).contains(where: { m.c[$0] < -0.5 }) { continue }
                put(m.c, m.col, m.r * big, PIC.poles[k])
            }
        }
        if set.marksOn && !none { for (i, p) in journey.marks.enumerated() { put(p, Journey.markColor(i), 0.1 * big, PIC.mark(i)) } }
        if set.foot { for p in journey.foot { put(p, [0.8, 0.85, 1], 0.03 * big, PIC.foot) } }
        for m in set.extra where !set.hideLabels.contains(m.label) { put(m.c, m.col, m.r) }
        if set.selfBall { put(cam.w.p, [1, 1, 1], set.mk == 0 ? 0.09 : 0.13, PIC.selfPic) }
        return out
    }
    func uniforms(width: Int, height: Int) -> Uni {
        let F = cam.viewFrame()
        var u = Uni()
        u.P = SIMD4<Float>(cam.w.p); u.R = SIMD4<Float>(F.R); u.U = SIMD4<Float>(F.U); u.F = SIMD4<Float>(F.L)
        u.L0 = SIMD4<Float>(nrm(F.R * -0.45 + F.U * 0.75 - F.L * 0.5))
        u.res = SIMD2(Float(width), Float(height))
        u.tanF = Float(tan(min(150, set.fov) * d2r / 2)); u.maxD = Float(set.maxD)
        u.fog = Float(set.fog * (set.grand ? 1.6 : 1)); u.fade = Float(set.fade); u.uni = 1; u.depth = Float(set.depth)
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
        u.space = set.space ? 1 : 0; u.band = Float(set.band)
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
        var u = uniforms(width: w, height: h)
        var mk = markers(); u.nm = Int32(mk.count)
        if mk.isEmpty { mk.append(MkGPU(c: .zero, col: .zero)) }
        guard let enc = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        enc.setRenderPipelineState(pipeline(fmt))
        enc.setFragmentBytes(&u, length: MemoryLayout<Uni>.stride, index: 0)
        enc.setFragmentBytes(mk, length: MemoryLayout<MkGPU>.stride * mk.count, index: 1)
        let sh = shellTable()
        enc.setFragmentBytes(sh, length: MemoryLayout<SIMD4<Float>>.stride * sh.count, index: 2)
        enc.setFragmentTexture(atlas, index: 0)
        enc.setFragmentBytes(Renderer.roomPlanes, length: MemoryLayout<SIMD4<Float>>.stride * 12, index: 3)
        enc.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        if set.space && set.stars > 0, let sb = starBuf {             // 星：景色の透けて残った所（アルファ）にだけ足す
            var su = StarU(P: u.P, R: u.R, U: u.U, F: u.F, res: u.res, tanF: u.tanF, fovY: u.fovY, lens: u.lens, fog: u.fog,
                           lum: Float(set.stars), maxD: u.maxD, edr: Float(max(1, min(edrHead, 4))), px: max(1, Float(h) / 1000))
            enc.setRenderPipelineState(starPipeline(fmt))
            enc.setVertexBuffer(sb, offset: 0, index: 0)
            enc.setVertexBytes(&su, length: MemoryLayout<StarU>.stride, index: 1)
            enc.setFragmentBytes(&su, length: MemoryLayout<StarU>.stride, index: 0)
            enc.drawPrimitives(type: .point, vertexStart: 0, vertexCount: Renderer.starN * 2)
        }
        enc.endEncoding()
    }
    // ---- 星（宇宙の時）----
    static let starN = 12000
    private var starPipes: [MTLPixelFormat: MTLRenderPipelineState] = [:]
    lazy var starBuf: MTLBuffer? = { let s = Renderer.makeStars(Renderer.starN); return device.makeBuffer(bytes: s, length: MemoryLayout<StarGPU>.stride * s.count) }()
    func starPipeline(_ fmt: MTLPixelFormat) -> MTLRenderPipelineState {
        if let p = starPipes[fmt] { return p }
        let d = MTLRenderPipelineDescriptor()
        d.vertexFunction = library.makeFunction(name: "vstar"); d.fragmentFunction = library.makeFunction(name: "fstar")
        let c = d.colorAttachments[0]!; c.pixelFormat = fmt; c.isBlendingEnabled = true
        c.rgbBlendOperation = .add; c.sourceRGBBlendFactor = .destinationAlpha; c.destinationRGBBlendFactor = .one   // 色 += 星 × 透けて残った割合
        c.alphaBlendOperation = .add; c.sourceAlphaBlendFactor = .zero; c.destinationAlphaBlendFactor = .one
        let p = try! device.makeRenderPipelineState(descriptor: d)
        starPipes[fmt] = p; return p
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
        let sp = 0.9 * set.spd * dt * (shiftFast ? 3 : 1)
        var mv = SIMD3<Double>(0, 0, 0)
        if roaming { journey.roam(&cam, dt, set.roamK) }
        if pathMode != .none {                                   // 決まった道：自動で進む（キー・スティックで歩いたらやめる）
            let manual = keys.contains(where: { [13, 1, 0, 2, 12, 14].contains($0) }) || (set.gamepad && game.read().move != .zero)
            if manual { pathMode = .none; say?("決まった道をやめた（歩いた）") }
            else { pathStep(0.9 * set.spd * dt * (shiftFast ? 3 : 1)); return }
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
                cam.hy += cx * turnX * dt; cam.hp = max(-89, min(89, cam.hp + cy * turnY * dt))
            } else {
                cam.az += cx * turnX * dt; cam.el = max(-89, min(89, cam.el + cy * turnY * dt))
            }
            let target = g.move
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
        // W（または歩き続ける・縦横無尽）。自動で進んでいる時に左スティックを倒すと、自動の前進はスティックに入れかわる
        //   （手前に倒すと後ろへ。足し合わせると前後が打ち消し合い、残った少しの横の傾きが全速の横歩きになってしまっていた）
        let keyWalk = keys.contains(where: { [13, 1, 0, 2, 12, 14].contains($0) })
        if keys.contains(13) { mv.z += 1 } else if walking || roaming { mv.z += max(0, 1 - min(1, simd_length(padMove))) }
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
        cam.clampAngles()
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
