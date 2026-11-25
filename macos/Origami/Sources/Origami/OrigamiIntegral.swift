// 積分（ウェブ版の「4D積分」）：超立方体＝立方体（輪切り）を w の方向に積み重ねたもの。
//   立方体が ふた +W の外から 1 個ずつ飛んできて、奥（底 −W）から敷きつめる → いっぱいで止める → 取り出す → 空で止める → くり返し。
//   区分の数 n 個（2〜512）で敷きつめても、本当の値 ∫₋₁¹ 8 dw ＝ 16 は同じ（式の欄は、敷きつめた先頭 w までの連続の値）。
//   左の立方体の窓は 1 つ下の仲間：正方形（面積 4）を z の方向に積む（∫ 4 dz ＝ 8）。
//   時間割・飛び方・色の決まりはウェブ版（hypercube.html の wPackSetN・wPackList・specCol・ballMat・starMat）と同じ。
//   これからの分（積分の移植メモ.md の 段）：ふた・両端の染め・胞の面のタイル・球柱・デュオシリンダー・タイガー・何方向も同時・二重積分・4D の水
import SwiftUI
import QuartzCore
import simd

struct IntItem { var t: Double; var slot: Double; var a: Double; var fa: Double; var fly: Bool; var k: Int; var ax: Int = 3 }   // ax：入れる向き（0 x・1 y・2 z・3 w）

extension OrigamiState {
    // 出発点（t、1＝ふた）・1 個の移動秒・いっぱいで止める秒・空で止める秒（ウェブ版の WPACK）
    static let intOUT = 3.0, intD = 1.3, intHOLD = 1.4, intEMPTY = 0.8, intFlyFA = 0.15
    var intNi: Int { max(2, min(512, Int(intN.rounded()))) }
    /// 入れる向き（何方向も同時：1〜4 個。w が先頭）
    var intAxesList: [Int] { if intShape != 0 { return [3] }; let a = [3, 0, 1, 2].filter { intAxes & (1 << $0) != 0 }; return a.isEmpty ? [3] : a }   // 形を積む時は w だけ
    /// 1 つの向きの区分の数（何方向も同時の時は、向きの数で分け合う＝ウェブ版と同じ）
    var intNax: Int { max(2, intNi / intAxesList.count) }
    /// 入れる段の数（入れる量：底から何割まで入れるか）
    var intM: Int { max(1, min(intNax, Int((Double(intNax) * intAmount).rounded()))) }
    /// 段 k が出発する時刻：はじめゆっくり、だんだん速く（0.5×0.88^k、最小 4/n）。一定なら同じ長さを等しい間隔で
    func intST(_ N: Int) -> [Double] {
        let gmin = max(0.008, min(0.25, 4 / Double(N)))
        var st = [0.0]
        for k in 1..<max(2, N) { st.append(st[k - 1] + max(gmin, 0.5 * pow(0.88, Double(k - 1)))) }
        if intPace == 1 { let T = st[N - 1]; for k in 0..<N { st[k] = T * Double(k) / Double(max(1, N - 1)) } }
        return st
    }
    /// 今の時刻の段の一覧と、積分の上の端（先頭）・下の端（取り出し中の反対側）。
    ///   入れる量：底から M 段（M＝n×入れる量）だけ入れて止める＝積分の上の端が −1＋2M／n で止まる。
    ///   何方向も同時：どの向きも同じ時間割で、向きごとに同じ段を入れる
    /// 1 往復（入れる → 待つ → 取り出す → 空）の長さ
    var intCycleT: Double { let M = intM, ST = intST(M); return 2 * (ST[M - 1] + Self.intD) + intHoldNow + Self.intEMPTY }
    /// 積分を見る向き：1 横（x）＝ X‐W を 90° 回して w を画面の左右に（輪切りが横に並ぶ）・2 横（y）＝ Y‐W を 90° で w を上下に（下から積み上がる）。
    ///   どちらも平行投影（輪切りが同じ大きさで並ぶ）と少しななめの 3D。0 は何もしない。なめらかに回す
    func intApplyView(_ k: Int) {
        guard k == 1 || k == 2 else { return }
        cycling = false; stopSpins(); playing = false; loop = false; viewSel = -1
        pend = [0, 0, 0, 0, 0]
        let to: [Double] = k == 1 ? [Double.pi / 2, 0, 0, 0, 0.35, -0.3] : [0, Double.pi / 2, 0, 0, 0.45, -0.2]
        tween = (cur6, to, 0, 1.2, projBlend, 1); presetPar = 1; presetHold = SIMD3(to[0], to[1], to[2])
    }
    func intUpdate() -> [IntItem] {
        let N = intNax, M = intM, ST = intST(M), fillT = ST[M - 1] + Self.intD, HOLD = intHoldNow, cycle = 2 * fillT + HOLD + Self.intEMPTY
        let t = intT.truncatingRemainder(dividingBy: cycle)
        func sm(_ x: Double) -> Double { let c = max(0, min(1, x)); return c * c * (3 - 2 * c) }
        let filling = t < fillT + HOLD
        var base: [IntItem] = []
        for k in 0..<M {
            let tk = -1 + 2 * Double(k) / Double(N - 1)
            let p = filling ? max(0, min(1, (t - ST[k]) / Self.intD))
                            : 1 - max(0, min(1, (t - fillT - HOLD - ST[intOutOpp ? k : M - 1 - k]) / Self.intD))   // 入る：奥の段から／出る：手前の段から（反対側なら奥の段から）
            if p <= 0 { continue }
            let opp = !filling && intOutOpp
            let tt = opp ? -Self.intOUT + (tk + Self.intOUT) * sm(p) : Self.intOUT + (tk - Self.intOUT) * sm(p)
            var it = IntItem(t: tt, slot: Double(k) / Double(max(1, N - 1)), a: max(0, min(1, (opp ? tt + Self.intOUT : Self.intOUT - tt) / 0.6)),
                             fa: Self.intFlyFA + (1 - Self.intFlyFA) * sm((p - 0.75) / 0.25), fly: p < 1, k: k)
            if !intFly { it.t = tk; it.a = sm(p); it.fa = 1; it.fly = false }
            base.append(it)
        }
        // 積分の上の端：段 k が着く時刻をつないだ、連続の「いまどこまで」（ウェブ版と同じ。入れる量で edge(M) まで）
        func edge(_ k: Int) -> Double { -1 + 2 * Double(k) / Double(N) }
        var front = -1.0, back = -1.0
        if filling {
            func L(_ k: Int) -> Double { ST[k] + Self.intD }
            if t <= L(0) { front = edge(0) + (edge(1) - edge(0)) * max(0, t) / L(0) }
            else { var k = 1; while k < M && t > L(k) { k += 1 }; front = k >= M ? edge(M) : edge(k) + (edge(k + 1) - edge(k)) * (t - L(k - 1)) / (L(k) - L(k - 1)) }
        } else if intOutOpp {
            func O(_ j: Int) -> Double { fillT + HOLD + ST[j] }
            let te = O(M - 1) + Self.intD
            front = edge(M)
            if t >= O(0) { var j = 0; while j < M - 1 && t > O(j + 1) { j += 1 }; let t1 = j < M - 1 ? O(j + 1) : te; back = min(edge(M), edge(j) + (edge(j + 1) - edge(j)) * min(1, (t - O(j)) / (t1 - O(j)))) }
        } else {
            func O(_ j: Int) -> Double { fillT + HOLD + ST[j] }
            let te = O(M - 1) + Self.intD
            if t < O(0) { front = edge(M) }
            else { var j = 0; while j < M - 1 && t > O(j + 1) { j += 1 }; let t1 = j < M - 1 ? O(j + 1) : te; front = max(-1, edge(M - j) - (edge(M - j) - edge(M - j - 1)) * min(1, (t - O(j)) / (t1 - O(j)))) }
        }
        if !intFly {   // 演出なし：段は、積分の範囲（下の端〜先頭）が自分の段にかかった分だけ出す
            base = base.compactMap { it in
                let e0 = edge(it.k), e1 = edge(it.k + 1), cv = max(0, min(1, (min(front, e1) - max(back, e0)) / (e1 - e0)))
                if cv <= 0.001 { return nil }; var o = it; o.a = cv; return o
            }
        }
        let f = max(-1, min(1, front)), b = max(-1, min(1, back))
        if abs(intFront - f) > 1e-5 { intFront = f }
        if abs(intBack - b) > 1e-5 { intBack = b }
        if intFilling != filling { intFilling = filling }
        // 向きごとに同じ段を
        var out: [IntItem] = []
        for ax in intAxesList { for it in base { var o = it; o.ax = ax; out.append(o) } }
        return out
    }
    /// 七色（ウェブ版の specCol）：f＝0（下・赤）〜 1（上・紫）。色相 0.82×f・彩度 1・明るさ 0.58
    static func specCol(_ f: Double) -> SIMD3<Float> { hsl(0.82 * max(0, min(1, f)), 1, 0.58) }
    static func hsl(_ h: Double, _ s: Double, _ l: Double) -> SIMD3<Float> {
        let q = l < 0.5 ? l * (1 + s) : l + s - l * s, p = 2 * l - q
        func c(_ t0: Double) -> Double {
            var t = t0; if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1.0 / 6 { return p + (q - p) * 6 * t }; if t < 0.5 { return q }; if t < 2.0 / 3 { return p + (q - p) * (2.0 / 3 - t) * 6 }; return p
        }
        return SIMD3(Float(c(h + 1.0 / 3)), Float(c(h)), Float(c(h - 1.0 / 3)))
    }
    static let dbOrange = SIMD3<Float>(1.0, 0.55, 0.08), dbRed = SIMD3<Float>(0.92, 0.1, 0.06), dbLine = SIMD3<Float>(1.0, 0.72, 0.32)
    static let db4Lo = SIMD3<Float>(0.95, 0.12, 0.06), db4Hi = SIMD3<Float>(1.0, 0.62, 0.12)
    static let dbT = 0.33 / sqrt(3.0)
    static let dbStars1: [SIMD4<Double>] = [SIMD4(0, 0, 0, 0.22)]
    static let dbStars4: [SIMD4<Double>] = [SIMD4(dbT, dbT, dbT, 0.14), SIMD4(dbT, -dbT, -dbT, 0.14), SIMD4(-dbT, dbT, -dbT, 0.14), SIMD4(-dbT, -dbT, dbT, 0.14)]
    /// 積分が見えている度合い（組み上がり 92% から。分解すると消す）
    /// 確かめ用：全部の段が積み終わった時刻（積み終わり ＋ 少し）
    var intFilledT: Double { let ST = intST(intM); return ST[intM - 1] + Self.intD + Self.intHOLD * 0.5 }
    var intVis: Double { intOn ? max(0, min(1, (progress - 0.92) / 0.08)) * max(0, 1 - 4 * explodeE) : 0 }
}

