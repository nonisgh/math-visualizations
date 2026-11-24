// 4 次元の水を注ぐ（ウェブ版の「4D水を注ぐ」の 1 段目と 2 段目：注ぐ・ためる・抜く ＋ 浅水方程式の波）。
//   ふた +W を開けて、外から水を注ぐ。水位 h が 底 −W から上がっていく：V(h) ＝ ∫₋₁ʰ 8 dw ＝ 8(h＋1)（連続の積分）。
//   水の中身は 4 次元の箱 [−1,1]³ × [−1, h]。その表面＝底の立方体（w ＝ −1）・水面の立方体（w ＝ h）・壁に触れている 12 枚の面（立方体の辺 × w）。
//   4 次元の水面は 3 次元の立方体。それを浅水方程式（ナビエ–ストークスを深さで平均したもの）で本当に揺らす（4D は 32×32×32、左の 3D 水は 48×48）。
//   底を全部開けると、水はかたまりのまま自由落下で抜ける（見かけの重力 0 なので、揺れはそのまま）。
//   左の立方体の窓は 1 次元下げた同じもの：z の方向に水位が上がり、水面は正方形。
//   これから：排水口（渦・トリチェリ）・通気口（ごぼっ）・泡・油・虹の水・穴の工事・ふたの開け閉めの絵（積分の移植メモ.md の 8c〜8e）
import Foundation
import simd

/// 浅水方程式の格子（ウェブ版の SWE）：η（水面の高さのずれ）と、面の上の流れ u
final class WaterSWE {
    static let N = 32, M = 48, GAM = 0.2, JET = 0.3, LIM = 0.32, DT = 0.008, NU = 0.002   // 格子は 4D 32³・3D 48²（細かい波）。DT は波が格子を飛び越さない小ささ
    var eta = [Float](repeating: 0, count: N * N * N)
    var ux = [Float](repeating: 0, count: (N + 1) * N * N), uy = [Float](repeating: 0, count: N * (N + 1) * N), uz = [Float](repeating: 0, count: N * N * (N + 1))
    var p = [Float](repeating: 0, count: N * N * N), gj = [Float](repeating: 0, count: N * N * N), gc = [Float](repeating: 0, count: N * N * N)   // gc：排水口（真ん中）
    var e2 = [Float](repeating: 0, count: M * M), vx2 = [Float](repeating: 0, count: (M + 1) * M), vy2 = [Float](repeating: 0, count: M * (M + 1))
    var p2 = [Float](repeating: 0, count: M * M), gj2 = [Float](repeating: 0, count: M * M), gc2 = [Float](repeating: 0, count: M * M)
    var noise: Float = 0
    init(us: SIMD3<Double>) {
        let N = Self.N, M = Self.M
        func cen(_ i: Int, _ n: Int) -> Double { -1 + (Double(i) + 0.5) * 2 / Double(n) }
        for i in 0..<N { for j in 0..<N { for k in 0..<N {
            let x = cen(i, N), y = cen(j, N), z = cen(k, N)
            gj[(i * N + j) * N + k] = Float(exp(-(pow(x - us.x, 2) + pow(y - us.y, 2) + pow(z - us.z, 2)) / 0.035))   // 水の筋が当たる所
            gc[(i * N + j) * N + k] = Float(exp(-(x * x + y * y + z * z) / 0.02))
        } } }
        for i in 0..<M { for j in 0..<M { let x = cen(i, M), y = cen(j, M); gj2[i * M + j] = Float(exp(-(pow(x - us.x, 2) + pow(y - us.y, 2)) / 0.035)); gc2[i * M + j] = Float(exp(-(x * x + y * y) / 0.02)) } }
    }
    func reset() {
        for i in eta.indices { eta[i] = 0 }; for i in ux.indices { ux[i] = 0 }; for i in uy.indices { uy[i] = 0 }; for i in uz.indices { uz[i] = 0 }
        for i in e2.indices { e2[i] = 0 }; for i in vx2.indices { vx2[i] = 0 }; for i in vy2.indices { vy2[i] = 0 }; noise = 0
    }
    /// 1 小ステップ：∂u/∂t ＝ −g∇η − ∇p − γu（p＝水の筋が当たる所の圧力）、∂η/∂t ＝ −D∇·u − q（q＝排水口から吸い出す量）。壁は流れが通らない。平均の水位は h が受け持つので η は平均 0
    func step(_ dt: Float, g: Float, D: Float, jet: Float, H: Float, sink: Float = 0) {
        let N = Self.N, dx = 2 * H / Float(N), damp = exp(-(Float(Self.GAM) + 3 * Float(Self.NU) / (D * D)) * dt), L = Float(Self.LIM) * H
        for n in 0..<p.count { p[n] = jet * gj[n] }
        for i in 1..<N { for j in 0..<N { for k in 0..<N { let a = ((i - 1) * N + j) * N + k, b = (i * N + j) * N + k; ux[b] = (ux[b] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx) * damp } } }
        for i in 0..<N { for j in 1..<N { for k in 0..<N { let a = (i * N + j - 1) * N + k, b = (i * N + j) * N + k, f = (i * (N + 1) + j) * N + k; uy[f] = (uy[f] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx) * damp } } }
        for i in 0..<N { for j in 0..<N { for k in 1..<N { let a = (i * N + j) * N + k - 1, b = a + 1, f = (i * N + j) * (N + 1) + k; uz[f] = (uz[f] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx) * damp } } }
        var sum: Float = 0
        for i in 0..<N { for j in 0..<N { for k in 0..<N {
            let n = (i * N + j) * N + k
            let div = ux[((i + 1) * N + j) * N + k] - ux[n] + uy[(i * (N + 1) + j + 1) * N + k] - uy[(i * (N + 1) + j) * N + k] + uz[(i * N + j) * (N + 1) + k + 1] - uz[(i * N + j) * (N + 1) + k]
            eta[n] += dt * (-D * div / dx - sink * gc[n]); sum += eta[n]
        } } }
        let mean = sum / Float(eta.count); for n in 0..<eta.count { eta[n] = max(-L, min(L, eta[n] - mean)) }
        // 左の 3D 水（x・y の 2 方向）
        let M = Self.M, d2 = 2 * H / Float(M)
        for n in 0..<p2.count { p2[n] = jet * gj2[n] }
        for i in 1..<M { for j in 0..<M { let a = (i - 1) * M + j, b = i * M + j; vx2[b] = (vx2[b] - dt * (g * (e2[b] - e2[a]) + p2[b] - p2[a]) / d2) * damp } }
        for i in 0..<M { for j in 1..<M { let a = i * M + j - 1, b = a + 1, f = i * (M + 1) + j; vy2[f] = (vy2[f] - dt * (g * (e2[b] - e2[a]) + p2[b] - p2[a]) / d2) * damp } }
        var s2: Float = 0
        for i in 0..<M { for j in 0..<M { let n = i * M + j, div = vx2[(i + 1) * M + j] - vx2[n] + vy2[i * (M + 1) + j + 1] - vy2[i * (M + 1) + j]; e2[n] += dt * (-D * div / d2 - sink * gc2[n]); s2 += e2[n] } }
        let m2 = s2 / Float(e2.count); for n in 0..<e2.count { e2[n] = max(-L, min(L, e2[n] - m2)) }
    }
    /// 水面のずれ η を点 u（−1〜1）で（格子の真ん中どうしを直線でつなぐ）
    func sample3(_ u: SIMD3<Double>) -> Double {
        let N = Self.N
        func f(_ q: Double) -> Double { max(0, min(Double(N) - 1.0001, (q + 1) / 2 * Double(N) - 0.5)) }
        let fx = f(u.x), fy = f(u.y), fz = f(u.z), i = Int(fx), j = Int(fy), k = Int(fz), a = fx - Double(i), b = fy - Double(j), c = fz - Double(k)
        let I = min(N - 1, i + 1), J = min(N - 1, j + 1), K = min(N - 1, k + 1)
        func e(_ x: Int, _ y: Int, _ z: Int) -> Double { Double(eta[(x * N + y) * N + z]) }
        return ((e(i, j, k) * (1 - c) + e(i, j, K) * c) * (1 - b) + (e(i, J, k) * (1 - c) + e(i, J, K) * c) * b) * (1 - a)
             + ((e(I, j, k) * (1 - c) + e(I, j, K) * c) * (1 - b) + (e(I, J, k) * (1 - c) + e(I, J, K) * c) * b) * a
    }
    func sample2(_ u: SIMD2<Double>) -> Double {
        let M = Self.M
        func f(_ q: Double) -> Double { max(0, min(Double(M) - 1.0001, (q + 1) / 2 * Double(M) - 0.5)) }
        let fx = f(u.x), fy = f(u.y), i = Int(fx), j = Int(fy), a = fx - Double(i), b = fy - Double(j), I = min(M - 1, i + 1), J = min(M - 1, j + 1)
        func e(_ x: Int, _ y: Int) -> Double { Double(e2[x * M + y]) }
        return (e(i, j) * (1 - b) + e(i, J) * b) * (1 - a) + (e(I, j) * (1 - b) + e(I, J) * b) * a
    }
}

