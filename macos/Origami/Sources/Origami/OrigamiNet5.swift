// 5 次元 β の展開図図鑑：5 次元超立方体の展開図を全部（回したり裏返したりして重なるものは 1 つと数えて 9,694 種類）。
//   10 個の胞（超立方体）を点に、くっつけられる（向かい合っていない）胞どうしを線にした図（線 40 本）で、
//   9 本の線で 10 個を輪を作らずにつなぐ「木」が展開図。木は全部で 32,768,000 通り（2⁸ × 4⁵ × 5³）。
//   5 次元超立方体を回したり裏返したりする 3,840 通り（軸の入れかえ 120 × 向きの反転 32）で重なる木を 1 つにまとめる。
//   全部の木を 3,840 通りずつ比べると 1,260 億回になるので、小さな木から 1 本ずつ枝を足しながら、そのつど同じ形をまとめて数える
//   （どの木も、葉を 1 つずつ取っていけば小さな木から作れるので、もれなく数えられる）。
//   数えるのは時間がかかるので、確かめの時に 1 回だけ数えて OrigamiNet5Data.swift に書き出し、アプリはその表を読むだけ。
//   平らにした時に胞が重ならないかは、4 次元のマス目で調べる（平らな展開図の胞は、どれもマス目にぴったり並ぶ）。
//   見本の向き：木のまん中の胞を真ん中の胞（−v）に置き、平らにした形が たて（y）に長く → 横（x）→ 奥（z）→ w の順に短くなる向き
import Foundation
import SwiftUI

enum Net5Atlas {
    // ---- 胞のつながりの図 ----
    /// 胞の番号 → 向き（軸・±1）
    static let cellAS: [(Int, Int)] = (0..<10).map { let (a, s) = OrigamiState.cellNormal($0, 5); return (a, s > 0 ? 1 : -1) }
    /// 向き → 胞の番号（[軸][− 0・＋ 1]）
    static let cellOf: [[Int]] = {
        var t = [[Int]](repeating: [0, 0], count: 5)
        for i in 0..<10 { let (a, s) = cellAS[i]; t[a][s > 0 ? 1 : 0] = i }
        return t
    }()
    /// くっつけられる胞どうし（40 本）と、その番号（向かい合う胞は −1）
    static let pairs: [(Int, Int)] = {
        var p: [(Int, Int)] = []
        for i in 0..<10 { for j in (i + 1)..<10 where cellAS[i].0 != cellAS[j].0 { p.append((i, j)) } }
        return p
    }()
    static let pairIdx: [[Int]] = {
        var t = [[Int]](repeating: [Int](repeating: -1, count: 10), count: 10)
        for (k, (i, j)) in pairs.enumerated() { t[i][j] = k; t[j][i] = k }
        return t
    }()
    /// 回す・裏返す 3,840 通り：胞の入れかえ（胞 c → g[c]）
    static let group: [[Int]] = {
        var perms: [[Int]] = []
        func gen(_ a: [Int], _ rest: [Int]) { if rest.isEmpty { perms.append(a); return }; for (k, x) in rest.enumerated() { var r = rest; r.remove(at: k); gen(a + [x], r) } }
        gen([], [0, 1, 2, 3, 4])
        var out: [[Int]] = []
        for pm in perms { for sg in 0..<32 {
            out.append((0..<10).map { c in let (a, s) = cellAS[c]; let s2 = (sg >> a) & 1 == 1 ? -s : s; return cellOf[pm[a]][s2 > 0 ? 1 : 0] })
        } }
        return out
    }()
    /// それぞれの回し方で、線の番号がどこへ移るか
    static let edgeMaps: [[UInt8]] = group.map { g in pairs.map { (i, j) in UInt8(pairIdx[g[i]][g[j]]) } }

