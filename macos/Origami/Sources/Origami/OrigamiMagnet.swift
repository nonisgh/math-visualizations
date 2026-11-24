// 手前と奥の目印の磁石と光、内接球の模様の回転（3D・4D の二重回転）。
//   目印：手前の頂点（＋…＋）と奥の頂点（−…−）は 4D でちょうど反対側の 2 点なので、4D でどう回しても、写すと真ん中（原点）を通る
//   1 本の直線の上にのる。目がその直線の上にあれば、遠近があっても 2 点はぴったり重なる。手で回してそこに近づいたら（2.5° 以内）、
//   3D の向きだけを少し回して、ぴたっと吸いつかせる（4D のかたむきは変えない）。ぴったり重なった瞬間に光の輪。
//   内接球の回転：球はまんまるなので回しても形と接点は変わらず、模様（殻・膜・網目）だけが動く。
//     3D：w ＝ 一定の層ごとに、層の中で y の軸のまわりに回す。赤道の層ほど速く（層ごとの差）＝膜がねじれてうずまきに。
//     4D：X-Y の面と Z-W の面を同時に回す（二重回転）。1 : 1 なら止まる点が 1 つもなく、どの点も大円を走り、その道どうしは
//       鎖のようにからみ合う（ホップの輪）。Z-W が回るので、w ＝ 一定の層がかたむいて流れ出す
import Foundation
import simd

