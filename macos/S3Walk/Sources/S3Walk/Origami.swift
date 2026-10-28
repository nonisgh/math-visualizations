// 次元おりがみ（ネイティブ版・移植の第 1 歩）：ウェブ版 hypercube.html の基本を、Swift と Metal（光で描く TesseractLab の描き方）で。
//   左：2D の展開図（正方形 6 枚）を折りたたんで立方体に。右：3D の展開図（立方体 8 つ）を折りたたんで超立方体に。
//   折り方はウェブ版（共通部品 nd-geom の PRESETS.okami）と同じ：腕が先（0〜0.60）、ふたは少しあと（0.45〜1）、なめらか（smootherstep）、
//     ふたは +y の腕の先、組み上がるにつれて中心が原点へ寄る。頂点は ±0.9（辺 1.8）。
//   回し方もウェブ版と同じ：左をドラッグ＝左の X-Z・Y-Z ＝ 右の X-W・Y-W（いっしょに回る）、⇧＋横ドラッグ＝Z-W、右をドラッグ＝右の 3D の回転（X-Z・Y-Z）。
//     超立方体は X-W → Y-W → Z-W → X-Y → X-Z → Y-Z の順に回し、w を遠近（D＝4.5、±(D − 0.5) ではさむ）で 3D へ写す。
//   色もウェブ版：立方体は中央とふた＝z の濃い青、±y 緑、±x ローズ。超立方体は中央とふた＝w の紫、±y 緑、±x ローズ、±z 水色。
//     面は展開図ほど濃く（紙の展開図）、組み上がると透ける。辺は手前が白く奥ほど暗い。手前の頂点はマゼンタ、奥は水色の目印
import SwiftUI
import MetalKit

final class OrigamiState: ObservableObject {
    @Published var progress = 1.0            // 組み立て（0 展開図・1 組み上がり）
    @Published var playing = false           // 折る・開くの途中
    var target = 1.0
    @Published var ax = 0.0                   // 左 X-Z ／ 右 X-W
    @Published var ay = 0.0                   // 左 Y-Z ／ 右 Y-W
    @Published var zw = 0.0                   // Z-W
    @Published var xy = 0.0                   // 3D の回転（右の超立方体。左は X-Y だけ＝ウェブ版の標準）
    @Published var xz = 0.55
    @Published var yz = -0.4
    @Published var spinW = false
    @Published var spin3 = false
    @Published var camW = 4.5
    @Published var look = 0
    // ---- 光と質感（ウェブ版の visual-fx：照り返しライト・グレア・鮮やかさ、shadeFace の奥・内側の濃さ）----
    @Published var shine = true              // 照り返しライト
    @Published var shineK = 1.0              // 照り返しの強さ（0〜4）
    @Published var shineSpread = 0.0         // 照りの広さ（−1 鋭く小さく・0 今まで・1 広くやわらか）
    @Published var shineAz = -30.0           // 主光の向き：カメラから見た左右（度）
    @Published var shineEl = 33.0            // 上下（度）
    @Published var glare = 0.35              // グレア
    @Published var vivid = 0.0               // 鮮やかさ
    @Published var envK = 0.35               // 映り込み（スタジオの空と照明）
    @Published var deep = 0.5                // 奥の胞ほど濃く・深い色に
    @Published var inner = 0.5               // 入れ子の内側の面ほど濃く
    /// 照り返しライトの時のざらつきの倍率（visual-fx の shineRough：今までの 0.8 倍、広さで −85%〜0.7 まで）
    func roughMul(_ r0: Double) -> Double {
        let b = r0 * 0.8, s = shineSpread
        return (s < 0 ? b * (1 + 0.85 * s) : b + (max(b, 0.7) - b) * s) / r0
    }
    /// 色を濃く（彩度を上げて少し暗く。visual-fx の deepen）
    static func deepen(_ c: SIMD3<Float>, _ t: Double) -> SIMD3<Float> {
        guard t > 0 else { return c }
        let Y = simd_dot(c, SIMD3(0.299, 0.587, 0.114)), sat = Float(1 + t), dk = Float(max(0.18, 1 - 0.45 * t))
        return simd_clamp((SIMD3(repeating: Y) + (c - Y) * sat) * dk, .zero, SIMD3(repeating: 1))
    }
    var zoom = [1.0, 1.0], dist = [9.0, 9.0], center = [SIMD2<Double>(0, 0), SIMD2<Double>(0, 0)]   // 見る所（形の真ん中へなめらかに寄る）
    static let half = 0.9

    func reset() { ax = 0; ay = 0; zw = 0; xy = 0; xz = 0; yz = 0; zoom = [1, 1] }

