// 120 胞体（S³ を 120 個の正十二面体で区切る）：ウェブ版の cellDodeca・planesAt・solveScale・cell120 と同じ作り方
//   planes：基本の部屋（正十二面体 1 つ）の 12 枚の面の 4 次元の向き（シェーダーの「部屋の辺」で、光を部屋の中へ折り返すのに使う）
//   edges：120 胞体ぜんぶの辺（地図に描く）
import Foundation
import simd

enum Cell120 {
    static let PHI = (1 + sqrt(5.0)) / 2
    struct Built { let planes: [V4]; let edges: [(V4, V4)]; let cells: Int }
    static let shared: Built = build()

    static func build() -> Built {
        // 正十二面体：頂点 20、面の向き 12、辺 30
        var V: [SIMD3<Double>] = []
        for x in [-1.0, 1] { for y in [-1.0, 1] { for z in [-1.0, 1] { V.append([x, y, z]) } } }
        let a = 1 / PHI, b = PHI
        // 黄金比の頂点は (0, ±φ, ±1/φ) の並び。ウェブ版は (0, ±1/φ, ±φ) で、面の向き N と組み合わせがずれていて
        //   （どの面にも頂点が 1 つしか乗らない）、地図の 120 胞体の辺が 3600 本・頂点 2153 個になっていた。
        //   面の向き N はウェブ版のまま（部屋の面は s·d0 だけで決まるので、中の景色の部屋の絵はウェブ版と同じ）
        for s in [-1.0, 1] { for t in [-1.0, 1] { V.append([0, s * b, t * a]); V.append([s * b, t * a, 0]); V.append([s * a, 0, t * b]) } }
        var N: [SIMD3<Double>] = []
        for s in [-1.0, 1] { for t in [-1.0, 1] { N.append([0, s, t * PHI]); N.append([s, t * PHI, 0]); N.append([s * PHI, 0, t]) } }
        N = N.map { simd_normalize($0) }
        let d0 = V.map { simd_dot($0, N[0]) }.max()!
        var E: [(Int, Int)] = []; let el = 2 / PHI
        for i in 0..<20 { for j in (i + 1)..<20 where abs(simd_length(V[i] - V[j]) - el) < 1e-6 { E.append((i, j)) } }
        // 面の 4 次元の向き：(n, −s·d0) を正規化（S³ の曲がり k = 1）
        func planesAt(_ s: Double) -> [V4] { N.map { nrm(V4($0.x, $0.y, $0.z, -s * d0)) } }
        // となり合う面の角がちょうど 120°（2π/3）になる大きさ s を二分法で
        var bi = 0, bj = 1, best = -2.0
        for i in 0..<N.count { for j in (i + 1)..<N.count { let d = simd_dot(N[i], N[j]); if d < 0.9999 && d > best { best = d; bi = i; bj = j } } }
        func f(_ s: Double) -> Double { let P = planesAt(s); return acos(max(-1, min(1, -dot4(P[bi], P[bj])))) }
        var lo = 1e-6, hi = 50.0
        for _ in 0..<200 { let m = (lo + hi) / 2; if f(m) < 2 * Double.pi / 3 { lo = m } else { hi = m } }
        let s = (lo + hi) / 2, P = planesAt(s)
        // 面での鏡映をくり返して 120 個の部屋を数え、辺を集める
        typealias M4 = simd_double4x4
        func refl(_ v: V4) -> M4 { M4(diagonal: [1, 1, 1, 1]) - 2 * M4(rows: [v * v.x, v * v.y, v * v.z, v * v.w]) }
        let R = P.map(refl)
        let Vh = V.map { nrm(V4($0.x * s, $0.y * s, $0.z * s, 1)) }
        func key(_ M: M4) -> String { (0..<4).map { String(Int((M[3, $0] * 1000).rounded())) }.joined(separator: ",") }   // 行列の 4 列目（行ごとの [3]）
        var cells: [M4] = [M4(diagonal: [1, 1, 1, 1])], seen: Set<String> = [key(cells[0])], q = cells
        while !q.isEmpty && cells.count < 200 {
            let M = q.removeFirst()
            for Rf in R { let M2 = M * Rf; let k = key(M2); if seen.contains(k) { continue }; seen.insert(k); cells.append(M2); q.append(M2) }
        }
        var em: [String: (V4, V4)] = [:]
        for M in cells { for (i, j) in E {
            let A = M * Vh[i], B = M * Vh[j]
            let k = (0..<4).map { String(Int(((A[$0] + B[$0]) * 1000).rounded())) }.joined(separator: ",")
            if em[k] == nil { em[k] = (A, B) }
        } }
        return Built(planes: P, edges: Array(em.values), cells: cells.count)
    }
}
