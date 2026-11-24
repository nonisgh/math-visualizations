// 積分で 4 次元の形を作る（ウェブ版の「輪切りの形を積む」：球柱・デュオシリンダー・タイガー）。
//   立方体の代わりに、その w での輪切りの形を段ごとに置く。積み上がると 4 次元の形になる（いわば微分の形を積分する）。色は積む順（w：−1 赤 → +1 紫）。
//   球柱（玉 × 線分）：どの段も同じ大きさの玉（w の方向から見ると、全部の玉がぴったり重なって 1 個の球）。
//   デュオシリンダー（x²＋y² ≤ r²、z²＋w² ≤ r²）：輪切り＝円柱。半径 r はいつも同じ、高さ 2√(r²−w²) が変わる（まんなかで最も高く、両端でぺちゃんこ）。体積 π²r⁴。
//   タイガー（(ρ₁−R₁)²＋(ρ₂−R₂)² ≤ r²、ρ₁＝√(x²＋y²)、ρ₂＝√(z²＋w²)）：輪切り＝z の上下に 2 つのドーナツ。w が進むと近づいて 1 つにつながり、最後に消える。体積 4π³R₁R₂r²。
//   左の窓（3 次元の仲間）：球柱 → 円柱（円を積む）、デュオ → x にのびた円柱の輪切り＝高さの変わる長方形、タイガー → x ＝ ±R₁ に立てたドーナツ 2 つの輪切り＝4 つの丸。
//   大きさはウェブ版と同じ（立方体の半分の辺を 1 として）：デュオ r 0.9、タイガー R₁ 0.55・R₂ 0.55・r 0.3、玉の半径 0.6
import Foundation
import simd

