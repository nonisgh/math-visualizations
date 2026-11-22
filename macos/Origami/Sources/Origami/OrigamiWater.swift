// 4 次元の水を注ぐ（ウェブ版の「4D水を注ぐ」の 1 段目と 2 段目：注ぐ・ためる・抜く ＋ 浅水方程式の波）。
//   ふた +W を開けて、外から水を注ぐ。水位 h が 底 −W から上がっていく：V(h) ＝ ∫₋₁ʰ 8 dw ＝ 8(h＋1)（連続の積分）。
//   水の中身は 4 次元の箱 [−1,1]³ × [−1, h]。その表面＝底の立方体（w ＝ −1）・水面の立方体（w ＝ h）・壁に触れている 12 枚の面（立方体の辺 × w）。
//   4 次元の水面は 3 次元の立方体。それを浅水方程式（ナビエ–ストークスを深さで平均したもの）で本当に揺らす（4D は 16×16×16、左の 3D 水は 32×32）。
//   底を全部開けると、水はかたまりのまま自由落下で抜ける（見かけの重力 0 なので、揺れはそのまま）。
//   左の立方体の窓は 1 次元下げた同じもの：z の方向に水位が上がり、水面は正方形。
//   これから：排水口（渦・トリチェリ）・通気口（ごぼっ）・泡・油・虹の水・穴の工事・ふたの開け閉めの絵（積分の移植メモ.md の 8c〜8e）
import Foundation
import simd

