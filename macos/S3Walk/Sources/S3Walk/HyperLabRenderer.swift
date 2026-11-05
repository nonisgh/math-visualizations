// 超球の窓の描く係（左の 3D の球・右の超球・地図）
import SwiftUI
import MetalKit
import CoreVideo

/// 左右どちらかの画面を描く
final class HyperLabRenderer: NSObject, MTKViewDelegate {
    enum Side { case left, right }
    let side: Side, st: HyperLabState
    /// 全体像（ダイブ中に 3D の球の場所へ出す、ダイブしていない超球）：ダイブは見ない
    var overview = false
    var diveWipe = false                                              // ダイブ画面の窓：本体がダイブしていない間も、ダイブの絵を描く（音・記録はしない）
    var wipeFirst = false                                             // ダイブ画面の窓を、三人称の設定によらず一人称で描く
    var wipeMain = false                                              // 「両方」のダイブ画面：3D の球がなくなるので、代わりに受け持つ
    var ovMotion = false                                              // 全体像のうち、Y-W 地図（球層を横から見る）。ふつうの全体像は自分地図
    // 動画の書き出し（記録 → 書き出し）で、記録した時刻・拍・細かさで描き直すための差しかえ。nil ならふだんどおり
    var clockOverride: Double? = nil, domOverride: Double? = nil, renderKOverride: Double? = nil
    var nowT: Double { clockOverride ?? CACurrentMediaTime() }
    var rK: Double { renderKOverride ?? HyperLabState.renderK }
    /// いま画面に出ている、右の超球の画面（記録はこの画面から取る）
    static weak var liveMain: HyperLabRenderer?
    static var liveRightW = 1390.0
    /// 誘導灯の光とドミノの拍（彗星の音のうなり 6 つで 1 回。音が鳴っていない時は 4 秒ごと）
    static func domClock(_ now: Double) -> Double {
        let b = HyperSound.shared.beatClock()
        return now - b.stamp < 0.4 && b.rate > 0.05 ? (b.cyc + b.rate * (now - b.stamp)) / 6 : now / 4.0
    }
    var dvT: Double { overview ? 0 : diveWipe ? 1 : st.diveT }
    var dvFade: Double { overview || diveWipe ? 0 : st.diveFade }
    var dvThird: Double { overview || wipeFirst ? 0 : st.thirdK }
    /// 今いる所の印（全体像は別に選べる。−1 ならふつうと同じ）
    var cur: Int { overview && st.ovCursor >= 0 ? st.ovCursor : st.cursor }
    /// ヘビーモードで描くか（小さい地図は普通のまま）
    var heavyHere: Bool { st.heavy && !overview && !diveWipe && side == .right }
    let device: MTLDevice, queue: MTLCommandQueue
    var opaquePipe: MTLRenderPipelineState!, alphaPipe: MTLRenderPipelineState!
    var depthWrite: MTLDepthStencilState!, depthRead: MTLDepthStencilState!, depthAlways: MTLDepthStencilState!
    var tris: [HLVert] = [], glass: [HLVert] = [], lines: [HLVert] = []
    var triBuf: MTLBuffer?, glassBuf: MTLBuffer?, lineBuf: MTLBuffer?
    /// 右：層ごとの範囲（殻の面・その層の線）。ウェブ版（three.js）と同じく、層の順に「面 → 線」と描く
    var ranges: [(g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>)] = []   // c：殻の中心、e：殻の上の 1 点（どちらも S³ の半径を 1 とした 4D の点）
    /// 右：元の 4D の点・層の色・つなぎ方（三角形と線の番号）。層数・半球が変わった時だけ作る
    var rBase: MTLBuffer?, rCol: MTLBuffer?, rIdx: MTLBuffer?, rMesh = 48, rSub = 4, rBaseW: MTLBuffer?, rIdxW: MTLBuffer?, rMeshW = 48
    var rPipe: MTLRenderPipelineState!, dsPipe: MTLRenderPipelineState!, mirPipe: MTLRenderPipelineState!, mirTex: MTLTexture?
    var polyArmSeen = 0
    weak var paneView: MTKView?                                       // 画面（ナイフの点の座標を、画面の大きさで写す）
    var tun = TunnelCam(), tunAddPipe: MTLRenderPipelineState!            // トンネルのカメラ・足し合わせの描き方
    var knifeSizeOverride: CGSize? = nil                              // 確かめの絵：画面の代わりの大きさ（画素）
    var knifeMVP = matrix_identity_float4x4, knifeWasDown = false, knifeStartLon: Double? = nil, knifePrevLon = 0.0, knifeSpan = 0.0   // ナイフ：今のコマの写し方・押していたか・押した経度・前の経度・切った幅（回り込みも足す）
    var wirePipe: MTLRenderPipelineState!, wirePipeAdd: MTLRenderPipelineState!, segPipe: MTLRenderPipelineState!
    var ringPipe: MTLRenderPipelineState!, ringMesh: MTLBuffer?, ringMeshCount = 0, rings: [HLRing] = []
    var leftRings: [(rho: Double, h: Double, col: SIMD3<Float>)] = []
    var rPipeAdd: MTLRenderPipelineState!, starPipe: MTLRenderPipelineState!, bgPipe: MTLRenderPipelineState!, bgMakePipe: MTLRenderPipelineState!
    var bgTex: MTLTexture?                                    // 宇宙の背景の絵（大きさが変わった時だけ作る。毎コマ星雲を計算すると重い）
    var bgTex2: MTLTexture?
    /// 天の川：S³ の大きな球面（法線 milkyN に垂直な S²）のまわりに、細かい星と、ぼんやりした光の雲。寄ると見える
    static let milkyN = simd_normalize(SIMD4<Float>(0.35, 0.55, -0.25, 0.72))
    lazy var milkyBufs: (dust: MTLBuffer?, haze: MTLBuffer?, nd: Int, nh: Int) = {
        var seed: UInt64 = 0x2545F4914F6CDD1D
        func rnd() -> Float { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Float(seed % 1_000_000) / 1_000_000 }
        func gauss() -> Float { let u = max(1e-6, rnd()), v = rnd(); return (-2 * log(u)).squareRoot() * cos(2 * .pi * v) }
        let n = Self.milkyN
        func make(_ count: Int, _ thick: Float, _ bright: ClosedRange<Float>) -> [StarGPU] {
            var out: [StarGPU] = []; out.reserveCapacity(count)
            while out.count < count {
                var p = SIMD4<Float>(gauss(), gauss(), gauss(), gauss()); p = simd_normalize(p)
                let d = simd_dot(p, n); p -= n * d; p = simd_normalize(p)                 // 帯の上へ
                p = simd_normalize(p + n * gauss() * thick)                               // 帯の厚み
                // 濃いところと薄いところ（ちぎれた雲のように）
                let cl = 0.5 + 0.5 * sin(p.x * 7.1 + p.y * 3.3) * sin(p.z * 5.7 - p.w * 4.1 + 1.3)
                if rnd() > 0.25 + 0.75 * cl { continue }
                let warm = rnd()
                let c = simd_mix(SIMD3<Float>(0.72, 0.82, 1.0), SIMD3<Float>(1.0, 0.88, 0.72), SIMD3(repeating: warm))
                out.append(StarGPU(p: p, c: SIMD4(c, bright.lowerBound + (bright.upperBound - bright.lowerBound) * rnd() * rnd())))
            }
            return out
        }
        let dust = make(30000, 0.06, 0.15...1.4)
        // 天の川の淡い光：さんぽの景色と同じ、大きな円（y・z の円。北極・南極・天極・地極を通る）のまわり（Renderer.makeStars の天の川の星と同じ広がり 0.11）
        var haze: [StarGPU] = []
        while haze.count < 6000 {
            let s = Double(rnd()) * 2 * .pi, g1 = Double(gauss()) * 0.13, g2 = Double(gauss()) * 0.13
            let p = simd_normalize(SIMD4<Float>(Float(g1), Float(cos(s)), Float(sin(s)), Float(g2)))
            let cl = 0.55 + 0.45 * sin(Float(s) * 5 + 1.3) * sin(Float(s) * 3.1 - 0.4)   // 濃いところと薄いところ
            if rnd() > cl { continue }
            let warm = rnd()
            haze.append(StarGPU(p: p, c: SIMD4(simd_mix(SIMD3<Float>(0.62, 0.74, 1.0), SIMD3<Float>(0.95, 0.88, 1.0), SIMD3(repeating: warm)), 0.08 + 0.2 * rnd())))
        }
        func buf(_ a: [StarGPU]) -> MTLBuffer? { a.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count) } }
        return (buf(dust), buf(haze), dust.count, haze.count)
    }()
    /// 寄った時の天の川の淡い光（右の画面・ダイブで寄るほど。さんぽの景色と同じ y・z の円のまわり）。dust の帯は使っていない（さんぽと位置が合わない）
    ///   haze：ぼんやりした光の雲だけを、いちばん奥の背景として（網目より先に・奥行きを見ずに。網目の影が雲に浮き出ないように）。ほかは細かい星
    func drawMilkyWay(_ e: MTLRenderCommandEncoder, _ u: HLUni, _ h: HLRight, _ z: Float, haze: Bool) {
        guard z > 0.02 else { return }
        let mb = milkyBufs
        var uu = u, hh = h; uu.cut = .zero
        var tz = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), 0.3 * z, z, 0)   // またたきは控えめ。z：遠近
        e.setRenderPipelineState(starPipe); e.setDepthStencilState(haze ? depthAlways : depthRead)
        e.setVertexBytes(&uu, length: MemoryLayout<HLUni>.stride, index: 1); e.setVertexBytes(&hh, length: MemoryLayout<HLRight>.stride, index: 2)
        e.setVertexBytes(&tz, length: 16, index: 4); e.setFragmentBytes(&tz, length: 16, index: 4)
        if haze, let b = mb.haze {                                        // 天の川の淡い光（大きく・とても淡く。遠くの光なので遠近で消さない）
            var k = SIMD4<Float>(0.75, 0, 1, 0.19 * z)   // 帯に集まっているので少し強めに（強すぎるとまぶしい・画面が白い雲で覆われる）
            var tz2 = tz; tz2.y = 0; tz2.z = 0; tz2.w = 0; e.setVertexBytes(&tz2, length: 16, index: 4); e.setFragmentBytes(&tz2, length: 16, index: 4)
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&k, length: 16, index: 3)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: mb.nh)
            e.setVertexBytes(&tz, length: 16, index: 4); e.setFragmentBytes(&tz, length: 16, index: 4)
        }
        if !haze, let b = mb.dust {                                       // 細かい星（またたく）
            var k = SIMD4<Float>(0.026, 0, 1, 1.0 * z)   // 星くず：景色と同じように星があると分かるくらい、ごく淡く小さく
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&k, length: 16, index: 3)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: mb.nd)
        }
    }
    lazy var starBuf: MTLBuffer? = { let s = Renderer.starList; return device.makeBuffer(bytes: s, length: MemoryLayout<StarGPU>.stride * s.count) }()
    var cometPipe: MTLRenderPipelineState!
    var lbPipe: MTLRenderPipelineState!, labelTex: [String: MTLTexture] = [:]
    /// 左：2 倍の大きさで描くための絵（変わった時だけ作る）
    var ssTex: (ms: MTLTexture, dep: MTLTexture, hi: MTLTexture)?
    var builtKey = "", lastT = CACurrentMediaTime(), fpsN = 0, fpsT = CACurrentMediaTime()
    /// コマ数を動きに合わせる：見た目に関わる値の組（前のコマと同じなら「止まっている」）・止まっている時間・画面のいちばん速いコマ数
    var lastSig: [Double] = [], stillT = 0.0, lowFPS = false, maxFPS = 60, moveFPS = 60
    var pN = 0, pT = 0.0, slowS = 0, fastS = 0          // 実際のコマ数を数える（1 秒ごと）・遅い／速い秒が続いた数
    /// 描く画素の数を画質に合わせる（画面の細かさ × renderK）。画面には拡大して出す
    static func fit(_ view: MTKView, extra: Double = 1) {
        #if os(macOS)
        let bs = view.window?.backingScaleFactor ?? 2
        #else
        let bs = view.window?.screen.scale ?? UIScreen.main.scale
        #endif
        let k = HyperLabState.renderK * extra
        let want = CGSize(width: max(8, (view.bounds.width * bs * k).rounded()), height: max(8, (view.bounds.height * bs * k).rounded()))
        if view.autoResizeDrawable { view.autoResizeDrawable = false }
        if view.drawableSize != want { view.drawableSize = want }
    }
    static let idleFPS = 10, idleAfter = 0.6
    static let R = 1.35, SCALE = 1.55, MIN_THETA = 0.08
    static let nearFade: Float = 0.1                                  // ダイブの三人称：カメラからこの距離（自分の所までの半径に対して）より近い殻を溶かす。一人称は自分が殻の中にいるので溶かさない

    init?(side: Side, state: HyperLabState, view: MTKView?) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        self.side = side; st = state; device = d; queue = q
        super.init()
        if let view {
            paneView = view
            view.device = d; view.colorPixelFormat = .bgra8Unorm
            // 左は自分で 2 倍の大きさに描いて縮めるので、画面そのものは 1 点・奥行きなし。右は画面に 4 倍のなめらかさ（マルチサンプル）で
            if side == .left { view.depthStencilPixelFormat = .invalid; view.sampleCount = 1 } else { view.depthStencilPixelFormat = .depth32Float; view.sampleCount = 4 }
            view.clearColor = MTLClearColor(red: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
            // 画面のいちばん速いコマ数で（144 Hz の画面なら 144。120 にすると 144 の半分の 72 になってしまう。ウェブ版と同じぬるぬる）
            #if os(macOS)
            maxFPS = NSScreen.screens.map { $0.maximumFramesPerSecond }.max() ?? 60
            #else
            maxFPS = UIScreen.main.maximumFramesPerSecond
            #endif
            view.preferredFramesPerSecond = maxFPS; moveFPS = maxFPS
        }
        let lib = try! d.makeLibrary(source: hlShader, options: nil)
        func pipe(_ blend: Bool, _ vf: String = "hlv", _ ff: String = "hlf", add: Bool = false) -> MTLRenderPipelineState {   // add：足し合わせ
            let p = MTLRenderPipelineDescriptor()
            p.vertexFunction = lib.makeFunction(name: vf); p.fragmentFunction = lib.makeFunction(name: ff)
            p.colorAttachments[0].pixelFormat = .bgra8Unorm; p.depthAttachmentPixelFormat = .depth32Float; p.rasterSampleCount = 4
            if blend {
                let c = p.colorAttachments[0]!; c.isBlendingEnabled = true
                c.sourceRGBBlendFactor = .sourceAlpha; c.destinationRGBBlendFactor = .oneMinusSourceAlpha
                c.sourceAlphaBlendFactor = .one; c.destinationAlphaBlendFactor = .oneMinusSourceAlpha
                if add { c.destinationRGBBlendFactor = .one; c.destinationAlphaBlendFactor = .one }   // 足し合わせ（光る線・星）
            }
            return try! d.makeRenderPipelineState(descriptor: p)
        }
        opaquePipe = pipe(false); alphaPipe = pipe(true); rPipe = pipe(true, "hrv"); ringPipe = pipe(false, "ringv")
        tunAddPipe = pipe(true, add: true)                              // トンネル：光る線・星・炉（足し合わせ）
        wirePipe = pipe(true, "hrwv", "wlf"); wirePipeAdd = pipe(true, "hrwv", "wlf", add: true); segPipe = pipe(true, "segwv", "wlf")
        // 輪の型（周 160 × 管の周り 16 の三角形。cos u, sin u, cos v, sin v）
        var mesh: [SIMD4<Float>] = []; let sa = 160, sb = 16
        func rq(_ a: Int, _ b: Int) -> SIMD4<Float> { let uu = Float(a) / Float(sa) * 2 * .pi, vv = Float(b) / Float(sb) * 2 * .pi; return SIMD4(cos(uu), sin(uu), cos(vv), sin(vv)) }
        for a in 0..<sa { for b in 0..<sb { mesh += [rq(a, b), rq(a + 1, b), rq(a + 1, b + 1), rq(a, b), rq(a + 1, b + 1), rq(a, b + 1)] } }
        ringMeshCount = mesh.count
        ringMesh = mesh.withUnsafeBytes { d.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        rPipeAdd = pipe(true, "hrv", add: true); cometPipe = pipe(true, "cmv", "cmf", add: true); starPipe = pipe(true, "stv", "stf", add: true); bgPipe = pipe(false, "dsv", "cpf")
        let bp = MTLRenderPipelineDescriptor(); bp.vertexFunction = lib.makeFunction(name: "bgv"); bp.fragmentFunction = lib.makeFunction(name: "bgf")
        bp.colorAttachments[0].pixelFormat = .bgra8Unorm; bgMakePipe = try! d.makeRenderPipelineState(descriptor: bp)
        let dp = MTLRenderPipelineDescriptor(); dp.vertexFunction = lib.makeFunction(name: "dsv"); dp.fragmentFunction = lib.makeFunction(name: "dsf")
        dp.colorAttachments[0].pixelFormat = .bgra8Unorm; dsPipe = try! d.makeRenderPipelineState(descriptor: dp)
        dp.fragmentFunction = lib.makeFunction(name: "mirf"); mirPipe = try! d.makeRenderPipelineState(descriptor: dp)
        let lp = MTLRenderPipelineDescriptor(); lp.vertexFunction = lib.makeFunction(name: "lbv"); lp.fragmentFunction = lib.makeFunction(name: "lbf")
        lp.colorAttachments[0].pixelFormat = .bgra8Unorm; lp.depthAttachmentPixelFormat = .depth32Float; lp.rasterSampleCount = 4
        let lc = lp.colorAttachments[0]!; lc.isBlendingEnabled = true; lc.sourceRGBBlendFactor = .one; lc.destinationRGBBlendFactor = .oneMinusSourceAlpha
        lc.sourceAlphaBlendFactor = .one; lc.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        lbPipe = try! d.makeRenderPipelineState(descriptor: lp)
        let w = MTLDepthStencilDescriptor(); w.depthCompareFunction = .less; w.isDepthWriteEnabled = true; depthWrite = d.makeDepthStencilState(descriptor: w)
        let r = MTLDepthStencilDescriptor(); r.depthCompareFunction = .less; r.isDepthWriteEnabled = false; depthRead = d.makeDepthStencilState(descriptor: r)
        let a = MTLDepthStencilDescriptor(); a.depthCompareFunction = .always; a.isDepthWriteEnabled = false; depthAlways = d.makeDepthStencilState(descriptor: a)
    }

    // ---- 色（ウェブ版の layerColor：中心が赤、北は赤→水色、南は紫→青）----
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> SIMD3<Float> {
        func f(_ n: Double) -> Double { let k = (n + h * 12).truncatingRemainder(dividingBy: 12), a = s * min(l, 1 - l); return l - a * max(-1, min(k - 3, 9 - k, 1)) }
        return SIMD3(Float(f(0)), Float(f(8)), Float(f(4)))
    }
    /// 北の殻の色相：中心の赤から水色へ。黄（t ＝ 1/3）より内側だけ進み方をゆるめて、赤・橙の幅を広げる。黄より外は変えない
    static func northHue(_ t: Double) -> Double { t >= 1.0 / 3 ? t * 0.5 : pow(t * 3, 1.4) / 6 }
    static func layerColor(_ i: Int, _ n: Int, _ south: Bool) -> SIMD3<Float> {
        let t = Double(i) / Double(max(1, n - 1))
        return south ? hsl(0.80 - t * 0.30, 0.95, 0.52) : hsl(northHue(t), 0.95, 0.52)
    }
    /// S³ の点 p（長さ 1）のところの球殻の色（球層の色の決まり方 m：0 レインボー・1 4 方向レインボー・2 軸の色）。
    ///   レインボーは、その軸の座標 c から緯度 θ＝acos|c| を出して層の色（北は赤→水色、南は紫→青）。4 方向・軸の色は、
    ///   いちばん近い軸ほど強く（座標の 4 乗の重み）混ぜる
    static func shellTint(_ p: SIMD4<Double>, _ m: Int) -> SIMD3<Float> {
        func rain(_ c: Double) -> SIMD3<Float> {
            let th = acos(min(1, abs(c))), t = max(0, min(1, (th - MIN_THETA) / (Double.pi / 2 - MIN_THETA)))
            return c < 0 ? hsl(0.80 - t * 0.30, 0.95, 0.52) : hsl(northHue(t), 0.95, 0.52)
        }
        if m != 1 && m != 2 { return rain(p.w) }
        let cs = [p.x, p.y, p.z, p.w]
        var sum = SIMD3<Float>(), wsum = 0.0
        for k in 0..<4 {
            let w = pow(cs[k], 4), col: SIMD3<Float>
            if m == 1 { col = rain(cs[k]) }
            else { let f = Float(1 - abs(cs[k])); col = simd_mix(axisCol[k] * (0.55 + 0.45 * f), SIMD3(repeating: 1), SIMD3(repeating: 0.18 * f)) }
            sum += col * Float(w); wsum += w
        }
        return wsum > 1e-12 ? sum / Float(wsum) : rain(p.w)
    }
    /// 層：北・南それぞれ n 枚（緯度 θ のリング＝半径 R sin θ・高さ ±R cos θ）。南の赤道は北と重なるので 1 枚だけ
    func layerList() -> [(r: Double, w: Double, col: SIMD3<Float>)] {
        let n = max(2, st.layers), R = Self.R
        var out: [(Double, Double, SIMD3<Float>)] = []
        for south in [false, true] {
            if (st.hemi == 1 && south) || (st.hemi == 2 && !south) { continue }
            for i in 0..<n {
                if south && i == n - 1 && st.hemi == 0 { continue }
                let th = Self.MIN_THETA + Double(i) / Double(n - 1) * (Double.pi / 2 - Self.MIN_THETA)
                out.append((R * sin(th), (south ? -1 : 1) * R * cos(th), Self.layerColor(i, n, south)))
            }
        }
        return out
    }

    /// 球層の組：レインボーは w の 1 組。4 方向・軸の色は x・y・z・w の 4 組（左は z を落とした x・y・z(w) の 3 組）。
    ///   k は囲む軸（0 x・1 y・2 z・3 w）。軸の色：その軸の色で、赤道に近い層ほど明るく
    func shellFams(left: Bool) -> [(k: Int, list: [(r: Double, w: Double, col: SIMD3<Float>)])] {
        let m = st.shellModeNow, L = layerList()
        guard m == 1 || m == 2 else { return [(3, L)] }
        return (left ? [3, 0, 1] : [3, 0, 1, 2]).map { k in
            (k, m == 1 ? L : L.map { e in
                let f = Float(1 - abs(e.w) / Self.R), c = Self.axisCol[k]
                return (e.r, e.w, simd_mix(c * (0.55 + 0.45 * f), SIMD3(repeating: 1), SIMD3(repeating: 0.18 * f)))
            })
        }
    }

    // ---- 左：リングの球（3D）----
    /// three.js の Euler（順序 YXZ）：ベクトルには面内（z）→ 前後（x）→ 左右（y）の順で効く
    func leftRot() -> simd_double3x3 {
        func rx(_ a: Double) -> simd_double3x3 { simd_double3x3(rows: [[1, 0, 0], [0, cos(a), -sin(a)], [0, sin(a), cos(a)]]) }
        func ry(_ a: Double) -> simd_double3x3 { simd_double3x3(rows: [[cos(a), 0, sin(a)], [0, 1, 0], [-sin(a), 0, cos(a)]]) }
        func rz(_ a: Double) -> simd_double3x3 { simd_double3x3(rows: [[cos(a), -sin(a), 0], [sin(a), cos(a), 0], [0, 0, 1]]) }
        return ry(st.roll) * rx(st.pitch) * rz(st.yaw)
    }
    /// 左の形（傾きは描く時に GPU で回すので、形は Z-W・層数・半球が変わった時だけ作る）
    func buildLeftForBench() { buildLeft() }
    func buildLeft() {
        tris = []; glass = []; lines = []; ranges = []; leftRings = []; rings = []
        let M = matrix_identity_double3x3, R = Self.R, cs = cos(st.zw)
        let n = max(2, st.layers), tube = n > 31 ? 0.008 : 0.02
        let sn = sin(st.zw), lzw = st.lzw
        for (k, list) in shellFams(left: true) where k != 3 {          // x・y の軸のまわりの輪（Z-W は w の組だけに効かせる）
            for (r, w, col) in list { rings.append(HLRing(a: SIMD4(Float(r), Float(w), Float(tube), k == 0 ? 1 : 2), c: SIMD4(col, 1))) }
        }
        let wList = shellFams(left: true)[0].list
        for (r, w, col) in wList {
            // 影（投影。ウェブ版の leftZW 'shadow'・'both'）：層（半径 r の球面）を z の向きから写した影＝平たい回転楕円体
            //   （中心の高さ w·cos、横の半径 r、厚み r·|sin|）。網目で薄く。影だけの時（1）は輪も消えず、影の赤道（高さ w·cos・半径 r）に
            if lzw != 0 && abs(sn) > 1e-3 {
                let a: Float = lzw == 2 ? 0.32 : 0.55, c4 = SIMD4(col * 1.25, a), th = abs(sn) * r   // 左は 2 倍に描いて縮めるので、細い線はウェブ版（0.16・0.28）の倍くらいの濃さで
                func ep(_ i: Int, _ j: Int) -> SIMD3<Double> {
                    let t = Double(i) / 14 * .pi, f = Double(j) / 32 * 2 * .pi
                    return SIMD3(r * sin(t) * cos(f), r * sin(t) * sin(f), w * cs + th * cos(t))
                }
                for i in 1..<14 { for j in 0..<32 { addLine(ep(i, j), ep(i, j + 1), c4) } }   // 緯線
                for j in 0..<32 { for i in 0..<14 { addLine(ep(i, j), ep(i + 1, j), c4) } }   // 経線
            }
            // 輪：断面（0・2）は z′＝0 で切った円。高さ w の層は h ＝ w／cos(Z-W) の所の円（半径 √(R² − h²)）。超球からはみ出すと消える。影（1）は影の赤道
            var rho = r, h = w
            if lzw == 1 { h = w * cs }
            else if abs(st.zw) > 1e-6 {
                guard abs(cs) > 1e-3 || abs(w) < 1e-9 else { continue }
                h = abs(w) < 1e-9 ? 0 : w / cs
                guard abs(h) <= R + 1e-6 else { continue }
                rho = (max(0, R * R - h * h)).squareRoot()
            }
            leftRings.append((rho, h, col))
            rings.append(HLRing(a: SIMD4(Float(rho), Float(h), Float(tube), 0), c: SIMD4(col, 1)))   // 細い管（トーラス）は GPU で組み立てる
        }
        // 球の輪郭（うすい円）と、z 軸（4 次元目の w と対応する軸）
        let eq = (0...96).map { k -> SIMD3<Double> in let a = Double(k) / 96 * 2 * .pi; return SIMD3(R * cos(a), R * sin(a), 0) }
        for k in 0..<96 { addLine(M * eq[k], M * eq[k + 1], SIMD4(0.58, 0.64, 0.72, 0.18)) }
        if !st.axes { addLine(M * SIMD3(0, 0, -R * 1.25), M * SIMD3(0, 0, R * 1.25), SIMD4(0.38, 0.65, 0.98, 0.55)) }   // 座標軸を出す時は、毎コマ drawAxes で
    }
    func addLine(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD4<Float>) {
        lines.append(HLVert(p: SIMD4(SIMD3<Float>(a), 1), n: .zero, c: c)); lines.append(HLVert(p: SIMD4(SIMD3<Float>(b), 1), n: .zero, c: c))
    }

    // ---- 右：球殻の超球（4D → 3D）----
    /// 4D の回転（ウェブ版の mkSteps と同じ順）：Z-W → X-Y（面内）→ Y-W（前後）→ X-W（左右、向きは逆）
    /// 地図の構図（全体像だけの向き）：ダイブの間、w 軸を縦にして球層を水平に見せる（玉の重なりは上の地図の役目）
    var ovFxNow = -1, ovOnionK = 0.0, ovPolyK = 0.0, ovSpinK = 0.0, ovFxSeed: Float = 0   // W 消失地図の演出：今の切り方・玉ねぎ・ポリゴン・回る断面の効き
    var ovM: simd_double4x4? = nil, ovBase: simd_double4x4? = nil, ovLast = -9.0, ovCutK = 0.0, ovCutLast = -99.0, ovPeekT = -1.0
    var ovLogT = -9.0
    var ovZoomK = 1.0, ovShufT = 0.0, ovWedgeT = -1.0, ovWedgeK = 0.0, ovWedgeLast = -99.0, ovPitch = 0.0, ovPitchV = 0.0, ovViewYaw = 0.0, ovYawV = 0.0, ovBall = 0.0
    var ovSpin = 0.0, ovSpinRate = 0.0, ovBornT = -1.0, ovFlipT = -1.0   // W 消失地図のおまかせ：ゆっくり回る角度・今の速さ・地図が定まった時刻・最後に反転した時刻
    /// 上の地図（車のナビ）：自分がいつも真ん中で、背景が動く。自分のいる所を 4 次元の手前（w）へ、進む向きを画面の上（y）へ、右を右（x）へ写す。
    ///   ダイブの間だけ。曲がる時に背景がぱっと回らないよう、向きは少しならす
    var naviM: simd_double4x4? = nil, naviR = SIMD4<Double>(0, 0, 0, 0), naviF = SIMD4<Double>(0, 0, 0, 0), naviU = SIMD4<Double>(0, 0, 0, 0), naviLast = -9.0, naviBall = 0.0, naviHole = 0.0, splitVel = 0.0
    func xf(_ v0: SIMD4<Double>) -> SIMD4<Double> {
        if let m = naviM ?? ovM { return m * v0 }
        var v = v0
        let g = SIMD4(st.zw, st.yaw, st.pitch, st.roll)
        for (i, j, a) in [(2, 3, g[0]), (0, 1, g[1]), (1, 3, g[2]), (0, 3, -g[3])] where a != 0 {
            let c = cos(a), s = sin(a), t = v[i] * c - v[j] * s
            v[j] = v[i] * s + v[j] * c; v[i] = t
        }
        return v
    }
    func buildRight() {
        tris = []; glass = []; lines = []; ranges = []
        let n = max(2, st.layers), MESH0 = n > 61 ? 12 : n > 31 ? 16 : 24
        // 網目の線はウェブ版と同じ本数（MESH0）。面と線の曲がりは 2 倍に細かく（輪郭がカクカク・ギザギザしないよう）。4 方向・軸の色は殻が 4 倍なので 2 倍まで
        let SUB = (shellFams(left: false).count > 1 ? 2 : 4) * (heavyHere ? 2 : 1), M = MESH0 * SUB, M1 = M + 1, per = M1 * M1   // 光を頂点で計算するので、網目は 4 倍に細かく（照り返しがなめらか）
        rMesh = M; rSub = SUB
        let fams = shellFams(left: false)
        let L = fams.flatMap { $0.list }, layerK = fams.flatMap { f in f.list.map { _ in f.k } }
        // 元の 4D の点（網目の並びは three.js の SphereGeometry と同じ：極が上下＝y、地球儀のように緯線が横に並ぶ。ウェブ版と同じ見た目）
        func points(_ M: Int) -> [SIMD4<Float>] {
            var base = [SIMD4<Float>](); base.reserveCapacity(L.count * (M + 1) * (M + 1))
            for (k, list) in fams { for (r, w, _) in list { for i in 0...M { let th = Double(i) / Double(M) * .pi; for j in 0...M {
                let ph = Double(j) / Double(M) * 2 * .pi
                var v = SIMD4<Float>(Float(-r * sin(th) * cos(ph)), Float(r * cos(th)), Float(r * sin(th) * sin(ph)), Float(w))
                if k != 3 { let s = v[k]; v[k] = v[3]; v[3] = s }            // 軸 k ＝ 一定の殻（w と入れかえる）
                base.append(v)
            } } } }
            return base
        }
        let base = points(M)
        // 網目の線は面の 2 倍に細かく（ダイブで寄ると線の折れ目が見える。面はなめらかなので細かくしない）。地図は小さく、ヘビーは面ごと細かいので、そのまま
        let WK = overview || heavyHere ? 1 : 2, WM = M * WK, W1 = WM + 1, WS = SUB * WK
        let baseW = WK == 1 ? base : points(WM)
        rMeshW = WM
        // つなぎ方：層ごとに「三角形」→「線（緯線・経線・升目の斜め）」。three.js の網目は三角形の辺を全部描くので、升目ごとに (i, j) → (i+1, j+1) の斜めが入る（織物のような見た目）
        // ポリゴンカットは網目を全部作って、シェーダーが殻の経度で画素ごとに切る（物体に固定と同じ。真ん中は押した時の手前の経度）
        var idx = [UInt32](), idxW = [UInt32]()
        for li in 0..<L.count {
            let o = UInt32(li * per), g0 = idx.count
            for i in 0..<M { for j in 0..<M {
                let k = UInt32(i * M1 + j) + o, d = UInt32(M1)
                idx += [k, k + d, k + d + 1, k, k + d + 1, k + 1]
            } }
            let oW = UInt32(li * W1 * W1), l0 = idxW.count
            for i in stride(from: 0, through: WM, by: WS) { for j in 0..<WM { let k = UInt32(i * W1 + j) + oW; idxW += [k, k + 1] } }
            for j in stride(from: 0, to: WM, by: WS) { for i in 0..<WM { let k = UInt32(i * W1 + j) + oW; idxW += [k, k + UInt32(W1)] } }
            for i in stride(from: 0, to: WM, by: WS) { for j in stride(from: 0, to: WM, by: WS) { for s in 0..<WS {
                let k = UInt32((i + s) * W1 + j + s) + oW; idxW += [k, k + UInt32(W1) + 1]
            } } }
            var ax = SIMD4<Double>(repeating: 0), ex = SIMD4<Double>(repeating: 0); ax[layerK[li]] = 1; ex[layerK[li] == 0 ? 1 : 0] = 1
            ranges.append((g0..<idx.count, l0..<idxW.count, ax * (L[li].w / Self.R), ax * (L[li].w / Self.R) + ex * (L[li].r / Self.R)))
        }
        let thin: Float = fams.count > 1 ? (st.shellModeNow == 1 ? 0.45 : 0.6) : 1   // 4 組重なるので 1 枚ずつ薄く（白っぽく埋まらないように）
        // 4 方向レインボー：極に近い殻（赤・紫など）ほど濃く、赤道に近い殻ほど薄く。描く順も、極に近い殻をあとに（上に重ねる）。
        //   真ん中の緑・水色に埋もれず、極の色が前に浮き出る（殻の形と場所はそのまま）
        func poleK(_ w: Double) -> Double { smoothstep(0.1, 0.9, abs(w) / Self.R) }
        let four = fams.count > 1 && st.shellModeNow == 1
        // 赤の殻（アナ星の入っている殻とその外）だけ濃く：外の橙・黄の殻が重なっても、赤が赤く見えるように
        let cols = L.map { SIMD4<Float>($0.col, four ? thin * Float(0.2 + 1.7 * poleK($0.w)) : thin * (fams.count != 1 ? 1 : $0.w / Self.R > 0.97 ? 2.4 : $0.w / Self.R > 0.9 ? 1.5 : 1)) }
        if four { ranges = ranges.indices.sorted { poleK(L[$0].w) < poleK(L[$1].w) }.map { ranges[$0] } }
        rBase = base.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        rCol = cols.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: max(16, $0.count), options: .storageModeShared) }
        rIdx = idx.isEmpty ? nil : idx.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        rBaseW = WK == 1 ? rBase : baseW.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
        rIdxW = idxW.isEmpty ? nil : idxW.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) }
    }
    func smoothstep(_ a: Double, _ b: Double, _ x: Double) -> Double { let t = max(0, min(1, (x - a) / (b - a))); return t * t * (3 - 2 * t) }

    // ---- 描く ----
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    // 確かめ用（環境変数 S3_HL_LOG）：1 秒ごとに、描く間隔の最大・描く処理の時間（CPU）の平均と最大
    static let logOn = ProcessInfo.processInfo.environment["S3_HL_LOG"] != nil
    var lgN = 0, lgCPU = 0.0, lgMaxCPU = 0.0, lgMaxGap = 0.0, lgT = 0.0, lgLong = 0
    /// 音：彗星（今いる所）の S³ の上の速さ（ラジアン／秒）をならして、シューの大きさ・高さへ。当たった瞬間にチリン
    var sndWobT = 0.0                                         // 前に低音をゆらした時刻
    var sndIceT = 0.0                                          // 前にシュパッを鳴らした時刻
    var sndPass = PolePass(), sndLayer: Int? = nil, sndSwing = 0.0, sndPos: SIMD4<Double>?, sndSpeed = 0.0, sndFwd: SIMD4<Double>?, sndTurn = 0.0, sndPulseT = ProcessInfo.processInfo.systemUptime
    /// オートカメラ：ゆっくり周りを漂う（40 秒・27 秒の波）＋曲がる時は外側へ回り込む（曲がる道すじと尾が見えるように）。ズーム中だけ
    var acFwd: SIMD4<Double>?, acTurn = 0.0, acTurnU = 0.0, acVert = 0.0
    /// 彗星の速さ（S³ の上で 1 秒に進む角度をならして、0〜1 に）
    var csPos: SIMD4<Double>?
    /// 空気とコースター：毎コマ、彗星の今の速さと曲がり方を風にして解き、音とカメラへ渡す
    let air = AirSim()
    var meterT = 0.0
    /// ショーカメラ：カーブが近い（予定の道で 0.7 以内に、1 歩 0.02 で 0.7° より大きく曲がる所がある）か曲がっている間は、真後ろの低い所から
    ///   （ターンを後ろから見せる。曲がり終えて 1 秒は続ける）。まっすぐな所は 4.5 秒ごとに：斜め右上（傾ける）→ 右の真横 → 真上の近く → 斜め左上（傾ける）→ 左の真横 → 高く引いた全体 → 低い斜め後ろ → 後ろ。
    ///   返り値は、オートカメラの左右・見下ろしの目標（三人称の基本の角度からのずれ）と、距離の倍率
    var showIdx = 0, showT = 0.0, showHold = 0.0, showDistT = 1.0, showRollT = 0.0, showFrameT = SIMD2<Double>(0, 0)
    // 演出 AI の覚え：先回りしている構図・そのカーブの種類・抜けてから戻るまで・最近使った構図
    var sdV = 0.0, sfV = SIMD2<Double>(0, 0)                       // 視点のばねの速さ（距離・彗星の置き場所）
    var camQ = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), camW = SIMD3<Double>(0, 0, 0)   // 四元数のカメラ：今の向きと、回る速さ（角速度）
    var aiShot: (Double, Double, Double, Double, Double, Double)? = nil, aiKey = -99, aiHold = 0.0, aiHist: [Int] = []
    var sndRush = 0.0, sndAim = 0.0                           // 直線の伸び・極へ向かう度合い
    var sndZ = 0.0
    /// アニメーションなしの切りかえ：切りかえる前のコマを取っておいて、薄くしながら重ねる（右の画面のリゾルブ）
    var snapTex: MTLTexture?
    /// 毎コマの受け持ち（状態を進める・画質の自動・保存など）：ふだんは左の画面。3D の球を隠している時は右の画面
    var wasIdle = false, offShown = false
    var ownerRole: Bool { !ovMotion && (diveWipe ? wipeMain && st.show3D : side == .left || overview || !st.show3D) }
    var mainPane: Bool { side == .right && !overview && !diveWipe }
    let bornT = CACurrentMediaTime()
    /// 受け持ちは 1 つだけ（画面の切りかえで 2 つが重なっている間に両方が進めると、回転やズームが倍の速さになる）。
    ///   受け持ちの窓が描かれなくなった時は、大きな画面が代わりに進める（誰も進めないと、変形も黒い間も終わらない）。受け持ちの窓が戻ったら返す
    var owner: Bool {
        let me = Self.tickBy == ObjectIdentifier(self), age = CACurrentMediaTime() - Self.tickT
        if ownerRole { return me || age > 0.1 || Self.tickSpare }
        return mainPane && (me || age > 0.2)
    }
    static var tickBy: ObjectIdentifier? = nil, tickT = 0.0, tickSpare = false
    static let proxyK = 0.25                                  // プロキシの画面の細かさ
    /// 地図の窓を地図の見え方で描くか：ダイブの間ずっと。消えていく間（切りかえの 0.7 秒）も保つ（ふつうの超球の絵に戻ると、どの窓も同じ絵になる）
    var ovLive: Bool {
        let on = st.diveOn || st.diveT > 0 || st.paneDive
        if on { ovOnT = nowT }
        return on || (clockOverride == nil && nowT - ovOnT < 1)
    }
    var ovOnT = -9.0
    static var keepK: Double? = nil                           // プロキシの前の細かさ
    var ownerForTest: Bool { ownerRole }   // 全体像を 3D の球の場所に出している時は、全体像が受け持つ
    func draw(in view: MTKView) {
        let t0 = CACurrentMediaTime()
        defer { if !mainPane && bornT > st.paneSwapT { st.paneDrawn = true } }   // 入れかえたあとの新しい窓が、最初の絵を描いた
        if owner && !(VideoExport.shared.rendering && !VideoExport.shared.liveRun && mainPane) { Self.tickBy = ObjectIdentifier(self); Self.tickT = t0; Self.tickSpare = !ownerRole }
        if owner { HyperLabState.walkRendererGet?()?.driveIfIdle() }       // さんぽの画面が描かれていない時は、ここから歩く計算を進める
        defer {
            if Self.logOn {
                let c = (CACurrentMediaTime() - t0) * 1000; lgN += 1; lgCPU += c; lgMaxCPU = max(lgMaxCPU, c)
                if t0 - lgT >= 1 { print(String(format: "%@ n %d  CPU 平均 %.2f 最大 %.2f ms  間隔の最大 %.1f ms（12 ms 超 %d 回）  目標 %d", side == .left ? "左" : "右", lgN, lgCPU / Double(max(1, lgN)), lgMaxCPU, lgMaxGap, lgLong, view.preferredFramesPerSecond)); fflush(stdout); lgN = 0; lgLong = 0; lgCPU = 0; lgMaxCPU = 0; lgMaxGap = 0; lgT = t0 }
            }
        }
        if Self.logOn { let g = (t0 - lastT) * 1000; lgMaxGap = max(lgMaxGap, g); if g > 12 { lgLong += 1 } }
        let now = CACurrentMediaTime(), dt = min(0.05, now - lastT); lastT = now
        if VideoExport.shared.rendering && !VideoExport.shared.liveRun && side == .right && !overview { return }   // 動画を書き出している間は、右の画面を止めて（GPU を書き出しに回す）
        #if os(macOS)
        if owner && st.shutAuto {                                        // 前の窓だけ描く：どちらの窓が前（キー）かで、瞬時に切りかえ
            let hk = HyperLabWindow.window?.isKeyWindow ?? false, wk = HyperLabWindow.walkWindow?.isKeyWindow ?? false
            if HyperLabState.walkShut != hk { HyperLabState.walkShut = hk }
            let idle = wk && !hk; if HyperLabState.hyperIdle != idle { HyperLabState.hyperIdle = idle }
        }
        #endif
        if mainPane || (VideoExport.shared.rendering && owner) { st.tickDive(dt) }   // 変形はいつも描いている大きな画面で進める（書き出しで大きな画面が止まる間は、受け持ちの窓で）
        if owner { st.tick(dt); st.pullLayers(); st.tickCut(dt); st.tickFollow(dt); updateLive(now); tickSound(dt); tickAutoCam(dt); tickCometSpeed(dt); tickAir(dt) }   // 自動の回転・さんぽの層数を読むのは受け持ちの画面（ふだん左。右は同じ状態を描く）
        pace(view, dt)
        let proxy = VideoExport.shared.proxyNow, frozen = (proxy || HyperLabState.paneFreezeNow) && (side == .left || overview || diveWipe)   // プロキシ・左が黒い間：小さい画面は止める（プロキシは大きな画面も粗く）
        if proxy { if Self.keepK == nil { Self.keepK = HyperLabState.renderK }; HyperLabState.renderK = Self.proxyK }
        else if let k = Self.keepK { HyperLabState.renderK = k; Self.keepK = nil }   // 走り終わったら、すぐ元の細かさへ
        let wipeK = diveWipe && st.wipeLow ? 0.71 : 1                    // 左下のダイブ画面の低負荷：画素は半分（線の太さはそのまま）
        if diveWipe { renderKOverride = HyperLabState.renderK * wipeK }
        if !frozen { Self.fit(view, extra: wipeK) }
        if owner { fpsN += 1; if now - fpsT >= 1 { st.saveIfChanged(); let f = Int((Double(fpsN) / (now - fpsT)).rounded()); fpsN = 0; fpsT = now; DispatchQueue.main.async { [st] in st.stats.text = String(format: "%d fps・GPU %.1f＋%.1f ms・画質 %.0f%%", f, st.gpuL, st.gpuR, HyperLabState.renderK * 100) } } }
        if frozen { return }
        // 前の窓だけ描く（自動）で、さんぽの窓が前の時：この窓の画面はオフ（真っ暗を 1 回だけ出して、あとは描かない）
        if HyperLabState.hyperIdle {
            if !offShown, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() {
                let rp = MTLRenderPassDescriptor()
                rp.colorAttachments[0].texture = dr.texture; rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .store
                rp.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
                cb.makeRenderCommandEncoder(descriptor: rp)?.endEncoding(); cb.present(dr); cb.commit(); offShown = true
            }
            return
        }
        offShown = false
        if side == .left {
            guard let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
            renderLeft(cb, into: dr.texture); timeGPU(cb); cb.present(dr); cb.commit(); return
        }
        guard let rpd = view.currentRenderPassDescriptor, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer() else { return }
        if dvT > 0 {
            // ダイブの間：マルチサンプルの絵を別の絵（mirTex）にまとめてから、鏡を広げて画面へ
            let W = dr.texture.width, H = dr.texture.height
            if mirTex == nil || mirTex!.width != W || mirTex!.height != H {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .bgra8Unorm, width: W, height: H, mipmapped: false)
                d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private; mirTex = device.makeTexture(descriptor: d)
            }
            guard let mt = mirTex else { return }
            rpd.colorAttachments[0].resolveTexture = mt
            guard let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
            encode(e, view.drawableSize); e.endEncoding()
            mirrorPass(cb, mt, dr.texture)
        } else {
            mirTex = nil
            guard let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
            encode(e, view.drawableSize); e.endEncoding()
        }
        resolvePass(cb, view, dr.texture)
        if mainPane && st.paneSeeA > 0, let ev = Self.seeView, ev.bounds.width > 1 {
            let bw = ev.bounds.width, bh = ev.bounds.height, want = CGSize(width: (bw * 0.7).rounded(), height: (bh * 0.7).rounded())   // 暗いので粗くてよい（右の窓の 2 割ほどの画素）
            if ev.autoResizeDrawable { ev.autoResizeDrawable = false }
            if ev.drawableSize != want { ev.drawableSize = want }
            if let ed = (ev.layer as? CAMetalLayer)?.nextDrawable(), seeRender(cb, ed.texture, Int(want.width), Int(want.height), rw: Double(view.bounds.width), rh: Double(view.bounds.height), lw: Double(bw), gap: Self.seeGap, b: st.paneSeeB) { cb.present(ed) }
        }
        timeGPU(cb); cb.present(dr); cb.commit()
        if !overview && !diveWipe && side == .right { Self.liveMain = self; Self.liveRightW = Double(view.bounds.width) }   // 右の画面の幅（点）：書き出しの文字を画面と同じ割合にする
        if (VideoExport.shared.recording || VideoExport.shared.keepLast || VideoExport.shared.armed) && !overview && !diveWipe, let f = recordFrame() { VideoExport.shared.capture(f) }   // 記録している間・直前 1 分を覚える間：この画面の動きを 1 コマずつ覚える（描き直すのは止めたあと）
    }
    // ---- 動画の書き出し：16:9（1920×1080）で画面の裏でもう一度描く。ダイブ中は左上に小さく全体像の地図 ----
    var exMS: MTLTexture?, exDep: MTLTexture?, exOut: MTLTexture?, exCache: CVMetalTextureCache?, exOverview: HyperLabRenderer?, exOverview2: HyperLabRenderer?, exGlass: InsetGlass?
    // シースルー：右の窓の絵の左の続きを、右の窓と同じカメラ・同じ写し方で描く（右の窓の描き方は変えない）
    var seeAsp: Float? = nil, seeClip = matrix_identity_float4x4, seeMS: MTLTexture?, seeDep: MTLTexture?, seeOut: MTLTexture?, seeDst: MTLTexture?
    static weak var seeView: MTKView?
    static let seeGap = 5.0                                            // 窓の仕切りの太さ（点）
    /// 書き出し：ダイブ画面を描く入れ物（レイアウトの右の大きな所）
    var exPaneTex: MTLTexture?
    /// 書き出し：「両方」の時のダイブ画面を w×h に描いた絵
    var exWipe: HyperLabRenderer?, exWipe1: HyperLabRenderer?
    /// 書き出し：左の 3D の球を w×h に描いた絵（左の窓と同じ描き方）
    var exBall: HyperLabRenderer?
    /// 書き出し：さんぽの景色を、記録したさんぽのカメラで w×h に描いた絵（さんぽの窓と同じ描き方。カメラは描く間だけ借りて戻す）
    var exWalkTex: MTLTexture?
    var liveT = 0.0
    /// 角度の読みを 0.5 秒ごとに（変わった時だけ。表示を変えるたびに窓の並べ直しが走るので、少なめに）
    var coordT = 0.0, coordP: SIMD4<Double>?, coordSpd = 0.0
    var livePass = PassCaption()
    func updateLive(_ now: Double) {
        // 走行中の座標（1 秒に 10 回）：S³ の上の x・y・z・w、アナ極からの角度、いちばん近い極、速さ（1 秒に進む角度）
        if now - coordT >= 0.1 {
            var cs = ""
            if st.coordOn && st.walk, let w = (wsrc)?() {
                let p = w.pos, en = st.poleEN, dtc = now - coordT
                if let p0 = coordP, dtc > 0 && dtc < 1 { let v = acos(max(-1, min(1, simd_dot(p, p0)))) / dtc; coordSpd += (v - coordSpd) * 0.35 }
                coordP = p
                let ana = acos(max(-1, min(1, p.w))) * 180 / .pi
                var bk = 0, bd = 9.0
                for (k, m) in FIXED.enumerated() { let d = acos(max(-1, min(1, simd_dot(p, m.c)))); if d < bd { bd = d; bk = k } }
                let pn = en ? MapRenderer.poleNameToEN(MapRenderer.poleName(FIXED[bk])) : MapRenderer.poleName(FIXED[bk])
                func f(_ v: Double) -> String { String(format: "%@%.3f", v < 0 ? "−" : "+", abs(v)) }
                cs = "S³  x \(f(p.x))  y \(f(p.y))  z \(f(p.z))  w \(f(p.w))" + (st.worldR < 0.9995 ? (en ? "   " : "   いる世界 ") + MapRenderer.worldTag(st.worldR) : "") + "\n"
                   + (en ? String(format: "from Ana %6.1f°   near %@ %5.1f°   v %.2f rad/s", ana, pn, bd * 180 / .pi, coordSpd)
                         : String(format: "アナ極から %6.1f°   近い極 %@ %5.1f°   速さ %.2f rad/s", ana, pn, bd * 180 / .pi, coordSpd))
            } else { coordP = nil }
            coordT = now
            if cs != st.live.coords { st.live.coords = cs }
            if st.walk, st.passOn, let w = (wsrc)?() {
                let pc = livePass.update(w.pos, now, r: st.worldR)
                if pc.text != st.live.pass { st.live.pass = pc.text; st.live.passCol = pc.col }
                if abs(pc.a - st.live.passA) > 0.01 { st.live.passA = pc.a }
            } else if st.live.passA != 0 { st.live.passA = 0 }
            var noteTo = 0.0
            if st.noteOn, st.walk, st.diveT > 0.3, let w = (wsrc)?(), acos(min(1, abs(w.pos.w))) < 0.75 { noteTo = 1 }
            let na = st.live.noteA + (noteTo - st.live.noteA) * 0.35
            if abs(na - st.live.noteA) > 0.01 || (noteTo == 0 && st.live.noteA > 0) { st.live.noteA = na < 0.01 ? 0 : na }
        }
        guard now - liveT >= 0.5 else { return }
        liveT = now
        let s = String(format: "前後（Y-W）%+.0f°　左右（X-W）%+.0f°　面内（X-Y）%+.0f°　Z-W %+.0f°", st.pitch * 180 / .pi, -st.roll * 180 / .pi, st.yaw * 180 / .pi, st.zw * 180 / .pi)
        if s != st.live.angles { st.live.angles = s }
        // 周回：目印が 2 つ以上ある時は目印で、なければ 8 つの極で数える（英語モードは Lap n）
        var lp = ""
        if let w = (wsrc)?(), (st.marksOn && w.marks.count >= 2) || (w.marks.count < 2 && st.polesMode > 0) || w.lap > 1 {
            lp = st.poleEN ? "Lap \(w.lap)" : "\(w.lap) 周目"
        }
        if lp != st.live.lap { st.live.lap = lp }
    }
    /// コマ数を動きに合わせる（iPhone の ProMotion のように）：見た目に関わる値が 0.6 秒変わらなければ 1 秒 10 コマに落とし、
    ///   どれかが変わったら（ドラッグ・自動の回転・スライダー・さんぽで歩く…）すぐ画面のいちばん速いコマ数に戻す
    func pace(_ view: MTKView, _ dt: Double) {
        let s = st
        #if os(macOS)
        // 窓のある画面のいちばん速いコマ数に合わせる（外の 144 Hz の画面から MacBook の 120 Hz の画面へ移った時など）。
        //   全部の画面のいちばん速い値（144）のままだと、120 Hz の画面で 144 を目指して届かず「遅い」と判断し、
        //   画質を下げ、コマ数も 144 の半分の 72（120 Hz を割り切れない）にして、カクカクになる
        if let hz = view.window?.screen?.maximumFramesPerSecond, hz > 0, hz != maxFPS {
            maxFPS = hz; moveFPS = hz; pN = 0; pT = 0; slowS = 0; fastS = 0
            if owner && s.quality == 0 { HyperLabState.renderK = 1 }
            if !lowFPS { view.preferredFramesPerSecond = hz }
        }
        #endif
        var sig: [Double] = [s.pitch, s.roll, s.yaw, s.zw, s.viewYaw, s.viewPitch, s.viewDist, s.leftDist, s.camW, s.gloss, s.glare ? 1 : 0,
                             Double(s.layers), Double(s.mode), Double(s.hemi), Double(s.lzw), s.cutOn ? 1 : 0, Double(s.cutRef), s.cutAngDeg, s.cutWDeg, s.cutPhi, Double(s.cutKind), Double(s.planeDir), s.cutPos, s.cutSweep ? 1 : 0, Double(s.cut4Axis), s.wireW, s.wireWMap, s.wireT, s.wireAuto ? 1 : 0, s.followOn ? 1 : 0, s.followSlack, s.followDrift, s.diveT,
                             s.axes ? 1 : 0, s.axPlus ? 1 : 0, s.axThin ? 1 : 0, s.walk ? 1 : 0, s.marksOn ? 1 : 0, Double(s.cursor), Double(s.ovCursor), s.starDepth, s.autoYaw, s.autoPitch, s.diveYawOff, s.divePitchOff, s.thirdK, s.chaseDistS, s.chasePitchS, s.chaseYawS, Double(s.depth4), s.depth4K, s.depth4On ? 1 : 0, s.symGlow ? 1 : 0, s.trailW, Double(s.trailCol), s.clearAhead ? 1 : 0, s.poleEN ? 1 : 0, s.diveThird ? 1 : 0, s.chaseDist, s.chasePitch, s.chaseYaw, Double(s.shellModeNow), Double(s.polesMode), Double(s.spaceMode), s.starsPct, s.spaceNow ? 1 : 0, s.auto ? 1 : 0,
                             Double(view.drawableSize.width), Double(view.drawableSize.height),
                             s.worldR, s.drillK, s.rOnly ? s.rOnlyR : -1, s.knifeLon ?? -9, s.knifeOn ? 1 : 0, s.chaosOn ? 1 : 0]   // R の世界・ドリル・この R だけ・ナイフ・内核の演出
        if (s.walk || s.marksOn), let src = wsrc {
            let w = src(); sig += [Double(w.trail.count), w.pos.x, w.pos.y, w.pos.z, w.pos.w, Double(w.marks.count), Double(w.hit.filter { $0 }.count), Double(w.poles.count)]
        }
        if owner { HyperLabState.planWanted = s.walk && s.planOn; HyperLabState.railWanted = s.walk && s.railOn }
        if s.drillOn || s.drillK > 0 || s.runOn || s.tunnelNow || (s.chaosOn && (s.worldR < 0.9995 || s.expandOn || s.fillOn || s.rOnly)) { sig.append(CACurrentMediaTime()) }   // ドリル・内核の演出（ゆらぐ・脈打つ）の間は描き続ける
        if flashing || s.paneBusy || s.diveT != (s.diveOn ? 1 : 0) || (side == .right && (diveWipe || s.lightWrap || s.diveT > 0.05)) || (s.walk && [1, 3, 4].contains(s.cursor)) || (HyperLabState.planWanted && HyperLabState.planActive) { sig.append(CACurrentMediaTime()) }   // 光の彗星を出している間も（すじが流れる）   // 光っている間・寄っている間（星がまたたく）は、止まっていても描き続ける                 // 当たった瞬間の光の間は、止まっていても描き続ける
        // ほんの少しの違い（計算の誤差）は「同じ」とみなす
        let moved = sig.count != lastSig.count || zip(sig, lastSig).contains { abs($0 - $1) > 1e-7 }
        // 動いている時のコマ数：ふだんは画面のいちばん速いコマ数。実際のコマ数が 2 秒続けて目標の 8 割に届かなければ（GPU があふれて
        //   コマを待つ間、ドラッグなどの操作も遅れてひっかかる）1 段下げ（画面の最高の 1/2・1/3…）、5 秒続けて余裕があれば 1 段上げてみる
        if owner { HyperLabState.boostWalk = s.diveFade > 0 }   // さんぽの窓を速くするのは、景色を右の大きな画面に重ねている間だけ（ふだんは 72 で十分。重ねる前に速くすると、ほかが詰まる）
        // コマ数の自動調整は、画面の半分（144Hz なら 72）より下げない。半端な速さ（80〜100）は 144Hz の画面でコマの間隔がそろわずカクついて見えるので、
        //   届かない時は、まず画質を下げ、それでも届かなければ画面の半分（一定の間隔）にする
        if owner { HyperLabState.walkBigShown = s.diveFade > 0.99 }
        if s.quality != 0 { HyperLabState.renderK = [1.0, 1.0, 0.75, 0.6][s.quality] }
        // さんぽの静かモード（ファンを回さない）の時は、超球の窓も静かに：コマ数だけ、画面の速さを割り切れる 45 以上のいちばん遅い速さへ（144Hz → 48）。
        //   描く画素は減らさない（減らして引き伸ばすと、細い線と小さな星がにじんで、透けたように色が薄く見える）
        let quiet = s.hyperQ == 1 || (s.hyperQ == 0 && (HyperLabState.walkRendererGet?()?.set.quiet ?? false))
        if owner { HyperLabState.quietNow = quiet }
        let kMax = 1.0
        // 遅い時は、まず画質（描く画素の数）を下げ、それでも遅ければコマ数を下げる（ダイブ・追う間はコマ数は下げない）。余裕が戻ったら逆の順に上げる。
        //   画質を決めるのは左の画面だけ（同じ窓の両方が同じ値を使う）
        // 超球だけ（さんぽの窓は止める）の時は静かに：動かす時も画面の速さを割り切れる 60 以上のいちばん遅い速さまで（144Hz → 72、120Hz → 60）。ファンを回さない
        //   上限はいつも 60 くらい（画面の速さを割り切れる 60 以上のいちばん遅い速さ：120Hz → 60、144Hz → 72）。それ以上は見た目がほとんど変わらず、熱くなるだけ
        var top = maxFPS / max(1, maxFPS / 60)
        if s.walk && [1, 3, 4].contains(s.cursor) && s.cometSpd < 0.03 && s.diveT == 0 { top = min(top, maxFPS / max(1, maxFPS / 60)) }   // 彗星が止まっている時は 60 まで（なめらかなまま、少し静かに）
        if quiet { top = min(top, maxFPS / max(1, maxFPS / 45)) }
        if HyperLabState.hyperIdle { top = maxFPS / max(1, maxFPS / 15) }   // 前の窓だけ描く：さんぽの窓が前の間は画面オフ（計算だけゆっくり続ける）
        if wasIdle && !HyperLabState.hyperIdle { moveFPS = top; if !lowFPS { view.preferredFramesPerSecond = moveFPS } }   // 超球の窓が前に戻ったら、すぐ元のなめらかさに
        wasIdle = HyperLabState.hyperIdle
        if moveFPS > top { moveFPS = top; if !lowFPS { view.preferredFramesPerSecond = moveFPS } }
        if !lowFPS {
            pN += 1; pT += dt
            // 0.5 秒ごとに数える（ダイブは 3 秒ほどなので、画質はすぐ下げる。上げるのはゆっくり＝ 2.5 秒続けて余裕がある時）
            if pT >= 0.5 {
                let got = Double(pN) / pT; pN = 0; pT = 0
                if got < Double(moveFPS) * 0.82 { slowS += 1; fastS = 0 } else if got > Double(moveFPS) * 0.94 { fastS += 1; slowS = 0 } else { slowS = 0; fastS = 0 }
                let lv = maxFPS / max(1, moveFPS), auto = s.quality == 0 && owner
                let autoFill = owner && s.fillAuto && (s.fillOn || s.expandOn)   // 内側の球層の自動（VBR）
                if slowS >= 2 {
                    slowS = 0
                    // 足りない時は、内側の球層の自動なら、まず内側の球層を 1 枚減らす（コマ数・画質は守る）。
                    //   次にコマ数を落として画質を守る（粗密・道を全部などで重い時も、絵はきれいなまま）。
                    //   コマ数がもう半分（60Hz なら 30）まで落ちていたら、自動の時だけ画質を 75% まで（それより下げると細い線がぼやけて混ざり、色がくすんで見える）
                    if autoFill && s.fillLayers > 1 { s.fillLayers -= 1 }
                    else if moveFPS > maxFPS / 2 { moveFPS = maxFPS / (lv + 1); view.preferredFramesPerSecond = moveFPS }
                    else if auto && !s.heavy && HyperLabState.renderK > 0.76 { HyperLabState.renderK = max(0.75, HyperLabState.renderK - 0.125) }
                } else if fastS >= 2 && (s.diveT == 0 || s.diveT == 1) {     // 余裕が 1 秒続いたら戻す（画質を先に、次にコマ数）
                    fastS = 0
                    if auto && HyperLabState.renderK < kMax - 0.001 { HyperLabState.renderK = min(kMax, HyperLabState.renderK + 0.125) }
                    else if lv > 1 && maxFPS / (lv - 1) <= top { moveFPS = maxFPS / (lv - 1); view.preferredFramesPerSecond = moveFPS }
                    // コマ数・画質がいっぱいに戻ってから、GPU に 4 割の余裕があれば内側の球層を 1 枚増やす（上限は R ＝ 1 の層の数）
                    else if autoFill && s.fillLayers < max(2, s.layers) && s.gpuL + s.gpuR < 1000 / Double(top) * 0.6 { s.fillLayers += 1 }
                }
            }
        } else { pN = 0; pT = 0; slowS = 0; fastS = 0 }
        if moved || !s.adaptive || s.shotOn {                          // 視点切りかえは止まっている間もコマ数を落とさない（次の切りかえが遅れないように）
            lastSig = sig; stillT = 0
            if lowFPS { lowFPS = false; view.preferredFramesPerSecond = moveFPS }
        } else {
            stillT += dt
            if !lowFPS && stillT > Self.idleAfter { lowFPS = true; view.preferredFramesPerSecond = Self.idleFPS }
        }
    }
    /// 左の輪：縦横 2 倍の大きさに 4 倍のマルチサンプルで描いて（1 画素に 16 点）、4 点を混ぜて縮める。細い管のふちと照り返しの筋がギザギザしない。
    ///   マルチサンプルの絵と奥行きは、GPU の中の小さな記憶（タイル）だけで済ませる（memoryless。大きな記憶を使わない）
    func renderLeft(_ cb: MTLCommandBuffer, into target: MTLTexture) {
        let W = target.width * 2, H = target.height * 2
        if ssTex == nil || ssTex!.hi.width != W || ssTex!.hi.height != H {
            var memless = true
            #if os(macOS)
            memless = device.supportsFamily(.apple7) || device.supportsFamily(.apple6)
            #endif
            func tex(_ f: MTLPixelFormat, ms: Bool) -> MTLTexture? {
                let d = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: f, width: W, height: H, mipmapped: false)
                if ms { d.textureType = .type2DMultisample; d.sampleCount = 4; d.usage = [.renderTarget]; d.storageMode = memless ? .memoryless : .private }
                else { d.usage = [.renderTarget, .shaderRead]; d.storageMode = .private }
                return device.makeTexture(descriptor: d)
            }
            guard let ms = tex(.bgra8Unorm, ms: true), let dep = tex(.depth32Float, ms: true), let hi = tex(.bgra8Unorm, ms: false) else { return }
            ssTex = (ms, dep, hi)
        }
        guard let s = ssTex else { return }
        let rp = MTLRenderPassDescriptor()
        rp.colorAttachments[0].texture = s.ms; rp.colorAttachments[0].resolveTexture = s.hi
        rp.colorAttachments[0].loadAction = .clear; rp.colorAttachments[0].storeAction = .multisampleResolve
        rp.colorAttachments[0].clearColor = MTLClearColor(red: 3 / 255, green: 7 / 255, blue: 18 / 255, alpha: 1)
        rp.depthAttachment.texture = s.dep; rp.depthAttachment.loadAction = .clear; rp.depthAttachment.storeAction = .dontCare; rp.depthAttachment.clearDepth = 1
        guard let e = cb.makeRenderCommandEncoder(descriptor: rp) else { return }
        encode(e, CGSize(width: W, height: H)); e.endEncoding()
        let fp = MTLRenderPassDescriptor()
        fp.colorAttachments[0].texture = target; fp.colorAttachments[0].loadAction = .dontCare; fp.colorAttachments[0].storeAction = .store
        guard let f = cb.makeRenderCommandEncoder(descriptor: fp) else { return }
        f.setRenderPipelineState(dsPipe); f.setFragmentTexture(s.hi, index: 0); f.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3); f.endEncoding()
    }
    /// 形を（変わっていれば）作り直して、描く命令を積む
    func encode(_ e: MTLRenderCommandEncoder, _ sz: CGSize) {
        // ポリゴンカットを押した：今の手前の経度を決めて、網目を作り直す。決めるのは大きな超球の係だけ
        //   （ダイブ画面・地図の係も超球を描くが、カメラの向きがちがう。全員が決めると、最後の係のカメラで大きな超球が切られる）
        if side == .right && !overview && !diveWipe && st.polyArm != polyArmSeen {
            polyArmSeen = st.polyArm
            // ウェブ版と同じ：今こちら（カメラ）の向きを超球の座標へ戻して、殻の経度（y 軸のまわり。SphereGeometry：x ＝ −cosφ、z ＝ sinφ）で手前の経度を決める。
            //   切るのは殻ごとの経度なので、4D で回しても、どの殻も同じすいかの 1 切れのまま（上から見ると扇形に開く）。真上・真下から見ている時は前の経度のまま
            //   4D の向きは今の角度から（effM はこのあと diveSetup で決まるので、ここではまだ前のコマのまま）
            let Bv = camBasis().3, o = SIMD4(SIMD3(Bv.x, Bv.y, Bv.z), 0)
            let m = simd_double4x4(columns: (xf(SIMD4(1, 0, 0, 0)), xf(SIMD4(0, 1, 0, 0)), xf(SIMD4(0, 0, 1, 0)), xf(SIMD4(0, 0, 0, 1)))), ob = m.transpose * o
            if hypot(ob.x, ob.z) > 1e-3 { st.cutPhi = atan2(ob.z, -ob.x) }
        }
        let key = side == .left ? "\(st.zw),\(st.layers),\(st.hemi),\(st.lzw),\(st.axes),\(st.shellModeNow)" : "\(heavyHere),\(st.layers),\(st.hemi),\(st.shellModeNow)"
        if builtKey != key {
            builtKey = key
            if side == .left { buildLeft() } else { buildRight() }
            func buf(_ a: [HLVert]) -> MTLBuffer? { a.isEmpty ? nil : a.withUnsafeBytes { device.makeBuffer(bytes: $0.baseAddress!, length: $0.count, options: .storageModeShared) } }
            triBuf = buf(tris); glassBuf = buf(glass); lineBuf = buf(lines)
        }
        let asp = seeAsp ?? Float(sz.width / max(1, sz.height))          // シースルーは右の窓と同じ写し方で、その隣を描く
        var u = HLUni()
        // ダイブ（右）：超球の向き・4D のカメラ・視野を、景色と同じへ。左右を鏡に（景色の右・上・前と、画面の右・上・奥をそろえるため。超球の外の姿はほぼ左右対称）
        diveSetup()
        if side == .right && dvFade > 0.995 { return }              // 景色に入りきった：上に重ねた景色で隠れるので、超球は描かない（軽く）
        if drawTunnel(e, sz, asp) { return }                         // トンネル（超球ラン・トンネルで見るドリル）：自分を通る 4D の断面だけを描く
        if side == .right && dvT > 0 {
            let (_, e2) = Self.diveEase(dvT), f0 = Self.fitFov(Self.rightFov, asp), fov = f0 + (Float(diveFov) - f0) * Float(e2)   // 終わりは景色と同じ視野
            u.mvp = seeClip * Self.persp(fov, asp) * view3()             // 鏡は描いたあとで（mirf。なめらかに広げる）
            lastFov = Double(fov); lastAsp = Double(asp)
        } else { let fv = Self.fitFov(side == .right ? Self.rightFov : 45, asp); u.mvp = seeClip * Self.persp(fv, asp) * view3(); lastFov = Double(fv); lastAsp = Double(asp) }
        if side == .left { let m = leftRot(); u.model = simd_float4x4(SIMD4<Float>(SIMD3<Float>(m.columns.0), 0), SIMD4<Float>(SIMD3<Float>(m.columns.1), 0), SIMD4<Float>(SIMD3<Float>(m.columns.2), 0), SIMD4(0, 0, 0, 1)) }
        // 照り返しライト（visual-fx の shineRig と同じ置き方）：主光は カメラから見て左 30°・上 33°、逆光は 右うしろ 168°・上 23°。カメラについて回る
        let (eye, R, Up, B) = camBasis()
        func dir(_ az: Double, _ el: Double) -> SIMD4<Float> {
            let a = az * .pi / 180, l = el * .pi / 180
            return SIMD4(SIMD3<Float>(simd_normalize(R * (sin(a) * cos(l)) + Up * sin(l) + B * (cos(a) * cos(l)))), 0)
        }
        u.eye = SIMD4(SIMD3<Float>(eye), 1); u.key = dir(-30, 33); u.rim = dir(168, 23)
        u.camR = SIMD4(SIMD3<Float>(R), 0); u.camU = SIMD4(SIMD3<Float>(Up), 0)
        if side == .right && !overview && !diveWipe && dvT == 0 { knifeMVP = u.mvp; knifeStep(u.mvp, knifeSizeOverride ?? paneView?.bounds.size ?? .zero) }   // ナイフ：切り欠きを動かす（このあとの切り方に入る）
        u.g = SIMD4(Float(max(0, st.gloss)), st.glare && st.gloss > 0 ? 1 : 0, 1, 0)
        if side == .right && (st.glareAuto || (!overview && dvT == 0)) { let k = tickGlint(eye, R, Up, { let k = dir(-30, 33); return SIMD3<Double>(Double(k.x), Double(k.y), Double(k.z)) }()); u.g.x *= k; u.g.y *= k; u.eye.w = k }   // 固定の光はそのまま k 倍（eye.w）
        if side == .right && dvT > 0 { let k = Float(1 - Self.diveEase(dvT).1); u.g.x *= k; u.g.y *= k }   // ダイブ：近づくほど照り返し・グレアを消す（景色には無いので）
        if side == .right && (st.shellModeNow == 1 || st.shellModeNow == 2) { u.g.x *= 0.18; u.g.y *= 0.18 }   // 4 方向レインボー・軸の色：殻が 4 倍重なるので、照り返しの白いぼやけを弱く
        e.setCullMode(.none)
        planeCut(&u)
        // 宇宙モード：さんぽと同じ（さんぽで宇宙の背景を入れている時）か、入
        let wk = (wsrc)?()
        st.spaceNow = st.spaceMode == 1 || (st.spaceMode == 0 && (wk?.space ?? false))
        if st.spaceNow, let bg = spaceBackground(sz) {
            e.setRenderPipelineState(bgPipe); e.setDepthStencilState(depthAlways); e.setFragmentTexture(bg, index: 0)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        }
        if side == .left, !rings.isEmpty, let mb = ringMesh {
            var ul = u; ul.g.z = 1; ul.g.w = 1
            e.setRenderPipelineState(ringPipe); e.setDepthStencilState(depthWrite)
            e.setVertexBuffer(mb, offset: 0, index: 0); e.setVertexBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1)
            rings.withUnsafeBytes { b in
                if b.count <= 4096 { e.setVertexBytes(b.baseAddress!, length: b.count, index: 2) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 2) }
            }
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ringMeshCount, instanceCount: rings.count)
        }
        if let b = triBuf {
            e.setRenderPipelineState(opaquePipe); e.setDepthStencilState(depthWrite); u.g.z = 1; u.g.w = 1
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tris.count)
        }
        if side == .right {
            // 右：層の順に「殻の面（奥行きは書かない）→ その層の線（奥行きを書く）」。ウェブ版（three.js の透明な物の描く順）と同じ。
            //   線が奥行きを書くので、あとの層の面に線が埋もれない。4D の回転・遠近は GPU で（回す行列だけ渡す）
            guard let rb = rBase, let rc = rCol, let ri = rIdx, let rbw = rBaseW, let riw = rIdxW else { return }
            let n = max(2, st.layers), dens = Float(min(1, 12 / Double(n)))
            let solidA: Float = st.mode == 1 ? 0 : (st.mode == 2 ? min(0.85, 0.22 * 1.5 * dens) : 0.22 * dens)
            let wireA: Float = st.mode == 2 ? 0 : min(0.95, 0.22 * (st.mode == 1 ? 3.5 : 2.8) * dens)
            let m = effM
            var hg = HLRight(), hl = HLRight()
            hg.m4 = simd_float4x4(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3)); hl.m4 = hg.m4
            let sp = st.spaceNow
            let demoK = Float(overview ? 1 : st.demoGlass), demoL = 1 + 1.1 * (1 - demoK)   // デモで透かす分、色は明るくして、暗く沈まないように
            hg.q = SIMD4(demoL, solidA * (sp ? 0.22 : 1) * demoK, Float(effCamW), Float(Self.SCALE)); hl.q = SIMD4(1.4 * demoL, wireA * (sp ? Float(HyperLabState.spaceWire) : 1) * Float(1 - st.wireT) * demoK, Float(effCamW), Float(Self.SCALE))
            hg.d.x = Float(effClamp); hl.d.x = Float(effClamp)
            hl.d.y = Float(HyperLabState.wireBackGray); hl.d.z = Float(HyperLabState.wireBackDark)   // 宇宙：殻と網目は控えめに（中の星が見えるよう）
            hg.r = SIMD4(Float(Self.R), Float(rMesh), 0, 0); hl.r = SIMD4(Float(Self.R), Float(rMeshW), 0, 0)
            // 自分のいる所の近くの殻・網目を濃く（さんぽの跡を出している時。4 方向・4 軸は強め、ほかは控えめ）
            if st.walk, let w = wsrc?() {
                let k: Float = (st.shellModeNow == 1 || st.shellModeNow == 2) ? 1 : 0.6
                hg.s = SIMD4<Float>(w.pos); hg.t.x = k; hl.s = hg.s; hl.t.x = k
                // ヘッドライト（ダイブの景色の時だけ）：彗星から遠い殻・網目ほど暗く（遠くは闇に溶ける）
                let hd = Float(Self.diveEase(dvT).1); hg.t.y = hd; hl.t.y = hd
                // 矢印の明かり：予定の道の 0.06・0.12・0.18・0.24 先（ダイブの時だけ）
                if HyperLabState.arrowLight && st.planOn && hd > 0.3 && w.plan.count >= 2 {   // 矢印の明かり（いまは切ってある：殻の色が白く飛ぶので）
                    var acc = 0.0, out: [SIMD4<Float>] = [], want = [0.06, 0.12, 0.18, 0.24], wi = 0
                    for i in 1..<w.plan.count where wi < want.count {
                        acc += simd_length(w.plan[i] - w.plan[i - 1])
                        if acc >= want[wi] { out.append(SIMD4<Float>(w.plan[i])); wi += 1 }
                    }
                    while out.count < 4 { out.append(.zero) }
                    for h in [0, 1] { var r = h == 0 ? hg : hl; r.a0 = out[0]; r.a1 = out[1]; r.a2 = out[2]; r.a3 = out[3]; r.t.w = hd; if h == 0 { hg = r } else { hl = r } }
                }
                let hf = w.head ?? w.vL, fwd = hf - w.pos * simd_dot(hf, w.pos)
                if simd_length(fwd) > 1e-9 { hg.f = SIMD4<Float>(simd_normalize(fwd)); hl.f = hg.f }
            }
            // 4 方向レインボー：網目の線は、極に近い殻でも前より濃くしない（濃くすると、奥のかすみで暗くした線が黒い線になって上に重なる）。r.z：網目の濃さの上限
            //   宇宙の時は、網目と殻をもう少し透明に（中の星屑が見えるように）
            if st.shellModeNow == 1 && shellFams(left: false).count > 1 { hl.r.z = sp ? 0.28 : 0.45; if sp { hg.q.y *= 0.7 } }   // 軸の色（4 軸）は色が組ごとに違うので、足し合わせると白く混ざる。網目は前のまま
            //   ダイブで寄るほど、網目と殻をさらに透明に（中の星屑の景色を主役に）
            if hl.r.z > 0 { hg.r.z = 1 }                                     // 殻のふちを少し濃く（hrv）
            else if st.shellModeNow == 0 { hg.t.z = 1 }                       // ふつうのレインボー：斜めから見た殻を濃く（hrv）
            if hl.r.z > 0 && dvT > 0 { let dz = Float(Self.diveEase(dvT).1); hl.r.z *= 1 - 0.35 * dz; hg.q.y *= 1 - 0.15 * dz }
            // 4D の遠近：ダイブで寄るほど弱める（寄った所は景色と同じに）
            let dk = st.depth4On ? Float(st.depth4K * (1 - Self.diveEase(dvT).1)) : 0
            hg.e = SIMD4(st.depth4 == 1 || st.depth4 == 3 ? dk : 0, st.depth4 >= 2 ? dk : 0, 0, Float(max(naviBall, ovBall))); hl.e = hg.e
            hg.d.w = 3; hl.d.w = 3
            if naviHole > 0.001 { hg.n = SIMD4(SIMD3<Float>(simd_normalize(eye)), Float(naviHole)); hl.n = hg.n }
            hg.ey.w = Float(rSub); hl.ey.w = Float(rSub * rMeshW / rMesh)   // 線で囲まれた升の大きさ（細かい網目の何個ぶんか）
            if overview {                                                     // 地図の殻の立体感：光は画面の上・少し左・少し手前から
                let (_, Rv, Uv, Bv) = camBasis(), l = simd_normalize(Uv * 0.85 - Rv * 0.35 + Bv * 0.4)
                hg.v = SIMD4(1, Float(l.x), Float(l.y), Float(l.z)); hl.v = hg.v
                hg.fd.w = Float(simd_length(eye)); hl.fd.w = hg.fd.w
                hg.fd.y = ovMotion && st.ovView == 3 ? 1 : Float(naviBall)    // 面だけなので、線の定数には入れない
                hg.ey.x = Float(Bv.x); hg.ey.y = Float(Bv.y); hg.ey.z = Float(Bv.z); hl.ey.x = hg.ey.x; hl.ey.y = hg.ey.y; hl.ey.z = hg.ey.z
            } else if dvT > 0 && st.wireAuto {                                // ダイブ画面：網目は近くだけ残して、遠くは色に任せる
                let R3 = Float(Self.R * Self.SCALE), dz = Float(Self.diveEase(dvT).1)
                hg.ey.x = Float(eye.x); hg.ey.y = Float(eye.y); hg.ey.z = Float(eye.z); hl.ey.x = hg.ey.x; hl.ey.y = hg.ey.y; hl.ey.z = hg.ey.z
                hg.fd = SIMD4(0.75 * dz, 0.5 * R3, 1.6 * R3, 1); hl.fd = hg.fd
            }
            // 天の川の淡い光は出さない（暗いのが魅力）。天の川は星の密度で見せる（drawStars）
            var ug = u; ug.g.z = HyperLabState.shellPixelLight ? 1 : 2; ug.g.w = 0   // 殻の光：ふだんは頂点ごと（2）。比べる時は画素ごと（1）
            if heavyHere { ug.hv = SIMD4(1, hg.t.z, hg.r.z, 0) }
            if ovMotion && st.ovView == 3 { ug.g.x = 0; ug.g.y = 0; ug.eye.w = 0 }   // W 消失地図：照り返しを足さず、殻のそのままの色で
            if !overview && dvT > 0 { ug.hv.w = 0.6 * Float(Self.diveEase(dvT).1); let nr: Double = Self.R * Self.SCALE * effCamW / max(effClamp, effCamW - Self.R); ug.sd.z = Self.nearFade * Float(min(1, Self.diveEase(dvT).1 * 2.5) * nr * dvThird) }
            var ul = u; ul.g.z = 0; ul.sd.z = ug.sd.z
            if st.cutOn && st.cutKind == 0 {                         // ポリゴンカットは物体に固定と同じ殻の経度で、真ん中を押した時の手前の経度（cutPhi）に
                let poly = st.cutRef == 2
                let c = SIMD4<Float>(Float(poly ? 2 : st.cutRef + 1), Float(poly ? st.cutPhi : st.cutAngDeg * .pi / 180), Float(st.cutWDeg * .pi / 360), 0)
                ug.cut = c; ul.cut = c
            }
            if st.cutOn && st.cutKind == 2 && dvT == 0 {               // 4D で切る：超平面 w′ ＝ 一定の切り口だけ（殻・軸・跡は出さない）
                drawSlice4(e, u, m)
                var hs = hg; hs.r.z = Float(st.cutPos * Self.R); hs.r.w = Float(st.cut4Axis); drawStars(e, u, hs, slice: true)
                return
            }
            if dvT == 0 || st.axesDive { drawAxes4(e, u) }           // ダイブの間も（「ズーム中も」を切ると出さない）
            // 地図のカーソルのまわり：殻と網目だけを薄くして、カーソルを目立たせる（星は消さない）。上の地図は、ポリゴンごと抜く穴（holeIn）
            if overview, naviM == nil, st.walk, let w = (wsrc)?() {
                let q = u.mvp * SIMD4(SIMD3<Float>(wPlace(w.pos).0), 1)
                if q.w > 1e-4 {
                    let W = Float(sz.width), H = Float(sz.height)
                    u.halo = SIMD4((q.x / q.w * 0.5 + 0.5) * W, (0.5 - q.y / q.w * 0.5) * H, 0.13 * min(W, H), 0.9)
                }
            }
            // 赤星・紫星までの視線を開ける：遠くの星が殻に埋もれないように。星がカメラのすぐ近くの時は開けない（星そのものが大きい）
            if !overview && dvT > 0 && st.wireAuto {
                let W = Float(sz.width), H = Float(sz.height), dz = Float(Self.diveEase(dvT).1)
                for k in 0..<2 {
                    let P = wPlace(FIXED[k].c).0, q = u.mvp * SIMD4(SIMD3<Float>(P), 1), d = simd_length(P - eye)
                    guard q.w > 1e-4 else { continue }
                    let far = Float(smoothstep(0.12, 0.5, d / (Self.R * Self.SCALE)))
                    let s = SIMD4((q.x / q.w * 0.5 + 0.5) * W, (0.5 - q.y / q.w * 0.5) * H, 0.17 * min(W, H), 0.85 * dz * far)
                    let dk = Float(d - 0.5 * Self.R * Self.SCALE)                     // 星のまわりの色の殻は残す（星より少し手前までの殻だけ薄くする）
                    if k == 0 { ug.sa = s; ul.sa = s; ug.sd.x = dk; ul.sd.x = dk } else { ug.sb = s; ul.sb = s; ug.sd.y = dk; ul.sd.y = dk }
                }
            }
            var wk = SIMD4<Float>(Float(sz.width), Float(sz.height), Float((overview && st.wireWMap > 0 ? st.wireWMap : st.wireW) * rK * 0.5), 0)   // 線の太さ（画面の点 × 細かさ）。地図は別に変えられる
            e.setRenderPipelineState(rPipe); e.setVertexBuffer(rb, offset: 0, index: 0); e.setVertexBuffer(rc, offset: 0, index: 3)
            // 4 方向レインボー・軸の色：面を全部先に描いてから、線をまとめて描く（線が奥行きを書くので、層ごとに交互に描くと、あとの面が線の所だけ抜けて黒い筋になる）
            let multiFam = (st.shellModeNow == 1 || st.shellModeNow == 2) && shellFams(left: false).count > 1   // 4 方向レインボー・軸の色（4 軸）
            // W 消失地図の玉ねぎ：外の殻から順に透明にして、波が内へ行って戻る（真ん中の殻は残す）
            hg.ms = SIMD4(1, Float(0.72 * ovPolyK), ovFxSeed, 0); hl.ms = SIMD4(1, 0, 0, 0)
            func shellK(_ r: (g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>)) -> Float {
                guard overview, ovOnionK > 0.002 else { return 1 }
                let rn = simd_length(walkPlace(r.e).0 - walkPlace(r.c).0) / (Self.R * Self.SCALE), f = 0.6 + 0.35 * cos(nowT * 0.8)
                return Float(1 - ovOnionK * 0.96 * smoothstep(f - 0.1, f + 0.1, rn))
            }
            func drawFaces(_ r: (g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>)) {
                if solidA > 0 && !r.g.isEmpty {
                    hg.ms.x = shellK(r)
                    e.setDepthStencilState(depthRead)
                    e.setVertexBytes(&ug, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ug, length: MemoryLayout<HLUni>.stride, index: 1)
                    e.setVertexBytes(&hg, length: MemoryLayout<HLRight>.stride, index: 2)
                    e.drawIndexedPrimitives(type: .triangle, indexCount: r.g.count, indexType: .uint32, indexBuffer: ri, indexBufferOffset: r.g.lowerBound * 4)
                }
            }
            func drawWires(_ r: (g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>)) {
                if wireA > 0 && !r.l.isEmpty && hl.q.y > 0 {
                    hl.ms.x = shellK(r)
                    // 網目は太さのある帯で（1 画素の線は細すぎて色が薄く見える）。宇宙の時は足し合わせて光らせる（さんぽの景色の線のように）
                    // 4 方向レインボー・宇宙でダイブ中：線は奥行きを書かない（書くと、あとから描く星屑が線の所だけ隠れて、暗い筋になる）。
                    //   外から見る時は書く（書かないと、奥の線まで全部重なって白く飛ぶ）
                    //   奥行きを書かないのは 4 方向レインボーだけ（網目の濃さに上限があるので、奥まで見えても白く飛ばない）
                    e.setDepthStencilState(!multiFam || (hl.r.z > 0 && sp && dvT > 0) ? depthRead : depthWrite)
                    e.setRenderPipelineState(sp || hl.r.z > 0 ? wirePipeAdd : wirePipe)   // 4 方向レインボーも光の線（暗い紫が黒い線に沈まない）
                    e.setVertexBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&ul, length: MemoryLayout<HLUni>.stride, index: 1)
                    e.setVertexBytes(&hl, length: MemoryLayout<HLRight>.stride, index: 2)
                    e.setVertexBuffer(rbw, offset: 0, index: 0); e.setVertexBuffer(riw, offset: r.l.lowerBound * 4, index: 4); e.setVertexBytes(&wk, length: 16, index: 5)
                    e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: r.l.count / 2)
                    e.setRenderPipelineState(rPipe); e.setVertexBuffer(rb, offset: 0, index: 0)
                }
            }
            // 超球（試作）：同じ超球面を半径を変えて外から内へ重ねる（内側の殻は線なしで、層を 3 枚に 1 枚に間引いて軽く）
            // R の世界にいる時：その S³ をふつうに、外の超球はうっすら（ダイブ・地図は今いる S³ だけ）。この R だけ表示は、つまみの R の S³ だけ
            let wr = walkK, inWorld = wr < 0.9995
            let one: Float = 1, faint: Float = 0.35
            var fillShells: [(r: Double, k: Float)] = [(1, one)]                // 詰める・拡張のステージ
            if !overview && st.drillK > 0.001 {                             // ドリル：ステージの殻をうっすら（掘り進む間に通りすぎる）、今いる S³ はふつうに
                fillShells = HyperLabState.stageR.filter { abs($0 - wr) > 0.04 }.map { ($0, Float(0.3 * st.drillK)) } + [(wr, one)]
            }
            else if overview || dvT > 0 { fillShells = [(wr, one)] }
            else if st.rOnly { fillShells = [(st.rOnlyR, one)] }
            else if st.expandOn { fillShells = st.expandShells() }
            else if st.fillOn { fillShells = st.fillShells() }
            else if inWorld { fillShells = [(1, faint), (wr, one)] }
            let fillG = hg.q.y * (fillShells.count > 1 ? 0.6 : 1), fillL = hl.q.y
            // 内側の超球は球層を間引く（重いので）：R ＝ 1 の層の数のうち fillLayers 層ぶんを、北から南へ均等に選ぶ
            let thinF = min(1, Double(st.fillLayers) / Double(max(2, st.layers)))
            let thinRanges: [(g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>)] = {
                let m = ranges.count, t = max(1, min(m, Int((Double(m) * thinF).rounded())))
                guard t < m else { return ranges }
                return (0..<t).map { ranges[t == 1 ? 0 : Int((Double($0) * Double(m - 1) / Double(t - 1)).rounded())] }
            }()
            for sh in fillShells {
            // 内側の殻は重いので層を間引いて線なし。1 枚だけ描く時（ほかのステージを消す）は、外の殻と同じに全部の層と線で
            let full = sh.r > 0.999 || fillShells.count == 1 || (inWorld && !st.fillOn && abs(sh.r - wr) < 1e-9), shellRanges = full ? ranges : thinRanges
            // 内核の演出：殻の本当の半径（今いる世界の殻は、ダイブで広げていても今の R）が小さいほど強く
            let rTrue = abs(sh.r - wr) < 1e-9 ? st.worldR : sh.r, ck = side == .right && !overview && st.chaosOn ? pow(max(0, 1 - rTrue), 0.8) : 0
            hg.cz = SIMD4(Float(ck), Float(nowT.truncatingRemainder(dividingBy: 1000)), Float(0.4 + 2.2 * ck), Float(0.035 * ck)); hl.cz = hg.cz
            hg.ms.w = Float(1 - sh.r); hl.ms.w = hg.ms.w; let thinBoost: Float = full ? 1 : Float(1 + 0.9 * (1 - thinF)); hg.q.y = fillG * sh.k * thinBoost; hl.q.y = full ? fillL * min(1, sh.k * 1.5) : 0
            if multiFam { for r in shellRanges { drawFaces(r) }; for r in shellRanges { drawWires(r) } }
            else {
                // 半透明なので、重ねる順番がそのまま奥行きになる：カメラから面までがいちばん遠い殻から順に、面と線を重ねる（線は奥行きを書かない。書くと、あとの面が線の形に抜けて黒い線になる）
                func gap(_ r: (g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>)) -> Double {
                    let c = walkPlace(r.c).0, rho = simd_length(walkPlace(r.e).0 - c)
                    return abs(simd_length(eye - c) - rho)
                }
                // W 消失地図で手前を切った時は、お椀の内側を見ることになるので、外の殻（いちばん奥）から順に重ねる
                let bowl = (overview && st.ovView == 3 && max(ovCutK, ovWedgeK) > 0.3) || (!overview && cutFacesViewer())   // 大きな超球の断面カットで手前を切った時も同じ
                let inner = shellRanges.map({ ($0, gap($0)) }).sorted(by: { $0.1 > $1.1 }).map({ $0.0 })   // 内から外へ（手前の半分の奥行きの順）
                if bowl && !overview {
                    // 切り口がこちらを向いている時、殻を丸ごと並べると、外の殻の切っていない手前の部分が内の殻の下に埋まる（切っていない所なのに中が透けて見える）。
                    //   殻を奥の半分と手前の半分に分けて、奥は外から内へ、手前は内から外へ重ねる（本当の奥行きの順）
                    func half(_ r: (g: Range<Int>, l: Range<Int>, c: SIMD4<Double>, e: SIMD4<Double>), _ mode: Float) {
                        let c = walkPlace(r.c * Double(1 - hg.ms.w)).0
                        ug.hb = SIMD4(SIMD3<Float>(c), mode); ul.hb = ug.hb; drawFaces(r); drawWires(r)
                    }
                    for r in inner.reversed() { half(r, 1) }
                    for r in inner { half(r, 2) }
                    ug.hb = .zero; ul.hb = .zero
                } else {
                    for r in bowl ? inner.reversed() : inner { drawFaces(r); drawWires(r) }
                }
            }
            }
            hg.ms.w = 0; hl.ms.w = 0; hg.q.y = fillG; hl.q.y = fillL; hg.cz = .zero; hl.cz = .zero
            u.halo = .zero
            drawStars(e, u, hg)
            // 寄った時の星は、さんぽと同じ本物の星だけ（drawStars。天の川は、さんぽと同じ y・z の大きな円のまわりの星）
            drawLightWrap(e, u)
            drawKnife(e, u)
            drawDrill(e, u)
            drawWalk(e, u); drawMarks(e, u)                               // ダイブの間も、跡をたどって背中へ寄る（玉は画面の上で大きくなりすぎないよう縮める）
            if st.spaceNow && st.shellModeNow == 1 { drawFlare(e, u) }   // 4 方向レインボー・宇宙：天の川の中心のレンズフレア
            if dvT == 0 && !overview && st.rot2On && st.rot2Rings && !st.demoOn { drawRot2Rings(e, u) }
            if dvT == 0 && !overview && st.expandOn { drawExpand(e, u) }
            if dvT == 0 || st.axesDive { drawAxisLabels(e, u) }
            return
        }
        if let b = glassBuf {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthRead); u.g.z = 1; u.g.w = 0
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: glass.count)
        }
        if let b = lineBuf {
            // 線は太さのある帯で（左は 2 倍の大きさに描くので、太さも 2 倍）
            var k = SIMD4<Float>(Float(sz.width), Float(sz.height), Float(st.wireW * (side == .left ? 2 : 1) * rK * 0.5), 0)   // 画質を下げても、画面の上の太さは同じ
            e.setRenderPipelineState(segPipe); e.setDepthStencilState(depthRead); u.g.z = 0
            e.setVertexBuffer(b, offset: 0, index: 0); e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.setVertexBytes(&k, length: 16, index: 5)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6, instanceCount: lines.count / 2)
        }
        drawAxes3(e, u)
        if st.cutOn && st.cutKind == 2 { drawSlicePlane2(e, u) }
        var hL = HLRight(); hL.r = SIMD4(Float(Self.R), 0, 0, 0); drawStars(e, u, hL)
        drawWalk(e, u); drawMarks(e, u); drawAxisLabels(e, u)
    }
    // ---- 座標の矢印（さんぽの地図と同じ色：x 赤・y 緑・z 青・w 紫）----
    static let AXL = 1.35 * 1.32                                      // 矢印の長さ（球の半径の 1.32 倍）
    static let axisCol: [SIMD3<Float>] = [SIMD3(1.0, 0.365, 0.424), SIMD3(0.239, 0.863, 0.518), SIMD3(0.337, 0.659, 1.0), SIMD3(0.690, 0.486, 1.0)]
    static let axisName = ["x", "y", "z", "w"]
    /// ダイブの間（右）は画面を左右の鏡にしているので、札の文字は逆に並べて裏返らないように
    var mirrorX: Double { side == .right && diveMirror > 0.3 ? -1 : 1 }
    /// ダイブの鏡の広がり（0：鏡なし〜0.5：画面の端まで鏡。少し先まで行って、ふちのぼかしも画面の外へ）。
    ///   自分が画面の真ん中にそろった後（向きのそろえは 0.5 まで）、寄っていく途中の 0.52〜0.78 で広げる（真ん中がずれていると、物が 2 つに分かれて見える）
    var diveMirror: Double { side == .right && dvT > 0 ? -0.1 + 0.75 * smoothstep(0.52, 0.78, dvT) : -0.1 }
    /// 歩いた跡・目印の点を画面の 3 次元へ（右：超球の上を 4D の回転・遠近で、左：影 (x, y, w) を球の上へ）。face：見えている側なら 1、奥の側は 0
    /// 歩いた物（彗星・跡・目印・光の回り込み）の写し方：今いる R の世界の S³ の上（左の球はいつも外の球の上）。
    ///   ダイブで寄る間は R ＝ 1 の大きさへなめらかに広げる（寄り切ると今までのダイブと同じ。4D のカメラが小さい S³ の中へ入ると、外の星・極の印がカメラの後ろへ回って画面をおおうので）。地図はいつも R ＝ 1 の大きさ
    ///   ドリルの間は本当の半径のまま（中心へ落ちていくのが見える）
    var walkK: Double {
        guard side == .right, !overview, st.worldR < 0.9995 || st.drillK > 0 else { return 1 }
        let normal = st.worldR + (1 - st.worldR) * (dvT > 0 ? Self.diveEase(dvT).1 : 0)
        return normal + (st.worldR - normal) * st.drillK
    }
    func wPlace(_ p: SIMD4<Double>) -> (SIMD3<Double>, Double) { walkPlace(p * walkK) }
    func walkPlace(_ p: SIMD4<Double>) -> (SIMD3<Double>, Double) {
        let R = Self.R, camW = side == .right ? effCamW : st.camW
        if side == .right {                                                // 右はカメラの向きを使わない（camBasis は重いので、左の時だけ求める）
            let v = effM * (p * R), s = camW / max(effClamp, camW - v.w) * Self.SCALE
            return (SIMD3(v.x, v.y, v.z) * s, smoothstep(-0.1, 0.05, (v.w - R * R / camW) / R))
        }
        let eye = camBasis().0
        var q = SIMD3(p.x, p.y, p.w); let l = simd_length(q); q = l < 1e-9 ? SIMD3(0, 0, 1) : q / l
        let w = leftRot() * (q * R * 1.012)
        return (w, smoothstep(-0.15, 0.1, simd_dot(simd_normalize(w), simd_normalize(eye - w))))
    }
    /// 強い照り返しのよけ：殻が平たくなる向きでは、何枚もの殻の照り返しが同じ所へ重なって白いかたまりになる。少ない点で殻の照り返しを足して、
    ///   画面の粗い升目でいちばん強い所を測り、強いと判断した間だけ反射を切る（さっと切って、弱くなったら戻す自動）。測るのは 1 秒に 10 回
    var glintT = -9.0, glintLast = -9.0, glintNow = 0.0, glintK: Float = 1, glintCut = false, glintFlashT = -99.0, glintNext = 0.0
    static var glintLo = 5.5, glintHi = 7.5
    static var glintLog = false
    var camLogT = -9.0, railI = 0, railN = 0, railTrailN = 0, railG = -1
    /// 周の区切りの線：railEnd ＝ 先の線の終わり（−1 は道の終わりまで）、railTail ＝ まだ道の終わりの側を走っている（その先に、道のはじめから railEnd までが続く）、
    ///   railT0 ＝ 区切りの時刻（新しい線が伸びていく・前の周の線が消えていく）、railGhost ＝ 前の周の線
    var railEnd = -1, railTail = false, railT0 = -99.0, railGhost: [SIMD4<Double>] = [], railPrev: [SIMD4<Double>] = []
    static let glintL1 = simd_normalize(SIMD3<Double>(5, 12, 8))
    /// 当たった瞬間（極・目印が「通った」になった時刻）：ピカッと光らせる。前のコマの「通った」を覚えて比べる（初めのコマは光らせない）
    /// 光っている間（1 秒）は描き続ける（当たった瞬間の記録は Journey.hitPulse）
    var flashing: Bool { let now = ProcessInfo.processInfo.systemUptime; return Journey.hitPulse.contains { now - $0.t < 1.0 } }
    // ---- ダイブ ----
    var effM = matrix_identity_double4x4, effCamW = 3.8, effClamp = 0.6, diveFov = 70.0
    /// おくれて追うカメラの向き（S³ の自分のいる所の接空間）と、彗星が画面の中で先へ出た分（3D）・カメラの傾き（バンク）
    var lagR: SIMD4<Double>?, lagU = SIMD4<Double>(), lagL = SIMD4<Double>(), lagT = 0.0
    var leadOff = SIMD3<Double>(), bank = 0.0, lagMix = 0.0
    /// 彗星の頭のゆがみ（3D。曲がる向き・強さ）：すぐ追う向き warpL からのずれを、ばね（少し揺れる）でならす
    var warpL: SIMD4<Double>?, headWarp = SIMD3<Double>(), headWarpV = SIMD3<Double>()
    /// オートカメラの見せ場：前の方に目印・極・道の点・カーブが近づくと、カメラが少しそちらを向き、彗星は画面の空いた所（反対側、
    ///   左右・上下どこでも）へずれて、行き先が見える。通り過ぎるとゆっくり元の構図へ。focusDir：行き先の向き（3D）、focusW：強さ 0〜1
    var focusDir = SIMD3<Double>(), focusW = 0.0, focusT = 0.0
    /// ハイライトは一瞬：同じ行き先へは 1.6 秒だけ向き、通り過ぎて離れるまでは、もう向かない（focusKey：今の行き先、focusAge：向いている時間）
    var focusKey = "", focusAge = 0.0, focusUsed: Set<String> = []
    /// 球面さんぽで歩いた跡と今いる所（お遊び）。
    ///   右：S³ はこの超球そのもの。歩いた点 (x, y, z, w) を R 倍して、殻と同じ 4D の回転・遠近で写す（超球の面の上を這う光の線）。
    ///   左：2 次元とのアナロジー。4 つ目の z を落とした影 (x, y, w) を球の上へ（左の高さ z は右の w。輪と同じ対応）。
    ///   線はカメラに向いた帯（にじみの太い帯＋芯）、古い所ほど青く淡く、新しい所ほど白く明るい。超球（球）の奥の側は薄く。今いる所は青緑の玉
    /// 光の回り込み（超球の大きな画面。アナ極・カタ極の近くで）：自分から全方向へ出た大円は、超球を回って自分の反対側の 1 点に集まる。
    ///   その線を光らせて、反対側から出た光の粒が回り込んで自分へ届くところを見せる。反対側が極のそばに来るので、極の色が視界いっぱいに追い上げて見える
    static let wrapDirs: [SIMD3<Double>] = (0..<18).map { i in
        let z = 1 - 2 * (Double(i) + 0.5) / 18, a = Double(i) * 2.399963, r = (1 - z * z).squareRoot()
        return SIMD3(r * cos(a), r * sin(a), z)
    }
    /// ときどき彗星が画面の手前へ迫る強さ（0〜1）。たまにだけ（3 つのゆっくりした波が重なって強まる時。メリハリが大事）。
    ///   迫る間は、予定の道の矢印の間も詰めて見せる（望遠のように、奥行きが詰まって見える）
    var surgeK: Double {
        guard side == .right, st.autoCam, !st.camHeld, dvThird > 0.3 else { return 0 }
        let t = nowT, zw = max(0, sin(t * 0.21) * sin(t * 0.53 + 0.7) * sin(t * 0.083 + 2.1))
        return smoothstep(0.3, 0.7, zw)
    }
    // 目印の色の候補：金・暖かい白・水色・青白・桃色・若葉
    static let beadPalette: [SIMD4<Float>] = [SIMD4(1.0, 0.78, 0.35, 1), SIMD4(1.0, 0.93, 0.8, 1), SIMD4(0.5, 0.9, 1.0, 1), SIMD4(0.75, 0.85, 1.0, 1), SIMD4(1.0, 0.68, 0.9, 1), SIMD4(0.65, 1.0, 0.7, 1)]
    static let beadAxisTint: Float = 0.3                                // 軸の色をどれだけ混ぜるか（ほんのり）
    static let beadStretch = Double(ProcessInfo.processInfo.environment["S3_BEAD"] ?? "") ?? 2.2   // 光のビーズの、まっすぐな所で進む向きに伸びる長さ（1 で球。確かめの絵でくらべる。曲がる所はまるくなる）
    var planWAcc = 0.0, planWLast: Double? = nil               // 粗密：歩いたぶんの重みつきの道のり（矢印の並びのもと）と、前のコマの歩いた道のり
    var curveSpin: [Int: Double] = [:]                       // 立体の矢印ごとの、カーブで自分から回った角
    var spinSm: [Int: (r: Double, v: Double)] = [:]          // 立体の矢印ごとの、ドミノのスピンの回り（ばね。風に吹かれるように）
    var planRoll: (r: Double, v: Double)? = nil                 // 立体の矢印の鎖全体の回し（ばね）
    var planFrame: SIMD4<Double>? = nil                         // 立体の矢印の、道の始まりでの横の向き（平行移動で運ぶもと）
    var arrowRoll: [Int: (r: Double, v: Double)] = [:]          // 予定の道の矢印ごとの、水平の軸の傾き（ばねでゆっくり追う）
    var arrowSm: [Int: (dev: Double, bank: Double, dv: Double, bv: Double)] = [:], arrowSmT = 0.0   // 予定の道の矢印ごとの、向きのずれと傾き（とその速さ。スピードメーターの針のように、ばねで動く）
    var marchGap = 0.0                                         // 寄った時の予定の道の矢印の間隔（S³ の道のり。ゆっくり合わせる）
    var railLast = 0                                           // 通った矢印の番号（線路の音）
    static var railGap = 0.0                                           // 今の矢印の間隔（決まった道から作る書き出しの音で使う）
    var lastFov = 37.0, lastAsp = 1.0                          // 今の絵の縦の視野（度）と横÷縦（レンズフレアを画面の上に置くため）
    /// 確かめの絵用：歩いた跡の代わり（無ければアプリのもの）
    var walkOverride: (() -> HyperLabState.Walk)?
    /// 歩いた跡などの読み口（確かめの絵では walkOverride、ふだんは 1 コマに 1 度・なめらかにした st.walkFrame）
    var wsrc: (() -> HyperLabState.Walk)? {
        if let o = walkOverride { return o }
        guard HyperLabState.walkSource != nil else { return nil }
        return { [st] in st.walkFrame() ?? HyperLabState.Walk(trail: [], pos: SIMD4(0, 0, 0, 1)) }
    }
    /// カメラの位置と、右・上・うしろ（画面の奥と逆）の向き
    func camBasis() -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
        let ovFixed = ovMotion || naviM != nil                           // 2 枚の地図は、ドラッグの 3D の向きを使わない
        var yaw = side == .left ? 0 : ovMotion ? ovViewYaw + ovSpin + st.ovDragYaw : ovFixed ? 0 : st.viewYaw, pit = side == .left ? 0 : ovMotion ? max(-1.45, min(1.45, ovPitch + st.ovDragPitch)) : ovFixed ? 0 : st.viewPitch, dist = side == .left ? st.leftDist : st.viewDist
        if ovMotion { dist *= ovZoomK }
        if side == .right && dvT > 0 {                              // ダイブ：見る向きは正面へ、3D のカメラは自分のいる所（原点）へ
            let (e1, e2) = Self.diveEase(dvT)
            // 一人称：見る向きは正面、背中へ寄る（近いほどゆっくり）。三人称：斜め後ろの少し上で止まって、自分（彗星）を追う
            // 三人称の斜め：鏡が広がるのに合わせて、真後ろを通って反対側へ回り込む（鏡と合わせて、見かけはずっと同じ側の斜め後ろ）
            let mw = smoothstep(0.52, 0.78, dvT), th = dvThird
            let ty = th * st.chaseYawS * (1 - 2 * mw) * .pi / 180, tp = th * st.chasePitchS * .pi / 180, td = 0.02 + (st.chaseDistS - 0.02) * th
            yaw += (ty - yaw) * e1; pit += (tp - pit) * e1; dist = td + (dist - td) * pow(1 - e2, 1.6)
            // オートカメラ（三人称の時だけ）とズーム中に回した分（自分のまわりを回る。離すと所定の角度へゆっくり戻る）
            yaw += (st.autoYaw * dvThird) * e1; pit += st.autoPitch * dvThird * e1
            // ときどき彗星が画面の手前へ迫る（カメラとの距離がぐっと縮まり、またゆっくり離れる。ゆっくりした 2 つの波が重なって強まる時だけ）
            dist *= 1 - 0.42 * surgeK * dvThird * e1
            dist *= 1 + (st.showDist - 1) * dvThird * e1                   // ショーカメラの寄り・引き
            yaw += st.diveYawOff * e1; pit = max(-1.45, min(1.45, pit + st.divePitchOff * e1))
        }
        var eye = SIMD3(sin(yaw) * cos(pit), sin(pit), cos(yaw) * cos(pit)) * dist
        let f = simd_normalize(-eye), up = SIMD3<Double>(0, 1, 0)
        var r = simd_normalize(simd_cross(f, up)), uu = simd_cross(r, f)
        let ez = side == .right && dvT > 0 ? Self.diveEase(dvT).0 : 0     // カメラのずらしや傾きは、ズームといっしょに 0 から始まり 0 で終わる（超球へ戻った瞬間に絵が飛ばない）
        if side == .right && dvT > 0 && focusW > 0 {
            // 見せ場：行き先が画面の真ん中寄りに来るよう、カメラを行き先の側へずらす（彗星は反対側の空いた所へ。左右・上下どこでも）。
            //   行き先がちょうど彗星の真後ろに重なる時は、彗星を下へずらす
            var dd = r * simd_dot(focusDir, r) + uu * simd_dot(focusDir, uu) * (st.camShow ? 0.35 : 1)   // ショーカメラは上下へはあまりずらさない（彗星が画面の下へ寄りすぎない）
            let dl = simd_length(dd)
            dd = dl > 0.25 ? dd / dl : simd_normalize(dd + uu * (0.25 - dl) * 4)
            eye += dd * (0.42 * dist * focusW * ez)
        }
        if side == .right && dvT > 0 && dvThird > 0.3 && leadOff != SIMD3() {
            // 疾走の揺れ：速いほど、まっすぐでも細かく震える。きつく曲がる時は、ときどき（ゆっくりした波で強まる時だけ）強く揺れる（スピード感）
            let t = CACurrentMediaTime()
            let turnK = smoothstep(0.06, 0.3, simd_length(leadOff)), spdK = 0.4 + 0.6 * st.cometSpd
            let burst = smoothstep(0.15, 0.6, (0.5 + 0.5 * sin(t * 0.9)) * (0.5 + 0.5 * sin(t * 0.37 + 1.3)) * 2)
            let a = 0.03 * st.shakeK * dist * (turnK * spdK * (0.25 + 0.75 * burst) + 0.4 * st.cometSpd * st.cometSpd) * dvThird * ez
            if a > 1e-6 {
                let jx = 0.6 * sin(t * 31) + 0.4 * sin(t * 47 + 1), jy = 0.6 * sin(t * 37 + 2) + 0.4 * sin(t * 53)
                eye += (r * jx + uu * jy) * a
            }
            eye += uu * (0.05 * st.shakeK * dist * st.airLift * st.cometSpd * dvThird * ez)   // 空気の渦の揺れ（音の息づかいと同じ揚力）
        }
        if side == .right && dvT > 0 && st.showFrame != .zero {
            // ショーカメラの構図：彗星を画面の左上・右上などへ（カメラの見る所を反対へずらす）
            eye -= (r * st.showFrame.x + uu * st.showFrame.y) * (dist * dvThird * ez)
        }
        if side == .right && dvT > 0 && st.showRoll != 0 {
            // ショーカメラの斜め構え：カメラを少し傾ける
            let a = st.showRoll * dvThird * ez, cb = cos(a), sb = sin(a)
            let r2 = r * cb - uu * sb, u2 = uu * cb + r * sb
            r = r2; uu = u2
        }
        if side == .right && dvT > 0 && (bank != 0 || leadOff != SIMD3()) {
            // オートカメラ：彗星が曲がる側へ先に流れる（カメラの見る所を反対へずらす）＋あとから曲がる側へ傾く
            let d = leadOff, sh = (r * simd_dot(d, r) + uu * simd_dot(d, uu) * (st.camShow ? 0.5 : 1)) * (0.55 * dist * ez)
            eye -= sh
            let cb = cos(bank * ez), sb = sin(bank * ez)
            let r2 = r * cb - uu * sb, u2 = uu * cb + r * sb
            r = r2; uu = u2
        }
        return (eye, r, uu, -f)
    }
    func view3() -> simd_float4x4 {
        let (eye, r, uu, b) = camBasis(), f = -b
        let m = simd_double4x4(rows: [SIMD4(r, -simd_dot(r, eye)), SIMD4(uu, -simd_dot(uu, eye)), SIMD4(-f, simd_dot(f, eye)), SIMD4(0, 0, 0, 1)])
        return simd_float4x4(SIMD4<Float>(m.columns.0), SIMD4<Float>(m.columns.1), SIMD4<Float>(m.columns.2), SIMD4<Float>(m.columns.3))
    }
    /// 画面の形に合わせた縦の視野：横長の時は縦 fov のまま、縦長の時は横が fov になるよう広げる（幅と高さの狭い方に球が収まる。
    ///   仕切りで画面を広げると、球も自動で大きくなる）
    /// 右の超球の基本の視野：ふだんの距離（7.5）で、超球の輪郭（半径 ≈ 2.24）が画面の狭い方の 93% ほど（仕切りで広げると、ぎりぎりまで大きく）
    static let rightFov: Float = 37
    static func fitFov(_ fovDeg: Float, _ asp: Float) -> Float {
        guard asp < 1 else { return fovDeg }
        return 2 * atan(tan(fovDeg * .pi / 360) / max(0.05, asp)) * 180 / .pi
    }
    static func persp(_ fovDeg: Float, _ asp: Float) -> simd_float4x4 {
        let n: Float = 0.1, f: Float = 100, ys = 1 / tan(fovDeg * .pi / 360), xs = ys / asp
        return simd_float4x4(rows: [[xs, 0, 0, 0], [0, ys, 0, 0], [0, 0, f / (n - f), f * n / (n - f)], [0, 0, -1, 0]])
    }
}
