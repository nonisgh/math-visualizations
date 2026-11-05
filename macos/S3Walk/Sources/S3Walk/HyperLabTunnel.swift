import Foundation
import simd
import Metal
import QuartzCore

// トンネル（超球ラン）：超球を、自分の通る道を含む 4D の断面（自分の上下・前後・左右の 3 つの向き。残りの 1 つの向きは 0）で見る。
//   この断面では、入れ子の S³（ステージの殻）がそのまま入れ子の球になる。殻と殻のすき間がトンネル（外の殻が天井、内の殻が床）。
//   本当の 4D の切り口なので、中心へ向かう向きがそのまま画面の下になる

/// 殻にあく穴：殻の半径 r・穴の真ん中の向き（S³ の点）・開きぐあい（0〜1）・何回り目の穴か
struct TunnelHole { var r: Double; var dir: SIMD4<Double>; var open = 0.0; var gen = 0 }

/// 超球ランの 1 回り：表面すれすれ → 穴から 1 枚下のすき間へ → すき間を飛ぶ → … → 中心の炉へ急降下 → 反対側へまっすぐ脱出 → 表面すれすれ
final class HyperRun {
    struct Sample { var p: SIMD4<Double>; var l: SIMD4<Double>; var rho: Double; var flips: Int }
    static let V = 0.8                                                // 前へ進む速さ（R ＝ 1 の半径を 1 として、毎秒）
    static let top = 1.06                                             // 表面すれすれの高さ（外の殻のすぐ外）
    static let hz = 240.0                                             // 道を作るこまかさ（1 秒に何点）
    static let coreSpeed = 1.2                                        // 中心を抜ける速さ
    private(set) var samples: [Sample] = []
    private(set) var holes: [(r: Double, dir: SIMD4<Double>)] = []
    private(set) var flipT: [Double] = []                             // 中心を抜けた時刻
    var length: Double { Double(max(0, samples.count - 1)) / Self.hz }
    enum Phase { case skim(Double), drop(Double, Double), plunge(Double), escape(Double) }
    /// 1 回りの段取り（秒）。すき間はステージの殻のまん中
    static var phases: [(Phase, Double)] {
        let st = HyperLabState.stageR, gaps = zip(st, st.dropFirst()).map { ($0 + $1) / 2 }
        var ph: [(Phase, Double)] = [(.skim(top), 4)]
        var cur = top
        for (i, g) in gaps.enumerated() { ph += [(.drop(cur, g), 1.4), (.skim(g), i < 2 ? 3 : 2.5)]; cur = g }
        ph += [(.plunge(cur), 2 * cur / coreSpeed), (.escape(top), 2 * top / coreSpeed)]
        return ph
    }
    /// 出発の点 p0・前の向き l0 から、1 回り分の道を作る（同じ出発なら、いつも同じ道）
    func build(p0: SIMD4<Double>, l0: SIMD4<Double>) {
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        var p = simd_normalize(p0), l = l0 - p * simd_dot(l0, p); l = simd_normalize(l)
        var flips = 0, prevRho = Self.top
        samples = [Sample(p: p, l: l, rho: Self.top, flips: 0)]; holes = []; flipT = []
        let dt = 1 / Self.hz, stage = HyperLabState.stageR
        var t0 = 0.0
        for (ph, dur) in Self.phases {
            let n = max(1, Int((dur * Self.hz).rounded()))
            for i in 1...n {
                let x = Double(i) / Double(n)
                var rho: Double, vf: Double
                switch ph {
                case .skim(let r): rho = r; vf = Self.V
                case .drop(let a, let b): rho = a + (b - a) * sm(x); vf = Self.V
                case .plunge(let a): rho = a * (1 - x * x); vf = Self.V * (1 - sm(x / 0.4))      // 前へ進むのをやめて、まっすぐ中心へ
                case .escape(let e): rho = e * (1 - (1 - x) * (1 - x)); vf = Self.V * sm((x - 0.55) / 0.45)   // まっすぐ外へ、最後に前へ向きを変える
                }
                if case .escape = ph, i == 1 { p = -p; flips += 1; flipT.append(t0) }      // 中心を抜けた：反対側の点へ（さんぽの体も 180° 宙返り）
                let a = vf * dt / max(rho, 0.05), ca = cos(a), sa = sin(a)
                let np = p * ca + l * sa; l = l * ca - p * sa; p = simd_normalize(np); l = simd_normalize(l - p * simd_dot(l, p))
                for r in stage {                                     // 殻を通る所に穴（降りる時は上から、脱出は下から）
                    if (prevRho > r && rho <= r) || (prevRho < r && rho >= r) { holes.append((r, p)) }
                }
                prevRho = rho
                samples.append(Sample(p: p, l: l, rho: rho, flips: flips))
            }
            t0 += Double(n) / Self.hz
        }
    }
    /// t 秒の所（間はなめらかに）
    func at(_ t: Double) -> Sample {
        guard !samples.isEmpty else { return Sample(p: SIMD4(0, 0, 0, 1), l: SIMD4(1, 0, 0, 0), rho: 1, flips: 0) }
        let f = max(0, min(Double(samples.count - 1), t * Self.hz)), i = Int(f), j = min(samples.count - 1, i + 1), k = f - Double(i)
        let a = samples[i], b = samples[j]
        if a.flips != b.flips { return k < 0.5 ? a : b }
        let p = simd_normalize(a.p + (b.p - a.p) * k), l0 = a.l + (b.l - a.l) * k
        return Sample(p: p, l: simd_normalize(l0 - p * simd_dot(l0, p)), rho: a.rho + (b.rho - a.rho) * k, flips: a.flips)
    }
}

