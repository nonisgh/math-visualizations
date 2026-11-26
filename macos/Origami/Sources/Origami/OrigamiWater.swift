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
    var tiltLim: Float = 0                                            // 重力を傾けた時の水面の高さの上限（H の何倍か。傾いた水面が上限で切れないように）
    var calmDamp: Float = 0                                           // マウスを離したあと、ゆれを早めにおさめる減り方（1/秒。波紋には効かせない）
    var tmp3: [Float] = [], tmp2: [Float] = []                        // ならす時の入れ物
    static let SMOOTH: Float = 0.08                                   // 細かいでこぼこを ならす強さ（1 小ステップごと）
    var extraDamp: Float = 0                                          // 足す減り方（1/秒）：一時停止中に、水面を早めに静かにする
    init(us: SIMD3<Double>) {
        rUS = us
        let N = Self.N, M = Self.M
        func cen(_ i: Int, _ n: Int) -> Double { -1 + (Double(i) + 0.5) * 2 / Double(n) }
        for i in 0..<N { for j in 0..<N { for k in 0..<N {
            let x = cen(i, N), y = cen(j, N), z = cen(k, N)
            gj[(i * N + j) * N + k] = Float(exp(-(pow(x - us.x, 2) + pow(y - us.y, 2) + pow(z - us.z, 2)) / 0.035))   // 水の筋が当たる所
            gc[(i * N + j) * N + k] = Float(exp(-(x * x + y * y + z * z) / 0.02))
        } } }
        for i in 0..<M { for j in 0..<M { let x = cen(i, M), y = cen(j, M); gj2[i * M + j] = Float(exp(-(pow(x - us.x, 2) + pow(y - us.y, 2)) / 0.035)); gc2[i * M + j] = Float(exp(-(x * x + y * y) / 0.02)) } }
    }
    // ---- 波紋：水の筋が当たる所から広がる細かい波（浅水の格子より細かい、別の薄い層。波の方程式 ∂²ζ/∂t² ＝ c²∇²ζ − γ∂ζ/∂t） ----
    //   4D の水面は 3 次元なので、波紋は球の殻になって広がる（48³）。左の 3D の水面は 2 次元なので輪（96²）。壁ではね返る
    static let R3 = 48, R2 = 96, RC = 0.9, RGAM: Float = 0.45, ROMG = 16.0   // RC：波の速さ（−1〜1 の座標で 1 秒に）・RGAM：減り方・ROMG：筋がたたく速さ（波長 ≈ 2πc／ω ≈ 0.35）
    var rz = [Float](repeating: 0, count: R3 * R3 * R3), rv = [Float](repeating: 0, count: R3 * R3 * R3)
    var rz2 = [Float](repeating: 0, count: R2 * R2), rv2 = [Float](repeating: 0, count: R2 * R2)
    var rT: Double = 0, rLive: Double = 0                             // rLive：最後にたたいてからの秒（静かになったら計算を休む）
    let rUS: SIMD3<Double>
    func rippleReset() { for i in rz.indices { rz[i] = 0; rv[i] = 0 }; for i in rz2.indices { rz2[i] = 0; rv2[i] = 0 }; rLive = 99 }
    /// 1 小ステップ：on の間、筋が当たる所を ω でたたく（強さは筋のゆらぎで少し変わる）。壁は鏡（波がはね返る）
    func rippleStep(_ dt: Float, on: Bool, amp: Float) {
        rT += Double(dt); rLive = on ? 0 : rLive + Double(dt)
        guard rLive < 5 else { return }
        let damp = exp(-(Self.RGAM + extraDamp) * dt), c = Float(Self.RC)
        let f: Float = on ? amp * Float(sin(Self.ROMG * rT)) * (0.75 + 0.35 * noise) : 0
        do {   // 4D の水面（3 次元）
            let N = Self.R3, dx = Float(2) / Float(N), k = c * c / (dx * dx)
            func cen(_ i: Int) -> Double { -1 + (Double(i) + 0.5) * 2 / Double(N) }
            let si = Int(((rUS.x + 1) / 2 * Double(N)).rounded(.down)), sj = Int(((rUS.y + 1) / 2 * Double(N)).rounded(.down)), sk = Int(((rUS.z + 1) / 2 * Double(N)).rounded(.down))
            for i in 0..<N { let im = max(0, i - 1), ip = min(N - 1, i + 1)
                for j in 0..<N { let jm = max(0, j - 1), jp = min(N - 1, j + 1)
                    for kk in 0..<N { let km = max(0, kk - 1), kp = min(N - 1, kk + 1)
                        let n = (i * N + j) * N + kk, z = rz[n]
                        let lap = rz[(im * N + j) * N + kk] + rz[(ip * N + j) * N + kk] + rz[(i * N + jm) * N + kk] + rz[(i * N + jp) * N + kk] + rz[(i * N + j) * N + km] + rz[(i * N + j) * N + kp] - 6 * z
                        rv[n] = (rv[n] + dt * k * lap) * damp
            } } }
            if f != 0 {
                for i in max(0, si - 2)...min(N - 1, si + 2) { for j in max(0, sj - 2)...min(N - 1, sj + 2) { for kk in max(0, sk - 2)...min(N - 1, sk + 2) {
                    let r2 = pow(cen(i) - rUS.x, 2) + pow(cen(j) - rUS.y, 2) + pow(cen(kk) - rUS.z, 2)
                    rv[(i * N + j) * N + kk] += dt * f * 45 * Float(exp(-r2 / (2 * 0.045 * 0.045)))   // 4D は 3 方向へ広がって薄まるので、強めに
                } } }
            }
            for n in rz.indices { rz[n] += dt * rv[n] }
        }
        do {   // 左の 3D の水面（2 次元）
            let N = Self.R2, dx = Float(2) / Float(N), k = c * c / (dx * dx)
            func cen(_ i: Int) -> Double { -1 + (Double(i) + 0.5) * 2 / Double(N) }
            let si = Int(((rUS.x + 1) / 2 * Double(N)).rounded(.down)), sj = Int(((rUS.y + 1) / 2 * Double(N)).rounded(.down))
            for i in 0..<N { let im = max(0, i - 1), ip = min(N - 1, i + 1)
                for j in 0..<N { let jm = max(0, j - 1), jp = min(N - 1, j + 1)
                    let n = i * N + j, lap = rz2[im * N + j] + rz2[ip * N + j] + rz2[i * N + jm] + rz2[i * N + jp] - 4 * rz2[n]
                    rv2[n] = (rv2[n] + dt * k * lap) * damp
            } }
            if f != 0 {
                for i in max(0, si - 3)...min(N - 1, si + 3) { for j in max(0, sj - 3)...min(N - 1, sj + 3) {
                    let r2 = pow(cen(i) - rUS.x, 2) + pow(cen(j) - rUS.y, 2)
                    rv2[i * N + j] += dt * f * 55 * Float(exp(-r2 / (2 * 0.03 * 0.03)))
                } }
            }
            for n in rz2.indices { rz2[n] += dt * rv2[n] }
        }
    }
    /// 波紋の高さ（世界の単位）を点 u（−1〜1）で
    func rip3(_ u: SIMD3<Double>) -> Double {
        guard rLive < 5 else { return 0 }
        let N = Self.R3
        func f(_ q: Double) -> Double { max(0, min(Double(N) - 1.0001, (q + 1) / 2 * Double(N) - 0.5)) }
        let fx = f(u.x), fy = f(u.y), fz = f(u.z), i = Int(fx), j = Int(fy), k = Int(fz), a = fx - Double(i), b = fy - Double(j), c = fz - Double(k)
        let I = min(N - 1, i + 1), J = min(N - 1, j + 1), K = min(N - 1, k + 1)
        func e(_ x: Int, _ y: Int, _ z: Int) -> Double { Double(rz[(x * N + y) * N + z]) }
        return ((e(i, j, k) * (1 - c) + e(i, j, K) * c) * (1 - b) + (e(i, J, k) * (1 - c) + e(i, J, K) * c) * b) * (1 - a)
             + ((e(I, j, k) * (1 - c) + e(I, j, K) * c) * (1 - b) + (e(I, J, k) * (1 - c) + e(I, J, K) * c) * b) * a
    }
    func rip2(_ u: SIMD2<Double>) -> Double {
        guard rLive < 5 else { return 0 }
        let M = Self.R2
        func f(_ q: Double) -> Double { max(0, min(Double(M) - 1.0001, (q + 1) / 2 * Double(M) - 0.5)) }
        let fx = f(u.x), fy = f(u.y), i = Int(fx), j = Int(fy), a = fx - Double(i), b = fy - Double(j), I = min(M - 1, i + 1), J = min(M - 1, j + 1)
        func e(_ x: Int, _ y: Int) -> Double { Double(rz2[x * M + y]) }
        return (e(i, j) * (1 - b) + e(i, J) * b) * (1 - a) + (e(I, j) * (1 - b) + e(I, J) * b) * a
    }
    func reset() {
        rippleReset()
        for i in eta.indices { eta[i] = 0 }; for i in ux.indices { ux[i] = 0 }; for i in uy.indices { uy[i] = 0 }; for i in uz.indices { uz[i] = 0 }
        for i in e2.indices { e2[i] = 0 }; for i in vx2.indices { vx2[i] = 0 }; for i in vy2.indices { vy2[i] = 0 }; noise = 0
    }
    /// 1 小ステップ：∂u/∂t ＝ −g∇η − ∇p − γu（p＝水の筋が当たる所の圧力）、∂η/∂t ＝ −D∇·u − q（q＝排水口から吸い出す量）。壁は流れが通らない。平均の水位は h が受け持つので η は平均 0
    /// ah・ah2：箱から見た見かけの重力の横向きの分（4D の水は x・y・z、左の 3D の水は x・y）。箱を回すと「下」が遅れてついてくるので、水が寄ってゆれる（ちゃぷちゃぷ）
    func step(_ dt: Float, g: Float, D: Float, jet: Float, H: Float, sink: Float = 0, ah: SIMD3<Float> = .zero, ah2: SIMD2<Float> = .zero) {
        let N = Self.N, dx = 2 * H / Float(N), damp = exp(-(Float(Self.GAM) + extraDamp + calmDamp + 3 * Float(Self.NU) / (D * D)) * dt), L = max(Float(Self.LIM), tiltLim) * H, Lo = min(L, 0.97 * D)   // Lo：床が出るより下へは下げない
        for n in 0..<p.count { p[n] = jet * gj[n] }
        for i in 1..<N { for j in 0..<N { for k in 0..<N { let a = ((i - 1) * N + j) * N + k, b = (i * N + j) * N + k; ux[b] = (ux[b] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx + dt * ah.x) * damp } } }
        for i in 0..<N { for j in 1..<N { for k in 0..<N { let a = (i * N + j - 1) * N + k, b = (i * N + j) * N + k, f = (i * (N + 1) + j) * N + k; uy[f] = (uy[f] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx + dt * ah.y) * damp } } }
        for i in 0..<N { for j in 0..<N { for k in 1..<N { let a = (i * N + j) * N + k - 1, b = a + 1, f = (i * N + j) * (N + 1) + k; uz[f] = (uz[f] - dt * (g * (eta[b] - eta[a]) + p[b] - p[a]) / dx + dt * ah.z) * damp } } }
        var sum: Float = 0
        for i in 0..<N { for j in 0..<N { for k in 0..<N {
            let n = (i * N + j) * N + k
            let div = ux[((i + 1) * N + j) * N + k] - ux[n] + uy[(i * (N + 1) + j + 1) * N + k] - uy[(i * (N + 1) + j) * N + k] + uz[(i * N + j) * (N + 1) + k + 1] - uz[(i * N + j) * (N + 1) + k]
            eta[n] += dt * (-D * div / dx - sink * gc[n]); sum += eta[n]
        } } }
        let mean = sum / Float(eta.count); for n in 0..<eta.count { eta[n] = max(-Lo, min(L, eta[n] - mean)) }
        // 格子の細かいでこぼこ（となりと互い違いの波）だけを ならす：となりの平均へ少し寄せる（長い波はほとんど変わらない。全体の量は変わらない）
        smooth3(Self.SMOOTH)
        // 左の 3D 水（x・y の 2 方向）
        let M = Self.M, d2 = 2 * H / Float(M)
        for n in 0..<p2.count { p2[n] = jet * gj2[n] }
        for i in 1..<M { for j in 0..<M { let a = (i - 1) * M + j, b = i * M + j; vx2[b] = (vx2[b] - dt * (g * (e2[b] - e2[a]) + p2[b] - p2[a]) / d2 + dt * ah2.x) * damp } }
        for i in 0..<M { for j in 1..<M { let a = i * M + j - 1, b = a + 1, f = i * (M + 1) + j; vy2[f] = (vy2[f] - dt * (g * (e2[b] - e2[a]) + p2[b] - p2[a]) / d2 + dt * ah2.y) * damp } }
        var s2: Float = 0
        for i in 0..<M { for j in 0..<M { let n = i * M + j, div = vx2[(i + 1) * M + j] - vx2[n] + vy2[i * (M + 1) + j + 1] - vy2[i * (M + 1) + j]; e2[n] += dt * (-D * div / d2 - sink * gc2[n]); s2 += e2[n] } }
        let m2 = s2 / Float(e2.count); for n in 0..<e2.count { e2[n] = max(-Lo, min(L, e2[n] - m2)) }
        smooth2(Self.SMOOTH)
    }
    /// η をとなりの平均へ a だけ寄せる（壁は鏡：はしの外は自分と同じ）
    private func smooth3(_ a: Float) {
        let N = Self.N; if tmp3.count != eta.count { tmp3 = eta }
        for i in 0..<N { let im = max(0, i - 1), ip = min(N - 1, i + 1); for j in 0..<N { let jm = max(0, j - 1), jp = min(N - 1, j + 1); for k in 0..<N { let km = max(0, k - 1), kp = min(N - 1, k + 1)
            let s = eta[(im * N + j) * N + k] + eta[(ip * N + j) * N + k] + eta[(i * N + jm) * N + k] + eta[(i * N + jp) * N + k] + eta[(i * N + j) * N + km] + eta[(i * N + j) * N + kp]
            let n = (i * N + j) * N + k; tmp3[n] = eta[n] + a * (s / 6 - eta[n])
        } } }
        swap(&eta, &tmp3)
    }
    private func smooth2(_ a: Float) {
        let M = Self.M; if tmp2.count != e2.count { tmp2 = e2 }
        for i in 0..<M { let im = max(0, i - 1), ip = min(M - 1, i + 1); for j in 0..<M { let jm = max(0, j - 1), jp = min(M - 1, j + 1)
            let n = i * M + j, s = e2[im * M + j] + e2[ip * M + j] + e2[i * M + jm] + e2[i * M + jp]; tmp2[n] = e2[n] + a * (s / 4 - e2[n])
        } }
        swap(&e2, &tmp2)
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
    static var wFullN: Int { Int(ProcessInfo.processInfo.environment["NSFULLN"] ?? "") ?? 12 }   // 通気口があれば 100% まで入れてよいマスの細かさ（これ以上）
    static let wFloorSlope = 0.35                                          // 本物の 4D の水：抜く間の床の傾き（排水口へ向かう力、重力の何倍か）
    static let wPuddleT = 1.0                                              // 水玉になってから吸いこまれ切るまでの秒（排水口で抜く時）
    static let wPuddle = 0.35                                              // 水玉の厚み（H の何倍か）：これより浅い間は、床の中の水玉で描く
    /// 内接球（半径 1）のまわりの水の 4 次元の体積（箱の半分 ＝ 1）：V(h) ＝ ∫₋₁ʰ (8 − ⁴⁄₃π(1 − w²)^{3⁄2}) dw。
    ///   ∫(1 − w²)^{3⁄2} dw ＝ (w⁄8)(5 − 2w²)√(1 − w²) ＋ (3⁄8) asin w。全部で 16 − π²⁄2（超立方体の約 69%）
    static func ballWaterV(_ h: Double) -> Double {
        func F(_ w: Double) -> Double { let c = max(-1, min(1, w)); return c / 8 * (5 - 2 * c * c) * sqrt(max(0, 1 - c * c)) + 3.0 / 8 * asin(c) }
        return 8 * (h + 1) - 4.0 / 3 * Double.pi * (F(h) - F(-1))
    }
    static let ballWaterFull = 16 - Double.pi * Double.pi / 2
    /// 3D の仲間（立方体の中の内接球、左の窓）：V(h) ＝ ∫₋₁ʰ (4 − π(1 − z²)) dz。全部で 8 − ⁴⁄₃π（約 48%）
    static func ballWaterV3(_ h: Double) -> Double { let c = max(-1, min(1, h)); return 4 * (c + 1) - Double.pi * (c - c * c * c / 3 + 2.0 / 3) }
    static let ballWaterFull3 = 8 - 4 * Double.pi / 3
    /// 体積 V（箱の半分 ＝ 1）から水位 h：V(h) は増えるだけなので二分法で
    static func ballWaterH(_ V: Double) -> Double {
        var lo = -1.0, hi = 1.0
        for _ in 0..<40 { let m = (lo + hi) / 2; if ballWaterV(m) < V { lo = m } else { hi = m } }
        return (lo + hi) / 2
    }
    static let wBallOcc = 0.97                                             // 内接球のかくす半径（本当の半径の何倍か）：玉に触れている水まで消さないように少し小さく
    static let wBallSeg = 0.06                                             // 玉のふちで三角形を分ける細かさ（世界の長さ。これより小さくは分けない）
    static let wPudSit = 0.01                                              // 4D の水玉を床の胞から浮かせる量（H の何倍か）：ほぼぴったり
    static let wPudLiftFrom = 0.75                                         // 床を何割満たしたら、水玉を水面の高さへ持ち上げはじめるか
    static let wPudRing = 0.9                                              // 4D の水玉の輪（xy・yz・zx）の明るさ
    static let wTouchTo = 0.25                                             // 接点の光が消えるまでの水玉の広さ（床の何割か）
    static let wTouchLen = 0.32                                            // 接点の光の十字の長さ（H の何倍か）
    static let wFF = 3.0                                                   // 水が見えない間の早送りの倍率
    static let wVISIBLE = 0.015                                           // 本物の 4D の水：これより少なければ「もう見えない」（箱の 1.5%）
    static let wHOLE = 0.58, wQOPEN = 0.48, wSINK: Float = 1.6, wGF = 1.4
    static let wUS = SIMD3<Double>(0.3, -0.35, 0.2)
    /// 底を全部開けた時に、満水（深さ 2H）が落ちきるまでの秒（自由落下）
    static var wFallT: Double { sqrt(2 * 2 * half / wG) }
    /// 1 コマ分すすめる：時刻・水位・場面と、波（小ステップに分けて）
    /// 排水口から抜くのは g と穴の広さから：トリチェリ（出る速さ √(2g・深さ)）で、空になるまで (水面の広さ／穴の広さ) × √(2・2H／g)。
    ///   4 次元では「広さ」は 3 次元の体積なので、広さの比は (穴の半幅／H)³（3 次元のお風呂なら 2 乗）。同じ形の穴でも 4 次元のほうがずっとゆっくり抜ける
    var wDrainHoleT: Double { Self.wFallT / pow(drainSize, 3) }
    /// 排水口があるか（水で、抜き方が排水口か交互の時。オンにすると底の胞にすっと現れる）
    var drainShown: Bool { intOn && intMethod == 1 && drainMode != 0 }
    /// 排水口が開けっぱなし（排水口がある時だけ）
    var holesOpen: Bool { drainShown && holesOpenSet }
    /// 今回の抜き方が排水口か（交互＝1 回ごとに 底を全部 → 排水口 → …）
    var waterHoleNow: Bool { holesOpen || drainMode == 1 || (drainMode == 2 && waterCyc % 2 == 1) }
    /// 自動モードで、注いでいる途中でも抜けるか（開けっぱなし・遊ぶモードでは使わない）
    var waterCanDrainNow: Bool { intOn && intMethod == 1 && !(waterFree && waterNS) && !holesOpen && waterDrainH == nil && (waterPhase == 1 || waterPhase == 2) }
    /// 今すぐ抜く：その時の水位のまま、ふたを閉めて栓を抜く（場面の時計を「注ぎ終わり」へ進める。本物の 4D の水は今の体積のまま）
    func waterDrainNow() {
        guard waterCanDrainNow, waterH > -0.97 else { return }
        waterDrainH = waterH
        waterT = Self.wOPEN + Self.wPOUR + (waterPhase == 2 ? Self.wCLOSE + Self.wHOLD : 0)   // 注いでいる：ふたを閉めるところへ・いっぱい：栓を抜くところへ
    }
    /// 1 コマ分すすめる：時刻・水位・場面と、波（小ステップに分けて）
    func waterTick(_ dt0: Double) {
        if waterFree && waterNS, let ns = ns4Get() { waterFreeTick(ns, min(0.1, dt0)); return }
        let dt = min(0.1, dt0), H = Self.half
        // 一時停止：場面の時計（開ける → 注ぐ → 抜く…）だけ止める。注ぐのをやめ、栓も閉めて流れを止める。水の計算（波）は続けるので、水面は静かになっていく
        // 水が見えない間（栓をする・空・ふたを開ける）は、場面の時計を 3 倍の早送り（待ち時間を短く）
        let ff = [0, 5, 6].contains(waterPhase) ? Self.wFF : 1.0
        let paused = intPaused, dtT = paused ? 0 : dt * ff
        waterPauseT = paused ? waterPauseT + dt : 0
        waterPauseK = max(0, min(1, waterPauseK + (paused ? dt : -dt) * 2.5))
        let hole = waterHoleNow, hOpen = holesOpen, DR = hole ? wDrainHoleT : Self.wFallT
        // 通気：空気の入り口（通気口か、開いたままの上のふた）が無いと、底から空気と入れ替わりながらしか抜けない（ごぼごぼ、ゆっくり）
        let vented = waterVent || (intLidMode == 1 && hole), DRv = vented ? DR : DR / (hole ? 0.35 : 0.5), GF = Self.wGF
        // 途中で抜く時：水の深さ d0（0〜1）。抜ける時間は √(深さ) に比例（排水口：トリチェリ・全部開ける：自由落下）
        let hTop = waterDrainH ?? 1, d0 = max(0.02, (hTop + 1) / 2), sq0 = sqrt(d0)
        // 排水口で抜く時：床だけ（水玉）になったら、トリチェリ（浅いほどゆっくりで、最後がなかなか終わらない）をやめて、wPuddleT 秒でさっと吸いこまれる
        let T0 = DRv * sq0, qp = Self.wPuddle / 2                      // T0：トリチェリで d0 から空になる時間・qp：水玉になる深さ（箱の高さの割合）
        let s1 = hole ? max(0, 1 - sqrt(min(1, qp / d0))) : 1, TP = hole ? Self.wPuddleT * sqrt(min(1, d0 / qp)) : 0
        let DRT = s1 * T0 + TP                                          // 抜ける時間（トリチェリの分 ＋ 水玉の分）
        let t0 = Self.wOPEN, t1 = t0 + Self.wPOUR * (hOpen ? 1.4 : 1), t2 = t1 + Self.wCLOSE, t3 = t2 + Self.wHOLD, t3b = t3 + Self.wBOPEN, t4 = t3b + DRT, t5 = t4 + Self.wBCLOSE, cycle = t5 + Self.wEMPTY
        if hOpen {   // 開けっぱなし：栓が無いので注いでいる間も抜ける。入る量 Q と出る量 a√(2g・深さ)（トリチェリ）がつり合う水位に近づき、止めると抜けきる
            let r = pow(drainSize, 3), tt = waterT + dtT
            if tt < dtT * 1.5 { waterDOpen = 0 }
            let pourNow = tt >= t0 && tt < t1, dd = waterDOpen, outR = r * sqrt(2 * Self.wG * dd) * (vented ? 1 : 0.35)
            waterDOpen = max(0, min(2 * H, dd + ((pourNow ? Self.wQOPEN : 0) - outR) * dtT))   // 水位の式：d′ ＝ Q − a√(2g d)
            waterHEq = min(1, -1 + pow(Self.wQOPEN / r, 2) / (2 * Self.wG) / H)
            if !pourNow && tt >= t1 && waterDOpen <= 1e-3 {   // 抜けきったら少し置いて、また注ぐ
                if waterEmptyT == nil { waterEmptyT = tt }
                if tt - (waterEmptyT ?? tt) > Self.wEMPTY { waterT = -dtT; waterEmptyT = nil; waterCyc += 1 }
            } else { waterEmptyT = nil }
        }
        if waterDrainH != nil && waterT >= t2 && waterT < t3 { waterT = t3 }   // 途中で抜く時は「いっぱい」で待たずに、ふたを閉めたらすぐ栓を抜く
        if waterT + dtT >= cycle { waterCyc += 1; waterDrainH = nil }
        waterT = (waterT + dtT).truncatingRemainder(dividingBy: cycle); waterTT += dt
        let t = waterT, pourT = t >= t0 && t < t1, pouring = pourT && !paused
        if t < t1 - 1e-9 && waterDrainH != nil { waterDrainH = nil }   // 最初から（場面を作り直した時など）
        var sD = (t - t3b) / T0                                       // トリチェリ・自由落下の進み（d0 から空まで 0〜1。前は DRv で割っていて、途中から抜くと最後に水位が飛んでいた）
        if !vented && t >= t3b && t < t4 { sD = max(0, min(1, sD - 0.8 / (2 * .pi * GF * DRv) * sin(2 * .pi * GF * (t - t3b)))) }   // ごぼっ、ごぼっ：空気が 1 回入るたびに少し流れる
        let gp = t >= t3b && t < t4 ? Int(floor(GF * (t - t3b) + 0.25)) : -1, glugNow = !vented && gp >= 0 && gp != waterGlugN; waterGlugN = gp
        waterVented = vented
        // 底を全部開けると、水はかたまりのまま落ちる（だんだん速く）。排水口からは、深いほど速く出て、浅くなるとゆっくり（トリチェリ）
        var h = t < t0 ? -1 : t < t1 ? -1 + 2 * (t - t0) / (t1 - t0) : t < t3b ? hTop : t < t4 ? (hole ? (t - t3b < s1 * T0 ? -1 + 2 * d0 * (1 - sD) * (1 - sD) : -1 + 2 * min(d0, qp) * pow(max(0, 1 - (t - t3b - s1 * T0) / max(1e-6, TP)), 1.3)) : -1 + 2 * d0 * (1 - sD * sD)) : -1
        var phase = t < t0 ? 0 : pouring ? 1 : t < t3 ? 2 : t < t3b ? 3 : t < t4 ? 4 : t < t5 ? 5 : 6   // 0 開ける・1 注ぐ・2 いっぱい・3 栓を抜く・4 抜ける・5 栓をする・6 空
        var lid = t < t0 ? t / t0 : t < t1 ? 1 : t < t2 ? 1 - (t - t1) / Self.wCLOSE : 0                     // 上のふた：開ける → 注ぐ → 閉める
        var blid = t < t3 ? 0 : t < t3b ? (t - t3) / Self.wBOPEN : t < t4 ? 1 : t < t5 ? 1 - (t - t4) / Self.wBCLOSE : 0   // 底：栓を抜く → 抜く → 栓をする
        if intLidMode == 1 { lid = hole ? 1 : 1 - blid }                                                   // 開けたまま：上のふたは閉じない（底を全部開ける時だけ閉める）
        // 流れ出る水の柱（同じ g）：全部開けた時は止まった所から自由落下、排水口からは √(2g・深さ) の速さで出て、さらに g で加速
        let FL = 1.5 * H, v0 = hole ? sqrt(2 * Self.wG * 2 * H * d0) : 0, vEnd = hole ? 0 : Self.wG * DR * sq0, tau = t - t3b, tl = t - t4
        func fallD(_ v: Double, _ s: Double) -> Double { v * s + 0.5 * Self.wG * s * s }
        if !paused && t >= t3b && (t < t4 || -H - fallD(vEnd, tl) > -H - FL) {
            waterOut = SIMD2(t < t4 ? -H : -H - fallD(vEnd, tl), -H - min(FL * 1.05, fallD(v0, tau)))
        } else { waterOut = nil }
        if hOpen {   // 開けっぱなし：水位・場面・流れ出る柱を、上の水位の式から（栓は無い）
            let d = waterDOpen
            h = -1 + d / H; phase = t < t0 ? 0 : pouring ? 1 : d > 1e-3 ? 4 : 6
            blid = 1; waterOut = d > 1e-3 && !paused ? SIMD2(-H, -H - FL * 1.05) : nil
        }
        blid *= 1 - waterPauseK                                            // 止めている間は、底（栓）を閉める
        waterLid = max(0, min(1, lid)); waterBLid = max(0, min(1, blid))
        if abs(waterH - h) > 1e-5 { waterH = h }
        if waterPhase != phase { waterPhase = phase }
        waterPour = t >= t0 ? (pouring ? Self.wTOP * H : t >= t1 ? Self.wTOP * H - 0.5 * Self.wG * (t - t1) * (t - t1) : -9) : -9   // 水の筋の上の端（止めた後のしっぽは g で落ちる）
        if paused && pourT { waterPour = Self.wTOP * H - 0.5 * Self.wG * waterPauseT * waterPauseT }   // 注ぐ途中で止めた：しっぽが落ちていく
        // 波：浅水方程式（水が無い時は静か。底を全部開けて落ちている間は、見かけの重力 0 なので形はそのまま。通気が無い時は空気の圧力で支えられるので計算する）
        let flowing = !paused && hole && (phase == 4 || (hOpen && phase == 1))
        // 箱から見た見かけの重力：回すと「下」が遅れてついてくる ＋ ドラッグの手の加速度の逆向き（浅水にも、本物の 4D の水にも）
        let gDown = gravCustom ? gravDown : SIMD4<Double>(0, 0, 0, -1)    // 好きな向きの重力（自動のあいだは −w から 35° まで）
        let gApp = nsLagGravity(dt, down: gDown) * Self.wG + nsShake(dt)
        // 傾けた重力：浅水は「床に垂直な分」が波の速さ、「床にそった分」が水面を傾ける（つり合うと傾き ＝ 横の分 ÷ 縦の分）
        let gN = max(0.5, -gDown.w), slope = simd_length(SIMD3(gDown.x, gDown.y, gDown.z)) / gN
        swe.tiltLim = gravCustom ? Float(1.15 * slope) : 0
        let ahS = SIMD3<Float>(Float(gApp.x), Float(gApp.y), Float(gApp.z)), ahS2 = SIMD2<Float>(Float(gApp.x), Float(gApp.y))
        swe.extraDamp = Float(0.9 * waterPauseK)                            // 止めている間は、波が 2 秒ほどで おさまるように
        // マウスを離したら（0.2 秒動かなかったら）、ゆれを 2 秒ほどで おだやかに。注ぐ所の波紋には効かせない。しばらくたったら元の静かさへ
        waterDragIdle += dt
        let ci = max(0, min(1, (waterDragIdle - 0.2) / 0.5)); swe.calmDamp = waterDragIdle < 6 ? Float(1.3 * ci * ci * (3 - 2 * ci)) : 0
        if h <= -0.999 { swe.reset() }
        else if paused || !(phase == 4 && !hole && vented) {
            let D = Float(max(0.02, (h + 1) * H)), nSub = min(12, Int(ceil(dt / WaterSWE.DT))), sd = Float(dt) / Float(max(1, nSub))
            for _ in 0..<max(1, nSub) {
                swe.noise = max(-1, min(1, swe.noise * 0.97 + Float.random(in: -1...1) * 0.35))   // 水の筋の勢いのゆらぎ
                let jet: Float = pouring && h > -0.98 ? Float(WaterSWE.JET) * (1 + swe.noise) : 0
                let sink: Float = flowing ? Self.wSINK * Float(min(1, (h + 1) * 2)) * Float(1 + 3 * max(0, waterBurst) / 0.45) : 0   // 開けた瞬間は強く吸い込む
                if waterBurst > 0 { waterBurst -= Double(sd) }
                swe.step(sd, g: Float(Self.wG * gN), D: D, jet: jet, H: Float(H), sink: sink, ah: ahS, ah2: ahS2)
                swe.rippleStep(sd, on: jet > 0 && waterReal, amp: Float(0.9 * H))   // 波紋：筋が水面をたたいている間
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
            let H4 = pow(H, 4), Vbox = 16 * H4, ball = ns.ballOn, Vcap = ns.capVol   // Vcap：水が入れる体積（内接球の壁があれば、玉の中を引いたもの）
            if t < nsPrevT - 1e-6 { ns.reset(level: -1); nsVTarget = 0 }       // 1 回りの始め：空に
            nsPrevT = t
            // 通気口（排水口があって、通気口ありの時）：上 +W の面の通気口を、外の空気につながった口にする（圧力 0）。底から抜ける分だけ、ここから空気が入る
            let ventOn = waterVent && drainShown
            // 満タンの上限：通気口があれば 100% まで（16⁴ 以上）。無ければ、いちばん上に空気の層が 1 マス以上残るように（空気が無いと、閉じた箱で水が抜けない）。
            //   8⁴ は通気口があっても 85%：満タンからは抜け始めなかった（原因はまだ分からない。2026-11-26）
            let fillMax = ventOn && ns.N >= Self.wFullN ? 0.995 : min(0.95, 1 - 1.2 / Double(ns.N))   // 8⁴ は 93% でも抜け始めなかった（空気の層が 1 マス要る）
            let vf = ns.lastVol / Vcap, pourOn = pouring && vf < fillMax + 0.02, Nf = Float(ns.N)
            ns.par.vort = Float(waterVort)
            ns.par.jetOn = pourOn ? 1 : 0; ns.par.topOpen = 0; ns.par.gvec = SIMD4<Float>(gApp); nsSetThin(ns); ns.par.jetD = SIMD4(0, 0, 0, -1); ns.par.pad2 = 0
            ns.par.ex2.z = ventOn ? max(0.55, 0.05 * Float(ns.N)) : 0             // 通気口の半分の幅（格子の単位。粗い格子でも 1 マスは開ける）
            ns.par.ex2.w = hole && phase == 4 && !paused && vf < 0.25 ? Float(Self.wFloorSlope * Self.wG) : 0   // 抜く間の最後（25% 未満）は、床が排水口へ少し傾いている（最後の水が口へ集まる）。はじめから入れると 12⁴ が満タンから抜けなかった
            // 入れる所：平均の水位（体積から：V ＝ 8(h＋1)）のすぐ上（2 マス上から 3 マス）。落ちる高さを小さく（天井から落とすと はねすぎる）。
            //   柱の水面を探すと、入れた水が下とつながった時に「水面がそこまで上がった」とまちがえて、入れる所が天井までのぼっていく
            let hAvg = max(-1, min(1, ns.lastVol / (8 * pow(H, 4)) - 1))
            // 内接球の壁がある時：天井から注ぐ（注ぐ所は玉の真上なので、水は玉に当たって、まわりを流れ落ちる。水面のすぐ上だと玉の中になって入らない）
            let l0 = ball ? ns.N - 3 : max(0, min(ns.N - 3, Int(((hAvg * H + H) / Double(ns.par.dx)).rounded()) + 1))   // 1 マス上（静かに）
            ns.par.jetC = SIMD4(Float(Self.wUS.x + 1) / 2 * Nf, Float(Self.wUS.y + 1) / 2 * Nf, Float(Self.wUS.z + 1) / 2 * Nf, Float(l0))
            let jr = 0.32, jv = 0.9                                            // 筋の太さ（世界の単位）と速さ：4 次元では筋の切り口も 3 次元の玉なので、太くないとなかなか溜まらない
            ns.par.jetR = Float(jr) / ns.par.dx; ns.par.jetV = Float(jv)
            ns.par.hole = !paused && hole && (phase == 4 || hOpen) ? Float(drainSize) * Nf / 2 : 0
            ns.par.open = !paused && !hole && phase == 4 ? 1 : 0
            if phase == 4 && nsPrevPhase != 4 && hole && waterSwirl > 0 { ns.addSwirl(Float(waterSwirl)) }   // 栓を抜いた瞬間：お風呂に残っている小さな回転
            nsPrevPhase = phase
            // 体積の目標：注いでいる間は、注ぐ時間でまっすぐ増やす（V(h) ＝ 8(h＋1) の連続の積分どおり。筋は見た目と波）。
            //   注ぎ終わったらその量を保つ。抜いている間は、減った分を目標に（体積の合わせ直しは、計算で少しずつ減る分を戻すだけ）
            if pouring && !hOpen { nsVTarget = max(nsVTarget, fillMax * Vcap * max(0, min(1, (t - t0) / (t1 - t0)))) }
            if hOpen && pouring { nsVTarget = ns.lastVol }
            if ns.par.hole > 0 || ns.par.open != 0 { nsVTarget = min(nsVTarget, ns.lastVol) }
            if !pouring && ns.lastVol < 1e-3 { nsVTarget = 0 }
            // 止めた瞬間に 1 回だけ、目標を今の量に（注ぐ途中で目標だけ先に進んでいた分は捨てる）。そのあとは目標を保つ：
            //   毎コマ「今の量」に合わせ直すと、計算で少しずつ減る分を戻さなくなって、止めている間に水がだんだん減っていた
            if paused && waterPauseT <= dt * 1.01 { nsVTarget = min(nsVTarget, ns.lastVol) }
            nsSloshKick(ns, dt)
            ns.tick(dt, target: nsVTarget < 1e-3 || (hOpen && pouring) ? nil : nsVTarget)
            // 水位：体積から（内接球の壁がある時は、玉のまわりの体積の式 V(h) を逆に解く）
            let hN = ball ? Self.ballWaterH(min(1, ns.lastVol / max(1e-9, Vcap)) * Self.ballWaterFull) : max(-1, min(1, ns.lastVol / (8 * H4) - 1))
            if abs(waterH - hN) > 1e-5 { waterH = hN }
            if phase == 4 && vf > Self.wVISIBLE && waterT > t4 - 0.1 && !hOpen { waterT = t4 - 0.1 }   // 抜けきるまで待つ（見えなくなるまで）
            // 抜け終わった（栓をする・空）：見えないほどの残り（底の水たまりのうすい膜）は、そこで空にする（最後のちょろちょろを待たない）
            if (phase == 5 || phase == 6) && !hOpen && ns.lastVol > 0 && vf <= Self.wVISIBLE { ns.reset(level: -1); nsVTarget = 0 }
        }
    }
}

extension OrigamiState {
    /// 箱を回した時のちゃぷちゃぷ：前のコマからの箱の回転 Q ＝ R₀ᵀR₁ の生成子 W ＝ (Q − Qᵀ)／(2dt)（箱から見た回る速さ）の、前との差 ΔW を水に渡す
    /// 箱にくっついた重力（箱の −w）を、水が感じる「下」として少し遅れさせる：遅れた向き L が今の向き R に 0.3×強さ 秒で追いつく。
    ///   箱から見た重力 ＝ Rᵀ L (0,0,0,−1)。回している間は回る前の「下」が残って水が寄り、止めると追いついてゆれもどる（ちゃぷちゃぷ）
    func nsLagGravity(_ dt: Double, down: SIMD4<Double> = SIMD4(0, 0, 0, -1)) -> SIMD4<Double> {
        let R = m4
        guard waterSlosh > 0.01, var L = nsLagM4 else { nsLagM4 = R; return down }
        let a = 1 - exp(-dt / (0.3 * waterSlosh))
        L = L + (R - L) * a
        // 列を正規直交に（グラム–シュミット）
        var c = [L.columns.0, L.columns.1, L.columns.2, L.columns.3]
        for i in 0..<4 { for j in 0..<i { c[i] -= simd_dot(c[i], c[j]) * c[j] }; let l = simd_length(c[i]); c[i] = l > 1e-9 ? c[i] / l : SIMD4(i == 0 ? 1 : 0, i == 1 ? 1 : 0, i == 2 ? 1 : 0, i == 3 ? 1 : 0) }
        L = simd_double4x4(c[0], c[1], c[2], c[3]); nsLagM4 = L
        let g = simd_transpose(R) * (L * down), gl = simd_length(g)
        return gl > 1e-9 ? g / gl : down
    }
    /// ゆさぶり：ドラッグの手の速さの変わり（加速度）を、箱から見た「見かけの力」（手と逆向き）にして重力に足す。急に動かす・止めると水が寄ってゆれもどる
    func nsShake(_ dt: Double) -> SIMD4<Double> {
        guard dt > 1e-4 else { return .zero }
        let vNow = waterShakeAcc / dt; waterShakeAcc = .zero
        let vS = waterShakeV + (vNow - waterShakeV) * min(1, dt / 0.14)        // 手の速さ（なめらかに：マウスの知らせはコマごとに 0〜2 回とばらつくので、そのままだと力がガタガタになって水面が沸いたようになる）
        let acc = (vS - waterShakeV) / dt; waterShakeV = vS
        // 画面の横 ＝ 景色の x、縦（下が ＋）＝ 景色の −y。手の加速度の逆向きを、箱の向きへ戻す
        var f = SIMD4<Double>(-acc.x, acc.y, 0, 0) * (0.12 * waterSlosh)
        let fl = simd_length(f); if fl > 3 { f *= 3 / fl }
        return simd_transpose(m4) * f
    }
    /// 本物の 4D の水のさらさら具合：粘り ν（世界の単位）と、波のブレーキ（ν に合わせて）。速さの運び方は MacCormack（ex2.y ＝ 1：マス目でなまる見かけの粘りを減らす）
    func nsSetThin(_ ns: NS4) {
        ns.par.nu = Float(waterNu); ns.par.ex2.x = Float(0.25 + 30 * waterNu); ns.par.ex2.y = 1
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
        let H = Self.half, Vbox = ns.capVol                                   // 水が入れる体積（内接球の壁があれば、玉の中を引いたもの）
        waterT += dt; waterTT += dt
        let first = !waterGDirInit
        let gdir = waterFreeGravity(dt)
        ns.par.gvec = SIMD4<Float>(gdir * waterG + nsShake(dt)); ns.par.vort = Float(waterVort); nsSetThin(ns)
        waterFreeTick3(dt, first: first)
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
        let hold = waterPourHold && !intPaused                              // 一時停止中は注がない
        ns.par.jetOn = hold && !full && ns.lastVol < nsVTarget + 0.01 * Vbox ? 1 : 0
        ns.par.jetD = SIMD4<Float>(gdir); ns.par.pad2 = 1; ns.par.ex2.z = 0; ns.par.ex2.w = 0   // 遊ぶモードは、ふたを開けて空気を入れる（通気口は使わない）
        ns.par.jetC = SIMD4<Float>((E / (2 * H) + 0.5) * Double(ns.N))
        ns.par.jetR = Float(0.24 * (0.7 + 0.3 * waterPourRate)) / ns.par.dx; ns.par.jetV = Float(0.5 * waterPourRate)   // 静かに
        ns.par.topOpen = waterLidSet ? 1 : 0
        let holeOn = waterBottomSet && drainMode == 1
        ns.par.hole = holeOn ? Float(drainSize) * Nf / 2 : 0
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
        if hold && !full { nsVTarget = min(0.88 * Vbox, max(nsVTarget, ns.lastVol) + 1.0 * waterPourRate * dt) }
        else if leaking { nsVTarget = min(nsVTarget, ns.lastVol) }
        nsVTarget = min(nsVTarget, ns.lastVol + 0.01 * Vbox)                // 目標が実際の量から離れすぎないように
        nsSloshKick(ns, dt)
        ns.tick(dt, target: nsVTarget < 1e-3 ? nil : nsVTarget, keepAir: true)
        let hN = max(-1, min(1, ns.lastVol / (8 * pow(H, 4)) - 1))
        if abs(waterH - hN) > 1e-5 { waterH = hN }
        let ph = hold ? 1 : (waterBottomSet && ns.lastVol > 1e-3 ? 4 : (ns.lastVol < 1e-3 ? 6 : 2))
        if waterPhase != ph { waterPhase = ph }
        waterPour = hold && waterCanPour ? Self.wTOP * H : -9
        // ふたの開け閉め（なめらかに）
        func step(_ x: Double, _ t: Double) -> Double { x + (t > x ? 1 : -1) * min(abs(t - x), dt * 2) }
        waterLid = step(waterLid, waterLidSet ? 1 : 0); waterBLid = step(waterBLid, waterBottomSet ? 1 : 0)
        waterOut = nil; _ = Vbox
    }
    /// 遊ぶモードの重力の向き（箱の x・y・z・w）。目標へ なめらかに回す（waterGDir に入れて返す）
    func waterFreeGravity(_ dt: Double) -> SIMD4<Double> {
        // 画面の下（景色の −y）を、箱の向きへ：写す行列の逆向き（回転なので転置）で戻す
        // 重力の向き：画面の奥（景色の −w ＝ w の消失点へ）か、画面の下（景色の −y）。写す行列の逆向き（回転なので転置）で箱の向きへ戻す。
        //   画面の奥の時は、3D の回転（見る向き）では変わらない＝見回しても水は傾かない。w を傾ける回転（X‐W・Y‐W・Z‐W）でだけ傾く
        //   箱の −w（2）：重力はいつも箱の −w（+W の口 → −W の底。積分と同じ）。回しても変わらない
        let gb = waterGravMode == 2 ? nsLagGravity(dt) : waterGravMode == 3 ? nsLagGravity(dt, down: gravDown) : simd_transpose(m4) * (waterGravMode == 0 ? SIMD4<Double>(0, 0, 0, -1) : SIMD4<Double>(0, -1, 0, 0)), gl = simd_length(gb)
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
        waterGDir = gdir
        return gdir
    }
    /// 遊ぶモードの左の 3D の水：同じ重力の設定を、左の立方体（x・y・z、z が右の w にあたる）の向きで。
    ///   箱の −w（2）→ 左の −z。画面の奥（0）・画面の下（1）→ 景色の −z・−y を、左の写し方の逆（その場の伸び方の逆行列）で箱の向きへ（玉と同じ）
    ///   重力は 2.5 rad/s で目標へ回り、水面の向きはその逆向きを ばねで追いかける（少し行き過ぎて ゆれもどる。強さは「ゆれ」の設定）
    func waterFreeTick3(_ dt: Double, first: Bool) {
        let H = Self.half
        var t3 = SIMD3<Double>(0, 0, -1)
        if waterGravMode == 3 {   // 好きな向き：右の w は左の z（右の z は左には無い）
            let d = gravDown, v = SIMD3(d.x, d.y, d.w); if simd_length(v) > 1e-6 { t3 = simd_normalize(v) }
        } else if waterGravMode != 2 {
            let o = place3([0, 0, 0]).0, cols = (0..<3).map { a -> SIMD3<Double> in var e = [0.0, 0, 0]; e[a] = 0.1; return (place3(e).0 - o) / 0.1 }
            let J = simd_double3x3(cols[0], cols[1], cols[2]), want: SIMD3<Double> = waterGravMode == 0 ? SIMD3(0, 0, -1) : SIMD3(0, -1, 0)
            if abs(J.determinant) > 1e-9 { let v = J.inverse * want; if simd_length(v) > 1e-9 { t3 = simd_normalize(v) } }
        }
        if first { waterGDir3 = t3; waterN3 = -t3; waterN3V = .zero }
        var g = waterGDir3
        let cs = max(-1, min(1, simd_dot(g, t3))), ang = acos(cs), stepA = 2.5 * dt
        if ang <= stepA { g = t3 } else {
            var pp = t3 - g * cs
            if simd_length(pp) < 1e-6 { for e in [SIMD3<Double>(1, 0, 0), SIMD3<Double>(0, 1, 0)] { let q = e - g * simd_dot(e, g); if simd_length(q) > 0.3 { pp = q; break } } }
            g = g * cos(stepA) + simd_normalize(pp) * sin(stepA)
        }
        waterGDir3 = g
        // 水面の向き：ばね（1 秒に約 1.1 回ゆれる）。ゆれの設定が大きいほど減りにくい
        let w0 = 7.0, ze = max(0.18, 1 - 0.8 * waterSlosh), sub = max(1, Int(ceil(dt / 0.02))), h = dt / Double(sub)
        for _ in 0..<sub {
            waterN3V += ((-g - waterN3) * (w0 * w0) - waterN3V * (2 * ze * w0)) * h
            waterN3 += waterN3V * h
        }
        let nl = simd_length(waterN3); waterN3 = nl > 1e-9 ? waterN3 / nl : -g
        // 筋が入る所：注ぐ場所（x・y のずれ）から上（重力の逆）へ、今の水面のすぐ上まで
        let up = -g, base = SIMD3<Double>(waterPourX, waterPourY, 0) * (0.55 * H)
        var tMax = 9.0
        for a in 0..<3 where abs(up[a]) > 1e-6 { tMax = min(tMax, ((up[a] > 0 ? 1 : -1) * 0.78 * H - base[a]) / up[a]) }
        let tw = tiltWater3(waterN3, (waterH + 1) / 2, H), nu = simd_dot(waterN3, up)
        let tSurf = nu > 0.2 ? (tw.c + 0.14 * H - simd_dot(waterN3, base)) / nu : tMax
        waterEntry3 = base + up * max(0, min(tMax, tSurf))
    }
    /// 遊ぶモード：超立方体の向きを変える（Y‐W の角 ay：−90° でふた（+W）が真上、−55° くらいでビールジョッキのようにななめ）。なめらかに回す
    /// 手で遊ぶ：▶ はじめる を押していなくても、注ぐ・向き・量のボタンで動き出す（組み上がっていなければ組み上げる。見る向きは変えない）
    func waterPlayStart() {
        guard !intOn else { if intPaused { intPaused = false }; return }
        intOn = true; intPaused = false
        if progress < 0.92 { playFold() }
    }
    func waterFreeView(ay: Double, xz: Double, yz: Double) {
        cycling = false; stopSpins(); playing = false; loop = false; viewSel = -1
        pend = [0, 0, 0, 0, 0]
        let to: [Double] = [0, ay, 0, 0, xz, yz]
        tween = (cur6, to, 0, 1.2, projBlend, projBlend); presetPar = projBlend; presetHold = SIMD3(to[0], to[1], to[2])
    }
    /// 遊ぶモード：水を入れ直す（−1 空・0 半分・0.9 ほぼいっぱい）
    func waterFreeFill(_ h: Double) { if let ns = ns4Get() { ns.reset(level: Float(h)); nsVTarget = ns.lastVol; waterH = h } }
}

/// 3D の立方体 [−H, H]³ を平面 n·p ＝ c で切った下側（n·p ≤ c）＝ 傾いた水。体積が frac（0〜1）になる c と、壁の多角形・水面の多角形。
///   体積は発散定理で：V ＝ (1/3)(H × 壁の面積の和 ＋ c × 水面の面積)。c は二分法で
struct TiltWater3 { var c: Double; var walls: [[SIMD3<Double>]]; var cap: [SIMD3<Double>] }
func tiltWater3(_ n0: SIMD3<Double>, _ frac: Double, _ H: Double) -> TiltWater3 {
    let nl = simd_length(n0), n = nl > 1e-9 ? n0 / nl : SIMD3<Double>(0, 0, 1)
    var faces: [[SIMD3<Double>]] = []
    for ax in 0..<3 { for sg in [-1.0, 1.0] {
        let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
        faces.append([(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { st in var p = SIMD3<Double>(0, 0, 0); p[ax] = sg * H; p[a1] = st.0 * H; p[a2] = st.1 * H; return p })
    } }
    func clip(_ poly: [SIMD3<Double>], _ c: Double) -> [SIMD3<Double>] {
        var out: [SIMD3<Double>] = []
        for i in 0..<poly.count {
            let a = poly[i], b = poly[(i + 1) % poly.count], da = simd_dot(n, a) - c, db = simd_dot(n, b) - c
            if da <= 0 { out.append(a) }
            if (da < 0) != (db < 0) && abs(da - db) > 1e-12 { out.append(a + (b - a) * (da / (da - db))) }
        }
        return out
    }
    func area(_ p: [SIMD3<Double>]) -> Double {
        guard p.count >= 3 else { return 0 }
        var s = SIMD3<Double>(0, 0, 0); for i in 1..<(p.count - 1) { s += simd_cross(p[i] - p[0], p[i + 1] - p[0]) }
        return simd_length(s) / 2
    }
    func cap(_ c: Double) -> [SIMD3<Double>] {
        var pts: [SIMD3<Double>] = []
        for ax in 0..<3 { let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3; for s in [-1.0, 1.0] { for t in [-1.0, 1.0] {
            var a = SIMD3<Double>(0, 0, 0); a[ax] = -H; a[a1] = s * H; a[a2] = t * H; var b = a; b[ax] = H
            let da = simd_dot(n, a) - c, db = simd_dot(n, b) - c
            if (da < 0) != (db < 0) && abs(da - db) > 1e-12 { pts.append(a + (b - a) * (da / (da - db))) }
        } } }
        guard pts.count >= 3 else { return [] }
        let ctr = pts.reduce(SIMD3<Double>(0, 0, 0), +) / Double(pts.count)
        let hlp: SIMD3<Double> = abs(n.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), e1 = simd_normalize(simd_cross(n, hlp)), e2 = simd_cross(n, e1)
        return pts.sorted { atan2(simd_dot($0 - ctr, e2), simd_dot($0 - ctr, e1)) < atan2(simd_dot($1 - ctr, e2), simd_dot($1 - ctr, e1)) }
    }
    func vol(_ c: Double) -> Double { (faces.reduce(0) { $0 + H * area(clip($1, c)) } + c * area(cap(c))) / 3 }
    let R = H * (abs(n.x) + abs(n.y) + abs(n.z)), target = max(0, min(1, frac)) * 8 * H * H * H
    var lo = -R, hi = R
    for _ in 0..<36 { let m = (lo + hi) / 2; if vol(m) < target { lo = m } else { hi = m } }
    let c = (lo + hi) / 2
    return TiltWater3(c: c, walls: faces.map { clip($0, c) }.filter { $0.count >= 3 }, cap: cap(c))
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
        var tris: [IntVert] = [], wtris: [IntVert] = [], ptris: [IntVert] = []   // ptris：水面に浮いたつぶ（水の面の後に重ねる）
        let real = st.waterReal
        /// リアルな水の板（3 つの点・面の向きは点の順から。kind：1 水面・0 壁と底）
        func wface(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ kind: Float, _ na: SIMD3<Double>? = nil, _ nb: SIMD3<Double>? = nil, _ nc: SIMD3<Double>? = nil) {
            var nn = simd_cross(b - a, c - a); let l = simd_length(nn); if l < 1e-12 { return }; nn /= l
            for (p, nv) in [(a, na ?? nn), (b, nb ?? nn), (c, nc ?? nn)] { wtris.append(IntVert(p: SIMD4(gpuW(p), 1), c: SIMD4(gpuW(nv), kind))) }
        }
        let A = Float(0.4 * k)                                            // 面の濃さ（ウェブ版の opacity 0.4）
        func P(_ u: [Double], _ w: Double) -> SIMD3<Double> { st.place(u.map { $0 * H } + [w], n).0 }
        // 排水口のくぼみ：吸い込む流れは中心ほど速く（4D は 3 方向から集まるので 1/r²）、速い所ほど水面が下がる（ベルヌーイ η ＝ −u²/2g ∝ 1/r⁴、真ん中は丸める）
        let vd = st.waterVD, HOLE = st.drainSize, hole = st.waterHoleNow, HR = HOLE * H
        func bern(_ u: [Double]) -> Double { let r = sqrt(u.reduce(0) { $0 + $1 * $1 }); return 0.8 * vd * H / (1 + pow(r / (0.45 * HOLE), 4)) }
        // 渦（お風呂の渦）：外から入ってきた水の回転は、角運動量が保たれるので真ん中ほど速い（回る速さ v ∝ 1/r）。
        //   速い所ほど水面が下がる（η ＝ −v²/2g ∝ 1/r²）。芯は丸めて η ＝ −D₀ /(1 ＋ (r/r_c)²)：ろうとの形。
        //   水が浅くなるほど回転が集まって深くなり、最後は空気の芯が排水口までつながる。
        //   4D：3D の水面の中で回るので、回る面は x‐y（本物の 4D の水の「渦の強さ」と同じ面）、芯は点ではなく z の線（とい）。排水口から z に離れるほど浅く（とがった細長いへこみ）
        let vk = min(1, vd / 0.3), depthA = max(0, (h + 1) * H), fillA = depthA / (2 * H)
        let vortOn = !(st.waterFree && st.waterNS) && vk > 0.01 && h > -0.99
        let D0 = vortOn ? st.waterSwirl * vk * H * (0.25 + 1.1 * (1 - fillA) * (1 - fillA)) : 0, VRC = 0.28 * st.drainSize / 0.58, VLY = 0.45, VT = st.waterTT
        // 渦の流れで運ばれる水面のさざ波：水面の模様を、渦の流れ（吸いこむ dr/dt ＝ −a/r、回る v ＝ Γ/r）でさかのぼった所から取ってくる。
        //   τ 秒前にいた所：r₀² ＝ r² ＋ 2aτ、θ₀ ＝ θ − (Γ/2a) ln(r₀²/r²)（水面のつぶと同じ対数らせん）。模様は回りながら中へ引きのばされて、らせんの筋になる。
        //   τ がずっと増えると巻きすぎるので、ずらした 2 枚を TP 秒ごとに入れかえて重ねる（片方が薄い時に、新しい模様に取りかえる）
        let FA = 0.07, FG = (0.5 + 0.9 * st.waterSwirl) * 0.6, FTP = 1.8, FAMP = 0.085 * H * vk * min(1, st.waterSwirl / 0.25 + 0.3)
        func flowRip(_ u: [Double], _ r2: Double) -> Double {
            guard FAMP > 1e-6, r2 < 1.9 else { return 0 }
            let r2c = max(r2, 1e-6), th = atan2(u[1], u[0]), zz = d == 3 ? u[2] : 0
            var s = 0.0, ww = 0.0
            for layer in 0..<2 {
                let ph = VT / FTP + 0.5 * Double(layer), cyc = floor(ph), fr = ph - cyc, tau = fr * FTP, w = 1 - abs(2 * fr - 1)
                let r02 = r2c + 2 * FA * tau, th0 = th - FG / (2 * FA) * log(r02 / r2c), r0 = sqrt(r02)
                let x0 = r0 * cos(th0), y0 = r0 * sin(th0), sd = cyc * 2.39 + Double(layer) * 5.1
                // 水面のさざ波の模様：向きのちがう 4 つの波の重ね合わせ（波長 0.3〜0.4。細かすぎると渦が目立たない）
                var n = 0.0
                for (i, kv) in [(0, SIMD3(17.0, 7.0, 5.0)), (1, SIMD3(-8.0, 16.0, -6.0)), (2, SIMD3(-14.0, -11.0, 8.0)), (3, SIMD3(5.0, -19.0, -9.0))] {
                    n += cos(kv.x * x0 + kv.y * y0 + kv.z * zz + sd * Double(i + 1) * 1.7)
                }
                s += w * n / 4; ww += w * w
            }
            s /= max(0.5, ww).squareRoot()                                    // 2 枚を重ねた時に薄くならないように
            // 真ん中（ろうとの中）は巻きすぎて細かすぎるので消す。壁の近くも少し弱く
            let r = sqrt(r2c), env = (1 - exp(-pow(r / 0.13, 2))) * exp(-pow(r / 1.3, 4)) * (d == 3 ? exp(-pow(zz / 0.8, 2)) : 1)
            return FAMP * env * s
        }
        func vortD(_ u: [Double]) -> Double {
            guard D0 > 1e-5 else { return 0 }
            let ux = u[0], uy = u[1], r2 = ux * ux + uy * uy, ty = d == 3 ? exp(-(u[2] / VLY) * (u[2] / VLY)) : 1
            return D0 * ty / (1 + r2 / (VRC * VRC)) + (real ? flowRip(u, r2) : 0)
        }
        func surfW(_ u: [Double]) -> Double {
            let e = d == 3 ? st.swe.sample3(SIMD3(u[0], u[1], u[2])) : st.swe.sample2(SIMD2(u[0], u[1]))
            // 波紋（リアルな水だけ。細かいので、線の図では描かない）
            let rp = real ? (d == 3 ? st.swe.rip3(SIMD3(u[0], u[1], u[2])) : st.swe.rip2(SIMD2(u[0], u[1]))) : 0
            return max(-H, min(H, h * H + thin * (e + rp) - (vd > 1e-4 ? bern(u) : 0) - vortD(u)))
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
        let sliceL0 = d == 2 && st.waterSlice > 0 && st.waterNS && st.ns4 != nil
        let nsW = d == 3 && st.waterNS ? st.ns4 : nil, nsOn = nsW != nil
        // 水玉（浅水だけ）：床をおおうほど水が無い間は、床いっぱいのうすい膜ではなく、床の中の「水玉」で描く。
        //   注ぐと、注いだ所に水玉ができて、床（4D では底の立方体の胞、左の窓では底の正方形）の中でふくらみ、床を満たしてから水かさが増えていく。
        //   抜く時は逆に、水かさが減って床だけになると、水玉にちぢんで排水口へ吸いこまれていく。
        //   水玉の厚み PUD（表面張力で、これより薄く広がれない）は、見せるために本物よりずっと厚く（注ぐ時間の約 2 割が水玉の間）
        let PUD = OrigamiState.wPuddle * H, cover = max(0, (h + 1) * H / PUD)
        let puddle = !nsOn && !sliceL0 && !(d == 2 && st.waterFree && st.waterNS) && cover < 1 && (hole || st.waterBLid < 0.01)
        // 輪切り：左の窓に、4D の水を 1 枚切った 3D の水（本物の 4D の水の時）
        let sliceNS = st.waterSlice > 0 && st.waterNS ? st.ns4 : nil, sliceL = sliceL0
        // ---- 内接球の壁（水の時）：玉は中まで詰まった玉なので、4 次元の目から見て玉の向こうにある水は、玉にかくれる ----
        //   目は 4D の回転で写した w ＝ D の所（箱の向きでは Mᵀ(0,0,0,D)）。平行投影の時は、見る向き Mᵀ(0,0,0,1) の光の線。玉の中の点もかくす
        //   見えない玉（waterBallLook 0）：玉はすき通っているので、向こうの水は見える。玉の中の水だけ消す（水面に玉の形の穴）
        let ballWall = st.waterBallOn, ballSeen = st.waterBallLook == 1, Mt = simd_transpose(st.m4), pbb = st.projBlend
        let E4 = Mt * SIMD4<Double>(0, 0, 0, st.camW), V4 = Mt * SIMD4<Double>(0, 0, 0, 1), RB = H, ROcc = H * OrigamiState.wBallOcc
        /// 玉のかげまでの近さ：目から点までの線が、玉の真ん中にいちばん近づく距離 − 半径（負ならかくれる）。点が少し動いても、それ以上は変わらない
        func sh4(_ q: SIMD4<Double>) -> Double {
            let lq = simd_length(q); if lq < ROcc { return lq - ROcc }
            // 見えない玉（玉の窓）：画面で玉に重なる所の水は、手前も向こうも描かない。水につかった玉の所が完全にすき通って、玉の形がはっきり分かる
            //   （本物なら玉ごしに手前と向こうの水が見えるが、分かりやすさを選んだ。2026-11-26 に相談して決めた）。見える玉：玉の向こうの水だけ
            if pbb > 0.5 { let sv = ballSeen ? max(0, -simd_dot(q, V4)) : -simd_dot(q, V4); return simd_length(q + V4 * sv) - ROcc }
            let dv = q - E4, tr = -simd_dot(E4, dv) / max(1e-12, simd_length_squared(dv))
            if !ballSeen { return simd_length(E4 + dv * max(0, tr)) - ROcc }
            let tt = max(0, min(1, tr))
            return (tt < 0.999 ? simd_length(E4 + dv * tt) : lq) - ROcc
        }
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
            // 玉のふちにかかる三角形：4 つに分けながら、かくれない所だけ描く（面の向きは三角形から）
            //   三角形のどの点も、4 つの見本の点（3 つの角と真ん中）のどれかから辺の長さ e 以内なので、見本がみな −e より下ならぜんぶかくれる・e より上ならぜんぶ見える
            func emitPart(_ q0: SIMD4<Double>, _ q1: SIMD4<Double>, _ q2: SIMD4<Double>, _ kd: Float, _ dep: Int) {
                let e = max(simd_length(q1 - q0), simd_length(q2 - q1), simd_length(q0 - q2)), sv = [sh4(q0), sh4(q1), sh4(q2), sh4((q0 + q1 + q2) / 3)]
                if sv.allSatisfy({ $0 < -e }) { return }
                let oc = sv[3] < 0
                if !sv.allSatisfy({ $0 > e }) && e > OrigamiState.wBallSeg && dep < 6 {
                    let m01 = (q0 + q1) / 2, m12 = (q1 + q2) / 2, m20 = (q2 + q0) / 2
                    emitPart(q0, m01, m20, kd, dep + 1); emitPart(m01, q1, m12, kd, dep + 1); emitPart(m20, m12, q2, kd, dep + 1); emitPart(m01, m12, m20, kd, dep + 1)
                    return
                }
                if oc { return }
                func pd(_ q: SIMD4<Double>) -> SIMD3<Double> { pj(SIMD4<Float>(Float(q.x), Float(q.y), Float(q.z), Float(q.w))) }
                let a = pd(q0), b = pd(q1), c = pd(q2)
                if real { wface(a, b, c, kd) } else { let col = kd > 0.5 ? Self.liqMen * 0.85 : Self.liqWall; face(a, b, c, col, col, col) }
            }
            for t in 0..<mesh.kind.count {
                if ballWall {
                    let q0 = SIMD4<Double>(mesh.p[3 * t]), q1 = SIMD4<Double>(mesh.p[3 * t + 1]), q2 = SIMD4<Double>(mesh.p[3 * t + 2])
                    let e = max(simd_length(q1 - q0), simd_length(q2 - q1), simd_length(q0 - q2)), sv = [sh4(q0), sh4(q1), sh4(q2), sh4((q0 + q1 + q2) / 3)]
                    if sv.allSatisfy({ $0 < -e }) { continue }
                    if !sv.allSatisfy({ $0 > e }) { emitPart(q0, q1, q2, mesh.kind[t], 0); continue }
                }
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
        } else if d == 2 && st.waterFree && st.waterNS {
            // 遊ぶモードの左：重力の向きに合わせて傾いた 3D の水（水面は平面、量は右の 4D の水と同じ割合）
            let frac = (h + 1) / 2
            if frac > 0.002 {
                let tw = tiltWater3(st.waterN3, frac, H)
                func Q(_ p: SIMD3<Double>) -> SIMD3<Double> { st.place([p.x, p.y, p.z], 3).0 }
                for poly in tw.walls {
                    let q = poly.map(Q)
                    for i in 1..<(q.count - 1) {
                        if real { wface(q[0], q[i], q[i + 1], 0) } else { face(q[0], q[i], q[i + 1], Self.liqWall, Self.liqWall, Self.liqWall, Float(0.3 * k)) }
                    }
                }
                if tw.cap.count >= 3 {
                    let q = tw.cap.map(Q), sc = SIMD3<Float>(Float(Self.liqSurf.x), Float(Self.liqSurf.y), Float(Self.liqSurf.z))
                    for i in 1..<(q.count - 1) {
                        if real { wface(q[0], q[i], q[i + 1], 1) } else { face(q[0], q[i], q[i + 1], sc, sc, sc, Float(0.3 * k)) }
                    }
                    if !real { for i in 0..<q.count { rod(q[i], q[(i + 1) % q.count], Self.liqMen) } }   // 水際の線（リアルな水では描かない：無いほうが水らしい）
                }
                // 開けた面（ふた ＋z・底 −z）に水が来ていたら、外へこぼれ落ちる筋（左の重力の向きへ）
                let g3 = st.waterGDir3, T = st.waterTT
                for (open, zq) in [(st.waterLidSet, H), (st.waterBottomSet, -H)] where open {
                    for i in 0..<7 { for j in 0..<7 {
                        let p = SIMD3<Double>(-H + (Double(i) + 0.5) * 2 * H / 7, -H + (Double(j) + 0.5) * 2 * H / 7, zq)
                        guard simd_dot(st.waterN3, p) < tw.c - 0.02 * H else { continue }
                        let hsh = sin(Double(i * 73 + j * 37) + zq) * 43758.5453
                        let f = (T * 1.6 + hsh - floor(hsh)).truncatingRemainder(dividingBy: 1), s0 = 0.9 * f * f, s1 = 0.9 * min(1, f + 0.12) * min(1, f + 0.12)
                        rod(Q(p + g3 * s0), Q(p + g3 * s1), Self.liqStream, 0.9 * (1 - f))
                    } }
                }
            }
        } else if h > -0.999 && puddle {
            // ---- 水玉：形は「p 乗の玉」（p ＝ 2 で まん丸、大きいほど四角い。床を満たすにつれて床の形に近づく）。広さ（体積）＝ 床 × cover ----
            let p = 2 + 14 * pow(cover, 4), g1 = exp(lgamma(1 + 1 / p)), D3 = d == 3
            let r = min(1, D3 ? cbrt(cover * exp(lgamma(1 + 3 / p)) / pow(g1, 3)) : sqrt(cover * exp(lgamma(1 + 2 / p)) / (g1 * g1)))
            // 真ん中：注ぐ間は注ぐ所・抜く時は排水口。重力を傾けていたら、低い方へ寄る。はみ出さないように
            let us = OrigamiState.wUS
            var c: [Double] = D3 ? [us.x, us.y, us.z] : [us.x, us.y]
            if hole && st.waterPhase >= 3 { c = c.map { _ in 0 } }
            let gD = st.gravCustom ? st.gravDown : SIMD4<Double>(0, 0, 0, -1), gt: [Double] = D3 ? [gD.x, gD.y, gD.z] : [gD.x, gD.y]
            let gl = sqrt(gt.reduce(0) { $0 + $1 * $1 })
            if gl > 1e-4 { for i in c.indices { c[i] += gt[i] / gl * min(1, gl * 4) * 0.9 } }
            for i in c.indices { c[i] = max(-(1 - r), min(1 - r, c[i])) }
            // 厚み：上は平ら、ふちは表面張力で丸く落ちる。排水口へ吸いこまれる間は、内へ向かう渦巻きのさざ波
            let drainFlow = hole && st.waterPhase == 4, T = st.waterTT
            func dep(_ rho: Double, _ th: Double) -> Double {
                var v = PUD * 1.2 * sqrt(max(0, 1 - pow(min(1, rho), 8)))
                if drainFlow && real { v += 0.18 * PUD * sin(26 * r * rho + 9 * T + 3 * th) * (1 - rho * rho) * min(1, rho * 4) }
                return max(0, v)
            }
            func pn(_ e: [Double]) -> Double { pow(e.reduce(0) { $0 + pow(abs($1), p) }, 1 / p) }
            let C0 = P(c, -H), up = P(c, -H + 0.3 * H) - C0
            func vnorm(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ out: SIMD3<Double>) -> SIMD3<Double> {
                var nn = simd_cross(a, b); let l = simd_length(nn); if l < 1e-12 { return simd_normalize(out) }
                nn /= l; return simd_dot(nn, out) < 0 ? -nn : nn
            }
            let wcol = SIMD3<Float>(Float(Self.liqSurf.x), Float(Self.liqSurf.y), Float(Self.liqSurf.z))
            if D3 {
                // 4D：床（底の立方体の胞）の中の水玉。床にふれている所は、胞の中の 3D の玉（超球が 3D の床にふれると、点から 3D の玉に広がるのと同じ）。
                //   玉は床の胞にぴったり（w ＝ −H のすぐ上）。床を満たし切る直前だけ、水面の高さ（PUD）まで持ち上げて、ふつうの水面へつなぐ
                let NT = 16, NP = 28, rhoS = 0.97
                let ss = max(0, min(1, (cover - OrigamiState.wPudLiftFrom) / (1 - OrigamiState.wPudLiftFrom))), lift = ss * ss * (3 - 2 * ss)
                let wB = -H + OrigamiState.wPudSit * H + (PUD - OrigamiState.wPudSit * H) * lift
                // 排水口へ吸いこまれる間のさざ波は、玉の半径のゆらぎで（w に持ち上げると胞から浮くので）
                func rip(_ th: Double, _ ph: Double) -> Double { drainFlow && real ? 1 + 0.05 * sin(14 * th + 9 * T + 3 * ph) : 1 }
                var V: [[SIMD3<Double>]] = []
                for i in 0...NT { let th = Double.pi * Double(i) / Double(NT); V.append((0..<NP).map { j in
                    let ph = 2 * Double.pi * Double(j) / Double(NP), e = [sin(th) * cos(ph), sin(th) * sin(ph), cos(th)], k1 = r * rhoS * rip(th, ph) / max(1e-9, pn(e))
                    return P([c[0] + e[0] * k1, c[1] + e[1] * k1, c[2] + e[2] * k1], wB)
                }) }
                // 玉の輪：3 つの向き（xy・yz・zx）の大きな輪を細い線で。平たい円ではなく 3D の玉だと分かるように
                let NRg = 48
                for (a, b) in [(0, 1), (1, 2), (2, 0)] {
                    var prev: SIMD3<Double>? = nil
                    for s in 0...NRg {
                        let t = 2 * Double.pi * Double(s) / Double(NRg)
                        var e = [0.0, 0, 0]; e[a] = cos(t); e[b] = sin(t)
                        let k1 = r * rhoS / max(1e-9, pn(e)), q = P([c[0] + e[0] * k1, c[1] + e[1] * k1, c[2] + e[2] * k1], wB)
                        if let pv = prev { rod(pv, q, Self.liqMen, OrigamiState.wPudRing * (1 - 0.6 * lift)) }
                        prev = q
                    }
                }
                for i in 0..<NT { for j in 0..<NP {
                    let j1 = (j + 1) % NP
                    let q = [V[i][j], V[i + 1][j], V[i + 1][j1], V[i][j1]]
                    func nAt(_ a: Int, _ b: Int) -> SIMD3<Double> { let bb = (b + NP) % NP; return vnorm(V[min(NT, a + 1)][bb] - V[max(0, a - 1)][bb], V[a][(bb + 1) % NP] - V[a][(bb - 1 + NP) % NP], V[a][bb] - C0) }
                    if real {
                        wface(q[0], q[1], q[2], 1, nAt(i, j), nAt(i + 1, j), nAt(i + 1, j1)); wface(q[0], q[2], q[3], 1, nAt(i, j), nAt(i + 1, j1), nAt(i, j1))
                    } else { face(q[0], q[1], q[2], wcol, wcol, wcol, Float(0.35 * k0)); face(q[0], q[2], q[3], wcol, wcol, wcol, Float(0.35 * k0)) }
                } }
            } else {
                // 3D：底の正方形の上の水玉（平らな上と、丸いふち）
                let NR = 18, NA = 64
                var V: [[SIMD3<Double>]] = []
                for i in 0...NR { let rho = Double(i) / Double(NR); V.append((0..<NA).map { j in
                    let th = 2 * Double.pi * Double(j) / Double(NA), e = [cos(th), sin(th)], k1 = r * rho / max(1e-9, pn(e))
                    return P([c[0] + e[0] * k1, c[1] + e[1] * k1], -H + dep(rho, th))
                }) }
                func nAt(_ a: Int, _ b: Int) -> SIMD3<Double> { let bb = (b + NA) % NA; return a == 0 ? simd_normalize(up) : vnorm(V[min(NR, a + 1)][bb] - V[max(0, a - 1)][bb], V[a][(bb + 1) % NA] - V[a][(bb - 1 + NA) % NA], up) }
                for i in 0..<NR { for j in 0..<NA {
                    let j1 = (j + 1) % NA, q = [V[i][j], V[i + 1][j], V[i + 1][j1], V[i][j1]]
                    if real {
                        wface(q[0], q[1], q[2], 1, nAt(i, j), nAt(i + 1, j), nAt(i + 1, j1)); wface(q[0], q[2], q[3], 1, nAt(i, j), nAt(i + 1, j1), nAt(i, j1))
                    } else { face(q[0], q[1], q[2], wcol, wcol, wcol, Float(0.35 * k0)); face(q[0], q[2], q[3], wcol, wcol, wcol, Float(0.35 * k0)) }
                } }
            }
            // 接点の光：注ぎはじめに水が床へ最初にふれた 1 点を光らせる（玉が小さい間だけ、だんだん消える）
            if st.waterPhase == 1 && cover < OrigamiState.wTouchTo {
                let f = 1 - cover / OrigamiState.wTouchTo, C = P(c, -H), L = OrigamiState.wTouchLen * H * (0.4 + 0.6 * f)
                let glow = SIMD3<Float>(0.85, 0.97, 1)
                func gl(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ br: Double, _ wd: Float) { rod(a, b, glow, br); rods[rods.count - 1].b.w = wd }
                for ax in 0..<(D3 ? 3 : 2) {
                    var u = c; u[ax] += L / H; let A = P(u, -H); u[ax] -= 2 * L / H; let B = P(u, -H)
                    gl(A, C, 2.6 * f, 1 + 2 * Float(f)); gl(C, B, 2.6 * f, 1 + 2 * Float(f))
                }
                gl(C, P(c, -H + 1.4 * L), 1.8 * f, 1 + Float(f))              // 水が来た向き（上 ＝ ＋w）へ短い光
            }
        } else if h > -0.999 {
            if d == 3 {
                // 水面の立方体（w ＝ h ＋ 揺れ）：6 面を G×G に分けて。色は頂点ごと（面の向きは隣の点から）
                for ax in 0..<3 { for sg in [-1.0, 1.0] {
                    let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                    if real {
                        // リアルな水面：細かく（24×24）、点ごとの面の向きで（なめらかな光）。網目の線は描かない
                        let G2 = 44                                         // 波紋の細かさ（波長 ≈ 0.28）まで出るように
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
                        if real { wface(A0, B0, B1, 0); wface(A0, B1, A1, 0) }   // リアルな水：水際の線は描かない（無いほうが水らしい）
                        else { face(A0, B0, B1, Self.liqWall, Self.liqWall, Self.liqWall); face(A0, B1, A1, Self.liqWall, Self.liqWall, Self.liqWall); rod(A1, B1, Self.liqMen) }
                    }
                } } }
                // 角の縦の線（w の方向）と、底の立方体（w ＝ −1）
                for v in 0..<8 {
                    let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1, v & 4 != 0 ? 1.0 : -1]
                    if !real { rod(P(u, -H), P(u, surfW(u)), (Self.liqCornB + Self.liqCornT) / 2) }
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
                let G = real ? 72 : G
                // リアルな水：真ん中ほど細かく（渦のろうとの細い所まで形が出るように）。端は ±1 のまま。端も波紋の波長が出る細かさに
                func gs(_ i: Int) -> Double { let s = -1 + 2 * Double(i) / Double(G); return real ? s * (0.45 + 0.55 * s * s) : s }
                var V: [[SIMD3<Double>]] = [], Dd: [[Double]] = []
                for i in 0...G { var row: [SIMD3<Double>] = [], drow: [Double] = []; for j in 0...G { let u = [gs(i), gs(j)], w = surfW(u); row.append(P(u, w)); drow.append(w / H - h) }; V.append(row); Dd.append(drow) }
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
                        if real { wface(A0, B0, B1, 0); wface(A0, B1, A1, 0) }   // リアルな水：水際の線は描かない（無いほうが水らしい）
                        else { face(A0, B0, B1, Self.liqWall, Self.liqWall, Self.liqWall, Float(0.3 * k)); face(A0, B1, A1, Self.liqWall, Self.liqWall, Self.liqWall, Float(0.3 * k)); rod(A1, B1, Self.liqMen) }
                    }
                } }
                for v in 0..<4 { let u = [v & 1 != 0 ? 1.0 : -1, v & 2 != 0 ? 1.0 : -1]; if !real { rod(P(u, -H), P(u, surfW(u)), (Self.liqCornB + Self.liqCornT) / 2) } }
                let b0 = P([-1, -1], -H), b1 = P([1, -1], -H), b2 = P([1, 1], -H), b3 = P([-1, 1], -H)
                if real { wface(b0, b1, b2, 0); wface(b0, b2, b3, 0) }
                else { face(b0, b1, b2, Self.liqBot, Self.liqBot, Self.liqBot, Float(0.3 * k)); face(b0, b2, b3, Self.liqBot, Self.liqBot, Self.liqBot, Float(0.3 * k)) }
            }
        }
        // 水の筋：ふたの先（w ＝ TOP×H）から水面まで、w の方向に落ちる（止めた後は、しっぽが落ちていく）。粒は g で加速しながら落ちる
        // 遊ぶモード（本物の 4D の水）：右も左も、重力の向きに落ちてくる筋（左は左の 3D の重力で）
        let free = st.waterFree && st.waterNS && (nsOn || d == 2)
        let us = free ? SIMD3(st.waterPourX, st.waterPourY, st.waterPourZ) : OrigamiState.wUS, top = st.waterPour
        let su: [Double] = d == 3 ? [us.x, us.y, us.z] : [us.x, us.y]
        var surfS = free ? H * 0.85 : h > -0.999 ? (nsW.map { min($0.surfaceWorld(SIMD3(us.x, us.y, us.z)), h * H + 0.08 * H) } ?? surfW(su)) : -H   // 本物の 4D：柱の水面と平均の水位の低いほう（入れたばかりの水に止まって見えないように）   // 遊ぶモード：筋はふたの近く（水を入れる所）まで
        // 内接球の壁：筋は玉の上で止まる（そこから玉のまわりを流れ落ちる）。玉の上の高さ ＝ √(1 − |注ぐ所|²)
        let r2 = su.reduce(0) { $0 + $1 * $1 }
        if st.inSphere && st.waterBallWall && st.waterNS && !free && r2 < 1 { surfS = max(surfS, H * sqrt(1 - r2)) }
        if top > surfS && !sliceL {
            let T = st.waterTT
            if real && free {
                // 遊ぶモード：画面の上から（重力の向きにまっすぐ）落ちてきて、ふた（+W）の注ぐ場所に入る透明な水の柱
                //   左の窓は、左の 3D の重力の向きと入る所で（x・y・z を SIMD4 の前の 3 つに）
                let g = d == 2 ? SIMD4(st.waterGDir3, 0) : st.waterGDir, E4 = d == 2 ? SIMD4(st.waterEntry3, 0) : st.waterEntry4, L = 1.7, MS = 24, K = 12
                func PL(_ q: SIMD4<Double>) -> SIMD3<Double> { d == 2 ? st.place([q.x, q.y, q.z], 3).0 : st.place([q.x, q.y, q.z, q.w], 4).0 }
                var rings: [[(SIMD3<Double>, SIMD3<Double>)]] = []
                for m in 0...MS {
                    let f = Double(m) / Double(MS), q = E4 - g * (L * (1 - f)), C = PL(q)
                    let q2 = q + g * 0.02, Cn = PL(q2), Tg = simd_normalize(Cn - C)
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
        if d == 3 && (hole || st.drainShown) && h > -0.99 && !nsOn && !puddle {
            // 排水口の真上の水の柱：4 次元の水は外側の皮しか描けないので、床の真ん中の上の水は見えない。穴の上の柱だけ描いて、水が排水口まで来ているのを見せる
            let R = HOLE, cW = Self.liqWall * 0.75, cTop = Self.liqMen * 0.8
            for ax in 0..<3 { for s1 in [-1.0, 1.0] { for s2 in [-1.0, 1.0] {
                let a1 = (ax + 1) % 3, a2 = (ax + 2) % 3
                var A = [0.0, 0, 0], B = [0.0, 0, 0]; A[ax] = -R; B[ax] = R; A[a1] = s1 * R; B[a1] = s1 * R; A[a2] = s2 * R; B[a2] = s2 * R
                let wa = surfW(A), wb = surfW(B), q0 = P(A, -H), q1 = P(B, -H), q2 = P(B, wb), q3 = P(A, wa)
                if real { continue }                                           // リアルな水：柱は描かない（水面に排水口の口の形が写って見えるので）
                face(q0, q1, q2, cW, cW, cW); face(q0, q2, q3, cW, cW, cW)
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
                for q in 0..<(real ? 0 : 10) {   // 柱の中を穴へ流れ込む水の筋（リアルな水では描かない）
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
            if !st.drainShown { edges(HOLE, -H, rimC, 1) }
            let po = st.waterBLid, pw = -H + po * 0.55 * H, pa = 1 - 0.75 * po
            if pa > 0.05 && !st.holesOpen && !st.drainShown {
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
            if vd > 0.01 && h > -0.999 && !nsOn && !sliceL && !real {   // 線の図の渦（リアルな水では、下のろうとの面と、吸いこまれるつぶ）
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
        if vortOn && real && d == 3 && D0 > 0.01 * H {
            // 右の窓の渦：4D の水面の真ん中は皮の内側なので見えない。z の 3 か所で水面を切った断面（x‐y × 高さ w）を、透けるろうとの面で描く。
            //   真ん中（排水口の真上）が深く、z に離れた 2 枚は浅い（とい）。外へ行くほど透明にして、水面にとけこませる
            let NR = 18, NT = 32, ROUT = 0.78
            func nrmAt(_ u: [Double]) -> SIMD3<Double> {
                let e = 0.02
                func Q(_ dx: Double, _ dy: Double) -> SIMD3<Double> { let v = [u[0] + dx, u[1] + dy, u[2]]; return P(v, surfW(v)) }
                let nn = simd_cross(Q(e, 0) - Q(-e, 0), Q(0, e) - Q(0, -e)), l = simd_length(nn); return l > 1e-12 ? nn / l : SIMD3(0, 1, 0)
            }
            for (zz, al0) in [(0.0, 0.6), (-0.42, 0.3), (0.42, 0.3)] {
                var V: [[(SIMD3<Double>, SIMD4<Float>, Bool)]] = []
                for i in 0...NR {
                    let r = ROUT * pow(Double(i) / Double(NR), 1.7), fa = Float(al0 * vk * k * (1 - pow(r / ROUT, 2)))
                    V.append((0...NT).map { j in
                        let th = 2 * .pi * Double(j) / Double(NT), u = [r * cos(th), r * sin(th), zz], w = surfW(u), p = P(u, w)
                        let c = (surfColor(p, nrmAt(u), w / H - h) + SIMD3<Float>(0.45, 0.8, 1)) * 0.6   // 暗くなりすぎないように、明るい水色を半分まぜる
                        return (p, SIMD4(c * fa, fa), w <= -H + 1e-3)
                    })
                }
                for i in 0..<NR { for j in 0..<NT {
                    for tr in [[(i, j), (i + 1, j), (i + 1, j + 1)], [(i, j), (i + 1, j + 1), (i, j + 1)]] {
                        let vs = tr.map { V[$0.0][$0.1] }
                        if vs.allSatisfy({ $0.2 }) { continue }                    // 空気の芯が底まで届いた所（排水口への穴）は描かない
                        for v in vs { tris.append(IntVert(p: SIMD4(gpuW(v.0), 1), c: v.1)) }
                    }
                } }
            }
        }
        if vortOn && !sliceL && !real {   // リアルな水では、つぶの帯の代わりに水面のさざ波が渦の流れで運ばれる（flowRip）
            // 水面に浮いたつぶ（泡・ほこり）：回りながら真ん中へ吸いこまれる。吸いこむ流れ dr/dt ＝ −a/r と、回る速さ v ＝ Γ/r（角運動量が保たれる）から
            //   r² ＝ r₀² − 2at、θ ＝ θ₀ ＋ (Γ/2a) ln(r₀²/r²)：対数らせん。真ん中に近いほど速く回り、ろうとを下って消える。4D は x‐y で回り、z も排水口へ寄っていく
            let NP = d == 3 ? 60 : 44, TL = 4.5, RE = 0.07, om0 = 0.5 + 0.9 * st.waterSwirl
            func hs(_ x: Double) -> Double { let y = sin(x) * 43758.5453; return y - floor(y) }
            for q in 0..<NP {
                let qd = Double(q), r0 = 0.92 * (0.6 + 0.4 * hs(qd * 1.37 + 0.2)), th0 = 2 * .pi * hs(qd * 2.71 + 0.5), y0 = (hs(qd * 3.33 + 0.9) * 2 - 1) * 0.85
                let a = (r0 * r0 - RE * RE) / (2 * TL), Gm = om0 * r0 * r0
                func at(_ t: Double) -> [Double] {
                    let r2 = max(RE * RE, r0 * r0 - 2 * a * t), r = sqrt(r2), th = th0 + Gm / (2 * a) * log(r0 * r0 / r2)
                    return d == 3 ? [r * cos(th), r * sin(th), y0 * r / r0] : [r * cos(th), r * sin(th)]
                }
                let t = (T / TL + hs(qd * 5.1 + 0.3)).truncatingRemainder(dividingBy: 1) * TL
                let r2n = max(RE * RE, r0 * r0 - 2 * a * t), dtS = min(0.35, 1.4 * r2n / Gm)   // 尾の長さ：速く回る所は短い時間ぶん（尾が回る角度をそろえる）
                let f = t / TL, al = vk * min(1, f * 6) * min(1, (1 - f) * 4)
                if al < 0.02 { continue }
                // 通ってきた道を、すける細い帯の尾で（先が濃く、後ろほど透明に）。線（rod）は濃さを変えると暗くなるので、三角形で
                let NS = 6, wd = (0.006 + 0.005 * hs(qd * 7.7)) * H, ln = 0.45 + 0.75 * hs(qd * 4.3), aq = 0.4 + 0.45 * hs(qd * 9.1)   // つぶごとに太さ・尾の長さ・濃さをばらばらに
                var pts: [SIMD3<Double>] = []
                for m in 0...NS { let u = at(max(0, t - ln * dtS * Double(m) / Double(NS))); pts.append(P(u, surfW(u) + 0.03 * H)) }
                for m in 0..<NS {
                    let a0 = pts[m], b0 = pts[m + 1], dir = b0 - a0
                    var sd = simd_cross(dir, eye - a0); let sl = simd_length(sd); if sl < 1e-12 { continue }; sd *= wd / sl
                    let fa = Float(al * aq * (1 - Double(m) / Double(NS))), fb = Float(al * aq * (1 - Double(m + 1) / Double(NS)))
                    let ca = SIMD4<Float>(0.9 * fa, 0.97 * fa, fa, fa), cb = SIMD4<Float>(0.9 * fb, 0.97 * fb, fb, fb)
                    for (q, c) in [(a0 + sd, ca), (a0 - sd, ca), (b0 - sd, cb), (a0 + sd, ca), (b0 - sd, cb), (b0 + sd, cb)] { ptris.append(IntVert(p: SIMD4(gpuW(q), 1), c: c)) }
                }
            }
        }
        if d == 2 && st.waterVent && st.waterPhase == 4 {   // 左：抜いている間は、上ぶたの通気口から空気が入っていく
            for q in 0..<6 {
                let f = (T * 1.2 + Double(q) / 6).truncatingRemainder(dividingBy: 1), z0 = H + (1 - f) * 0.9 * H, ox = cos(Double(q) * 2.4) * 0.06, oy = sin(Double(q) * 2.4) * 0.06, a = sin(.pi * f) * 0.8
                rod(P([-0.5 + ox, 0.5 + oy], z0), P([-0.5 + ox, 0.5 + oy], z0 - 0.12 * H), SIMD3<Float>(0.85, 0.9, 1), a)
            }
        }
        // ---- 内接球の壁（左の 3D の窓）：3D の目から見て、玉の向こうと玉の中の水をかくす（描く側の座標で。ふちにかかる三角形は分ける）----
        // 玉の写し絵（描く側の 3D の玉）：左 3D はそのまま。4D は 4D の玉を写した 3D の玉（真ん中は写した原点、半径は目から見たふちの点までの距離）
        func ballImage() -> (SIMD3<Double>, Double) {
            if d == 2 { let c = P([0, 0], 0); return (c, simd_length(P([1, 0], 0) - c)) }
            let c = st.place([0, 0, 0, 0], 4).0, De = simd_length(E4), axis = pbb > 0.5 ? V4 : E4 / max(1e-9, De)
            let c0 = pbb > 0.5 ? SIMD4<Double>(0, 0, 0, 0) : axis * (RB * RB / De), rs = pbb > 0.5 ? RB : RB * sqrt(max(0, 1 - RB * RB / (De * De)))
            var u = SIMD4<Double>(1, 0, 0, 0) - axis * axis.x; if simd_length(u) < 0.3 { u = SIMD4<Double>(0, 1, 0, 0) - axis * axis.y }; u = simd_normalize(u)
            let X = c0 + u * rs
            return (c, simd_length(st.place([X.x, X.y, X.z, X.w], 4).0 - c))
        }
        // 見えない玉は 4D でも左と同じ「玉の窓」：画面で玉の写し絵に重なる水は描かない（見える玉の 4D は、4D の目で玉の向こうだけ）
        if ballWall && !sliceL && (d == 2 || !ballSeen) {
            let bim = ballImage()
            let eyeG = gpuW(eye), Cg = gpuW(bim.0), RG = Float(bim.1), RO = RG * Float(OrigamiState.wBallOcc), seg = RG * 0.025   // ふちがぎざぎざにならないように細かく
            func occ3(_ q: SIMD4<Float>) -> Bool {
                let p = SIMD3<Float>(q.x, q.y, q.z)
                if simd_length(p - Cg) < RO { return true }
                let dv = p - eyeG, tr = simd_dot(Cg - eyeG, dv) / max(1e-12, simd_length_squared(dv))
                if !ballSeen { return simd_length(eyeG + dv * max(0, tr) - Cg) < RO }   // 玉の窓：手前も向こうも
                let tt = max(0, min(1, tr))
                return tt < 0.999 && simd_length(eyeG + dv * tt - Cg) < RO
            }
            func filt(_ v: [IntVert], _ isNormal: Bool) -> [IntVert] {
                var outV: [IntVert] = []; outV.reserveCapacity(v.count)
                func mid(_ a: IntVert, _ b: IntVert) -> IntVert {
                    var c = (a.c + b.c) * 0.5
                    if isNormal { let nv = SIMD3<Float>(c.x, c.y, c.z), l = simd_length(nv); if l > 1e-6 { c = SIMD4<Float>(nv / l, a.c.w) } }
                    return IntVert(p: (a.p + b.p) * 0.5, c: c)
                }
                func rec(_ a: IntVert, _ b: IntVert, _ c: IntVert, _ dep: Int) {
                    let ctr = (a.p + b.p + c.p) / 3
                    let oa = occ3(a.p), ob = occ3(b.p), oc = occ3(c.p), om = occ3(ctr)
                    if oa && ob && oc && om { return }
                    let big = max(simd_length(a.p - b.p), simd_length(b.p - c.p), simd_length(c.p - a.p)) > seg
                    if (oa || ob || oc || om) && big && dep < 7 {
                        let ab = mid(a, b), bc = mid(b, c), ca = mid(c, a)
                        rec(a, ab, ca, dep + 1); rec(ab, b, bc, dep + 1); rec(ca, bc, c, dep + 1); rec(ab, bc, ca, dep + 1)
                        return
                    }
                    if !om { outV.append(a); outV.append(b); outV.append(c) }
                }
                var i = 0; while i + 2 < v.count { rec(v[i], v[i + 1], v[i + 2], 0); i += 3 }
                return outV
            }
            wtris = filt(wtris, true); tris = filt(tris, false); ptris = filt(ptris, false)   // 水面のつぶも
        }
        // ---- 水の時の内接球（水専用の玉）：ワイヤーや模様は無しの、すき通った玉と接点。玉の壁の時は、水につかった所を水色に、水ぎわに光る輪 ----
        //   左（3D）は水の前に描く（玉の向こうの水はもう消してあるので、手前の水が玉にかかる）。右（4D）は手前の胞の水ごしになって見えなくなるので、水の後に重ねる
        var btris: [IntVert] = []
        if st.inSphere && ballSeen { waterBall(&btris, &rods, d: d, h: h, k: k, eye: eye, wall: ballWall, E4: E4, V4: V4, par: pbb > 0.5) }
        // 左 3D：水につかった玉の面（球の下の部分 z ＜ 水位）は、水と玉の中の空気のさかい目＝水の壁。水の壁と同じ水で描く（玉の中に水が無いのが分かる：水の中の泡のように）。
        //   半径は水面の穴（かくす半径 0.97）とそろえる。面の向きは水から玉の中へ
        if st.inSphere && ballWall && ballSeen && d == 2 && h > -0.999 {   // 見える玉の時だけ（見えない玉は、玉の中に何も描かない）
            let Rc = RB * OrigamiState.wBallOcc, cz = max(-1, min(1, h * H / Rc)), th0 = acos(cz), NT = 16, NP = 40
            let Cc = P([0, 0], 0)
            var V: [[SIMD3<Double>]] = []
            for i in 0...NT { let th = th0 + (Double.pi - th0) * Double(i) / Double(NT); V.append((0..<NP).map { j in
                let ph = 2 * Double.pi * Double(j) / Double(NP)
                return P([Rc * sin(th) * cos(ph) / H, Rc * sin(th) * sin(ph) / H], Rc * cos(th))
            }) }
            func nIn(_ p: SIMD3<Double>) -> SIMD3<Double> { let v = Cc - p, l = simd_length(v); return l > 1e-12 ? v / l : SIMD3(0, 0, 1) }
            for i in 0..<NT { for j in 0..<NP {
                let j1 = (j + 1) % NP, q = [V[i][j], V[i + 1][j], V[i + 1][j1], V[i][j1]]
                if real { wface(q[0], q[1], q[2], 0, nIn(q[0]), nIn(q[1]), nIn(q[2])); wface(q[0], q[2], q[3], 0, nIn(q[0]), nIn(q[2]), nIn(q[3])) }
                else { face(q[0], q[1], q[2], Self.liqWall, Self.liqWall, Self.liqWall); face(q[0], q[2], q[3], Self.liqWall, Self.liqWall, Self.liqWall) }
            } }
        }
        // 見えない玉：玉そのものも、輪郭の線も描かない（水につかった玉の所は、水が何も無い窓。2026-11-26 に線は消すことに）
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
        if !ptris.isEmpty { out.append(IntTriBatch(add: false, verts: ptris)) }
        if !btris.isEmpty { out.append(IntTriBatch(add: false, verts: btris)) }
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

// ---- 好きな向きの重力（waterGravMode ＝ 3）：つまみと、画面の重力ハンドル（矢印の先の玉をドラッグ）----
//   重力は箱から見た向き（x・y・z・w）で持つ。箱を回すと重力もいっしょに回る（+W→−W と同じ考え方。回した時の遅れ・ゆれも同じ）。
//   手で遊ぶ（本物の 4D）はどの向きでも。ほか（自動・浅水）は −w から 35° まで：浅水は「床の上の高さ」で水を表すので、傾けすぎると床が乾いて計算できない
extension OrigamiState {
    static let gravMaxTilt = 35.0 * Double.pi / 180
    static let gravLen = 1.2                                          // 矢印の長さ（H の何倍か）
    // 右の窓：矢印は真ん中から x・y・z の分だけ（−w は遠近で消失点へ向かうので、そのまま描くと点になる）。w の分は真ん中の輪のメーターで
    static let gravRing = 0.6                                        // w のメーターの輪の半径（w ＝ 0 の時。H の何倍か）。−w で縮み、+w で広がる
    static let gravRingK = 0.5                                        // 輪の伸び縮み（w ＝ ±1 で 1 ∓ この分）
    /// 好きな向きの重力を使っているか
    var gravCustom: Bool { intOn && intMethod == 1 && waterGravMode == 3 }
    /// どの向きにも傾けてよいか（手で遊ぶ・本物の 4D の水）
    var gravAnyTilt: Bool { waterFree && waterNS }
    /// 箱から見た「下」（長さ 1。自動・浅水では −w から 35° まで）
    var gravDown: SIMD4<Double> {
        var g = SIMD4(gravX, gravY, gravZ, gravW); let l = simd_length(g)
        g = l > 1e-6 ? g / l : SIMD4(0, 0, 0, -1)
        return gravAnyTilt ? g : Self.gravClamp(g)
    }
    /// −w からの傾きを 35° までに
    static func gravClamp(_ g: SIMD4<Double>) -> SIMD4<Double> {
        guard acos(max(-1, min(1, -g.w))) > gravMaxTilt else { return g }
        let t = SIMD3(g.x, g.y, g.z), tl = simd_length(t), dir = tl > 1e-9 ? t / tl : SIMD3<Double>(1, 0, 0)
        return SIMD4(dir * sin(gravMaxTilt), -cos(gravMaxTilt))
    }
    /// −w からの傾き（度）
    var gravTiltDeg: Double { acos(max(-1, min(1, -gravDown.w))) * 180 / .pi }
    /// 向きを入れる（長さ 1 に。35° までの時は、そこで止める）
    func gravSet(_ g: SIMD4<Double>) {
        let l = simd_length(g); guard l > 1e-6 else { return }
        var v = g / l; if !gravAnyTilt { v = Self.gravClamp(v) }
        gravX = v.x; gravY = v.y; gravZ = v.z; gravW = v.w
    }
    /// この窓に重力ハンドルを出すか（右の超立方体・左の立方体）
    func gravHandleOn(_ n: Int) -> Bool { gravCustom && gravHandleShow && n <= 4 && progress > 0.95 }
    /// 矢印の根もと（真ん中）と先（写した 3D の位置）。右の窓は x・y・z の分だけ（w ＝ 0 の面の中）。左の窓は右の x・y・w を x・y・z に
    func gravHandlePts(_ n: Int, _ d0: SIMD4<Double>? = nil) -> (SIMD3<Double>, SIMD3<Double>) {
        let H = Self.half, d = d0 ?? gravDown, L = Self.gravLen * H
        if n == 4 { let t = SIMD3(d.x, d.y, d.z) * L; return (place4([0, 0, 0, 0]).0, place4([t.x, t.y, t.z, 0]).0) }
        var v = SIMD3(d.x, d.y, d.w); let l = simd_length(v); v = l > 1e-6 ? v / l : SIMD3(0, 0, -1)
        let t3 = v * L
        return (place3([0, 0, 0]).0, place3([t3.x, t3.y, t3.z]).0)
    }
    /// w のメーターの輪の半径（写した 3D の長さ。真ん中のまわり、画面に平行）
    func gravRingR(_ d0: SIMD4<Double>? = nil) -> Double { Self.gravRing * Self.half * (1 + Self.gravRingK * (d0 ?? gravDown).w) }
    /// 写した 3D の点を、窓の上のポイント（左上が 0）へ（軸の名前・点の札と同じ写し方）
    func gravScreen(_ n: Int, _ p: SIMD3<Double>, size: CGSize) -> CGPoint? {
        let i = wix(n), c = center[i], tanF = tan(22.5 * Double.pi / 180), W = Double(size.width), Hh = Double(size.height)
        guard W > 1, Hh > 1 else { return nil }
        let asp = W / Hh, z = dist[i] - p.z, ps = raster ? pan[i] : .zero
        guard z > 0.1 else { return nil }
        return CGPoint(x: ((p.x - c.x) / (z * tanF * asp) * 0.5 + 0.5 + ps.x * 0.5) * W, y: (0.5 - (p.y - c.y) / (z * tanF) * 0.5 - ps.y * 0.5) * Hh)
    }
    /// 押した所が、矢印の先の玉か、右の窓の w のメーターの輪の近くか（輪なら gravGrabW）
    func gravHit(_ n: Int, _ at: CGPoint, size: CGSize) -> Bool {
        gravGrabW = false
        let (o, tip) = gravHandlePts(n)
        guard let s = gravScreen(n, tip, size: size) else { return false }
        let dTip = hypot(s.x - at.x, s.y - at.y)
        if dTip < 12 { return true }
        if n == 4, let c = gravScreen(n, o, size: size), let e = gravScreen(n, o + SIMD3(gravRingR(), 0, 0), size: size) {
            let rs = hypot(e.x - c.x, e.y - c.y), dd = hypot(at.x - c.x, at.y - c.y)
            if abs(dd - rs) < 12 && dd > 2 { gravGrabW = true; gravGrabDir = SIMD2(Double(at.x - c.x), Double(at.y - c.y)) / Double(dd); return true }
        }
        return dTip < 26
    }
    /// ハンドルのドラッグ：ふつうは矢印の先が指についてくるように向きを回す（見えている 3D の中で）。⌥ は w の方へ倒す（上へ ＝ +w）。
    ///   左の窓では、右の x・y・w を回す
    func gravDrag(_ n: Int, _ dx: Double, _ dy: Double, alt: Bool, size: CGSize) {
        var d = SIMD4(gravX, gravY, gravZ, gravW); let l0 = simd_length(d); d = l0 > 1e-6 ? d / l0 : SIMD4(0, 0, 0, -1)
        if (alt || gravGrabW) && n == 4 {   // w の方へ：⌥ は上へ ＝ +w、輪は外へ ＝ +w（つかんだ所から外向きの動きの分）
            let ew = SIMD4<Double>(0, 0, 0, 1), t = ew - d * simd_dot(ew, d), a = gravGrabW ? (dx * gravGrabDir.x + dy * gravGrabDir.y) * 0.006 : -dy * 0.01
            if simd_length(t) > 1e-6 { d = d * cos(a) + simd_normalize(t) * sin(a) }
            gravSet(d); return
        }
        func scr(_ v: SIMD4<Double>) -> SIMD2<Double>? { gravScreen(n, gravHandlePts(n, v).1, size: size).map { SIMD2(Double($0.x), Double($0.y)) } }
        guard let s0 = scr(d) else { return }
        // 動かしてよい向き：右は x・y・z、左は x・y・w（左の z）。今の向きに垂直な成分だけ（長さ 1 のまま回す）
        let axes: [SIMD4<Double>] = n == 4 ? [SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0)] : [SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 0, 1)]
        var B: [SIMD4<Double>] = []
        for e in axes { var t = e - d * simd_dot(e, d); for b in B { t -= b * simd_dot(t, b) }; let tl = simd_length(t); if tl > 0.15 { B.append(t / tl) } }
        // 画面の動き ＝ J c（J は 2 × 本数）。いちばん小さい c で、指の動きにそろえる：c ＝ Jᵀ (J Jᵀ ＋ λ)⁻¹ δ
        var J: [SIMD2<Double>] = []
        for b in B { guard let s1 = scr(simd_normalize(d + b * 0.01)) else { return }; J.append((s1 - s0) / 0.01) }
        var a11 = 1e-3, a12 = 0.0, a22 = 1e-3
        for j in J { a11 += j.x * j.x; a12 += j.x * j.y; a22 += j.y * j.y }
        let det = a11 * a22 - a12 * a12; guard abs(det) > 1e-12 else { return }
        let dl = SIMD2(dx, dy), y = SIMD2((a22 * dl.x - a12 * dl.y) / det, (-a12 * dl.x + a11 * dl.y) / det)
        var step = SIMD4<Double>(0, 0, 0, 0)
        for (k, b) in B.enumerated() { step += b * simd_dot(J[k], y) }
        let sl = simd_length(step); if sl > 0.3 { step *= 0.3 / sl }     // 1 回で大きく跳ばない
        gravSet(d + step)
    }
}

@inline(__always) private func gpuG(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 好きな向きの重力の矢印：真ん中から、光る芯の入った軸・円すいの頭・軸を流れていく光の粒（重力の向きに落ちていく感じ）。つかむ所は頭の先の輪。
    ///   右の窓は x・y・z の分だけを矢印に、w の分は真ん中の紫の輪のメーター（点線の輪が w ＝ 0。縮むほど −w、広がるほど +w。波の輪がそちらへ動く）。
    ///   つかんでいる間は全体を明るく
    func gravHandleGeometry(_ rods: inout [TLRod], _ balls: inout [TLBall]) {
        guard st.gravHandleOn(n) else { return }
        let (o, tip) = st.gravHandlePts(n), v = tip - o, L = simd_length(v), gr = st.gravGrab, H = OrigamiState.half
        let amber = SIMD3<Float>(1, 0.62, 0.2), gold = SIMD3<Float>(1, 0.88, 0.55), core = SIMD3<Float>(1, 0.97, 0.85), violet = SIMD3<Float>(0.72, 0.5, 1)
        let kB: Float = gr ? 1.5 : 1.0
        func R(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Float>, _ w: Float, _ br: Float) { rods.append(TLRod(a: SIMD4(gpuG(a), 0), b: SIMD4(gpuG(b), w), col: SIMD4(c, br * kB))) }
        func mark(_ p: SIMD3<Double>, _ r: Double, _ c: SIMD3<Float>) {
            let m = TLBall(p: SIMD4(gpuG(p), Float(r)), col: SIMD4(c, 3))
            if st.raster { marks.append(m) } else { balls.append(m) }
        }
        let t = Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1000)
        if L > 0.05 * H {
            let u = v / L
            var p1 = simd_cross(u, SIMD3<Double>(0, 0, 1)); if simd_length(p1) < 1e-3 { p1 = simd_cross(u, SIMD3<Double>(0, 1, 0)) }; p1 = simd_normalize(p1)
            let p2 = simd_cross(u, p1), hl = min(0.22 * L, 0.28 * H), rr = hl * 0.36, C = tip - u * hl
            let ring = (0..<12).map { k -> SIMD3<Double> in let a = Double(k) / 12 * 2 * .pi; return C + (p1 * cos(a) + p2 * sin(a)) * rr }
            R(o, C, amber, 4.2, 1.3); R(o, C, core, 1.4, 2.2)                // 軸：琥珀色の太い線と、白く光る芯
            for (k, q) in ring.enumerated() { R(q, tip, k % 3 == 0 ? gold : amber, 1.6, 1.5); R(q, ring[(k + 1) % 12], gold, 1.8, 1.6) }
            R(C, tip, core, 1.4, 2.4)
            for k in 0..<4 {                                                  // 流れる光の粒（1 秒に 0.9 回、両はしでふわっと消える）
                let f = (t * 0.9 + Double(k) / 4).truncatingRemainder(dividingBy: 1), fade = Float(sin(.pi * f))
                mark(o + (C - o) * f, (0.022 + 0.012 * Double(fade)) * H, core * (0.6 + 0.9 * fade) * kB)
            }
        }
        if n == 4 {
            // w のメーター：画面に平行な輪。点線 ＝ w ＝ 0、紫の輪 ＝ 今の w。波の輪が点線から今の輪へ動く（−w なら内へ吸いこまれる）
            func circle(_ r: Double, _ c: SIMD3<Float>, _ w: Float, _ br: Float, dashed: Bool = false) {
                let pts = (0..<40).map { k -> SIMD3<Double> in let a = Double(k) / 40 * 2 * .pi; return o + SIMD3(cos(a), sin(a), 0) * r }
                for k in 0..<40 where !dashed || k % 2 == 0 { R(pts[k], pts[(k + 1) % 40], c, w, br) }
            }
            let r0 = OrigamiState.gravRing * H, r = st.gravRingR()
            circle(r0, violet * 0.7, 1.0, 0.8, dashed: true)
            circle(r, violet, st.gravGrabW && gr ? 3.4 : 2.6, 1.6)
            if abs(r - r0) > 0.01 * H {
                let f = (t * 0.7).truncatingRemainder(dividingBy: 1)
                circle(r0 + (r - r0) * f, violet, 1.4, Float(sin(.pi * f)) * 1.3)
            }
        }
        mark(tip, (gr && !st.gravGrabW ? 0.11 : 0.085) * H, gold * (gr ? 1.6 : 1.2))   // つかむ所：頭の先の輪（まっすぐ −w の時は真ん中）
    }
}

// ---- 水の時の内接球：ワイヤーも模様も無しの、すき通った玉と接点だけ ----
extension OrigamiRenderer {
    /// 玉の見かけ（4D：写した玉の外形＝目から見たふちの 2 次元の球面。左 3D：ふつうの球）。ふちほど明るく（すき通った玉）。
    ///   玉の壁の時：水につかった所はうすい水色・水面の高さに光る輪（水ぎわ。4D では水面と玉の交わり＝半径 √(1 − h²) の球面）
    func waterBall(_ tris: inout [IntVert], _ rods: inout [TLRod], d: Int, h: Double, k: Double, eye: SIMD3<Double>, wall: Bool, E4: SIMD4<Double>, V4: SIMD4<Double>, par: Bool) {
        let H = OrigamiState.half, RB = H, lvl = h * H, wet = wall && h > -0.999
        let pearl = SIMD3<Float>(0.93, 0.95, 1.0), wetC = SIMD3<Float>(0.5, 0.8, 1.0), aK = Float(k) * (wall ? 1 : 0.55)
        func rodL(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Float>, _ L: Double) { rods.append(TLRod(a: SIMD4(gpuW(a), 0), b: SIMD4(gpuW(b), 0), col: SIMD4(c, Float(L * k / 1.4)))) }
        func p4(_ X: SIMD4<Double>) -> SIMD3<Double> { st.place([X.x, X.y, X.z, X.w], 4).0 }
        func p3(_ X: SIMD3<Double>) -> SIMD3<Double> { st.place([X.x, X.y, X.z], 3).0 }
        let NT = 20, NP = 36
        var S: [[SIMD3<Double>]] = [], Wv: [[Double]] = []                  // 写した点と、その点の水の向きの高さ（4D は w・3D は z）
        if d == 3 {
            // 目から見た玉のふち：目 E（|E| ＝ D）から玉に接する点は X·E ＝ R²。中心 Ê R²/D・半径 R√(1 − R²/D²) の 2 次元の球面（平行投影なら、見る向きに直交する大きな球面）
            let De = simd_length(E4), axis = par ? V4 : E4 / max(1e-9, De)
            let c0 = par ? SIMD4<Double>(0, 0, 0, 0) : axis * (RB * RB / De), rs = par ? RB : RB * sqrt(max(0, 1 - RB * RB / (De * De)))
            var bs: [SIMD4<Double>] = []
            for e in [SIMD4<Double>(1, 0, 0, 0), SIMD4<Double>(0, 1, 0, 0), SIMD4<Double>(0, 0, 1, 0), SIMD4<Double>(0, 0, 0, 1)] where bs.count < 3 {
                var v = e - axis * simd_dot(e, axis); for b in bs { v -= b * simd_dot(v, b) }
                let l = simd_length(v); if l > 1e-6 { bs.append(v / l) }
            }
            guard bs.count == 3 else { return }
            for i in 0...NT {
                let th = Double.pi * Double(i) / Double(NT); var row: [SIMD3<Double>] = [], wr: [Double] = []
                for j in 0..<NP {
                    let ph = 2 * Double.pi * Double(j) / Double(NP)
                    let X = c0 + (bs[0] * (sin(th) * cos(ph)) + bs[1] * (sin(th) * sin(ph)) + bs[2] * cos(th)) * rs
                    row.append(p4(X)); wr.append(X.w)
                }
                S.append(row); Wv.append(wr)
            }
        } else {
            for i in 0...NT {
                let th = Double.pi * Double(i) / Double(NT); var row: [SIMD3<Double>] = [], wr: [Double] = []
                for j in 0..<NP {
                    let ph = 2 * Double.pi * Double(j) / Double(NP), X = SIMD3<Double>(sin(th) * cos(ph), sin(th) * sin(ph), cos(th)) * RB
                    row.append(p3(X)); wr.append(X.z)
                }
                S.append(row); Wv.append(wr)
            }
        }
        for i in 0..<NT { for j in 0..<NP {
            let j1 = (j + 1) % NP
            let q = [S[i][j], S[i + 1][j], S[i + 1][j1], S[i][j1]], wq = [Wv[i][j], Wv[i + 1][j], Wv[i + 1][j1], Wv[i][j1]]
            let nrm = simd_cross(q[1] - q[0], q[3] - q[0]), nl = simd_length(nrm), cen = (q[0] + q[1] + q[2] + q[3]) / 4
            let rim = nl > 1e-12 ? 1 - abs(simd_dot(nrm / nl, simd_normalize(eye - cen))) : 0.5
            let base = Float((d == 3 ? 0.12 : 0.05) + 0.4 * pow(rim, 2.2))      // 4D は水の上に重ねるので、少し濃く（中まで詰まった玉に見えるように）
            let cs: [SIMD4<Float>] = wq.map { w in
                let sub = wet && w < lvl, a = aK * base * (sub ? 1.2 : 1)
                return SIMD4<Float>((sub ? wetC : pearl) * a, a)
            }
            for (x, y, z) in [(0, 1, 2), (0, 2, 3)] {
                tris.append(IntVert(p: SIMD4(gpuW(q[x]), 1), c: cs[x])); tris.append(IntVert(p: SIMD4(gpuW(q[y]), 1), c: cs[y])); tris.append(IntVert(p: SIMD4(gpuW(q[z]), 1), c: cs[z]))
            }
        } }
        // 水ぎわ：水面（4D：w ＝ h の 3 次元、3D：z ＝ h の平面）と玉の交わり。4D は球面なので 3 つの大きな輪、3D は円
        if wet && h < 0.999 {
            let rh = RB * sqrt(max(0, 1 - h * h)), NR = 64, cl = SIMD3<Float>(0.6, 0.95, 1)
            let planes: [(Int, Int)] = d == 3 ? [(0, 1), (1, 2), (2, 0)] : [(0, 1)]
            for (a, b) in planes {
                var prev: SIMD3<Double>? = nil
                for s in 0...NR {
                    let t = 2 * Double.pi * Double(s) / Double(NR)
                    var e = [0.0, 0, 0]; e[a] = cos(t) * rh; e[b] = sin(t) * rh
                    let q = d == 3 ? p4(SIMD4(e[0], e[1], e[2], lvl)) : p3(SIMD3(e[0], e[1], lvl))
                    if let pv = prev { rodL(pv, q, cl, 1.7) }
                    prev = q
                }
            }
        }
        // 接点：玉が箱の胞（4D は 8 つ）・面（3D は 6 つ）にふれる 1 点。小さな十字で
        let na = d == 3 ? 4 : 3, L = 0.05 * H, wc = SIMD3<Float>(1, 1, 1)
        for a in 0..<na { for sg in [-1.0, 1.0] {
            var c = [Double](repeating: 0, count: na); c[a] = sg * RB
            for b in 0..<na where b != a {
                var u = c, v = c; u[b] += L; v[b] -= L
                let A = d == 3 ? p4(SIMD4(u[0], u[1], u[2], u[3])) : p3(SIMD3(u[0], u[1], u[2]))
                let B = d == 3 ? p4(SIMD4(v[0], v[1], v[2], v[3])) : p3(SIMD3(v[0], v[1], v[2]))
                rodL(A, B, wc, 1.4)
            }
        } }
    }
}
