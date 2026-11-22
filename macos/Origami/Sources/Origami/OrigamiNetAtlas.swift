// 展開図図鑑：超立方体の展開図 261 種類を全部。
//   8 個の胞を点に、くっつけられる（向かい合っていない）胞どうしを線にした図（線 24 本）で、
//   7 本の線で 8 個を輪を作らずにつなぐ「木」を全部作る（82,944 通り）。
//   超立方体を回したり裏返したりする 384 通り（軸の入れかえ 24 × 向きの反転 16）で重なる木を 1 つにまとめると 261 種類（ターニー 1984）。
//   平らに広げて胞が重ならないかも 1 つずつ確かめる（--ogpng の数え上げ）。
//   並び：いちばん長いつながり（一続きの胞の数）の短い順 → 1 つの胞にくっつく数の多い順 → くっつく数の並び → 線の番号。No.1 はダリの十字架。
//   見本の向き：木のまん中の胞を真ん中の胞（−w）に置き、平らにした形が たて（y）に長く → 横（x）に長く → 奥（z）に薄い 向きを選ぶ
import Foundation
import SwiftUI

/// 図鑑の 1 種類
struct NetAtlasEntry: Identifiable {
    let id: Int                         // 番号（1〜261）
    let def: NetDef
    let longest: Int                    // いちばん長いつながり（胞の数）
    let maxDeg: Int                     // 1 つの胞にくっつく数のいちばん多い所
    let valid: Bool                     // 平らにして重ならない
    let flat: [SIMD3<Int>]              // 平らにした時の胞の位置（胞 1 個 ＝ 1、xyz）
}

enum NetAtlas {
    // ---- 胞のつながりの図 ----
    /// 胞の番号 ↔ 向き（軸・±）
    static let cellIdx: [[Int]] = {
        var t = [[Int]](repeating: [0, 0], count: 4)
        for i in 0..<8 { let (a, s) = OrigamiState.cellNormal(i, 4); t[a][s > 0 ? 1 : 0] = i }
        return t
    }()
    /// くっつけられる胞どうし（24 本）と、その番号
    static let edges: [(Int, Int)] = {
        var e: [(Int, Int)] = []
        for i in 0..<8 { for j in (i + 1)..<8 where OrigamiState.cellNormal(i, 4).0 != OrigamiState.cellNormal(j, 4).0 { e.append((i, j)) } }
        return e
    }()
    static let edgeID: [Int] = {
        var t = [Int](repeating: -1, count: 64)
        for (k, e) in edges.enumerated() { t[e.0 * 8 + e.1] = k; t[e.1 * 8 + e.0] = k }
        return t
    }()
    /// 超立方体の対称（384 通り）：胞の番号の入れかえ
    static let syms: [[Int]] = {
        var perms: [[Int]] = []
        func gen(_ a: [Int], _ rest: [Int]) { if rest.isEmpty { perms.append(a); return }; for (k, r) in rest.enumerated() { var b = rest; b.remove(at: k); gen(a + [r], b) } }
        gen([], [0, 1, 2, 3])
        var out: [[Int]] = []
        for p in perms { for f in 0..<16 {
            out.append((0..<8).map { i in
                let (a, s) = OrigamiState.cellNormal(i, 4), b = p[a], sg = (f >> b) & 1 == 1 ? -s : s
                return cellIdx[b][sg > 0 ? 1 : 0]
            })
        } }
        return out
    }()
    /// 対称ごとの、線の番号の入れかえ
    static let edgePerm: [[Int]] = syms.map { g in edges.map { e in edgeID[g[e.0] * 8 + g[e.1]] } }

