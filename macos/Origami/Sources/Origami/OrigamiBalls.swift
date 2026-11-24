// 玉を詰める（積分ではないお遊び）：小さな 4 次元の玉（超球）を、上（+W）から 1 つずつ落として、超立方体の箱に詰めていく物理シミュレーション。
//   重力は箱の −w（+W→−W、積分と同じ）。玉どうし・壁とぶつかって、はずんで、底から積もる。玉は壁に 1 点でしか接しないので、角やへりにはすきまが残る。
//   詰まり具合 ＝ 玉の体積の合計 ÷ 箱の体積（4D の玉の体積は π²r⁴／2、箱は (2H)⁴）。立方体を積んだ時の 100% とくらべる。
//   左の立方体の窓は 1 つ下の仲間：同じ大きさの 3 次元の玉を、同じように立方体に落とす（3D の玉の体積は 4πr³／3）。
//   「角に 16 個＋真ん中」：半径 H／2 の玉を 16 の角に置くと、真ん中のすきまに入る玉の半径も ちょうど H／2（4 次元だけ：√4 − 1 ＝ 1）
import Foundation
import simd

/// n 次元（3 か 4）の玉の物理：位置・速さ、重力はどの向きでも（gvec。はじめは最後の軸の −）、壁は ±H
final class BallSim {
    let dim: Int
    var p: [SIMD4<Double>] = [], v: [SIMD4<Double>] = [], hue: [Double] = [], rad: [Double] = []   // rad：玉ごとの半径
    var r = 0.18, H = OrigamiState.half, rest = 0.35
    var gvec = SIMD4<Double>(0, 0, 0, -6)                             // 重力（箱の向き。3 次元の時は x・y・z だけ）
    var g: Double { get { simd_length(gvec) } set { let l = simd_length(gvec); gvec = l > 1e-9 ? gvec * (newValue / l) : SIMD4(0, 0, 0, -newValue) } }
    /// 上（重力の逆）：口のある向き。重力が 0 の時は最後の軸の ＋
    var upAxis: (Int, Double) {
        let l = simd_length(gvec); if l < 1e-6 { return (dim - 1, 1) }
        var best = dim - 1, bv = 0.0
        for a in 0..<dim where abs(gvec[a]) > bv { bv = abs(gvec[a]); best = a }
        return (best, gvec[best] < 0 ? 1 : -1)
    }
    init(dim: Int) { self.dim = dim }
    func clear() { p = []; v = []; hue = []; rad = [] }
    /// 口（+ の端）で、玉が入るすきまを探す（何か所か試して、ほかの玉と重ならない所。無ければ nil）
    func findSpawn(_ seed: Int) -> SIMD4<Double>? {
        for t in 0..<40 {
            func rnd(_ k: Int) -> Double { let x = sin(Double(seed * 131 + t * 17 + k) * 12.9898) * 43758.5453; return x - floor(x) }
            var q = SIMD4<Double>(0, 0, 0, 0)
            let (ua, us) = upAxis
            for a in 0..<dim { q[a] = (rnd(a) * 2 - 1) * (H - r) }
            q[ua] = us * (H - r)                                               // 上（重力の逆）の口から
            if p.indices.allSatisfy({ simd_length(p[$0] - q) >= (rad[$0] + r) * 0.98 }) { return q }
        }
        return nil
    }
    /// 上から 1 つ落とす（口の すきまに）。入らなければ false
    @discardableResult func drop(_ seed: Int) -> Bool {
        guard let q = findSpawn(seed) else { return false }
        // 入れる時に、口から中へそっと押し出す（無重力でも口にとどまらず、次の玉が入れるように）
        var v0 = SIMD4<Double>(0, 0, 0, 0); let (ua, us) = upAxis; v0[ua] = -us * 1.2
        p.append(q); v.append(v0); hue.append((Double(seed) * 0.13).truncatingRemainder(dividingBy: 1)); rad.append(r)
        return true
    }
    /// 1 コマ分すすめる（小ステップに分けて）
    func step(_ dt0: Double) {
        let nSub = 6, dt = min(0.05, dt0) / Double(nSub)
        for _ in 0..<nSub {
            for i in p.indices {
                v[i] += gvec * dt
                v[i] *= exp(-0.25 * dt)
                p[i] += v[i] * dt
                let lim = H - rad[i]
                for a in 0..<dim {
                    if p[i][a] < -lim { p[i][a] = -lim; if v[i][a] < 0 { v[i][a] = -v[i][a] * rest } }
                    if p[i][a] > lim { p[i][a] = lim; if v[i][a] > 0 { v[i][a] = -v[i][a] * rest } }
                }
            }
            // 玉どうし：重なりを半分ずつ押しもどし、ぶつかる向きの速さを はね返す
            let n = p.count
            if n > 1 {
                for i in 0..<(n - 1) { for j in (i + 1)..<n {
                    let d = p[j] - p[i], l2 = simd_length_squared(d), rr = rad[i] + rad[j]
                    if l2 >= rr * rr || l2 < 1e-12 { continue }
                    let l = l2.squareRoot(), nv = d / l, ov = rr - l
                    p[i] -= nv * (ov * 0.5); p[j] += nv * (ov * 0.5)
                    let vn = simd_dot(v[j] - v[i], nv)
                    if vn < 0 { let jI = -(1 + rest) * vn * 0.5; v[i] -= nv * jI; v[j] += nv * jI }
                } }
            }
        }
    }
    /// まだ入るか：いちばん上の玉が口（+ の端）から玉 2 つ分より下で、詰まり具合が その次元のふつうの詰まり方（ばらばらに詰めた時：3D 約 64%・4D 約 46%）より少し手前
    /// いっぱい：詰まり具合がその次元の限界の手前、または玉が落ち着いていて、口に玉が入るすきまがもう無い
    func isFull(_ seed: Int) -> Bool {
        if fill >= (dim == 4 ? 0.42 : 0.58) { return true }
        let calm = v.allSatisfy { simd_length($0) < 0.2 }
        return calm && !p.isEmpty && findSpawn(seed) == nil
    }
    /// 詰まり具合（玉の体積の合計 ÷ 箱の体積）
    var fill: Double {
        let vb = pow(2 * H, Double(dim))
        return rad.reduce(0.0) { $0 + (dim == 4 ? Double.pi * Double.pi / 2 * pow($1, 4) : 4 * Double.pi / 3 * pow($1, 3)) } / vb
    }
    /// 角に 2^dim 個 ＋ 真ん中（半径 H／2）
    func cornersAndCenter() {
        clear(); r = H / 2
        for b in 0..<(1 << dim) {
            var q = SIMD4<Double>(0, 0, 0, 0)
            for a in 0..<dim { q[a] = (b >> a) & 1 == 1 ? H / 2 : -H / 2 }
            p.append(q); v.append(.zero); hue.append(0.55); rad.append(r)
        }
        // 真ん中：4 次元ならちょうど半径 H／2（角の玉と同じ）、3 次元なら (√3 − 1)·H／2 ≈ 0.37H しか入らない
        p.append(.zero); v.append(.zero); hue.append(0.08); rad.append(centerR)
    }
    /// 真ん中に入る玉の半径（角の玉が半径 H／2 の時）
    var centerR: Double { (Double(dim).squareRoot() - 1) * H / 2 }
}