/// 景色の座標（y が上）を、描く側（z が上）へ
@inline(__always) private func gpuI(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    /// 積分の段（立方体の窓は正方形）：線（rods に足す）と三角形（返す）。eye：カメラの位置（景色の座標）
    func integralGeometry(_ rods: inout [TLRod], eye: SIMD3<Double>) -> [IntTriBatch] {
        let k = st.intVis
        intMarks = []; intSpheres = []
        guard k > 0.01 else { return [] }
        // 立方体の窓では、4 次元の z の向きの仲間が無い（立方体の z は超立方体の w）
        let items = st.intItems.filter { n == 4 || $0.ax != 2 }
        guard !items.isEmpty else { return [] }
        let h = OrigamiState.half, d = n - 1                         // 輪切りの次元（超立方体は立方体 3、立方体は正方形 2）
        let nv = 1 << d
        let units: [[Double]] = (0..<nv).map { v in (0..<d).map { v & (1 << $0) != 0 ? 1.0 : -1.0 } }   // 先に 1 回だけ
        func unit(_ v: Int) -> [Double] { units[v] }
        /// 輪切りの点：入れる向き ax（0 x・1 y・2 z・3 w）の座標が t、残りの軸が u（−1〜1）。立方体の窓では w → z
        func atA(_ u: [Double], _ t: Double, _ ax: Int) -> SIMD3<Double> {
            let a = n == 4 ? ax : (ax == 3 ? 2 : ax)
            var p: [Double] = [], j = 0
            for i in 0..<n { if i == a { p.append(t * h) } else { p.append(u[j] * h); j += 1 } }
            return st.place(p, n).0
        }
        func at(_ u: [Double], _ t: Double) -> SIMD3<Double> { atA(u, t, 3) }
        // 何方向も同時の、w 以外の向きの色（ウェブ版の WDUO_GRAD）：x 赤→黄、y 緑→水色、z 青→紫
        let grad: [Int: (SIMD3<Float>, SIMD3<Float>)] = [0: (OrigamiState.rgb(0xf87171), OrigamiState.rgb(0xfbbf24)), 1: (OrigamiState.rgb(0x34d399), OrigamiState.rgb(0x22d3ee)), 2: (OrigamiState.rgb(0x38bdf8), OrigamiState.rgb(0xa78bfa))]
        // 色：0 白・1 層ごと・2 七色の縞（面）・3 ドラゴンボール・4 七色の枠だけ・5 レインボーボール（枠＋玉）・6 同心の七色・7 同心球 3D プリント
        let color0 = st.intColor, stars4 = st.intStars == 4
        let spin = st.intBallSpin ? Date().timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 3600) * 0.9 : 0
        let fs = max(1, Int(ceil(Double(st.intNi) / (color0 == 2 ? 256 : color0 == 6 || color0 == 7 ? 64 : 96))))   // 同心は 1 面が重いので 64 枚まで
        let aF = min(1, 9 * Double(fs) / Double(max(1, items.count)))
        let fsB = max(1, Int(ceil(Double(st.intNi) / 128)))
        let fsS = max(1, Int(ceil(Double(st.intNi) / 10)))           // 同心球の殻を入れる立方体（10 個くらいまで）
        // 遠い段から順に（重ねる順。ウェブ版は w の順のまま）
        //   （真ん中の遠さは先に 1 回だけ計算。比べるたびに写すと、512 個で重かった）
        let zero = [Double](repeating: 0, count: d)
        let dist = items.map { simd_distance(atA(zero, $0.t, $0.ax), eye) }
        let order = items.indices.sorted { dist[$0] > dist[$1] }
        var norm: [IntVert] = [], add: [IntVert] = [], shellV: [IntVert] = [], shapeV: [IntVert] = [], sphV: [IntSphere] = []
        // 4 次元の形を積む（球柱・デュオシリンダー・タイガー）：着いた段は中に何枚か重ねてなめらかに（段の数が多い時は間引く）
        let shape0 = st.intShape, Nax = st.intNax
        let kSub = shape0 == 1 ? max(1, min(16, Int((240.0 / Double(Nax)).rounded()))) : shape0 == 2 || shape0 == 4 || shape0 == 5 || shape0 == 6 || shape0 == 8 ? (Nax > 64 ? 1 : 3) : (Nax > 32 ? 1 : 3)
        let thinS = shape0 == 3 || shape0 == 7 ? max(1, Int(ceil(Double(Nax) / 64))) : shape0 == 2 || shape0 == 4 || shape0 == 5 || shape0 == 6 || shape0 == 8 ? max(1, Int(ceil(Double(Nax) / 160))) : 1
        let ballRes = shape0 == 1 ? (Nax * kSub > 160 ? 6 : 9) : shape0 == 4 || shape0 == 5 ? (Nax > 64 ? 7 : 10) : 6
        func tri(_ list: inout [IntVert], _ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Double>, _ col: SIMD4<Float>) {
            list.append(IntVert(p: SIMD4(gpuI(a), 1), c: col)); list.append(IntVert(p: SIMD4(gpuI(b), 1), c: col)); list.append(IntVert(p: SIMD4(gpuI(c), 1), c: col))
        }
        func rod(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ col: SIMD3<Float>, _ L: Double) {
            rods.append(TLRod(a: SIMD4(gpuI(a), 0), b: SIMD4(gpuI(b), 0), col: SIMD4(col, Float(min(1, L) / 1.4))))
        }
        for idx in order {
            let it = items[idx], t = it.t, wAx = it.ax == 3
            if shape0 != 0 {
                let land = it.fa >= 0.85 && !it.fly, hw = 1 / Double(Nax), lo = st.intBack, hi = st.intFront
                if land && it.k % thinS != 0 { continue }
                let target = -1 + (2 * Double(it.k) + 1) / Double(Nax)     // 飛んでいる間は、着く所の輪切りの形のまま動く
                let K = land ? kSub * thinS : 1
                for j in 0..<K {
                    let tt = land ? t - hw * Double(thinS) + (Double(j) + 0.5) * 2 * hw * Double(thinS) / Double(K) : t
                    if land && (tt < lo - 1e-6 || tt > hi + 1e-6) { continue }
                    sliceShape(&shapeV, &sphV, shape: shape0, pos: tt, ws: land ? tt : target, a: it.a * k, eye: eye, ballRes: ballRes, spin: spin)
                }
                continue
            }
            // 柄は w（立方体の窓は z）の向きだけ。ほかの向きは、その向きの色の「層ごと」
            let color = wAx ? color0 : 1, spec = color == 2, dragon = color == 3
            let specLine = color == 2 || color == 4 || color == 5, ringM = color == 6 || color == 7, shellM = color == 7
            let V = (0..<nv).map { atA(unit($0), t, it.ax) }
            let L = 0.75 * 1.33 * it.a * k                            // 線の濃さ（ウェブ版の aL＝1.33）
            // 線：輪切りの辺。七色は y の向きの辺を 7 つに分けて、下 赤 → 上 紫
            func edgeCol(_ f: Double) -> SIMD3<Float> {
                if dragon { return stars4 ? OrigamiState.db4Lo + (OrigamiState.db4Hi - OrigamiState.db4Lo) * Float(f) : OrigamiState.dbLine }
                return OrigamiState.specCol(f)
            }
            var base = SIMD3<Float>(0.97, 0.98, 0.99)
            if color == 0 {   // 白：ZW の色の約束で w の − は水色・＋ はピンクに少し寄せる
                let tint: SIMD3<Float> = t >= 0 ? SIMD3(1.0, 0.45, 0.85) : SIMD3(0.35, 0.85, 1.0)
                base = base + (tint - base) * Float(min(1, abs(t) * 0.9 + 0.1) * 0.4)
            } else if color == 1 {
                if let g = grad[it.ax] { base = g.0 + (g.1 - g.0) * Float(it.slot) } else { base = OrigamiState.specCol(it.slot) }
            }   // 層ごとに 1 色：底 −W 赤 … ふた +W 紫
            for v in 0..<nv { for ax in 0..<d where v & (1 << ax) == 0 {
                let a = V[v], b = V[v | (1 << ax)]
                if ringM {   // 同心：辺は 6 つに分けて、真ん中 緑 → 両端の角 紫（同心球は中心からの距離）
                    for m in 0..<6 {
                        let f0 = Double(m) / 6, f1 = Double(m + 1) / 6, sm = 2 * (f0 + f1) / 2 - 1
                        let f = shellM ? (2 + sm * sm) / 3 : min(1, (1 + sm * sm) / 2)
                        rod(a + (b - a) * f0, a + (b - a) * f1, OrigamiState.specCol(f), L)
                    }
                } else if specLine || dragon {
                    let ya = unit(v).count > 1 ? (unit(v)[1] + 1) / 2 : 0.5, yb = unit(v | (1 << ax)).count > 1 ? (unit(v | (1 << ax))[1] + 1) / 2 : 0.5
                    if ax == 1 && !(dragon && !stars4) {
                        for m in 0..<7 { let f0 = Double(m) / 7, f1 = Double(m + 1) / 7; rod(a + (b - a) * f0, a + (b - a) * f1, edgeCol(ya + (yb - ya) * (f0 + f1) / 2), L) }
                    } else { rod(a, b, edgeCol(ya), L) }
                } else { rod(a, b, base, L) }
            } }
            // 面
            let faceOn = !dragon && color != 4 && color != 5 && it.k % fs == 0
            if faceOn {
                // 輪切りの面（立方体は 6 面、正方形は 1 面）。四角を 2 つの三角形に
                var quads: [[Int]] = []
                if d == 3 { for ax in 0..<3 { for s in 0..<2 { let o = (0..<3).filter { $0 != ax }; let b0 = s << ax; quads.append([b0, b0 | (1 << o[0]), b0 | (1 << o[0]) | (1 << o[1]), b0 | (1 << o[1])]) } } }
                else { quads.append([0, 1, 3, 2]) }
                if ringM {  // 同心の七色：どの面も 6×6 に分けて、真ん中 赤 → 角 紫（同心球の立方体は、立方体の中心からの距離。中の殻が見えるようにうすく）
                    let FS = min(1, L * 0.9) * it.fa * (shellM ? 0.08 : 0.22)
                    for q in quads {
                        let q0 = V[q[0]], q1 = V[q[1]], q2 = V[q[2]], q3 = V[q[3]]
                        func bil(_ s_: Double, _ t_: Double) -> SIMD3<Double> { let A = q0 + (q1 - q0) * s_, B = q3 + (q2 - q3) * s_; return A + (B - A) * t_ }
                        for i in 0..<6 { for j in 0..<6 {
                            let s0 = Double(i) / 6, s1 = Double(i + 1) / 6, t0 = Double(j) / 6, t1 = Double(j + 1) / 6
                            let a_ = s0 + s1 - 1, b_ = t0 + t1 - 1
                            let f = shellM ? (1 + a_ * a_ + b_ * b_) / 3 : min(1, (a_ * a_ + b_ * b_) / 2)
                            let c = OrigamiState.specCol(f) * Float(FS)
                            tri(&norm, bil(s0, t0), bil(s1, t0), bil(s1, t1), SIMD4(c, Float(FS))); tri(&norm, bil(s0, t0), bil(s1, t1), bil(s0, t1), SIMD4(c, Float(FS)))
                        } }
                    }
                } else if spec {   // 七色：ふつうに重ねる（足すと白くなる）。y の向きに 7 つの帯
                    let FS = min(1, L * 0.9) * it.fa * 0.22
                    for q in quads {
                        let ys = q.map { (unit($0)[1] + 1) / 2 }
                        if ys.allSatisfy({ $0 == ys[0] }) {
                            let c = OrigamiState.specCol(ys[0]) * Float(FS)
                            tri(&norm, V[q[0]], V[q[1]], V[q[2]], SIMD4(c, Float(FS))); tri(&norm, V[q[0]], V[q[2]], V[q[3]], SIMD4(c, Float(FS)))
                        } else {
                            let bot = q.filter { unit($0)[1] < 0 }
                            let top = bot.map { b in q.first { c in unit(c)[1] > 0 && (0..<d).allSatisfy { ax in ax == 1 || unit(c)[ax] == unit(b)[ax] } }! }
                            for m in 0..<7 {
                                let f0 = Double(m) / 7, f1 = Double(m + 1) / 7, c = OrigamiState.specCol((f0 + f1) / 2) * Float(FS)
                                let A0 = V[bot[0]] + (V[top[0]] - V[bot[0]]) * f0, B0 = V[bot[1]] + (V[top[1]] - V[bot[1]]) * f0
                                let B1 = V[bot[1]] + (V[top[1]] - V[bot[1]]) * f1, A1 = V[bot[0]] + (V[top[0]] - V[bot[0]]) * f1
                                tri(&norm, A0, B0, B1, SIMD4(c, Float(FS))); tri(&norm, A0, B1, A1, SIMD4(c, Float(FS)))
                            }
                        }
                    }
                } else {    // 白・層ごと：足し合わせ（重なるほど明るい）
                    let F = 0.45 * aF * it.a * k * 0.12
                    let c = base * Float(F)
                    for q in quads { tri(&add, V[q[0]], V[q[1]], V[q[2]], SIMD4(c, 0)); tri(&add, V[q[0]], V[q[2]], V[q[3]], SIMD4(c, 0)) }
                }
            }
            // ドラゴンボール：オレンジのガラスの玉（裏 → 表）と赤い星
            //   段が多い時は、着いた玉を 128 個くらいまでに間引く（重なってほとんど同じに見える。飛んでいる玉はいつも描く）
            // 玉（ドラゴンボール・レインボーボール・同心球）は、何方向も同時の時もどの向きの立方体にも入れる（枠の色は向きごとの色で見分ける）
            let ballPat = wAx ? color0 : (color0 == 3 || color0 == 5 || color0 == 7 ? color0 : -1)
            let atIt: ([Double], Double) -> SIMD3<Double> = { u, tt in atA(u, tt, it.ax) }
            if ballPat == 3 && (it.fly || it.k % fsB == 0) { dragonBall(&norm, t: t, fa: it.fa * it.a * k, eye: eye, count: min(items.count, 128), at: atIt) }
            // レインボーボール（ドラゴンボールの原型）：七色の帯の玉（着くと濃く、飛んでいる間は薄く）
            if ballPat == 5 && (it.fly || it.k % fsB == 0) {
                let fa = (0.3 + 0.7 * (it.fa - 0.15) / 0.85) * it.a * k
                if d == 3 {   // 玉を画素ごとに（輪郭も陰もなめらか）。その段の写し方で＝4D で回すとだ円体につぶれる
                    let R = 0.6, C0 = atIt([0, 0, 0], t), E0 = [atIt([R, 0, 0], t), atIt([0, R, 0], t), atIt([0, 0, R], t)]
                    if n == 4 {
                        // 4D：遠近で正確に写しただ円体（x・y・z の向きの玉は w にも広がるので、近道ではずれる）
                        var c4 = SIMD4<Double>(0, 0, 0, 0); c4[it.ax] = t
                        if let e = exactBallAxes(c4, R, axes: (0..<4).filter { $0 != it.ax }, approxC: C0, approxE: E0, spin: spin, alpha: fa * 1.12) {
                            sphV.append(e)
                        }
                    } else { sphV.append(Self.ellipsoid(C0, E0, spin: spin, alpha: fa * 1.12)) }
                } else { rainbowBall(&norm, t: t, fa: fa, eye: eye, count: min(items.count, 128), spin: spin, at: atIt) }
            }
            // 同心球 3D プリント：選んだ立方体の中に 12 枚の殻と赤い芯（殻ごとに軸を傾けて、交互に逆回り）
            //   殻は全部の面のあとに描く（ウェブ版と同じ：面に隠れない）
            if ballPat == 7 && (it.k == 0 || it.k % fsS == 0) { shells(&shellV, V: V, t: t, a: it.a * k, spin: spin) }
        }
        var out: [IntTriBatch] = []
        if !add.isEmpty { out.append(IntTriBatch(add: true, verts: add)) }
        norm += shellV
        if !shapeV.isEmpty { out.append(IntTriBatch(add: false, verts: shapeV, spin: Float(spin), depth: true)) }
        // 内接する超球：胞に接する点に金色の光（積分がそこまで届いたら）
        intMarks = shape0 == 4 && st.raster ? hyperTouchMarks(front: st.intFront, back: st.intBack, k: k) : []
        intSpheres = sphV
        if !norm.isEmpty { out.append(IntTriBatch(add: false, verts: norm, spin: Float(spin))) }
        return out
    }

    /// ドラゴンボール 1 個：輪切りの真ん中の玉（立方体の 1 辺を 1 として半径 0.32）を、点ごとに 4 次元の回転と遠近で写す（形がゆがむのも本当の写し方のまま）。
    ///   ガラス：表はふちほど濃いオレンジとつや、裏は薄いオレンジ（ウェブ版の ballMat の pat 4）。星：その上に、こちらを向いた赤い星（立体の星の面、ウェブ版の starMat）
    private func dragonBall(_ list: inout [IntVert], t: Double, fa: Double, eye: SIMD3<Double>, count: Int, at: ([Double], Double) -> SIMD3<Double>) {
        let d = n - 1, R = 0.64                                         // 単位の座標（1 辺 2）での半径
        let C = at([Double](repeating: 0, count: d), t)
        let stars = st.intStars == 4 ? OrigamiState.dbStars4 : OrigamiState.dbStars1
        let Ld = simd_normalize(SIMD3<Double>(-0.4, 0.8, 0.45))
        func col(_ P: SIMD3<Double>, _ N: SIMD3<Double>, back: Bool) -> SIMD4<Float> {
            let vd = simd_normalize(eye - P), f = simd_dot(N, vd)
            if back { let a = Float(0.35 * fa); return SIMD4(SIMD3<Float>(1.0, 0.5, 0.06) * a, a) }
            let fr = pow(1 - max(0, f), 2.0)
            let glass = SIMD3<Float>(1.0, 0.62, 0.12) + (SIMD3<Float>(0.95, 0.32, 0.02) - SIMD3<Float>(1.0, 0.62, 0.12)) * Float(fr)
            let spc = pow(max(simd_dot(simd_reflect(-vd, N), Ld), 0), 48)
            let a = Float(min(1, 0.38 + 0.45 * fr + spc) * fa)
            return SIMD4((glass + Float(spc * 0.9)) * a, a)
        }
        func vtx(_ P: SIMD3<Double>, _ c: SIMD4<Float>) -> IntVert { IntVert(p: SIMD4(gpuI(P), 1), c: c) }
        if d == 3 {
            // 玉の細かさ：段の数が多いほど粗く（全部で約 6 万点まで）
            let rings = count > 96 ? 7 : count > 48 ? 10 : 16, segs = rings * 2
            var P: [[SIMD3<Double>]] = [], Nn: [[SIMD3<Double>]] = []
            for i in 0...rings {
                let th = Double.pi * Double(i) / Double(rings)
                var row: [SIMD3<Double>] = [], nrow: [SIMD3<Double>] = []
                for j in 0...segs {
                    let ph = 2 * Double.pi * Double(j) / Double(segs)
                    let s = SIMD3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
                    let p = at([s.x * R, s.y * R, s.z * R], t)
                    row.append(p); nrow.append(simd_length(p - C) > 1e-9 ? simd_normalize(p - C) : SIMD3(0, 0, 1))
                }
                P.append(row); Nn.append(nrow)
            }
            var front: [IntVert] = [], back: [IntVert] = []
            for i in 0..<rings { for j in 0..<segs {
                let q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                let mid = q.reduce(SIMD3<Double>(0, 0, 0)) { $0 + P[$1.0][$1.1] } / 4, mn = q.reduce(SIMD3<Double>(0, 0, 0)) { $0 + Nn[$1.0][$1.1] }
                let isBack = simd_dot(mn, eye - mid) <= 0
                for tr in [[0, 1, 2], [0, 2, 3]] { for v in tr { let (a, b) = q[v]; let c = col(P[a][b], Nn[a][b], back: isBack); (isBack ? { back.append(vtx(P[a][b], c)) } : { front.append(vtx(P[a][b], c)) })() } }
            } }
            list += back; list += front
            // 玉の写った大きさ（星の大きさに）
            let rb = (simd_distance(at([R, 0, 0], t), C) + simd_distance(at([0, R, 0], t), C) + simd_distance(at([0, 0, R], t), C)) / 3
            for s in stars { starAt(&list, at([s.x * R, s.y * R, s.z * R], t), size: s.w * rb, eye: eye, fa: fa) }
        } else {
            // 立方体の窓（1 つ下の仲間）：正方形の真ん中の丸（円板）と星 1 個
            let segs = 28
            var ring: [SIMD3<Double>] = []
            for j in 0..<segs { let ph = 2 * Double.pi * Double(j) / Double(segs); ring.append(at([cos(ph) * R, sin(ph) * R], t)) }
            let a = Float(0.55 * fa), c = SIMD4(SIMD3<Float>(1.0, 0.55, 0.1) * a, a)
            for j in 0..<segs { list.append(vtx(C, c)); list.append(vtx(ring[j], c)); list.append(vtx(ring[(j + 1) % segs], c)) }
            let rb = simd_distance(ring[0], C)
            starAt(&list, C, size: 0.22 * rb, eye: eye, fa: fa)
        }
    }
    /// 七色の帯（ウェブ版の band）：y＝0〜1 を 7 段に分けた色
    static func band(_ y: Double) -> SIMD3<Float> { let m = max(0, min(6, floor(y * 7))); return OrigamiState.hsl(0.82 * (m + 0.5) / 7, 1, 0.58) }
    /// 傾いた軸のまわりに回す（ウェブ版の spinV）
    static func spinV(_ v: SIMD3<Double>, _ an: Double) -> SIMD3<Double> {
        let a = simd_normalize(SIMD3<Double>(0.62, 0.72, 0.3)), c = cos(an), s = sin(an)
        return v * c + simd_cross(a, v) * s + a * simd_dot(a, v) * (1 - c)
    }
    /// レインボーボール 1 個（玉の半径は立方体の 1 辺を 1 として 0.3）：七色の帯が傾いた軸のまわりに回る。少し陰（裏 → 表の順に）
    private func rainbowBall(_ list: inout [IntVert], t: Double, fa: Double, eye: SIMD3<Double>, count: Int, spin: Double, at: ([Double], Double) -> SIMD3<Double>) {
        let d = n - 1, R = 0.6
        let C = at([Double](repeating: 0, count: d), t)
        func vtx(_ P: SIMD3<Double>, _ c: SIMD4<Float>) -> IntVert { IntVert(p: SIMD4(gpuI(P), 1), c: c) }
        if d == 3 {
            let rings = count > 96 ? 8 : count > 48 ? 11 : 18, segs = rings * 2   // 輪郭がカクカクしないよう細かめ（帯の色は画素ごとなので、網目は形だけ）
            var P: [[SIMD3<Double>]] = [], S: [[SIMD3<Double>]] = []
            for i in 0...rings {
                let th = Double.pi * Double(i) / Double(rings)
                var row: [SIMD3<Double>] = [], srow: [SIMD3<Double>] = []
                for j in 0...segs {
                    let ph = 2 * Double.pi * Double(j) / Double(segs), sv = SIMD3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph))
                    row.append(at([sv.x * R, sv.y * R, sv.z * R], t)); srow.append(sv)
                }
                P.append(row); S.append(srow)
            }
            // 頂点ごとに、玉の上の位置（単位球）と陰の明るさを渡し、帯の色はシェーダーが画素ごとに決める（p.w＝−濃さ が印）
            let a = Float(min(1, fa * 1.12))
            func bv(_ ii: Int, _ jj: Int) -> IntVert {
                let Pp = P[ii][jj], nrm = simd_length(Pp - C) > 1e-9 ? simd_normalize(Pp - C) : SIMD3(0, 0, 1)
                let f = simd_dot(nrm, simd_normalize(eye - Pp)), sv = S[ii][jj]
                return IntVert(p: SIMD4(gpuI(Pp), -max(a, 1e-4)), c: SIMD4(Float(sv.x), Float(sv.y), Float(sv.z), Float(0.45 + 0.55 * max(f, 0))))
            }
            var front: [IntVert] = [], back: [IntVert] = []
            for i in 0..<rings { for j in 0..<segs {
                let q = [(i, j), (i + 1, j), (i + 1, j + 1), (i, j + 1)]
                let mid = q.reduce(SIMD3<Double>(0, 0, 0)) { $0 + P[$1.0][$1.1] } / 4
                let nrm = simd_length(mid - C) > 1e-9 ? simd_normalize(mid - C) : SIMD3(0, 0, 1)
                let isBack = simd_dot(nrm, simd_normalize(eye - mid)) <= 0
                for v in [0, 1, 2, 0, 2, 3] { let (ii, jj) = q[v]; if isBack { back.append(bv(ii, jj)) } else { front.append(bv(ii, jj)) } }
            } }
            list += back; list += front
        } else {
            // 立方体の窓：七色の帯の円板（回す。帯の色は画素ごと）
            let segs = 48, a = Float(min(1, fa * 1.12))
            func dv(_ ph: Double, _ r: Double) -> IntVert {
                IntVert(p: SIMD4(gpuI(at([cos(ph) * R * r, sin(ph) * R * r], t)), -max(a, 1e-4)), c: SIMD4(Float(cos(ph) * r), Float(sin(ph) * r), Float(sqrt(max(0, 1 - r * r)) + 1e-3), 1))
            }
            for j in 0..<segs {
                let p0 = 2 * Double.pi * Double(j) / Double(segs), p1 = 2 * Double.pi * Double(j + 1) / Double(segs)
                for r in 0..<6 {
                    let r0 = Double(r) / 6, r1 = Double(r + 1) / 6
                    list += [dv(p0, r0), dv(p1, r0), dv(p1, r1), dv(p0, r0), dv(p1, r1), dv(p0, r1)]
                }
            }
        }
    }
    /// 同心球 3D プリント：立方体の中に 12 枚の同心の殻（色の位置 f＝距離²／3、外から先に）と赤い芯。殻は立方体からはみ出す所を切り取る。
    ///   色：経線 3 本ずつ 7 色（ビーチボールのよう）、殻ごとに軸を少し傾けて交互に逆回り。写し方は 8 つの角からの三重線形（ウェブ版と同じ）
    private func shells(_ list: inout [IntVert], V: [SIMD3<Double>], t: Double, a: Double, spin: Double) {
        let d = n - 1
        func vtx(_ P: SIMD3<Double>, _ c: SIMD4<Float>) -> IntVert { IntVert(p: SIMD4(gpuI(P), 1), c: c) }
        if d == 3 {
            // 立方体の座標 u（−1〜1）→ 写した位置（角の番号：x が 1 の位・y が 2 の位・z が 4 の位）
            func tril(_ u: SIMD3<Double>) -> SIMD3<Double> {
                let x = (u.x + 1) / 2, y = (u.y + 1) / 2, z = (u.z + 1) / 2
                let c00 = V[0] + (V[1] - V[0]) * x, c10 = V[2] + (V[3] - V[2]) * x, c01 = V[4] + (V[5] - V[4]) * x, c11 = V[6] + (V[7] - V[6]) * x
                let c0 = c00 + (c10 - c00) * y, c1 = c01 + (c11 - c01) * y
                return c0 + (c1 - c0) * z
            }
            let NT = 9, NP = 21, al = Float(0.18 * a)
            func sphere(_ rad: Double, _ f: Double, _ k: Int) {
                let th0 = spin / 0.9 * 0.7 * (k % 2 == 1 ? -1 : 1) * (1 + 0.15 * Double(k))
                let ax = simd_normalize(SIMD3(sin(0.4 + 0.3 * Double(k)), cos(0.4 + 0.3 * Double(k)), 0.25)), c = cos(th0), s = sin(th0)
                func rot(_ v: SIMD3<Double>) -> SIMD3<Double> { v * c + simd_cross(ax, v) * s + ax * simd_dot(ax, v) * (1 - c) }
                func pt(_ i: Int, _ j: Int) -> SIMD3<Double> { let th = Double.pi * Double(i) / Double(NT), ph = 2 * Double.pi * Double(j) / Double(NP); return rot(SIMD3(rad * sin(th) * cos(ph), rad * cos(th), rad * sin(th) * sin(ph))) }
                func inside(_ q: SIMD3<Double>) -> Bool { max(abs(q.x), max(abs(q.y), abs(q.z))) <= 1.0001 }
                for i in 0..<NT { for j in 0..<NP {
                    let A = pt(i, j), B = pt(i + 1, j), Cc = pt(i + 1, j + 1), E = pt(i, j + 1)
                    let br = Float(i % 2 == 1 ? 0.86 : 1), fc = k == 0 ? 0 : Double(j / 3) / 6
                    let col = OrigamiState.specCol(fc) * br * al
                    for tr in [[A, B, Cc], [A, Cc, E]] where tr.allSatisfy(inside) { for q in tr { list.append(vtx(tril(q), SIMD4(col, al))) } }
                } }
            }
            for k in stride(from: 12, through: 1, by: -1) { let f = Double(k) / 13; sphere(sqrt(3 * f), f, k) }   // 外の殻から先に＝内側の色が上に乗って、芯まで透ける
            sphere(0.18, 0, 0)                                                                                    // 赤い芯（最後＝いちばん上）
        } else {
            // 立方体の窓：正方形の中の同心の円（外から）。正方形からはみ出す所は四角に切る
            let al = Float(0.22 * a), segs = 40
            func bil(_ u: SIMD2<Double>) -> SIMD3<Double> {
                let x = (max(-1, min(1, u.x)) + 1) / 2, y = (max(-1, min(1, u.y)) + 1) / 2
                let A = V[0] + (V[1] - V[0]) * x, B = V[2] + (V[3] - V[2]) * x
                return A + (B - A) * y
            }
            for k in stride(from: 12, through: 0, by: -1) {
                let f = k == 0 ? 0.0 : Double(k) / 13, rad = k == 0 ? 0.18 : sqrt(2 * f)
                let col = OrigamiState.specCol(f) * al
                let cen = bil(SIMD2(0, 0))
                for j in 0..<segs {
                    let p0 = 2 * Double.pi * Double(j) / Double(segs) + spin * 0.3, p1 = 2 * Double.pi * Double(j + 1) / Double(segs) + spin * 0.3
                    list.append(vtx(cen, SIMD4(col, al))); list.append(vtx(bil(SIMD2(cos(p0), sin(p0)) * rad), SIMD4(col, al))); list.append(vtx(bil(SIMD2(cos(p1), sin(p1)) * rad), SIMD4(col, al)))
                }
            }
        }
    }
    /// 赤い星（10 個の三角形、真ん中を少し盛り上げて面ごとに明暗）：S を真ん中に、カメラを向けて
    private func starAt(_ list: inout [IntVert], _ S: SIMD3<Double>, size: Double, eye: SIMD3<Double>, fa: Double) {
        let nz = simd_normalize(eye - S), tx = simd_normalize(simd_cross(SIMD3(0, 1, 0), nz)), ty = simd_cross(nz, tx)
        let o = (0..<10).map { k -> SIMD3<Double> in let r = k % 2 == 1 ? 0.45 : 1.0, th = Double.pi / 2 + Double(k) * Double.pi / 5; return S + (tx * (r * cos(th)) + ty * (r * sin(th))) * size }
        let top = S + nz * (0.16 * size)
        for k in 0..<10 {
            let a = o[k], b = o[(k + 1) % 10], nrm = simd_normalize(simd_cross(a - top, b - top)), f = abs(simd_dot(nrm, nz))
            let cc = OrigamiState.dbRed * Float(0.4 + 0.6 * f) + Float(pow(f, 24) * 0.3), al = Float(fa)
            let c = SIMD4(cc * al, al)
            list.append(IntVert(p: SIMD4(gpuI(top), 1), c: c)); list.append(IntVert(p: SIMD4(gpuI(a), 1), c: c)); list.append(IntVert(p: SIMD4(gpuI(b), 1), c: c))
        }
    }
}