extension OrigamiState {
    // 秒・重力（世界の長さ／秒²）・水面の細かさ・水の筋の出発点（w ＝ TOP×H）・筋の位置（ウェブ版の WWATER）
    static let wOPEN = 0.8, wPOUR = 10.0, wCLOSE = 0.9, wHOLD = 2.2, wBOPEN = 0.7, wBCLOSE = 0.8, wEMPTY = 0.7, wG = 2.7, wGrid = 8, wTOP = 2.0
    // 排水口：床の立方体の真ん中の小さな立方体（半分の幅 HOLE×H）・開けっぱなしで注ぐ速さ（水位の上がる速さ）・吸い出す強さ・ごぼっの回数（1 秒に）
    static let wHOLE = 0.58, wQOPEN = 0.48, wSINK: Float = 1.6, wGF = 1.4
    static let wUS = SIMD3<Double>(0.3, -0.35, 0.2)
    /// 底を全部開けた時に、満水（深さ 2H）が落ちきるまでの秒（自由落下）
    static var wFallT: Double { sqrt(2 * 2 * half / wG) }
    /// 1 コマ分すすめる：時刻・水位・場面と、波（小ステップに分けて）
    /// 排水口から抜くのは g と穴の広さから：トリチェリ（出る速さ √(2g・深さ)）で、空になるまで (水面の広さ／穴の広さ) × √(2・2H／g)。
    ///   4 次元では「広さ」は 3 次元の体積なので、広さの比は (穴の半幅／H)³（3 次元のお風呂なら 2 乗）。同じ形の穴でも 4 次元のほうがずっとゆっくり抜ける
    static var wDrainHoleT: Double { wFallT / pow(wHOLE, 3) }
    /// 排水口が開けっぱなし（工事済みの時だけ）
    var holesOpen: Bool { holesBuilt && holesOpenSet }
    /// 今回の抜き方が排水口か（交互＝1 回ごとに 底を全部 → 排水口 → …）
    var waterHoleNow: Bool { holesOpen || drainMode == 1 || (drainMode == 2 && waterCyc % 2 == 1) }
    /// 1 コマ分すすめる：時刻・水位・場面と、波（小ステップに分けて）
    func waterTick(_ dt0: Double) {
        if waterFree && waterNS, let ns = ns4Get() { waterFreeTick(ns, min(0.1, dt0)); return }
        let dt = min(0.1, dt0), H = Self.half
        let hole = waterHoleNow, hOpen = holesOpen, DR = hole ? Self.wDrainHoleT : Self.wFallT
        // 通気：空気の入り口（通気口か、開いたままの上のふた）が無いと、底から空気と入れ替わりながらしか抜けない（ごぼごぼ、ゆっくり）
        let vented = waterVent || (intLidMode == 1 && hole), DRv = vented ? DR : DR / (hole ? 0.35 : 0.5), GF = Self.wGF
        let t0 = Self.wOPEN, t1 = t0 + Self.wPOUR * (hOpen ? 1.4 : 1), t2 = t1 + Self.wCLOSE, t3 = t2 + Self.wHOLD, t3b = t3 + Self.wBOPEN, t4 = t3b + DRv, t5 = t4 + Self.wBCLOSE, cycle = t5 + Self.wEMPTY
        if hOpen {   // 開けっぱなし：栓が無いので注いでいる間も抜ける。入る量 Q と出る量 a√(2g・深さ)（トリチェリ）がつり合う水位に近づき、止めると抜けきる
            let r = pow(Self.wHOLE, 3), tt = waterT + dt
            if tt < dt * 1.5 { waterDOpen = 0 }
            let pourNow = tt >= t0 && tt < t1, dd = waterDOpen, outR = r * sqrt(2 * Self.wG * dd) * (vented ? 1 : 0.35)
            waterDOpen = max(0, min(2 * H, dd + ((pourNow ? Self.wQOPEN : 0) - outR) * dt))   // 水位の式：d′ ＝ Q − a√(2g d)
            waterHEq = min(1, -1 + pow(Self.wQOPEN / r, 2) / (2 * Self.wG) / H)
            if !pourNow && tt >= t1 && waterDOpen <= 1e-3 {   // 抜けきったら少し置いて、また注ぐ
                if waterEmptyT == nil { waterEmptyT = tt }
                if tt - (waterEmptyT ?? tt) > Self.wEMPTY { waterT = -dt; waterEmptyT = nil; waterCyc += 1 }
            } else { waterEmptyT = nil }
        }
        if waterT + dt >= cycle { waterCyc += 1 }
        waterT = (waterT + dt).truncatingRemainder(dividingBy: cycle); waterTT += dt
        let t = waterT, pouring = t >= t0 && t < t1
        var sD = (t - t3b) / DRv
        if !vented && t >= t3b && t < t4 { sD = max(0, min(1, sD - 0.8 / (2 * .pi * GF * DRv) * sin(2 * .pi * GF * (t - t3b)))) }   // ごぼっ、ごぼっ：空気が 1 回入るたびに少し流れる
        let gp = t >= t3b && t < t4 ? Int(floor(GF * (t - t3b) + 0.25)) : -1, glugNow = !vented && gp >= 0 && gp != waterGlugN; waterGlugN = gp
        waterVented = vented
        // 底を全部開けると、水はかたまりのまま落ちる（だんだん速く）。排水口からは、深いほど速く出て、浅くなるとゆっくり（トリチェリ）
        var h = t < t0 ? -1 : t < t1 ? -1 + 2 * (t - t0) / (t1 - t0) : t < t3b ? 1 : t < t4 ? (hole ? -1 + 2 * (1 - sD) * (1 - sD) : 1 - 2 * sD * sD) : -1
        var phase = t < t0 ? 0 : pouring ? 1 : t < t3 ? 2 : t < t3b ? 3 : t < t4 ? 4 : t < t5 ? 5 : 6   // 0 開ける・1 注ぐ・2 いっぱい・3 栓を抜く・4 抜ける・5 栓をする・6 空
        var lid = t < t0 ? t / t0 : t < t1 ? 1 : t < t2 ? 1 - (t - t1) / Self.wCLOSE : 0                     // 上のふた：開ける → 注ぐ → 閉める
        var blid = t < t3 ? 0 : t < t3b ? (t - t3) / Self.wBOPEN : t < t4 ? 1 : t < t5 ? 1 - (t - t4) / Self.wBCLOSE : 0   // 底：栓を抜く → 抜く → 栓をする
        if intLidMode == 1 { lid = hole ? 1 : 1 - blid }                                                   // 開けたまま：上のふたは閉じない（底を全部開ける時だけ閉める）
        // 流れ出る水の柱（同じ g）：全部開けた時は止まった所から自由落下、排水口からは √(2g・深さ) の速さで出て、さらに g で加速
        let FL = 1.5 * H, v0 = hole ? sqrt(2 * Self.wG * 2 * H) : 0, vEnd = hole ? 0 : Self.wG * DR, tau = t - t3b, tl = t - t4
        func fallD(_ v: Double, _ s: Double) -> Double { v * s + 0.5 * Self.wG * s * s }
        if t >= t3b && (t < t4 || -H - fallD(vEnd, tl) > -H - FL) {
            waterOut = SIMD2(t < t4 ? -H : -H - fallD(vEnd, tl), -H - min(FL * 1.05, fallD(v0, tau)))
        } else { waterOut = nil }
        if hOpen {   // 開けっぱなし：水位・場面・流れ出る柱を、上の水位の式から（栓は無い）
            let d = waterDOpen
            h = -1 + d / H; phase = t < t0 ? 0 : pouring ? 1 : d > 1e-3 ? 4 : 6
            blid = 1; waterOut = d > 1e-3 ? SIMD2(-H, -H - FL * 1.05) : nil
        }
        waterLid = max(0, min(1, lid)); waterBLid = max(0, min(1, blid))
        if abs(waterH - h) > 1e-5 { waterH = h }
        if waterPhase != phase { waterPhase = phase }
        waterPour = t >= t0 ? (pouring ? Self.wTOP * H : t >= t1 ? Self.wTOP * H - 0.5 * Self.wG * (t - t1) * (t - t1) : -9) : -9   // 水の筋の上の端（止めた後のしっぽは g で落ちる）
        // 波：浅水方程式（水が無い時は静か。底を全部開けて落ちている間は、見かけの重力 0 なので形はそのまま。通気が無い時は空気の圧力で支えられるので計算する）
        let flowing = hole && (phase == 4 || (hOpen && phase == 1))
        if h <= -0.999 { swe.reset() }
        else if !(phase == 4 && !hole && vented) {
            let D = Float(max(0.02, (h + 1) * H)), nSub = min(12, Int(ceil(dt / WaterSWE.DT))), sd = Float(dt) / Float(max(1, nSub))
            for _ in 0..<max(1, nSub) {
                swe.noise = max(-1, min(1, swe.noise * 0.97 + Float.random(in: -1...1) * 0.35))   // 水の筋の勢いのゆらぎ
                let jet: Float = pouring && h > -0.98 ? Float(WaterSWE.JET) * (1 + swe.noise) : 0
                let sink: Float = flowing ? Self.wSINK * Float(min(1, (h + 1) * 2)) * Float(1 + 3 * max(0, waterBurst) / 0.45) : 0   // 開けた瞬間は強く吸い込む
                if waterBurst > 0 { waterBurst -= Double(sd) }
                swe.step(sd, g: Float(Self.wG), D: D, jet: jet, H: Float(H), sink: sink)
            }
        }
        // 開けた瞬間：排水口の所の圧力が急に下がり、真上がぐっとへこむ（へこみは輪になって広がる）
        if phase == 4 && waterPrevPhase != 4 && h > -0.97 && hole {
            waterBurst = 0.45
            for n in swe.eta.indices { swe.eta[n] -= Float(0.1 * H) * swe.gc[n] }
            for n in swe.e2.indices { swe.e2[n] -= Float(0.1 * H) * swe.gc2[n] }
        }
        waterPrevPhase = phase
        if glugNow && h > -0.97 {   // ごぼっ：底から入った空気のかたまりが水を押し上げる（真ん中がぽこっと盛り上がる）
            for n in swe.eta.indices { swe.eta[n] += Float(0.06 * H) * swe.gc[n] }
            for n in swe.e2.indices { swe.e2[n] += Float(0.06 * H) * swe.gc2[n] }
        }
        // 渦のくぼみ（水面の真ん中が排水口へ向かってへこむ）：なめらかに追いかける
        let vdT = flowing ? 0.45 * min(1, hOpen ? 1 : max(0, sD) * 5) * min(1, (h + 1) * 1.5) : 0
        waterVD += (vdT - waterVD) * min(1, dt * 3); waterSD = sD
        // ---- 本物の 4D の水（ナビエ–ストークス）：注ぐ・排水口・底の全開を境目として与え、水位は体積から ----
        if waterNS, let ns = ns4Get() {
            let H4 = pow(H, 4), Vbox = 16 * H4
            if t < nsPrevT - 1e-6 { ns.reset(level: -1); nsVTarget = 0 }       // 1 回りの始め：空に
            nsPrevT = t
            let vf = ns.lastVol / Vbox, pourOn = pouring && vf < 0.97, Nf = Float(ns.N)
            ns.par.vort = Float(waterVort)
            ns.par.jetOn = pourOn ? 1 : 0; ns.par.topOpen = 0; ns.par.gvec = SIMD4<Float>(nsLagGravity(dt) * Self.wG + nsShake(dt)); ns.par.jetD = SIMD4(0, 0, 0, -1); ns.par.pad2 = 0
            // 入れる所：平均の水位（体積から：V ＝ 8(h＋1)）のすぐ上（2 マス上から 3 マス）。落ちる高さを小さく（天井から落とすと はねすぎる）。
            //   柱の水面を探すと、入れた水が下とつながった時に「水面がそこまで上がった」とまちがえて、入れる所が天井までのぼっていく
            let hAvg = max(-1, min(1, ns.lastVol / (8 * pow(H, 4)) - 1)), l0 = max(0, min(ns.N - 3, Int(((hAvg * H + H) / Double(ns.par.dx)).rounded()) + 1))   // 1 マス上（静かに）
            ns.par.jetC = SIMD4(Float(Self.wUS.x + 1) / 2 * Nf, Float(Self.wUS.y + 1) / 2 * Nf, Float(Self.wUS.z + 1) / 2 * Nf, Float(l0))
            let jr = 0.32, jv = 0.9                                            // 筋の太さ（世界の単位）と速さ：4 次元では筋の切り口も 3 次元の玉なので、太くないとなかなか溜まらない
            ns.par.jetR = Float(jr) / ns.par.dx; ns.par.jetV = Float(jv)
            ns.par.hole = hole && (phase == 4 || hOpen) ? Float(Self.wHOLE) * Nf / 2 : 0
            ns.par.open = !hole && phase == 4 ? 1 : 0
            if phase == 4 && nsPrevPhase != 4 && hole && waterSwirl > 0 { ns.addSwirl(Float(waterSwirl)) }   // 栓を抜いた瞬間：お風呂に残っている小さな回転
            nsPrevPhase = phase
            // 体積の目標：注いでいる間は、注ぐ時間でまっすぐ増やす（V(h) ＝ 8(h＋1) の連続の積分どおり。筋は見た目と波）。
            //   注ぎ終わったらその量を保つ。抜いている間は、減った分を目標に（体積の合わせ直しは、計算で少しずつ減る分を戻すだけ）
            if pouring && !hOpen { nsVTarget = max(nsVTarget, 0.95 * Vbox * max(0, min(1, (t - t0) / (t1 - t0)))) }
            if hOpen && pouring { nsVTarget = ns.lastVol }
            if ns.par.hole > 0 || ns.par.open != 0 { nsVTarget = min(nsVTarget, ns.lastVol) }
            if !pouring && ns.lastVol < 1e-3 { nsVTarget = 0 }
            nsSloshKick(ns, dt)
            ns.tick(dt, target: nsVTarget < 1e-3 || (hOpen && pouring) ? nil : nsVTarget)
            let hN = max(-1, min(1, ns.lastVol / (8 * H4) - 1))
            if abs(waterH - hN) > 1e-5 { waterH = hN }
            if phase == 4 && vf > 0.003 && waterT > t4 - 0.1 && !hOpen { waterT = t4 - 0.1 }   // 抜けきるまで待つ
        }
    }
}