    static func image(_ m: UInt32, _ g: Int) -> UInt32 {
        var o: UInt32 = 0, x = m
        let P = edgePerm[g]
        while x != 0 { let b = x.trailingZeroBitCount; o |= 1 << UInt32(P[b]); x &= x - 1 }
        return o
    }
    /// 対称で重なるもののうち、いちばん小さい番号（その種類の印）
    static func canon(_ m: UInt32) -> UInt32 { var best = m; for g in 0..<syms.count { best = min(best, image(m, g)) }; return best }
    /// 親の並び（p4）→ 線の組
    static func mask(_ p4: [Int]) -> UInt32? {
        var m: UInt32 = 0
        for (i, p) in p4.enumerated() where p >= 0 { let e = edgeID[i * 8 + p]; if e < 0 { return nil }; m |= 1 << UInt32(e) }
        return m.nonzeroBitCount == 7 ? m : nil
    }
    /// 線の組 → 胞 0 を根にした親の並び
    static func parents(_ m: UInt32) -> [Int] {
        var adj = [[Int]](repeating: [], count: 8)
        for (k, e) in edges.enumerated() where m & (1 << UInt32(k)) != 0 { adj[e.0].append(e.1); adj[e.1].append(e.0) }
        var p = [Int](repeating: -2, count: 8); p[0] = -1
        var q = [0]
        while !q.isEmpty { let u = q.removeFirst(); for v in adj[u].sorted() where p[v] == -2 { p[v] = u; q.append(v) } }
        return p
    }

    // ---- 全部を作る ----
    struct Built { let entries: [NetAtlasEntry]; let trees: Int; let byCanon: [UInt32: Int] }
    static let built: Built = build()
    static var all: [NetAtlasEntry] { built.entries }
    static var count: Int { built.entries.count }

    static func build() -> Built {
        // 1) 木を全部：線を番号の順に足していき、輪ができる線は足さない（つながりの組の印で見る）
        var trees = 0, seen = Set<UInt32>(), reps: [UInt32] = []
        func rec(_ start: Int, _ k: Int, _ comp: [Int], _ m: UInt32) {
            if k == 7 {
                trees += 1
                if !seen.contains(m) {                                           // 新しい種類：重なるもの（384 通り）を全部覚える
                    var orbit = Set<UInt32>(); for g in 0..<syms.count { orbit.insert(image(m, g)) }
                    seen.formUnion(orbit); reps.append(orbit.min()!)
                }
                return
            }
            guard start < edges.count, edges.count - start >= 7 - k else { return }
            for e in start..<edges.count {
                if edges.count - e < 7 - k { break }
                let (a, b) = edges[e], ca = comp[a], cb = comp[b]
                if ca == cb { continue }
                var c2 = comp; for i in 0..<8 where c2[i] == cb { c2[i] = ca }
                rec(e + 1, k + 1, c2, m | (1 << UInt32(e)))
            }
        }
        rec(0, 0, Array(0..<8), 0)

        // 2) 種類ごとに：長さ・くっつく数・見本の向き
        struct Info { let rep: UInt32; let longest: Int; let deg: [Int]; let p4: [Int]; let valid: Bool; let flat: [SIMD3<Int>] }
        var infos: [Info] = []
        for rep in reps {
            var adj = [[Int]](repeating: [], count: 8)
            for (k, e) in edges.enumerated() where rep & (1 << UInt32(k)) != 0 { adj[e.0].append(e.1); adj[e.1].append(e.0) }
            func ecc(_ s: Int) -> Int {
                var d = [Int](repeating: -1, count: 8); d[s] = 0; var q = [s]
                while !q.isEmpty { let u = q.removeFirst(); for v in adj[u] where d[v] < 0 { d[v] = d[u] + 1; q.append(v) } }
                return d.max()!
            }
            let E = (0..<8).map(ecc), deg = adj.map { $0.count }
            let center = (0..<8).min { (E[$0], -deg[$0], $0) < (E[$1], -deg[$1], $1) }!
            // まん中の胞を胞 0 へ写す対称のうち、平らな形がいちばん見やすい向き
            var best: (key: [Int], p4: [Int], flat: [[Int]]?)? = nil
            for g in 0..<syms.count where syms[g][center] == 0 {
                let p4 = parents(image(rep, g))
                let fc = OrigamiState.flatCenters(p4, 4)
                var key: [Int]
                if let fc = fc {
                    func ext(_ a: Int) -> Int { let v = fc.map { $0[a] }; return (v.max()! - v.min()!) / 2 + 1 }
                    key = [-ext(1), -ext(0), ext(2)]
                } else { key = [99, 99, 99] }
                key += p4
                if best == nil || key.lexicographicallyPrecedes(best!.key) { best = (key, p4, fc) }
            }
            let b = best!
            let valid = b.flat != nil && Set(b.flat!.map { $0.description }).count == 8
            let flat = (b.flat ?? []).map { SIMD3<Int>($0[0] / 2, $0[1] / 2, $0[2] / 2) }
            infos.append(Info(rep: rep, longest: E.max()! + 1, deg: deg.sorted(by: >), p4: b.p4, valid: valid, flat: flat))
        }
        infos.sort { a, b in
            if a.longest != b.longest { return a.longest < b.longest }
            if a.deg != b.deg { return a.deg.lexicographicallyPrecedes(b.deg, by: >) }
            return a.rep < b.rep
        }
        // 見本の展開図の名前
        var names: [UInt32: String] = [:]
        for d in OrigamiState.netPresets { if let m = mask(d.p4), names[canon(m)] == nil { names[canon(m)] = d.name } }
        var entries: [NetAtlasEntry] = [], byCanon: [UInt32: Int] = [:]
        for (k, f) in infos.enumerated() {
            let no = k + 1, nm = names[f.rep].map { "No.\(no) \($0)" } ?? "No.\(no)"
            entries.append(NetAtlasEntry(id: no, def: NetDef(name: nm, p4: f.p4, p3: OrigamiState.cubeAnalog(f.p4)), longest: f.longest, maxDeg: f.deg[0], valid: f.valid, flat: f.flat))
            byCanon[f.rep] = no
        }
        return Built(entries: entries, trees: trees, byCanon: byCanon)
    }
    /// 展開図の図鑑の番号（どんな向き・根でも同じ種類なら同じ番号）
    static func number(of p4: [Int]) -> Int? { mask(p4).flatMap { built.byCanon[canon($0)] } }
    /// 番号を d だけ進めた展開図
    static func step(from p4: [Int], _ d: Int) -> NetDef {
        let n = count, k = number(of: p4) ?? (d > 0 ? 0 : 1)
        return all[((k - 1 + d) % n + n) % n].def
    }
}