// ---- 式の欄（ウェブ版の updatePackHUD）：∫ V dw ＝ 8(w＋1) ＝ … ／ 16 と、進みぐあいの棒 ----
struct IntegralHUD: View {
    let n: Int; @ObservedObject var st: OrigamiState
    var body: some View {
        LiveRead(live: st.live) { content }
    }
    @ViewBuilder var content: some View {
        if st.intVis > 0.01 && st.intMethod == 2 { EmptyView() }   // 玉を詰める：数はパネルに
        else if st.intVis > 0.01 && st.intMethod == 1 { waterContent }
        else if st.intVis > 0.01 && st.intShape != 0 { shapeContent }
        else if st.intVis > 0.01 {
            let ax = n == 4 ? "w" : "z", unit = n == 4 ? 8.0 : 4.0, full = n == 4 ? 16.0 : 8.0
            // 何方向も同時：向きの数だけ同じ中身を数える（立方体の窓には 4 次元の z の向きの仲間が無い）
            let cnt = Double(max(1, n == 4 ? st.intAxesList.count : st.intAxesList.filter { $0 != 2 }.count))
            let wf = st.intFront, lb = st.intBack, val = unit * (wf - lb) * cnt, pct = min(1, max(0, val / (full * cnt)))
            let lbOn = lb > -0.9995
            let sg = { (x: Double) -> String in (x < -0.0005 ? "−" : "+") + String(format: "%.2f", abs(x)) }
            VStack(spacing: 3) {
                // ∫ の下に下の端、上に上の端（積分の範囲）
                (Text("∫").font(.system(size: 22, design: .serif))
                 + Text(lbOn ? sg(lb) : "−1").font(.system(size: 10, design: .serif)).baselineOffset(-6)
                 + Text(sg(wf)).font(.system(size: 10, weight: .bold, design: .serif)).foregroundColor(Color(red: 0.98, green: 0.81, blue: 0.91)).baselineOffset(12)
                 + Text("  V(\(ax)) d\(ax)  ＝  " + (lbOn ? "\(Int(unit))（\(sg(wf)) − (\(sg(lb)))）" : "\(Int(unit))（\(ax)＋1）")).font(.system(size: 15, weight: .semibold, design: .serif)))
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.gray.opacity(0.25))
                        Capsule().fill(LinearGradient(colors: st.intColor == 3 ? [Color(red: 1, green: 0.55, blue: 0.08), Color(red: 0.92, green: 0.1, blue: 0.06)]
                                                                               : [.red, .orange, .yellow, .green, .cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing))
                            .frame(width: g.size.width * pct)
                    }
                }.frame(height: 7)
                Text("＝ \(String(format: "%.3f", val)) ／ \(Int(full * cnt))" + (cnt > 1 ? "（\(Int(full)) × \(Int(cnt)) 方向＝同じ中身を \(Int(cnt)) 回数えている）" : "（\(n == 4 ? "超立方体の 4 次元の体積 2⁴" : "立方体の体積 2³")）") + "　\(st.intFilling ? "敷きつめ中" : "取り出し中")")
                    .font(.system(size: 11))
                if st.intAmount < 0.999 {
                    Text("入れる量 \(Int((st.intAmount * 100).rounded()))%：\(ax) ＝ \(sg(-1 + 2 * Double(st.intM) / Double(st.intNax))) まで入れて止める").font(.system(size: 10)).foregroundStyle(Color(red: 0.98, green: 0.81, blue: 0.91))
                }
                Text("輪切り 1 個＝\(n == 4 ? "立方体 2³＝8" : "正方形 2²＝4")・区分の数 n＝\(st.intNax)\(cnt > 1 ? "（1 方向）" : "")（厚み Δ\(ax)＝\(String(format: "%.3f", 2 / Double(st.intNax)))）")
                    .font(.system(size: 9)).foregroundStyle(UIC.sub)
            }
            .foregroundStyle(UIC.text)
            .padding(.horizontal, 14).padding(.vertical, 7)
            .frame(maxWidth: 380)
            .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.96, green: 0.45, blue: 0.71).opacity(0.45)))
            .padding(.bottom, 84)
        }
    }
}