extension OrigamiState {
    /// 玉を詰める：1 コマ分（どんどん入れる時は間をあけて 1 つずつ）
    /// 玉の重力：向き（0 画面の奥・1 画面の下・2 箱の −w）と強さ。目標の向きへ なめらかに回す（1 秒に 2.5 ラジアン）
    func ballsGravity(_ dt: Double) {
        func turn(_ cur: SIMD4<Double>, _ tgt: SIMD4<Double>) -> SIMD4<Double> {
            let cl = simd_length(cur), tl = simd_length(tgt); if cl < 1e-9 || tl < 1e-9 { return tgt / max(tl, 1e-9) }
            let a = cur / cl, b = tgt / tl, cs = max(-1, min(1, simd_dot(a, b))), ang = acos(cs), st = 2.5 * dt
            if ang <= st { return b }
            var pp = b - a * cs
            if simd_length(pp) < 1e-6 { for e in [SIMD4<Double>(1, 0, 0, 0), SIMD4<Double>(0, 1, 0, 0), SIMD4<Double>(0, 0, 1, 0)] { let q = e - a * simd_dot(e, a); if simd_length(q) > 0.3 { pp = q; break } } }
            pp /= simd_length(pp)
            return a * cos(st) + pp * sin(st)
        }
        // 4D：箱の −w、または景色の −w（奥）・−y（下）を箱の向きへ
        let t4 = ballGravMode == 2 ? SIMD4<Double>(0, 0, 0, -1) : simd_transpose(m4) * (ballGravMode == 0 ? SIMD4<Double>(0, 0, 0, -1) : SIMD4<Double>(0, -1, 0, 0))
        // 3D（左）：箱の −z、または景色の −z（奥）・−y（下）を、左の写し方の逆で箱の向きへ
        var t3 = SIMD4<Double>(0, 0, -1, 0)
        if ballGravMode != 2 {
            let o = place3([0, 0, 0]).0, cols = (0..<3).map { a -> SIMD3<Double> in var e = [0.0, 0, 0]; e[a] = 0.1; return (place3(e).0 - o) / 0.1 }
            let J = simd_double3x3(cols[0], cols[1], cols[2]), want: SIMD3<Double> = ballGravMode == 0 ? SIMD3(0, 0, -1) : SIMD3(0, -1, 0)
            if abs(J.determinant) > 1e-9 { let d = J.inverse * want; t3 = SIMD4(d.x, d.y, d.z, 0) }
        }
        let g4 = turn(balls4.gvec, t4), g3 = turn(balls3.gvec, t3)
        balls4.gvec = g4 * ballG; balls3.gvec = SIMD4(g3.x, g3.y, g3.z, 0) * ballG
    }
    func ballsTick(_ dt: Double) {
        ballsGravity(dt)
        balls4.r = ballR * Self.half; balls3.r = balls4.r
        if ballsAuto {
            ballsDropT += dt
            // まだ入る箱にだけ入れる。口の近くに玉がいる間は待つ。両方いっぱいになったら終わり
            if ballsDropT >= 0.25 {
                ballsDropT = 0
                // 口に すきまが 1 秒（4 回）続けて見つからなければ、もう入らない＝終わり（玉が小さくゆれ続けていても止まる）
                let room = balls4.findSpawn(ballsSeed + 1) != nil || balls3.findSpawn(ballsSeed + 1) != nil
                ballsNoRoom = room ? 0 : ballsNoRoom + 1
                if (balls4.isFull(ballsSeed) && balls3.isFull(ballsSeed)) || ballsNoRoom >= 4 { ballsAuto = false; ballsNoRoom = 0 } else if room { ballsDropOne() }
            }
        }
        balls4.step(dt); balls3.step(dt)
        ballsRev &+= 1
    }
    /// 1 つ入れる：右（4D）と左（3D）それぞれ、まだ入る時だけ（同じ大きさの玉なら 4 次元の箱のほうがずっとたくさん入るので、別々に）
    func ballsDropOne() { ballsSeed += 1; if !balls4.isFull(ballsSeed) { balls4.drop(ballsSeed) }; if !balls3.isFull(ballsSeed) { balls3.drop(ballsSeed) } }
    func ballsClear() { balls4.clear(); balls3.clear(); ballsAuto = false }
    func ballsCorners() { ballsAuto = false; balls4.cornersAndCenter(); balls3.cornersAndCenter(); ballR = 0.5 }
}

