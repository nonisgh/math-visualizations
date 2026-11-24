// 展開図のかたち（ダリの十字架だけでなく、いろいろな展開図）。
//   展開図を「どの胞（立方体では面）が、どの胞にくっついているか」の木で持つ（parent：くっついている相手の番号、根は真ん中の胞＝−1）。
//   折り方：くっついている面（ちょうつがい）のまわりに、それぞれ 90° ずつ折る。子は親といっしょに動く（親の動きを受けついで、その上で自分も折る）。
//   どの展開図でも、全部折りきると同じ超立方体（立方体）になる。折る順番は、根から近い順に少しずつ遅れて（深いちょうつがいほどあとから）。
//   胞の番号と向き：超立方体 0 真ん中（−w）・1 +y・2 −y・3 +x・4 −x・5 +z・6 −z・7 ふた（+w）。立方体 0 真ん中（−z）・1 +y・2 −y・3 +x・4 −x・5 ふた（+z）
import Foundation
import simd

/// 組み変わりの途中（前の展開図と、始まってからの時間）
struct NetMorph { var from: NetDef; var t: Double; var from5: [Int]? = nil }   // from5：5 次元の展開図の組み変わり（前の展開図の親）

/// 展開図（超立方体の木と、立方体の展開図＝アナロジー）
struct NetDef: Codable, Equatable {
    var name: String
    var p4: [Int]                              // 超立方体：胞 8 個の親
    var p3: [Int]                              // 立方体：面 6 個の親
}

extension OrigamiState {
    static let netDali = NetDef(name: "ダリの十字架", p4: [-1, 0, 0, 0, 0, 0, 0, 1], p3: [-1, 0, 0, 0, 0, 1])
    /// 見本の展開図
    static let netPresets: [NetDef] = [
        netDali,
        // 塔：真ん中・+y・ふた・−y がたてに 4 つ並び、2 つ目（+y）のまわりに ±x・±z
        NetDef(name: "塔", p4: [-1, 0, 7, 1, 1, 1, 1, 1], p3: []),
        // 階段：+y の上にふた、ふたの横に ±x、真ん中の横に ±z と −y
        NetDef(name: "階段", p4: [-1, 0, 0, 7, 7, 0, 0, 1], p3: []),
        // ねじれ：+x の先に +y、+y の先にふた、ふたの先に −z、ほかは真ん中に
        NetDef(name: "ねじれ", p4: [-1, 3, 0, 0, 0, 0, 7, 1], p3: []),
    ].map { d in var d = d; if d.p3.isEmpty { d.p3 = OrigamiState.cubeAnalog(d.p4) }; return d }

    /// 番号の胞の向き（軸と ±）
    static func cellNormal(_ i: Int, _ n: Int) -> (Int, Double) { fixed(cells(n)[i], n) }