extension IntegralHUD {
    /// 4 次元の形を積む時の式：∫ V(w) dw（V＝その w での輪切りの体積）。数値積分で
    @ViewBuilder var shapeContent: some View {
        let shape = st.intShape, left = n == 3, ax = left ? "z" : "w"
        let wf = st.intFront, lb = st.intBack, val = OrigamiState.slInt(shape, lb, wf, left: left), full = OrigamiState.slTotal(shape, left: left)
        let pct = min(1, max(0, val / max(full, 1e-9)))
        let sg = { (x: Double) -> String in (x < -0.0005 ? "−" : "+") + String(format: "%.2f", abs(x)) }
        let names = left ? ["", "円柱", "x にのびた円柱", "立てたドーナツ 2 つ", "内接する球", "円すい", "立方体（角から切る）", "ドーナツ", "x にのびた円柱"] : ["", "球柱（玉 × 線分）", "デュオシリンダー（円 × 円）", "タイガー", "内接する超球", "球すい（4 次元の円すい）", "超立方体（角から切る）", "球のドーナツ", "キュービンダー（円 × 正方形）"]
        let vNote = left ? ["", "輪切り＝円 πr²", "輪切り＝長方形 2r × 2√(r²−z²)", "輪切り＝4 つの丸", "輪切り＝円 π(1−z²)", "輪切り＝円 π((1−z)⁄2)²", "輪切り＝三角形 → 六角形 → 三角形", "輪切り＝丸が 1 つ ↔ 2 つ", "輪切り＝長方形 2s × 2√(r²−z²)"] : ["", "輪切り＝玉 4⁄3 πr³（どこでも同じ）", "輪切り＝円柱 πr² × 2√(r²−w²)", "輪切り＝上下 2 つのドーナツ 2πR₁ × A(w)", "輪切り＝玉 4⁄3 π(1−w²)^{3⁄2}", "輪切り＝玉 ⁴⁄₃π((1−w)⁄2)³（点まで小さく）", "輪切り＝四面体 → 八面体 → 四面体", "輪切り＝玉が 1 つ ↔ 2 つ", "輪切り＝箱 (2s)² × 2√(r²−w²)"]
        let fNote = left ? ["", "全部で 2πr²", "全部で 2πr³", "全部で 4π²R₂r²", "全部で 4⁄3 π（立方体 8 の約 52%）", "全部で ⅓ × 底 × 高さ ＝ ⅔π", "全部で a³（1 辺 a ＝ 2⁄√3）", "全部で 2πR × πr²", "全部で 2s × πr²"] : ["", "全部で 2 × 4⁄3 πr³", "全部で π²r⁴", "全部で 4π³R₁R₂r²", "全部で π²⁄2（超立方体 16 の約 31%）", "全部で ¼ × 底 × 高さ ＝ ⅔π", "全部で 1（1 辺 1 の超立方体）", "全部で 2πR × ⁴⁄₃πr³", "全部で (2s)² × πr²"]
        VStack(spacing: 3) {
            (Text("∫").font(.system(size: 22, design: .serif))
             + Text(lb > -0.9995 ? sg(lb) : "−1").font(.system(size: 10, design: .serif)).baselineOffset(-6)
             + Text(sg(wf)).font(.system(size: 10, weight: .bold, design: .serif)).foregroundColor(Color(red: 0.98, green: 0.81, blue: 0.91)).baselineOffset(12)
             + Text("  V(\(ax)) d\(ax)").font(.system(size: 15, weight: .semibold, design: .serif)))
            Text(vNote[shape]).font(.system(size: 10)).foregroundStyle(UIC.sub)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.25))
                    Capsule().fill(LinearGradient(colors: [.red, .orange, .yellow, .green, .cyan, .blue, .purple], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * pct)
                }
            }.frame(height: 7)
            Text("＝ \(String(format: "%.3f", val)) ／ \(String(format: "%.3f", full))（\(names[shape])の \(left ? 3 : 4) 次元の体積・\(fNote[shape])）　\(st.intFilling ? "敷きつめ中" : "取り出し中")").font(.system(size: 11))
        }
        .foregroundStyle(UIC.text)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .frame(maxWidth: 400)
        .background(Color(red: 0.06, green: 0.09, blue: 0.16).opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.96, green: 0.45, blue: 0.71).opacity(0.45)))
        .padding(.bottom, 84)
    }
    /// 4 次元の水の式：V(h) ＝ ∫₋₁ʰ 8 dw ＝ 8(h＋1)（連続の積分）
    @ViewBuilder var waterContent: some View {
        let ax = n == 4 ? "w" : "z", unit = n == 4 ? 8.0 : 4.0, full = n == 4 ? 16.0 : 8.0
        let h = st.waterH, val = unit * (h + 1), pct = min(1, max(0, val / full))
        let sg = { (x: Double) -> String in (x < -0.0005 ? "−" : "+") + String(format: "%.2f", abs(x)) }
        let phases = ["上のふたを開ける", "注いでいる", "いっぱい", "底の栓を抜く", "底を全部開けて、かたまりのまま落ちる（自由落下）", "栓をする", "空"]
        VStack(spacing: 3) {
            (Text("V(h) ＝ ").font(.system(size: 15, weight: .semibold, design: .serif))
             + Text("∫").font(.system(size: 22, design: .serif))
             + Text("−1").font(.system(size: 10, design: .serif)).baselineOffset(-6)
             + Text(sg(h)).font(.system(size: 10, weight: .bold, design: .serif)).foregroundColor(Color(red: 0.6, green: 0.85, blue: 1)).baselineOffset(12)
             + Text("  \(Int(unit)) d\(ax)  ＝  \(Int(unit))（h＋1）").font(.system(size: 15, weight: .semibold, design: .serif)))
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.gray.opacity(0.25))
                    Capsule().fill(LinearGradient(colors: [Color(red: 0.1, green: 0.4, blue: 0.95), Color(red: 0.32, green: 0.78, blue: 1)], startPoint: .leading, endPoint: .trailing)).frame(width: g.size.width * pct)
                }
            }.frame(height: 7)
            Text("水位 h ＝ \(sg(h))　＝ \(String(format: "%.3f", val)) ／ \(Int(full))（\(n == 4 ? "4 次元の水の体積" : "3 次元の水の体積")）").font(.system(size: 11))
            if n == 4 && st.waterPhase <= 1 {
                Text("筋は w の向きにまっすぐ落ちる（外の大きい立方体＝ふた ＋W → 内の小さい立方体＝底 −W）。横の胞に重なって見えるのは写しただけで、ぶつかっていない").font(.system(size: 9)).foregroundStyle(Color(red: 0.75, green: 0.85, blue: 1))
            }
            Text((st.waterPhase == 4 && st.waterHoleNow ? (st.holesOpen ? "排水口が開けっぱなし：入る量＝出る量の水位 h≈\(String(format: "%.2f", st.waterHEq)) に近づく" : st.waterVented ? "排水口から抜ける（トリチェリ：深いほど速く出る）。渦でくぼむ" : "通気口が無い：空気と入れ替わりながら、ごぼっ、ごぼっ") : st.waterPhase == 4 && !st.waterVented ? "通気口が無い：空気の圧力で支えられて、ゆっくり" : st.waterPhase == 3 && st.waterHoleNow ? "排水口の栓を抜く" : st.waterDrainH != nil && st.waterPhase == 2 ? "途中で抜く：ふたを閉めて栓を抜く" : phases[max(0, min(6, st.waterPhase))]) + (n == 4 ? "。水面は 3 次元の立方体（浅水方程式で揺れる）" : "。水面は正方形")).font(.system(size: 9)).foregroundStyle(UIC.sub)
        }
        .foregroundStyle(UIC.text)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .frame(maxWidth: 380)
        .background(Color(red: 0.04, green: 0.09, blue: 0.18).opacity(0.86), in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color(red: 0.32, green: 0.78, blue: 1).opacity(0.5)))
        .padding(.bottom, 84)
    }
}