extension OrigamiState {
    /// 箱を回した時のちゃぷちゃぷ：前のコマからの箱の回転 Q ＝ R₀ᵀR₁ の生成子 W ＝ (Q − Qᵀ)／(2dt)（箱から見た回る速さ）の、前との差 ΔW を水に渡す
    /// 箱にくっついた重力（箱の −w）を、水が感じる「下」として少し遅れさせる：遅れた向き L が今の向き R に 0.3×強さ 秒で追いつく。
    ///   箱から見た重力 ＝ Rᵀ L (0,0,0,−1)。回している間は回る前の「下」が残って水が寄り、止めると追いついてゆれもどる（ちゃぷちゃぷ）
    func nsLagGravity(_ dt: Double) -> SIMD4<Double> {
        let R = m4
        guard waterSlosh > 0.01, var L = nsLagM4 else { nsLagM4 = R; return SIMD4(0, 0, 0, -1) }
        let a = 1 - exp(-dt / (0.3 * waterSlosh))
        L = L + (R - L) * a
        // 列を正規直交に（グラム–シュミット）
        var c = [L.columns.0, L.columns.1, L.columns.2, L.columns.3]
        for i in 0..<4 { for j in 0..<i { c[i] -= simd_dot(c[i], c[j]) * c[j] }; let l = simd_length(c[i]); c[i] = l > 1e-9 ? c[i] / l : SIMD4(i == 0 ? 1 : 0, i == 1 ? 1 : 0, i == 2 ? 1 : 0, i == 3 ? 1 : 0) }
        L = simd_double4x4(c[0], c[1], c[2], c[3]); nsLagM4 = L
        let g = simd_transpose(R) * (L * SIMD4<Double>(0, 0, 0, -1)), gl = simd_length(g)
        return gl > 1e-9 ? g / gl : SIMD4(0, 0, 0, -1)
    }
    /// ゆさぶり：ドラッグの手の速さの変わり（加速度）を、箱から見た「見かけの力」（手と逆向き）にして重力に足す。急に動かす・止めると水が寄ってゆれもどる
    func nsShake(_ dt: Double) -> SIMD4<Double> {
        guard dt > 1e-4 else { return .zero }
        let vNow = waterShakeAcc / dt; waterShakeAcc = .zero
        let vS = waterShakeV + (vNow - waterShakeV) * min(1, dt / 0.06)        // 手の速さ（少しなめらかに）
        let acc = (vS - waterShakeV) / dt; waterShakeV = vS
        // 画面の横 ＝ 景色の x、縦（下が ＋）＝ 景色の −y。手の加速度の逆向きを、箱の向きへ戻す
        var f = SIMD4<Double>(-acc.x, acc.y, 0, 0) * (0.12 * waterSlosh)
        let fl = simd_length(f); if fl > 8 { f *= 8 / fl }
        return simd_transpose(m4) * f
    }
    func nsSloshKick(_ ns: NS4, _ dt: Double) {
        defer { nsPrevM4 = m4 }
        guard let R0 = nsPrevM4, dt > 1e-4 else { nsPrevW = simd_double4x4(0); ns.par.kick = simd_float4x4(0); return }
        let Q = simd_transpose(R0) * m4, Wn = (Q - simd_transpose(Q)) * (0.5 / dt)
        var dW = (Wn - nsPrevW) * waterSlosh
        // 急に大きく回した時に暴れないように（1 コマで 0.6 ラジアン／秒まで）
        var mx = 0.0; for c in 0..<4 { for r in 0..<4 { mx = max(mx, abs(dW[c][r])) } }
        if mx > 0.6 { dW = dW * (0.6 / mx) }
        nsPrevW = Wn
        ns.par.kick = simd_float4x4(SIMD4<Float>(dW[0]), SIMD4<Float>(dW[1]), SIMD4<Float>(dW[2]), SIMD4<Float>(dW[3]))
    }
    /// 遊ぶモード：重力は画面の下（今の向きから、箱の x・y・z・w の向きに直す）。押している間だけ、ふたの近くから注ぐ。開けた面から、こぼれていく
    func waterFreeTick(_ ns: NS4, _ dt: Double) {
        let H = Self.half, Vbox = 16 * pow(H, 4)
        waterT += dt; waterTT += dt
        // 画面の下（景色の −y）を、箱の向きへ：写す行列の逆向き（回転なので転置）で戻す
        // 重力の向き：画面の奥（景色の −w ＝ w の消失点へ）か、画面の下（景色の −y）。写す行列の逆向き（回転なので転置）で箱の向きへ戻す。
        //   画面の奥の時は、3D の回転（見る向き）では変わらない＝見回しても水は傾かない。w を傾ける回転（X‐W・Y‐W・Z‐W）でだけ傾く
        //   箱の −w（2）：重力はいつも箱の −w（+W の口 → −W の底。積分と同じ）。回しても変わらない
        let gb = waterGravMode == 2 ? nsLagGravity(dt) : simd_transpose(m4) * (waterGravMode == 0 ? SIMD4<Double>(0, 0, 0, -1) : SIMD4<Double>(0, -1, 0, 0)), gl = simd_length(gb)
        let gTarget = gl > 1e-9 ? gb / gl : SIMD4(0, 0, 0, -1)
        // 重力の向きは、目標へ なめらかに回る（1 秒に 2.5 ラジアンまで：90° で約 0.6 秒）：切りかえた時に水がガクッと跳ねず、新しい底へすーっと流れる
        var gdir = waterGDirInit ? waterGDir : gTarget; waterGDirInit = true
        let cs = max(-1, min(1, simd_dot(gdir, gTarget))), ang = acos(cs), stepA = 2.5 * dt
        if ang <= stepA { gdir = gTarget } else {
            var pp = gTarget - gdir * cs
            if simd_length(pp) < 1e-6 {                                         // 真反対：とちゅうの向きを 1 つ選ぶ
                for e in [SIMD4<Double>(1, 0, 0, 0), SIMD4<Double>(0, 1, 0, 0), SIMD4<Double>(0, 0, 1, 0)] { let q = e - gdir * simd_dot(e, gdir); if simd_length(q) > 0.3 { pp = q; break } }
            }
            pp /= simd_length(pp)
            gdir = gdir * cos(stepA) + pp * sin(stepA)
        }
        ns.par.gvec = SIMD4<Float>(gdir * waterG + nsShake(dt)); waterGDir = gdir; ns.par.vort = Float(waterVort)
        let Nf = Float(ns.N)
        // 画面の上から注ぐ：筋は重力の向きにまっすぐ落ちてきて、ふた（+W の胞）の「注ぐ場所」から入る。ふたが上を向いていない時は入れない
        // 入る所：注ぐ場所（x・y・z のずれ）から上（重力の逆）へ、今の水面のすぐ上まで（高い所から落とすと、9.8 で速くなって はねまくる）。
        //   水面の高さ（上向きの座標 c）：箱の上向きの広がり R ＝ H Σ|up| の中で、たまっている割合ぶん（ななめの時もだいたい）
        let up = -gdir, base = SIMD4<Double>(waterPourX, waterPourY, waterPourZ, 0) * (0.55 * H)
        var tMax = 9.0
        for a in 0..<4 where abs(up[a]) > 1e-6 { tMax = min(tMax, ((up[a] > 0 ? 1 : -1) * 0.78 * H - base[a]) / up[a]) }
        let R = H * (abs(up.x) + abs(up.y) + abs(up.z) + abs(up.w)), frac = max(0, min(1, ns.lastVol / Vbox))
        let c = -R + 2 * R * frac, tSurf = c + 0.14 * H - simd_dot(base, up)
        let E = base + up * max(0, min(tMax, tSurf))
        waterEntry4 = E
        let full = ns.lastVol >= 0.88 * Vbox                                // 満タン：これ以上は箱に入れない（口からあふれる）。空気が残っていないと、逆さにしても抜けない
        // 水を入れるのは、目標の量（押している時間 × 勢い）より遅れている時だけ（入れる所の玉が残りの空気を一気に水に変えて、満タンを越えないように）
        ns.par.jetOn = waterPourHold && !full && ns.lastVol < nsVTarget + 0.01 * Vbox ? 1 : 0
        ns.par.jetD = SIMD4<Float>(gdir); ns.par.pad2 = 1
        ns.par.jetC = SIMD4<Float>((E / (2 * H) + 0.5) * Double(ns.N))
        ns.par.jetR = Float(0.24 * (0.7 + 0.3 * waterPourRate)) / ns.par.dx; ns.par.jetV = Float(0.5 * waterPourRate)   // 静かに
        ns.par.topOpen = waterLidSet ? 1 : 0
        let holeOn = waterBottomSet && drainMode == 1
        ns.par.hole = holeOn ? Float(Self.wHOLE) * Nf / 2 : 0
        ns.par.open = waterBottomSet && !holeOn ? 1 : 0
        // 体積：押している間は、押している時間の分だけ確かに増やす（勢い × 時間）。開けた所から出ていく間は、減った分を目標に。閉じている時は保つ
        // 開いた口・底に、水が本当に触れている時だけ「出ていく」とみなす（触れていなければ、計算で少しずつ減る分を戻して、減らない）
        let n4 = ns.N
        func touches(_ l: Int) -> Bool {
            for k in 0..<n4 { for j in 0..<n4 { for i in 0..<n4 where ns.phiAt(i, j, k, l) < 0 { return true } } }
            return false
        }
        let leaking = (waterLidSet && touches(n4 - 1)) || (waterBottomSet && touches(0))
        // 目標を増やすのは、本当に水を入れている間だけ（満タンで止めた後も増やし続けると、行き場のない水を足し続けて圧力がたまり、流れが暴れる）
        if waterPourHold && !full { nsVTarget = min(0.88 * Vbox, max(nsVTarget, ns.lastVol) + 1.0 * waterPourRate * dt) }
        else if leaking { nsVTarget = min(nsVTarget, ns.lastVol) }
        nsVTarget = min(nsVTarget, ns.lastVol + 0.01 * Vbox)                // 目標が実際の量から離れすぎないように
        nsSloshKick(ns, dt)
        ns.tick(dt, target: nsVTarget < 1e-3 ? nil : nsVTarget, keepAir: true)
        let hN = max(-1, min(1, ns.lastVol / (8 * pow(H, 4)) - 1))
        if abs(waterH - hN) > 1e-5 { waterH = hN }
        let ph = waterPourHold ? 1 : (waterBottomSet && ns.lastVol > 1e-3 ? 4 : (ns.lastVol < 1e-3 ? 6 : 2))
        if waterPhase != ph { waterPhase = ph }
        waterPour = waterPourHold && waterCanPour ? Self.wTOP * H : -9
        // ふたの開け閉め（なめらかに）
        func step(_ x: Double, _ t: Double) -> Double { x + (t > x ? 1 : -1) * min(abs(t - x), dt * 2) }
        waterLid = step(waterLid, waterLidSet ? 1 : 0); waterBLid = step(waterBLid, waterBottomSet ? 1 : 0)
        waterOut = nil; _ = Vbox
    }
    /// 遊ぶモード：超立方体の向きを変える（Y‐W の角 ay：−90° でふた（+W）が真上、−55° くらいでビールジョッキのようにななめ）。なめらかに回す
    func waterFreeView(ay: Double, xz: Double, yz: Double) {
        cycling = false; stopSpins(); playing = false; loop = false; viewSel = -1
        pend = [0, 0, 0, 0, 0]
        let to: [Double] = [0, ay, 0, 0, xz, yz]
        tween = (cur6, to, 0, 1.2, projBlend, projBlend); presetPar = projBlend; presetHold = SIMD3(to[0], to[1], to[2])
    }
    /// 遊ぶモード：水を入れ直す（−1 空・0 半分・0.9 ほぼいっぱい）
    func waterFreeFill(_ h: Double) { if let ns = ns4Get() { ns.reset(level: Float(h)); nsVTarget = ns.lastVol; waterH = h } }
}