/// トンネルの断面の向き（a：出発の点・b：前・c：右。この 3 つでできる 3D がトンネルの世界）
struct TunnelBase { var a: SIMD4<Double>; var b: SIMD4<Double>; var c: SIMD4<Double> }

extension HyperLabState {
    /// 体の向きから、トンネルの断面の向きを作る（右は景色の右から、点・前と直角に）
    static func tunnelBase(_ w: Walk) -> TunnelBase {
        let a = simd_normalize(w.pos)
        var b = w.fwd - a * simd_dot(w.fwd, a); if simd_length(b) < 1e-6 { b = w.vL - a * simd_dot(w.vL, a) }
        if simd_length(b) < 1e-6 { b = SIMD4(1, 0, 0, 0) - a * a.x }
        b = simd_normalize(b)
        var c = SIMD4<Double>.zero
        for cand in [w.vR, SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)] {
            var v = cand - a * simd_dot(cand, a); v -= b * simd_dot(v, b)
            if simd_length(v) > 0.2 { c = simd_normalize(v); break }
        }
        return TunnelBase(a: a, b: b, c: c)
    }
    /// トンネルで見ている（超球ラン、またはトンネルで見るドリル・ドリルの道）
    var tunnelNow: Bool { tunForce ?? (tunnelView && (runOn || drillOn || drillK > 0.01 || drillTour != 0)) }
    // ---- 超球ラン ----
    func startRun() {
        guard let w = Self.walkSource?() else { runOn = false; return }
        if drillOn { runOn = false; return }
        drillTour = 0; glideDir = 0
        let b = Self.tunnelBase(w)
        tunBase = b; hrun.build(p0: b.a, l0: b.b); runT = 0; runGen = 0; runFlips = 0
        tunHoles = hrun.holes.map { TunnelHole(r: $0.r, dir: $0.dir, gen: 0) }
        Self.drillSink?(0)                                            // さんぽの体は自分では歩かない（ランが動かす）
        runLine = true; runClock = 0; runTrail = []
        if !tunnelView && !diveOn { diveManual = false; diveOn = true }   // ダイブ画面で見る：まだならダイブする
        bump()
    }
    /// ダイブ画面の金色の線の点（古い順。最後は今いる所）
    func runPathPoints() -> [SIMD4<Double>] {
        if let o = runPathOverride { return o }
        var pts = runTrail.map { $0.x }
        if runOn { let s = hrun.at(runT); pts.append(s.p * min(1, s.rho)) }
        return pts
    }
    func stopRun() {
        Self.drillSink?(2)
        tunHoles = []; bump()
    }
    /// 毎コマ：ランを進めて、さんぽの体・いる世界の R・穴を合わせる
    func tickRun(_ dt: Double) {
        if !runOn && tunForce == nil && tunnelView && (drillOn || drillK > 0.01), dt > 0, let x = tunnelPos() { openHoles(x, dt) }   // ドリル：近づいた殻の穴が開く
        guard runOn, dt > 0 else { return }
        runT += min(dt, 0.1)
        if runT >= hrun.length {                                       // 1 回り終わった：着いた所から次の回りへ（前の回りの穴は少しずつ閉じる）
            let end = hrun.at(hrun.length)
            runT -= hrun.length; runGen += 1; runFlips -= end.flips
            hrun.build(p0: end.p, l0: end.l)
            tunHoles = tunHoles.filter { $0.gen >= runGen - 1 } + hrun.holes.map { TunnelHole(r: $0.r, dir: $0.dir, gen: runGen) }
        }
        let s = hrun.at(runT)
        while runFlips < s.flips { Self.drillSink?(drillMirror ? 3 : 1); runFlips += 1 }
        Self.runPoseSink?(s.p, s.l)
        let r = max(0.05, min(1, s.rho)); if abs(r - worldR) > 1e-6 { worldR = r }
        openHoles(s.p * s.rho, dt)
        runClock += min(dt, 0.1)                                       // 通った道（ダイブ画面の金色の線）：0.02 進むごとに 1 点、7 秒分
        let x = s.p * min(1, s.rho)
        if runTrail.last.map({ simd_length($0.x - x) > 0.02 }) ?? true { runTrail.append((runClock, x)) }
        if let i = runTrail.firstIndex(where: { $0.t >= runClock - 7 }), i > 0 { runTrail.removeFirst(i) }
        version &+= 1
    }
    /// 穴：彗星が近づくと開く（一度開いたら、その回りの間は開いたまま）。前の回りの穴は、次の回りの 6 秒あとから閉じる
    func openHoles(_ x: SIMD4<Double>, _ dt: Double) {
        func sm(_ a: Double, _ b: Double, _ v: Double) -> Double { let c = max(0, min(1, (v - a) / (b - a))); return c * c * (3 - 2 * c) }
        for i in tunHoles.indices {
            if runOn && tunHoles[i].gen < runGen && runT > 6 { tunHoles[i].open = max(0, tunHoles[i].open - dt / 2); continue }
            let d = simd_length(x - tunHoles[i].dir * tunHoles[i].r)
            tunHoles[i].open = max(tunHoles[i].open, 1 - sm(0.12, 0.55, d))
        }
    }
    /// ドリルを始めた時：トンネルの断面と、通る殻の穴（降りる側・抜けた側）
    func tunnelDrillStart() {
        guard let w = Self.walkSource?() else { return }
        var b = Self.tunnelBase(w)
        if let o = tunBase, abs(simd_dot(o.a, b.a)) > 0.999 { b = o }       // 往復・D の字：同じ線を通るドリルは、同じ断面のまま（絵が飛ばない）
        tunBase = b
        tunHoles = HyperLabState.stageR.flatMap { [TunnelHole(r: $0, dir: b.a), TunnelHole(r: $0, dir: -b.a)] }
    }
    /// 今の彗星の 4D の場所（トンネルの世界で）。ラン・ドリル・ドリルの道の歩き
    func tunnelPos() -> SIMD4<Double>? {
        if tunForce != nil { return tunOverride }
        if runOn { let s = hrun.at(runT); return s.p * s.rho }
        guard tunnelView, let w = Self.walkSource?() else { return nil }
        func lift(_ r: Double) -> Double { r + 0.04 * max(0, min(1, (r - 0.85) / 0.15)) }   // 地表を歩く時は、外の殻のすぐ上（すれすれ）に
        if drillOn || drillK > 0.01 {
            let p0 = drillS < 1 ? w.pos : -w.pos, x = drillR0 * (1 - drillS)
            if !drillOn { return w.pos * lift(worldR) }
            return p0 * (x >= 0 ? lift(x) : -lift(-x))
        }
        return w.pos * lift(worldR)
    }
}