// ---- 積分のタブ：上から順に決めていけば動く（① 形 → ② 求め方 → ③ 見た目 → ④ 動かす → ⑤ 見え方）----
struct IntegralTab: View {
    @ObservedObject var st: OrigamiState
    @AppStorage("waterMoreOpen") var waterMore = false               // 水の「くわしい設定」を開いているか（覚えておく）
    @AppStorage("waterNoteOpen") var waterNote = false               // 水の「説明」を開いているか
    static let shapeNote: [Int: String] = [
        0: "立方体を w の方向に積む。輪切りはどこでも同じ立方体（体積 8）。w の −1 〜 ＋1 に積むと ∫ 8 dw ＝ 16",
        1: "七色の玉を w の方向に積む（玉 × 線分）。どの段も同じ大きさの玉なので、w の方向から見ると全部ぴったり重なって 1 個の球。左の窓は円を積んだ円柱",
        2: "円 × 円（x²＋y² ≤ r²、z²＋w² ≤ r²）。輪切りは円柱で、半径は同じまま高さ 2√(r²−w²) が変わる（まんなかで最も高く、両端でぺちゃんこ）。体積 π²r⁴",
        4: "超立方体にぴったり内接する超球（半径 1）。輪切りは半径 √(1−w²) の玉：底 −W では点 → まんなかで立方体の 6 面に接する大きな玉 → ふた +W でまた点。体積 π²⁄2（超立方体 16 の約 31%）。超球が胞に接する点（胞の真ん中）に、積分が届くと金色の光がともります。左の窓は内接する球（円を積む）",
        8: "キュービンダー（円 × 正方形）：x‐y の正方形 × z‐w の円。輪切りは四角い箱で、底はいつも同じ正方形、高さ 2√(r²−w²) が変わる（デュオシリンダーの円柱が箱になったなかま）。体積 (2s)² × πr²。左の窓は x にのびた円柱",
        5: "球すい（4 次元の円すい。底が玉の円すい）：底（w ＝ −1）に半径 1 の玉、てっぺん（w ＝ ＋1）は点。輪切りは半径 (1−w)⁄2 の玉。体積は ¼ × 底の体積 × 高さ（3 次元の円すいの ⅓ が ¼ に）。左の窓はふつうの円すい（⅓）",
        6: "1 辺 1 の超立方体を、角と角を結ぶ対角線が w の向きになるように立てて切る。輪切りは 点 → 正四面体 → 角の切れた四面体 → 正八面体（まんなか）→ … → 正四面体 → 点。左の窓は立方体を角から（三角形 → 六角形 → 三角形）",
        7: "球のドーナツ：玉（半径 r）を x‐w の面の輪（半径 R）にそってぐるっと回した形（玉 × 円）。輪切りは、はしでは玉 1 つ、まんなかでは輪の左右に玉 2 つ。体積 2πR × ⁴⁄₃πr³（パップス）。左の窓はふつうのドーナツ（丸が 1 つ ↔ 2 つ）",
        3: "輪切りは z の上下に 2 つのドーナツ。w が進むと 2 つが近づいて 1 つにつながり、最後に消える。体積 4π³R₁R₂r²。左の窓は 4 つの丸",
    ]
    static let colorNote: [Int: String] = [
        0: "白い立方体（w の − は水色・＋ はピンクに少し寄る）",
        1: "立方体 1 個は 1 色。底 −W 赤 → ふた +W 紫＝色の並びが目に見えない w の向き",
        2: "どの立方体も同じ七色（下 赤 → 上 紫）。重なった面の色で、立方体が w に詰まっている様子が見える",
        4: "七色の枠だけ（面なし）。枠の重なりで、積んだ立方体の数が見える",
        5: "七色の枠の真ん中に、七つの帯の玉（ドラゴンボールの原型）。真ん中に小さく見える玉は、中にあるのではなく w の遠くの段",
        6: "どの面も、真ん中 赤 → 角 紫 の同心の輪",
        7: "立方体の中に 12 枚の同心の殻と赤い芯。殻ごとに軸を傾けて、交互に逆回り（ジャイロのよう）",
        3: "オレンジの枠の真ん中に、オレンジのガラスの玉と赤い星（お遊び）。外側の立方体だけが今の空間で、中に見える玉は遠くの段",
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // いちばん上：はじめる・止める（下の設定が長くても、すぐ押せるように）
            Sec("動かす", "play.circle") {
                HStack(spacing: 6) {
                    Btn(st.intOn ? "■ やめる" : "▶ はじめる", on: st.intOn) { st.intOn.toggle(); st.intPaused = false; if st.intOn { st.intT = 0; st.waterT = 0; st.swe.reset(); if st.progress < 0.92 { st.playFold() }; st.intApplyView(st.intView) } }
                    if !(st.intMethod == 1 && st.waterNS && st.waterFree) {
                        Btn(st.intMethod == 1 ? (st.intPaused ? "▶ 続ける" : "⏸ 止める") : (st.intPaused ? "▶ 再開" : "⏸ 一時停止"), on: st.intPaused) { st.intPaused.toggle() }.disabled(!st.intOn)
                            .help(st.intMethod == 1 ? "水：注ぐのを止めて、栓も閉めます（流れが止まる）。水は動き続けるので、水面はだんだん静かになります。▶ 続けると、止めた所から" : "止めて、そのまま見る")
                        Btn("最初から") { st.intT = 0; st.waterT = 0; st.swe.reset(); st.intPaused = false }.disabled(!st.intOn)
                    }
                    Btn("横から") { st.intApplyView(st.intView == 0 ? 1 : st.intView) }
                        .help("w の向きを横に向けて、輪切りが並ぶ・積み上がる所を横から見る（平行投影）。向きは ④ の「はじめる時の見る向き」で")
                }
            }
            Sec("① なにの体積？", "cube") {
                Picker("形", selection: $st.intShape) { Text("超立方体").tag(0); Text("球柱").tag(1); Text("デュオシリンダー").tag(2); Text("タイガー").tag(3); Text("超球（内接）").tag(4); Text("球すい（4 次元の円すい）").tag(5); Text("超立方体（角から）").tag(6); Text("球のドーナツ").tag(7); Text("キュービンダー").tag(8) }
                    .onChange(of: st.intShape) { _, _ in st.intT = 0 }
                if st.intShape == 4 {
                    Picker("超球の輪切りの写し方", selection: $st.intExact) { Text("正確（内接がわかる）").tag(true); Text("ぷよぷよ（ゴムボール）").tag(false) }.pickerStyle(.segmented)
                        .help("正確：遠近で写しても、輪切りの玉を正確な形（手前が少し大きい）で描く。積み上げた輪郭は、回してもまんまるの超球のまま＝超立方体にずっと内接して見える。ぷよぷよ：前の近道（玉の真ん中と 3 本の半径の先だけを写す）。遠近だと、回すと輪郭までゴムボールのようにゆれる")
                }
                Text(Self.shapeNote[st.intShape] ?? "").font(.caption2).foregroundStyle(UIC.sub)
            }
            Sec("② どう足す？", "square.stack.3d.up") {
                Picker("求め方", selection: $st.intMethod) { Text("輪切りを積む").tag(0); Text("4 次元の水を注ぐ").tag(1); Text("玉を詰める").tag(2) }.pickerStyle(.segmented)
                if st.intMethod == 1 {
                    // ---- 4 次元の水：よく使うものだけ出して、数字の設定と説明はたたむ ----
                    Picker("水の見た目", selection: $st.waterReal) { Text("線の図").tag(false); Text("リアル").tag(true) }.pickerStyle(.segmented)
                        .help("リアル：映りこみ・屈折・さざ波・キラキラ。線の図：前の図のような水（網目つき）")
                    Toggle("本物の 4D の水（ナビエ–ストークス）", isOn: $st.waterNS).font(.system(size: 11))
                        .help("4 次元の箱を 32×32×32×32（約 105 万）のマスに分けて、水の流れを GPU で本当に解きます（速さは 4 成分、水面は水面までの距離で追う）。切ると前の浅水方程式の水")
                    if st.waterNS {
                        Picker("遊び方", selection: $st.waterFree) { Text("自動（注ぐ → 抜く）").tag(false); Text("手で遊ぶ").tag(true) }.pickerStyle(.segmented)
                            .help("自動：注いで、いっぱいになったら抜く、をくり返す。手で遊ぶ：重力は画面の下。押している間だけ注いで、自分で回してこぼす（▶ はじめる を押さなくても使えます）")
                            .onChange(of: st.waterFree) { _, v in if v { st.waterPlayStart() } }
                    }
                    if st.waterNS && st.waterFree {
                        HStack(spacing: 6) {
                            Text("💧 押している間 注ぐ").font(.system(size: 12, weight: .semibold))
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color(red: 0.15, green: 0.45, blue: 0.85).opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
                                .onLongPressGesture(minimumDuration: 600, maximumDistance: 80, pressing: { p in if p { st.waterPlayStart() }; st.waterPourHold = p }, perform: {})
                            Btn(st.waterLidSet ? "ふた：開いている" : "ふた：閉じている", on: st.waterLidSet) { st.waterLidSet.toggle() }
                            Btn(st.waterBottomSet ? (st.drainMode == 1 ? "排水口：開いている" : "底：開いている") : (st.drainMode == 1 ? "排水口：閉じている" : "底：閉じている"), on: st.waterBottomSet) { st.waterBottomSet.toggle() }
                        }
                        HStack(spacing: 6) {
                            Text("向き").font(.system(size: 11)).foregroundStyle(UIC.sub)
                            Btn("口を上に", on: false) { st.waterPlayStart(); st.waterFreeView(ay: st.waterFreeAY(0), xz: 0, yz: 0) }
                            Btn("ななめ", on: false) { st.waterPlayStart(); st.waterFreeView(ay: st.waterFreeAY(1), xz: 0, yz: 0) }
                            Btn("横倒し", on: false) { st.waterPlayStart(); st.waterFreeView(ay: st.waterFreeAY(2), xz: 0, yz: 0) }
                        }
                        HStack(spacing: 6) {
                            Text("量").font(.system(size: 11)).foregroundStyle(UIC.sub)
                            Btn("空", on: false) { st.waterPlayStart(); st.waterFreeFill(-1) }
                            Btn("半分", on: false) { st.waterPlayStart(); st.waterFreeFill(0) }
                            Btn("ほぼいっぱい", on: false) { st.waterPlayStart(); st.waterFreeFill(0.85) }
                        }
                        Picker("重力の向き", selection: $st.waterGravMode) { Text("画面の奥").tag(0); Text("画面の下").tag(1); Text("+W→−W").tag(2) }.pickerStyle(.segmented)
                            .help("画面の奥：重力は w の消失点へ（積分と同じ。外の立方体＝口 → 内の立方体＝底）。見回しても水は傾かず、⌥＋ドラッグで w を傾けた時だけ流れる。画面の下：見慣れた向き（見る向きを変えても水が傾く）。+W→−W：重力はいつも箱の −w（外の立方体の口 → 内の立方体の底。積分と同じ）で、回しても水はいつも底にたまる（こぼれない）")
                    } else {
                        Picker("抜き方", selection: $st.drainMode) { Text("底を全部").tag(0); Text("排水口").tag(1); Text("交互").tag(2) }.pickerStyle(.segmented)
                            .help("底を全部：かたまりのまま自由落下。排水口：床の真ん中の小さな立方体の穴から、トリチェリ（√(2g・深さ)）で抜けて渦でくぼむ。4 次元では穴と床の広さの比が 3 乗なので、とてもゆっくり")
                    HStack(spacing: 6) {
                        Btn("🚿 今すぐ抜く", on: false) { st.waterDrainNow() }
                            .opacity(st.waterCanDrainNow ? 1 : 0.4)
                            .help("注いでいる途中でも、その水位のまま ふたを閉めて抜きます（抜き方の設定どおり。浅いほど早く空に）")
                        Btn(st.holesOpenSet ? "🕳 排水口：開けっぱなし" : "🕳 排水口：栓をする", on: st.holesOpenSet) {
                            guard st.drainShown else { return }
                            st.holesOpenSet.toggle(); st.waterT = 0; st.waterDOpen = 0
                        }.opacity(st.drainShown ? 1 : 0.4)
                    }
                        Btn(st.waterVent ? "🌬 通気口：あり" : "🌬 通気口：なし", on: st.waterVent) { st.waterVent.toggle() }
                        Picker("ふた", selection: $st.intLidMode) { Text("直角に開く").tag(0); Text("開けたまま").tag(1); Text("消す").tag(2); Text("開けない").tag(3) }.pickerStyle(.segmented)
                            .help("上のふた（+W の胞）を蝶番で 90° 開けて注ぎ、いっぱいで閉じる。底を開けて抜く。左の立方体のふたも連動")
                    }
                    DisclosureGroup(isExpanded: $waterMore) {
                        VStack(alignment: .leading, spacing: 7) {
                            LiveRead(live: st.live) { NumRow("回した時のちゃぷちゃぷ", $st.waterSlosh, 0...2, "%.1f", scale: 1) }
                                .help("箱を回したり、ドラッグの手を急に動かす・止めると、水が感じる「下」がずれて、水が寄ってゆれもどります。0 で なし")
                            LiveRead(live: st.live) { NumRow("渦の強さ（抜く時に残っている回転）", $st.waterSwirl, 0...1, "%.2f", scale: 1) }
                            if st.drainMode != 0 && !(st.waterNS && st.waterFree) {
                                LiveRead(live: st.live) { NumRow("排水口の大きさ（底の幅の何倍か）", $st.drainSize, 0.2...0.9, "%.2f", scale: 1) }
                                    .help("大きいほど早く抜けます。4 次元では穴の広さは 3 次元の体積なので、大きさ 2 倍で 8 倍速く（3 次元のお風呂なら 4 倍）。渦の太さ・ふたの大きさも変わります")
                            }
                            if st.waterNS {
                                LiveRead(live: st.live) { NumRow("粘り（小さいほどさらさら）", $st.waterNu, 0...0.02, "%.3f", scale: 1) }
                                    .help("動粘性 ν（世界の単位）。小さいほど、さらさら動いて ゆれが長く続きます。前は 0.012。マス目が粗いと、計算でなまる分の見かけの粘りも残ります（速さの運び方を MacCormack にして減らしています）")
                                LiveRead(live: st.live) { NumRow("渦の強調（消えかけた渦を足し戻す）", $st.waterVort, 0...8, "%.1f", scale: 1) }
                                    .help("渦度の閉じこめ：粗いマスでならされて消えてしまう細い渦を、回る向きに少し力を足して戻します。4 次元では渦は『回る面』（6 成分）。0 で なし")
                                Picker("マスの細かさ", selection: $st.waterNSRes) { Text("おまかせ").tag(0); Text("16⁴").tag(16); Text("24⁴").tag(24); Text("32⁴").tag(32) }.pickerStyle(.segmented)
                                    .help("4D の水のマス：16⁴ ＝ 約 6.6 万（軽い）・24⁴ ＝ 約 33 万・32⁴ ＝ 約 105 万（細かい）。おまかせは 16。変えると水は最初から")
                                Picker("輪切り（左の窓に）", selection: $st.waterSlice) { Text("なし").tag(0); Text("x ＝ 一定").tag(1); Text("y ＝ 一定").tag(2); Text("z ＝ 一定").tag(3) }.pickerStyle(.segmented)
                                    .help("4D の水を 1 枚切って、残りの 3 つの向きの 3D の水を左の窓に出します（w は左の窓の上下）。右の窓には切り口の立方体を金色の線で。水面の立方体の内側にできる渦のくぼみも、中から見えます")
                                if st.waterSlice > 0 {
                                    LiveRead(live: st.live) { NumRow("切る位置", $st.waterSlicePos, -0.95...0.95, "%+.2f", scale: 1) }
                                }
                            }
                            if st.waterNS && st.waterFree {
                                LiveRead(live: st.live) { NumRow("重力 g（m/s²）", $st.waterG, 1...9.8, "%.1f", scale: 1) }
                                LiveRead(live: st.live) { NumRow("注ぐ勢い", $st.waterPourRate, 0.3...2, "%.1f", scale: 1) }
                                LiveRead(live: st.live) { NumRow("注ぐ場所 x", $st.waterPourX, -0.8...0.8, "%+.2f", scale: 1) }
                                LiveRead(live: st.live) { NumRow("注ぐ場所 y", $st.waterPourY, -0.8...0.8, "%+.2f", scale: 1) }
                                LiveRead(live: st.live) { NumRow("注ぐ場所 z", $st.waterPourZ, -0.8...0.8, "%+.2f", scale: 1) }
                            }
                        }.padding(.top, 4)
                    } label: { Text("くわしい設定").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text) }
                    DisclosureGroup(isExpanded: $waterNote) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("ふた +W を開けて 4 次元の水を注ぎます。水位 h が上がり、V(h) ＝ ∫₋₁ʰ 8 dw ＝ 8(h＋1)（連続の積分）。4 次元の水面は 3 次元の立方体で、浅水方程式（ナビエ–ストークスを深さで平均したもの）で揺れます。いっぱいになったら底を全部開けて、かたまりのまま落ちます。ふつうの 3D の水は 4 次元の体積が 0 なので、いくら注いでも満タンにならない").font(.caption2).foregroundStyle(UIC.sub)
                            if st.waterNS && st.waterFree {
                                Text("マウス：右の窓のドラッグ＝3D に回す、⌥（option）＋ドラッグ＝w を傾ける（X‐W・Y‐W）、⇧＋ドラッグ＝Z‐W。左の窓のドラッグでも w を傾けられます").font(.caption2).foregroundStyle(Color(red: 0.75, green: 0.85, blue: 1))
                                Text("重力は画面の奥（または下）の決まった 1 つの向き。注ぐ水は重力の逆から まっすぐ落ちてきて、箱のいちばん上の所から入ります（押している間ずっと、たまっていきます）。回転で超立方体を傾けると（4D の回転も）、水は箱の中で 4 次元の「下」へ流れます。ふた（+W）や底（−W）を開けて下に向けると、そこからこぼれ落ちます。").font(.caption2).foregroundStyle(UIC.sub)
                            } else {
                                Text("抜き方を「排水口」（か「交互」）にすると、底（−W の胞）の真ん中に排水口、上（+W の胞）に通気口が現れます。ふたは蝶番で 90° 開きます。開けっぱなしで注ぐと、入る量＝出る量の水位で止まります。通気口が無いと、空気と入れ替わりながら ごぼっ、ごぼっ と抜けます").font(.caption2).foregroundStyle(UIC.sub)
                            }
                            if st.waterNS { Text("右の超立方体の水だけが本物の 4D（左の立方体の水は浅水方程式のまま）。8 つの壁の胞の中の水の形を描いています").font(.caption2).foregroundStyle(UIC.sub) }
                        }.padding(.top, 4)
                    } label: { Text("説明").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.text) }
                } else if st.intMethod == 2 {
                    Text("小さな 4 次元の玉（超球）を上（+W）から 1 つずつ落として、箱に詰めます。重力は +W→−W。玉は壁に 1 点でしか接しないので、角やへりにはすきまが残ります（左の立方体は 3 次元の玉）").font(.caption2).foregroundStyle(UIC.sub)
                    HStack(spacing: 6) {
                        Btn("⚽ 1 つ入れる", on: false) { st.ballsDropOne() }
                        Btn(st.ballsAuto ? "どんどん入れる：入れている" : "どんどん入れる", on: st.ballsAuto) { st.ballsAuto.toggle() }
                        Btn("空にする", on: false) { st.ballsClear() }
                    }
                    LiveRead(live: st.live) { NumRow("玉の大きさ（半径）", $st.ballR, 0.1...0.5, "%.2f", scale: 1) }
                    Picker("重力の向き", selection: $st.ballGravMode) { Text("+W→−W（箱の −w）").tag(2); Text("画面の奥").tag(0); Text("画面の下").tag(1) }.pickerStyle(.segmented)
                        .help("+W→−W：重力はいつも箱の −w（積分と同じ）。画面の奥：w の消失点へ（⌥＋ドラッグで傾けると転がる）。画面の下：見慣れた向き（見回すと転がる）。切りかえても見る向きはそのまま、重力だけ なめらかに回る")
                    LiveRead(live: st.live) { NumRow("重力の強さ", $st.ballG, 0...12, "%.1f", scale: 1) }
                        .help("0 で無重力（ふわふわ浮かぶ）")
                    Btn("角に 16 個 ＋ 真ん中（4 次元だけの ふしぎ）", on: false) { st.ballsCorners() }
                        .help("半径が箱の半分の幅の ½ の玉を、超立方体の 16 の角に置くと、真ん中のすきまに入る玉の半径も ちょうど ½（√4 − 1 ＝ 1）。3 次元（左の立方体）では 8 つの角の玉のあいだに、0.37 の玉しか入らない")
                    LiveRead(live: st.live) {
                        Text(String(format: "4 次元：%d 個・詰まり %.0f%%　／　3 次元：%d 個・%.0f%%（立方体を積むと 100%%）", st.balls4.p.count, st.balls4.fill * 100, st.balls3.p.count, st.balls3.fill * 100)).font(.system(size: 11))
                    }
                } else {
                Text("ふた の外から 1 個ずつ飛んできて、底から敷きつめます").font(.caption2).foregroundStyle(UIC.sub)
                if st.intShape != 0 { Text("形を積む時は w の向きだけ").font(.caption2).foregroundStyle(UIC.sub) }
                else {
                HStack(spacing: 6) {
                    Text("入れる向き").font(.system(size: 11))
                    ForEach([(3, "w"), (0, "x"), (1, "y"), (2, "z")], id: \.0) { ax, nm in
                        Btn(nm, on: st.intAxes & (1 << ax) != 0) {
                            let v = st.intAxes ^ (1 << ax)
                            if v != 0 { st.intAxes = v; st.intT = 0 }          // 0 個にはしない。変えたら最初から
                        }
                    }
                }
                Text(st.intAxesList.count > 1 ? "何方向も同時：それぞれの向きから、残り 3 軸の立方体を同時に入れます。同じ中身を \(st.intAxesList.count) 回数える＝イメージ（本当の体積は 16）。区分の数は向きの数で分け合います。枠の色は w 虹・x 赤→黄・y 緑→水色・z 青→紫。玉（レインボーボール・ドラゴンボール・同心球）はどの向きの立方体にも入ります" : (st.intAxesList == [3] ? "w の向きから（ふつうの 4D積分）。2 つ以上選ぶと、何方向も同時" : "この向きから、残り 3 軸の立方体を入れます（縞・同心の柄は w の時だけ。玉はどの向きにも入ります）"))
                    .font(.caption2).foregroundStyle(UIC.sub)
                }
                Text("マス目（二重積分）はこれから").font(.caption2).foregroundStyle(UIC.sub)
                }
            }
            if st.intMethod == 0 && st.intShape == 0 {
            Sec("③ 見た目", "paintbrush") {
                Picker("色・柄", selection: $st.intColor) {
                    Text("白").tag(0); Text("層ごとに 1 色").tag(1)
                    Divider()
                    Text("七色の縞（面）").tag(2); Text("七色の枠だけ").tag(4); Text("レインボーボール（枠＋玉）").tag(5)
                    Divider()
                    Text("同心の七色").tag(6); Text("同心球 3D プリント").tag(7)
                    Divider()
                    Text("ドラゴンボール（お遊び）").tag(3)
                }
                Text(Self.colorNote[st.intColor] ?? "").font(.caption2).foregroundStyle(UIC.sub)
                if st.intColor == 3 {
                    Picker("星", selection: $st.intStars) { Text("一星球").tag(1); Text("四星球").tag(4) }.pickerStyle(.segmented)
                }
                if st.intColor == 5 || st.intColor == 7 {
                    Toggle("球を回す", isOn: $st.intBallSpin)
                }
                Toggle("🔍 1 個を見る（本来の立方体）", isOn: $st.intPreview)
                    .help("積分に詰める立方体 1 個を、4 次元の回転も遠近もかけない、ふつうの 3 次元の立方体として見る。ドラッグで回せます")
                if st.intPreview { IntegralPreview(st: st).frame(height: 230).clipShape(RoundedRectangle(cornerRadius: 8)) }
            }
            }
            Sec("④ 動かし方", "slider.horizontal.3") {
                HStack(spacing: 6) {
                    Btn(st.intOnce ? "1 往復" : "くり返し", on: st.intOnce) { st.intOnce.toggle(); if !st.intOnce && st.intPaused { st.intPaused = false } }
                        .help("押すたびに切りかえ。1 往復：入れて取り出して空になったら止まる（「最初から」でもう一度）。くり返し：ずっとくり返す")
                }
                Picker("はじめる時の見る向き", selection: $st.intView) { Text("そのまま（w から）").tag(0); Text("横（x）").tag(1); Text("横（y）").tag(2) }.pickerStyle(.segmented)
                    .help("▶ はじめる を押した時に、自動でこの向きへ回す。横（x）：輪切りが左右に並ぶ。横（y）：輪切りが下から積み上がる。そのまま：今の向きのまま")
                if st.intMethod == 0 {
                LiveRead(live: st.live) { NumRow("区分の数 n", $st.intN, 2...512, "%.0f 個", scale: 1) }
                LiveRead(live: st.live) { NumRow("入れる量", $st.intAmount, 0.1...1, "%.0f%%", scale: 100) }
                    .help("底から何割まで入れて止めるか（積分の上の端）。100% で全部（∫₋₁¹）、50% なら w ＝ 0 まで（∫₋₁⁰ ＝ 8）")
                LiveRead(live: st.live) { Text("立方体 1 個の厚み Δw ＝ 2／n ＝ \(String(format: "%.3f", 2 / Double(st.intNi)))。n をいくつにしても、積んだ全部は 16").font(.caption2).foregroundStyle(UIC.sub) }
                Picker("積む速さ", selection: $st.intPace) { Text("だんだん速く").tag(0); Text("一定").tag(1) }.pickerStyle(.segmented)
                Picker("取り出し口", selection: $st.intOutOpp) { Text("入れた側から").tag(false); Text("反対側から").tag(true) }.pickerStyle(.segmented)
                }
                if st.intMethod != 1 {   // 水の時は ② の「自動」の所に
                Picker("ふた", selection: $st.intLidMode) { Text("直角に開く").tag(0); Text("開けたまま").tag(1); Text("消す").tag(2); Text("開けない").tag(3) }.pickerStyle(.segmented)
                    .help("入れてくる側の胞（w なら +W）を蝶番で 90° 開けて、いっぱいで閉じる。取り出す前にまた開ける（反対側から出す時は −側）。水は上のふたを開けて注ぎ、底を開けて抜く。左の立方体のふたも連動")
                }
                if st.intMethod == 0 {
                Toggle("外から飛びこむ演出", isOn: $st.intFly)
                }
            }
            Sec("⑤ 積分中の見え方", "eye") {
                Picker("超立方体", selection: $st.intLook) { Text("ふつう").tag(0); Text("線だけ").tag(1); Text("消す").tag(2) }.pickerStyle(.segmented)
                Text("積分している間だけ。やめると元に戻ります").font(.caption2).foregroundStyle(UIC.sub)
            }
        }
    }
}