    /// 木（線の集まり）の決まった形：3,840 通りに回した中で、いちばん小さい数
    static func canon(_ m: UInt64) -> UInt64 {
        var bits: [Int] = []; var x = m
        while x != 0 { let b = x.trailingZeroBitCount; bits.append(b); x &= x - 1 }
        var best = UInt64.max
        for em in edgeMaps {
            var r: UInt64 = 0
            for b in bits { r |= 1 << UInt64(em[b]) }
            if r < best { best = r }
        }
        return best
    }
    /// 全部数える（小さな木から 1 本ずつ）。返り値：線 9 本の木（決まった形）・線の本数ごとの種類の数
    static func enumerate() -> ([UInt64], [Int]) {
        var level: Set<UInt64> = [canon(1)]                                   // 線 1 本（どの線も同じ形）
        var counts = [1]
        for _ in 2...9 {
            let reps = Array(level), lock = NSLock()
            var next = Set<UInt64>()
            let chunks = 64, per = (reps.count + chunks - 1) / chunks
            DispatchQueue.concurrentPerform(iterations: chunks) { ci in
                var local = Set<UInt64>()
                let lo = ci * per, hi = min(reps.count, lo + per)
                if lo >= hi { return }
                for m in reps[lo..<hi] {
                    var inT = [Bool](repeating: false, count: 10)
                    var x = m; while x != 0 { let b = x.trailingZeroBitCount; inT[pairs[b].0] = true; inT[pairs[b].1] = true; x &= x - 1 }
                    for u in 0..<10 where inT[u] { for v in 0..<10 where !inT[v] {
                        let e = pairIdx[u][v]; if e < 0 { continue }
                        local.insert(canon(m | (1 << UInt64(e))))
                    } }
                }
                lock.lock(); next.formUnion(local); lock.unlock()
            }
            level = next; counts.append(level.count)
        }
        return (Array(level), counts)
    }

