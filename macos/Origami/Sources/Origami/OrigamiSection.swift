// 断面（切り口）：組み上がった超立方体（立方体）を、平らな包丁で切った切り口。
//   包丁＝画面の「折りたたみでできた次元」の向き（超立方体は w、立方体は z）に垂直な平らなもの（超立方体なら 3 次元の超平面＝わたしたちの 3 次元の世界）。
//   形の体の座標では、その向きは回転の行列の w の行（立方体は z の行）。4 次元で回すと包丁が形に対してななめになり、切り口の形が変わる。
//     胞から見る＝いつも立方体、頂点から見る＝点 → 正四面体 → 切頂四面体 → 正八面体（まんなか）→ …（立方体なら 三角形 → 正六角形）。
//   切り口の頂点＝包丁と辺の交わり。超立方体の切り口の面＝包丁と胞（立方体）の交わり＝多角形（面の色はその胞の色）。
//   立方体の切り口は、交わりの点を全部つないだ 1 枚の多角形。
import simd

struct SecPoly { var pts: [SIMD4<Double>]; var cell: Int }   // 体の座標（×half 済み）の点・どの胞から来たか（立方体は −1）

extension OrigamiState {
    /// 包丁の向き（体の座標）：超立方体は回転の w の行、立方体は X-Z・Y-Z のあとの z の行
    func secNormal(_ n: Int) -> SIMD4<Double> {
        if n == 4 { return SIMD4(m4[0][3], m4[1][3], m4[2][3], m4[3][3]) }
        return SIMD4(l3[0][2], l3[1][2], l3[2][2], 0)
    }
    /// 包丁の位置の範囲（形の頂点のうち、いちばん向こう側の値）
    func secRange(_ n: Int) -> Double {
        let nr = secNormal(n)
        return Self.half * (0..<n).reduce(0.0) { $0 + abs(nr[$1]) }
    }
    static func unitVert(_ v: Int, _ n: Int) -> SIMD4<Double> {
        var p = SIMD4<Double>(0, 0, 0, 0)
        for k in 0..<n { p[k] = v & (1 << k) != 0 ? 1 : -1 }
        return p
    }
    /// 切り口の多角形と、形の名前（頂点の数・面の数から）
    func section(_ n: Int) -> (polys: [SecPoly], verts: Int, info: String) {
        let nr = secNormal(n), R = secRange(n)
        guard R > 1e-9 else { return ([], 0, "") }
        let c = max(-1, min(1, secPos)) * R * 0.9995                    // ちょうど頂点の所は、形がつぶれるので少しだけ内側
        let cells = Self.cells(n)
        var byCell: [Int: [SIMD4<Double>]] = [:], all: [SIMD4<Double>] = []
        func addUnique(_ list: inout [SIMD4<Double>], _ p: SIMD4<Double>) { if !list.contains(where: { simd_distance($0, p) < 1e-7 }) { list.append(p) } }
        for v in 0..<(1 << n) {
            for k in 0..<n where v & (1 << k) == 0 {
                let a = Self.unitVert(v, n) * Self.half, b = Self.unitVert(v | (1 << k), n) * Self.half
                let da = simd_dot(nr, a) - c, db = simd_dot(nr, b) - c
                guard (da <= 0 && db > 0) || (da > 0 && db <= 0) else { continue }
                let p = a + (b - a) * (da / (da - db))
                addUnique(&all, p)
                // この辺を含む胞（辺の向き k 以外の軸が ±1 で決まった胞）
                if n == 4 {
                    for j in 0..<n where j != k {
                        let val = a[j] > 0 ? 1.0 : -1.0
                        if let ci = cells.firstIndex(where: { Self.fixed($0, n) == (j, val) }) { addUnique(&byCell[ci, default: []], p) }
                    }
                }
            }
        }
        /// 平らな点の組を、まわりの順に並べる（重心のまわりの角度で）
        func ordered(_ ps: [SIMD4<Double>]) -> [SIMD4<Double>]? {
            guard ps.count >= 3 else { return nil }
            let g = ps.reduce(SIMD4<Double>(0, 0, 0, 0), +) / Double(ps.count)
            guard let p0 = ps.max(by: { simd_length($0 - g) < simd_length($1 - g) }), simd_length(p0 - g) > 1e-9 else { return nil }
            let u = simd_normalize(p0 - g)
            var best = SIMD4<Double>(0, 0, 0, 0)
            for p in ps { let w = (p - g) - simd_dot(p - g, u) * u; if simd_length(w) > simd_length(best) { best = w } }
            guard simd_length(best) > 1e-9 else { return nil }
            let v = simd_normalize(best)
            return ps.sorted { atan2(simd_dot($0 - g, v), simd_dot($0 - g, u)) < atan2(simd_dot($1 - g, v), simd_dot($1 - g, u)) }
        }
        var polys: [SecPoly] = []
        if n == 4 {
            for ci in byCell.keys.sorted() { if let o = ordered(byCell[ci]!) { polys.append(SecPoly(pts: o, cell: ci)) } }
        } else if let o = ordered(all) {
            polys.append(SecPoly(pts: o, cell: -1))
        }
        return (polys, all.count, Self.secName(n, all.count, polys.map { $0.pts.count }))
    }
    /// 頂点の数と、面ごとの角の数から、形の名前
    static func secName(_ n: Int, _ V: Int, _ faces: [Int]) -> String {
        if V == 0 { return "切り口なし" }
        if n == 3 {
            let names = [3: "三角形", 4: "四角形", 5: "五角形", 6: "六角形"]
            return "\(names[V] ?? "\(V) 角形")（頂点 \(V)）"
        }
        let F = faces.count, t3 = faces.filter { $0 == 3 }.count, t4 = faces.filter { $0 == 4 }.count, t6 = faces.filter { $0 == 6 }.count
        let name: String
        switch (V, F) {
        case (4, 4): name = "四面体"
        case (6, 8) where t3 == 8: name = "八面体"
        case (8, 6) where t4 == 6: name = "六面体（立方体のなかま）"
        case (12, 8) where t3 == 4 && t6 == 4: name = "切頂四面体（角の欠けた四面体）"
        case (6, 5) where t3 == 2: name = "三角柱"
        case (12, 8) where t6 == 2: name = "六角柱"
        default: name = "\(F) 面の多面体"
        }
        return "\(name)（頂点 \(V)・面 \(F)）"
    }
}