extension OrigamiState {
    /// 二重回転の速さの比（Z-W ÷ X-Y）・名前・1 周の道を閉じるのに要る X-Y の周回数
    static let sphRatios: [(r: Double, name: String, q: Double)] = [(1, "1 : 1（ホップ）", 1), (2, "1 : 2", 1), (0.5, "2 : 1", 2), (0, "1 : 0（ふつう）", 1)]
    /// 手前と奥の目印：ずれを測り、重なった瞬間に光らせ、近ければ吸いつかせる（1 コマごと）
    func markTick(_ dt: Double) {
        markFlashT += dt
        guard markShowNear && markShowFar, progress >= 0.999, explodeE < 1e-3, !isPreview else { markAlign = 1; markWasAligned = false; return }
        let near = place(fold(.cap, [1, 1, 1, 1], 4), 4).0, far = place(fold(.center, [-1, -1, -1, -1], 4), 4).0, o0 = place([0, 0, 0, 0], 4).0
        let eye = SIMD3<Double>(center[1].x, center[1].y, dist[1])
        var a = near - far, e = eye - o0
        let la = simd_length(a), le = simd_length(e)
        guard la > 1e-9, le > 1e-9 else { return }
        a /= la; e /= le
        let c = simd_dot(a, e), sg = c < 0 ? -1.0 : 1.0, th = acos(min(1, abs(c)))
        markAlign = th
        if th < 0.0015 { if !markWasAligned && markFlash { markFlashT = 0 }; markWasAligned = true }
        else if th > 0.004 { markWasAligned = false }
        // 磁石：手を離している時・ほかに回しているものが無い時だけ。残りの 1 割ずつ（約 0.2 秒）近づけ、わずかになったらちょうどに
        let busy = tween != nil || asmLand != nil || pp != nil || cycling || spinX || spinY || spinZW || spinXY || spinXZ || spinYZ || stepRemain.contains { abs($0) > 1e-7 }
        guard markMagnet, !dragging, !busy, th > 1e-7, th < 2.5 * Double.pi / 180 else { return }
        let step = th < 2e-4 ? th : th * min(1, 10 * dt)
        let ax = simd_cross(a * sg, e), lx = simd_length(ax)
        guard lx > 1e-12 else { return }
        let Q = simd_double4x4(simd_quatd(angle: step, axis: ax / lx))
        let d = Self.decompose(Q * Self.rot3(cur6), [xy, xz, yz])
        xyManualOff = Self.wrapPi(xyManualOff + Self.wrapPi(d[0] - xy))         // 手で回したのと同じ（左の立方体の X-Y は変えない）
        xy = d[0]; xz = d[1]; yz = d[2]; rotRev += 1; updateMats()
    }
    /// 手前と奥の目印がちょうど重なる向きへ、3D の向きだけを一気に回す（確かめの絵と数字のテスト用。磁石と同じ計算）
    func markAlignNow() {
        let near = place(fold(.cap, [1, 1, 1, 1], 4), 4).0, far = place(fold(.center, [-1, -1, -1, -1], 4), 4).0, o0 = place([0, 0, 0, 0], 4).0
        let e = simd_normalize(SIMD3<Double>(center[1].x, center[1].y, dist[1]) - o0), a = simd_normalize(near - far)
        let ax = simd_cross(a, e), lx = simd_length(ax)
        guard lx > 1e-12 else { return }
        let Q = simd_double4x4(simd_quatd(angle: atan2(lx, simd_dot(a, e)), axis: ax / lx))
        let d = Self.decompose(Q * Self.rot3(cur6), [xy, xz, yz]); xy = d[0]; xz = d[1]; yz = d[2]; updateMats()
    }
    /// 内接球の模様の回転を進める（組み上がっている時だけ）
    func sphereSpinTick(_ dt: Double) {
        guard inSphere, inSphereSpin != 0, progress >= 0.92, !isPreview else { return }
        inSphereT = (inSphereT + dt * 0.6 * inSphereSpinSpeed).truncatingRemainder(dividingBy: 2 * Double.pi * 1000)
    }
    /// 4D の二重回転（X-Y を T、Z-W を r·T）
    static func doubleRot(_ u: SIMD4<Double>, _ T: Double, _ r: Double) -> SIMD4<Double> {
        let c1 = cos(T), s1 = sin(T), c2 = cos(r * T), s2 = sin(r * T)
        return SIMD4(u.x * c1 - u.y * s1, u.x * s1 + u.y * c1, u.z * c2 - u.w * s2, u.z * s2 + u.w * c2)
    }
    /// 内接球の模様の回転の決まり（1 コマに 1 回だけ設定を読んで作る。点ごとに設定を読むと、何万回も読むので重い）
    func sphereSpinRule(n: Int) -> SphereSpinRule? {
        guard inSphere, inSphereSpin != 0 else { return nil }
        let mode = n == 4 && inSphereSpin == 2 ? 2 : 1
        return SphereSpinRule(n: n, mode: mode, T: inSphereT, d: inSphereSpin == 1 ? inSphereDiff : 0, r: Self.sphRatios[max(0, min(Self.sphRatios.count - 1, inSphereRatio))].r)
    }
    /// 内接球の模様の点 u（球の上）→ 超立方体（立方体の窓は x・y・z、u.w は使わない）の座標。inv：逆（超立方体の点 → 模様の点）
    func sphereSpun(_ u: SIMD4<Double>, n: Int, inv: Bool = false) -> SIMD4<Double> {
        guard let R = sphereSpinRule(n: n) else { return u }
        return R.apply(u, inv: inv)
    }
    /// 接点 c（超立方体の座標）を模様の経線が通っている度合い（0〜1）。経線は y の軸（立方体の窓は z の軸）のまわりの角 φ が
    ///   45° おき（経度の膜を切った時は網目の 90° おき）
    func sphereContactFlash(_ c: SIMD4<Double>, n: Int) -> Double {
        guard inSphere, inSphereSpin != 0, inSphereFlash else { return 0 }
        let u = sphereSpun(c, n: n, inv: true)
        let (p, q) = n == 4 ? (u.x, u.z) : (u.x, u.y)
        guard hypot(p, q) > 0.2 else { return 0 }                                  // 回る軸の上（極）は、いつも経線が集まるので光らせない
        let sp = inSphereLon ? Double.pi / 4 : Double.pi / 2, ph = atan2(q, p)
        let dd = abs(remainder(ph, sp))
        return exp(-pow(dd / 0.07, 2))
    }
}

/// 内接球の模様の回転（決まった数だけを持つ。点ごとの計算はこれで）
struct SphereSpinRule {
    let n: Int, mode: Int, T: Double, d: Double, r: Double
    @inline(__always) func apply(_ u: SIMD4<Double>, inv: Bool = false) -> SIMD4<Double> {
        let T = inv ? -self.T : self.T
        if mode == 2 { return OrigamiState.doubleRot(u, T, r) }
        if n == 4 {
            // 層（w）ごとに、層の中で y の軸のまわりに（X-Z の面）。赤道の層ほど速い
            let a = T * ((1 - d) + d * max(0, 1 - u.w * u.w).squareRoot()), c = cos(a), s = sin(a)
            return SIMD4(u.x * c - u.z * s, u.y, u.x * s + u.z * c, u.w)
        }
        // 立方体の窓：層（z）ごとに、z の軸のまわりに（X-Y の面）
        let a = T * ((1 - d) + d * max(0, 1 - u.z * u.z).squareRoot()), c = cos(a), s = sin(a)
        return SIMD4(u.x * c - u.y * s, u.x * s + u.y * c, u.z, u.w)
    }
}