// ---- 図鑑の画面 ----
/// 平らにした展開図の小さな絵（胞を立方体の積み木で、斜め上から）
struct NetThumb: View {
    let flat: [SIMD3<Int>]
    let cols: [Color]
    var body: some View {
        Canvas { ctx, size in
            guard !flat.isEmpty else { return }
            let c30 = 0.8660254, s30 = 0.5
            func pr(_ x: Double, _ y: Double, _ z: Double) -> CGPoint { CGPoint(x: (x - z) * c30, y: (x + z) * s30 - y) }
            var lo = CGPoint(x: 1e9, y: 1e9), hi = CGPoint(x: -1e9, y: -1e9)
            for c in flat { for dx in 0...1 { for dy in 0...1 { for dz in 0...1 {
                let p = pr(Double(c.x + dx), Double(c.y + dy), Double(c.z + dz))
                lo.x = min(lo.x, p.x); lo.y = min(lo.y, p.y); hi.x = max(hi.x, p.x); hi.y = max(hi.y, p.y)
            } } } }
            let pad = 4.0, sc = min((size.width - 2 * pad) / max(1e-6, hi.x - lo.x), (size.height - 2 * pad) / max(1e-6, hi.y - lo.y))
            let ox = (size.width - (hi.x - lo.x) * sc) / 2 - lo.x * sc, oy = (size.height - (hi.y - lo.y) * sc) / 2 - lo.y * sc
            // 積み木は少し小さく（すき間から奥の胞も見えるように）。c：胞の位置、d：角（0 か 1）
            let gap = 0.13
            func P(_ c: SIMD3<Int>, _ dx: Int, _ dy: Int, _ dz: Int) -> CGPoint {
                func g(_ v: Int, _ d: Int) -> Double { Double(v) + (d == 0 ? gap : 1 - gap) }
                let p = pr(g(c.x, dx), g(c.y, dy), g(c.z, dz)); return CGPoint(x: p.x * sc + ox, y: p.y * sc + oy)
            }
            // 奥から手前へ（x＋y＋z の小さい順）
            let order = flat.indices.sorted { let a = flat[$0], b = flat[$1]; return (a.x + a.y + a.z, $0) < (b.x + b.y + b.z, $1) }
            for i in order {
                let c = flat[i], col = i < cols.count ? cols[i] : .gray
                let faces: [([CGPoint], Double)] = [
                    ([P(c, 0, 1, 0), P(c, 1, 1, 0), P(c, 1, 1, 1), P(c, 0, 1, 1)], 1.0),     // 上
                    ([P(c, 1, 0, 0), P(c, 1, 1, 0), P(c, 1, 1, 1), P(c, 1, 0, 1)], 0.74),    // 右（+x）
                    ([P(c, 0, 0, 1), P(c, 1, 0, 1), P(c, 1, 1, 1), P(c, 0, 1, 1)], 0.56),    // 手前（+z）
                ]
                for (q, k) in faces {
                    var path = Path(); path.addLines(q); path.closeSubpath()
                    ctx.fill(path, with: .color(col.opacity(1)))
                    ctx.fill(path, with: .color(.black.opacity(1 - k)))
                    ctx.stroke(path, with: .color(.black.opacity(0.55)), lineWidth: 0.6)
                }
                if i == 0 {                                                    // 真ん中の胞（動かない胞）に白い点
                    let t = P(c, 0, 1, 0), u = P(c, 1, 1, 1)
                    let m = CGPoint(x: (t.x + u.x) / 2, y: (t.y + u.y) / 2)
                    ctx.fill(Path(ellipseIn: CGRect(x: m.x - 1.6, y: m.y - 1.6, width: 3.2, height: 3.2)), with: .color(.white))
                }
            }
        }
    }
}

