// n 次元の計算（ウェブ版の共通部品 共通部品/nd-geom/nd-geom.js 1.0.1 の Swift 版。式も名前もそろえる）
//   次元おりがみ（ネイティブ版）を 5 次元・6 次元へ広げるための土台。3〜10 次元で同じコードが動く。
//   回転：回転面 (i, j) と角度の並びから n×n の行列（x_i' = cos·x_i − sin·x_j、x_j' = sin·x_i + cos·x_j）。
//   写し方：4 本目から先を、いちばん上の次元から 1 本ずつ遠近で 3D へ（段 m ごとに k_m = 1 / (1 − q_m / D_m)、q_0 … q_{m−1} を k_m 倍）。
//     見かけの縮み K = k_{n−1} × … × k_3（大きいほど手前）。次元おりがみの距離：D_w = 4.5、v は ×1.4、u は ×1.9、その先は 0.5 ずつ。はさみ方は ±(D − 0.5)。
//   展開図：真ん中・腕 2(n−1)・ふた。腕が先（0〜0.60）、ふたは少しあと（0.45〜1）、なめらか（smootherstep）、ふたは +y の腕の先、組み上がるにつれて中心が原点へ。
//   胞の並び：真ん中、腕 +軸0、−軸0、+軸1 … −軸(N−1)、ふた（ウェブ版と同じ。次元おりがみのネイティブ版の 3・4 次元は +y が先なので、並びを変える時はそちらに合わせる）
import Foundation

enum NDGeom {
    static let version = "1.0.1"
    static let axes = ["x", "y", "z", "w", "v", "u", "t", "s", "r", "q"]

    // ---- 1. 回転（n×n、行 r・列 c を r * n + c に）----
    static func identity(_ n: Int) -> [Double] { var R = [Double](repeating: 0, count: n * n); for i in 0..<n { R[i * n + i] = 1 }; return R }
    /// R に平面 (i, j) の回転を左からかける（今の向きのあとに回す）
    static func rotatePlane(_ R: inout [Double], _ n: Int, _ i: Int, _ j: Int, _ a: Double) {
        guard a != 0 else { return }
        let c = cos(a), s = sin(a)
        for col in 0..<n {
            let x = R[i * n + col], y = R[j * n + col]
            R[i * n + col] = c * x - s * y; R[j * n + col] = s * x + c * y
        }
    }
    /// 回す順に (i, j, 角度)
    static func rotation(_ n: Int, _ spec: [(Int, Int, Double)]) -> [Double] {
        var R = identity(n)
        for (i, j, a) in spec { rotatePlane(&R, n, i, j, a) }
        return R
    }
    static func apply(_ R: [Double], _ n: Int, _ p: [Double]) -> [Double] {
        (0..<n).map { r in (0..<n).reduce(0) { $0 + R[r * n + $1] * p[$1] } }
    }
    static func multiply(_ A: [Double], _ B: [Double], _ n: Int) -> [Double] {
        var C = [Double](repeating: 0, count: n * n)
        for r in 0..<n { for c in 0..<n { var s = 0.0; for k in 0..<n { s += A[r * n + k] * B[k * n + c] }; C[r * n + c] = s } }
        return C
    }
    static func transpose(_ R: [Double], _ n: Int) -> [Double] { var T = R; for r in 0..<n { for c in 0..<n { T[c * n + r] = R[r * n + c] } }; return T }
    /// 軸 k が x・y・z に残っている割合（0〜1。4 本目から先へ回った分だけ消える）
    static func axisVisible(_ R: [Double], _ n: Int, _ k: Int) -> Double {
        var s = 0.0
        for r in 0..<min(3, n) { let x = R[r * n + k]; s += x * x }
        return sqrt(s)
    }

    // ---- 2. 3D への写し方（次元おりがみの式：preset okami）----
    static func okamiRatio(_ m: Int) -> Double { m <= 3 ? 1 : m == 4 ? 1.4 : 1.9 + 0.5 * Double(m - 5) }
    struct Projector {
        let n: Int
        var D: [Double]                         // 段 m の距離（m < 3 は使わない）
        var margin = 0.5, both = true, blend = 0.0, scale = 1.0
        var R: [Double]?                         // 回転（無ければ回さない）
        init(n: Int, w: Double = 4.5, R: [Double]? = nil) {
            self.n = n; self.R = R
            D = (0..<n).map { $0 < 3 ? 0 : w * NDGeom.okamiRatio($0) }
        }
        /// 点を回して写す。返り値：3D の位置・見かけの縮み K（大きいほど手前）・縮めたあとの w
        func project(_ p: [Double]) -> (SIMD3<Double>, Double, Double) {
            var q = R.map { NDGeom.apply($0, n, p) } ?? p
            var K = 1.0
            var m = n - 1
            while m >= 3 {
                let Dm = D[m]
                var x = q[m]
                if x > Dm - margin { x = Dm - margin }
                if both && x < -Dm + margin { x = -Dm + margin }
                var k = 1 / (1 - x / Dm)
                if blend != 0 { k = 1 + (k - 1) * (1 - blend) }
                for t in 0..<m { q[t] *= k }
                K *= k; m -= 1
            }
            return (SIMD3(q[0], q[1], q[2]) * scale, K, n > 3 ? q[3] : 0)
        }
    }