@inline(__always) private func gpuB(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 4 次元の玉（真ん中 c、半径 r）を、今の写し方で 3D に写した「本当の影」：目（景色の w ＝ D の点）からの中心投影なので、影はだ円体。
    ///   目から玉に引いた接する円すいと、景色の w ＝ 0 の面との交わり：X ＝ (x, y, z) について (a·d)² ≥ (|a|² − r²)|d|²、a ＝ c' − 目、d ＝ (X, −D)。
    ///   まとめると (X − X₀)ᵀM(X − X₀) ≤ ρ（M ＝ (|a|² − r²)I − a₃a₃ᵀ）。a₃ の向きの半径は √(ρ／(a_w² − r²))、垂直な 2 本は √(ρ／(|a|² − r²))。
    ///   平行投影の時は、そのまま半径 r の球
    func ball4Shadow(_ c4: SIMD4<Double>, _ r: Double, alpha: Double) -> IntSphere? {
        let cv = st.m4 * c4, D = st.camW, pb = st.projBlend
        if pb > 0.5 {
            let C = SIMD3(cv.x, cv.y, cv.z)
            return Self.ellipsoid(C, [C + SIMD3(r, 0, 0), C + SIMD3(0, r, 0), C + SIMD3(0, 0, r)], spin: 0, alpha: alpha)
        }
        let a = SIMD4<Double>(cv.x, cv.y, cv.z, cv.w - D), a3 = SIMD3(a.x, a.y, a.z), aw = a.w
        let cc = simd_length_squared(a) - r * r, den = aw * aw - r * r
        guard den > 1e-6, cc > 1e-6 else { return nil }
        let b = a3 * (aw * D), X0 = -b / den
        let rho = (aw * aw - cc) * D * D + simd_length_squared(b) / den
        guard rho > 0 else { return nil }
        let l3 = simd_length(a3)
        let u1 = l3 > 1e-9 ? a3 / l3 : SIMD3<Double>(1, 0, 0)
        let hlp: SIMD3<Double> = abs(u1.x) < 0.9 ? SIMD3(1, 0, 0) : SIMD3(0, 1, 0), u2 = simd_normalize(simd_cross(u1, hlp)), u3 = simd_cross(u1, u2)
        let L1 = (rho / den).squareRoot(), L2 = (rho / cc).squareRoot()
        return Self.ellipsoid(X0, [X0 + u1 * L1, X0 + u2 * L2, X0 + u3 * L2], spin: 0, alpha: alpha)
    }
    /// 玉を描く。4D のミニ超球は、w の輪切り（3D の玉）を何枚か重ねて半透明で（積分の超球と同じ見せ方）：
    ///   輪切りは w の高さごとに大きさと写る所が変わるので、ゆがんだ立方体（横の胞）にめりこんで見え、壁には 1 点でしか触れていないのがわかる。
    ///   接点（底・壁・玉どうし）は光る点で。左の 3D の玉は、ふつうの玉と接点
    func ballsGeometry(_ rods: inout [TLRod]) -> [IntTriBatch] {
        guard st.intVis > 0.01, st.intMethod == 2, n <= 4 else { return [] }
        let sim = n == 4 ? st.balls4 : st.balls3, k = st.intVis, H = sim.H
        var sph: [IntSphere] = [], marks: [TLBall] = []
        let pulse = 0.75 + 0.25 * sin(Date().timeIntervalSinceReferenceDate * 4)
        func P(_ q: SIMD4<Double>) -> SIMD3<Double> { n == 4 ? st.place([q.x, q.y, q.z, q.w], 4).0 : st.place([q.x, q.y, q.z], 3).0 }
        for i in sim.p.indices {
            let q = sim.p[i], r = sim.rad[i], hue = Float(1 + sim.hue[i])
            if n == 4 {
                // 本当の影（遠近で写しただ円体）をうすいガラスで：w の手前ほど大きく写るので、輪切りより外にふくらみ、となりのゆがんだ立方体にめりこんで見える
                if var s = ball4Shadow(q, r, alpha: 0.42 * k) { s.m.z = hue; sph.append(s) }
                // 中に w の輪切り：t ＝ −0.6r・0・0.6r の 3 枚（半径 √(r² − t²)）
                for f in [-0.6, 0.0, 0.6] {
                    let t = f * r, R = (r * r - t * t).squareRoot()
                    var c4 = q; c4.w += t
                    let C = P(c4), E = (0..<3).map { a -> SIMD3<Double> in var e = c4; e[a] += R; return P(e) }
                    if var s = exactBallAxes(c4, R, axes: [0, 1, 2], approxC: C, approxE: E, spin: 0, alpha: 0.32 * k) { s.m.z = hue; sph.append(s) }
                }
            } else {
                let C = P(q), E = (0..<3).map { a -> SIMD3<Double> in var e = q; e[a] += r; return P(e) }
                var s = Self.ellipsoid(C, E, spin: 0, alpha: 0.92 * k); s.m.z = hue; sph.append(s)
            }
            // 壁・底との接点：その向きで箱の端まで届いている所（1 点だけ）
            for a in 0..<sim.dim {
                for sg in [-1.0, 1.0] where abs(q[a] + sg * r - sg * H) < 0.012 * H {
                    var c = q; c[a] = sg * H
                    marks.append(TLBall(p: SIMD4(gpuB(P(c)), Float(0.045 * pulse)), col: SIMD4(SIMD3<Float>(1.0, 0.84, 0.3) * Float(k), 2)))
                }
            }
        }
        // 玉どうしの接点（白く小さく）
        let np = sim.p.count
        if np > 1 { for i in 0..<(np - 1) { for j in (i + 1)..<np {
            let d = sim.p[j] - sim.p[i], l = simd_length(d), rr = sim.rad[i] + sim.rad[j]
            if l < 1e-9 || l > rr + 0.012 * H { continue }
            let c = sim.p[i] + d * (sim.rad[i] / l)
            marks.append(TLBall(p: SIMD4(gpuB(P(c)), Float(0.03 * pulse)), col: SIMD4(SIMD3<Float>(0.9, 0.95, 1) * Float(k), 2)))
        } } }
        intSpheres = sph
        intMarks = marks
        return []
    }
}
