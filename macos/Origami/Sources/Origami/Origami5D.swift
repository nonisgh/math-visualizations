// 5 次元 β（ウェブ版 hypercube.html の「5次元β」の移植の第 1 歩。くわしくは 5次元の準備メモ.md）。
//   左の窓に超立方体（1 つ下の次元のたとえ）・右の窓に 5 次元超立方体（10 個の超立方体の展開図を、5 次元で折りたたむ）。
//   展開図はダリの十字架の 5 次元版（真ん中 −v・±y・±x・±z・±w・ふた +v は +y の腕の先）だけ。
//   回す順はウェブ版の rotate5 と同じ：X-V・Y-V・Z-V（＝超立方体の X-W・Y-W・Z-W と同じ角度）→ 5 次元だけの X-W・Y-W・Z-W・W-V → 3D の X-Y・X-Z・Y-Z。
//   写し方：いちばん上の v から 1 本ずつ遠近（v の距離は w の 1.4 倍。逆向きの 2 つの超立方体がぴったり重ならないように）
import Foundation
import simd

extension OrigamiState {
    static let eye5: [[Double]] = (0..<5).map { i in (0..<5).map { $0 == i ? 1.0 : 0.0 } }
    /// 5 次元の展開図（ダリの十字架の 5 次元版）：10 個の超立方体の親。ふた（9）は +y（1）の先、ほかは真ん中（0）に
    static let p5Dali = [-1, 0, 0, 0, 0, 0, 0, 0, 0, 1]
    /// 展開図の木（次元ごと）。5 次元はダリだけ
    func netParent(_ n: Int) -> [Int] { n == 5 ? net5 : n == 4 ? net.p4 : net.p3 }
    /// 窓の番号（zoom・center・pan などの入れ物）：ふだんは 左 0 立方体・右 1 超立方体。5 次元では 左 0 超立方体・右 1 5 次元超立方体
    func wix(_ n: Int) -> Int { n == 3 ? 0 : n == 5 ? 1 : (dim5 ? 0 : 1) }