    // ---- 3. 立方体の展開図 ----
    static func smoother(_ t: Double) -> Double { let c = max(0, min(1, t)); return c * c * c * (c * (c * 6 - 15) + 10) }
    enum Kind { case center, arm, cap }
    struct Cell { let kind: Kind; let axis: Int; let sign: Double; var free: [Int] }
    /// 折る角度（腕は軸ごと、ふたは腕に対してさらに）。f：0 平ら〜1 組み上がり。次元おりがみ：腕 0〜0.60、ふた 0.45〜1
    static func foldAngles(_ f: Double, _ n: Int, armEnd: Double = 0.60, capStart: Double = 0.45) -> (arm: [Double], cap: Double) {
        let a = smoother(min(1, f / armEnd)) * .pi / 2
        return ([Double](repeating: a, count: n - 1), smoother(max(0, (f - capStart) / (1 - capStart))) * .pi / 2)
    }
    /// 1 点を折る。p：組み上がりの位置（±1）、capAxis：ふたがつく腕の軸、shift：最後に軸 N に足す量（真ん中を原点に寄せる時）
    static func foldPoint(_ cell: Cell, _ p: [Double], _ ang: (arm: [Double], cap: Double), _ n: Int, capAxis: Int = 1, shift: Double = 0) -> [Double] {
        let N = n - 1
        var o = p
        switch cell.kind {
        case .arm:                                              // 蝶番：x_a = s, x_N = −1。x_N + 1 の分が、軸 a の外向き（平ら）→ 軸 N の向き（組み上がり）へ
            let a = cell.axis, th = ang.arm[a], d = p[N] + 1
            o[a] = cell.sign * (1 + d * cos(th)); o[N] = -1 + d * sin(th)
        case .cap:                                              // 腕 +capAxis の先（長さ 2）を蝶番に、腕の向きからさらに
            let c = capAxis, t1 = ang.arm[c], g = t1 + ang.cap, e = 1 - p[c]
            o[c] = 1 + 2 * cos(t1) + e * cos(g); o[N] = -1 + 2 * sin(t1) + e * sin(g)
        case .center: break
        }
        o[N] += shift
        return o
    }
    /// 展開図（次元おりがみ：頂点 ±0.9・ふたは +y の腕の先・組み上がりの中心が原点）
    struct CubeNet {
        let n: Int, size: Double, capAxis: Int
        let cells: [Cell]
        let nl: Int                                             // 胞 1 つの頂点の数（2^(n−1)）
        let edges: [(Int, Int)]                                 // 頂点の番号（胞 ci の頂点 v は ci * nl + v）
        let squares: [(Int, Int, Int, Int, cell: Int)]          // 正方形の面（4 つの角と胞）
        init(n: Int, size: Double = 0.9, capAxis: Int = 1) {
            self.n = n; self.size = size; self.capAxis = capAxis
            let N = n - 1, nl = 1 << N
            var cs = [Cell(kind: .center, axis: N, sign: -1, free: [])]
            for k in 0..<N { for sg in [1.0, -1.0] { cs.append(Cell(kind: .arm, axis: k, sign: sg, free: [])) } }
            cs.append(Cell(kind: .cap, axis: N, sign: 1, free: []))
            for i in cs.indices { cs[i].free = (0..<n).filter { $0 != cs[i].axis } }
            var E: [(Int, Int)] = [], Q: [(Int, Int, Int, Int, cell: Int)] = []
            for ci in cs.indices {
                let off = ci * nl
                for v in 0..<nl { for b in 0..<N where (v >> b) & 1 == 0 { E.append((off + v, off + (v | 1 << b))) } }
                for a in 0..<N { for b in (a + 1)..<max(a + 1, N) { for v in 0..<nl where (v >> a) & 1 == 0 && (v >> b) & 1 == 0 {
                    Q.append((off + v, off + (v | 1 << a), off + (v | 1 << a | 1 << b), off + (v | 1 << b), cell: ci))
                } } }
            }
            cells = cs; self.nl = nl; edges = E; squares = Q
        }
        /// 胞 ci の頂点 v の組み上がりの位置（±1）
        func base(_ ci: Int, _ v: Int) -> [Double] {
            let C = cells[ci]
            var p = [Double](repeating: 0, count: n); p[C.axis] = C.sign
            for (b, ax) in C.free.enumerated() { p[ax] = (v >> b) & 1 == 1 ? 1 : -1 }
            return p
        }
        /// 折り具合 f の全部の頂点（n 次元。× size 済み）
        func place(_ f: Double) -> [[Double]] {
            let ang = NDGeom.foldAngles(f, n)
            let shift = 1 - (ang.arm.reduce(0, +) / Double(n - 1)) / (.pi / 2)
            var V: [[Double]] = []; V.reserveCapacity(cells.count * nl)
            for ci in cells.indices { for v in 0..<nl { V.append(NDGeom.foldPoint(cells[ci], base(ci, v), ang, n, capAxis: capAxis, shift: shift).map { $0 * size }) } }
            return V
        }
    }
}
