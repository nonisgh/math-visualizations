// 内接する超球面（回転バーの「内接球」）：超立方体にぴったり内接する超球面（半径 1、8 個の胞の真ん中に接する）を、
//   超球面アプリ（hypersphere.html）と同じ「w ＝ 一定で切った球殻を積んだもの」として、超立方体の中に描く。
//   層：北（w＞0）と南（w＜0）に 6 枚ずつと赤道。層 i の球殻は 半径 sinθ・高さ w ＝ ±cosθ（θ は極からの角度）。
//   色も超球面アプリと同じ（北 紫 → 水色、南 赤 → 緑、赤道に向かって）。半透明の殻と、うすい網目。
//   点ごとに超立方体と同じ 4 次元の回転と遠近で写す＝超立方体と一緒に回る（4D で回すと殻がゆがみ、裏返る）。
//   立方体の窓には、内接する球を緯度の輪（z ＝ 一定の円）で。積分の「超球（内接）」（レインボーボール）とは別のもの
import Foundation
import simd

@inline(__always) private func gpuH(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 超球面アプリの層の色（redCenter でない時）：北 h＝0.80 − 0.40t、南 h＝0.40t（t＝0 極 〜 1 赤道）
    static func layerCol(_ i: Int, _ n: Int, south: Bool) -> SIMD3<Float> {
        let t = Double(i) / Double(max(1, n - 1))
        return OrigamiState.hsl(south ? 0.40 * t : 0.80 - 0.40 * t, 0.95, 0.52)
    }
    func inSphereGeometry(_ rods: inout [TLRod], eye: SIMD3<Double>) -> [IntTriBatch] {
        guard st.inSphere else { return [] }
        let k = max(0, min(1, (st.progress - 0.92) / 0.08)) * max(0, 1 - 4 * st.explodeE)   // 組み上がっている時だけ
        guard k > 0.01 else { return [] }
        let H = OrigamiState.half, NL = 6, MIN = 0.08
        func P(_ u: [Double]) -> SIMD3<Double> { st.place(u.map { $0 * H }, n).0 }
        func rod(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Float>, _ L: Double) { rods.append(TLRod(a: SIMD4(gpuH(a), 0), b: SIMD4(gpuH(b), 0), col: SIMD4(c, Float(L * k / 1.4)))) }
        // 層（北・南。赤道は 1 枚）
        var layers: [(th: Double, south: Bool, i: Int)] = []
        for i in 0..<NL { let th = MIN + Double(i) / Double(NL - 1) * (Double.pi / 2 - MIN); layers.append((th, false, i)); if i < NL - 1 { layers.append((th, true, i)) } }
        if n == 3 {
            // 立方体の窓：内接する球の緯度の輪（z ＝ ±cosθ、半径 sinθ）
            for L in layers {
                let r = sin(L.th), z = (L.south ? -1 : 1) * cos(L.th), col = Self.layerCol(L.i, NL, south: L.south), S = 48
                for s in 0..<S {
                    let a0 = 2 * Double.pi * Double(s) / Double(S), a1 = 2 * Double.pi * Double(s + 1) / Double(S)
                    rod(P([r * cos(a0), r * sin(a0), z]), P([r * cos(a1), r * sin(a1), z]), col, 0.9)
                }
            }
            return []
        }
        // 超立方体の窓：球殻（w ＝ ±cosθ、半径 sinθ）を、遠い層から順に（重ねる順）
        let order = layers.sorted { simd_distance(P([0, 0, 0, ($0.south ? -1 : 1) * cos($0.th)]), eye) > simd_distance(P([0, 0, 0, ($1.south ? -1 : 1) * cos($1.th)]), eye) }
        var tris: [IntVert] = []
        let RG = 10, SG = 20
        for L in order {
            let r = sin(L.th), w = (L.south ? -1 : 1) * cos(L.th), col = Self.layerCol(L.i, NL, south: L.south)
            var G: [[SIMD3<Double>]] = []
            for i in 0...RG {
                let th = Double.pi * Double(i) / Double(RG)
                G.append((0...SG).map { j in let ph = 2 * Double.pi * Double(j) / Double(SG); return P([r * sin(th) * cos(ph), r * cos(th), r * sin(th) * sin(ph), w]) })
            }
            let C = P([0, 0, 0, w])
            // 半透明の殻：ふちほど暗く（超球面アプリのリム影）。裏 → 表の順
            var back: [IntVert] = [], front: [IntVert] = []
            for i in 0..<RG { for j in 0..<SG {
                let q = [G[i][j], G[i + 1][j], G[i + 1][j + 1], G[i][j + 1]]
                let mid = (q[0] + q[1] + q[2] + q[3]) / 4, nrm = simd_length(mid - C) > 1e-9 ? simd_normalize(mid - C) : SIMD3(0, 0, 1)
                let f = simd_dot(nrm, simd_normalize(eye - mid)), rim = 1 - abs(f)
                let al = Float(0.13 * k), c = col * Float(1 - 0.55 * pow(rim, 1.6)) * al
                let vs = [q[0], q[1], q[2], q[0], q[2], q[3]].map { IntVert(p: SIMD4(gpuH($0), 1), c: SIMD4(c, al)) }
                if f < 0 { back += vs } else { front += vs }
            } }
            tris += back; tris += front
            // うすい網目（緯線 3 本・経線 6 本）
            let wc = col * 1.3
            for i in stride(from: 2, to: RG, by: 3) { for j in 0..<SG { rod(G[i][j], G[i][j + 1], wc, 0.45) } }
            for j in stride(from: 0, to: SG, by: SG / 6) { for i in 0..<RG { rod(G[i][j], G[i + 1][j], wc, 0.45) } }
        }
        return tris.isEmpty ? [] : [IntTriBatch(add: false, verts: tris)]
    }
}