    // ---- 平らにする（転がす）----
    /// 胞の向き（立方体の軸 d の ＋ が、平らな場所のどの軸の ±か）
    typealias Frame = [(Int, Int)]
    /// 平らにした時の胞の位置（4 次元のマス目。真ん中の胞が原点）。重なったら nil
    static func flat(_ parent: [Int]) -> [[Int]]? {
        var pos = [[Int]?](repeating: nil, count: 10), fr = [Frame?](repeating: nil, count: 10)
        pos[0] = [0, 0, 0, 0]; fr[0] = (0..<5).map { ($0, 1) }
        func get(_ c: Int) -> Bool {
            if pos[c] != nil { return true }
            let p = parent[c]; guard p >= 0, get(p), let Mp = fr[p], let pp = pos[p] else { return false }
            let (ac, sc) = cellAS[c], (sd, s0) = Mp[ac], ss = s0 * sc
            guard sd != 4 else { return false }
            var q = pp; q[sd] += ss; pos[c] = q
            // 転がす：進む向き（sd・ss）が下（v の −）へ、下が −進む向きへ、上が進む向きへ
            fr[c] = Mp.map { (d, s) -> (Int, Int) in
                if d == sd { return s == ss ? (4, -1) : (4, 1) }
                if d == 4 { return s < 0 ? (sd, -ss) : (sd, ss) }
                return (d, s)
            }
            return true
        }
        for c in 0..<10 { if !get(c) { return nil } }
        let P = pos.map { $0! }
        return Set(P).count == 10 ? P : nil
    }
    /// 木 → 親の並び（胞 r を根に）
    static func parents(_ adj: [[Int]], root: Int) -> [Int] {
        var par = [Int](repeating: -2, count: 10); par[root] = -1; var q = [root]
        while !q.isEmpty { let u = q.removeFirst(); for v in adj[u] where par[v] == -2 { par[v] = u; q.append(v) } }
        return par
    }
    static func adjacency(_ m: UInt64) -> [[Int]] {
        var adj = [[Int]](repeating: [], count: 10); var x = m
        while x != 0 { let b = x.trailingZeroBitCount; let (i, j) = pairs[b]; adj[i].append(j); adj[j].append(i); x &= x - 1 }
        return adj
    }
    /// 見本の向きにした親の並び（根＝胞 0）
    static func orient(_ m: UInt64) -> [Int] {
        var adj = adjacency(m)
        // 木のまん中：いちばん長いつながりの真ん中の胞（2 つなら、くっつく数の多いほう）
        func far(_ s: Int) -> ([Int], [Int]) {
            var d = [Int](repeating: -1, count: 10), pr = [Int](repeating: -1, count: 10); d[s] = 0; var q = [s]
            while !q.isEmpty { let u = q.removeFirst(); for v in adj[u] where d[v] < 0 { d[v] = d[u] + 1; pr[v] = u; q.append(v) } }
            return (d, pr)
        }
        let (d0, _) = far(adj.firstIndex { !$0.isEmpty } ?? 0), a = (0..<10).max { d0[$0] < d0[$1] }!
        let (d1, pr) = far(a), b = (0..<10).max { d1[$0] < d1[$1] }!
        var path = [b]; while let l = path.last, pr[l] >= 0 { path.append(pr[l]) }
        var ctr = path[path.count / 2]
        if path.count % 2 == 0 { let c2 = path[path.count / 2 - 1]; if adj[c2].count > adj[ctr].count { ctr = c2 } }
        // まん中の胞を胞 0（−v）へ
        let g0 = group.first { $0[ctr] == 0 }!
        func relabel(_ g: [Int]) { var n = [[Int]](repeating: [], count: 10); for u in 0..<10 { n[g[u]] = adj[u].map { g[$0] } }; adj = n }
        relabel(g0)
        guard let P = flat(parents(adj, root: 0)) else { return parents(adj, root: 0) }
        // 平らな形の長さ：長い軸を y・x・z・w の順に、胞の多い側を ＋ に（v は動かさない）
        let ext = (0..<4).map { d in (P.map { $0[d] }.max()! - P.map { $0[d] }.min()!, d) }
        let order = ext.sorted { $0.0 != $1.0 ? $0.0 > $1.0 : $0.1 < $1.1 }.map(\.1), target = [1, 0, 2, 3]
        var axMap = [0, 1, 2, 3, 4], flip = [1, 1, 1, 1, 1]
        for k in 0..<4 { axMap[order[k]] = target[k]; if P.reduce(0, { $0 + $1[order[k]] }) < 0 { flip[order[k]] = -1 } }
        let g1 = (0..<10).map { c -> Int in let (a, s) = cellAS[c]; return cellOf[axMap[a]][s * flip[a] > 0 ? 1 : 0] }
        relabel(g1)
        return parents(adj, root: 0)
    }