    // ---- 分解（くっついた ⇔ バラバラ。ウェブ版の applyExplode・xpCellE・数える）----
    @Published var explodeRaw = 0.0          // スライダー（0 くっついた・1 全部バラバラ）
    @Published var xpStagger = true          // 時間差（1 個ずつ順に）
    @Published var xpDistK = 1.0             // 離す距離の倍率
    var xpAnim: (from: Double, to: Double, t: Double, total: Double)? = nil
    static let XP_DUR = 0.72, XP_STAG = 0.05, XP_FLASH = 0.35
    var labels: [[SIMD3<Double>]] = [[], []]  // 番号の札の位置（離したあとの胞の中心。左・右）
    var xpStag: Double { xpStagger ? Self.XP_STAG : 0 }
    static func easeOutBack(_ u: Double, _ k: Double = 1.7) -> Double { 1 + (k + 1) * pow(u - 1, 3) + k * pow(u - 1, 2) }
    static func easeInBack(_ u: Double, _ k: Double = 1.4) -> Double { (k + 1) * u * u * u - k * u * u }
    /// 全体の進み（札の濃さ・ボタンの向き）
    var explodeE: Double { if let a = xpAnim { return a.from + (a.to - a.from) * Self.smoother(min(1, a.t / a.total)) }; return Self.smoother(explodeRaw) }
    /// 胞 i の今の離し具合（アニメ中は胞ごとに時間差・バラす時は行き過ぎ、くっつける時は一度ためてから吸いつく）
    func xpCellE(_ i: Int) -> Double {
        guard let a = xpAnim else { return Self.smoother(explodeRaw) }
        let u = max(0, min(1, (a.t - Double(max(0, i - 1)) * xpStag) / Self.XP_DUR))
        return a.from + (a.to - a.from) * (a.to > a.from ? Self.easeOutBack(u) : Self.easeInBack(u))
    }
    /// くっついた瞬間の光（0〜1）。中心は最後の胞が吸いついた時に
    func xpFlash(_ i: Int, _ n: Int) -> Double {
        guard let a = xpAnim, a.to == 0 else { return 0 }
        let arrive = Double(i == 0 ? n - 2 : i - 1) * xpStag + Self.XP_DUR, dt = a.t - arrive
        return dt >= 0 && dt < Self.XP_FLASH ? 1 - dt / Self.XP_FLASH : 0
    }
    func startXp(_ to: Double) {
        let from = explodeE
        if abs(from - to) < 1e-4 { xpAnim = nil; explodeRaw = to; return }
        xpAnim = (from, to, 0, Self.XP_DUR + 6 * xpStag + (to == 0 ? Self.XP_FLASH : 0))
    }
    var apart: Bool { if let a = xpAnim { return a.to == 1 }; return explodeRaw >= 0.5 }
    // 数える：まずバラして、番号の順に 1 個ずつ光らせる（まだの胞はうっすら、今の胞は濃く）
    @Published var counting = false
    @Published var countIdx = -1
    var countPhase = 0, countT = 0.0          // 0 バラしている・1 1 個ずつ・2 数え終わった
    static let XP_STEP = 0.85
    func startCount() { counting = true; countPhase = 0; countIdx = -1; countT = 0; startXp(1) }
    func endCount() { counting = false; countIdx = -1 }
    /// 胞の面・辺の強さ（くっついた瞬間の光・数えている時）
    func cellFocus(_ i: Int, _ n: Int) -> (face: Double, edge: Double) {
        let fl = xpFlash(i, n)
        if fl > 0 { return (1 + 0.4 * fl, 1 + 1.8 * fl) }
        guard counting, countPhase == 1, countIdx < n else { return (1, 1) }
        return i > countIdx ? (0.12, 0.16) : i == countIdx ? (1.7, 1.3) : (1, 1)
    }
    /// 離す量（3D）。組み上がり：外向きへ（新しい次元の向きは斜めへ逃がす）、展開図：中心からの距離に比例して広げる。途中は折り具合で混ぜる
    func explodeOffsets(_ CV: [[SIMD3<Double>]], _ n: Int) -> [SIMD3<Double>] {
        let S = 1.8, DF = 2.2 * xpDistK, GN = 1.2 * xpDistK, last = CV.count - 1
        let m = Self.smoother(max(0, min(1, progress)))
        let ctr = CV.map { vs in vs.reduce(SIMD3<Double>(0, 0, 0), +) / Double(vs.count) }, c0 = ctr[0]
        let rad = CV.indices.map { i in CV[i].map { simd_distance($0, ctr[i]) }.max() ?? 0 }
        return CV.indices.map { i in
            let e = i == 0 ? 0 : xpCellE(i)
            guard e != 0 else { return .zero }
            let fo = m > 0 ? foldedOffset(i, n, i == last ? DF * e * 1.35 : DF * e) : .zero
            var no = SIMD3<Double>(0, 0, 0)
            if m < 1 {
                let rel = ctr[i] - c0, len = simd_length(rel), far = 1.0 - 0.25 * max(0, len / S - 1)
                no = len > 0.6 * S ? rel * (GN * e / S * far) : foldedOffset(i, n, e * (rad[i] + rad[0] + GN))
            }
            return no * (1 - m) + fo * m
        }
    }
    /// 組み上がりの離す向き（胞の外向き。x・y はそのまま、z は (0.55, 0.42, 1)×1.25、新しい次元は (0.75, −0.75, −0.3)×1.4）を、形と同じに回す
    func foldedOffset(_ i: Int, _ n: Int, _ d: Double) -> SIMD3<Double> {
        let EZ = simd_normalize(SIMD3<Double>(0.55, 0.42, 1)) * 1.25, EF = simd_normalize(SIMD3<Double>(0.75, -0.75, -0.3)) * 1.4
        var q = [Double](repeating: 0, count: n)
        switch Self.cells(n)[i] { case .center: q[n - 1] = -1; case .cap: q[n - 1] = 1; case .arm(let a, let s): q[a] = s }
        var o: SIMD3<Double>
        if n == 3 {
            Self.rot(&q, 0, 2, ax); Self.rot(&q, 1, 2, ay)
            o = SIMD3(1, 0, 0) * q[0] + SIMD3(0, 1, 0) * q[1] + EF * q[2]
            var v = [o.x * d, o.y * d, o.z * d]; Self.rot(&v, 0, 1, xy); return SIMD3(v[0], v[1], v[2])   // 左は X-Y だけ
        }
        Self.rot(&q, 0, 3, ax); Self.rot(&q, 1, 3, ay); Self.rot(&q, 2, 3, zw)
        o = SIMD3(1, 0, 0) * q[0] + SIMD3(0, 1, 0) * q[1] + EZ * q[2] + EF * q[3]
        var v = [o.x * d, o.y * d, o.z * d]; Self.rot(&v, 0, 1, xy); Self.rot(&v, 0, 2, xz); Self.rot(&v, 1, 2, yz)
        return SIMD3(v[0], v[1], v[2])
    }
    static let shortNames = [["−Z（中心）", "+Y", "−Y", "+X", "−X", "+Z（蓋）"], ["−W（中心）", "+Y", "−Y", "+X", "−X", "+Z", "−Z", "+W（蓋）"]]
    static let longNames = [["中央面", "上面", "下面", "右面", "左面", "最上蓋"], ["中央固定核胞", "上ヒンジ胞", "下ヒンジ胞", "右ヒンジ胞", "左ヒンジ胞", "前ヒンジ胞", "後ヒンジ胞", "連鎖頂点胞"]]
    /// 組み立てる・開く（今の向きの逆へ。ウェブ版の ▶）
    func toggleFold() { target = progress > 0.5 ? 0 : 1; playing = true }
    func tick(_ dt: Double) {
        if playing {
            let sp = dt / 2.4, d = target - progress
            if abs(d) <= sp { progress = target; playing = false } else { progress += d > 0 ? sp : -sp }
        }
        if var x = xpAnim { x.t += dt; if x.t >= x.total { explodeRaw = x.to; xpAnim = nil } else { xpAnim = x; objectWillChange.send() } }
        if counting {
            if countPhase == 0 { if xpAnim == nil && explodeRaw >= 1 { countPhase = 1; countT = Self.XP_STEP } }
            else {
                countT += dt
                if countPhase == 1 && countT >= Self.XP_STEP { countT = 0; countIdx += 1; if countIdx >= 8 { countPhase = 2 } }
                else if countPhase == 2 && countT > 3 { endCount() }
            }
        }
        if spinW { ax += 0.45 * dt; ay += 0.3 * dt }
        if spin3 { xz += 0.4 * dt; yz += 0.25 * dt }
    }