/// 景色の座標（y が上）を、描く側（z が上）へ
@inline(__always) private func gpuW(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    // 水の色（ウェブ版の LIQ_WATER）
    static let liqSurf = SIMD3<Double>(0.32, 0.78, 1), liqWall = SIMD3<Float>(0.1, 0.4, 0.95), liqMen = SIMD3<Float>(0.38, 0.78, 1)
    static let liqCornB = SIMD3<Float>(0.12, 0.42, 0.95), liqCornT = SIMD3<Float>(0.3, 0.7, 1), liqBot = SIMD3<Float>(0.05, 0.25, 0.7)
    static let liqVort = SIMD3<Float>(0.75, 0.92, 1)
    static let liqStream = SIMD3<Float>(0.3, 0.7, 1), liqBead = SIMD3<Float>(0.5, 0.85, 1), liqOut = SIMD3<Float>(0.12, 0.45, 0.98)

    /// 4 次元の水（立方体の窓は 3 次元の水）：線は rods に足し、面は三角形で返す
    func waterGeometry(_ rods: inout [TLRod], eye: SIMD3<Double>) -> [IntTriBatch] {
        let k = st.intVis
        guard k > 0.01, st.intMethod == 1 else { return [] }
        let H = OrigamiState.half, h = st.waterH, d = n - 1, G = OrigamiState.wGrid, k0 = k
        let thin = min(1, (h + 1) * 3)                                   // 水が薄い時は揺れも小さく
        var tris: [IntVert] = [], wtris: [IntVert] = []
        let real = st.waterReal
        /// リアルな水の板（3 つの点・面の向きは点の順から。kind：1 水面・0 壁と底）
        func wface(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ kind: Float, _ na: SIMD3<Double>? = nil, _ nb: SIMD3<Double>? = nil, _ nc: SIMD3<Double>? = nil) {
            var nn = simd_cross(b - a, c - a); let l = simd_length(nn); if l < 1e-12 { return }; nn /= l
            for (p, nv) in [(a, na ?? nn), (b, nb ?? nn), (c, nc ?? nn)] { wtris.append(IntVert(p: SIMD4(gpuW(p), 1), c: SIMD4(gpuW(nv), kind))) }
        }
        let A = Float(0.4 * k)                                            // 面の濃さ（ウェブ版の opacity 0.4）
        func P(_ u: [Double], _ w: Double) -> SIMD3<Double> { st.place(u.map { $0 * H } + [w], n).0 }
        // 排水口のくぼみ：吸い込む流れは中心ほど速く（4D は 3 方向から集まるので 1/r²）、速い所ほど水面が下がる（ベルヌーイ η ＝ −u²/2g ∝ 1/r⁴、真ん中は丸める）
        let vd = st.waterVD, HOLE = OrigamiState.wHOLE, hole = st.waterHoleNow, HR = HOLE * H
        func bern(_ u: [Double]) -> Double { let r = sqrt(u.reduce(0) { $0 + $1 * $1 }); return 0.8 * vd * H / (1 + pow(r / (0.45 * HOLE), 4)) }
        func surfW(_ u: [Double]) -> Double {
            let e = d == 3 ? st.swe.sample3(SIMD3(u[0], u[1], u[2])) : st.swe.sample2(SIMD2(u[0], u[1]))
            return max(-H, min(H, h * H + thin * e - (vd > 1e-4 ? bern(u) : 0)))
        }
        func rod(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Float>, _ L: Double = 1) { rods.append(TLRod(a: SIMD4(gpuW(a), 0), b: SIMD4(gpuW(b), 0), col: SIMD4(c, Float(L * k / 1.4)))) }
        func face(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ ca: SIMD3<Float>, _ cb: SIMD3<Float>, _ cc: SIMD3<Float>, _ al: Float = -1) {
            let aa = al < 0 ? A : al
            tris.append(IntVert(p: SIMD4(gpuW(a), 1), c: SIMD4(ca * aa, aa))); tris.append(IntVert(p: SIMD4(gpuW(b), 1), c: SIMD4(cb * aa, aa))); tris.append(IntVert(p: SIMD4(gpuW(c), 1), c: SIMD4(cc * aa, aa)))
        }
        /// 水面の色：フレネル反射（シュリック：水 R₀＝0.02）＋ 映る空 ＋ 照り返し。波の山は明るく、谷は暗く（ウェブ版の surfGridColors）
        func surfColor(_ p: SIMD3<Double>, _ nrm0: SIMD3<Double>, _ dd: Double) -> SIMD3<Float> {
            let vd = simd_normalize(eye - p)
            var nrm = nrm0, cosI = simd_dot(nrm, vd); if cosI < 0 { nrm = -nrm; cosI = -cosI }
            let Fr = 0.02 + 0.98 * pow(1 - min(1, cosI), 5)
            let ry = 2 * cosI * nrm.y - vd.y, tk = max(0, min(1, ry * 0.5 + 0.5))
            let sky = SIMD3<Double>(0.32, 0.38, 0.5) + (SIMD3<Double>(0.85, 0.9, 1.0) - SIMD3<Double>(0.32, 0.38, 0.5)) * tk
            let L = simd_normalize(vd + SIMD3(0.25, 0.55, 0.1)), hv = simd_normalize(L + vd)
            let sp = 2.2 * pow(max(0, simd_dot(nrm, hv)), 28) * (0.25 + Fr)
            let sh = max(0.55, min(1.5, 0.85 + 5 * dd))
            let c = Self.liqSurf * sh * (1 - Fr) + sky * Fr + sp
            return SIMD3<Float>(Float(c.x), Float(c.y), Float(c.z))
        }
        let nsW = d == 3 && st.waterNS ? st.ns4 : nil, nsOn = nsW != nil
        // 輪切り：左の窓に、4D の水を 1 枚切った 3D の水（本物の 4D の水の時）
        let sliceNS = st.waterSlice > 0 && st.waterNS ? st.ns4 : nil, sliceL = d == 2 && sliceNS != nil
        if let ns = nsW {
            // 本物の 4D の水：8 つの壁の胞の中の水の形（φ ＝ 0 の面を四面体で取り出したもの）を、今の向きで写す。面の向きは写した三角形から
            let mesh = ns.wallMesh(), m4 = st.m4, D = st.camW, pb = st.projBlend
            @inline(__always) func pj(_ q: SIMD4<Float>) -> SIMD3<Double> {   // st.place4 と同じ写し方（配列を作らずに速く）
                let v = m4 * SIMD4<Double>(Double(q.x), Double(q.y), Double(q.z), Double(q.w))
                let w = max(-D + 0.5, min(D - 0.5, v.w)), kk = 1 + (1 / (1 - w / D) - 1) * (1 - pb)
                return SIMD3(v.x * kk, v.y * kk, v.z * kk)
            }
            wtris.reserveCapacity(wtris.count + mesh.p.count)
            // なめらかな面の向き：点のまわりで水面に沿った 2 つの向きに少しずらして写し、その 2 本の外積（写し方が遠近でも正しい向き）
            @inline(__always) func vn(_ i: Int, _ P0: SIMD3<Double>) -> SIMD3<Double>? {
                let a1 = mesh.t1[i]; if a1 == .zero { return nil }
                let q = mesh.p[i], e: Float = 0.03, n = simd_cross(pj(q + a1 * e) - P0, pj(q + mesh.t2[i] * e) - P0), l = simd_length(n)
                return l > 1e-12 ? n / l : nil
            }
            let smoothN = mesh.t1.count == mesh.p.count
            for t in 0..<mesh.kind.count {
                let a = pj(mesh.p[3 * t]), b = pj(mesh.p[3 * t + 1]), c = pj(mesh.p[3 * t + 2]), kd = mesh.kind[t]
                if real && smoothN && kd > 0.5, let na = vn(3 * t, a), let nb = vn(3 * t + 1, b), let nc = vn(3 * t + 2, c) {
                    let fn = simd_cross(b - a, c - a)                          // 向きをそろえる（三角形の向きと同じ側に）
                    wface(a, b, c, kd, simd_dot(na, fn) < 0 ? -na : na, simd_dot(nb, fn) < 0 ? -nb : nb, simd_dot(nc, fn) < 0 ? -nc : nc)
                } else if real { wface(a, b, c, kd) }
                else { let col = kd > 0.5 ? Self.liqMen * 0.85 : Self.liqWall; face(a, b, c, col, col, col) }
            }
            // 輪切りの切り口：軸 a ＝ c の 3D の立方体（残りの 3 つの向きが ±H）を金色の線で
            if st.waterSlice > 0 {
                let a = st.waterSlice - 1, kk = max(0, min(ns.N - 1, Int(((st.waterSlicePos + 1) / 2 * Double(ns.N)).rounded(.down))))
                let cv = -H + (Double(kk) + 0.5) * Double(ns.par.dx), oth = (0..<4).filter { $0 != a }
                func cor(_ b: Int) -> SIMD3<Double> { var q = [0.0, 0, 0, 0]; q[a] = cv; for (j, ax) in oth.enumerated() { q[ax] = (b >> j) & 1 == 1 ? H : -H }; return st.place(q, 4).0 }
                for b in 0..<8 { for j in 0..<3 where (b >> j) & 1 == 0 { rod(cor(b), cor(b | 1 << j), SIMD3(1, 0.8, 0.3), 1.2) } }
            }
            // 遊ぶモード：開けた面（ふた +W・底 −W）に水が来ていたら、外へこぼれ落ちる筋（景色の下向き）
            if st.waterFree {
                let n4 = ns.N, T = st.waterTT, dxw = Double(ns.par.dx)
                for (open, l, wq) in [(st.waterLidSet, n4 - 1, H), (st.waterBottomSet, 0, -H)] where open {
                    var cnt = 0
                    for k in stride(from: 1, to: n4, by: 3) { for j in stride(from: 1, to: n4, by: 3) { for i in stride(from: 1, to: n4, by: 3) where ns.phiAt(i, j, k, l) < 0 && cnt < 160 {
                        cnt += 1
                        let x = -H + (Double(i) + 0.5) * dxw, y = -H + (Double(j) + 0.5) * dxw, z = -H + (Double(k) + 0.5) * dxw
                        // こぼれた水は重力の向き（4D）へ落ちていく（画面の奥なら、消失点へ吸いこまれるように）
                        let g4 = st.waterGDir, hsh = sin(Double(i * 73 + j * 37 + k * 11)) * 43758.5453
                        let f = (T * 1.6 + hsh - floor(hsh)).truncatingRemainder(dividingBy: 1), s0 = 0.9 * f * f, s1 = 0.9 * min(1, f + 0.12) * min(1, f + 0.12)
                        let q0 = SIMD4(x, y, z, wq) + g4 * s0, q1 = SIMD4(x, y, z, wq) + g4 * s1
                        rod(st.place([q0.x, q0.y, q0.z, q0.w], 4).0, st.place([q1.x, q1.y, q1.z, q1.w], 4).0, Self.liqStream, 0.9 * (1 - f))
                    } } }
                }
            }
        } else if sliceL, let ns = sliceNS {
            // 左の窓：切った 3D の水。残りの空間の 2 つの向き → 左の x・y、w → 左の z（左の立方体の上下）
            let a = st.waterSlice - 1, k = max(0, min(ns.N - 1, Int(((st.waterSlicePos + 1) / 2 * Double(ns.N)).rounded(.down))))
            let mesh = ns.sliceMesh(axis: a, index: k), oth = (0..<3).filter { $0 != a }
            func L(_ q: SIMD4<Float>) -> SIMD3<Double> { P([Double(q[oth[0]]) / H, Double(q[oth[1]]) / H], Double(q.w)) }
            for t in 0..<mesh.kind.count {
                let A0 = L(mesh.p[3 * t]), B0 = L(mesh.p[3 * t + 1]), C0 = L(mesh.p[3 * t + 2])
                if real { wface(A0, B0, C0, mesh.kind[t]) } else { let col = mesh.kind[t] > 0.5 ? Self.liqMen * 0.85 : Self.liqWall; face(A0, B0, C0, col, col, col, Float(0.3 * k0)) }
            }
        } else if h > -0.999 {
            if d == 3 {
                // 水面の立方体（w ＝ h ＋ 揺れ）：6 面を G×G に分けて。色は頂点ごと（面の向きは隣の点から）
                for ax in 0..<3 { for sg in [-1.0, 1.0] {
                    let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                    if real {
                        // リアルな水面：細かく（24×24）、点ごとの面の向きで（なめらかな光）。網目の線は描かない
                        let G2 = 24
                        func U2(_ i: Int, _ j: Int) -> [Double] { var u = [0.0, 0, 0]; u[ax] = sg; u[a1] = -1 + 2 * Double(i) / Double(G2); u[a2] = -1 + 2 * Double(j) / Double(G2); return u }
                        var V: [[SIMD3<Double>]] = []
                        for i in 0...G2 { V.append((0...G2).map { j in let u = U2(i, j); return P(u, surfW(u)) }) }
                        var Nn: [[SIMD3<Double>]] = []
                        for i in 0...G2 { Nn.append((0...G2).map { j in
                            let a = V[min(G2, i + 1)][j] - V[max(0, i - 1)][j], b = V[i][min(G2, j + 1)] - V[i][max(0, j - 1)]
                            let nn = simd_cross(a, b), nl = simd_length(nn); return nl > 1e-12 ? nn / nl : SIMD3(0, 0, 1)
                        }) }
                        for i in 0..<G2 { for j in 0..<G2 {
                            wface(V[i][j], V[i + 1][j], V[i + 1][j + 1], 1, Nn[i][j], Nn[i + 1][j], Nn[i + 1][j + 1])
                            wface(V[i][j], V[i + 1][j + 1], V[i][j + 1], 1, Nn[i][j], Nn[i + 1][j + 1], Nn[i][j + 1])
                        } }
                        continue
                    }
                    func U(_ i: Int, _ j: Int) -> [Double] { var u = [0.0, 0, 0]; u[ax] = sg; u[a1] = -1 + 2 * Double(i) / Double(G); u[a2] = -1 + 2 * Double(j) / Double(G); return u }
                    var V: [[SIMD3<Double>]] = [], Dd: [[Double]] = []
                    for i in 0...G { var row: [SIMD3<Double>] = [], drow: [Double] = []; for j in 0...G { let u = U(i, j), w = surfW(u); row.append(P(u, w)); drow.append(w / H - h) }; V.append(row); Dd.append(drow) }
                    var C: [[SIMD3<Float>]] = []
                    for i in 0...G { var row: [SIMD3<Float>] = []; for j in 0...G {
                        let a = V[min(G, i + 1)][j] - V[max(0, i - 1)][j], b = V[i][min(G, j + 1)] - V[i][max(0, j - 1)]
                        let nn = simd_cross(a, b), nl = simd_length(nn)
                        row.append(surfColor(V[i][j], nl > 1e-12 ? nn / nl : SIMD3(0, 0, 1), Dd[i][j]))
                    }; C.append(row) }
                    for i in 0..<G { for j in 0..<G {
                        face(V[i][j], V[i + 1][j], V[i + 1][j + 1], C[i][j], C[i + 1][j], C[i + 1][j + 1])
                        face(V[i][j], V[i + 1][j + 1], V[i][j + 1], C[i][j], C[i + 1][j + 1], C[i][j + 1])
                    } }
                    // 水面の網目（うすい青、2 つおき）
                    let gc = SIMD3<Float>(Float(Self.liqSurf.x), Float(Self.liqSurf.y), Float(Self.liqSurf.z)) * 0.55
                    for i in stride(from: 0, through: G, by: 2) { for j in 0..<G { rod(V[i][j], V[i][j + 1], gc, 0.8); rod(V[j][i], V[j + 1][i], gc, 0.8) } }
                } }
                // 壁に触れている面：立方体の 12 本の辺 × w（底 −H から水面まで）と、水際の線
                for ax in 0..<3 { for s1 in [-1.0, 1.0] { for s2 in [-1.0, 1.0] {
                    let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                    func U(_ i: Int) -> [Double] { var u = [0.0, 0, 0]; u[ax] = -1 + 2 * Double(i) / Double(G); u[a1] = s1; u[a2] = s2; return u }
                    for i in 0..<G {
                        let ua = U(i), ub = U(i + 1), wa = surfW(ua), wb = surfW(ub)
                        let A0 = P(ua, -H), B0 = P(ub, -H), A1 = P(ua, wa), B1 = P(ub, wb)
                        if real { wface(A0, B0, B1, 0); wface(A0, B1, A1, 0); rod(A1, B1, Self.liqMen, 0.6) }
                        else { face(A0, B0, B1, Self.liqWall, Self.liqWall, Self.liqWall); face(A0, B1, A1, Self.liqWall, Self.liqWall, Self.liqWall); rod(A1, B1, Self.liqMen) }
                    }
                } } }
                // 角の縦の線（w の方向）と、底の立方体（w ＝ −1）
                for v in 0..<8 {
                    let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1]
                    rod(P(u, -H), P(u, surfW(u)), (Self.liqCornB + Self.liqCornT) / 2)
                }
                if real {
                    for ax in 0..<3 { for sg in [-1.0, 1.0] {
                        let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                        func Ub(_ s: Double, _ t: Double) -> [Double] { var u = [0.0, 0, 0]; u[ax] = sg; u[a1] = s; u[a2] = t; return u }
                        let q = [P(Ub(-1, -1), -H), P(Ub(1, -1), -H), P(Ub(1, 1), -H), P(Ub(-1, 1), -H)]
                        wface(q[0], q[1], q[2], 0); wface(q[0], q[2], q[3], 0)
                    } }
                } else { cubeFaces(-H, Self.liqBot, A, P, &tris) }
            } else {
                // 3 次元の水：水面は正方形（z ＝ h ＋ 揺れ）
                let G = real ? 32 : G
                var V: [[SIMD3<Double>]] = [], Dd: [[Double]] = []
                for i in 0...G { var row: [SIMD3<Double>] = [], drow: [Double] = []; for j in 0...G { let u = [-1 + 2 * Double(i) / Double(G), -1 + 2 * Double(j) / Double(G)], w = surfW(u); row.append(P(u, w)); drow.append(w / H - h) }; V.append(row); Dd.append(drow) }
                var C: [[SIMD3<Float>]] = []
                for i in 0...G { var row: [SIMD3<Float>] = []; for j in 0...G {
                    let a = V[min(G, i + 1)][j] - V[max(0, i - 1)][j], b = V[i][min(G, j + 1)] - V[i][max(0, j - 1)]
                    let nn = simd_cross(a, b), nl = simd_length(nn)
                    row.append(surfColor(V[i][j], nl > 1e-12 ? nn / nl : SIMD3(0, 0, 1), Dd[i][j]))
                }; C.append(row) }
                for i in 0..<G { for j in 0..<G {
                    if real {
                        func nAt(_ x: Int, _ y: Int) -> SIMD3<Double> { let a = V[min(G, x + 1)][y] - V[max(0, x - 1)][y], b = V[x][min(G, y + 1)] - V[x][max(0, y - 1)]; let nn = simd_cross(a, b), nl = simd_length(nn); return nl > 1e-12 ? nn / nl : SIMD3(0, 0, 1) }
                        wface(V[i][j], V[i + 1][j], V[i + 1][j + 1], 1, nAt(i, j), nAt(i + 1, j), nAt(i + 1, j + 1))
                        wface(V[i][j], V[i + 1][j + 1], V[i][j + 1], 1, nAt(i, j), nAt(i + 1, j + 1), nAt(i, j + 1))
                        continue
                    }
                    face(V[i][j], V[i + 1][j], V[i + 1][j + 1], C[i][j], C[i + 1][j], C[i + 1][j + 1], Float(0.3 * k))
                    face(V[i][j], V[i + 1][j + 1], V[i][j + 1], C[i][j], C[i + 1][j + 1], C[i][j + 1], Float(0.3 * k))
                } }
                // 壁（正方形の 4 本の辺 × z）・水際の線・角の縦の線・底の正方形
                for ax in 0..<2 { for s1 in [-1.0, 1.0] {
                    func U(_ i: Int) -> [Double] { var u = [0.0, 0]; u[ax] = -1 + 2 * Double(i) / Double(G); u[1 - ax] = s1; return u }
                    for i in 0..<G {
                        let ua = U(i), ub = U(i + 1), wa = surfW(ua), wb = surfW(ub)
                        let A0 = P(ua, -H), B0 = P(ub, -H), A1 = P(ua, wa), B1 = P(ub, wb)
                        if real { wface(A0, B0, B1, 0); wface(A0, B1, A1, 0); rod(A1, B1, Self.liqMen, 0.6) }
                        else { face(A0, B0, B1, Self.liqWall, Self.liqWall, Self.liqWall, Float(0.3 * k)); face(A0, B1, A1, Self.liqWall, Self.liqWall, Self.liqWall, Float(0.3 * k)); rod(A1, B1, Self.liqMen) }
                    }
                } }
                for v in 0..<4 { let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1]; rod(P(u, -H), P(u, surfW(u)), (Self.liqCornB + Self.liqCornT) / 2) }
                let b0 = P([-1, -1], -H), b1 = P([1, -1], -H), b2 = P([1, 1], -H), b3 = P([-1, 1], -H)
                if real { wface(b0, b1, b2, 0); wface(b0, b2, b3, 0) }
                else { face(b0, b1, b2, Self.liqBot, Self.liqBot, Self.liqBot, Float(0.3 * k)); face(b0, b2, b3, Self.liqBot, Self.liqBot, Self.liqBot, Float(0.3 * k)) }
            }
        }
        // 水の筋：ふたの先（w ＝ TOP×H）から水面まで、w の方向に落ちる（止めた後は、しっぽが落ちていく）。粒は g で加速しながら落ちる
        let us = st.waterFree && nsOn ? SIMD3(st.waterPourX, st.waterPourY, st.waterPourZ) : OrigamiState.wUS, top = st.waterPour
        let su: [Double] = d == 3 ? [us.x, us.y, us.z] : [us.x, us.y]
        let free = st.waterFree && nsOn
        let surfS = free ? H * 0.85 : h > -0.999 ? (nsW.map { min($0.surfaceWorld(SIMD3(us.x, us.y, us.z)), h * H + 0.08 * H) } ?? surfW(su)) : -H   // 本物の 4D：柱の水面と平均の水位の低いほう（入れたばかりの水に止まって見えないように）   // 遊ぶモード：筋はふたの近く（水を入れる所）まで
        if top > surfS && !sliceL {
            let T = st.waterTT
            if real && free {
                // 遊ぶモード：画面の上から（重力の向きにまっすぐ）落ちてきて、ふた（+W）の注ぐ場所に入る透明な水の柱
                let g = st.waterGDir, E4 = st.waterEntry4, L = 1.7, MS = 24, K = 12
                var rings: [[(SIMD3<Double>, SIMD3<Double>)]] = []
                for m in 0...MS {
                    let f = Double(m) / Double(MS), q = E4 - g * (L * (1 - f)), C = st.place([q.x, q.y, q.z, q.w], 4).0
                    let q2 = q + g * 0.02, Cn = st.place([q2.x, q2.y, q2.z, q2.w], 4).0, Tg = simd_normalize(Cn - C)
                    let v = sqrt(0.36 + 2 * st.waterG * L * f), rr = 0.05 * pow(0.6 / v, 1.0 / 3.0)
                    let hlp: SIMD3<Double> = abs(Tg.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), N1 = simd_normalize(simd_cross(Tg, hlp)), N2 = simd_cross(Tg, N1)
                    rings.append((0..<K).map { j in let th = 2 * Double.pi * Double(j) / Double(K), nv = N1 * cos(th) + N2 * sin(th); return (C + nv * rr, nv) })
                }
                for m in 0..<MS { for j in 0..<K {
                    let a = rings[m][j], b = rings[m][(j + 1) % K], c = rings[m + 1][(j + 1) % K], e = rings[m + 1][j]
                    wface(a.0, b.0, c.0, 1, a.1, b.1, c.1); wface(a.0, c.0, e.0, 1, a.1, c.1, e.1)
                } }
            } else if real {
                // 透明な水の柱：上（ふたの先）から水面まで、w の向きにまっすぐ落ちる。いちばん手前に描く（水の三角形は奥行きで隠れない）ので、
                //   横の胞の面に重なって見えても切れない＝ぶつかっていない。落ちるほど速くなって細くなる（4 次元では切り口が 3 次元の玉なので、太さ ∝ 速さ^(−1/3)）
                let MS = 30, K = 12, v0 = 0.6, r0 = 0.05
                var rings: [[(SIMD3<Double>, SIMD3<Double>)]] = []
                for m in 0...MS {
                    let f = Double(m) / Double(MS), w = top + (surfS - top) * f, v = sqrt(v0 * v0 + 2 * OrigamiState.wG * max(0, top - w))
                    var u = su; u[0] += 0.006 * sin(T * 14 + f * 9); if d == 3 { u[2] += 0.005 * sin(T * 11 + f * 7 + 1) } else { u[1] += 0.005 * sin(T * 11 + f * 7 + 1) }
                    let C = P(u, w), Cn = P(u, w - 0.02), Tg = simd_normalize(Cn - C)
                    var ux = u; ux[0] += 0.1
                    let sc = simd_length(P(ux, w) - C) / (0.1 * H), rr = r0 * pow(v0 / v, 1.0 / 3.0) * sc   // 写した時の大きさ（遠近）に合わせて
                    let hlp: SIMD3<Double> = abs(Tg.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), N1 = simd_normalize(simd_cross(Tg, hlp)), N2 = simd_cross(Tg, N1)
                    rings.append((0..<K).map { j in let th = 2 * Double.pi * Double(j) / Double(K), nv = N1 * cos(th) + N2 * sin(th); return (C + nv * rr, nv) })
                }
                for m in 0..<MS { for j in 0..<K {
                    let a = rings[m][j], b = rings[m][(j + 1) % K], c = rings[m + 1][(j + 1) % K], e = rings[m + 1][j]
                    wface(a.0, b.0, c.0, 1, a.1, b.1, c.1); wface(a.0, c.0, e.0, 1, a.1, c.1, e.1)
                } }
            } else {
            for (n, o) in [(0, SIMD2(0.0, 0.0)), (1, SIMD2(0.025, 0.01)), (2, SIMD2(-0.02, 0.02)), (3, SIMD2(0.01, -0.025))] {
                let a = n == 0 ? 1.0 : 0.6, M = 10
                for m in 0..<M {
                    let w0 = top + (surfS - top) * Double(m) / Double(M), w1 = top + (surfS - top) * Double(m + 1) / Double(M)
                    let wob = 0.012 * sin(T * 20 + Double(m) * 1.7 + Double(n))
                    var pa = su, pb = su; pa[0] += o.x + wob; pb[0] += o.x - wob; if d == 3 { pa[2] += o.y; pb[2] += o.y }
                    rod(P(pa, w0), P(pb, w1), Self.liqStream, a)
                }
            }
            }
            // 突き抜けの印：筋（4D では w の向きのまっすぐな線）が、写った面（超立方体の 24 枚の正方形）と重なって見える所に、うすく光る輪。
            //   4 次元では、そこに壁は無い（写っているだけ）。本当の入口は、ふた（+W の胞）の中の 1 点だけ（金の輪）
            if real && d == 3 && !free {
                let S0 = P(su, top), S1 = P(su, surfS), SD = S1 - S0, T = st.waterTT
                func P4(_ q: [Double]) -> SIMD3<Double> { st.place(q, 4).0 }
                func ring(_ C: SIMD3<Double>, _ nrm: SIMD3<Double>, _ r: Double, _ col: SIMD3<Float>, _ br: Double) {
                    let hlp: SIMD3<Double> = abs(nrm.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), e1 = simd_normalize(simd_cross(nrm, hlp)), e2 = simd_cross(nrm, e1), K = 24
                    for j in 0..<K { let a0 = 2 * Double.pi * Double(j) / Double(K), a1 = 2 * Double.pi * Double(j + 1) / Double(K); rod(C + (e1 * cos(a0) + e2 * sin(a0)) * r, C + (e1 * cos(a1) + e2 * sin(a1)) * r, col, br) }
                }
                var ux = su; ux[0] += 0.1
                let scl = simd_length(P(ux, surfS) - S1) / (0.1 * H)
                for a in 0..<4 { for b in (a + 1)..<4 {
                    let o = (0..<4).filter { $0 != a && $0 != b }
                    for so in 0..<4 {
                        func corner(_ sa: Double, _ sb: Double) -> SIMD3<Double> { var q = [0.0, 0, 0, 0]; q[a] = sa * H; q[b] = sb * H; q[o[0]] = (so & 1 == 0 ? -1 : 1) * H; q[o[1]] = (so & 2 == 0 ? -1 : 1) * H; return P4(q) }
                        let A = corner(-1, -1), B = corner(1, -1), C = corner(1, 1), D = corner(-1, 1)
                        let nrm0 = simd_cross(B - A, D - A), nl = simd_length(nrm0); if nl < 1e-9 { continue }
                        let nrm = nrm0 / nl, den = simd_dot(nrm, SD); if abs(den) < 1e-9 { continue }
                        let t = simd_dot(nrm, A - S0) / den; if t <= 0.02 || t >= 0.98 { continue }
                        let X = S0 + SD * t
                        func inTri(_ p: SIMD3<Double>, _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>) -> Bool {
                            let v0 = c - a, v1 = b - a, v2 = p - a, d00 = simd_dot(v0, v0), d01 = simd_dot(v0, v1), d11 = simd_dot(v1, v1), d20 = simd_dot(v2, v0), d21 = simd_dot(v2, v1)
                            let dn = d00 * d11 - d01 * d01; if abs(dn) < 1e-14 { return false }
                            let u = (d11 * d20 - d01 * d21) / dn, v = (d00 * d21 - d01 * d20) / dn; return u >= 0 && v >= 0 && u + v <= 1
                        }
                        if !(inTri(X, A, B, C) || inTri(X, A, C, D)) { continue }
                        let pulse = 0.65 + 0.35 * sin(T * 4 + t * 9)
                        ring(X, nrm, 0.075 * scl, SIMD3(0.6, 0.95, 1), 0.9 * pulse); ring(X, nrm, 0.045 * scl, SIMD3(0.6, 0.95, 1), 0.5 * pulse)
                    }
                } }
                // 本当の入口：ふた（+W の胞）の中の 1 点（筋に垂直な金の輪）
                if top > H && surfS < H { ring(P(su, H), simd_normalize(SD), 0.09 * scl, SIMD3(1, 0.82, 0.35), 1.2) }
            }
            // 道しるべ：筋の通り道（ふた ＋W の点 → 底 −W の点、w の向きのまっすぐな点線）と、突き当たりの底の印（内の小さい立方体の中の小さな立方体）。
            //   横の胞に重なって見えても、4 次元では何もない所を通って、底の壁まで行けるのがわかるように
            if d == 3 && st.waterPhase <= 1 {
                let gc = SIMD3<Float>(0.8, 0.86, 1), DN = 18
                for q in 0..<DN where q % 2 == 0 {
                    let w0 = H - 2 * H * Double(q) / Double(DN), w1 = H - 2 * H * Double(q + 1) / Double(DN)
                    rod(P(su, w0), P(su, w1), gc, 0.35)
                }
                let rr = 0.07, bc = simd_min(SIMD3<Float>(repeating: 1), OrigamiState.rgb(st.cellColors(n)[0]) * 1.25 + 0.15)
                for wq in [-H, H] {
                    let cs3: [[Double]] = (0..<8).map { v in [su[0] + (v & 1 != 0 ? rr : -rr), su[1] + (v & 2 != 0 ? rr : -rr), su[2] + (v & 4 != 0 ? rr : -rr)] }
                    for i in 0..<8 { for j in 0..<3 where i & (1 << j) == 0 { rod(P(cs3[i], wq), P(cs3[i | 1 << j], wq), wq < 0 ? bc : gc, wq < 0 ? 1.1 : 0.5) } }
                }
            }
            // しぶき：筋が水面に当たる所から、小さな粒が跳ねて（水面に沿って広がりながら w の上へ）、g で落ちて戻る
            if real && h > -0.97 && !free {
                let SN = 14, life = 0.55
                for s in 0..<SN {
                    let ph = T / life + Double(s) / Double(SN), cyc = floor(ph), tau = (ph - cyc) * life
                    func hs(_ q: Double) -> Double { let x = sin(q * 12.9898 + cyc * 78.233 + Double(s) * 37.719) * 43758.5453; return x - floor(x) }
                    let sp = 0.25 + 0.35 * hs(1), up = (0.55 + 0.6 * hs(2)) * H * 1.6
                    var dir = d == 3 ? SIMD3(hs(3) - 0.5, hs(4) - 0.5, hs(5) - 0.5) : SIMD3(hs(3) - 0.5, hs(4) - 0.5, 0)
                    dir /= max(1e-6, simd_length(dir))
                    func at(_ t: Double) -> ([Double], Double) {
                        var u = su; for a in 0..<su.count { u[a] = max(-1, min(1, u[a] + dir[a] * sp * t / H)) }
                        return (u, surfS + up * t - 0.5 * OrigamiState.wG * t * t)
                    }
                    let (ua, wa) = at(tau), (ub, wb) = at(max(0, tau - 0.035))
                    if wa < surfS - 0.01 { continue }
                    rod(P(ua, wa), P(ub, wb), SIMD3<Float>(0.85, 0.95, 1), 1.5 * (1 - 0.5 * tau / life))
                }
            }
            let tf = sqrt(2 * max(1e-3, top - surfS) / OrigamiState.wG)
            for m in 0..<7 {
                let tau = ((T / tf + Double(m) / 7).truncatingRemainder(dividingBy: 1)) * tf, w = top - 0.5 * OrigamiState.wG * tau * tau
                rod(P(su, w + 0.05 * H), P(su, w - 0.05 * H), Self.liqBead)
            }
        }
        // 底から流れ出る水のかたまり（底を全部開けた時。立方体（正方形）× w の箱）
        // ---- 出ていく水 ----
        //   リアルな水の時：排水口からは、落ちるほど速く細くなる透明な水の柱（4D の切り口は立方体なので太さ ∝ 速さ^(−1/3)、左の窓は正方形で ^(−1/2)）。
        //   本物の 4D の水なら、計算で穴から実際に出ている量に合わせて太さが変わり、ちょろちょろになると先がしずくになる。底を全部開けた時は、かたまりのまま落ちる水の箱
        let nsO = st.waterNS ? st.ns4 : nil, gO = st.waterFree ? st.waterG : OrigamiState.wG
        let holeOut = hole || (st.waterFree && st.waterBottomSet && st.drainMode == 1)
        let qNS = nsO?.lastOutflow ?? 0
        let outNow = st.waterOut != nil || (nsO != nil && qNS > 2e-3 && (holeOut || (st.waterFree && st.waterBottomSet)))
        if real && outNow && holeOut {
            let dimC = Double(d), A0 = pow(2 * HOLE * H, dimC), depth = max(0.02, (h + 1) * H), vTor = max(0.4, sqrt(2 * gO * depth))
            let Q = nsO != nil && d == 3 ? qNS : (st.waterOut != nil ? A0 * vTor : 0)
            if Q > 1e-4 {
                let fill = min(1, Q / (A0 * vTor)), v0 = vTor, s0 = HOLE * pow(fill, 1 / dimC)       // 出口の太さ：少ししか出ていない時は細い
                let FL = 1.5 * H, bottom = st.waterOut.map { max($0.y, -H - FL) } ?? (-H - FL)
                let MS = 22, T = st.waterTT
                let cs: [[Double]] = d == 3 ? (0..<8).map { v in [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1] } : (0..<4).map { v in [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1] }
                var edges: [(Int, Int)] = []
                for (i, a) in cs.enumerated() { for (j, b) in cs.enumerated() where j > i && zip(a, b).filter({ $0 != $1 }).count == 1 { edges.append((i, j)) } }
                let solidL = (-H - bottom) * (fill > 0.35 ? 1 : 0.55)                // ちょろちょろの時は途中からしずくに
                func ring(_ zd: Double) -> [SIMD3<Double>] {                         // 穴から zd 落ちた所の切り口の角
                    let v = sqrt(v0 * v0 + 2 * gO * zd), sc = s0 * pow(v0 / v, 1 / dimC) * (1 + 0.07 * sin(T * 9 + zd * 13))
                    let ox = 0.025 * sin(T * 6.3 + zd * 9), oy = 0.025 * cos(T * 5.1 + zd * 7)
                    return cs.map { c in var u = c.map { $0 * sc }; u[0] += ox; u[1] += oy; return P(u, -H - zd) }
                }
                var prev = ring(0)
                for m in 1...MS {
                    let zd = solidL * Double(m) / Double(MS), cur = ring(zd)
                    for (i, j) in edges { wface(prev[i], prev[j], cur[j], 1); wface(prev[i], cur[j], cur[i], 1) }
                    prev = cur
                }
                // 先のしずく：柱の先から下へ、g で速くなりながら
                for q in 0..<14 {
                    let f = (T * 1.7 + Double(q) / 14).truncatingRemainder(dividingBy: 1), zd = solidL + ((-H - bottom) - solidL) * f * f + 0.02
                    var u = [sin(Double(q) * 2.3) * s0 * 0.7, cos(Double(q) * 1.9) * s0 * 0.7]; if d == 3 { u.append(sin(Double(q) * 3.1) * s0 * 0.7) }
                    rod(P(u, -H - zd), P(u, -H - zd - 0.06 * H), SIMD3(0.75, 0.92, 1), 1.3 * (1 - f))
                }
            }
        } else if real, let out = st.waterOut, out.x > out.y + 1e-4 {
            // 底を全部開けた時：かたまりのまま落ちる水の箱（リアルな水で）。立方体（正方形）の辺 × w の面と、下の面
            let cs: [[Double]] = d == 3 ? (0..<8).map { v in [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1] } : (0..<4).map { v in [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1] }
            for (i, a) in cs.enumerated() { for (j, b) in cs.enumerated() where j > i && zip(a, b).filter({ $0 != $1 }).count == 1 {
                wface(P(a, out.x), P(b, out.x), P(b, out.y), 1); wface(P(a, out.x), P(b, out.y), P(a, out.y), 1)
            } }
            if d == 3 {
                for ax in 0..<3 { for sg in [-1.0, 1.0] {
                    let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                    func Ub(_ p: Double, _ q: Double) -> [Double] { var u = [0.0, 0, 0]; u[ax] = sg; u[a1] = p; u[a2] = q; return u }
                    let q4 = [P(Ub(-1, -1), out.y), P(Ub(1, -1), out.y), P(Ub(1, 1), out.y), P(Ub(-1, 1), out.y)]
                    wface(q4[0], q4[1], q4[2], 1); wface(q4[0], q4[2], q4[3], 1)
                } }
            } else {
                let b0 = P([-1, -1], out.y), b1 = P([1, -1], out.y), b2 = P([1, 1], out.y), b3 = P([-1, 1], out.y)
                wface(b0, b1, b2, 1); wface(b0, b2, b3, 1)
            }
        } else if !real {
        if let out = st.waterOut, out.x > out.y + 1e-4, hole {
                // 排水口から出る水の柱：小さな立方体（正方形）× w
                let R = HOLE, al = Float(0.32 * k)
                let cs: [[Double]] = d == 3 ? (0..<8).map { v in [v & 1 != 0 ? R : -R, v & 2 != 0 ? R : -R, v & 4 != 0 ? R : -R] } : (0..<4).map { v in [v & 1 != 0 ? R : -R, v & 2 != 0 ? R : -R] }
                for c in cs { rod(P(c, out.x), P(c, out.y), Self.liqOut) }
                for (i, a) in cs.enumerated() { for (j, b) in cs.enumerated() where j > i {
                    if zip(a, b).filter({ $0 != $1 }).count != 1 { continue }                       // 立方体（正方形）の辺 × w の面
                    face(P(a, out.x), P(b, out.x), P(b, out.y), Self.liqOut, Self.liqOut, Self.liqOut, al); face(P(a, out.x), P(b, out.y), P(a, out.y), Self.liqOut, Self.liqOut, Self.liqOut, al)
                } }
                for q in 0..<8 {   // 柱の中を落ちていく筋（g で速くなる）
                    let f = (st.waterTT * 1.3 + Double(q) / 8).truncatingRemainder(dividingBy: 1), w = out.x + (out.y - out.x) * f * f
                    var u = [cos(Double(q) * 2.4) * R * 0.6, sin(Double(q) * 1.7) * R * 0.6]; if d == 3 { u.append(sin(Double(q) * 2.4) * R * 0.6) }
                    rod(P(u, w), P(u, max(out.y, w - 0.12 * H)), Self.liqStream, 0.8)
                }
            } else if let out = st.waterOut, out.x > out.y + 1e-4 {
                if d == 3 {
                    cubeFaces(out.y, Self.liqOut, Float(0.3 * k), P, &tris)
                    for v in 0..<8 { let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1]; rod(P(u, out.x), P(u, out.y), Self.liqOut) }
                } else {
                    for v in 0..<4 { let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1]; rod(P(u, out.x), P(u, out.y), Self.liqOut) }
                    let b0 = P([-1, -1], out.y), b1 = P([1, -1], out.y), b2 = P([1, 1], out.y), b3 = P([-1, 1], out.y)
                    face(b0, b1, b2, Self.liqOut, Self.liqOut, Self.liqOut, Float(0.3 * k)); face(b0, b2, b3, Self.liqOut, Self.liqOut, Self.liqOut, Float(0.3 * k))
                }
            }
        }
        // ---- 排水口（ウェブ版と同じ）----
        let flowing = hole && (st.waterPhase == 4 || (st.holesOpen && st.waterPhase == 1)), T = st.waterTT
        let botC = OrigamiState.rgb(st.cellColors(n)[0]), rimC = simd_min(SIMD3<Float>(repeating: 1), botC * 1.25 + 0.15)
        if d == 3 && (hole || st.holesBuilt) && h > -0.99 && !nsOn {
            // 排水口の真上の水の柱：4 次元の水は外側の皮しか描けないので、床の真ん中の上の水は見えない。穴の上の柱だけ描いて、水が排水口まで来ているのを見せる
            let R = HOLE, cW = Self.liqWall * 0.75, cTop = Self.liqMen * 0.8
            for ax in 0..<3 { for s1 in [-1.0, 1.0] { for s2 in [-1.0, 1.0] {
                let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                var A = [0.0, 0, 0], B = [0.0, 0, 0]; A[ax] = -R; B[ax] = R; A[a1] = s1 * R; B[a1] = s1 * R; A[a2] = s2 * R; B[a2] = s2 * R
                let wa = surfW(A), wb = surfW(B), q0 = P(A, -H), q1 = P(B, -H), q2 = P(B, wb), q3 = P(A, wa)
                if real { wface(q0, q1, q2, 0); wface(q0, q2, q3, 0) } else { face(q0, q1, q2, cW, cW, cW); face(q0, q2, q3, cW, cW, cW) }
                rod(q3, q2, cTop, 0.7)
            } } }
            if flowing {
                for q in 0..<36 {   // 床すれすれの水が、まわりから排水口へ吸い寄せられる：4 次元の床は立方体（水平な方向が 3 つ）なので 1/r²（r³ が一定の速さで減る）
                    func fr(_ x: Double) -> Double { let y = sin(x) * 43758.5453; return y - floor(y) }
                    let D = [fr(Double(q) * 12.9898) * 2 - 1, fr(Double(q) * 78.233) * 2 - 1, fr(Double(q) * 37.719) * 2 - 1], dl = max(abs(D[0]), max(abs(D[1]), abs(D[2])), 1e-6), R0 = 0.92 / dl
                    let sF = (T * 0.45 + Double(q) / 36).truncatingRemainder(dividingBy: 1), rr = cbrt(1 - sF), r2 = cbrt(max(0, 1 - sF + 0.06)), w = -H + 0.04 * H
                    if rr * R0 * dl < R * 0.9 { continue }
                    rod(P(D.map { $0 * R0 * rr }, w), P(D.map { $0 * R0 * r2 }, w), cTop, min(1, sF * 4))
                }
                for q in 0..<10 {   // 柱の中を穴へ流れ込む水の筋
                    let u = [cos(Double(q) * 2.4) * R * 0.6, sin(Double(q) * 1.7) * R * 0.6, sin(Double(q) * 2.4) * R * 0.6], top = surfW(u), f = (T * 0.9 + Double(q) / 10).truncatingRemainder(dividingBy: 1), w = top - f * (top + H)
                    rod(P(u, w), P(u, max(-H, w - 0.15 * H)), cTop)
                }
            }
        }
        if d == 2 && flowing && !sliceL {   // 左：床の水が排水口へ吸い寄せられる（3 次元の床は平面＝水平な方向が 2 つなので 1/r）
            for q in 0..<24 {
                let th = Double(q) * 2.399, dx = cos(th), dy = sin(th), dl = max(abs(dx), abs(dy)), R0 = 0.92 / dl
                let sF = (T * 0.45 + Double(q) / 24).truncatingRemainder(dividingBy: 1), rr = sqrt(1 - sF), r2 = sqrt(min(1, 1 - sF + 0.06))
                if rr * R0 * dl < HOLE * 0.9 { continue }
                rod(P([dx * R0 * rr, dy * R0 * rr], -H + 0.04 * H), P([dx * R0 * r2, dy * R0 * r2], -H + 0.04 * H), Self.liqMen * 0.8, min(1, sF * 4))
            }
        }
        if hole {
            // 排水口のふち（底の胞と同じ色で明るく。工事済みの時は穴の絵のほうで描く）と、栓（抜くと w の上へ持ち上がって薄くなる）
            let cs: [[Double]] = d == 3 ? (0..<8).map { v in [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1] } : (0..<4).map { v in [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1] }
            func edges(_ s: Double, _ w: Double, _ c: SIMD3<Float>, _ L: Double) {
                for (i, a) in cs.enumerated() { for (j, b) in cs.enumerated() where j > i && zip(a, b).filter({ $0 != $1 }).count == 1 { rod(P(a.map { $0 * s }, w), P(b.map { $0 * s }, w), c, L) } }
            }
            if !st.holesBuilt { edges(HOLE, -H, rimC, 1) }
            let po = st.waterBLid, pw = -H + po * 0.55 * H, pa = 1 - 0.75 * po
            if pa > 0.05 && !st.holesOpen && !st.holesBuilt {
                let pc = SIMD3<Float>(0.5, 0.56, 0.68) * Float(pa), s = HOLE * 1.08
                edges(s, pw, SIMD3<Float>(0.7, 0.75, 0.85) * Float(pa), 1)
                if d == 3 {
                    for ax in 0..<3 { for sg in [-1.0, 1.0] {
                        let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                        func Uq(_ p: Double, _ q2: Double) -> [Double] { var u = [0.0, 0, 0]; u[ax] = sg * s; u[a1] = p * s; u[a2] = q2 * s; return u }
                        let q = [P(Uq(-1, -1), pw), P(Uq(1, -1), pw), P(Uq(1, 1), pw), P(Uq(-1, 1), pw)]
                        face(q[0], q[1], q[2], pc, pc, pc, Float(0.6 * k)); face(q[0], q[2], q[3], pc, pc, pc, Float(0.6 * k))
                    } }
                } else {
                    let q = [P([-s, -s], pw), P([s, -s], pw), P([s, s], pw), P([-s, s], pw)]
                    face(q[0], q[1], q[2], pc, pc, pc, Float(0.6 * k)); face(q[0], q[2], q[3], pc, pc, pc, Float(0.6 * k))
                }
            }
            if vd > 0.01 && h > -0.999 && !nsOn && !sliceL {
                let va = min(1, vd / 0.3), vc = Self.liqVort, wc = surfW(d == 3 ? [0, 0, 0] : [0, 0]), M = 28
                if d == 3 {
                    let G = 8
                    for ax in 0..<3 {   // 水面（立方体）の真ん中を通る 3 枚の断面：渦でへこんだ形が見える
                        let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                        func pt(_ i: Int, _ j: Int) -> SIMD3<Double> { var u = [0.0, 0, 0]; u[a1] = -1 + 2 * Double(i) / Double(G); u[a2] = -1 + 2 * Double(j) / Double(G); return P(u, surfW(u)) }
                        for i in stride(from: 0, through: G, by: 2) { for j in 0..<G { rod(pt(i, j), pt(i, j + 1), vc, va * 0.8); rod(pt(j, i), pt(j + 1, i), vc, va * 0.8) } }
                    }
                }
                // 渦：水面のくぼみから排水口へ、回りながら細くなっていくらせん（4D は x‐z の面で回る：芯は y の線 × w の板）
                for (yy, ph) in (d == 3 ? [(-0.3, 0.0), (0.3, Double.pi), (0, Double.pi / 2), (0, 3 * Double.pi / 2)] : [(0, 0.0), (0, Double.pi)]) {
                    var prev: SIMD3<Double>? = nil
                    for m in 0...M {
                        let f = Double(m) / Double(M), rr = 0.55 * (1 - f) + HOLE * 0.8 * f, th = ph + 3.2 * T + f * 5 * .pi, w = wc + (-H - wc) * f
                        let v = d == 3 ? P([rr * cos(th), yy * (1 - f), rr * sin(th)], w) : P([rr * cos(th), rr * sin(th)], w)
                        if let p0 = prev { rod(p0, v, vc, va) }; prev = v
                    }
                }
            }
        }
        if d == 2 && st.waterVent && st.waterPhase == 4 {   // 左：抜いている間は、上ぶたの通気口から空気が入っていく
            for q in 0..<6 {
                let f = (T * 1.2 + Double(q) / 6).truncatingRemainder(dividingBy: 1), z0 = H + (1 - f) * 0.9 * H, ox = cos(Double(q) * 2.4) * 0.06, oy = sin(Double(q) * 2.4) * 0.06, a = sin(.pi * f) * 0.8
                rod(P([-0.5 + ox, 0.5 + oy], z0), P([-0.5 + ox, 0.5 + oy], z0 - 0.12 * H), SIMD3<Float>(0.85, 0.9, 1), a)
            }
        }
        var out: [IntTriBatch] = tris.isEmpty ? [] : [IntTriBatch(add: false, verts: tris)]
        if !wtris.isEmpty {
            // 注ぐ所の波紋：当たる点（描く側の座標）・強さ（注いでいる間 1、止めたら 0.8 秒ほどで消える）・箱の大きさ（波の細かさの物さし）
            let tEnd = OrigamiState.wOPEN + OrigamiState.wPOUR, wt = st.waterT
            let ringK = free ? 0 : st.waterPhase == 1 ? min(1, (wt - OrigamiState.wOPEN) * 3) : (wt >= tEnd ? exp(-(wt - tEnd) / 0.8) : 0)
            let c0 = P(su, surfS), sc = simd_length(P(su.map { _ in 1.0 }, surfS) - P(su.map { _ in -1.0 }, surfS)) / 2 / Double(su.count).squareRoot()
            let ring = [SIMD4<Float>(gpuW(c0), Float(ringK * thin)), SIMD4<Float>(Float(max(1e-3, sc)), 0, 0, 0)]
            // 水の値：時刻・（映りこみの絵があるかは描く時に）・深さ（水の厚み 0〜1）・濃さ
            out.append(IntTriBatch(add: false, verts: wtris, water: true, wp: SIMD4<Float>(Float(st.waterTT), 0, Float(0.15 + 0.45 * (h + 1) / 2), Float(k)), ring: ring))
        }
        return out
    }
    /// 立方体（x・y・z が ±1、w 一定）の 6 面を三角形に
    private func cubeFaces(_ w: Double, _ col: SIMD3<Float>, _ al: Float, _ P: ([Double], Double) -> SIMD3<Double>, _ tris: inout [IntVert]) {
        for ax in 0..<3 { for sg in [-1.0, 1.0] {
            let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
            func U(_ s: Double, _ t: Double) -> [Double] { var u = [0.0, 0, 0]; u[ax] = sg; u[a1] = s; u[a2] = t; return u }
            let q = [P(U(-1, -1), w), P(U(1, -1), w), P(U(1, 1), w), P(U(-1, 1), w)]
            for tr in [[0, 1, 2], [0, 2, 3]] { for i in tr { tris.append(IntVert(p: SIMD4(gpuW(q[i]), 1), c: SIMD4(col * al, al))) } }
        } }
    }
}