    // ---- 5 × 5 の行列（行 i・列 j）----
    static func rot5(_ i: Int, _ j: Int, _ t: Double) -> [[Double]] {
        var m = eye5
        m[i][i] = cos(t); m[j][j] = cos(t); m[j][i] = sin(t); m[i][j] = -sin(t)     // e_i → cos e_i ＋ sin e_j（4 次元の R と同じ向き）
        return m
    }
    static func mul5(_ a: [[Double]], _ b: [[Double]]) -> [[Double]] {
        (0..<5).map { i in (0..<5).map { j in var s = 0.0; for k in 0..<5 { s += a[i][k] * b[k][j] }; return s } }
    }
    static func apply5(_ m: [[Double]], _ p: [Double]) -> [Double] {
        (0..<5).map { i in var s = 0.0; for k in 0..<5 { s += m[i][k] * p[k] }; return s }
    }
    /// 回転を作り直す（updateMats から毎回）
    func updateMats5() {
        var r = Self.eye5
        for (i, j, t) in [(0, 4, ax), (1, 4, ay), (2, 4, zw), (0, 3, xw5), (1, 3, yw5), (2, 3, zw5), (3, 4, wv5)] where t != 0 { r = Self.mul5(Self.rot5(i, j, t), r) }
        r5a = r
        // 3D の回転（超立方体と同じ c3。w・v はそのまま）
        var E = Self.eye5
        for i in 0..<3 { for j in 0..<3 { E[i][j] = c3[j][i] } }
        m5 = Self.mul5(E, r)
    }
    /// 5 次元（右の 5 次元超立方体）：回して、v → w の順に遠近で 3D へ。返り値は見かけの縮み（v と w の縮みの積）
    func place5(_ p: [Double]) -> (SIMD3<Double>, Double) {
        var q = Self.apply5(m5, p)
        let pb = 1 - projBlend
        let Dv = camW * 1.4, v = max(-Dv + 0.5, min(Dv - 0.5, q[4])), kv = 1 + (1 / (1 - v / Dv) - 1) * pb
        for t in 0..<4 { q[t] *= kv }
        let Dw = camW, w = max(-Dw + 0.5, min(Dw - 0.5, q[3])), kw = 1 + (1 / (1 - w / Dw) - 1) * pb
        return (SIMD3(q[0] * kw, q[1] * kw, q[2] * kw), kv * kw)
    }
    /// place5 と同じ。w の遠近の縮みだけも返す（展開図の 1 つ 1 つの超立方体の、4 次元の奥行き＝内側の立方体ほど小さい）
    func place5KW(_ p: [Double]) -> (SIMD3<Double>, Double, Double) {
        var q = Self.apply5(m5, p)
        let pb = 1 - projBlend
        let Dv = camW * 1.4, v = max(-Dv + 0.5, min(Dv - 0.5, q[4])), kv = 1 + (1 / (1 - v / Dv) - 1) * pb
        for t in 0..<4 { q[t] *= kv }
        let Dw = camW, w = max(-Dw + 0.5, min(Dw - 0.5, q[3])), kw = 1 + (1 / (1 - w / Dw) - 1) * pb
        // 平行投影でも内と外がわかるように、遠近の縮みが無い時は w そのもの（手前ほど大きい）を奥行きに
        return (SIMD3(q[0] * kw, q[1] * kw, q[2] * kw), kv * kw, kw + 0.05 * q[3] / Dw)
    }
    /// 胞が表か（v の向こうの目から見て。超立方体の cellFront の 5 次元版）
    func cellFront5(_ fa: Int, _ fv: Double) -> Bool {
        var e = [Double](repeating: 0, count: 5); e[fa] = fv
        return Self.apply5(r5a, e)[4] > Self.half / (camW * 1.4) * (1 - projBlend) + 1e-6
    }
    /// 分解で胞を離す向き（組み上がった形での）：x・y はそのまま、z・w・v はななめの 3 つの向きへ（ウェブ版の EX_E・EX_F）
    func foldedOffset5(_ q: [Double], _ d: Double) -> SIMD3<Double> {
        let EZ = simd_normalize(SIMD3<Double>(0.55, 0.42, 1)) * 1.25, EW = simd_normalize(SIMD3<Double>(-0.9, 0.35, -0.5)) * 1.4, EF = simd_normalize(SIMD3<Double>(0.75, -0.75, -0.3)) * 1.4
        let r = Self.apply5(r5a, q)
        let o = SIMD3<Double>(r[0], r[1], 0) + EZ * r[2] + EW * r[3] + EF * r[4]
        let v = c3 * SIMD4(o * d, 0)
        return SIMD3(v.x, v.y, v.z)
    }
    /// 毎コマ：5 次元だけの 4 面を回し続ける・見え方のおすすめへなめらかに移る
    func tick5(_ dt: Double) {
        guard dim5 else { return }
        if var tw = tw5 {
            tw.t += dt
            let f = Self.smoother(tw.t / 1.2)
            let a = (0..<tw.from.count).map { tw.from[$0] + Self.wrapPi(tw.to[$0] - tw.from[$0]) * f }
            ax = a[0]; ay = a[1]; zw = a[2]; xy = a[3]; xz = a[4]; yz = a[5]; xw5 = a[6]; yw5 = a[7]; zw5 = a[8]; wv5 = a[9]
            tw5 = tw.t >= 1.2 ? nil : tw
            rotRev += 1; updateMats()
            return
        }
        guard spin5 else { return }
        let k = speed * dt * 144
        xw5 = Self.wrapPi(xw5 + 0.0047 * k); yw5 = Self.wrapPi(yw5 + 0.0035 * k); zw5 = Self.wrapPi(zw5 + 0.0026 * k); wv5 = Self.wrapPi(wv5 + 0.0041 * k)
        rotRev += 1; updateMats()
    }
    /// 今の 10 面の角度（X-V・Y-V・Z-V・X-Y・X-Z・Y-Z・X-W・Y-W・Z-W・W-V）
    var cur10: [Double] { [ax, ay, zw, xy, xz, yz, xw5, yw5, zw5, wv5] }
    /// 見え方のおすすめ（ウェブ版の 3D展開・4D展開）：形は同じで、回す角度と投影だけが違う。
    ///   0 3D展開：10 面とも 0°（w も v も目の方へつぶれる）＋ななめ・遠近 → ±W の胞が真ん中の手前と奥に重なった太い「3 次元の十字架」
    ///   1 4D展開：5 次元だけの X-W 45°・Y-W 35.264°・Z-W 30° ＋ななめ・平行 → w が 3D に出てきて、8 方向の腕が全部見える「4 次元の十字架」
    func view5(_ k: Int) {
        cycling = false; stopSpins(); tween = nil; pend = [0, 0, 0, 0, 0]; viewSel = -1; xyManualOff = 0
        let d = Double.pi / 180
        let tilt = [15 * d, 30 * d, 20 * d]
        let to: [Double] = k == 0 ? [0, 0, 0] + tilt + [0, 0, 0, 0] : [0, 0, 0] + tilt + [45 * d, 35.264 * d, 30 * d, 0]
        tw5 = (cur10, to, 0)
        presetPar = k == 0 ? 0 : 1; presetHold = SIMD3(0, 0, 0)
    }
    /// 5 次元だけの 4 面を 0 へ（なめらかに）
    func zero5() {
        spin5 = false
        var to = cur10; to[6] = 0; to[7] = 0; to[8] = 0; to[9] = 0
        tw5 = (cur10, to, 0)
    }
    /// 5 次元 β の入り切り
    func toggleDim5() {
        dim5.toggle(); tw5 = nil
        if dim5 { view5(1) } else { spin5 = false; xw5 = 0; yw5 = 0; zw5 = 0; wv5 = 0; updateMats() }
    }
}