    // ---- 図鑑（OrigamiNet5Data.swift の表から）----
    struct Entry { let no: Int; let parent: [Int]; let longest: Int; let maxDeg: Int; let canon: UInt64 }
    static let entries: [Entry] = {
        let s = Array(Net5Data.raw.utf8), W = 19, n = s.count / W
        var out: [Entry] = []; out.reserveCapacity(n)
        for k in 0..<n {
            let par = [-1] + (0..<9).map { Int(s[k * W + $0]) - 48 }
            let cm = UInt64(String(decoding: s[(k * W + 9)..<(k * W + W)], as: UTF8.self), radix: 16) ?? 0
            var adj = [[Int]](repeating: [], count: 10)
            for c in 1..<10 { adj[c].append(par[c]); adj[par[c]].append(c) }
            out.append(Entry(no: k + 1, parent: par, longest: longest(adj), maxDeg: adj.map(\.count).max() ?? 0, canon: cm))
        }
        return out
    }()
    /// 決まった形 → 図鑑の番号
    static let noOf: [UInt64: Int] = Dictionary(entries.map { ($0.canon, $0.no) }, uniquingKeysWith: { a, _ in a })
    /// 親の並び → 線の集まり
    static func mask(_ parent: [Int]) -> UInt64 {
        var m: UInt64 = 0
        for c in parent.indices where parent[c] >= 0 { let e = pairIdx[c][parent[c]]; if e >= 0 { m |= 1 << UInt64(e) } }
        return m
    }
    /// いちばん長いつながり（一続きの胞の数）
    static func longest(_ adj: [[Int]]) -> Int {
        func far(_ s: Int) -> (Int, Int) {
            var d = [Int](repeating: -1, count: adj.count); d[s] = 0; var q = [s], best = (s, 0)
            while !q.isEmpty { let u = q.removeFirst(); if d[u] > best.1 { best = (u, d[u]) }; for v in adj[u] where d[v] < 0 { d[v] = d[u] + 1; q.append(v) } }
            return best
        }
        return far(far(0).0).1 + 1
    }
    /// 並び：いちばん長いつながりの短い順 → 1 つの胞にくっつく数の多い順 → くっつく数の並び → 決まった形の数
    static func sortKey(_ m: UInt64) -> ([Int], UInt64) {
        let adj = adjacency(m), deg = adj.map(\.count).sorted(by: >)
        return ([longest(adj), -deg[0]] + deg.map { -$0 }, m)
    }
    /// 数えて、表（OrigamiNet5Data.swift）を書き出す（確かめの時に 1 回だけ）
    static func writeData(_ path: String) {
        let t0 = Date()
        let (reps, counts) = enumerate()
        let sorted = reps.map { (sortKey($0), $0) }.sorted { a, b in a.0.0 != b.0.0 ? a.0.0.lexicographicallyPrecedes(b.0.0) : a.0.1 < b.0.1 }.map(\.1)
        var raw = "", bad = 0
        for m in sorted {
            let p = orient(m)
            if flat(p) == nil { bad += 1 }
            raw += p[1...].map { String($0) }.joined() + String(format: "%010llx", m)
        }
        let src = """
        // 5 次元超立方体の展開図 \(sorted.count) 種類（OrigamiNet5.swift の Net5Atlas.writeData が数えて書き出した表。手で直さない）。
        //   1 種類 19 文字＝胞 1〜9 の親の番号（胞 0 ＝真ん中の胞 −v が根）9 文字＋決まった形（線の集まり、16 進）10 文字。並びは図鑑の番号の順
        enum Net5Data {
            static let raw = "\(raw)"
        }

        """
        try? src.write(toFile: path, atomically: true, encoding: .utf8)
        print(String(format: "5 次元の展開図：線の本数ごとの種類 %@・全部で %d 種類（重なる %d）・%.1f 秒", counts.map(String.init).joined(separator: " "), sorted.count, bad, Date().timeIntervalSince(t0)))
    }
}

extension OrigamiState {
    /// 5 次元の展開図の見本（超立方体の見本と同じ名前・同じ考え）
    static let net5Presets: [(String, [Int])] = [
        ("ダリの十字架", p5Dali),
        // （超立方体の「塔」は、5 次元ではダリの十字架と同じ形になるので入れない）
        // 階段：+y の上にふた、ふたの横に ±x、真ん中の横に ±z・±w と −y
        ("階段", [-1, 0, 0, 9, 9, 0, 0, 0, 0, 1]),
        // ねじれ：+x の先に +y、+y の先にふた、ふたの先に −z、−z の先に −w、ほかは真ん中に
        ("ねじれ", [-1, 3, 0, 0, 0, 0, 9, 0, 6, 1]),
        // 一続き：10 個が一列につながる（図鑑のいちばん最後）
        ("一続き（10 個）", Net5Atlas.entries.last?.parent ?? p5Dali),
    ]
    /// 5 次元の展開図をえらぶ（no：図鑑の番号。見本・でたらめも図鑑の中なら番号を出す）
    func setNet5(_ p: [Int]) { switchNet5(p) }
    func net5Step(_ d: Int) {
        let n = Net5Atlas.entries.count; guard n > 0 else { return }
        let i = ((max(1, net5No) - 1 + d) % n + n) % n
        switchNet5(Net5Atlas.entries[i].parent, no: i + 1)
    }
    func net5Random() {
        let n = Net5Atlas.entries.count; guard n > 0 else { return }
        let i = Int.random(in: 0..<n); switchNet5(Net5Atlas.entries[i].parent, no: i + 1)
    }
}