/// 見本の小窓：積分に詰める立方体 1 個（w ＝ 0 の輪切り）を、4 次元の回転をかけずに＝ゆがみのない本来の立方体として、ゆっくり回して見せる。
///   描き方は超立方体の窓と同じ（柄・玉・星もそのまま）。超立方体そのものと目印・座標軸は描かない。ドラッグで回せる
struct IntegralPreview: View {
    @ObservedObject var st: OrigamiState
    @StateObject private var pv = OrigamiState()
    var body: some View {
        OrigamiPane(n: 4, st: pv, driver: st.driver)
            .onAppear {
                pv.isPreview = true; pv.previewSrc = st
                pv.progress = 1; pv.raster = true; pv.showAxes = false; pv.spaceMode = 2; pv.bgSpace = false; pv.meshOn = false
                pv.intOn = true; pv.intMethod = 0; pv.intLook = 2; pv.intN = 41
                pv.intColor = st.intColor; pv.intStars = st.intStars; pv.intBallSpin = st.intBallSpin
                pv.intItems = [IntItem(t: 0, slot: 0.5, a: 1, fa: 1, fly: false, k: 0)]
                pv.xz = 0.5; pv.yz = -0.45; pv.spinXZ = true; pv.zoom = [1, 1.9]; pv.updateMats()
            }
    }
}
