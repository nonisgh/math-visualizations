// 5 次元 β の内接球：5 次元超立方体にぴったり内接する 4 次元球面 S⁴（半径 1、10 個の胞の真ん中に 1 点ずつ接する）。
//   S⁴ を「(w, v) の円板の上にならんだ、ふつうの球面 S² の家族」として描く：w・v を決めると、残りの x・y・z は半径 √(1 − w² − v²) の球面。
//   真ん中 (0, 0) の大きな球と、そのまわりの 2 つの輪（ρ ＝ 0.45・0.75、6 方向ずつ）の 13 枚。
//   それに、座標の大円 10 本（5 本の軸から 2 本えらんだ面の円。どれも接点を 4 つずつ通る）。
//   超立方体の内接球（OrigamiInSphere.swift）と同じく、組み上がっている時だけ出す。回転・めりこみ・ガラスは β ではまだ無い
import Foundation
import simd

@inline(__always) private func gpu5(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 5 次元の内接球の殻（(w, v) の組）。真ん中と 2 つの輪
    static let sph5Shells: [(w: Double, v: Double, ring: Int, k: Int)] = {
        var out: [(Double, Double, Int, Int)] = [(0, 0, 0, 0)]
        for (ri, rho) in [0.45, 0.75].enumerated() {
            for k in 0..<6 { let ph = Double(k) * .pi / 3 + (ri == 1 ? .pi / 6 : 0); out.append((rho * cos(ph), rho * sin(ph), ri + 1, k)) }
        }
        return out
    }()
    func inSphere5Geometry(_ rods: inout [TLRod], eye: SIMD3<Double>) -> [IntTriBatch] {
        guard st.inSphere, n == 5 else { return [] }
        let k = max(0, min(1, (st.progress - 0.92) / 0.08)) * max(0, 1 - 4 * st.explodeE)
        guard k > 0.01 else { return [] }
        let H = OrigamiState.half, appCol = st.inSphereColor == 0
        let bw = Float(st.inSphereWireW / max(0.3, st.lineWidthNow))           // 内接球のワイヤーの太さ（線の太さの分は打ち消す）
        let cols = st.cellColors(5).map { OrigamiState.rgb($0) }, nr = Self.cellNormals[2]
        func P(_ u: [Double]) -> SIMD3<Double> { st.place5(u.map { $0 * H }).0 }
        /// アプリの色：いちばん近い胞（接している胞）の色を、近さでなめらかにまぜる（超立方体の内接球と同じ考え）
        func cellCol(_ u: [Double]) -> SIMD3<Float> {
            var c = SIMD3<Float>(0, 0, 0), ws: Float = 0
            for i in 0..<min(cols.count, nr.count) {
                let d = max(0, u[nr[i].0] * nr[i].1), d2 = d * d, w = Float(d2 * d2 * d2)
                c += cols[i] * w; ws += w
            }
            return Self.vivid(ws > 1e-9 ? c / ws : SIMD3<Float>(repeating: 0.7))
        }
        // 殻：遠い殻から順に（重ねる順）。殻の中は 裏 → 表
        let NA = 14, NB = 28
        let shells = Self.sph5Shells.map { s -> (s: (w: Double, v: Double, ring: Int, k: Int), c: SIMD3<Double>) in (s, P([0, 0, 0, s.w, s.v])) }
            .sorted { simd_distance($0.c, eye) > simd_distance($1.c, eye) }
        var tris: [IntVert] = []; tris.reserveCapacity(shells.count * NA * NB * 6)
        // 出現（内接球の出現の時計）：殻は w の −1 から ＋1 へ積み上がる・正軸体の弧は接点から両側へのびる・部屋の真ん中の点は最後に
        let ap = st.inSphereAppear
        func appearAt(_ s: Double, _ span: Double = 0.3) -> Float {
            guard ap < 0.999 else { return 1 }
            let c = max(0, min(1, (ap - max(0, min(1, s)) * (1 - span)) / span)); return Float(c * c * (3 - 2 * c))
        }
        for (s, C) in st.inSphereLat ? shells : [] {                            // 緯度の殻（模様で切ると出さない。経度・円錐は 5 次元ではまだ無い）
            let vL = appearAt((s.w + 1) / 2)
            if vL < 0.005 { continue }
            let t0L = tris.count, r0L = rods.count
            defer {
                if vL < 0.999 {
                    for i in t0L..<tris.count { tris[i].c *= vL }
                    for i in r0L..<rods.count { rods[i].b.w = (rods[i].b.w > 0 ? rods[i].b.w : 1) * vL }   // 線は細く（暗くすると黒い筋になる）
                }
            }
            let r = max(0, 1 - s.w * s.w - s.v * s.v).squareRoot() * (0.35 + 0.65 * Double(vL))
            // 格子の点（緯度 a・経度 b）
            var G: [[SIMD3<Double>]] = [], CC: [[SIMD3<Float>]] = [], AL: [[Float]] = []
            let rainbow = OrigamiState.hsl(s.ring == 0 ? 0.55 : (Double(s.k) / 6 + (s.ring == 2 ? 1.0 / 12 : 0)).truncatingRemainder(dividingBy: 1), 0.85, s.ring == 0 ? 0.62 : s.ring == 1 ? 0.6 : 0.56)
            let al = Float(0.11 * k) * (s.ring == 0 ? 1.0 : 0.85)
            for a in 0...NA {
                var row: [SIMD3<Double>] = [], crow: [SIMD3<Float>] = [], arow: [Float] = []
                let th = Double.pi * Double(a) / Double(NA)
                for b in 0...NB {
                    let ph = 2 * Double.pi * Double(b) / Double(NB)
                    let u = [r * sin(th) * cos(ph), r * cos(th), r * sin(th) * sin(ph), s.w, s.v]
                    let p = P(u); row.append(p)
                    crow.append(appCol ? cellCol(u) : rainbow)
                    // ふちほど濃く（写した殻の真ん中から点への向きと、目への向き）
                    let nv = simd_length(p - C) > 1e-9 ? simd_normalize(p - C) : SIMD3<Double>(0, 0, 1), fv = abs(simd_dot(nv, simd_normalize(eye - p)))
                    let g = 1 - fv
                    arow.append(min(0.45, al * Float(0.45 + 1.8 * g * g)))
                }
                G.append(row); CC.append(crow); AL.append(arow)
            }
            var back: [IntVert] = [], front: [IntVert] = []
            for a in 0..<NA { for b in 0..<NB {
                let q = [G[a][b], G[a + 1][b], G[a + 1][b + 1], G[a][b + 1]]
                let mid = (q[0] + q[2]) / 2
                let isFront = simd_dot(mid - C, eye - mid) > 0                   // 殻の外向き（写した殻の真ん中から）が目を向いていれば表
                let ij = [(a, b), (a + 1, b), (a + 1, b + 1), (a, b + 1)]
                let vs = ij.map { (x, y) in IntVert(p: SIMD4(gpu5(G[x][y]), 1), c: SIMD4(CC[x][y] * AL[x][y], AL[x][y])) }
                let quad = [vs[0], vs[1], vs[2], vs[0], vs[2], vs[3]]
                if isFront { front += quad } else { back += quad }
            } }
            tris += back; tris += front
            // 殻の赤道（y ＝ 0 の輪）を細い線で
            let ec = (appCol ? SIMD3<Float>(0.9, 0.92, 1.0) : rainbow) * Float(0.55 * k)
            for b in 0..<NB { rods.append(TLRod(a: SIMD4(gpu5(G[NA / 2][b]), 0), b: SIMD4(gpu5(G[NA / 2][b + 1]), bw), col: SIMD4(ec, Float(0.5 * k / 1.4)))) }
        }
        // 正軸体（正 32 胞体）：5 次元には正 120 胞体の仲間がないので、模様の「正 120 胞体」は 5 次元ではこれ。
        //   頂点 ＝ 10 個の接点 ±e_i、辺 ＝ となりの接点どうしを結ぶ 90° の弧 40 本（つなぐと下の座標の大円 10 本と同じ）、
        //   部屋 ＝ 正単体 32 個（真ん中は (±1, ±1, ±1, ±1, ±1)／√5 ＝ 5 次元立方体の角の向き）。
        //   太いワイヤーで、色は両はしの接点の色からもう一方へうつり変わる。手前ほど明るく。部屋の真ん中に小さな光の点
        if st.inSphere120 {
            let wc = wireCols(5), nr5 = Self.cellNormals[2], c0 = simd_distance(P([0, 0, 0, 0, 0]), eye), R0 = H * 1.3
            func colOf(_ ax: Int, _ sg: Double) -> SIMD3<Float> { Self.vivid(wc[nr5.firstIndex { $0.0 == ax && $0.1 == sg } ?? 0]) }
            for i in 0..<5 { for j in (i + 1)..<5 { for si in [-1.0, 1] { for sj in [-1.0, 1] {
                let ca = colOf(i, si), cb = colOf(j, sj), S = 24
                var prev = P({ var u = [0.0, 0, 0, 0, 0]; u[i] = si; return u }())
                for t in 1...S {
                    let a = Double.pi / 2 * Double(t) / Double(S), am = Double.pi / 2 * (Double(t) - 0.5) / Double(S)
                    var u = [0.0, 0, 0, 0, 0]; u[i] = si * cos(a); u[j] = sj * sin(a)
                    let p = P(u), f = Float(am / (Double.pi / 2))
                    let dd = (simd_distance((prev + p) * 0.5, eye) - c0) / R0
                    let vO = appearAt(Double(min(f, 1 - f)) * 2, 0.25)                 // 出現：両はしの接点から、まん中へのびる
                    let col = simd_mix(ca, cb, SIMD3<Float>(repeating: f)) * Float(0.95 - 0.4 * max(-1, min(1, dd))) * Float(k) * (1 + 1.3 * 4 * vO * (1 - vO))
                    if vO < 0.04 { prev = p; continue }
                    rods.append(TLRod(a: SIMD4(gpu5(prev), 0), b: SIMD4(gpu5(p), bw * 1.6 * vO), col: SIMD4(col, Float(2.0 * k / 1.4))))
                    prev = p
                }
            } } } }
            for b in 0..<32 {
                let u = (0..<5).map { (b >> $0) & 1 == 1 ? 1 / 5.0.squareRoot() : -1 / 5.0.squareRoot() }
                var c = SIMD3<Float>(0, 0, 0); for ax in 0..<5 { c += colOf(ax, u[ax] > 0 ? 1 : -1) }
                let vC = appearAt(1, 0.25); if vC < 0.005 { continue }                // 部屋の真ん中の点は、弧がつながったあとに
                intMarks.append(TLBall(p: SIMD4(gpu5(P(u)), 0.03 * Float(vC)), col: SIMD4(simd_min(c / 5 * 1.4 + SIMD3<Float>(repeating: 0.2), SIMD3<Float>(repeating: 1)) * Float(k), 2)))
            }
        }
        // 座標の大円 10 本：軸 i と軸 j の面の円（どれも接点 ±e_i・±e_j の 4 つを通る）。色は 2 本の軸の色のまざり（正軸体を出す時は、それと重なるので出さない）
        let axc: [SIMD3<Float>] = (0..<5).map { OrigamiState.axisCol[$0] }
        for i in 0..<5 { for j in (i + 1)..<5 where !st.inSphere120 {
            let c = simd_min((axc[i] + axc[j]) * 0.5 * 1.25, SIMD3<Float>(repeating: 1))
            var prev = P({ var u = [0.0, 0, 0, 0, 0]; u[i] = 1; return u }())
            for t in 1...96 {
                let a = 2 * Double.pi * Double(t) / 96
                var u = [0.0, 0, 0, 0, 0]; u[i] = cos(a); u[j] = sin(a)
                let p = P(u)
                rods.append(TLRod(a: SIMD4(gpu5(prev), 0), b: SIMD4(gpu5(p), bw), col: SIMD4(c, Float(0.75 * k / 1.4))))
                prev = p
            }
        } }
        return tris.isEmpty ? [] : [IntTriBatch(add: false, verts: tris)]
    }
}