// ---- 5 次元の図鑑の画面 ----
/// 5 次元の展開図の小さな絵：平らにした形（4 次元のマス目 x・y・z・w）を、x・y・z は積み木で、w はななめ上へずらして描く
///   （ウェブ版の 4D展開と同じ考え：w が 3D に出てきて、±w の胞がななめに見える）
struct NetThumb5: View {
    let flat: [[Int]]
    let cols: [Color]
    var body: some View {
        Canvas { ctx, size in
            guard flat.count == 10 else { return }
            let c30 = 0.8660254, s30 = 0.5
            // w の 1 マス ＝ 3D の (0.55, 0.45, −0.55)：x・y・z のどのマスとも重ならない向き
            func p3(_ c: [Int]) -> (Double, Double, Double) { (Double(c[0]) + 0.55 * Double(c[3]), Double(c[1]) + 0.45 * Double(c[3]), Double(c[2]) - 0.55 * Double(c[3])) }
            func pr(_ x: Double, _ y: Double, _ z: Double) -> CGPoint { CGPoint(x: (x - z) * c30, y: (x + z) * s30 - y) }
            var lo = CGPoint(x: 1e9, y: 1e9), hi = CGPoint(x: -1e9, y: -1e9)
            for c in flat { let (x, y, z) = p3(c); for dx in 0...1 { for dy in 0...1 { for dz in 0...1 {
                let p = pr(x + Double(dx), y + Double(dy), z + Double(dz))
                lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
            } } } }
            let pad = 4.0, sc = min((size.width - 2 * pad) / max(1e-6, hi.x - lo.x), (size.height - 2 * pad) / max(1e-6, hi.y - lo.y))
            let ox = (size.width - (hi.x - lo.x) * sc) / 2 - lo.x * sc, oy = (size.height - (hi.y - lo.y) * sc) / 2 - lo.y * sc
            // 奥から手前へ（x＋y＋z の小さい順）
            let order = flat.indices.sorted { let a = p3(flat[$0]), b = p3(flat[$1]); return (a.0 + a.1 + a.2, $0) < (b.0 + b.1 + b.2, $1) }
            for i in order {
                let (x, y, z) = p3(flat[i]), col = i < cols.count ? cols[i] : .gray
                // ±w にずれた胞は少し小さく（w の向こう・手前にあるのがわかるように）
                let g = flat[i][3] == 0 ? 0.13 : 0.24
                func P(_ dx: Int, _ dy: Int, _ dz: Int) -> CGPoint {
                    func f(_ v: Double, _ d: Int) -> Double { v + (d == 0 ? g : 1 - g) }
                    let p = pr(f(x, dx), f(y, dy), f(z, dz)); return CGPoint(x: p.x * sc + ox, y: p.y * sc + oy)
                }
                let faces: [([CGPoint], Double)] = [
                    ([P(0, 1, 0), P(1, 1, 0), P(1, 1, 1), P(0, 1, 1)], 1.0),
                    ([P(1, 0, 0), P(1, 1, 0), P(1, 1, 1), P(1, 0, 1)], 0.74),
                    ([P(0, 0, 1), P(1, 0, 1), P(1, 1, 1), P(0, 1, 1)], 0.56),
                ]
                for (q, k) in faces {
                    var path = Path(); path.addLines(q); path.closeSubpath()
                    ctx.fill(path, with: .color(col))
                    ctx.fill(path, with: .color(.black.opacity(1 - k)))
                    ctx.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 0.6)
                }
                if i == 0 {                                                    // 真ん中の胞（動かない胞）に白い点
                    let t = P(0, 1, 0), u = P(1, 1, 1)
                    ctx.fill(Path(ellipseIn: CGRect(x: (t.x + u.x) / 2 - 1.6, y: (t.y + u.y) / 2 - 1.6, width: 3.2, height: 3.2)), with: .color(.white))
                }
            }
        }
    }
}