    // ---- 折りたたみ（nd-geom の foldAngles・foldPoint と同じ式）----
    static func smoother(_ t: Double) -> Double { let c = max(0, min(1, t)); return c * c * c * (c * (c * 6 - 15) + 10) }
    func foldAngles() -> (arm: Double, cap: Double) {
        (Self.smoother(min(1, progress / 0.60)) * .pi / 2, Self.smoother(max(0, (progress - 0.45) / 0.55)) * .pi / 2)
    }
    enum Cell { case center, arm(Int, Double), cap }
    /// 胞の並び（ウェブ版の NET3_CELLS・NET4_CELLS）：真ん中・+y・−y・+x・−x・（+z・−z）・ふた
    static func cells(_ n: Int) -> [Cell] {
        var c: [Cell] = [.center, .arm(1, 1), .arm(1, -1), .arm(0, 1), .arm(0, -1)]
        if n == 4 { c += [.arm(2, 1), .arm(2, -1)] }
        return c + [.cap]
    }
    /// 組み上がりの位置 p（±1）の点を、今の折り具合の位置へ（×0.9）
    func fold(_ cell: Cell, _ p: [Double], _ n: Int) -> [Double] {
        let N = n - 1, (arm, cap) = foldAngles()
        var o = p
        switch cell {
        case .arm(let a, let s):
            let d = p[N] + 1; o[a] = s * (1 + d * cos(arm)); o[N] = -1 + d * sin(arm)
        case .cap:
            let c = 1, g = arm + cap, e = 1 - p[c]
            o[c] = 1 + 2 * cos(arm) + e * cos(g); o[N] = -1 + 2 * sin(arm) + e * sin(g)
        case .center: break
        }
        o[N] += 1 - arm / (.pi / 2)                                      // 真ん中を原点へ（展開図では真ん中の胞が 0、組み上がりで中心が 0）
        return o.map { $0 * Self.half }
    }
    /// 胞の決まった軸と値（真ん中は軸 N の −1、ふたは ＋1、腕は軸 a の s）
    static func fixed(_ cell: Cell, _ n: Int) -> (Int, Double) {
        switch cell { case .center: return (n - 1, -1); case .cap: return (n - 1, 1); case .arm(let a, let s): return (a, s) }
    }
    // ---- 回して写す ----
    static func rot(_ v: inout [Double], _ i: Int, _ j: Int, _ a: Double) {
        guard a != 0 else { return }
        let c = cos(a), s = sin(a), t = v[i] * c - v[j] * s; v[j] = v[i] * s + v[j] * c; v[i] = t
    }
    /// 3 次元（左の立方体）：X-Z → Y-Z →（Z-W の遠近）→ X-Y。返り値は見かけの縮み
    func place3(_ p: [Double]) -> (SIMD3<Double>, Double) {
        var v = p
        Self.rot(&v, 0, 2, ax); Self.rot(&v, 1, 2, ay)
        var k = 1.0
        if zw != 0 {                                                     // Z-W：z の分が 4 次元へ逃げ、右と同じ遠近で縮む
            let w = v[2] * sin(zw), D = camW, wc = max(-D + 0.5, min(D - 0.5, w)); k = 1 / (1 - wc / D)
            v[0] *= k; v[1] *= k; v[2] = v[2] * cos(zw) * k
        }
        Self.rot(&v, 0, 1, xy)
        return (SIMD3(v[0], v[1], v[2]), k)
    }
    /// 4 次元（右の超立方体）：X-W → Y-W → Z-W → X-Y → X-Z → Y-Z、w を遠近で
    func place4(_ p: [Double]) -> (SIMD3<Double>, Double) {
        var v = p
        for (i, j, a) in [(0, 3, ax), (1, 3, ay), (2, 3, zw), (0, 1, xy), (0, 2, xz), (1, 2, yz)] { Self.rot(&v, i, j, a) }
        let D = camW, w = max(-D + 0.5, min(D - 0.5, v[3])), k = 1 / (1 - w / D)
        return (SIMD3(v[0] * k, v[1] * k, v[2] * k), k)
    }
    func place(_ p: [Double], _ n: Int) -> (SIMD3<Double>, Double) { n == 3 ? place3(p) : place4(p) }