/// トンネルのカメラ（毎コマなめらかに追う）と、彗星の跡
struct TunnelCam {
    var eye: SIMD3<Double>? = nil, up = SIMD3<Double>(0, 1, 0), vel = SIMD3<Double>(0, 0, 1), prev: SIMD3<Double>? = nil, lastT = 0.0
    var trail: [SIMD3<Double>] = []
    var flash = 0.0                                                   // 中心を抜けた時の光
    var wasNear = false
}

extension HyperLabRenderer {
    /// 星（トンネルの世界の遠くの球の上。毎回同じ並び）
    static let tunStars: [SIMD4<Double>] = {
        var g = UInt64(0x9E3779B97F4A7C15), out: [SIMD4<Double>] = []
        func rnd() -> Double { g = g &* 6364136223846793005 &+ 1442695040888963407; return Double(g >> 11) / Double(1 << 53) }
        for _ in 0..<700 {
            let z = rnd() * 2 - 1, a = rnd() * 2 * .pi, s = (1 - z * z).squareRoot()
            out.append(SIMD4(s * cos(a), z, s * sin(a), 0.3 + 0.7 * pow(rnd(), 3)))
        }
        return out
    }()
    /// トンネルの世界の 3D：右 ＝ −c、上 ＝ a、前 ＝ b（4D の残りの向きは見ない ＝ 断面）
    func tunQ(_ x: SIMD4<Double>, _ tb: TunnelBase) -> SIMD3<Double> {
        let k: Double = Self.R * Self.SCALE
        let qx: Double = -(x * tb.c).sum(), qy: Double = (x * tb.a).sum(), qz: Double = (x * tb.b).sum()
        return SIMD3<Double>(qx * k, qy * k, qz * k)
    }
    /// トンネルで描く（描いたら true）。殻は断面の入れ子の球（網目と薄い面）、穴・穴のふち・中心の炉・彗星と跡・星
    func drawTunnel(_ e: MTLRenderCommandEncoder, _ sz: CGSize, _ asp: Float) -> Bool {
        guard side == .right, !overview, st.tunnelNow, let x4 = st.tunnelPos(), let base = st.tunBase else { return false }
        let W = Self.R * Self.SCALE
        let now = nowT, dt = tun.lastT == 0 ? 1.0 / 60 : max(1e-4, min(0.1, now - tun.lastT)); tun.lastT = now
        let P = tunQ(x4, base)
        // 進む向き（なめらかに）・上（外向き。進む向きと直角に）・カメラ（すぐ後ろの少し上。天井と床のあいだ）
        if let pv = tun.prev, simd_length(P - pv) > 1e-6 * W {
            let v = simd_normalize(P - pv), k = 1 - exp(-dt * 5)
            if simd_dot(v, tun.vel) < -0.95 { tun.vel = v } else { tun.vel = simd_normalize(tun.vel + (v - tun.vel) * k) }
        }
        tun.prev = P
        let V = tun.vel
        var tgtUp = simd_length(P) > 0.02 * W ? simd_normalize(P) : tun.up
        tgtUp -= V * simd_dot(tgtUp, V)
        tun.up -= V * simd_dot(tun.up, V); tun.up = simd_length(tun.up) > 1e-6 ? simd_normalize(tun.up) : SIMD3(0, 1, 0)
        if simd_length(tgtUp) > 0.2 {
            // 上の向きを、進む向きのまわりに回して合わせる（逆さまの時も、決まった向きへひねって起き上がる ＝ 宙返りのひねり）
            tgtUp = simd_normalize(tgtUp)
            var ang = atan2(simd_dot(simd_cross(tun.up, tgtUp), V), simd_dot(tun.up, tgtUp))
            if abs(ang) > 3.0 { ang = abs(ang) }
            let th = ang * (1 - exp(-dt * 3))
            tun.up = tun.up * cos(th) + simd_cross(V, tun.up) * sin(th)
        }
        tun.up -= V * simd_dot(tun.up, V); tun.up = simd_length(tun.up) > 1e-6 ? simd_normalize(tun.up) : SIMD3(0, 1, 0)
        let want = P - V * (0.17 * W) + tun.up * (0.045 * W)
        if let ey = tun.eye, simd_length(want - ey) < 0.6 * W { tun.eye = ey + (want - ey) * (1 - exp(-dt * 7)) } else { tun.eye = want }
        let eye = tun.eye!
        let look = P + V * (0.3 * W) - tun.up * (0.015 * W)
        let f = simd_normalize(look - eye)
        var r = simd_cross(f, tun.up); r = simd_length(r) > 1e-6 ? simd_normalize(r) : SIMD3(1, 0, 0)
        let uu = simd_cross(r, f)
        let view = simd_double4x4(rows: [SIMD4(r, -simd_dot(r, eye)), SIMD4(uu, -simd_dot(uu, eye)), SIMD4(-f, simd_dot(f, eye)), SIMD4(0, 0, 0, 1)])
        let fov: Float = 74, n: Float = 0.01, fr: Float = 120, ys = 1 / tan(fov * .pi / 360), xs = ys / asp
        let proj = simd_float4x4(rows: [[xs, 0, 0, 0], [0, ys, 0, 0], [0, 0, fr / (n - fr), fr * n / (n - fr)], [0, 0, -1, 0]])
        var u = HLUni()
        u.mvp = seeClip * proj * simd_float4x4(SIMD4<Float>(view.columns.0), SIMD4<Float>(view.columns.1), SIMD4<Float>(view.columns.2), SIMD4<Float>(view.columns.3))
        u.eye = SIMD4(SIMD3<Float>(eye), 1); u.g = SIMD4(0, 0, 0, 0); u.camR = SIMD4(SIMD3<Float>(r), 0); u.camU = SIMD4(SIMD3<Float>(uu), 0)
        lastFov = Double(fov); lastAsp = Double(asp)
        // 中心を抜けた瞬間の光
        let near = simd_length(P) < 0.06 * W
        if near && !tun.wasNear { tun.flash = 1 }
        tun.wasNear = near; tun.flash = max(0, tun.flash - dt / 0.9)
        // 跡（最近の 1.2 秒ほど）
        tun.trail.append(P); if tun.trail.count > 80 { tun.trail.removeFirst(tun.trail.count - 80) }
        if let l = tun.trail.dropLast().last, simd_length(P - l) > 0.5 * W { tun.trail = [P] }   // 飛んだ（別の道）時は跡を切る
        var bg: [HLVert] = [], faces: [HLVert] = [], glow: [HLVert] = []
        // 背景：深い宇宙の色（画面いっぱい。いちばん奥）
        do {
            let c = SIMD4<Float>(0.012, 0.014, 0.035, 1)
            let q = [SIMD4<Float>(-1, -1, 0.9999, 1), SIMD4<Float>(1, -1, 0.9999, 1), SIMD4<Float>(1, 1, 0.9999, 1), SIMD4<Float>(-1, 1, 0.9999, 1)]
            bg = [0, 1, 2, 0, 2, 3].map { HLVert(p: q[$0], n: .zero, c: c) }
        }
        func disc(_ p: SIMD3<Double>, _ rad: Double, _ col: SIMD4<Float>, _ out: inout [HLVert], seg: Int = 14) {
            let a = r * rad, b = uu * rad
            for i in 0..<seg {
                let t0 = Double(i) / Double(seg) * 2 * .pi, t1 = Double(i + 1) / Double(seg) * 2 * .pi
                let c0 = SIMD4<Float>(col.x, col.y, col.z, 0)
                out += [HLVert(p: SIMD4(SIMD3<Float>(p), 1), n: .zero, c: col),
                        HLVert(p: SIMD4(SIMD3<Float>(p + a * cos(t0) + b * sin(t0)), 1), n: .zero, c: c0),
                        HLVert(p: SIMD4(SIMD3<Float>(p + a * cos(t1) + b * sin(t1)), 1), n: .zero, c: c0)]
            }
        }
        // 星（カメラのまわりの大きな球。足し合わせ）
        for s in Self.tunStars {
            let p = eye + SIMD3(s.x, s.y, s.z) * (40 * W / 2.24)
            disc(p, 0.05 * W * (0.5 + s.w), SIMD4(Float(0.7 * s.w), Float(0.78 * s.w), Float(0.95 * s.w), 1), &glow, seg: 5)
        }
        // 殻：断面の球（極は右の向き。彗星の道は赤道なので、経線が肋骨のように流れ、緯線が溝のように道にそう）
        let holes = st.tunHoles
        var wires: [HLVert] = []
        for (si, rs) in HyperLabState.stageR.enumerated() {
            let hk = Float(1 - rs)                                    // 内ほど炉の熱の色
            let wc = SIMD4<Float>(0.45 + 0.55 * hk, 0.72 - 0.2 * hk, 1.0 - 0.75 * hk, 0.55 - 0.3 * hk)
            let fc = SIMD4<Float>(0.25 + 0.5 * hk, 0.42 - 0.1 * hk, 0.8 - 0.6 * hk, 0.05 + 0.025 * Float(si) / 4)
            let myHoles: [(SIMD3<Double>, Double, Double)] = holes.filter { abs($0.r - rs) < 1e-6 && $0.open > 0.01 }.map {
                let d = tunQ($0.dir, base); let l = simd_length(d)
                return (l > 1e-9 ? d / l : SIMD3(0, 1, 0), $0.open * min(0.9, 0.13 / rs), $0.open)
            }
            func inHole(_ n: SIMD3<Double>, _ pad: Double = 0) -> Bool { myHoles.contains { acos(max(-1, min(1, simd_dot(n, $0.0)))) < $0.1 + pad } }
            func sp(_ th: Double, _ ph: Double) -> SIMD3<Double> { SIMD3(cos(th), sin(th) * cos(ph), sin(th) * sin(ph)) }
            let step = (rs >= 0.6 ? 4.0 : rs >= 0.4 ? 6 : 8) * .pi / 180, rad = rs * W, lw = 0.0024 * W, nm = rs >= 0.6 ? 30 : rs >= 0.4 ? 24 : 16, nl = rs >= 0.6 ? 15 : rs >= 0.4 ? 12 : 8
            // 経線（右の極から左の極まで）
            for k in 0..<nm {
                let ph = Double(k) / Double(nm) * 2 * .pi, m = Int((.pi / step).rounded())
                var pts: [SIMD3<Double>] = []
                for j in 0...m {
                    let n = sp(Double(j) / Double(m) * .pi, ph)
                    if inHole(n) { if pts.count > 1 { wires += Self.ribbon(pts, wc, w: lw, eye: eye) }; pts = [] } else { pts.append(n * rad) }
                }
                if pts.count > 1 { wires += Self.ribbon(pts, wc, w: lw, eye: eye) }
            }
            // 緯線（道にそう溝）
            for j in 1..<nl {
                let th = Double(j) / Double(nl) * .pi, m = Int((2 * .pi / step).rounded())
                var pts: [SIMD3<Double>] = []
                for k in 0...m {
                    let n = sp(th, Double(k) / Double(m) * 2 * .pi)
                    if inHole(n) { if pts.count > 1 { wires += Self.ribbon(pts, wc, w: lw, eye: eye) }; pts = [] } else { pts.append(n * rad) }
                }
                if pts.count > 1 { wires += Self.ribbon(pts, wc, w: lw, eye: eye) }
            }
            // 薄い面（穴の所はあける）
            let nt = rs >= 0.6 ? 24 : 14, np = nt * 2
            for a in 0..<nt { for b in 0..<np {
                let t0 = Double(a) / Double(nt) * .pi, t1 = Double(a + 1) / Double(nt) * .pi, p0 = Double(b) / Double(np) * 2 * .pi, p1 = Double(b + 1) / Double(np) * 2 * .pi
                let c = sp((t0 + t1) / 2, (p0 + p1) / 2)
                if inHole(c, 0.02) { continue }
                let q = [sp(t0, p0), sp(t1, p0), sp(t1, p1), sp(t0, p1)].map { HLVert(p: SIMD4(SIMD3<Float>($0 * rad), 1), n: SIMD4(SIMD3<Float>($0), 0), c: fc) }
                faces += [q[0], q[1], q[2], q[0], q[2], q[3]]
            } }
            // 穴のふち：光る輪（開くほど明るく）
            for h in myHoles where h.1 > 1e-3 {
                var t1 = simd_cross(h.0, SIMD3(0, 1, 0)); if simd_length(t1) < 0.1 { t1 = simd_cross(h.0, SIMD3(1, 0, 0)) }
                t1 = simd_normalize(t1); let t2 = simd_cross(h.0, t1)
                let ring = (0...48).map { i -> SIMD3<Double> in let a = Double(i) / 48 * 2 * .pi; return (h.0 * cos(h.1) + (t1 * cos(a) + t2 * sin(a)) * sin(h.1)) * rad }
                let k = Float(h.2)
                wires += Self.ribbon(ring, SIMD4(1.0 * k, 0.62 * k, 0.22 * k, 0.9 * k), w: lw * 2.2, eye: eye)
            }
        }
        // 中心の炉：脈打つ光（内核の演出の時はもっと強く）
        let pulse = 0.5 + 0.5 * sin(now * 3.1), heat = st.chaosOn ? 1.0 : 0.7
        disc(.zero, (0.035 + 0.008 * pulse) * W, SIMD4(1, 0.9, 0.65, 1), &glow, seg: 20)
        disc(.zero, (0.09 + 0.02 * pulse) * W * heat, SIMD4(Float(0.7 * heat), Float(0.32 * heat), 0.08, 1), &glow, seg: 24)
        disc(.zero, 0.2 * W * heat, SIMD4(0.22, 0.07, 0.02, 1), &glow, seg: 24)
        // 彗星と跡
        let tr = tun.trail
        if tr.count > 2 {
            let n = tr.count
            for i in stride(from: 0, to: n - 1, by: 8) {
                let seg = Array(tr[i...min(n - 1, i + 8)]), mid = seg[seg.count / 2]
                let dk = Float(max(0, min(1, (simd_length(mid - eye) - 0.08 * W) / (0.25 * W))))   // カメラのすぐそばの跡は消す（画面いっぱいの帯にならない）
                let k = Float(Double(i + 8) / Double(n)) * dk
                glow += Self.ribbon(seg, SIMD4(1.0 * k, 0.55 * k, 0.18 * k, 1), w: 0.0035 * W * Double(0.4 + 0.6 * k), eye: eye)
            }
        }
        disc(P, 0.014 * W, SIMD4(1, 1, 0.95, 1), &glow)
        disc(P, 0.045 * W, SIMD4(1, 0.6, 0.2, 1), &glow, seg: 18)
        if tun.flash > 0 { let k = Float(tun.flash * tun.flash); disc(eye + f * (0.2 * W), 0.6 * W, SIMD4(k, 0.85 * k, 0.6 * k, 1), &glow, seg: 24) }   // 中心を抜けたピカッ
        func put(_ v: [HLVert], _ pipe: MTLRenderPipelineState, _ uu0: HLUni) {
            guard !v.isEmpty else { return }
            var uu1 = uu0
            e.setRenderPipelineState(pipe); e.setDepthStencilState(depthRead)
            v.withUnsafeBytes { bb in if let buf = device.makeBuffer(bytes: bb.baseAddress!, length: bb.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) } }
            e.setVertexBytes(&uu1, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&uu1, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: v.count)
        }
        var ub = HLUni(); ub.g = SIMD4(0, 0, 0, 0)
        put(bg, alphaPipe, ub)
        put(faces, alphaPipe, u)
        put(wires, tunAddPipe, u)
        put(glow, tunAddPipe, u)
        return true
    }
}
