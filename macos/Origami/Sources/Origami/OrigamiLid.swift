// 積分のふた（ウェブ版の wLidOpenAt・wLidPair・drawLids・drawLid2 と同じ）：
//   立方体を入れてくる側の胞（w の積分なら +W、何方向も同時ならそれぞれの + 側）を、y ＝ +H の辺（y のふたなら z ＝ +H）を蝶番に、外へ 90° 開く。
//   いっぱいになったら閉じ、取り出す前に開ける（反対側から出す時は − 側のふたを開ける）。
//   4 次元の水：注ぐ前に上のふた（+W）を開けて、いっぱいで閉じる。抜く時は底（−W）を開けて、出しきったら閉じる。
//   左の立方体の窓は 1 つ下の仲間：右の w → 左の z、x → x、y → y（右の z に当たる面は左には無い）。
//   ふたの見せ方（intLidMode）：0 直角に開く・1 開けたまま・2 消す（薄く）・3 開けない
import Foundation
import simd

struct LidOpen { let ax: Int; let sg: Double; let o: Double }    // 右の超立方体の軸（0 x〜3 w）・向き ±1・開き具合 0〜1

extension OrigamiState {
    static let lidLEAD = 0.7                                         // ふたを開けるのにかける秒（取り出しが始まる前に開き切る）
    /// いっぱいで止める秒：ふたがある時は、取り出す前にふたを開ける分だけ長く（開けたままで入れた側から出す時はいらない）
    var intHoldNow: Double { Self.intHOLD + (intLidMode != 3 && !(intLidMode == 1 && !intOutOpp) ? Self.lidLEAD + 0.1 : 0) }
    /// 今開いているふた
    func lidOpens() -> [LidOpen] {
        guard intOn, intLidMode != 3, intVis > 0.01, progress >= 0.92, explodeE < 0.05 else { return [] }
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        var r: [LidOpen] = []
        if intMethod == 2 { return [] }                                   // 玉を詰める：ふたは閉じたまま（玉は箱の中の上から落ちる）
        if intMethod == 1 {   // 水：上のふた。底は、排水口で抜く時は開けない（排水口の栓・格子のふたが開く）
            r = [LidOpen(ax: 3, sg: 1, o: waterLid)]
            if !waterHoleNow { r.append(LidOpen(ax: 3, sg: -1, o: waterBLid)) }
        } else {
            let M = intM, ST = intST(M), fillT = ST[M - 1] + Self.intD, HOLD = intHoldNow, cycle = 2 * fillT + HOLD + Self.intEMPTY
            let t = intT.truncatingRemainder(dividingBy: cycle), outT = fillT + HOLD, endT = 2 * fillT + HOLD, L = Self.lidLEAD
            var plus = 0.0, minus = 0.0
            if intLidMode == 1 {                                       // 開けたまま：反対側から出す時は、取り出し口が開くのと同時に入れた側を閉める
                if intOutOpp { minus = t < outT - L ? 0 : t < endT ? sm((t - (outT - L)) / L) : 1 - sm((t - endT) / L) }
                plus = 1 - minus
            } else if !intOutOpp {                                     // いっぱいで 0.5 秒で閉じ、取り出しの L 秒前から開ける
                plus = t < fillT ? 1 : t < outT - L ? 1 - sm((t - fillT) / 0.5) : sm((t - (outT - L)) / L)
            } else {                                                   // 反対側から：+ は入れる時だけ、− は取り出す前に開けて出しきったら閉める
                plus = t < fillT ? 1 : t < fillT + 0.5 ? 1 - sm((t - fillT) / 0.5) : t > cycle - L ? sm((t - (cycle - L)) / L) : 0
                minus = t < outT - L ? 0 : t < endT ? sm((t - (outT - L)) / L) : 1 - sm((t - endT) / 0.5)
            }
            for ax in intAxesList { r.append(LidOpen(ax: ax, sg: 1, o: plus)); r.append(LidOpen(ax: ax, sg: -1, o: minus)) }
        }
        return r.filter { $0.o > 0.001 }
    }
}

@inline(__always) private func gpuL(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 右の軸を、この窓の軸へ（左の立方体：w → z、z は無い）
    func lidAxis(_ ax: Int) -> Int { n == 4 ? ax : ax == 3 ? 2 : ax == 2 ? -1 : ax }
    /// この窓の胞のふたの開き具合（0＝閉じている）
    func lidAmount(_ lids: [LidOpen], _ cell: OrigamiState.Cell) -> Double {
        let (a, s) = OrigamiState.fixed(cell, n)
        return lids.first { lidAxis($0.ax) == a && $0.sg == s }?.o ?? 0
    }
    /// 直角に開くふた：ふたの胞の写しを、蝶番のまわりに 0〜90° 回して描く（面はうすく、辺は明るく）
    func lidGeometry(_ rods: inout [TLRod], _ lids: [LidOpen]) -> [IntTriBatch] {
        guard n <= 4, st.intLidMode == 0 || st.intLidMode == 1, !lids.isEmpty else { return [] }
        let H = OrigamiState.half, cells = OrigamiState.cells(n), pcols = st.cellColors(n), k = st.intVis
        var tris: [IntVert] = []
        for l in lids {
            let a = lidAxis(l.ax); guard a >= 0, let ci = cells.firstIndex(where: { OrigamiState.fixed($0, n) == (a, l.sg) }) else { continue }
            let th = Double.pi / 2 * l.o * l.o * (3 - 2 * l.o), cs = cos(th), sn = sin(th)   // なめらかに 0〜90°
            let oth = (0..<n).filter { $0 != a }, hg = a == 1 ? 2 : 1, m = n - 1
            var V: [SIMD3<Double>] = []
            for b in 0..<(1 << m) {
                var g = [Double](repeating: 0, count: n)
                for (j, ax) in oth.enumerated() { g[ax] = (b >> j) & 1 == 1 ? H : -H }
                let sd = H - g[hg]; g[hg] = H - sd * cs; g[a] = l.sg * (H + sd * sn)      // 蝶番からの距離 sd を、(蝶番の軸, ふたの軸) の面の中で回す
                V.append(st.place(g, n).0)
            }
            let c0 = OrigamiState.rgb(pcols[min(ci, pcols.count - 1)]), cl = simd_min(SIMD3<Float>(repeating: 1), c0 * 1.3 + 0.15)
            for b in 0..<(1 << m) { for j in 0..<m where (b >> j) & 1 == 0 {
                rods.append(TLRod(a: SIMD4(gpuL(V[b]), 0), b: SIMD4(gpuL(V[b | (1 << j)]), 0), col: SIMD4(cl, Float(1.1 * k / 1.4))))
            } }
            let al = Float(0.35 * k)
            func quad(_ i: [Int]) { for t in [i[0], i[1], i[2], i[0], i[2], i[3]] { tris.append(IntVert(p: SIMD4(gpuL(V[t]), 1), c: SIMD4(c0 * al, al))) } }
            if m == 2 { quad([0, 1, 3, 2]) }
            else { for j in 0..<3 { for s in 0..<2 {
                let o1 = (j + 1) % 3, o2 = (j + 2) % 3, bs = s << j
                quad([bs, bs | 1 << o1, bs | 1 << o1 | 1 << o2, bs | 1 << o2])
            } } }
        }
        return tris.isEmpty ? [] : [IntTriBatch(add: false, verts: tris)]
    }
}