    static let faceCol3: [UInt32] = [0x0284c7, 0x10b981, 0x10b981, 0xf43f5e, 0xf43f5e, 0x0284c7]
    static let cellCol4: [UInt32] = [0x9333ea, 0x10b981, 0x10b981, 0xf43f5e, 0xf43f5e, 0x38bdf8, 0x38bdf8, 0x9333ea]
    static func rgb(_ h: UInt32) -> SIMD3<Float> { SIMD3(Float((h >> 16) & 255) / 255, Float((h >> 8) & 255) / 255, Float(h & 255) / 255) }
}

/// 景色の座標（ウェブ版は y が上）を、描く側（z が上）へ
@inline(__always) private func gpu(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

final class OrigamiRenderer: NSObject, MTKViewDelegate {
    let n: Int, st: OrigamiState
    let device: MTLDevice, queue: MTLCommandQueue
    private var pipe: MTLRenderPipelineState!
    private var lastT = CACurrentMediaTime()

    init?(n: Int, state: OrigamiState, view: MTKView) {
        guard let d = MTLCreateSystemDefaultDevice(), let q = d.makeCommandQueue() else { return nil }
        self.n = n; st = state; device = d; queue = q
        super.init()
        view.device = d; view.colorPixelFormat = .bgra8Unorm; view.preferredFramesPerSecond = 60
        let lib = try! d.makeLibrary(source: tlShader, options: nil)
        let p = MTLRenderPipelineDescriptor()
        p.vertexFunction = lib.makeFunction(name: "tlv"); p.fragmentFunction = lib.makeFunction(name: "tlf"); p.colorAttachments[0].pixelFormat = .bgra8Unorm
        pipe = try! d.makeRenderPipelineState(descriptor: p)
    }
    /// 面（板）・辺（線）・目印の頂点を作る。eye：カメラの位置（景色の座標）。分解（バラす）もここで（ウェブ版の applyExplode）
    func geometry(eye: SIMD3<Double>) -> ([TLQuad], [TLRod], [TLBall], Double, SIMD2<Double>) {
        let cells = OrigamiState.cells(n), di = n == 3 ? 0 : 1
        var quads: [TLQuad] = [], rods: [TLRod] = [], balls: [TLBall] = []
        var segs: [(SIMD3<Double>, SIMD3<Double>, Int)] = [], rMax = 0.0, lo = SIMD2<Double>(1e9, 1e9), hi = SIMD2<Double>(-1e9, -1e9)
        // 1. 胞ごとの頂点（折って・回して・写した 3D）
        var CV: [[SIMD3<Double>]] = [], FREE: [[Int]] = [], KV: [[Double]] = []
        for cell in cells {
            let (fa, fv) = OrigamiState.fixed(cell, n), free = (0..<n).filter { $0 != fa }
            let pk = (0..<(1 << free.count)).map { bits -> (SIMD3<Double>, Double) in
                var p = [Double](repeating: 0, count: n); p[fa] = fv
                for (k, ax) in free.enumerated() { p[ax] = bits & (1 << k) != 0 ? 1 : -1 }
                return st.place(st.fold(cell, p, n), n)
            }
            CV.append(pk.map(\.0)); KV.append(pk.map(\.1)); FREE.append(free)
        }
        // 2. 分解：胞を離す（中心の胞は動かない）
        let off = st.explodeOffsets(CV, n)
        for i in CV.indices { for k in CV[i].indices { CV[i][k] += off[i] } }
        st.labels[di] = CV.map { vs in vs.reduce(SIMD3<Double>(0, 0, 0), +) / Double(vs.count) }   // 番号の札の位置（離したあとの胞の中心）
        // 面の濃さ：展開図ほど濃く（ウェブ版の netOpacity：0.30 → 0.85）
        let pr = st.progress, mix = pow(1 - max(0, min(1, pr)), 1.5), base = 0.24, alpha0 = min(0.97, base + (max(base, 0.85) - base) * mix)
        // 奥・内側（visual-fx の cellDepth・innerAmount・shadeFace）：超立方体は 4D の遠近の縮み K（大きいほど手前）、立方体はカメラからの距離で。
        //   奥の胞ほど色を深く・濃く、手前の胞は薄く＝奥の濃い色が手前を透かして見える（組み上がった形の色が、重なり方から自然に決まる）
        var depthOf: [Double] = []
        for ci in CV.indices {
            if n == 4 { let s: Double = KV[ci].reduce(0, +); depthOf.append(-s / Double(KV[ci].count)) }
            else { var s = 0.0; for p in CV[ci] { s += simd_distance(p, eye) }; depthOf.append(s / Double(CV[ci].count)) }
        }
        let dLo = depthOf.min() ?? 0, dSp = max((depthOf.max() ?? 1) - dLo, 1e-6)
        let kD = 2 * st.deep, kI = 3.75 * st.inner
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        for (ci, P) in CV.enumerated() {
            let col0 = OrigamiState.rgb(n == 3 ? OrigamiState.faceCol3[ci] : OrigamiState.cellCol4[ci])
            let deepC = (depthOf[ci] - dLo) / dSp
            let foc = st.cellFocus(ci, cells.count)
            // 胞の中の面の縮み（入れ子の内側ぐあい）
            var faceKs: [Double]? = nil
            if n == 4 {
                var ks: [Double] = []
                for fi in 0..<6 {
                    let f = fi / 2, sv = fi % 2; var s = 0.0
                    for b in 0..<8 where (b >> f) & 1 == sv { s += KV[ci][b] }
                    ks.append(s / 4)
                }
                faceKs = ks
            }
            let fkLo = faceKs?.min() ?? 0, fkHi = faceKs?.max() ?? 0
            func shade(_ fi: Int) -> (SIMD3<Float>, Float) {
                var inn = 0.0
                if let ks = faceKs { inn = (fkHi - ks[fi]) / max(fkHi - fkLo, 1e-6) }
                let tIn: Double = kI * sm(inn)
                let c = OrigamiState.deepen(OrigamiState.deepen(col0, kD * sm(deepC) * 0.8), tIn)
                // 濃さは控えめに変える（手前 0.75 倍〜奥 1.3 倍、内側は 1.5 倍まで）。奥・内側は主に色の深さで見せる（暗い背景が透けて見えるガラスのまま）
                let dens: Double = max(0.3, 1 - 0.25 * kD + 0.55 * kD * deepC)
                let a: Double = min(0.9, alpha0 * dens * (1 + 0.27 * tIn) * foc.face)
                return (c, Float(a))
            }
            for p in P { lo = simd_min(lo, SIMD2(p.x, p.y)); hi = simd_max(hi, SIMD2(p.x, p.y)) }
            let nb = FREE[ci].count
            // 面：自由な軸のうち 2 本で張る正方形（立方体の胞は 6 枚、正方形の面は 1 枚）
            for f in (nb == 3 ? [0, 1, 2] : [-1]) {
                for fsv in (f < 0 ? [0] : [0, 1]) {
                    let (col, alpha) = shade(f < 0 ? 0 : f * 2 + fsv)
                    let span = (0..<nb).filter { $0 != f }
                    let b0 = f < 0 ? 0 : fsv << f
                    let idx = [b0, b0 | (1 << span[0]), b0 | (1 << span[0]) | (1 << span[1]), b0 | (1 << span[1])]
                    let Q = idx.map { gpu(P[$0]) }
                    var nn = simd_cross(Q[1] - Q[0], Q[3] - Q[0]); let l = simd_length(nn); if l < 1e-7 { continue }; nn /= l
                    quads.append(TLQuad(a: SIMD4(Q[0], 0), b: SIMD4(Q[1], 0), c: SIMD4(Q[2], 0), d: SIMD4(Q[3], 0), n: SIMD4(nn, simd_dot(nn, Q[0])), col: SIMD4(col, 0), m: SIMD4(alpha, 0, 0, 0)))
                }
            }
            // 辺：1 本の軸だけ違う頂点の組
            for a in 0..<(1 << nb) { for k in 0..<nb where a & (1 << k) == 0 { segs.append((P[a], P[a | (1 << k)], ci)) } }
        }
        let c = (lo + hi) / 2
        for (a, b, _) in segs { for p in [a, b] { rMax = max(rMax, simd_length(SIMD2(p.x, p.y) - c) + abs(p.z) * 0.3) } }
        // 辺の色：手前は白く（0.80）、奥ほど暗く（0.17）。カメラからの距離で。数えている・くっついた瞬間は、その胞の辺を強く
        let ds = segs.flatMap { [simd_distance($0.0, eye), simd_distance($0.1, eye)] }
        let dmin = ds.min() ?? 0, dmax = ds.max() ?? 1, sp = max(dmax - dmin, 1e-3)
        func br(_ p: SIMD3<Double>) -> Float { let t = max(0, min(1, (simd_distance(p, eye) - dmin) / sp)), s = t * t * (3 - 2 * t); return Float(0.80 + (0.17 - 0.80) * s) }
        for (a, b, ci) in segs {
            let k = Float(st.cellFocus(ci, cells.count).edge)
            rods.append(TLRod(a: SIMD4(gpu(a), 0.0), b: SIMD4(gpu(b), 0), col: SIMD4(SIMD3<Float>(0.92, 0.95, 1.0), (br(a) + br(b)) / 2 * 0.75 * k)))
        }
        // 目印：手前の頂点（ふたの胞の ＋…＋）はマゼンタ、奥の頂点（真ん中の胞の −…−）は水色。胞と一緒に離れる
        let near = st.place(st.fold(.cap, [Double](repeating: 1, count: n), n), n).0 + off[cells.count - 1]
        let far = st.place(st.fold(.center, [Double](repeating: -1, count: n), n), n).0 + off[0]
        balls.append(TLBall(p: SIMD4(gpu(near), 0.055), col: SIMD4(1.0, 0.267, 0.867, 2)))
        balls.append(TLBall(p: SIMD4(gpu(far), 0.055), col: SIMD4(0.2, 0.898, 1.0, 2)))
        return (quads, rods, balls, rMax, c)
    }
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {
        let now = CACurrentMediaTime(), dt = min(0.05, now - lastT); lastT = now
        if n == 3 { st.tick(dt) }
        guard let rpd = view.currentRenderPassDescriptor, let dr = view.currentDrawable, let cb = queue.makeCommandBuffer(),
              let e = cb.makeRenderCommandEncoder(descriptor: rpd) else { return }
        let i = n == 3 ? 0 : 1
        // カメラ：正面（ウェブ版と同じく、物を回してカメラは回さない）。全体が収まる距離へなめらかに寄る
        let eyeW = SIMD3<Double>(st.center[i].x, st.center[i].y, st.dist[i])
        let (quads, rods, balls, rMax, ctr) = geometry(eye: eyeW)
        let want = max(3.0, rMax * 2.75) / st.zoom[i], k = min(1, dt * 4)
        st.dist[i] += (want - st.dist[i]) * k; st.center[i] += (ctr - st.center[i]) * k
        var u = TLUni()
        u.eye = SIMD4(gpu(eyeW), 0); u.R = SIMD4(1, 0, 0, 0); u.U = SIMD4(0, 0, 1, 0); u.F = SIMD4(0, 1, 0, 0)
        let sz = view.drawableSize
        u.p = SIMD4(Float(tan(22.5 * Double.pi / 180)), Float(sz.width / max(1, sz.height)), 0, 1)
        let L = TessLabState.looks[st.look]
        u.q = SIMD4(Float(quads.count), 0, Float(now.truncatingRemainder(dividingBy: 1000)), 0)
        u.cnt = SIMD4(Float(rods.count), Float(balls.count), Float(2 * tan(22.5 * Double.pi / 180) / max(1, sz.height)), 0.08)   // 細い線（にじみは少し）
        u.L0 = SIMD4(L.base, L.fresA, L.fresP, L.rimK); u.L1 = SIMD4(L.lumT, L.lumK, L.env, L.sat)
        u.L2 = SIMD4(L.lift, L.add ? 1 : 0, 0, 1)                         // 辺は細い線（ウェブ版の 1 画素の線）
        u.rim = SIMD4(L.rim, L.rodEnv); u.L3 = SIMD4(L.soft ? 1 : 0, 1, 0, st.look == 0 ? 1 : 0)   // 質感「次元おりがみ」は three.js と同じ光で
        // 照り返しライト：主光はカメラから見て左右 az・上下 el、見ている点からの距離 D × 0.762。逆光は左右 +168°・上下 ×0.7、D × 0.886（visual-fx の shinePlace）
        let r0 = n == 3 ? 0.2 : 0.15, m0 = n == 3 ? 0.4 : 0.5
        u.S0 = SIMD4(st.shine ? 1 : 0, Float(st.shineK), Float(st.roughMul(r0)), Float(st.glare))
        u.S1 = SIMD4(Float(st.vivid), Float(st.envK), Float(m0), Float(r0))
        func lightAt(_ az: Double, _ el: Double, _ k: Double) -> SIMD4<Float> {
            let a = az * .pi / 180, e = el * .pi / 180, D = st.dist[i] * k
            let T = SIMD3<Double>(st.center[i].x, st.center[i].y, 0)
            return SIMD4(gpu(T + SIMD3(D * cos(e) * sin(a), D * sin(e), D * cos(e) * cos(a))), 0)
        }
        u.S2 = lightAt(st.shineAz, st.shineEl, 0.762); u.S3 = lightAt(st.shineAz + 168, max(-85, min(85, st.shineEl * 0.7)), 0.886)
        var qd = quads.isEmpty ? [TLQuad(a: .zero, b: .zero, c: .zero, d: .zero, n: .zero, col: .zero)] : quads, rd = rods, bl = balls
        guard let qb = device.makeBuffer(bytes: &qd, length: MemoryLayout<TLQuad>.stride * qd.count, options: .storageModeShared),
              let rb = device.makeBuffer(bytes: &rd, length: MemoryLayout<TLRod>.stride * max(1, rd.count), options: .storageModeShared),
              let bb = device.makeBuffer(bytes: &bl, length: MemoryLayout<TLBall>.stride * max(1, bl.count), options: .storageModeShared) else { return }
        e.setRenderPipelineState(pipe)
        e.setFragmentBytes(&u, length: MemoryLayout<TLUni>.stride, index: 0)
        e.setFragmentBuffer(qb, offset: 0, index: 1); e.setFragmentBuffer(rb, offset: 0, index: 2); e.setFragmentBuffer(bb, offset: 0, index: 3)
        e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        e.endEncoding(); cb.present(dr); cb.commit()
    }
}

#if os(macOS)
struct OrigamiPane: NSViewRepresentable {
    let n: Int; let st: OrigamiState
    final class Holder { var r: OrigamiRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeNSView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = OrigamiRenderer(n: n, state: st, view: v); v.delegate = context.coordinator.r; return v }
    func updateNSView(_ v: MTKView, context: Context) {}
}
#else
struct OrigamiPane: UIViewRepresentable {
    let n: Int; let st: OrigamiState
    final class Holder { var r: OrigamiRenderer? }
    func makeCoordinator() -> Holder { Holder() }
    func makeUIView(context: Context) -> MTKView { let v = MTKView(); context.coordinator.r = OrigamiRenderer(n: n, state: st, view: v); v.delegate = context.coordinator.r; return v }
    func updateUIView(_ v: MTKView, context: Context) {}
}
#endif

/// 座標軸（ウェブ版の X/Y/Z/W の軸：長さ 1.8 × 1.35、同じ回転と遠近）と、数式の斜体の名前
struct OrigamiAxes: View {
    let n: Int; @ObservedObject var st: OrigamiState
    var body: some View {
        TimelineView(.animation) { _ in
            Canvas { ctx, size in
                let i = n == 3 ? 0 : 1, dist = st.dist[i], c = st.center[i], tanF = tan(22.5 * Double.pi / 180), asp = Double(size.width / max(1, size.height))
                func scr(_ p: SIMD3<Double>) -> CGPoint? {
                    let z = dist - p.z; guard z > 0.1 else { return nil }
                    return CGPoint(x: ((p.x - c.x) / (z * tanF * asp) * 0.5 + 0.5) * Double(size.width), y: (0.5 - (p.y - c.y) / (z * tanF) * 0.5) * Double(size.height))
                }
                let L = 1.8 * 1.35
                guard let o = scr(n == 3 ? st.place3([0, 0, 0]).0 : st.place4([0, 0, 0, 0]).0) else { return }
                for ax in 0..<n {
                    var e = [Double](repeating: 0, count: n); e[ax] = L
                    guard let b = scr(st.place(e, n).0) else { continue }
                    let col = TessAxes.cols[ax]
                    var line = Path(); line.move(to: o); line.addLine(to: b)
                    ctx.stroke(line, with: .color(col.opacity(0.8)), lineWidth: 1.1)
                    let dx = b.x - o.x, dy = b.y - o.y, l = max(1, hypot(dx, dy)), ux = dx / l, uy = dy / l
                    if l < 6 { ctx.fill(Path(ellipseIn: CGRect(x: o.x - 3, y: o.y - 3, width: 6, height: 6)), with: .color(col)) }   // 0° の w は真ん中の 1 点に（w の方から見ている）
                    else {
                        var head = Path(); head.move(to: CGPoint(x: b.x + ux * 9, y: b.y + uy * 9))
                        head.addLine(to: CGPoint(x: b.x - uy * 5, y: b.y + ux * 5)); head.addLine(to: CGPoint(x: b.x + uy * 5, y: b.y - ux * 5)); head.closeSubpath()
                        ctx.fill(head, with: .color(col))
                    }
                    ctx.draw(Text(TessAxes.names[ax]).font(.custom("KaTeX_Math-Italic", size: 26)).foregroundColor(col), at: CGPoint(x: b.x + ux * 24, y: b.y + uy * 24 - (l < 6 ? 18 : 0)))
                }
            }
        }
    }
}

/// 分解の番号の札（ウェブ版の xp-label：胞の色の丸に番号、横に ±軸の名前）と、数える時の札（「3 / 8 +X（右ヒンジ胞）」）
struct OrigamiLabels: View {
    let n: Int; @ObservedObject var st: OrigamiState
    var pi: Int { n == 3 ? 0 : 1 }
    var body: some View {
        TimelineView(.animation) { _ in
            ZStack(alignment: .top) {
                if st.explodeE > 0.01 || st.counting { Canvas { ctx, size in draw(ctx, size) } }
                badge
            }
        }
    }
    func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        let i = pi, e = st.explodeE, dist = st.dist[i], c = st.center[i]
        let tanF = tan(22.5 * Double.pi / 180), asp = Double(size.width / max(1, size.height))
        let cols = n == 3 ? OrigamiState.faceCol3 : OrigamiState.cellCol4
        for (k, p) in st.labels[i].enumerated() where k < cols.count {
            var op = min(1, e * 1.6), sc = 1.0
            if st.counting && st.countPhase != 0 {
                if st.countPhase == 1 && k > st.countIdx { op = 0 } else { op = 1; if st.countPhase == 1 && k == st.countIdx { sc = 1.3 } }
            }
            let z = dist - p.z
            guard z > 0.1, op > 0 else { continue }
            let x = ((p.x - c.x) / (z * tanF * asp) * 0.5 + 0.5) * Double(size.width)
            let y = (0.5 - (p.y - c.y) / (z * tanF) * 0.5) * Double(size.height)
            drawLabel(ctx, k, CGPoint(x: x, y: y), op, sc, OrigamiState.rgb(cols[k]))
        }
    }
    func drawLabel(_ ctx: GraphicsContext, _ k: Int, _ at: CGPoint, _ op: Double, _ sc: Double, _ rgb: SIMD3<Float>) {
        var g = ctx; g.opacity = op
        let name = OrigamiState.shortNames[pi][k], h: Double = 22 * sc
        let w: Double = h + Double(name.count) * 9 * sc
        let box = CGRect(x: at.x - w / 2, y: at.y - h / 2, width: w, height: h)
        let pill = Path(roundedRect: box, cornerRadius: h / 2)
        g.fill(pill, with: .color(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.88)))
        let ring: Color = sc > 1 ? Color(red: 0.98, green: 0.75, blue: 0.3) : Color(red: 0.2, green: 0.25, blue: 0.33)
        g.stroke(pill, with: .color(ring), lineWidth: sc > 1 ? 2 : 1)
        let cr = CGRect(x: box.minX + 3, y: box.minY + 3, width: h - 6, height: h - 6)
        g.fill(Path(ellipseIn: cr), with: .color(Color(red: Double(rgb.x), green: Double(rgb.y), blue: Double(rgb.z))))
        g.draw(Text("\(k + 1)").font(.system(size: 10 * sc, weight: .bold)).foregroundColor(.white), at: CGPoint(x: cr.midX, y: cr.midY))
        g.draw(Text(name).font(.system(size: 11 * sc, weight: .semibold)).foregroundColor(.white), at: CGPoint(x: cr.maxX + (w - h) / 2 + 2, y: at.y))
    }
    /// 数える時の札：今の番号と名前、数え終わったら全部の数
    @ViewBuilder var badge: some View {
        if st.counting && st.countPhase != 0 && st.countIdx >= 0 {
            let cnt = n == 3 ? 6 : 8
            let done = st.countIdx >= cnt || st.countPhase == 2
            let text = done ? "全部で \(cnt)\(n == 3 ? "枚の正方形" : "個の立方体")"
                            : "\(st.countIdx + 1) / \(cnt)　\(OrigamiState.shortNames[pi][st.countIdx])（\(OrigamiState.longNames[pi][st.countIdx])）"
            Text(text)
                .font(.system(size: 15, weight: .bold)).foregroundStyle(Color(red: 1.0, green: 0.9, blue: 0.6))
                .padding(.horizontal, 14).padding(.vertical, 6)
                .background(Color(red: 0.25, green: 0.16, blue: 0.04).opacity(0.85), in: Capsule())
                .overlay(Capsule().stroke(Color(red: 0.98, green: 0.75, blue: 0.3).opacity(0.7)))
                .padding(.top, 70)
        }
    }
}

