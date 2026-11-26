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

// ---- 4 次元の立体を見る（3 つの窓）：ウェブ版の「柱の見本」を移植 ----
//   立体は「中か外かの式」（符号つき距離のようなもの：0 以下が中）1 つで決める。同じ式から、断面（3D の切り口）・4D の影（w の輪切りを重ねる）・
//   3D のたとえ（1 つ下の次元の仲間）を作る。大きさはウェブ版と同じ（箱の半分の辺 H に対して：R ＝ 0.8H、タイガー R₁ ＝ R₂ ＝ 0.55H・r ＝ 0.26H、4D トーラス 0.55H・0.32H）
//   1 球柱（玉 × 線分）・2 デュオシリンダー（円 × 円）・3 タイガー・4 4 次元トーラス（円 × 玉）・5 超球
struct ShapeMesh { var p: [SIMD4<Double>] = []; var g: [SIMD4<Double>] = [] }   // 三角形の点（4D、体の座標）と、その点の式の坂（面の向き）

extension OrigamiState {
    static let shapeNames = ["", "球柱（玉 × 線分）", "デュオシリンダー（円 × 円）", "タイガー", "4 次元トーラス（円 × 玉）", "超球"]
    static let shapeAnalog = ["", "円柱", "円柱（高さ ＝ 直径）", "ドーナツ 2 つ", "ドーナツ", "球"]
    static let shpR = 0.8, shpT1 = 0.55, shpTr = 0.26, shpT4r = 0.32
    static let shpRound = 0.06                                       // 角の丸み（H の何倍か）：球柱・デュオシリンダー・円柱の角（2 つの面がまじわる所）を少し丸める
    /// 2 つの形の重なり（max）を、角を半径 e で丸めて。2 つの式の坂が直交している時（球柱・デュオ・円柱）は、角の外も本当の距離になる。
    ///   ただの max だと角がとがって、四面体で取り出した面がぎざぎざになっていた（デュオシリンダー。2026-11-26）
    static func roundMax(_ a: Double, _ b: Double, _ e: Double) -> Double {
        let x = a + e, y = b + e
        return (max(x, 0) * max(x, 0) + max(y, 0) * max(y, 0)).squareRoot() + min(max(x, y), 0) - e
    }
    /// 4D の立体の式（体の座標、0 以下が中）
    static func shpF4(_ k: Int, _ p: SIMD4<Double>) -> Double {
        let H = half, R = shpR * H
        let rxy = (p.x * p.x + p.y * p.y).squareRoot(), rzw = (p.z * p.z + p.w * p.w).squareRoot()
        switch k {
        case 1: return roundMax((p.x * p.x + p.y * p.y + p.z * p.z).squareRoot() - R, abs(p.w) - H, shpRound * H)
        case 2: return roundMax(rxy - R, rzw - R, shpRound * H)
        case 3: let a = rxy - shpT1 * H, b = rzw - shpT1 * H; return (a * a + b * b).squareRoot() - shpTr * H
        case 4: let a = rxy - shpT1 * H; return (a * a + rzw * rzw).squareRoot() - shpT4r * H
        default: return simd_length(p) - R
        }
    }
    /// 3D のたとえ（左の窓、z が 4D の w の仲間）
    static func shpF3(_ k: Int, _ p: SIMD3<Double>) -> Double {
        let H = half, R = shpR * H, rxy = (p.x * p.x + p.y * p.y).squareRoot()
        switch k {
        case 1: return roundMax(rxy - R, abs(p.z) - H, shpRound * H)
        case 2: return roundMax(rxy - R, abs(p.z) - R, shpRound * H)
        case 3: let a = rxy - shpT1 * H, b = abs(p.z) - shpT1 * H; return (a * a + b * b).squareRoot() - shpTr * H
        case 4: let a = rxy - shpT1 * H; return (a * a + p.z * p.z).squareRoot() - shpT4r * H
        default: return simd_length(p) - R
        }
    }
    /// 立体がおさまる半径（4D・3D）と、w（3D は z）の向きの広がり
    static func shpBound(_ k: Int) -> (r4: Double, r3: Double, w: Double) {
        let H = half, R = shpR * H, t = shpT1 * H
        switch k {
        case 1: return ((R * R + H * H).squareRoot(), (R * R + H * H).squareRoot(), H)
        case 2: return (R * 2.0.squareRoot(), R * 2.0.squareRoot(), R)
        case 3: let a = t + shpTr * H; return ((a * a * 2).squareRoot(), (a * a * 2).squareRoot(), a)
        case 4: let a = t + shpT4r * H; return ((a * a + shpT4r * H * shpT4r * H).squareRoot(), a, shpT4r * H)
        default: return (R, R, R)
        }
    }
    /// 3D の格子（−L〜L、N 分割）の上の式 f の 0 の面を、四面体で取り出す（点は格子の座標 a・b・c。向きは中 → 外）
    static func marchTets(_ N: Int, _ L: Double, _ f: (SIMD3<Double>) -> Double) -> [SIMD3<Double>] {
        let M = N + 1, d = 2 * L / Double(N)
        var V = [Double](repeating: 0, count: M * M * M)
        for k in 0..<M { for j in 0..<M { for i in 0..<M { V[(k * M + j) * M + i] = f(SIMD3(-L + Double(i) * d, -L + Double(j) * d, -L + Double(k) * d)) } } }
        let tetF = [0, 1, 3, 7, 0, 3, 2, 7, 0, 2, 6, 7, 0, 6, 4, 7, 0, 4, 5, 7, 0, 5, 1, 7], cases = NS4.tetCases
        var out: [SIMD3<Double>] = []
        var c = [Double](repeating: 0, count: 8), cp = [SIMD3<Double>](repeating: .zero, count: 8)
        for k in 0..<N { for j in 0..<N { for i in 0..<N {
            var neg = 0
            for b in 0..<8 {
                let ii = i + (b & 1), jj = j + ((b >> 1) & 1), kk = k + ((b >> 2) & 1)
                c[b] = V[(kk * M + jj) * M + ii]; if c[b] < 0 { neg += 1 }
                cp[b] = SIMD3(-L + Double(ii) * d, -L + Double(jj) * d, -L + Double(kk) * d)
            }
            if neg == 0 || neg == 8 { continue }
            for t in 0..<6 {
                var m = 0
                for q in 0..<4 where c[tetF[4 * t + q]] < 0 { m |= 1 << q }
                if m == 0 || m == 15 { continue }
                let es = cases[m]
                var wc = SIMD3<Double>.zero, ac = SIMD3<Double>.zero, ni = 0.0, no = 0.0
                for q in 0..<4 { let pq = cp[tetF[4 * t + q]]; if m & (1 << q) != 0 { wc += pq; ni += 1 } else { ac += pq; no += 1 } }
                let outDir = ac / no - wc / ni
                var e = 0
                while e + 2 < es.count {
                    var P = (0..<3).map { s -> SIMD3<Double> in
                        let (a, o) = es[e + s], qa = tetF[4 * t + a], qo = tetF[4 * t + o]
                        return cp[qa] + (cp[qo] - cp[qa]) * (c[qa] / (c[qa] - c[qo]))
                    }
                    e += 3
                    let nrm = simd_cross(P[1] - P[0], P[2] - P[0]); if simd_length_squared(nrm) < 1e-16 { continue }
                    if simd_dot(nrm, outDir) < 0 { P.swapAt(1, 2) }
                    out += P
                }
            }
        } } }
        return out
    }
    /// 4D の式の坂（4D の向き、中 → 外）
    static func shpGrad4(_ k: Int, _ p: SIMD4<Double>) -> SIMD4<Double> {
        let e = 1e-4 * half
        var g = SIMD4<Double>(0, 0, 0, 0)
        for a in 0..<4 { var u = p, v = p; u[a] += e; v[a] -= e; g[a] = (shpF4(k, u) - shpF4(k, v)) / (2 * e) }
        return g
    }
    /// 断面：4D の回転で写した w′ ＝ s の 3 次元の面（体の座標では、回転の行列の w の行に垂直）で切った切り口。
    ///   面の上の点 ＝ a u₀ ＋ b u₁ ＋ c u₂ ＋ s u₃（u は回転の行）。4D の窓で写すと、切り口はゆがまずに（大きさだけ変わって）見える
    func shapeSection() -> ShapeMesh {
        let k = shapeKind, rows = (0..<4).map { r in SIMD4<Double>(m4[0][r], m4[1][r], m4[2][r], m4[3][r]) }
        let bd = Self.shpBound(k), s = shapeCut * bd.r4
        let coarse = dragging || shapePlay                                // 回している・動かしている間は粗く、止まったら細かく
        let key: [Double] = [Double(k), s, coarse ? 1.0 : 0.0] + rows.flatMap { r -> [Double] in [r.x, r.y, r.z, r.w] }
        if key == shapeSecKey { return shapeSecCache }
        let L = (max(0, bd.r4 * bd.r4 - s * s)).squareRoot() * 1.02 + 1e-3
        func Q(_ v: SIMD3<Double>) -> SIMD4<Double> { rows[0] * v.x + rows[1] * v.y + rows[2] * v.z + rows[3] * s }
        let pts = Self.marchTets(coarse ? 56 : 92, L, { Self.shpF4(k, Q($0)) })   // 角の丸み（0.06H）が、止まった時はマス 3 つ分・回す間も 2 つ分になる細かさ
        var m = ShapeMesh(); m.p = pts.map(Q); m.g = m.p.map { Self.shpGrad4(k, $0) }
        shapeSecCache = m; shapeSecKey = key
        return m
    }
    /// 4D の影：立体を、体の w の輪切り（w ＝ 一定の 3D の立体）を何枚も重ねて見せる（輪切りは立体ごとに 1 回作っておく）
    func shapeLayers() -> [ShapeMesh] {
        if shapeLayKind == shapeKind { return shapeLayCache }
        let k = shapeKind, bd = Self.shpBound(k), NL = 9
        var out: [ShapeMesh] = []
        for l in 0..<NL {
            let w = bd.w * (-1 + 2 * (Double(l) + 0.5) / Double(NL))
            let pts = Self.marchTets(40, bd.r4 * 1.02, { Self.shpF4(k, SIMD4($0.x, $0.y, $0.z, w)) })
            var m = ShapeMesh(); m.p = pts.map { SIMD4($0.x, $0.y, $0.z, w) }; m.g = m.p.map { Self.shpGrad4(k, $0) }
            out.append(m)
        }
        shapeLayCache = out; shapeLayKind = k
        return out
    }
    /// 本物の影（立体）：4D の窓の 3D の点 X に写る 4D の点は、目からの 1 本の線（回したあとの座標で xyz ＝ X／k(w)、w は自由。k は遠近の縮み）。
    ///   その線が立体にぶつかれば、X は影の中。g(X) ＝ 線の上での式のいちばん小さい値（w を 24 か所で調べて、いちばん小さい所のまわりを 3 分割でしぼる）。
    ///   g ＝ 0 の面を四面体で取り出す。色は、いちばん近づいた 4D の点の y（断面と同じ七色の帯）。回している間は粗く
    func shapeShadowSolid() -> (p: [SIMD3<Double>], n: [SIMD3<Double>], y: [Double]) {
        let k = shapeKind, bd = Self.shpBound(k), D = camW, pb = projBlend, coarse = dragging || shapePlay
        let key: [Double] = [Double(k), D, pb, coarse ? 1.0 : 0.0] + (0..<4).flatMap { c -> [Double] in (0..<4).map { m4[c][$0] } }
        if key == shapeSolKey { return shapeSolCache }
        let Mt = simd_transpose(m4), r4 = bd.r4
        func kk(_ w: Double) -> Double { let ww = max(-D + 0.5, min(D - 0.5, w)); return 1 + (1 / (1 - ww / D) - 1) * (1 - pb) }
        func f(_ X: SIMD3<Double>, _ w: Double) -> Double { let kw = kk(w); return Self.shpF4(k, Mt * SIMD4(X.x / kw, X.y / kw, X.z / kw, w)) }
        func g(_ X: SIMD3<Double>) -> (Double, Double) {
            let NS = 24
            var bw = -r4, bv = Double.infinity
            for i in 0...NS { let w = -r4 + 2 * r4 * Double(i) / Double(NS), v = f(X, w); if v < bv { bv = v; bw = w } }
            var lo = max(-r4, bw - 2 * r4 / Double(NS)), hi = min(r4, bw + 2 * r4 / Double(NS))
            for _ in 0..<10 { let a = lo + (hi - lo) / 3, b = hi - (hi - lo) / 3; if f(X, a) < f(X, b) { hi = b } else { lo = a } }
            let w = (lo + hi) / 2, v = f(X, w)
            return v < bv ? (v, w) : (bv, bw)
        }
        let L = r4 * kk(r4) * 1.03
        let pts = Self.marchTets(coarse ? 32 : 64, L, { g($0).0 })
        // 頂点ごとの面の向き：同じ点を使う三角形の向きの平均（なめらかに光る）
        var acc: [SIMD3<Int64>: SIMD3<Double>] = [:]
        func key3(_ p: SIMD3<Double>) -> SIMD3<Int64> { SIMD3(Int64((p.x * 1e6).rounded()), Int64((p.y * 1e6).rounded()), Int64((p.z * 1e6).rounded())) }
        var i = 0
        while i + 2 < pts.count { let nn = simd_cross(pts[i + 1] - pts[i], pts[i + 2] - pts[i]); for j in 0..<3 { acc[key3(pts[i + j]), default: .zero] += nn }; i += 3 }
        var ys: [Double] = [], ns: [SIMD3<Double>] = []
        ys.reserveCapacity(pts.count); ns.reserveCapacity(pts.count)
        var ycache: [SIMD3<Int64>: Double] = [:]
        for p in pts {
            let kp = key3(p), a = acc[kp] ?? SIMD3(0, 0, 1), l = simd_length(a); ns.append(l > 1e-12 ? a / l : SIMD3(0, 0, 1))
            if let y = ycache[kp] { ys.append(y); continue }
            let w = g(p).1, kw = kk(w), q = Mt * SIMD4(p.x / kw, p.y / kw, p.z / kw, w); ycache[kp] = q.y; ys.append(q.y)
        }
        shapeSolCache = (pts, ns, ys); shapeSolKey = key
        return shapeSolCache
    }
    /// 3D のたとえ（左の窓）の面
    func shapeAnalog() -> [SIMD3<Double>] {
        if shapeAnaKind == shapeKind { return shapeAnaCache }
        let k = shapeKind
        shapeAnaCache = Self.marchTets(64, Self.shpBound(k).r3 * 1.02, { Self.shpF3(k, $0) }); shapeAnaKind = k
        return shapeAnaCache
    }
    /// 七色の帯（ウェブ版の band：7 つに分けた色相 0.82×(m＋0.5)／7）
    static func bandColor(_ t: Double) -> SIMD3<Float> {
        let m = max(0, min(6, floor(t * 7))), h = 0.82 * (m + 0.5) / 7
        func ch(_ o: Double) -> Float { let x = abs((h * 6 + o).truncatingRemainder(dividingBy: 6) - 3) - 1; return Float(0.58 + 0.84 * (max(0, min(1, x)) - 0.5)) }
        return SIMD3(ch(0), ch(4), ch(2))
    }
    /// なめらかな色相（w で色を変える透ける虹）
    static func hueColor(_ t: Double) -> SIMD3<Float> {
        let h = max(0, min(1, t)) * 0.82
        func ch(_ o: Double) -> Float { let x = abs((h * 6 + o).truncatingRemainder(dividingBy: 6) - 3) - 1; return Float(0.3 + 0.7 * max(0, min(1, x))) }
        return SIMD3(ch(0), ch(4), ch(2))
    }
}

