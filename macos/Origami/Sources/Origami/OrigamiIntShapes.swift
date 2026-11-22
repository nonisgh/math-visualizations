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
    static func slH(_ w: Double) -> Double { sqrt(max(0, slDuoR * slDuoR - w * w)) }
    /// 輪切りの体積（右・4 次元）／面積（左・3 次元の仲間）。shape：1 球柱・2 デュオ・3 タイガー
    static func slMeasure(_ shape: Int, _ w: Double, left: Bool) -> Double {
        switch shape {
        case 1: return left ? Double.pi * slBallR * slBallR : 4.0 / 3 * Double.pi * pow(slBallR, 3)
        case 4: let q = max(0, 1 - w * w); return left ? Double.pi * q : 4.0 / 3 * Double.pi * pow(q, 1.5)   // 内接する超球（球）：半径 √(1−w²) の玉（円）
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
        // ぺちゃんこ（真横から見た円板）でも解けるように、ほんの少しだけ厚みを残す
        if abs(simd_dot(A[0], simd_cross(A[1], A[2]))) < 1e-3 * L * L * L, L > 0 {
            let k = (0..<3).min { simd_length(A[$0]) < simd_length(A[$1]) } ?? 0, o = (0..<3).filter { $0 != k }
            var nrm = simd_cross(A[o[0]], A[o[1]]); if simd_length(nrm) < 1e-12 { nrm = SIMD3(0, 0, 1) }
            A[k] += simd_normalize(nrm) * 0.02 * L
        }
        func g(_ v: SIMD3<Double>) -> SIMD4<Float> { SIMD4(Float(v.x), Float(-v.z), Float(v.y), 0) }
        return IntSphere(c: SIMD4(gpuS(C), Float(L)), m: SIMD4(Float(spin), Float(min(1, alpha)), 0, 0), ax: g(A[0]), ay: g(A[1]), az: g(A[2]))
    }
    /// 輪切りの形（1 段ぶん）を三角形で：pos＝その段が今いる w（飛んでいる間は着く所の形のまま動く）、ws＝形を決める w、eye＝カメラ
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
                sph.append(Self.ellipsoid(P([0, 0, 0]), [P([R, 0, 0]), P([0, R, 0]), P([0, 0, R])], spin: spin, alpha: a))   // 4D の回転でつぶれる
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