/// 5 次元の展開図図鑑（9,694 種類）：いちばん長いつながりの長さごとに並べる。見えている所だけ描く
struct NetAtlas5Sheet: View {
    @ObservedObject var st: OrigamiState
    @AppStorage("atlasFold") var foldOnPick = true
    static let groups: [(Int, [Net5Atlas.Entry])] = Dictionary(grouping: Net5Atlas.entries, by: { $0.longest }).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    func pick(_ e: Net5Atlas.Entry) {
        if foldOnPick && st.progress > 0.05 { st.netMorph = nil; st.net5 = e.parent; st.net5No = e.no; st.playing = false; st.loop = false; st.progress = 0; st.playFold() }
        else { st.switchNet5(e.parent, no: e.no, foldAfter: foldOnPick) }
        st.atlas5Open = false
    }
    var body: some View {
        let cols = st.cellColors(5).map { PaletteEditor.color($0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("5 次元の展開図図鑑（\(Net5Atlas.entries.count) 種類）", systemImage: "books.vertical").font(.system(size: 14, weight: .bold))
                Spacer()
                Toggle("選んだら折ってみせる", isOn: $foldOnPick).font(.caption)
                Button("閉じる") { st.atlas5Open = false }.keyboardShortcut(.cancelAction)
            }
            Text("5 次元超立方体の展開図は全部で 9,694 種類（回したり裏返したりして重なるものは 1 つと数える）。10 個の超立方体のくっつき方（木）は 32,768,000 通りあって、それを 3,840 通りの向きでまとめた数。絵は平らにした 4 次元の形で、w の向きはななめ上にずらして（少し小さく）描いている。白い点は真ん中の胞（折る時に動かない胞）。押すとその展開図になる")
                .font(.caption).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { sp in
                HStack(spacing: 6) {
                    Text("いちばん長いつながり").font(.caption).foregroundStyle(UIC.sub)
                    ForEach(Self.groups, id: \.0) { g in
                        Button("\(g.0) 個（\(g.1.count)）") { sp.scrollTo("h\(g.0)", anchor: .top) }.font(.caption)
                    }
                }
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6, pinnedViews: [.sectionHeaders]) {
                        ForEach(Self.groups, id: \.0) { g in
                            Section {
                                ForEach(g.1, id: \.no) { e in
                                    let on = st.net5No == e.no
                                    VStack(spacing: 2) {
                                        NetThumb5(flat: Net5Atlas.flat(e.parent) ?? [], cols: cols).frame(height: 74)
                                        Text("No.\(e.no)").font(.system(size: 10, weight: on ? .bold : .regular).monospacedDigit()).foregroundStyle(on ? UIC.cyan : UIC.text).lineLimit(1)
                                    }
                                    .padding(4)
                                    .background(on ? UIC.cyan.opacity(0.16) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? UIC.cyan.opacity(0.8) : UIC.line))
                                    .contentShape(Rectangle())
                                    .onTapGesture { pick(e) }
                                    .id(e.no)
                                }
                            } header: {
                                Text("いちばん長いつながり：胞 \(g.0) 個（\(g.1.count) 種類）").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.amber)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).background(UIC.panel)
                                    .id("h\(g.0)")
                            }
                        }
                    }
                }
                .onAppear { if st.net5No > 0 { let c = st.net5No; DispatchQueue.main.async { sp.scrollTo(c, anchor: .center) } } }
            }
        }
        .padding(14)
        #if os(macOS)
        .frame(width: 760, height: 660)
        #endif
        .background(UIC.panel).preferredColorScheme(.dark)
    }
}