/// 浅水方程式の格子（ウェブ版の SWE）：η（水面の高さのずれ）と、面の上の流れ u
final class WaterSWE {
    static let N = 16, M = 32, GAM = 0.2, JET = 0.3, LIM = 0.32, DT = 0.012, NU = 0.002
    var eta = [Float](repeating: 0, count: N * N * N)
    var ux = [Float](repeating: 0, count: (N + 1) * N * N), uy = [Float](repeating: 0, count: N * (N + 1) * N), uz = [Float](repeating: 0, count: N * N * (N + 1))
    var p = [Float](repeating: 0, count: N * N * N), gj = [Float](repeating: 0, count: N * N * N)
    var e2 = [Float](repeating: 0, count: M * M), vx2 = [Float](repeating: 0, count: (M + 1) * M), vy2 = [Float](repeating: 0, count: M * (M + 1))
    var p2 = [Float](repeating: 0, count: M * M), gj2 = [Float](repeating: 0, count: M * M)
    var noise: Float = 0
    init(us: SIMD3<Double>) {
        let N = Self.N, M = Self.M
        func cen(_ i: Int, _ n: Int) -> Double { -1 + (Double(i) + 0.5) * 2 / Double(n) }
        for i in 0..<N { for j in 0..<N { for k in 0..<N {
            let x = cen(i, N), y = cen(j, N), z = cen(k, N)
            gj[(i * N + j) * N + k] = Float(exp(-(pow(x - us.x, 2) + pow(y - us.y, 2) + pow(z - us.z, 2)) / 0.035))   // 水の筋が当たる所
        } } }
        for i in 0..<M { for j in 0..<M { let x = cen(i, M), y = cen(j, M); gj2[i * M + j] = Float(exp(-(pow(x - us.x, 2) + pow(y - us.y, 2)) / 0.035)) } }
    }
    func reset() {
        for i in eta.indices { eta[i] = 0 }; for i in ux.indices { ux[i] = 0 }; for i in uy.indices { uy[i] = 0 }; for i in uz.indices { uz[i] = 0 }
        for i in e2.indices { e2[i] = 0 }; for i in vx2.indices { vx2[i] = 0 }; for i in vy2.indices { vy2[i] = 0 }; noise = 0
    }
    /// 1 小ステップ：∂u/∂t ＝ −g∇η − ∇p − γu（p＝水の筋が当たる所の圧力）、∂η/∂t ＝ −D∇·u。壁は流れが通らない。平均の水位は h が受け持つので η は平均 0
    func step(_ dt: Float, g: Float, D: Float, jet: Float, H: Float) {
        let N = Self.N, dx = 2 * H / Float(N), damp = exp(-(Float(Self.GAM) + 3 * Float(Self.NU) / (D * D)) * dt), L = Float(Self.LIM) * H
        for n in 0..<p.count { p[n] = jet * gj[n] }
        for i in 1..<N { for j in 0..<N { for k in 0..<N { let a = ((i - 1) * N + j) * N + k, b = (i * N + j) * N + k; ux[b] = (ux[b] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx) * damp } } }
        for i in 0..<N { for j in 1..<N { for k in 0..<N { let a = (i * N + j - 1) * N + k, b = (i * N + j) * N + k, f = (i * (N + 1) + j) * N + k; uy[f] = (uy[f] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx) * damp } } }
        for i in 0..<N { for j in 0..<N { for k in 1..<N { let a = (i * N + j) * N + k - 1, b = a + 1, f = (i * N + j) * (N + 1) + k; uz[f] = (uz[f] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx) * damp } } }
        var sum: Float = 0
        for i in 0..<N { for j in 0..<N { for k in 0..<N {
            let n = (i * N + j) * N + k
            let div = ux[((i + 1) * N + j) * N + k] - ux[n] + uy[(i * (N + 1) + j + 1) * N + k] - uy[(i * (N + 1) + j) * N + k] + uz[(i * N + j) * (N + 1) + k + 1] - uz[(i * N + j) * (N + 1) + k]
            eta[n] += dt * (-D * div / dx); sum += eta[n]
        } } }
        let mean = sum / Float(eta.count); for n in 0..<eta.count { eta[n] = max(-L, min(L, eta[n] - mean)) }
        // 左の 3D 水（x・y の 2 方向）
        let M = Self.M, d2 = 2 * H / Float(M)
        for n in 0..<p2.count { p2[n] = jet * gj2[n] }
        for i in 1..<M { for j in 0..<M { let a = (i - 1) * M + j, b = i * M + j; vx2[b] = (vx2[b] - dt * (g * (e2[b] - e2[a]) + p2[b] - p2[a]) / d2) * damp } }
        for i in 0..<M { for j in 1..<M { let a = i * M + j - 1, b = a + 1, f = i * (M + 1) + j; vy2[f] = (vy2[f] - dt * (g * (e2[b] - e2[a]) + p2[b] - p2[a]) / d2) * damp } }
        var s2: Float = 0
        for i in 0..<M { for j in 0..<M { let n = i * M + j, div = vx2[(i + 1) * M + j] - vx2[n] + vy2[i * (M + 1) + j + 1] - vy2[i * (M + 1) + j]; e2[n] += dt * (-D * div / d2); s2 += e2[n] } }
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
    static let wUS = SIMD3<Double>(0.3, -0.35, 0.2)
    /// 底を全部開けた時に、満水（深さ 2H）が落ちきるまでの秒（自由落下）
    static var wFallT: Double { sqrt(2 * 2 * half / wG) }
    /// 1 コマ分すすめる：時刻・水位・場面と、波（小ステップに分けて）
    func waterTick(_ dt0: Double) {
        let dt = min(0.1, dt0), H = Self.half
        let t0 = Self.wOPEN, t1 = t0 + Self.wPOUR, t2 = t1 + Self.wCLOSE, t3 = t2 + Self.wHOLD, t3b = t3 + Self.wBOPEN, t4 = t3b + Self.wFallT, t5 = t4 + Self.wBCLOSE, cycle = t5 + Self.wEMPTY
        waterT = (waterT + dt).truncatingRemainder(dividingBy: cycle); waterTT += dt
        let t = waterT, sD = (t - t3b) / Self.wFallT
        // 底を全部開けると、水はかたまりのまま落ちる（だんだん速く）
        let h = t < t0 ? -1 : t < t1 ? -1 + 2 * (t - t0) / Self.wPOUR : t < t3b ? 1 : t < t4 ? 1 - 2 * sD * sD : -1
        let phase = t < t0 ? 0 : t < t1 ? 1 : t < t3 ? 2 : t < t3b ? 3 : t < t4 ? 4 : t < t5 ? 5 : 6   // 0 開ける・1 注ぐ・2 いっぱい・3 栓を抜く・4 抜ける・5 栓をする・6 空
        if abs(waterH - h) > 1e-5 { waterH = h }
        if waterPhase != phase { waterPhase = phase }
        // 流れ出る水のかたまり（同じ g）：底を全部開けた時は止まった所から自由落下。出きった後も、その時の速さのまま落ちていく
        let FL = 1.5 * H, vEnd = Self.wG * Self.wFallT, tau = t - t3b, tl = t - t4
        func fallD(_ v: Double, _ s: Double) -> Double { v * s + 0.5 * Self.wG * s * s }
        if t >= t3b && (t < t4 || -H - fallD(vEnd, tl) > -H - FL) {
            waterOut = SIMD2(t < t4 ? -H : -H - fallD(vEnd, tl), -H - min(FL * 1.05, fallD(0, tau)))
        } else { waterOut = nil }
        waterPour = t >= t0 ? (phase == 1 ? Self.wTOP * H : t >= t1 ? Self.wTOP * H - 0.5 * Self.wG * (t - t1) * (t - t1) : -9) : -9   // 水の筋の上の端（止めた後のしっぽは g で落ちる）
        // 波：浅水方程式（水が無い時は静か。底を全部開けて落ちている間は、見かけの重力 0 なので形はそのまま）
        if h <= -0.999 { swe.reset() }
        else if phase != 4 {
            let D = Float(max(0.02, (h + 1) * H)), nSub = min(12, Int(ceil(dt / WaterSWE.DT))), sd = Float(dt) / Float(max(1, nSub))
            for _ in 0..<max(1, nSub) {
                swe.noise = max(-1, min(1, swe.noise * 0.97 + Float.random(in: -1...1) * 0.35))   // 水の筋の勢いのゆらぎ
                let jet: Float = phase == 1 && h > -0.98 ? Float(WaterSWE.JET) * (1 + swe.noise) : 0
                swe.step(sd, g: Float(Self.wG), D: D, jet: jet, H: Float(H))
            }
        }
    }
}

/// 景色の座標（y が上）を、描く側（z が上）へ
@inline(__always) private func gpuW(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    // 水の色（ウェブ版の LIQ_WATER）
    static let liqSurf = SIMD3<Double>(0.32, 0.78, 1), liqWall = SIMD3<Float>(0.1, 0.4, 0.95), liqMen = SIMD3<Float>(0.38, 0.78, 1)
    static let liqCornB = SIMD3<Float>(0.12, 0.42, 0.95), liqCornT = SIMD3<Float>(0.3, 0.7, 1), liqBot = SIMD3<Float>(0.05, 0.25, 0.7)
    static let liqStream = SIMD3<Float>(0.3, 0.7, 1), liqBead = SIMD3<Float>(0.5, 0.85, 1), liqOut = SIMD3<Float>(0.12, 0.45, 0.98)

    /// 4 次元の水（立方体の窓は 3 次元の水）：線は rods に足し、面は三角形で返す
    func waterGeometry(_ rods: inout [TLRod], eye: SIMD3<Double>) -> [IntTriBatch] {
        let k = st.intVis
        guard k > 0.01, st.intMethod == 1 else { return [] }
        let H = OrigamiState.half, h = st.waterH, d = n - 1, G = OrigamiState.wGrid
        let thin = min(1, (h + 1) * 3)                                   // 水が薄い時は揺れも小さく
        var tris: [IntVert] = []
        let A = Float(0.4 * k)                                            // 面の濃さ（ウェブ版の opacity 0.4）
        func P(_ u: [Double], _ w: Double) -> SIMD3<Double> { st.place(u.map { $0 * H } + [w], n).0 }
        func surfW(_ u: [Double]) -> Double {
            let e = d == 3 ? st.swe.sample3(SIMD3(u[0], u[1], u[2])) : st.swe.sample2(SIMD2(u[0], u[1]))
            return max(-H, min(H, h * H + thin * e))
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
        if h > -0.999 {
            if d == 3 {
                // 水面の立方体（w ＝ h ＋ 揺れ）：6 面を G×G に分けて。色は頂点ごと（面の向きは隣の点から）
                for ax in 0..<3 { for sg in [-1.0, 1.0] {
                    let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
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
                        face(A0, B0, B1, Self.liqWall, Self.liqWall, Self.liqWall); face(A0, B1, A1, Self.liqWall, Self.liqWall, Self.liqWall)
                        rod(A1, B1, Self.liqMen)
                    }
                } } }
                // 角の縦の線（w の方向）と、底の立方体（w ＝ −1）
                for v in 0..<8 {
                    let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1]
                    rod(P(u, -H), P(u, surfW(u)), (Self.liqCornB + Self.liqCornT) / 2)
                }
                cubeFaces(-H, Self.liqBot, A, P, &tris)
            } else {
                // 3 次元の水：水面は正方形（z ＝ h ＋ 揺れ）
                var V: [[SIMD3<Double>]] = [], Dd: [[Double]] = []
                for i in 0...G { var row: [SIMD3<Double>] = [], drow: [Double] = []; for j in 0...G { let u = [-1 + 2 * Double(i) / Double(G), -1 + 2 * Double(j) / Double(G)], w = surfW(u); row.append(P(u, w)); drow.append(w / H - h) }; V.append(row); Dd.append(drow) }
                var C: [[SIMD3<Float>]] = []
                for i in 0...G { var row: [SIMD3<Float>] = []; for j in 0...G {
                    let a = V[min(G, i + 1)][j] - V[max(0, i - 1)][j], b = V[i][min(G, j + 1)] - V[i][max(0, j - 1)]
                    let nn = simd_cross(a, b), nl = simd_length(nn)
                    row.append(surfColor(V[i][j], nl > 1e-12 ? nn / nl : SIMD3(0, 0, 1), Dd[i][j]))
                }; C.append(row) }
                for i in 0..<G { for j in 0..<G {
                    face(V[i][j], V[i + 1][j], V[i + 1][j + 1], C[i][j], C[i + 1][j], C[i + 1][j + 1], Float(0.3 * k))
                    face(V[i][j], V[i + 1][j + 1], V[i][j + 1], C[i][j], C[i + 1][j + 1], C[i][j + 1], Float(0.3 * k))
                } }
                // 壁（正方形の 4 本の辺 × z）・水際の線・角の縦の線・底の正方形
                for ax in 0..<2 { for s1 in [-1.0, 1.0] {
                    func U(_ i: Int) -> [Double] { var u = [0.0, 0]; u[ax] = -1 + 2 * Double(i) / Double(G); u[1 - ax] = s1; return u }
                    for i in 0..<G {
                        let ua = U(i), ub = U(i + 1), wa = surfW(ua), wb = surfW(ub)
                        let A0 = P(ua, -H), B0 = P(ub, -H), A1 = P(ua, wa), B1 = P(ub, wb)
                        face(A0, B0, B1, Self.liqWall, Self.liqWall, Self.liqWall, Float(0.3 * k)); face(A0, B1, A1, Self.liqWall, Self.liqWall, Self.liqWall, Float(0.3 * k))
                        rod(A1, B1, Self.liqMen)
                    }
                } }
                for v in 0..<4 { let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1]; rod(P(u, -H), P(u, surfW(u)), (Self.liqCornB + Self.liqCornT) / 2) }
                let b0 = P([-1, -1], -H), b1 = P([1, -1], -H), b2 = P([1, 1], -H), b3 = P([-1, 1], -H)
                face(b0, b1, b2, Self.liqBot, Self.liqBot, Self.liqBot, Float(0.3 * k)); face(b0, b2, b3, Self.liqBot, Self.liqBot, Self.liqBot, Float(0.3 * k))
            }
        }
        // 水の筋：ふたの先（w ＝ TOP×H）から水面まで、w の方向に落ちる（止めた後は、しっぽが落ちていく）。粒は g で加速しながら落ちる
        let us = OrigamiState.wUS, top = st.waterPour
        let su: [Double] = d == 3 ? [us.x, us.y, us.z] : [us.x, us.y]
        let surfS = h > -0.999 ? surfW(su) : -H
        if top > surfS {
            let T = st.waterTT
            for (n, o) in [(0, SIMD2(0.0, 0.0)), (1, SIMD2(0.025, 0.01)), (2, SIMD2(-0.02, 0.02)), (3, SIMD2(0.01, -0.025))] {
                let a = n == 0 ? 1.0 : 0.6, M = 10
                for m in 0..<M {
                    let w0 = top + (surfS - top) * Double(m) / Double(M), w1 = top + (surfS - top) * Double(m + 1) / Double(M)
                    let wob = 0.012 * sin(T * 20 + Double(m) * 1.7 + Double(n))
                    var pa = su, pb = su; pa[0] += o.x + wob; pb[0] += o.x - wob; if d == 3 { pa[2] += o.y; pb[2] += o.y }
                    rod(P(pa, w0), P(pb, w1), Self.liqStream, a)
                }
            }
            let tf = sqrt(2 * max(1e-3, top - surfS) / OrigamiState.wG)
            for m in 0..<7 {
                let tau = ((T / tf + Double(m) / 7).truncatingRemainder(dividingBy: 1)) * tf, w = top - 0.5 * OrigamiState.wG * tau * tau
                rod(P(su, w + 0.05 * H), P(su, w - 0.05 * H), Self.liqBead)
            }
        }
        // 底から流れ出る水のかたまり（底を全部開けた時。立方体（正方形）× w の箱）
        if let out = st.waterOut, out.x > out.y + 1e-4 {
            if d == 3 {
                cubeFaces(out.y, Self.liqOut, Float(0.3 * k), P, &tris)
                for v in 0..<8 { let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1]; rod(P(u, out.x), P(u, out.y), Self.liqOut) }
            } else {
                for v in 0..<4 { let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1]; rod(P(u, out.x), P(u, out.y), Self.liqOut) }
                let b0 = P([-1, -1], out.y), b1 = P([1, -1], out.y), b2 = P([1, 1], out.y), b3 = P([-1, 1], out.y)
                face(b0, b1, b2, Self.liqOut, Self.liqOut, Self.liqOut, Float(0.3 * k)); face(b0, b2, b3, Self.liqOut, Self.liqOut, Self.liqOut, Float(0.3 * k))
            }
        }
        return tris.isEmpty ? [] : [IntTriBatch(add: false, verts: tris)]
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