@inline(__always) private func gpuSh(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// この 4D の窓に断面だけを出すか（メインの窓はふつう断面、「断面 ⇄ 投影」で入れかわる）
    var showsSectionOnly: Bool { st.shapeOn && n == 4 && !st.dim5 && ((role == 1) != st.shapeMainProj) }
    /// 断面の三角形（色つき）。glow：4D の影の中の「今切っている所」として光らせる
    func shapeSectionBatch(eye: SIMD3<Double>, glow: Bool) -> IntTriBatch? {
        let m = st.shapeSection(); guard m.p.count >= 3 else { return nil }
        let R = OrigamiState.shpR * OrigamiState.half, L = simd_normalize(SIMD3<Double>(0.35, 0.6, 0.72))
        var v: [IntVert] = []; v.reserveCapacity(m.p.count)
        let nr = SIMD4<Double>(st.m4[0][3], st.m4[1][3], st.m4[2][3], st.m4[3][3])
        for i in 0..<m.p.count {
            let q = m.p[i], P0 = st.place([q.x, q.y, q.z, q.w], 4).0
            if glow { let a = Float(0.16 * st.shapeGlowAlpha); v.append(IntVert(p: SIMD4(gpuSh(P0), 1), c: SIMD4(SIMD3<Float>(1, 0.78, 0.35) * a, a))); continue }
            var g = m.g[i]; g -= nr * simd_dot(g, nr)                      // 切る面に沿った向きだけ（切り口の面の向き）
            let gl = simd_length(g), e = 0.02
            var nv = SIMD3<Double>(0, 0, 1)
            if gl > 1e-9 { let q2 = q + g / gl * e, P1 = st.place([q2.x, q2.y, q2.z, q2.w], 4).0; nv = simd_normalize(P1 - P0) }
            let vd = simd_normalize(eye - P0), lam = max(0, simd_dot(nv, L)) * 0.65 + 0.35 * abs(simd_dot(nv, vd)), rim = pow(1 - abs(simd_dot(nv, vd)), 3)
            // 七色の帯は画素ごとに（ベクターのようにくっきり）：c.x＝帯の値・c.y＝明るさ・c.z＝ふちの白さ・p.w＝10＋濃さ
            v.append(IntVert(p: SIMD4(gpuSh(P0), 10.9), c: SIMD4(Float(q.y / R * 0.5 + 0.5), Float(0.3 + 0.75 * lam), Float(0.25 * rim), 0)))
        }
        return IntTriBatch(add: glow, verts: v)
    }
    /// 本物の影（立体）：七色の帯で、少しすける（中の光る断面が見えるように）
    func shapeSolidBatch(eye: SIMD3<Double>) -> IntTriBatch? {
        let s = st.shapeShadowSolid(); guard s.p.count >= 3 else { return nil }
        let R = OrigamiState.shpR * OrigamiState.half, L = simd_normalize(SIMD3<Double>(0.35, 0.6, 0.72))
        var v: [IntVert] = []; v.reserveCapacity(s.p.count)
        for i in 0..<s.p.count {
            let P0 = s.p[i], nv = s.n[i], vd = simd_normalize(eye - P0)
            let lam = max(0, simd_dot(nv, L)) * 0.6 + 0.4 * abs(simd_dot(nv, vd)), rim = pow(1 - abs(simd_dot(nv, vd)), 3)
            let hv = simd_normalize(L + vd), sp = pow(max(0, simd_dot(nv, hv)), 40) * 0.5
            let a = Float((0.55 + 0.35 * rim) * st.shapeShadowAlpha)
            v.append(IntVert(p: SIMD4(gpuSh(P0), 10 + max(0.001, a)), c: SIMD4(Float(s.y[i] / R * 0.5 + 0.5), Float(0.3 + 0.7 * lam), Float(0.3 * rim + sp), 0)))
        }
        return IntTriBatch(add: false, verts: v)
    }
    /// 積分の積み上げの番号（積分タブの形）：球柱 1・デュオ 2・タイガー 3・4D トーラス → 球のドーナツ 7・超球 → 内接する超球 4
    static let shapeIntId = [0, 1, 2, 3, 7, 4]
    static let shapeStackN = 64                                       // 積み上げの段の数（積分の仕上がりと同じくらいなめらかに）
    /// 4D の影（積分の積み上げ）：積分タブと同じ輪切りの形を、w の −1 〜 ＋1 に段ごとに置く（色は積む順：赤 → 紫）。大きさは積分タブの形のまま
    func shapeStackBatch(eye: SIMD3<Double>) -> IntTriBatch? {
        let sid = Self.shapeIntId[max(1, min(5, st.shapeKind))], N = Self.shapeStackN
        var v: [IntVert] = [], sph: [IntSphere] = []
        for j in 0..<N {
            let t = -1 + (2 * Double(j) + 1) / Double(N)
            sliceShape(&v, &sph, shape: sid, pos: t, ws: t, a: 0.85 * st.shapeShadowAlpha, eye: eye, ballRes: sid == 1 ? 6 : 7, spin: 0)
        }
        intSpheres += sph
        return v.isEmpty ? nil : IntTriBatch(add: false, verts: v)
    }
    /// 4D の影（w の輪切りを重ねる。色は w：透ける虹）
    func shapeShadowBatch(eye: SIMD3<Double>) -> IntTriBatch? {
        guard st.shapeShadowOn, st.shapeShadowAlpha > 0.005 else { return nil }   // 影なし：光る断面だけ
        if st.shapeShadowMode == 1 { return shapeStackBatch(eye: eye) }
        if st.shapeShadowMode == 2 { return shapeSolidBatch(eye: eye) }
        let bd = OrigamiState.shpBound(st.shapeKind)
        var v: [IntVert] = []
        for m in st.shapeLayers() {
            guard let w0 = m.p.first?.w else { continue }
            let col = OrigamiState.hueColor(w0 / max(1e-9, bd.w) * 0.5 + 0.5)
            var i = 0
            while i + 2 < m.p.count {
                let P = (0..<3).map { s -> SIMD3<Double> in let q = m.p[i + s]; return st.place([q.x, q.y, q.z, q.w], 4).0 }
                let nn = simd_cross(P[1] - P[0], P[2] - P[0]), nl = simd_length(nn)
                let rim = nl > 1e-12 ? 1 - abs(simd_dot(nn / nl, simd_normalize(eye - P[0]))) : 0.5
                let a = Float((0.012 + 0.1 * pow(rim, 3)) * st.shapeShadowAlpha)   // 9 枚重なるので、1 枚はうすく（ふちだけ見えるように）
                for p in P { v.append(IntVert(p: SIMD4(gpuSh(p), 1), c: SIMD4(col * a, a))) }
                i += 3
            }
        }
        return v.isEmpty ? nil : IntTriBatch(add: false, verts: v)
    }
    /// 3D のたとえ（左の窓）：立体・切る面・切り口の線
    func shapeAnalogBatch(_ rods: inout [TLRod], eye: SIMD3<Double>) -> IntTriBatch? {
        let pts = st.shapeAnalog(), R = OrigamiState.shpR * OrigamiState.half, bd = OrigamiState.shpBound(st.shapeKind)
        let nr = SIMD3<Double>(st.l3[0][2], st.l3[1][2], st.l3[2][2]), s = st.shapeCut * bd.r3
        func P(_ q: SIMD3<Double>) -> SIMD3<Double> { st.place([q.x, q.y, q.z], 3).0 }
        var v: [IntVert] = []; v.reserveCapacity(pts.count)
        var i = 0
        let red = SIMD3<Float>(1, 0.35, 0.35)
        while i + 2 < pts.count {
            let q = [pts[i], pts[i + 1], pts[i + 2]], Pq = q.map(P)
            let nn = simd_cross(Pq[1] - Pq[0], Pq[2] - Pq[0]), nl = simd_length(nn)
            let rim = nl > 1e-12 ? 1 - abs(simd_dot(nn / nl, simd_normalize(eye - Pq[0]))) : 0.5
            for j in 0..<3 {
                let a = Float(0.18 + 0.4 * pow(rim, 2))
                v.append(IntVert(p: SIMD4(gpuSh(Pq[j]), 10 + a), c: SIMD4(Float(q[j].y / R * 0.5 + 0.5), 1, 0, 0)))   // 帯は画素ごとに
            }
            // 切り口の線：三角形と切る面（n·q ＝ s）の交わり
            let dd = q.map { simd_dot($0, nr) - s }
            var cut: [SIMD3<Double>] = []
            for (a, b) in [(0, 1), (1, 2), (2, 0)] where (dd[a] < 0) != (dd[b] < 0) { cut.append(q[a] + (q[b] - q[a]) * (dd[a] / (dd[a] - dd[b]))) }
            if cut.count == 2 { rods.append(TLRod(a: SIMD4(gpuSh(P(cut[0])), 0), b: SIMD4(gpuSh(P(cut[1])), 1.8), col: SIMD4(red, 1.2))) }
            i += 3
        }
        // 切る面：箱いっぱいの四角（うすい白）
        let hp: SIMD3<Double> = abs(nr.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), e1 = simd_normalize(simd_cross(nr, hp)), e2 = simd_cross(nr, e1), E = bd.r3 * 1.15
        let c0 = nr * s, cs = [c0 + (e1 + e2) * E, c0 + (e1 - e2) * E, c0 + (-e1 - e2) * E, c0 + (-e1 + e2) * E].map(P)
        let wa: Float = 0.07, wc = SIMD4<Float>(0.9 * wa, 0.95 * wa, wa, wa)
        for (a, b, c) in [(0, 1, 2), (0, 2, 3)] { v += [IntVert(p: SIMD4(gpuSh(cs[a]), 1), c: wc), IntVert(p: SIMD4(gpuSh(cs[b]), 1), c: wc), IntVert(p: SIMD4(gpuSh(cs[c]), 1), c: wc)] }
        for j in 0..<4 { rods.append(TLRod(a: SIMD4(gpuSh(cs[j]), 0), b: SIMD4(gpuSh(cs[(j + 1) % 4]), 0), col: SIMD4(SIMD3<Float>(0.85, 0.9, 1), 0.4))) }
        return IntTriBatch(add: false, verts: v)
    }
}