    // ---- 折りの変換（n 次元のアフィン：o = M p + t）----
    struct Aff { var M: [[Double]]; var t: [Double]
        static func id(_ n: Int) -> Aff {
            var M = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
            for i in 0..<n { M[i][i] = 1 }
            return Aff(M: M, t: [Double](repeating: 0, count: n))
        }
        func apply(_ p: [Double]) -> [Double] {
            let n = t.count; var o = t
            for i in 0..<n { var s = 0.0; for k in 0..<n { s += M[i][k] * p[k] }; o[i] += s }
            return o
        }
        func then(_ L: Aff) -> Aff {                                   // self ∘ L
            let n = t.count
            var M2 = [[Double]](repeating: [Double](repeating: 0, count: n), count: n), t2 = t
            for i in 0..<n {
                for j in 0..<n { var s = 0.0; for k in 0..<n { s += M[i][k] * L.M[k][j] }; M2[i][j] = s }
                var s = 0.0; for k in 0..<n { s += M[i][k] * L.t[k] }; t2[i] += s
            }
            return Aff(M: M2, t: t2)
        }
    }
    /// 子 c を親 p のちょうつがいのまわりに φ だけ開く（φ＝π/2 で平ら、0 で折りきり）。ちょうつがい h ＝ 親の向き＋子の向き
    static func hingeAff(_ c: Int, _ p: Int, _ phi: Double, _ n: Int) -> Aff {
        let (ac, sc) = cellNormal(c, n), (ap, sp) = cellNormal(p, n)
        var A = Aff.id(n)
        // R：子の向き nc を親の向き np へ（φ）。R e_ac ＝ cosφ e_ac ＋ sinφ sc sp e_ap、R e_ap ＝ −sinφ sp sc e_ac ＋ cosφ e_ap
        let c0 = cos(phi), s0 = sin(phi)
        A.M[ac][ac] = c0; A.M[ap][ac] = s0 * sc * sp
        A.M[ac][ap] = -s0 * sp * sc; A.M[ap][ap] = c0
        var h = [Double](repeating: 0, count: n); h[ac] = sc; h[ap] = sp
        let Rh = A.apply(h)
        A.t = (0..<n).map { h[$0] - Rh[$0] }
        return A
    }
    /// 木の深さ（根 0）
    static func depths(_ parent: [Int]) -> [Int] {
        parent.indices.map { i in var d = 0, k = i, guardN = 0; while parent[k] >= 0 && guardN < 20 { k = parent[k]; d += 1; guardN += 1 }; return d }
    }
    // ---- 一筆（くるくる）：いちばん長いつながりの はしっこ から、ちょうつがいを 1 個ずつ順に折る（じゅうたんを巻くように）。
    //   列から枝分かれした胞は、コースがその根元に来た時に（枝の先から）折る。動かない胞は今までどおり真ん中の胞 ----
    /// 折る順（ちょうつがいを、子の胞の番号で）。はし A＝いちばん長いつながりの片方のはし、B＝もう片方
    func courseOrder(_ parent: [Int]) -> [Int] {
        let key = courseKey(parent)
        if let c = courseCache[key] { return c }
        let n = parent.count
        var adj = [[Int]](repeating: [], count: n)
        for (i, p) in parent.enumerated() where p >= 0 { adj[i].append(p); adj[p].append(i) }
        for i in 0..<n { adj[i].sort() }
        func bfs(_ s: Int) -> ([Int], [Int]) {
            var d = [Int](repeating: -1, count: n), pr = [Int](repeating: -1, count: n); d[s] = 0; var q = [s]
            while !q.isEmpty { let u = q.removeFirst(); for v in adj[u] where d[v] < 0 { d[v] = d[u] + 1; pr[v] = u; q.append(v) } }
            return (d, pr)
        }
        let (d0, _) = bfs(0), u = (0..<n).max { (d0[$0], -$0) < (d0[$1], -$1) }!
        let (d1, pr) = bfs(u), v = (0..<n).max { (d1[$0], -$0) < (d1[$1], -$1) }!
        var path = [v]; while let last = path.last, pr[last] >= 0 { path.append(pr[last]) }   // v → u
        if courseFromB { path.reverse() }
        let onPath = Set(path)
        func child(_ a: Int, _ b: Int) -> Int { parent[a] == b ? a : b }
        var order: [Int] = []
        func branch(_ c: Int, _ from: Int) { for x in adj[c] where x != from { branch(x, c) }; order.append(child(c, from)) }
        for (k, c) in path.enumerated() {
            for x in adj[c] where !onPath.contains(x) { branch(x, c) }
            if k + 1 < path.count { order.append(child(c, path[k + 1])) }
        }
        courseCache[key] = order; courseRootCache[key] = path.last ?? 0       // ゴールの胞（転がっていく先。ここは動かない）
        return order
    }
    /// 一筆での、子の胞 i のちょうつがいの折り角（0 平ら → π/2）。1 個ずつ順に、となりと少しだけ重ねて
    func courseTheta(_ i: Int, _ order: [Int], _ t: Double? = nil) -> Double {
        let t = max(0, min(1, t ?? progress))
        guard let k = order.firstIndex(of: i), order.count > 1 else { return Self.smoother(t) * .pi / 2 }
        let S = order.count, L = min(1, 1.3 / Double(S)), step = (1 - L) / Double(S - 1), s = Double(k) * step
        return Self.smoother(max(0, min(1, (t - s) / L))) * .pi / 2
    }
    func courseKey(_ parent: [Int]) -> String { parent.map(String.init).joined(separator: ",") + (courseFromB ? "B" : "A") }
    /// 段の数（多段階）：展開図の深さ D（真ん中の胞から何個つながっているか）と、最大の段数の小さいほう。切なら 1
    func foldStages(_ D: Int) -> Int { foldStagger ? max(1, min(D, foldMaxStages)) : 1 }
    /// 深さ d のちょうつがいの折り角（0 平ら → π/2 折りきり）。多段階：深さごとに段を分けて、真ん中に近い段から順に折る。
    ///   段の数 S＝深さ D（図鑑では、いちばん長いつながりが 4〜5 個 → 2 段・6〜7 個 → 3 段・8 個 → 4 段）。ただし最大の段数まで：
    ///   D が多い時は、近い深さどうしを 1 段にまとめる（深さ d は ⌈d × S ／ D⌉ 段目）。
    ///   段どうしは少しだけ重ねる（各段の長さ 1.2／S、となりの段と 0.2／S 重なる）。ダリの十字架（2 段）は 腕 0〜0.6・ふた 0.4〜1
    func foldTheta(_ d: Int, _ D: Int) -> Double {
        let t = max(0, min(1, progress)), S = foldStages(D)
        guard S > 1 else { return Self.smoother(t) * .pi / 2 }
        let k = max(1, min(S, Int((Double(d) * Double(S) / Double(D)).rounded(.up))))
        let L = min(1, 1.2 / Double(S)), step = (1 - L) / Double(S - 1)
        let s = Double(k - 1) * step, e = s + L
        return Self.smoother(max(0, min(1, (t - s) / max(1e-6, e - s)))) * .pi / 2
    }
    /// 今の折り具合での、胞ごとの変換（組み上がりの位置 → 今の位置）。組み変わりの途中なら、前の展開図から今の展開図へ動いている途中の形
    func netTransforms(_ n: Int) -> [Aff] {
        let parent = netParent(n)
        let head: [Double] = [Double(n), progress, foldStagger ? Double(foldMaxStages) : 0.0, foldCourse ? (courseFromB ? 2 : 1) : 0]
        var key: [Double] = head + parent.map { Double($0) }
        // 組み変わりの途中も、同じコマのあいだは使い回す（fold は点ごとに呼ばれるので、1 コマに何千回。毎回計算し直すと重い）
        let mo = netMorph.flatMap { n <= 4 || $0.from5 != nil ? $0 : nil }
        if let mo { key += [-1, mo.t] + (n == 5 ? (mo.from5 ?? []) : n == 4 ? mo.from.p4 : mo.from.p3).map { Double($0) } }
        if let c = netCache[n], c.0 == key { return c.1 }
        let raw = rawTransforms(parent, n)
        let out = mo.map { morphTransforms(n, $0, to: raw) } ?? raw
        netCache[n] = (key, out)
        return out
    }
    /// 展開図 parent の、今の折り具合での変換（とりおきなし）
    func rawTransforms(_ parent: [Int], _ n: Int) -> [Aff] {
        let dep = Self.depths(parent), D = dep.max() ?? 1
        guard foldCourse else { return Self.chain(parent, n) { foldTheta(dep[$0], D) } }
        // 一筆（ころころ）：はしから 1 個ずつ巻きながら、動かない胞をゴール（反対のはし）にして、かたまりが床の上を転がっていく。
        //   転がり終わったら（進み COURSE_ROLL から）、組み上がった超立方体を 90° ずつコロンと返しながら、いつもの真ん中・いつもの向きへ
        let order = courseOrder(parent), r = courseRootCache[courseKey(parent)] ?? 0
        let tRoll = min(1, max(0, progress) / Self.COURSE_ROLL)
        let T = Self.chain(parent, n) { courseTheta($0, order, tRoll) }
        guard r != 0 else { return T }
        let F = Self.chain(parent, n) { _ in 0 }                            // 平らな展開図
        let M: Aff
        if progress < Self.COURSE_ROLL { M = F[r].then(Self.invAff(T[r])) }   // ゴールの胞を床（平らな場所）に止めたまま
        else { M = Self.courseSettle(F[r], (progress - Self.COURSE_ROLL) / (1 - Self.COURSE_ROLL), n) }
        return T.map { M.then($0) }
    }
    /// 根（胞 0）からちょうつがいをたどった変換（theta：子の胞ごとの折り角 0 平ら〜π/2）
    static func chain(_ parent: [Int], _ n: Int, _ theta: (Int) -> Double) -> [Aff] {
        var T = [Aff?](repeating: nil, count: parent.count)
        func get(_ i: Int) -> Aff {
            if let a = T[i] { return a }
            let p = parent[i]
            let a = p < 0 ? Aff.id(n) : get(p).then(hingeAff(i, p, .pi / 2 - theta(i), n))
            T[i] = a; return a
        }
        return parent.indices.map { get($0) }
    }
    static func invAff(_ A: Aff) -> Aff {
        let n = A.t.count; var B = Aff.id(n)
        for i in 0..<n { for j in 0..<n { B.M[i][j] = A.M[j][i] } }
        for i in 0..<n { var s = 0.0; for k in 0..<n { s += B.M[i][k] * A.t[k] }; B.t[i] = -s }
        return B
    }
    static let COURSE_ROLL = 0.8
    /// 転がり終わりの置き場所 F（回転は 90° の組み合わせ）から、いつもの置き場所（何もしない）へ：90° ずつコロンと返しながら、すべって真ん中へ
    static func courseSettle(_ F: Aff, _ e: Double, _ n: Int) -> Aff {
        let word = flipWord(F.M.map { $0.map { Int($0.rounded()) } }, n)
        var R = Aff.id(n).M
        func mul(_ A: [[Double]], _ B: [[Double]]) -> [[Double]] { (0..<n).map { i in (0..<n).map { j in (0..<n).reduce(0.0) { $0 + A[i][$1] * B[$1][j] } } } }
        func rot(_ g: (Int, Int, Double), _ a: Double) -> [[Double]] {
            var m = Aff.id(n).M; let c = cos(a * g.2), s = sin(a * g.2)
            m[g.0][g.0] = c; m[g.1][g.1] = c; m[g.1][g.0] = s; m[g.0][g.1] = -s; return m
        }
        let m = word.count, ee = max(0, min(1, e))
        if m > 0 {
            // 右から 1 つずつ外していく：はじめ g1…gm（＝F の回転）、おわり 何もない
            let x = ee * Double(m), j = min(m - 1, Int(x)), f = smoother(x - Double(j))
            for k in 0..<(m - j - 1) { R = mul(R, rot(word[k], .pi / 2)) }
            R = mul(R, rot(word[m - j - 1], .pi / 2 * (1 - f)))
        }
        var out = Aff.id(n); out.M = R
        let s = smoother(ee); out.t = F.t.map { $0 * (1 - s) }
        return out
    }
    /// 90° の回転（座標の面ごと・＋／−）をいくつかつないで、回転 G（符号つき並べかえ）を作る いちばん短い並び（幅優先）
    static func flipWord(_ G: [[Int]], _ n: Int) -> [(Int, Int, Double)] {
        var gens: [(Int, Int, Double)] = []
        for i in 0..<n { for j in (i + 1)..<n { gens.append((i, j, 1)); gens.append((i, j, -1)) } }
        func apply(_ A: [[Int]], _ g: (Int, Int, Double)) -> [[Int]] {            // A・R(g)
            var B = A; let s = Int(g.2)
            for r in 0..<n { B[r][g.0] = A[r][g.1] * s; B[r][g.1] = -A[r][g.0] * s }
            return B
        }
        let I = (0..<n).map { i in (0..<n).map { $0 == i ? 1 : 0 } }
        if G == I { return [] }
        var seen: [[[Int]]: [(Int, Int, Double)]] = [I: []], q = [I]
        while !q.isEmpty {
            let a = q.removeFirst()
            for g in gens {
                let b = apply(a, g)
                if seen[b] != nil { continue }
                let w = seen[a]! + [g]; seen[b] = w
                if b == G { return w }
                q.append(b)
            }
        }
        return []
    }