struct NetAtlasSheet: View {
    @ObservedObject var st: OrigamiState
    @AppStorage("atlasFold") var foldOnPick = true
    var groups: [(Int, [NetAtlasEntry])] {
        Dictionary(grouping: NetAtlas.all, by: { $0.longest }).sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }
    func pick(_ e: NetAtlasEntry) {
        // 平らな展開図なら、組み変わってから組み立てる。組み上がっている（途中の）時は、いちど平らにしてから組み立てる
        if foldOnPick && st.progress > 0.05 { st.netMorph = nil; st.net = e.def; st.playing = false; st.loop = false; st.progress = 0; st.playFold() }
        else if foldOnPick { st.playing = false; st.loop = false; st.progress = 0; st.switchNet(e.def, foldAfter: true) }
        else { st.switchNet(e.def) }
        st.atlasOpen = false
    }
    var body: some View {
        let cur = NetAtlas.number(of: st.net.p4)
        let cols = st.cellColors(4).map { PaletteEditor.color($0) }
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("展開図図鑑（\(NetAtlas.count) 種類）", systemImage: "books.vertical").font(.system(size: 14, weight: .bold))
                Spacer()
                Toggle("選んだら折ってみせる", isOn: $foldOnPick).font(.caption)
                Button("閉じる") { st.atlasOpen = false }.keyboardShortcut(.cancelAction)
            }
            Text("超立方体の展開図は全部で 261 種類（回したり裏返したりして重なるものは 1 つと数える）。8 個の立方体のくっつき方（木）は 82,944 通りあって、それを 384 通りの向きでまとめた数。押すとその展開図になる。白い点は真ん中の胞（折る時に動かない胞）。「いちばん長いつながり」＝一続きにつながっている胞の、いちばん多い数")
                .font(.caption).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            ScrollViewReader { sp in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 6)], spacing: 6, pinnedViews: [.sectionHeaders]) {
                        ForEach(groups, id: \.0) { g in
                            Section {
                                ForEach(g.1) { e in
                                    let on = cur == e.id
                                    VStack(spacing: 2) {
                                        NetThumb(flat: e.flat, cols: cols).frame(height: 74)
                                        Text(e.def.name).font(.system(size: 10, weight: on ? .bold : .regular)).foregroundStyle(on ? UIC.cyan : UIC.text).lineLimit(1)
                                    }
                                    .padding(4)
                                    .background(on ? UIC.cyan.opacity(0.16) : Color.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(on ? UIC.cyan.opacity(0.8) : UIC.line))
                                    .contentShape(Rectangle())
                                    .onTapGesture { pick(e) }
                                    .id(e.id)
                                }
                            } header: {
                                Text("いちばん長いつながり：胞 \(g.0) 個（\(g.1.count) 種類）").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.amber)
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4).background(UIC.panel)
                            }
                        }
                    }
                }
                .onAppear { if let c = cur { DispatchQueue.main.async { sp.scrollTo(c, anchor: .center) } } }
            }
        }
        .padding(14)
        #if os(macOS)
        .frame(width: 680, height: 620)
        #endif
        .background(UIC.panel).preferredColorScheme(.dark)
    }
}