struct OrigamiView: View {
    @StateObject private var st = OrigamiState()
    @State private var last: CGSize = .zero
    @State private var pinch0: Double? = nil
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1) {
                pane(3, "左：2D 展開図 → 立方体", "折りたたみでできる新しい次元＝z。そこへ倒すと、影が重なって見える")
                pane(4, "右：3D 展開図 → 超立方体", "折りたたみでできる新しい次元＝w。そこへ倒すと、ただ立方体が回る")
            }
            .background(Color(red: 0.12, green: 0.16, blue: 0.23))
            controls
        }
        .background(Color(red: 3 / 255, green: 7 / 255, blue: 18 / 255))
        .preferredColorScheme(.dark)
    }
    func pane(_ n: Int, _ title: String, _ sub: String) -> some View {
        let i = n == 3 ? 0 : 1
        return ZStack(alignment: .top) {
            OrigamiPane(n: n, st: st)
                .gesture(DragGesture(minimumDistance: 1).onChanged { g in
                    let dd = CGSize(width: g.translation.width - last.width, height: g.translation.height - last.height); last = g.translation
                    #if os(macOS)
                    let shift = NSEvent.modifierFlags.contains(.shift)
                    #else
                    let shift = false
                    #endif
                    if shift { st.zw += Double(dd.width) * 0.01 }
                    else if n == 3 { st.ax += Double(dd.width) * 0.01; st.ay += Double(dd.height) * 0.01 }   // 左：X-W・Y-W（左は X-Z・Y-Z）
                    else { st.xz += Double(dd.width) * 0.01; st.yz += Double(dd.height) * 0.01 }            // 右：3D の回転
                }.onEnded { _ in last = .zero })
                .simultaneousGesture(MagnificationGesture().onChanged { k in
                    if pinch0 == nil { pinch0 = st.zoom[i] }
                    st.zoom[i] = max(0.3, min(5, pinch0! * Double(k)))
                }.onEnded { _ in pinch0 = nil })
            OrigamiAxes(n: n, st: st).allowsHitTesting(false)
            OrigamiLabels(n: n, st: st).allowsHitTesting(false)
            // 見出し（ウェブ版と同じ形の札）
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(sub).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.9), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color(red: 0.2, green: 0.25, blue: 0.33)))
            .padding(10).allowsHitTesting(false)
        }
        .clipped()
    }
    var controls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button(st.playing ? "■ 止める" : (st.progress > 0.5 ? "▶ 開く（展開図へ）" : "▶ 組み立てる")) { if st.playing { st.playing = false } else { st.toggleFold() } }
                Toggle("W 回転", isOn: $st.spinW).toggleStyle(.button)
                Toggle("3D 回転", isOn: $st.spin3).toggleStyle(.button)
                Button("初期位置") { st.reset() }
                Picker("質感", selection: $st.look) { ForEach(TessLabState.looks.indices, id: \.self) { Text(TessLabState.looks[$0].name).tag($0) } }.frame(width: 170)
                Spacer()
                Text("次元おりがみのネイティブ版（移植の第 1 歩）").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                Text("分解").font(.caption.bold()).foregroundStyle(Color(red: 0.98, green: 0.75, blue: 0.3))
                Text("くっついた").font(.caption2).foregroundStyle(.secondary)
                Slider(value: Binding(get: { st.xpAnim != nil ? max(0, min(1, st.explodeE)) : st.explodeRaw }, set: { st.xpAnim = nil; if st.counting { st.endCount() }; st.explodeRaw = $0 }), in: 0...1).frame(width: 160)
                Text("バラバラ").font(.caption2).foregroundStyle(.secondary)
                Text(String(format: "%.0f%%", (st.xpAnim != nil ? st.explodeE : st.explodeRaw) * 100)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 36)
                Button(st.apart ? "→ くっつける" : "→ バラす") { if st.counting { st.endCount() }; st.startXp(st.apart ? 0 : 1) }
                    .help("1 つずつの形に分けて離す／元にくっつける")
                Button(st.counting ? "→ やめる" : "→ 数える") { if st.counting { st.endCount() } else { st.startCount() } }
                    .help("バラして、1 個ずつ番号を付けて光らせながら数える")
                Toggle("時間差", isOn: $st.xpStagger).help("1 個ずつ順に動かす（オフなら全部いっしょに）")
                Text("離す距離").font(.caption2).foregroundStyle(.secondary)
                Slider(value: $st.xpDistK, in: 0.3...2.5).frame(width: 110)
                Text(String(format: "×%.1f", st.xpDistK)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                Spacer()
            }
            HStack(spacing: 8) {
                Text("光").font(.caption.bold()).foregroundStyle(Color(red: 0.73, green: 0.9, blue: 0.99))
                Toggle("照り返しライト", isOn: $st.shine)
                mini("強さ", $st.shineK, 0, 4, "%.1f"); mini("広さ", $st.shineSpread, -1, 1, "%+.1f")
                mini("左右", $st.shineAz, -180, 180, "%+.0f°"); mini("上下", $st.shineEl, -85, 85, "%+.0f°")
                mini("グレア", $st.glare, 0, 1, "%.2f"); mini("鮮やかさ", $st.vivid, 0, 1, "%.2f"); mini("映り込み", $st.envK, 0, 1.5, "%.2f")
                mini("奥の濃さ", $st.deep, 0, 1, "%.2f"); mini("内側の濃さ", $st.inner, 0, 1, "%.2f")
                Spacer()
            }
            HStack(spacing: 12) {
                slider("組み立て", $st.progress, 0, 1, "%.2f")
                slider("X-W（左 X-Z）", deg($st.ax), -180, 180)
                slider("Y-W（左 Y-Z）", deg($st.ay), -180, 180)
                slider("Z-W", deg($st.zw), -180, 180)
                slider("X-Y", deg($st.xy), -180, 180)
                slider("X-Z", deg($st.xz), -180, 180)
                slider("Y-Z", deg($st.yz), -180, 180)
                slider("4D の遠近", $st.camW, 2.5, 20, "%.1f")
            }
        }
        .padding(10).background(Color(red: 0.04, green: 0.06, blue: 0.11)).controlSize(.small)
    }
    func mini(_ name: String, _ v: Binding<Double>, _ lo: Double, _ hi: Double, _ fmt: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 3) { Text(name).font(.caption2); Text(String(format: fmt, v.wrappedValue)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: v, in: lo...hi).frame(width: 84)
        }
    }
    func deg(_ b: Binding<Double>) -> Binding<Double> {
        Binding(get: { var x = (b.wrappedValue * 180 / .pi + 180).truncatingRemainder(dividingBy: 360); if x < 0 { x += 360 }; return x - 180 }, set: { b.wrappedValue = $0 * .pi / 180 })
    }
    func slider(_ name: String, _ v: Binding<Double>, _ lo: Double, _ hi: Double, _ fmt: String = "%+.0f°") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text(name).font(.caption); Spacer(); Text(String(format: fmt, v.wrappedValue)).font(.caption.monospacedDigit()).foregroundStyle(.secondary) }
            Slider(value: v, in: lo...hi)
        }
    }
}