    // ---- 組み変わり（展開図を切りかえる時に、胞が 1 つずつ動いて新しい展開図になる）----
    //   動く胞は、4 次元の方向（立方体の展開図では紙から浮く方向）へいったん浮いて、ほかの胞をすり抜けて新しい場所へ。
    //   向きは前の向きから新しい向きへ回しながら（平らな展開図どうしなら、紙の中の回転＝3D の回転なので、なめらかに回せる）。動かない胞はそのまま
    static let MORPH_DUR = 0.85, MORPH_STAG = 0.09, MORPH_LIFT = 1.15
    /// 展開図を切りかえる（ボタン・図鑑から。組み変わりアニメが入なら動かす）
    func switchNet(_ d: NetDef, foldAfter: Bool = false) {
        guard d != net else { if foldAfter { playFold() }; return }
        let old = net
        net = d
        if netAnim && progress < 0.999 && explodeE < 0.01 {
            netMorph = NetMorph(from: old, t: 0)
            netMorphFoldAfter = foldAfter
        } else {
            netMorph = nil
            if foldAfter { playFold() }
        }
    }
    /// 5 次元の展開図を切りかえる（見本・図鑑・でたらめ・番号から。組み変わりアニメが入なら、超立方体と同じく胞が 1 つずつ動く）
    func switchNet5(_ p: [Int], no: Int? = nil, foldAfter: Bool = false) {
        let old = net5
        net5 = p; net5No = no ?? (Net5Atlas.noOf[Net5Atlas.canon(Net5Atlas.mask(p))] ?? 0)
        guard p != old else { if foldAfter { playFold() }; return }
        if netAnim && progress < 0.999 && explodeE < 0.01 {
            netMorph = NetMorph(from: net, t: 0, from5: old)
            netMorphFoldAfter = foldAfter
        } else {
            netMorph = nil
            if foldAfter { playFold() }
        }
    }
    func netMorphTick(_ dt: Double) {
        guard var mo = netMorph else { return }
        mo.t += dt
        if mo.t >= Self.MORPH_DUR + Double(mo.from5 != nil ? 9 : 7) * Self.MORPH_STAG + 0.05 {
            netMorph = nil
            if netMorphFoldAfter { netMorphFoldAfter = false; playFold() }
        } else { netMorph = mo }
    }
    /// 前の展開図（mo.from）から今の展開図（B）へ：動く胞ごとに時間差をつけて
    func morphTransforms(_ n: Int, _ mo: NetMorph, to B: [Aff]) -> [Aff] {
        let A = rawTransforms(n == 5 ? (mo.from5 ?? netParent(5)) : n == 4 ? mo.from.p4 : mo.from.p3, n)
        guard A.count == B.count else { return B }
        func same(_ a: Aff, _ b: Aff) -> Bool {
            for i in 0..<n { if abs(a.t[i] - b.t[i]) > 1e-6 { return false }; for j in 0..<n where abs(a.M[i][j] - b.M[i][j]) > 1e-6 { return false } }
            return true
        }
        var out = B, k = 0
        for i in A.indices where !same(A[i], B[i]) {
            let u = max(0, min(1, (mo.t - Double(k) * Self.MORPH_STAG) / Self.MORPH_DUR)); k += 1
            out[i] = Self.morphAff(A[i], B[i], Self.smoother(u), Self.cellNormal(i, n), n)
        }
        return out
    }
    /// 1 つの胞の変換を A から B へ（e：0〜1）。胞の真ん中を軸に回しながら動かし、途中で 4 次元の方向へ浮く
    static func morphAff(_ A: Aff, _ B: Aff, _ e: Double, _ nrm: (Int, Double), _ n: Int) -> Aff {
        let N = n - 1
        var kv = [Double](repeating: 0, count: n); kv[nrm.0] = nrm.1
        let cA = A.apply(kv), cB = B.apply(kv)
        // 相対の回転 R ＝ MB・MAᵀ
        var R = [[Double]](repeating: [Double](repeating: 0, count: n), count: n)
        for i in 0..<n { for j in 0..<n { var s = 0.0; for q in 0..<n { s += B.M[i][q] * A.M[j][q] }; R[i][j] = s } }
        var Rs = Aff.id(n).M
        if abs(R[N][N] - 1) < 1e-6 {
            if n == 5 {                                                      // 4D の回転：左と右の四元数に分けて、それぞれなめらかに
                let r4 = so4Slerp((0..<4).map { i in (0..<4).map { R[i][$0] } }, e)
                for i in 0..<4 { for j in 0..<4 { Rs[i][j] = r4[i][j] } }
            } else if n == 4 {                                                      // 3D の回転：四元数でなめらかに
                let m = simd_double3x3(rows: (0..<3).map { i in SIMD3(R[i][0], R[i][1], R[i][2]) })
                var q = simd_quatd(m); if q.real < 0 { q = simd_quatd(vector: -q.vector) }
                let r = simd_double3x3(simd_slerp(simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), q, e))
                for i in 0..<3 { for j in 0..<3 { Rs[i][j] = r[j][i] } }
            } else {                                                         // 2D の回転：角度で
                let a = atan2(R[1][0], R[0][0]) * e
                Rs[0][0] = cos(a); Rs[0][1] = -sin(a); Rs[1][0] = sin(a); Rs[1][1] = cos(a)
            }
        } else {
            // 折りかけで 4 次元の回転のとき：まぜてから直交にもどす（グラム・シュミット）
            var C = (0..<n).map { j in (0..<n).map { i in (1 - e) * (i == j ? 1 : 0) + e * R[i][j] } }   // 列 j
            for j in 0..<n {
                for p in 0..<j { let d = (0..<n).reduce(0.0) { $0 + C[j][$1] * C[p][$1] }; for i in 0..<n { C[j][i] -= d * C[p][i] } }
                let l = sqrt(C[j].reduce(0.0) { $0 + $1 * $1 }); if l > 1e-9 { for i in 0..<n { C[j][i] /= l } }
            }
            for i in 0..<n { for j in 0..<n { Rs[i][j] = C[j][i] } }
        }
        var out = Aff.id(n)
        for i in 0..<n { for j in 0..<n { var s = 0.0; for q in 0..<n { s += Rs[i][q] * A.M[q][j] }; out.M[i][j] = s } }
        let d = (0..<n).map { A.t[$0] - cA[$0] }
        for i in 0..<n {
            var s = 0.0; for q in 0..<n { s += Rs[i][q] * d[q] }
            out.t[i] = s + cA[i] + (cB[i] - cA[i]) * e + (i == N ? (n == 5 ? -MORPH_LIFT : MORPH_LIFT) * sin(.pi * e) : 0)   // 5 次元は v の奥へ（手前へ浮くと、v と w の遠近が重なって大きくふくらむので）
        }
        return out
    }
    /// 4 次元の回転 R（4×4）を、何もしない（e ＝ 0）から R（e ＝ 1）へなめらかに。
    ///   4D の回転は、左の四元数 a と右の四元数 p で x ↦ a x p と書ける（2 つの「同時に回る面」の組）。a と p を別々に球面補間する。
    ///   a と p は、R を基底 { x ↦ eᵢ x eⱼ }（16 個、たがいに直交）で展開した係数 Aᵢⱼ ＝ aᵢ pⱼ から取り出す
    static func so4Slerp(_ R: [[Double]], _ e: Double) -> [[Double]] {
        func q(_ i: Int) -> simd_quatd { var v = SIMD4<Double>(0, 0, 0, 0); v[i] = 1; return simd_quatd(vector: v) }
        var A = [[Double]](repeating: [0, 0, 0, 0], count: 4)
        for i in 0..<4 { for j in 0..<4 {
            var s = 0.0
            for k in 0..<4 { let col = (q(i) * q(k) * q(j)).vector; for r in 0..<4 { s += R[r][k] * col[r] } }
            A[i][j] = s / 4
        } }
        func n2(_ r: [Double]) -> Double { r.reduce(0) { $0 + $1 * $1 } }
        let ri = (0..<4).max { n2(A[$0]) < n2(A[$1]) } ?? 0
        guard n2(A[ri]) > 1e-12 else { return R }
        var p = simd_normalize(SIMD4(A[ri][0], A[ri][1], A[ri][2], A[ri][3]))
        var a = SIMD4<Double>(0, 0, 0, 0)
        for i in 0..<4 { var t = 0.0; for j in 0..<4 { t += A[i][j] * p[j] }; a[i] = t }
        a = simd_normalize(a)
        // (a, p) と (−a, −p) は同じ回転。回す角の合計が小さいほうを
        if acos(max(-1, min(1, a.w))) + acos(max(-1, min(1, p.w))) > .pi { a = -a; p = -p }
        func sl(_ v: SIMD4<Double>) -> simd_quatd {
            let th = acos(max(-1, min(1, v.w)))
            if th < 1e-9 { return simd_quatd(vector: SIMD4(0, 0, 0, 1)) }
            var u = SIMD4(v.x, v.y, v.z, 0)
            u = simd_length(u) > 1e-9 ? simd_normalize(u) : SIMD4(1, 0, 0, 0)
            return simd_quatd(vector: SIMD4(0, 0, 0, cos(e * th)) + u * sin(e * th))
        }
        let ae = sl(a), pe = sl(p)
        var out = R
        for k in 0..<4 { let c = (ae * q(k) * pe).vector; for r in 0..<4 { out[r][k] = c[r] } }
        return out
    }
    /// 平らな展開図での胞の真ん中（重なりの確かめ用。±1 の単位の整数）
    static func flatCenters(_ parent: [Int], _ n: Int) -> [[Int]]? {
        var T = [Aff?](repeating: nil, count: parent.count), guardN = 0
        func get(_ i: Int) -> Aff? {
            guardN += 1; if guardN > 200 { return nil }
            if let a = T[i] { return a }
            let p = parent[i]
            if p >= 0 { let (a1, _) = cellNormal(i, n), (a2, _) = cellNormal(p, n); if a1 == a2 { return nil } }   // 向かい合う胞どうしはくっつかない
            guard let pa: Aff = p < 0 ? Aff.id(n) : get(p) else { return nil }
            let a = p < 0 ? pa : pa.then(hingeAff(i, p, .pi / 2, n))
            T[i] = a; return a
        }
        var out: [[Int]] = []
        for i in parent.indices {
            guard let a = get(i) else { return nil }
            let (ax, s) = cellNormal(i, n); var c = [Double](repeating: 0, count: n); c[ax] = s
            out.append(a.apply(c).map { Int($0.rounded()) })
        }
        return out
    }
    /// 展開図として正しいか（木になっていて、平らにした時に胞が重ならない）
    static func validNet(_ parent: [Int], _ n: Int) -> Bool {
        guard parent.count == cells(n).count, parent[0] == -1, parent.dropFirst().allSatisfy({ $0 >= 0 && $0 < parent.count }) else { return false }
        guard let c = flatCenters(parent, n) else { return false }
        return Set(c.map { $0.description }).count == c.count
    }
    /// 立方体の展開図（アナロジー）：超立方体の木から ±z の胞を除き、w を立方体の z に読みかえる（真ん中 −w → −z、ふた +w → +z）。
    ///   親が除かれた胞は、さかのぼって最初に残っている（くっつける）胞へ。重なる時はラテン十字
    static func cubeAnalog(_ p4: [Int]) -> [Int] {
        let map4to3: [Int: Int] = [0: 0, 1: 1, 2: 2, 3: 3, 4: 4, 7: 5]
        var p3 = [Int](repeating: -1, count: 6)
        for (t, c) in map4to3 where c != 0 {
            let (ac, _) = cellNormal(c, 3)
            var k = p4[t], found = -1, g = 0
            while k >= 0 && g < 20 {
                if let c2 = map4to3[k] { let (a2, _) = cellNormal(c2, 3); if a2 != ac { found = c2; break } }
                k = p4[k]; g += 1
            }
            p3[c] = found >= 0 ? found : 0
        }
        return validNet(p3, 3) ? p3 : netDali.p3
    }
    /// でたらめな展開図（根から、くっつけられる胞を 1 つずつでたらめに足す。重なったらやり直し）
    static func randomNet() -> NetDef {
        for _ in 0..<2000 {
            var p = [Int](repeating: -2, count: 8); p[0] = -1
            var inTree = [0]
            while inTree.count < 8 {
                var cand: [(Int, Int)] = []
                for u in inTree { for v in 0..<8 where p[v] == -2 { if cellNormal(u, 4).0 != cellNormal(v, 4).0 { cand.append((u, v)) } } }
                guard let (u, v) = cand.randomElement() else { break }
                p[v] = u; inTree.append(v)
            }
            if validNet(p, 4) { return NetDef(name: "でたらめ", p4: p, p3: cubeAnalog(p)) }
        }
        return netDali
    }
}