extension OrigamiState {
    static let slDuoR = 0.9, slTgR1 = 0.55, slTgR2 = 0.55, slTgr = 0.3, slBallR = 0.6
    // 5 4 次元の円すい：w ＝ −1 で半径 1 の玉、w ＝ ＋1 で点（半径 (1−w)／2）
    // 6 超立方体を角から切る：1 辺 1 の超立方体を、対角線（1,1,1,1）が w の向きになるように立てる（対角線の長さ 2）。
    //   左の窓は 1 辺 2／√3 の立方体を、対角線（1,1,1）が z の向きに（長さ 2）
    // 7 球のドーナツ：玉（半径 r）を、x‐w の面の輪（半径 R）にそってぐるっと＝(√(x²＋w²) − R)² ＋ y² ＋ z² ≤ r²。左の窓はふつうのドーナツ
    static let slTorR = 0.55, slTorr = 0.35, slCubeA3 = 2 / 3.0.squareRoot()
    // 8 キュービンダー（円 × 正方形）：x‐y の正方形（半分の辺 s）× z‐w の円（半径 r）。輪切り＝箱（底 2s × 2s、高さ 2√(r²−w²)）。左の窓は x にのびた円柱
    static let slCubS = 0.75, slCubR = 0.9
    static func slCubH(_ w: Double) -> Double { max(0, slCubR * slCubR - w * w).squareRoot() }
    static func slConeR(_ w: Double) -> Double { max(0, (1 - w) / 2) }
    /// 立方体（n 次元、1 辺 1）を、すべての座標の和 t の面で切った切り口の (n−1) 次元の大きさ（√n／(n−1)! × Σ (−1)^k C(n,k) (t−k)₊^(n−1)）
    static func slCubeSlice(_ n: Int, _ t: Double) -> Double {
        let C = n == 4 ? [1.0, 4, 6, 4, 1] : [1.0, 3, 3, 1]
        var s = 0.0
        for k in 0...n { let x = t - Double(k); if x > 0 { s += (k % 2 == 0 ? 1 : -1) * C[k] * pow(x, Double(n - 1)) } }
        return Double(n).squareRoot() / (n == 4 ? 6 : 2) * s
    }
    /// 球のドーナツの輪切り（w）の、x の範囲（玉が 2 つなら x＞0 の 1 つぶん。1 つなら −xm〜xm）と、x での yz の円の半径
    static func slTorRange(_ w: Double) -> (lo: Double, hi: Double, two: Bool)? {
        let R = slTorR, r = slTorr, hi2 = (R + r) * (R + r) - w * w
        guard hi2 > 0 else { return nil }
        let lo2 = (R - r) * (R - r) - w * w
        return lo2 > 0 ? (lo2.squareRoot(), hi2.squareRoot(), true) : (0, hi2.squareRoot(), false)
    }
    static func slTorF(_ x: Double, _ w: Double) -> Double { let e = (x * x + w * w).squareRoot() - slTorR; return max(0, slTorr * slTorr - e * e).squareRoot() }
    static func slH(_ w: Double) -> Double { sqrt(max(0, slDuoR * slDuoR - w * w)) }
    /// 輪切りの体積（右・4 次元）／面積（左・3 次元の仲間）。shape：1 球柱・2 デュオ・3 タイガー
    static func slMeasure(_ shape: Int, _ w: Double, left: Bool) -> Double {
        switch shape {
        case 1: return left ? Double.pi * slBallR * slBallR : 4.0 / 3 * Double.pi * pow(slBallR, 3)
        case 4: let q = max(0, 1 - w * w); return left ? Double.pi * q : 4.0 / 3 * Double.pi * pow(q, 1.5)   // 内接する超球（球）：半径 √(1−w²) の玉（円）
        case 5: let R = slConeR(w); return left ? Double.pi * R * R : 4.0 / 3 * Double.pi * R * R * R
        case 8: let h = slCubH(w); return left ? 2 * slCubS * 2 * h : 4 * slCubS * slCubS * 2 * h
        case 6:
            if left { let a = slCubeA3; return a * a * slCubeSlice(3, 1.5 * w + 1.5) }        // 1 辺 a の立方体：t ＝ 1.5z ＋ 1.5
            return slCubeSlice(4, 2 * w + 2)                                                      // 1 辺 1 の超立方体：t ＝ 2w ＋ 2
        case 7:
            guard let rg = slTorRange(w) else { return 0 }
            let M = 48; var s = 0.0
            let a = rg.two ? rg.lo : -rg.hi, b = rg.hi
            for i in 0..<M { let x = a + (b - a) * (Double(i) + 0.5) / Double(M), f = slTorF(x, w); s += (left ? 2 * f : Double.pi * f * f) * (b - a) / Double(M) }
            return rg.two ? 2 * s : s
        case 2: return left ? 2 * slDuoR * 2 * slH(w) : Double.pi * slDuoR * slDuoR * 2 * slH(w)
        default:
            let r = slTgr, zm = slTgR2 + r
            if abs(w) >= zm { return 0 }
            var A = 0.0; let Z = sqrt(zm * zm - w * w), M = 64
            for i in 0..<M { let z = -Z + 2 * Z * (Double(i) + 0.5) / Double(M), e = hypot(z, w) - slTgR2; A += 2 * sqrt(max(0, r * r - e * e)) * 2 * Z / Double(M) }
            return left ? 2 * A : 2 * Double.pi * slTgR1 * A          // 右：2πR₁ × A（パップス）
        }
    }
    static func slTotal(_ shape: Int, left: Bool) -> Double {
        switch shape {
        case 1: return 2 * slMeasure(1, 0, left: left)
        case 4: return left ? 4.0 / 3 * Double.pi : pow(Double.pi, 2) / 2
        case 5: return 2.0 / 3 * Double.pi                                                       // 左：⅓ × π × 2、右：¼ × ⁴⁄₃π × 2（どちらも ⅔π）
        case 8: return left ? 2 * slCubS * Double.pi * slCubR * slCubR : 4 * slCubS * slCubS * Double.pi * slCubR * slCubR
        case 6: return left ? pow(slCubeA3, 3) : 1
        case 7: return left ? 2 * Double.pi * slTorR * Double.pi * slTorr * slTorr : 2 * Double.pi * slTorR * 4.0 / 3 * Double.pi * pow(slTorr, 3)
        case 2: return left ? 2 * Double.pi * pow(slDuoR, 3) : pow(Double.pi, 2) * pow(slDuoR, 4)
        default: return left ? 4 * pow(Double.pi, 2) * slTgR2 * slTgr * slTgr : 4 * pow(Double.pi, 3) * slTgR1 * slTgR2 * slTgr * slTgr
        }
    }
    /// 途中までの積分（数値積分）
    static func slInt(_ shape: Int, _ a: Double, _ b: Double, left: Bool) -> Double {
        guard b > a else { return 0 }
        let M = 160; var s = 0.0
        for i in 0..<M { s += slMeasure(shape, a + (b - a) * (Double(i) + 0.5) / Double(M), left: left) }
        return s * (b - a) / Double(M)
    }
}

