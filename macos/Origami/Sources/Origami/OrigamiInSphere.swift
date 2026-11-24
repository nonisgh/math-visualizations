// 内接する超球面（回転バーの「内接球」）：超立方体にぴったり内接する超球面（半径 1、8 個の胞の真ん中に接する）を、
//   超球面アプリ（hypersphere.html）と同じ「w ＝ 一定で切った球殻を積んだもの」として、超立方体の中に描く。
//   層：北（w＞0）と南（w＜0）に 6 枚ずつと赤道。層 i の球殻は 半径 sinθ・高さ w ＝ ±cosθ（θ は極からの角度）。
//   色も超球面アプリと同じ（北 紫 → 水色、南 赤 → 緑、赤道に向かって）。半透明の殻と、うすい網目。
//   点ごとに超立方体と同じ 4 次元の回転と遠近で写す＝超立方体と一緒に回る（4D で回すと殻がゆがみ、裏返る）。
//   立方体の窓には、内接する球を緯度の輪（z ＝ 一定の円）で。積分の「超球（内接）」（レインボーボール）とは別のもの
import Foundation
import simd
import QuartzCore

@inline(__always) private func gpuH(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 超球面アプリの層の色（redCenter でない時）：北 h＝0.80 − 0.40t、南 h＝0.40t（t＝0 極 〜 1 赤道）
    static func layerCol(_ i: Int, _ n: Int, south: Bool) -> SIMD3<Float> {
        let t = Double(i) / Double(max(1, n - 1))
        return OrigamiState.hsl(south ? 0.40 * t : 0.80 - 0.40 * t, 0.95, 0.52)
    }
    /// 「アプリの色」：超球面の上の点 u（単位）の色＝いちばん近い胞（立方体では面）の色を、近さでなめらかにまぜる。
    ///   内接球は 8 個の胞の真ん中に接するので、接する所はその胞の色・胞と胞のあいだは両方の色のまざり。少し明るくして見やすく
    static let cellNormals: [[(Int, Double)]] = [3, 4, 5].map { n in OrigamiState.cells(n).map { OrigamiState.fixed($0, n) } }   // 胞（面）の向きの表（1 回だけ作る）
    func inSphereCellColor4(_ u: SIMD4<Double>, _ cols: [SIMD3<Float>]) -> SIMD3<Float> {
        var c = SIMD3<Float>(0, 0, 0), ws: Float = 0
        let nr = Self.cellNormals[1]
        for i in 0..<min(cols.count, nr.count) {
            let d = max(0, u[nr[i].0] * nr[i].1), d2 = d * d, w = Float(d2 * d2 * d2)
            c += cols[i] * w; ws += w
        }
        return Self.vivid(ws > 1e-9 ? c / ws : SIMD3<Float>(repeating: 0.7))
    }
    /// あざやかに（灰色から遠ざけて、少し明るく）：まざった色がにごったり白っぽくつぶれたりしないように
    static func vivid(_ c: SIMD3<Float>) -> SIMD3<Float> {
        let g = (c.x + c.y + c.z) / 3
        return simd_clamp((SIMD3(repeating: g) + (c - SIMD3(repeating: g)) * 1.45) * 1.12, .zero, SIMD3(repeating: 1))
    }
    func inSphereCellColor(_ u: [Double], _ cols: [SIMD3<Float>], _ n: Int) -> SIMD3<Float> {
        var c = SIMD3<Float>(0, 0, 0), ws: Float = 0
        let nr = Self.cellNormals[n == 3 ? 0 : 1]
        for (i, col) in cols.enumerated() where i < nr.count {
            let (a, sg) = nr[i]
            let d = max(0, u[a] * sg), d2 = d * d
            let w = Float(d2 * d2 * d2)
            c += col * w; ws += w
        }
        return Self.vivid(ws > 1e-9 ? c / ws : SIMD3<Float>(repeating: 0.7))
    }
    /// 正 120 胞体（半径 1）の辺：点 600・辺 1200（どの点からも 4 本）。ふつうの座標（半径 √8 の表を 1/√8 倍）。
    ///   この向きでは x・y・z・w の軸の向き（内接球の 8 つの接点）が、ちょうど正十二面体の部屋の真ん中（まわりの 20 個の点が同じ近さ）
    static let cell120Edges: [(SIMD4<Double>, SIMD4<Double>)] = {
        let p = (1 + 5.0.squareRoot()) / 2, ip = 1 / p, s5 = 5.0.squareRoot()
        var V: [SIMD4<Double>] = [], seen = Set<SIMD4<Int64>>()
        func add(_ v: [Double]) {
            let k = SIMD4<Int64>(Int64((v[0] * 1e6).rounded()), Int64((v[1] * 1e6).rounded()), Int64((v[2] * 1e6).rounded()), Int64((v[3] * 1e6).rounded()))
            if seen.insert(k).inserted { V.append(SIMD4(v[0], v[1], v[2], v[3]) / 8.0.squareRoot()) }
        }
        func perms(_ a: [Double]) -> [[Double]] {
            var r: [[Double]] = []
            func go(_ c: [Double], _ rest: [Double]) { if rest.isEmpty { r.append(c); return }; for i in rest.indices { var rr = rest; let x = rr.remove(at: i); go(c + [x], rr) } }
            go([], a); return r
        }
        let even = [[0, 1, 2, 3], [0, 2, 3, 1], [0, 3, 1, 2], [1, 0, 3, 2], [1, 2, 0, 3], [1, 3, 2, 0], [2, 0, 1, 3], [2, 1, 3, 0], [2, 3, 0, 1], [3, 0, 2, 1], [3, 1, 0, 2], [3, 2, 1, 0]]
        func signs(_ v: [Double]) -> [[Double]] { var r: [[Double]] = [[]]; for x in v { r = r.flatMap { c in x == 0 ? [c + [0]] : [c + [x], c + [-x]] } }; return r }
        for b in [[0, 0, 2, 2], [1, 1, 1, s5], [ip * ip, p, p, p], [ip, ip, ip, p * p]] { for pm in perms(b) { for sv in signs(pm) { add(sv) } } }
        for b in [[0, ip * ip, 1, p * p], [0, ip, p, s5], [ip, 1, p, 2]] { for sv in signs(b) { for e in even { add(e.map { sv[$0] }) } } }
        let el = 0.2700907567377264
        var E: [(SIMD4<Double>, SIMD4<Double>)] = []
        for i in 0..<V.count { for j in (i + 1)..<V.count where abs(simd_distance(V[i], V[j]) - el) < 1e-6 { E.append((V[i], V[j])) } }
        return E
    }()
    /// 球面の正十二面体（半径 1）の辺：点 20・辺 30。立方体の窓用（正 120 胞体の部屋の形。x・y・z の軸の向きは辺の真ん中）
    static let dodecaEdges: [(SIMD3<Double>, SIMD3<Double>)] = {
        let p = (1 + 5.0.squareRoot()) / 2, ip = 1 / p
        var V: [SIMD3<Double>] = []
        for x in [-1.0, 1] { for y in [-1.0, 1] { for z in [-1.0, 1] { V.append([x, y, z]) } } }
        for s in [-1.0, 1] { for t in [-1.0, 1] { V.append([0, s * ip, t * p]); V.append([s * ip, t * p, 0]); V.append([s * p, 0, t * ip]) } }
        V = V.map { simd_normalize($0) }
        var md = 9.0; for i in 0..<V.count { for j in (i + 1)..<V.count { md = min(md, simd_distance(V[i], V[j])) } }
        var E: [(SIMD3<Double>, SIMD3<Double>)] = []
        for i in 0..<V.count { for j in (i + 1)..<V.count where simd_distance(V[i], V[j]) < md + 1e-6 { E.append((V[i], V[j])) } }
        return E
    }()
    /// 正 120 胞体のワイヤーの色の元：「接点の色」と同じ（軸の色 x 赤・y 緑・z 青・w 紫／胞の色）。いちばん近い接点の色に寄せる
    func wireCols(_ n: Int) -> [SIMD3<Float>] {
        if st.inSphereTouchCol == 1 { return st.cellColors(n).map { OrigamiState.rgb($0) } }
        return Self.cellNormals[n - 3].map { c in OrigamiState.rgb(c.0 >= 4 ? 0xf59e0b : OrigamiState.ptAxisCol[n == 3 && c.0 == 2 ? 3 : c.0]) }   // v は琥珀
    }
    /// 内接球の遠近（inSphereDepth）：球の真ん中より手前の膜と線は明るく・線は太く、奥はうすく・細く。
    ///   内接球が足した線（rods の r0 から先）と膜（batches）に、目からの遠さで掛ける（球の半径くらいの幅で、手前 −1 〜 奥 ＋1）
    func inSphereDepthFx(_ rods: inout [TLRod], from r0: Int, _ batches: [IntTriBatch], eye: SIMD3<Double>) -> [IntTriBatch] {
        let D = Float(st.inSphereDepth)
        guard D > 0.001 else { return batches }
        let eg = gpuH(eye), cg = gpuH(st.place([Double](repeating: 0, count: n), n).0), c0 = simd_distance(cg, eg), R = Float(OrigamiState.half) * 1.1
        /// （明るさ、太さ）の倍率
        func f(_ p: SIMD3<Float>) -> (Float, Float) {
            let back = (max(-1, min(1, (simd_distance(p, eg) - c0) / R)) + 1) / 2   // 0 いちばん手前 〜 1 いちばん奥
            return (1 + 0.25 * D * (1 - back) - 0.6 * D * back, 1 + 0.7 * D * (1 - back) - 0.4 * D * back)
        }
        if r0 < rods.count {
            for i in r0..<rods.count {
                let m = (SIMD3(rods[i].a.x, rods[i].a.y, rods[i].a.z) + SIMD3(rods[i].b.x, rods[i].b.y, rods[i].b.z)) * 0.5, (b, w) = f(m)
                rods[i].col = SIMD4(SIMD3(rods[i].col.x, rods[i].col.y, rods[i].col.z) * b, rods[i].col.w)
                rods[i].b.w = (rods[i].b.w > 0 ? rods[i].b.w : 1) * w
            }
        }
        var out = batches
        for bi in out.indices { for vi in out[bi].verts.indices { let v = out[bi].verts[vi]; out[bi].verts[vi].c = v.c * f(SIMD3(v.p.x, v.p.y, v.p.z)).0 } }
        return out
    }
    func inSphereGeometry(_ rods: inout [TLRod], eye: SIMD3<Double>) -> [IntTriBatch] {
        guard st.inSphere else { return [] }
        let k = max(0, min(1, (st.progress - 0.92) / 0.08)) * max(0, 1 - 4 * st.explodeE)   // 組み上がっている時だけ
        guard k > 0.01 else { return [] }
        let H = OrigamiState.half, NL = max(3, st.inSphereLayers), MIN = 0.06
        let appCol = st.inSphereColor == 0, cols = st.cellColors(n).map { OrigamiState.rgb($0) }
        let L = 2 * NL - 1, thin = Float(pow(11.0 / Double(L), 0.75))     // 層が多いほど 1 枚ずつはうすく（重ねた濃さは前と同じくらい）
        // 写し方（超立方体と同じ 4D の回転と遠近）。たくさん写すので、配列を作らずに SIMD で
        let M4 = st.m4, Dc = st.camW, pb = st.projBlend
        func P4(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> SIMD3<Double> {
            let v = M4 * SIMD4(x * H, y * H, z * H, w * H)
            let ww = max(-Dc + 0.5, min(Dc - 0.5, v.w)), kk = 1 + (1 / (1 - ww / Dc) - 1) * (1 - pb)
            return SIMD3(v.x * kk, v.y * kk, v.z * kk)
        }
        // 模様の回転（内接球の回転モード）：模様の点 → 超立方体（立方体）の座標。球はまんまるなので、形はそのまま模様だけが動く
        //   回し方の決まりは 1 コマに 1 回だけ作る（点ごとに設定を読むと重い）
        let rule = st.sphereSpinRule(n: n)
        func spun(_ u: SIMD4<Double>) -> SIMD4<Double> { rule?.apply(u) ?? u }
        func spin3(_ u: [Double]) -> [Double] { guard let rule else { return u }; let v = rule.apply(SIMD4(u[0], u[1], u[2], 0)); return [v.x, v.y, v.z] }
        func P(_ u: [Double]) -> SIMD3<Double> {
            if n == 4 { let v = spun(SIMD4(u[0], u[1], u[2], u[3])); return P4(v.x, v.y, v.z, v.w) }
            return st.place(spin3(u).map { $0 * H }, n).0
        }
        // めりこみ：写した絵では、超球が「奥の胞」（4D の目からいちばん遠い胞。W 消失なら内側の小さな立方体）にめりこんで見える。
        //   その胞を写した 6 面の立体（遠近で写しても面は平ら）の中にある所を、少し暗く。奥の胞が 4D の目の真後ろにある時ほど強く
        var dentPl: [(n: SIMD3<Double>, d: Double)] = [], dentK = 0.0
        if n == 4 && st.inSphereDent {
            var best = 0, bw = 2.0
            for (ci, c) in Self.cellNormals[1].enumerated() { let w = M4[c.0][3] * c.1; if w < bw { bw = w; best = ci } }
            dentK = max(0, min(1, (-bw - 0.7) / 0.25))
            if dentK > 0.01 {
                let (ax0, sg) = Self.cellNormals[1][best], others = (0..<4).filter { $0 != ax0 }
                func corner(_ v: [Double]) -> SIMD3<Double> { var u = [0.0, 0, 0, 0]; u[ax0] = sg; for (k2, o) in others.enumerated() { u[o] = v[k2] }; return P4(u[0], u[1], u[2], u[3]) }
                let cen = corner([0, 0, 0])
                for f in 0..<3 { for fs in [-1.0, 1.0] {
                    var q: [SIMD3<Double>] = []
                    for (a2, b2) in [(-1.0, -1.0), (1, -1), (-1, 1)] { var v = [0.0, 0, 0]; v[f] = fs; let rest = (0..<3).filter { $0 != f }; v[rest[0]] = a2; v[rest[1]] = b2; q.append(corner(v)) }
                    var nn = simd_cross(q[1] - q[0], q[2] - q[0]); let l = simd_length(nn); if l < 1e-12 { continue }; nn /= l
                    if simd_dot(nn, cen - q[0]) < 0 { nn = -nn }                 // 内向き
                    dentPl.append((nn, simd_dot(nn, q[0])))
                } }
            }
        }
        /// 色に掛ける数（めりこんで見える所は 1 より小さく）
        func dent(_ p: SIMD3<Double>) -> Float {
            guard dentPl.count == 6 else { return 1 }
            var m = Double.infinity; for pl in dentPl { m = min(m, simd_dot(pl.n, p) - pl.d) }
            let ins = max(0, min(1, (m + 0.006) / 0.03))
            return Float(1 - 0.55 * ins * dentK)
        }
        // くっきり：膜は画素ごとに（シェーダーで奥の胞の 6 つの壁と比べる）、線は壁のところで切って、中の部分だけ暗く
        let sharp = st.inSphereDentSharp && dentPl.count == 6, dk = Float(1 - 0.55 * dentK)
        // 線の太さ：内接球のワイヤーの太さ（見え方の「線の太さ」で全部の線が太くなる分は打ち消す）。wm：その線だけの倍率（正 120 胞体は 1.6）
        let bw0 = Float(st.inSphereWireW / max(0.3, st.lineWidthNow))
        func rod(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Float>, _ L: Double, wm: Float = 1) {
            let wd = Float(L * k / 1.4), bw = bw0 * wm
            func put(_ p: SIMD3<Double>, _ q: SIMD3<Double>, _ m: Float) { rods.append(TLRod(a: SIMD4(gpuH(p), 0), b: SIMD4(gpuH(q), bw), col: SIMD4(c * m, wd))) }
            guard sharp else { put(a, b, dent((a + b) * 0.5)); return }
            // 線分が奥の胞（6 つの壁の内側＝凸）の中にある区間 [t0, t1] を、壁ごとに切りつめて求める
            var t0 = 0.0, t1 = 1.0
            for pl in dentPl {
                let fa = simd_dot(pl.n, a) - pl.d, fb = simd_dot(pl.n, b) - pl.d
                if fa < 0 && fb < 0 { t0 = 1; t1 = 0; break }
                if fa < 0 { t0 = max(t0, fa / (fa - fb)) } else if fb < 0 { t1 = min(t1, fa / (fa - fb)) }
            }
            guard t0 < t1 else { put(a, b, 1); return }
            let pa = a + (b - a) * t0, pb = a + (b - a) * t1
            if t0 > 1e-6 { put(a, pa, 1) }
            put(pa, pb, dk)
            if t1 < 1 - 1e-6 { put(pb, b, 1) }
        }
        // 出現（inSphereAppear 0〜1）：s（0〜1）の所は、時計が s あたりに来た時に現れる（幅 span でなめらかに）
        let ap = st.inSphereAppear
        func appearAt(_ s: Double, _ span: Double = 0.3) -> Float {
            guard ap < 0.999 else { return 1 }
            let c = max(0, min(1, (ap - max(0, min(1, s)) * (1 - span)) / span)); return Float(c * c * (3 - 2 * c))
        }
        /// r0 から先に足した線を、現れかけの v の分だけ細く（線は上からぬるので、暗くすると黒い筋になる。細い線は自然にうすく見える）
        func fadeRods(_ r0: Int, _ v: Float) {
            guard v < 0.999, r0 < rods.count else { return }
            for i in r0..<rods.count { rods[i].b.w = (rods[i].b.w > 0 ? rods[i].b.w : 1) * v }
        }
        // 層（北・南。赤道は 1 枚）
        var layers: [(th: Double, south: Bool, i: Int)] = []
        for i in 0..<NL { let th = MIN + Double(i) / Double(NL - 1) * (Double.pi / 2 - MIN); layers.append((th, false, i)); if i < NL - 1 { layers.append((th, true, i)) } }
        if n == 3 {
            // 立方体の窓：内接する球の緯度の輪（z ＝ ±cosθ、半径 sinθ）。アプリの色なら、輪の上の点ごとに近い面の色
            for Ly in st.inSphereLat ? layers : [] {                            // 緯度の輪（模様で切ると出さない）
                let zL = (Ly.south ? -1 : 1) * cos(Ly.th), vL = appearAt((zL + 1) / 2)   // 出現：z の −1 から ＋1 へ積み上がる
                if vL < 0.005 { continue }
                let r0L = rods.count; defer { fadeRods(r0L, vL) }
                let r = sin(Ly.th) * (0.35 + 0.65 * Double(vL)), z = zL, S = 64
                for s in 0..<S {
                    let a0 = 2 * Double.pi * Double(s) / Double(S), a1 = 2 * Double.pi * Double(s + 1) / Double(S), am = (a0 + a1) / 2
                    let col = appCol ? inSphereCellColor(spin3([r * cos(am), r * sin(am), z]), cols, 3) : Self.layerCol(Ly.i, NL, south: Ly.south)
                    rod(P([r * cos(a0), r * sin(a0), z]), P([r * cos(a1), r * sin(a1), z]), col, 0.9 * Double(thin.squareRoot()))
                }
            }
            // 円錐：y の軸からの角度 θ が一定の輪（θ ＝ 30°〜150° の 5 本）
            if st.inSphereCone {
                for (kk, thd) in [30.0, 60, 90, 120, 150].enumerated() {
                    let vC = appearAt(Double(kk) / 5); if vC < 0.005 { continue }   // 出現：花のように順に
                    let r0C = rods.count; defer { fadeRods(r0C, vC) }
                    let th = thd * .pi / 180, S = 48
                    let colR = OrigamiState.hsl(0.05 + 0.75 * Double(kk) / 4, 0.85, 0.62)
                    for s in 0..<S {
                        let a0 = 2 * Double.pi * Double(s) / Double(S), a1 = 2 * Double.pi * Double(s + 1) / Double(S)
                        let col = appCol ? inSphereCellColor(spin3([sin(th) * cos(a0), cos(th), sin(th) * sin(a0)]), cols, 3) : colR
                        rod(P([sin(th) * cos(a0), cos(th), sin(th) * sin(a0)]), P([sin(th) * cos(a1), cos(th), sin(th) * sin(a1)]), col, st.inSphereLat ? 0.6 : 1.0)
                    }
                }
            }
            // 経度：極を通る大円の半分（経線）を 8 本
            if st.inSphereLon {
                for kk in 0..<8 {
                    let vO = appearAt(Double(kk) / 8); if vO < 0.005 { continue }    // 出現：扇のように 1 本ずつ
                    let r0O = rods.count; defer { fadeRods(r0O, vO) }
                    let ph = 2 * Double.pi * Double(kk) / 8, S = 40
                    let col = appCol ? inSphereCellColor(spin3([cos(ph), sin(ph), 0]), cols, 3) : OrigamiState.hsl(0.8 * Double(kk) / 8, 0.9, 0.6)
                    for s in 0..<S {
                        let a0 = Double.pi * Double(s) / Double(S), a1 = Double.pi * Double(s + 1) / Double(S)
                        rod(P([sin(a0) * cos(ph), sin(a0) * sin(ph), cos(a0)]), P([sin(a1) * cos(ph), sin(a1) * sin(ph), cos(a1)]), col, st.inSphereLat ? 0.6 : 1.0)
                    }
                }
            }
            // 正 120 胞体の部屋の形＝球面の正十二面体（辺を 4 つに分けて球に沿わせる）。少し太いワイヤー
            if st.inSphere120 {
                let wc = wireCols(3)
                for (A, B) in Self.dodecaEdges {
                    var a = A
                    for s in 1...4 {
                        let b = simd_normalize(A + (B - A) * (Double(s) / 4)), m = simd_normalize(a + b)
                        // 出現：6 つの接点（面の真ん中）から結晶が育つ。接点からの角度（いちばん遠い角の向きで 54.7°）の近い所から
                        let sm = spin3([m.x, m.y, m.z]), vG = appearAt((acos(min(1, sm.map { abs($0) }.max()!)) - 0.36) / (acos(1 / 3.0.squareRoot()) - 0.36), 0.22)
                        if vG < 0.04 { a = b; continue }
                        var col = appCol ? inSphereCellColor(sm, wc, 3) : OrigamiState.hsl(0.8 * (m.y + 1) / 2, 0.9, 0.6)
                        col *= 1 + 1.3 * 4 * vG * (1 - vG)                           // 育っている先は少し明るく（うすさは細さで）
                        rod(P([a.x, a.y, a.z]), P([b.x, b.y, b.z]), col, 2.0, wm: 1.6 * vG); a = b
                    }
                }
            }
            return []
        }
        // 超立方体の窓：球殻（w ＝ ±cosθ、半径 sinθ）を、遠い層から順に（重ねる順）
        let order = layers.sorted { simd_distance(P([0, 0, 0, ($0.south ? -1 : 1) * cos($0.th)]), eye) > simd_distance(P([0, 0, 0, ($1.south ? -1 : 1) * cos($1.th)]), eye) }
        var tris: [IntVert] = []
        /// t0・r0 から先に足した膜と線に、現れかけの v を掛ける
        func fadeRange(_ t0: Int, _ r0: Int, _ v: Float) {
            fadeRods(r0, v)
            guard v < 0.999, t0 < tris.count else { return }
            for i in t0..<tris.count { tris[i].c *= v }
        }
        let RG = 14, SG = 28
        tris.reserveCapacity((st.inSphereLat ? layers.count : 0) * RG * SG * 6 + (st.inSphereLon ? 8 * 16 * 16 * 6 : 0) + (st.inSphereCone ? 5 * 16 * 32 * 6 : 0))
        // 座標の面（超球面の角度 (χ, θ, φ)：(sinχ sinθ cosφ, sinχ cosθ, sinχ sinθ sinφ, cosχ)）。どれもうすいガラスの膜と少しの線で。
        //   経度面：φ 一定＝大きな球（大円の球）の半分。y と w の大円を軸に、φ ＝ 0°, 45°, … の 8 枚（χ・θ ∈ [0, π]）
        //   円錐の面：θ 一定＝真ん中から見ると y の軸のまわりの円錐。超球面の上では両はしが閉じたまゆ玉の形（θ＝90° だけ平らな大きな球）。
        //     θ ＝ 30°・60°・90°・120°・150° の 5 枚（χ ∈ [0, π]・φ ∈ [0, 2π]）
        // 緯度の球殻を切って経度・円錐だけの時は、膜と線を濃く（球殻に重ねる時のうすさのままだと、ほとんど見えない）
        let solo = st.inSphereLat ? 1.0 : 2.4, soloL = st.inSphereLat ? 1.0 : 1.7
        let Ld = simd_normalize(SIMD3<Double>(-0.45, 0.6, 0.65)), alm = Float(0.07 * k * solo), glassOn = st.inSphereGlass
        /// 膜を 1 枚：NA × NB の網、u(a, b) で超球面の点、rc はレインボーの時の色。lineB：この列に線（a の方向）、lineA：この行に線（b の方向）
        /// 膜 1 枚の材料：NA × NB の網、u(a, b) で超球面の点、rc はレインボーの時の色。lineB：この列に線（a の方向）、lineA：この行に線（b の方向）
        struct SheetSpec { var NA: Int; var NB: Int; var uf: (Int, Int) -> SIMD4<Double>; var rc: SIMD3<Float>; var lineA: [Int]; var lineB: [Int]; var vis: Float }
        struct SheetOut { var tris: [IntVert]; var Gm: [[SIMD3<Double>]]; var MC: [[SIMD3<Float>]] }
        /// 膜 1 枚を作る（共有のものにさわらない＝いくつもの CPU で同時に作れる）
        func sheetBuild(_ sp: SheetSpec) -> SheetOut {
            let NA = sp.NA, NB = sp.NB
            var Gm: [[SIMD3<Double>]] = [], MC: [[SIMD3<Float>]] = []
            Gm.reserveCapacity(NA + 1); MC.reserveCapacity(NA + 1)
            for a in 0...NA {
                var row: [SIMD3<Double>] = [], crow: [SIMD3<Float>] = []
                row.reserveCapacity(NB + 1); crow.reserveCapacity(NB + 1)
                for b in 0...NB { let u = spun(sp.uf(a, b)), q = P4(u.x, u.y, u.z, u.w); row.append(q); crow.append((appCol ? inSphereCellColor4(u, cols) : sp.rc) * dent(q)) }
                Gm.append(row); MC.append(crow)
            }
            var out: [IntVert] = []; out.reserveCapacity(NA * NB * 6)
            for a in 0..<NA { for b in 0..<NB {
                let q0 = Gm[a][b], q1 = Gm[a + 1][b], q2 = Gm[a + 1][b + 1], q3 = Gm[a][b + 1]
                let nn = simd_cross(q1 - q0, q3 - q0), nl = simd_length(nn), mid = (q0 + q1 + q2 + q3) * 0.25, vd = simd_normalize(eye - mid)
                let fq = nl > 1e-12 ? abs(simd_dot(nn / nl, vd)) : 1
                let g = 1 - fq, fres = g * g * g, aq = min(0.4, alm * Float(0.6 + 2.0 * fres))
                var addv = fres * 0.05 * k
                if glassOn, nl > 1e-12 {
                    var sn = nn / nl; if simd_dot(sn, vd) < 0 { sn = -sn }
                    let rf = 2 * simd_dot(sn, vd) * sn - vd, d = max(0, simd_dot(rf, Ld))
                    var sp = d * d; sp = sp * sp; sp = sp * sp; sp = sp * sp; sp = sp * sp      // d^32（軽い計算で、つや）
                    addv += sp * 0.5 * k
                }
                let addc = SIMD3<Float>(repeating: Float(addv) * aq * 2), ka = Float(0.85 + 0.9 * fres) * aq      // 膜の色はしっかり、ふちほど濃く
                let w0 = IntVert(p: SIMD4(gpuH(q0), 1), c: SIMD4(MC[a][b] * ka + addc, aq)), w1 = IntVert(p: SIMD4(gpuH(q1), 1), c: SIMD4(MC[a + 1][b] * ka + addc, aq))
                let w2 = IntVert(p: SIMD4(gpuH(q2), 1), c: SIMD4(MC[a + 1][b + 1] * ka + addc, aq)), w3 = IntVert(p: SIMD4(gpuH(q3), 1), c: SIMD4(MC[a][b + 1] * ka + addc, aq))
                out.append(w0); out.append(w1); out.append(w2); out.append(w0); out.append(w2); out.append(w3)
            } }
            return SheetOut(tris: out, Gm: Gm, MC: MC)
        }
        /// 作った膜を並べる（三角形と線。線は rod でめりこみの切り分けをするので順番に）
        func sheetEmit(_ sp: SheetSpec, _ so: SheetOut) {
            let t0S = tris.count, r0S = rods.count; defer { fadeRange(t0S, r0S, sp.vis) }
            tris += so.tris
            let Gm = so.Gm, MC = so.MC
            func lc(_ x: Int, _ y: Int) -> SIMD3<Float> { simd_mix(MC[x][y], SIMD3<Float>(repeating: 1), SIMD3<Float>(repeating: 0.3)) * 1.1 }
            for b in sp.lineB { for a in 0..<sp.NA { rod(Gm[a][b], Gm[a + 1][b], lc(a, b), 0.4 * soloL) } }
            for a in sp.lineA { for b in 0..<sp.NB { rod(Gm[a][b], Gm[a][b + 1], lc(a, b), 0.3 * soloL) } }
        }
        var tq0 = CACurrentMediaTime()
        func lap(_ nm: String) { if PerfTest.on { let t = CACurrentMediaTime(); PerfTest.add("　内接球・" + nm, t - tq0); tq0 = t } }
        lap("はじめ")
        // 経度（扇のように 1 枚ずつ）と円錐（花のように順に）の膜を、いっぺんにいくつもの CPU で作って、順に並べる
        var specs: [SheetSpec] = []
        if st.inSphereLon {
            let K = 8, NG = 16
            for kk in 0..<K {
                let vS = appearAt(Double(kk) / Double(K)); if vS < 0.005 { continue }
                let ph = 2 * Double.pi * Double(kk) / Double(K), cph = cos(ph), sph = sin(ph)
                specs.append(SheetSpec(NA: NG, NB: NG, uf: { a, b in
                    let chi = Double.pi * Double(a) / Double(NG), th = Double.pi * Double(b) / Double(NG), sc = sin(chi)
                    return SIMD4(sc * sin(th) * cph, sc * cos(th), sc * sin(th) * sph, cos(chi))
                }, rc: OrigamiState.hsl(0.8 * Double(kk) / Double(K), 0.9, 0.6), lineA: [NG / 4, NG / 2, 3 * NG / 4], lineB: [NG / 2], vis: vS))
            }
        }
        if st.inSphereCone {
            let ths = [30.0, 60, 90, 120, 150].map { $0 * .pi / 180 }, NA = 16, NB = 32
            for (kk, th) in ths.enumerated() {
                let vS = appearAt(Double(kk) / Double(ths.count)); if vS < 0.005 { continue }
                let st0 = sin(th), ct0 = cos(th)
                specs.append(SheetSpec(NA: NA, NB: NB, uf: { a, b in
                    let chi = Double.pi * Double(a) / Double(NA), ph = 2 * Double.pi * Double(b) / Double(NB), sc = sin(chi)
                    return SIMD4(sc * st0 * cos(ph), sc * ct0, sc * st0 * sin(ph), cos(chi))
                }, rc: OrigamiState.hsl(0.05 + 0.75 * Double(kk) / Double(ths.count - 1), 0.85, 0.62), lineA: [NA / 2], lineB: [0, NB / 4, NB / 2, 3 * NB / 4], vis: vS))
            }
        }
        if !specs.isEmpty {
            var outs = [SheetOut?](repeating: nil, count: specs.count)
            outs.withUnsafeMutableBufferPointer { ob in DispatchQueue.concurrentPerform(iterations: specs.count) { i in ob[i] = sheetBuild(specs[i]) } }
            for (i, sp) in specs.enumerated() { if let so = outs[i] { sheetEmit(sp, so) } }
        }
        lap("経度と円錐")
        // 緯度の球殻（模様で切ると出さない）。点ごとの重い計算（回転・遠近・色・めりこみ・ガラスの光）は、殻ごとに
        //   いくつもの CPU で同時に（前は 1 つの CPU で順番に、殻 19 枚で 1 コマ 1.2 ミリ秒かかり、144 コマが落ちていた）。
        //   三角形と網目の線を並べるのは、重ねる順を守って、あとで順番に
        struct ShellPre { var G: [[SIMD3<Double>]]; var VC: [[SIMD3<Float>]]; var back: [IntVert]; var front: [IntVert]; var vL: Float; var i: Int }
        let shellsL = st.inSphereLat ? order : []
        var pre = [ShellPre?](repeating: nil, count: shellsL.count)
        let al = Float(0.13 * k) * thin * (appCol ? 1.3 : 1), rimK = appCol ? 0.35 : 0.55
        let LdS = simd_normalize(SIMD3<Double>(-0.45, 0.6, 0.65)), glassS = st.inSphereGlass, filmS = st.inSphereFilm, toneS = Float(st.inSphereTone)
        /// 面の向き n・目への向き vd での、光の跳ね返る向き（表の側で）
        func rf0(_ n: SIMD3<Double>, _ vd: SIMD3<Double>) -> SIMD3<Double> { let sn = simd_dot(n, vd) >= 0 ? n : -n; return 2 * simd_dot(sn, vd) * sn - vd }
        func shellPre(_ Ly: (th: Double, south: Bool, i: Int)) -> ShellPre? {
            // 出現：w の −1 から ＋1 へ、殻が 1 枚ずつふくらみながら積み上がる（4 次元の球が 3 次元を通りぬけるパラパラ漫画）
            let wL = (Ly.south ? -1 : 1) * cos(Ly.th), vL = appearAt((wL + 1) / 2)
            if vL < 0.005 { return nil }
            let r = sin(Ly.th) * (0.35 + 0.65 * Double(vL)), w = wL, lcol = Self.layerCol(Ly.i, NL, south: Ly.south)
            var G: [[SIMD3<Double>]] = [], VC: [[SIMD3<Float>]] = []
            G.reserveCapacity(RG + 1); VC.reserveCapacity(RG + 1)
            for i in 0...RG {
                let th = Double.pi * Double(i) / Double(RG), st0 = sin(th), ct0 = cos(th)
                var row: [SIMD3<Double>] = [], crow: [SIMD3<Float>] = []
                row.reserveCapacity(SG + 1); crow.reserveCapacity(SG + 1)
                for j in 0...SG {
                    let ph = 2 * Double.pi * Double(j) / Double(SG)
                    let u = spun(SIMD4<Double>(r * st0 * cos(ph), r * ct0, r * st0 * sin(ph), w)), q = P4(u.x, u.y, u.z, u.w)
                    row.append(q)
                    // 点の色（アプリの色なら近い胞の色）× めりこみ（くっきりの時は画素ごとに）
                    crow.append((appCol ? inSphereCellColor4(u, cols) : lcol) * (dentPl.isEmpty || sharp ? 1 : dent(q)))
                }
                G.append(row); VC.append(crow)
            }
            let C = P([0, 0, 0, w])
            // 頂点ごとの色と濃さ（4 つの面で分け合うので、1 回だけ計算）。水晶玉（ガラス）：いちばん外の殻（赤道の大きな殻）だけが細いふちで
            //   キラッと反射し、内側の殻はうんとうすく（中に浮かぶ模様）。まんなかはすきとおって、光の当たる所に小さく強いハイライト、
            //   反対側の奥に光の集まったぽわっとした明るみ。累乗はかけ算のくり返しで（pow は重い）
            let r2 = r * r, r4 = r2 * r2, outer = r4 * r4
            var VV = [[IntVert]](); VV.reserveCapacity(RG + 1)
            for a in 0...RG {
                var row: [IntVert] = []; row.reserveCapacity(SG + 1)
                for b in 0...SG {
                    let pv = G[a][b], nv = simd_length(pv - C) > 1e-9 ? simd_normalize(pv - C) : SIMD3(0, 0, 1), vd = simd_normalize(eye - pv)
                    let fv = simd_dot(nv, vd), af = abs(fv), vc = VC[a][b]
                    if filmS {
                        // 油膜（シャボン玉）：殻は色（胞の色）をのせたまま少し暗く、うしろを少し沈めて透かす（内側の殻ほどうすい）。
                        //   ふちほど、膜の厚みのむら（殻の上の位置でゆっくり変わる）と見る角度で虹色がゆらぐ（薄膜の干渉）
                        let th = Double.pi * Double(a) / Double(RG), ph = 2 * Double.pi * Double(b) / Double(SG), li = Double(Ly.i)
                        let m1 = 1 - af, fres = m1 * m1
                        let thick = 0.5 + 0.25 * sin(3 * th + 2 * ph + li * 0.7) + 0.25 * sin(5 * ph - 2 * th + li)
                        let hue = (thick * (1.4 + 0.8 * af) * 1.7 + 10).truncatingRemainder(dividingBy: 1)
                        let irid = OrigamiState.hsl(hue, 0.9, 0.58)
                        let ow = 0.25 + 0.75 * outer                                  // 外の殻ほど膜がはっきり
                        let aq = min(0.45, al * 0.75 * Float(0.35 + 1.5 * fres * ow))
                        var add = irid * Float((0.12 + fres) * ow * 1.1 * k) * thin
                        if fv > 0 {
                            let x = max(0, simd_dot(rf0(nv, vd), LdS)), x2 = x * x, x4 = x2 * x2, x8 = x4 * x4, x16 = x8 * x8, x32 = x16 * x16, x64 = x32 * x32
                            add += SIMD3<Float>(repeating: Float(x64 * 1.2 * outer * k))     // 小さなつや
                        }
                        row.append(IntVert(p: SIMD4(gpuH(pv), 1), c: SIMD4(vc * toneS * 0.85 * aq + add * aq * 2.2, aq)))
                    } else if glassS {
                        // 色つきの水晶：中は色がうっすら見えるくらい・ふちはその場所の胞の色で光る（白で足さない＝白っぽくならない）
                        let m1 = 1 - af, m2 = m1 * m1, fres = m2 * m2
                        let aq = min(0.55, al * Float(0.5 + 1.9 * fres * outer)), base = Float(0.5 + 0.3 * af) * aq
                        let sn = fv >= 0 ? nv : -nv, rf = 2 * simd_dot(sn, vd) * sn - vd
                        var add = vc * Float(fres * outer * 0.7 * k) * thin + SIMD3<Float>(repeating: Float(fres * outer * 0.08 * k))
                        if fv > 0 {
                            let x = max(0, simd_dot(rf, LdS)), x2 = x * x, x4 = x2 * x2, x8 = x4 * x4, x16 = x8 * x8, x32 = x16 * x16, x64 = x32 * x32, x128 = x64 * x64
                            let sp = x128 * x8 * x4                                       // x^140
                            add += SIMD3<Float>(repeating: Float(sp * 1.6 * outer * k))
                        } else {
                            let y = max(0, simd_dot(-nv, -LdS)), y2 = y * y, ca = y2 * y2 * y2   // y^6
                            add += SIMD3<Float>(1.0, 0.92, 0.75) * Float(ca * 0.12 * outer * k) * thin
                        }
                        row.append(IntVert(p: SIMD4(gpuH(pv), 1), c: SIMD4(vc * base + add, aq)))
                    } else {
                        let base = Float(1 - rimK * pow(1 - af, 1.6)) * al
                        row.append(IntVert(p: SIMD4(gpuH(pv), 1), c: SIMD4(vc * base, al)))
                    }
                }
                VV.append(row)
            }
            // 半透明の殻：ふちほど暗く（超球面アプリのリム影）。裏 → 表の順（これも同時に作っておく）
            var back: [IntVert] = [], front: [IntVert] = []
            back.reserveCapacity(RG * SG * 6); front.reserveCapacity(RG * SG * 6)
            for i in 0..<RG { for j in 0..<SG {
                let mid = (G[i][j] + G[i + 1][j] + G[i + 1][j + 1] + G[i][j + 1]) / 4
                let f = simd_dot(simd_length(mid - C) > 1e-9 ? simd_normalize(mid - C) : SIMD3(0, 0, 1), eye - mid)
                let v00 = VV[i][j], v10 = VV[i + 1][j], v11 = VV[i + 1][j + 1], v01 = VV[i][j + 1]
                if f < 0 { back.append(v00); back.append(v10); back.append(v11); back.append(v00); back.append(v11); back.append(v01) } else { front.append(v00); front.append(v10); front.append(v11); front.append(v00); front.append(v11); front.append(v01) }
            } }
            return ShellPre(G: G, VC: VC, back: back, front: front, vL: vL, i: Ly.i)
        }
        pre.withUnsafeMutableBufferPointer { buf in
            DispatchQueue.concurrentPerform(iterations: shellsL.count) { si in buf[si] = shellPre(shellsL[si]) }
        }
        for sp in pre {
            guard let sp else { continue }
            let G = sp.G, vL = sp.vL
            let t0L = tris.count, r0L = rods.count; defer { fadeRange(t0L, r0L, vL) }
            tris += sp.back; tris += sp.front
            // うすい網目（緯線・経線）。層が多い時はごちゃごちゃしないよう、1 枚おきの層だけ・本数も少なめに。色は明るく
            if sp.i % max(1, NL / 5) == 0 {
                let lineK = 0.5
                func lc(_ i: Int, _ j: Int) -> SIMD3<Float> { simd_mix(sp.VC[i][j], SIMD3<Float>(repeating: 1), SIMD3<Float>(repeating: 0.35)) * 1.2 }
                for i in [RG / 3, RG / 2, 2 * RG / 3] { for j in 0..<SG { rod(G[i][j], G[i][j + 1], lc(i, j), lineK) } }
                for j in stride(from: 0, to: SG, by: SG / 4) { for i in 0..<RG { rod(G[i][j], G[i + 1][j], lc(i, j), lineK) } }
            }
        }
        lap("緯度")
        // 正 120 胞体：辺 1200 本を 3 つに分けて球面に沿わせた、少し太いワイヤー。色はいちばん近い接点（触れている胞）の色に寄せる。
        //   手前の辺ほど明るく、奥ほど暗く（重なっても奥行きがわかるように）
        if st.inSphere120 {
            let wc = wireCols(4), c0 = simd_distance(P4(0, 0, 0, 0), eye), R0 = H * 1.3
            for (A, B) in Self.cell120Edges {
                var a = A, qa = { let u = spun(A); return P4(u.x, u.y, u.z, u.w) }()
                for s in 1...3 {
                    let b = simd_normalize(A + (B - A) * (Double(s) / 3)), ub = spun(b), qb = P4(ub.x, ub.y, ub.z, ub.w)
                    let m = simd_normalize(a + b), um = spun(m)
                    // 出現：8 つの接点（正十二面体の部屋の真ん中）から結晶が育ち、まん中（角の向き。接点から 60°）でぶつかって全部うまる
                    //   接点のまわりは部屋の中（空っぽ）なので、いちばん近い辺（接点から約 20°）が時計の 0 で育ちはじめるように
                    let vG = appearAt((acos(min(1, max(max(abs(um.x), abs(um.y)), max(abs(um.z), abs(um.w))))) - 0.33) / (Double.pi / 3 - 0.33), 0.22)
                    if vG < 0.04 { a = b; qa = qb; continue }
                    var col = appCol ? inSphereCellColor4(um, wc) : OrigamiState.hsl(0.8 * (m.w + 1) / 2, 0.9, 0.6)
                    let dd = (simd_distance((qa + qb) * 0.5, eye) - c0) / R0
                    col *= Float(0.95 - 0.4 * max(-1, min(1, dd)))
                    col *= 1 + 1.3 * 4 * vG * (1 - vG)                               // 育っている先は少し明るく（うすさは細さで）
                    rod(qa, qb, col, 2.0, wm: 1.6 * vG); a = b; qa = qb
                }
            }
        }
        // ホップの輪（4D の二重回転の時）：模様の点を 9 個えらび、1 周で走る道を光る輪で、今いる所に小さな玉。
        //   1 : 1 ならどの道も大円で、どの 2 本も鎖のようにからみ合う（クリフォードの平行線）。点は 3 つの入れ子のドーナツ（a）の上に 3 個ずつ
        if st.inSphereSpin == 2 && st.inSphereHopf {
            let rt = OrigamiState.sphRatios[max(0, min(OrigamiState.sphRatios.count - 1, st.inSphereRatio))], S = Int(160 * rt.q)
            var idx = 0
            for a in [0.45, Double.pi / 4, 1.12] { for c in [0.0, 2 * Double.pi / 3, 4 * Double.pi / 3] {
                let p0 = SIMD4<Double>(cos(a), 0, sin(a) * cos(c + a), sin(a) * sin(c + a))
                let col = OrigamiState.hsl(Double(idx) / 9, 0.95, 0.62); idx += 1
                var prev = P4(p0.x, p0.y, p0.z, p0.w)
                for s2 in 1...S {
                    let v = OrigamiState.doubleRot(p0, 2 * Double.pi * rt.q * Double(s2) / Double(S), rt.r), q = P4(v.x, v.y, v.z, v.w)
                    rod(prev, q, col, 1.1); prev = q
                }
                let b = OrigamiState.doubleRot(p0, st.inSphereT, rt.r), bq = P4(b.x, b.y, b.z, b.w)
                intMarks.append(TLBall(p: SIMD4(gpuH(bq), 0.034), col: SIMD4(simd_min(col * 1.3 + SIMD3<Float>(repeating: 0.15), SIMD3<Float>(repeating: 1)) * Float(k), 2)))
            } }
        }
        guard !tris.isEmpty else { return [] }
        var bt = IntTriBatch(add: false, verts: tris)
        if sharp {                                                       // 壁は GPU の座標（x, −z, y）に直して渡す
            bt.dent = dentPl.map { SIMD4<Float>(Float($0.n.x), Float(-$0.n.z), Float($0.n.y), Float($0.d)) } + [SIMD4<Float>(0.55 * Float(dentK), 1, 0, 0)]
        }
        return [bt]
    }
}