/// 景色の座標（y が上）を、描く側（z が上）へ
@inline(__always) private func gpuS(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 4 次元の玉（真ん中 C と、3 本の半径の先 E を写した位置）→ 画素ごとに描くだ円体。
    ///   4D で回すと、玉の入っている 3 次元の切り口が傾くので、写した玉はつぶれる（真横からだと円板）。まんまるの時は球と同じ
    static func ellipsoid(_ C: SIMD3<Double>, _ E: [SIMD3<Double>], spin: Double, alpha: Double) -> IntSphere {
        var A = E.map { $0 - C }
        let L = A.map { simd_length($0) }.max() ?? 0
        // ぺちゃんこ（真横から見た円板）でも解けるように、厚みを少し残す（いちばん長い半径の 4%）。
        //   厚み＝いちばん短い軸の、ほかの 2 本の面に垂直な長さ（行列式 ÷ 2 本のつくる面積）
        if L > 0 {
            let k = (0..<3).min { simd_length(A[$0]) < simd_length(A[$1]) } ?? 0, o = (0..<3).filter { $0 != k }
            var nrm = simd_cross(A[o[0]], A[o[1]]); let area = simd_length(nrm)
            if area < 1e-12 { nrm = SIMD3(0, 0, 1) } else { nrm /= area }
            let h = area < 1e-12 ? 0 : abs(simd_dot(A[k], nrm)), hMin = 0.04 * L
            if h < hMin { A[k] += nrm * ((simd_dot(A[k], nrm) < 0 ? -1 : 1) * (hMin - h)) }
        }
        func g(_ v: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(-v.z), Float(v.y), 0) }
        // 描く板の大きさ：3 本の半径がななめにかたむいていても、だ円体が必ず入る大きさ（√(半径の 2 乗の和)）。
        //   前はいちばん長い半径だけで決めていて、平べったく傾いた玉が板からはみ出し、まっすぐな辺で切れていた
        let Lb = (A.reduce(0.0) { $0 + simd_length_squared($1) }).squareRoot()
        return IntSphere(c: SIMD4(gpuS(C), Float(Lb)), m: SIMD4(Float(spin), Float(min(1, alpha)), 0, 0), ax: g(A[0]), ay: g(A[1]), az: g(A[2]))
    }
    /// 3×3 の対称行列（正定値）の平方根と、その逆（ヤコビ法で固有値に分けて）
    static func symSqrt3(_ m: simd_double3x3) -> (simd_double3x3, simd_double3x3)? {
        var a = [[m[0][0], m[1][0], m[2][0]], [m[0][1], m[1][1], m[2][1]], [m[0][2], m[1][2], m[2][2]]]
        var v = [[1.0, 0, 0], [0, 1, 0], [0, 0, 1]]
        for _ in 0..<40 {
            var p = 0, q = 1, big = 0.0
            for i in 0..<3 { for j in (i + 1)..<3 where abs(a[i][j]) > big { big = abs(a[i][j]); p = i; q = j } }
            if big < 1e-15 { break }
            let th = 0.5 * atan2(2 * a[p][q], a[q][q] - a[p][p]), c = cos(th), sn = sin(th)
            for k in 0..<3 { let x = c * a[k][p] - sn * a[k][q], y = sn * a[k][p] + c * a[k][q]; a[k][p] = x; a[k][q] = y }
            for k in 0..<3 { let x = c * a[p][k] - sn * a[q][k], y = sn * a[p][k] + c * a[q][k]; a[p][k] = x; a[q][k] = y }
            for k in 0..<3 { let x = c * v[k][p] - sn * v[k][q], y = sn * v[k][p] + c * v[k][q]; v[k][p] = x; v[k][q] = y }
        }
        let ev = [a[0][0], a[1][1], a[2][2]]
        guard ev.allSatisfy({ $0 > 1e-14 }) else { return nil }
        let V = simd_double3x3(columns: (SIMD3(v[0][0], v[1][0], v[2][0]), SIMD3(v[0][1], v[1][1], v[2][1]), SIMD3(v[0][2], v[1][2], v[2][2])))
        let Ds = simd_double3x3(diagonal: SIMD3(ev.map { $0.squareRoot() }[0], ev[1].squareRoot(), ev[2].squareRoot()))
        let Di = simd_double3x3(diagonal: SIMD3(1 / ev[0].squareRoot(), 1 / ev[1].squareRoot(), 1 / ev[2].squareRoot()))
        return (V * Ds * V.transpose, V * Di * V.transpose)
    }
    /// 4D の玉（超立方体の座標で真ん中 c4・半径 R。xyz の 3D 空間に入っている＝輪切りの玉）を、今の 4D の回転と遠近で「正確に」写しただ円体。
    ///   遠近で写すのは射影の変換なので、玉は正確にだ円体に写る（手前が大きい）。その 2 次曲面を変換で求める：
    ///   玉 uᵀu ≤ 1（同次座標で Q ＝ diag(1,1,1,−1)）、写し方 p ～ H·(u, 1) → 写った形 Q′ ＝ H⁻ᵀ Q H⁻¹ → 真ん中と形（Σ）。
    ///   3 本の軸は、近道で写した軸にいちばん近い向きに（模様の向きがそろう）。平行投影なら近道がもともと正確
    func exactBall(_ c4: SIMD4<Double>, _ R: Double, approxC: SIMD3<Double>, approxE: [SIMD3<Double>], spin: Double, alpha: Double) -> IntSphere {
        let fallback = Self.ellipsoid(approxC, approxE, spin: spin, alpha: alpha)
        let pb = st.projBlend
        guard pb < 0.999 else { return fallback }
        let Hh = OrigamiState.half, M = st.m4, De = st.camW / max(1e-6, 1 - pb)
        let m0 = M * (c4 * Hh)
        let b = (0..<3).map { i -> SIMD4<Double> in var e = SIMD4<Double>(0, 0, 0, 0); e[i] = R * Hh; return M * e }
        // 同次の写し方（行 0〜2：xyz、行 3：1 − w/D）。simd は列で作る
        let Hm = simd_double4x4(columns: (SIMD4(b[0].x, b[0].y, b[0].z, -b[0].w / De), SIMD4(b[1].x, b[1].y, b[1].z, -b[1].w / De),
                                          SIMD4(b[2].x, b[2].y, b[2].z, -b[2].w / De), SIMD4(m0.x, m0.y, m0.z, 1 - m0.w / De)))
        guard abs(Hm.determinant) > 1e-12 else { return fallback }
        let Hi = Hm.inverse, Q = simd_double4x4(diagonal: SIMD4(1, 1, 1, -1)), Qp = Hi.transpose * Q * Hi
        let A = simd_double3x3(columns: (SIMD3(Qp[0][0], Qp[0][1], Qp[0][2]), SIMD3(Qp[1][0], Qp[1][1], Qp[1][2]), SIMD3(Qp[2][0], Qp[2][1], Qp[2][2])))
        let bv = SIMD3(Qp[3][0], Qp[3][1], Qp[3][2]), c = Qp[3][3]
        guard abs(A.determinant) > 1e-14 else { return fallback }
        let Ai = A.inverse, ctr = -(Ai * bv), sK = simd_dot(bv, Ai * bv) - c
        guard sK > 1e-14, let (S, _) = Self.symSqrt3(Ai * sK) else { return fallback }   // Σ ＝ s A⁻¹（正定値でなければ近道のまま）
        // 近道の軸 A0 にいちばん近い L（L Lᵀ ＝ Σ）：L ＝ S · polar(S⁻¹ A0)
        let A0 = simd_double3x3(columns: (approxE[0] - approxC, approxE[1] - approxC, approxE[2] - approxC))
        var L = S
        if abs(S.determinant) > 1e-14 {
            let T = S.inverse * A0
            if let (_, TtTi) = Self.symSqrt3(T.transpose * T) { L = S * (T * TtTi) }
        }
        return Self.ellipsoid(ctr, [ctr + L.columns.0, ctr + L.columns.1, ctr + L.columns.2], spin: spin, alpha: alpha)
    }
    /// exactBall の、どの向きの立方体の玉にも使える形：玉の真ん中 c4（超立方体の座標）と、玉の入っている 3 本の軸 axes、半径 R。
    ///   x・y・z の向きから入れた立方体の玉は w（4D の奥行き）の方向にも広がるので、真ん中と 3 本の半径の先を写すだけでは
    ///   遠近の倍率が場所でちがってずれる（目に近いと、とても大きくなって四角い板になっていた）。射影の変換で正確に求める。
    ///   写した形がだ円体にならない（玉が目の面にかかる）時は nil（描かない）。平行投影なら近道がもともと正確
    func exactBallAxes(_ c4: SIMD4<Double>, _ R: Double, axes: [Int], approxC: SIMD3<Double>, approxE: [SIMD3<Double>], spin: Double, alpha: Double) -> IntSphere? {
        let pb = st.projBlend
        guard pb < 0.999 else { return Self.ellipsoid(approxC, approxE, spin: spin, alpha: alpha) }
        guard axes.count == 3 else { return nil }
        let Hh = OrigamiState.half, M = st.m4, De = st.camW / max(1e-6, 1 - pb)
        let m0 = M * (c4 * Hh)
        let b = axes.map { i -> SIMD4<Double> in var e = SIMD4<Double>(0, 0, 0, 0); e[i] = R * Hh; return M * e }
        let Hm = simd_double4x4(columns: (SIMD4(b[0].x, b[0].y, b[0].z, -b[0].w / De), SIMD4(b[1].x, b[1].y, b[1].z, -b[1].w / De),
                                          SIMD4(b[2].x, b[2].y, b[2].z, -b[2].w / De), SIMD4(m0.x, m0.y, m0.z, 1 - m0.w / De)))
        // 玉のいちばん手前の w が、目の面（遠近の分母 0）に近ければ描かない
        let wMax = m0.w + (b[0].w * b[0].w + b[1].w * b[1].w + b[2].w * b[2].w).squareRoot()
        guard wMax < De * 0.92, abs(Hm.determinant) > 1e-12 else { return nil }
        let Hi = Hm.inverse, Q = simd_double4x4(diagonal: SIMD4(1, 1, 1, -1)), Qp = Hi.transpose * Q * Hi
        let A = simd_double3x3(columns: (SIMD3(Qp[0][0], Qp[0][1], Qp[0][2]), SIMD3(Qp[1][0], Qp[1][1], Qp[1][2]), SIMD3(Qp[2][0], Qp[2][1], Qp[2][2])))
        let bv = SIMD3(Qp[3][0], Qp[3][1], Qp[3][2]), c = Qp[3][3]
        guard abs(A.determinant) > 1e-14 else { return nil }
        let Ai = A.inverse, ctr = -(Ai * bv), sK = simd_dot(bv, Ai * bv) - c
        guard sK > 1e-14, let (S, _) = Self.symSqrt3(Ai * sK) else { return nil }
        let A0 = simd_double3x3(columns: (approxE[0] - approxC, approxE[1] - approxC, approxE[2] - approxC))
        var L = S
        if abs(S.determinant) > 1e-14 {
            let T = S.inverse * A0
            if let (_, TtTi) = Self.symSqrt3(T.transpose * T) { L = S * (T * TtTi) }
        }
        return Self.ellipsoid(ctr, [ctr + L.columns.0, ctr + L.columns.1, ctr + L.columns.2], spin: spin, alpha: alpha)
    }
    /// 輪切りの形（1 段ぶん）を三角形で：pos＝その段が今いる w（飛んでいる間は着く所の形のまま動く）、ws＝形を決める w、eye＝カメラ
    /// 1 辺 1 の超立方体（[−½, ½]⁴）を、対角線の向き n ＝ (1,1,1,1)／2 で、n·p ＝ d の 3 次元の面で切った切り口（凸多面体）。
    ///   切り口の中の座標は b₁ ＝ (1,1,−1,−1)／2・b₂ ＝ (1,−1,1,−1)／2・b₃ ＝ (1,−1,−1,1)／2。面ごとの多角形（角の並び）で返す
    static func cornerSlice4(_ d: Double) -> [[SIMD3<Double>]] {
        let h = 0.5, n = SIMD4<Double>(0.5, 0.5, 0.5, 0.5)
        let b1 = SIMD4<Double>(0.5, 0.5, -0.5, -0.5), b2 = SIMD4<Double>(0.5, -0.5, 0.5, -0.5), b3 = SIMD4<Double>(0.5, -0.5, -0.5, 0.5)
        var pts: [SIMD3<Double>] = []
        func addPt(_ p: SIMD4<Double>) { let q = SIMD3(simd_dot(p, b1), simd_dot(p, b2), simd_dot(p, b3)); if !pts.contains(where: { simd_distance($0, q) < 1e-7 }) { pts.append(q) } }
        for v in 0..<16 { for ax in 0..<4 where v & (1 << ax) == 0 {
            let A = SIMD4<Double>((0..<4).map { v & (1 << $0) != 0 ? h : -h }), B = { var t = A; t[ax] = h; return t }()
            let sa = simd_dot(A, n), sb = simd_dot(B, n)
            if (sa - d) * (sb - d) <= 0 && abs(sb - sa) > 1e-12 { addPt(A + (B - A) * ((d - sa) / (sb - sa))) }
            else if abs(sa - d) < 1e-12 { addPt(A) }
        } }
        return hull3(pts)
    }
    /// 1 辺 a の立方体（[−a/2, a/2]³）を、対角線の向き (1,1,1)／√3 で切った切り口（凸多角形）。中の座標は (1,−1,0)／√2・(1,1,−2)／√6
    static func cornerSlice3(_ d: Double) -> [SIMD2<Double>] {
        let h = OrigamiState.slCubeA3 / 2, n = SIMD3<Double>(1, 1, 1) / 3.0.squareRoot()
        let c1 = SIMD3<Double>(1, -1, 0) / 2.0.squareRoot(), c2 = SIMD3<Double>(1, 1, -2) / 6.0.squareRoot()
        var pts: [SIMD2<Double>] = []
        for v in 0..<8 { for ax in 0..<3 where v & (1 << ax) == 0 {
            let A = SIMD3<Double>((0..<3).map { v & (1 << $0) != 0 ? h : -h }), B = { var t = A; t[ax] = h; return t }()
            let sa = simd_dot(A, n), sb = simd_dot(B, n)
            if (sa - d) * (sb - d) <= 0 && abs(sb - sa) > 1e-12 {
                let p = A + (B - A) * ((d - sa) / (sb - sa)), q = SIMD2(simd_dot(p, c1), simd_dot(p, c2))
                if !pts.contains(where: { simd_distance($0, q) < 1e-7 }) { pts.append(q) }
            }
        } }
        guard pts.count >= 3 else { return [] }
        let c = pts.reduce(SIMD2<Double>(0, 0), +) / Double(pts.count)
        return pts.sorted { atan2($0.y - c.y, $0.x - c.x) < atan2($1.y - c.y, $1.x - c.x) }
    }
    /// 点の集まりの凸包（3 次元）を、面ごとの多角形（外から見て並んだ角）で。点が少ない（20 個くらいまで）ので、3 つずつ全部ためす
    static func hull3(_ p: [SIMD3<Double>]) -> [[SIMD3<Double>]] {
        guard p.count >= 4 else { return [] }
        let ctr = p.reduce(SIMD3<Double>(0, 0, 0), +) / Double(p.count)
        var planes: [(n: SIMD3<Double>, d: Double)] = [], faces: [[SIMD3<Double>]] = []
        let eps = 1e-7
        for i in 0..<p.count { for j in (i + 1)..<p.count { for k in (j + 1)..<p.count {
            var nn = simd_cross(p[j] - p[i], p[k] - p[i]); let l = simd_length(nn); if l < 1e-10 { continue }; nn /= l
            if simd_dot(nn, ctr - p[i]) > 0 { nn = -nn }                       // 外向き
            let dd = simd_dot(nn, p[i])
            guard p.allSatisfy({ simd_dot(nn, $0) - dd <= eps }) else { continue }
            if planes.contains(where: { simd_distance($0.n, nn) < 1e-6 && abs($0.d - dd) < 1e-6 }) { continue }
            planes.append((nn, dd))
            let on = p.filter { abs(simd_dot(nn, $0) - dd) <= eps }
            let fc = on.reduce(SIMD3<Double>(0, 0, 0), +) / Double(on.count)
            let e1 = simd_normalize(on[0] - fc), e2 = simd_cross(nn, e1)
            faces.append(on.sorted { atan2(simd_dot($0 - fc, e2), simd_dot($0 - fc, e1)) < atan2(simd_dot($1 - fc, e2), simd_dot($1 - fc, e1)) })
        } } }
        return faces
    }
    func sliceShape(_ list: inout [IntVert], _ sph: inout [IntSphere], shape: Int, pos: Double, ws: Double, a: Double, eye: SIMD3<Double>, ballRes: Int, spin: Double) {
        let H = OrigamiState.half, d = n - 1
        let f = Float(ws * 0.5 + 0.5)
        let base = OrigamiRenderer.band(Double(f))
        func P(_ u: [Double]) -> SIMD3<Double> { st.place(u.map { $0 * H } + [pos * H], n).0 }
        func tri(_ A: SIMD3<Double>, _ B: SIMD3<Double>, _ C: SIMD3<Double>) {
            let nn = simd_cross(B - A, C - A), nl = simd_length(nn)
            guard nl > 1e-12 else { return }
            let mid = (A + B + C) / 3, sh = Float(0.42 + 0.58 * abs(simd_dot(nn / nl, simd_normalize(eye - mid))))
            let al = Float(a), c = SIMD4(base * sh * al, al)
            list.append(IntVert(p: SIMD4(gpuS(A), 1), c: c)); list.append(IntVert(p: SIMD4(gpuS(B), 1), c: c)); list.append(IntVert(p: SIMD4(gpuS(C), 1), c: c))
        }
        if d == 3 {
            switch shape {
            case 1:
                // 球柱：その段の真ん中に、同じ大きさ（半径 0.6）の玉。写し方は段と同じ（遠近・4D の回転でつぶれる）。画素ごとのだ円体で（輪郭も陰もなめらか）
                let R = OrigamiState.slBallR
                sph.append(Self.ellipsoid(P([0, 0, 0]), [P([R, 0, 0]), P([0, R, 0]), P([0, 0, R])], spin: spin, alpha: a))
            case 4:
                // 内接する超球の輪切り＝半径 √(1−w²) の玉。その段の写し方で（4D の回転でつぶれる）、画素ごとのだ円体で
                let R = sqrt(max(0, 1 - ws * ws))
                guard R > 1e-3 else { return }
                let C0 = P([0, 0, 0]), E0 = [P([R, 0, 0]), P([0, R, 0]), P([0, 0, R])]
                // 正確に写す（遠近でも、積み上げた輪郭が超球の正確な影＝まんまるのまま）か、近道（ぷよぷよのゴムボール）か
                if st.intExact { sph.append(exactBall(SIMD4(0, 0, 0, pos), R, approxC: C0, approxE: E0, spin: spin, alpha: a)) }
                else { sph.append(Self.ellipsoid(C0, E0, spin: spin, alpha: a)) }   // 4D の回転でつぶれる
            case 5:
                // 4 次元の円すいの輪切り＝半径 (1−w)／2 の玉（超球と同じ描き方）
                let R = OrigamiState.slConeR(ws)
                guard R > 1e-3 else { return }
                let C0 = P([0, 0, 0]), E0 = [P([R, 0, 0]), P([0, R, 0]), P([0, 0, R])]
                if st.intExact { sph.append(exactBall(SIMD4(0, 0, 0, pos), R, approxC: C0, approxE: E0, spin: spin, alpha: a)) }
                else { sph.append(Self.ellipsoid(C0, E0, spin: spin, alpha: a)) }
            case 8:
                // キュービンダーの輪切り＝箱（底 2s × 2s、高さ 2√(r²−w²)）
                let s = OrigamiState.slCubS, h = OrigamiState.slCubH(ws)
                guard h > 1e-4 else { return }
                let V = (0..<8).map { v in P([v & 1 != 0 ? s : -s, v & 2 != 0 ? s : -s, v & 4 != 0 ? h : -h]) }
                for f in [[0, 1, 3, 2], [4, 5, 7, 6], [0, 1, 5, 4], [2, 3, 7, 6], [0, 2, 6, 4], [1, 3, 7, 5]] { tri(V[f[0]], V[f[1]], V[f[2]]); tri(V[f[0]], V[f[2]], V[f[3]]) }
            case 6:
                // 超立方体を角から切った切り口（四面体 → 角の切れた四面体 → 八面体 → …）。凸多面体を面ごとの多角形で
                for poly in Self.cornerSlice4(ws) { let Q = poly.map { P([$0.x, $0.y, $0.z]) }; for i in 1..<(Q.count - 1) { tri(Q[0], Q[i], Q[i + 1]) } }
            case 7:
                // 球のドーナツの輪切り：x の軸のまわりの回転体（半径 f(x)）。玉が 2 つ（x の左右）か、つながって 1 つ
                guard let rg = OrigamiState.slTorRange(ws) else { return }
                let NX = 18, NT = 20
                func blob(_ a: Double, _ b: Double) {
                    let mid = (a + b) / 2, half = (b - a) / 2
                    let xs: [Double] = (0...NX).map { (i: Int) -> Double in mid - half * cos(Double.pi * Double(i) / Double(NX)) }
                    let G = xs.map { x -> [SIMD3<Double>] in let f = OrigamiState.slTorF(x, ws); return (0...NT).map { s in let th = 2 * Double.pi * Double(s) / Double(NT); return P([x, f * cos(th), f * sin(th)]) } }
                    for i in 0..<NX { for s in 0..<NT { tri(G[i][s], G[i + 1][s], G[i][s + 1]); tri(G[i][s + 1], G[i + 1][s], G[i + 1][s + 1]) } }
                }
                if rg.two { blob(rg.lo, rg.hi); blob(-rg.hi, -rg.lo) } else { blob(-rg.hi, rg.hi) }
            case 2:
                // デュオシリンダーの輪切り＝円柱（半径 r、高さ 2√(r²−w²)）：横の面とふた 2 枚
                let r = OrigamiState.slDuoR, h = OrigamiState.slH(ws), CS = 32
                guard h > 1e-4 else { return }
                let ring = (0...CS).map { s -> (Double, Double) in let th = 2 * Double.pi * Double(s) / Double(CS); return (r * cos(th), r * sin(th)) }
                let lo = ring.map { P([$0.0, $0.1, -h]) }, hi = ring.map { P([$0.0, $0.1, h]) }, cl = P([0, 0, -h]), ch = P([0, 0, h])
                for s in 0..<CS { tri(lo[s], lo[s + 1], hi[s]); tri(lo[s + 1], hi[s + 1], hi[s]); tri(cl, lo[s], lo[s + 1]); tri(ch, hi[s + 1], hi[s]) }
            default:
                // タイガーの輪切り＝z の上下に 2 つのドーナツ（管のまわり α × 回り θ）。ρ₂＜|w| の所は z＝0 につぶれる（2 つがつながった所）
                let NA = 12, NT = 20
                for sg in [-1.0, 1.0] {
                    var G: [[SIMD3<Double>]] = []
                    for ai in 0...NA {
                        let al = 2 * Double.pi * Double(ai) / Double(NA), r1 = OrigamiState.slTgR1 + OrigamiState.slTgr * cos(al), r2 = OrigamiState.slTgR2 + OrigamiState.slTgr * sin(al)
                        let z = sg * sqrt(max(0, r2 * r2 - ws * ws))
                        G.append((0...NT).map { s in let th = 2 * Double.pi * Double(s) / Double(NT); return P([r1 * cos(th), r1 * sin(th), z]) })
                    }
                    for ai in 0..<NA { for s in 0..<NT { tri(G[ai][s], G[ai + 1][s], G[ai][s + 1]); tri(G[ai][s + 1], G[ai + 1][s], G[ai + 1][s + 1]) } }
                }
            }
        } else {
            // 左の窓（3 次元の仲間）：正方形の中に、行ごとの台形で
            func quad(_ x0: Double, _ x1: Double, _ ya: Double, _ x2: Double, _ x3: Double, _ yb: Double) {
                let q = [P([x0, ya]), P([x1, ya]), P([x3, yb]), P([x2, yb])]
                tri(q[0], q[1], q[2]); tri(q[0], q[2], q[3])
            }
            switch shape {
            case 1:   // 円柱の輪切り＝円（どの段も同じ）
                let R = OrigamiState.slBallR, ROWS = 16
                for i in 0..<ROWS {
                    let ya = -R * cos(Double.pi * Double(i) / Double(ROWS)), yb = -R * cos(Double.pi * Double(i + 1) / Double(ROWS))
                    let da = sqrt(max(0, R * R - ya * ya)), db = sqrt(max(0, R * R - yb * yb))
                    quad(-da, da, ya, -db, db, yb)
                }
            case 4:   // 内接する球の輪切り＝半径 √(1−z²) の円
                let R = sqrt(max(0, 1 - ws * ws)), ROWS = 16
                guard R > 1e-3 else { return }
                for i in 0..<ROWS {
                    let ya = -R * cos(Double.pi * Double(i) / Double(ROWS)), yb = -R * cos(Double.pi * Double(i + 1) / Double(ROWS))
                    let da = sqrt(max(0, R * R - ya * ya)), db = sqrt(max(0, R * R - yb * yb))
                    quad(-da, da, ya, -db, db, yb)
                }
            case 5:   // 円すいの輪切り＝半径 (1−z)／2 の円
                let R = OrigamiState.slConeR(ws), ROWS = 16
                guard R > 1e-3 else { return }
                for i in 0..<ROWS {
                    let ya = -R * cos(Double.pi * Double(i) / Double(ROWS)), yb = -R * cos(Double.pi * Double(i + 1) / Double(ROWS))
                    let da = sqrt(max(0, R * R - ya * ya)), db = sqrt(max(0, R * R - yb * yb))
                    quad(-da, da, ya, -db, db, yb)
                }
            case 8:   // x にのびた円柱の輪切り＝長方形（横 2s、高さ 2√(r²−z²)）
                let s = OrigamiState.slCubS, h = OrigamiState.slCubH(ws)
                if h > 1e-4 { quad(-s, s, -h, -s, s, h) }
            case 6:   // 立方体を角から切った切り口（三角形 → 六角形 → 三角形）
                let Q = Self.cornerSlice3(ws).map { P([$0.x, $0.y]) }
                if Q.count >= 3 { for i in 1..<(Q.count - 1) { tri(Q[0], Q[i], Q[i + 1]) } }
            case 7:   // ドーナツの輪切り：x の左右に丸 2 つ、または 1 つ（y の幅 2f(x)）
                guard let rg = OrigamiState.slTorRange(ws) else { return }
                let ROWS = 16
                func band(_ a: Double, _ b: Double) {
                    func X(_ i: Int) -> Double { (a + b) / 2 - (b - a) / 2 * cos(Double.pi * Double(i) / Double(ROWS)) }
                    for i in 0..<ROWS {
                        let xa = X(i), xb = X(i + 1), fa = OrigamiState.slTorF(xa, ws), fb = OrigamiState.slTorF(xb, ws)
                        let q = [P([xa, -fa]), P([xb, -fb]), P([xb, fb]), P([xa, fa])]; tri(q[0], q[1], q[2]); tri(q[0], q[2], q[3])
                    }
                }
                if rg.two { band(rg.lo, rg.hi); band(-rg.hi, -rg.lo) } else { band(-rg.hi, rg.hi) }
            case 2:   // 長方形（横 2r、高さ 2√(r²−z²)）
                let r = OrigamiState.slDuoR, h = OrigamiState.slH(ws)
                if h > 1e-4 { quad(-r, r, -h, -r, r, h) }
            default:  // x ＝ ±R₁ の左右に、y の上下に丸（|w| が R₂−r を越えると上下がつながる）
                let r = OrigamiState.slTgr, R1 = OrigamiState.slTgR1, R2 = OrigamiState.slTgR2, hi2 = (R2 + r) * (R2 + r) - ws * ws
                guard hi2 > 0 else { return }
                let hi = sqrt(hi2), lo = sqrt(max(0, (R2 - r) * (R2 - r) - ws * ws)), ROWS = 16
                func dAt(_ y: Double) -> Double { let q = sqrt(y * y + ws * ws) - R2; return sqrt(max(0, r * r - q * q)) }
                func band(_ y0: Double, _ y1: Double) {
                    func Y(_ i: Int) -> Double { (y0 + y1) / 2 - (y1 - y0) / 2 * cos(Double.pi * Double(i) / Double(ROWS)) }
                    for i in 0..<ROWS { let ya = Y(i), yb = Y(i + 1), da = dAt(ya), db = dAt(yb); quad(R1 - da, R1 + da, ya, R1 - db, R1 + db, yb); quad(-R1 - da, -R1 + da, ya, -R1 - db, -R1 + db, yb) }
                }
                if lo > 0 { band(lo, hi); band(-hi, -lo) } else { band(-hi, hi) }
            }
        }
    }
}

extension OrigamiRenderer {
    /// 内接する超球（球）が、超立方体（立方体）の胞（面）に接する点：胞の真ん中（±e_i）。積分がその w まで届いたら、金色の点をともす（脈打つ）
    func hyperTouchMarks(front: Double, back: Double, k: Double) -> [TLBall] {
        let H = OrigamiState.half, d = n - 1
        var out: [TLBall] = []
        let pulse = 0.75 + 0.25 * sin(Date().timeIntervalSinceReferenceDate * 4)
        for ax in 0...d { for sg in [-1.0, 1.0] {
            var u = [Double](repeating: 0, count: n); u[ax] = sg
            let w = u[d]                                                    // 折りたたみの向き（超立方体は w、立方体は z）の値
            guard w >= back - 1e-6 && w <= front + 1e-6 else { continue }   // 積分がそこまで届いた所だけ
            let p = st.place(u.map { $0 * H }, n).0
            out.append(TLBall(p: SIMD4(gpuS(p), Float(0.05 * pulse)), col: SIMD4(SIMD3<Float>(1.0, 0.84, 0.3) * Float(k), 2)))
        } }
        return out
    }
}
