// 超立方体サイコロ：2 段階で振る。
//   ① 4D のひと振り：超立方体を 4 次元でころころ転がして、胞が 1 つ「いちばん奥（真ん中に小さく見える胞）」で止まる（8 通り）。
//   ② 3D のひと振り：その胞がぽこっと飛び出して、ふつうの立方体のサイコロとして 3 次元でころころ。手前を向いた面が目（6 通り）。
//   目は 2 種類（切りかえ）：
//     24 の目：正方形の面ごとに 1〜24（表と裏は同じ目）。超立方体の中心をはさんで反対側の正方形との和が 25。
//              （サイコロ 1 個＝胞 1 個の上の「向かい合う面」の和は一定にできない：24 組の和の平均が 25 なので、全部 25 にすると同じ目が 2 つできてしまう）
//              正方形はどれも 2 つの胞から出られるので、どの目も 2/48 ＝ 1/24 で公平。
//     48 の目：胞ごとに、ふつうのサイコロの 1〜6（向かい合う面の和が 7）。胞の色 × 点で読む（同じ正方形の表と裏で目がちがう）。
//   一発（既定）：4D と 3D を同時にごろごろ、だんだん遅くなって止まる。4 次元でいちばん手前の胞（外側の大きな立方体）の、
//     まっすぐこちらを向いた面が目（「手前の胞の手前の面」）。
//   公平さ：出る胞（8）と面（6）を先にでたらめに決めて、そこへ転がっていくように見せる。
//   目の絵は画像を使わず、シェーダーで画素ごとに「点の中か」を計算する（OrigamiRaster の rif、p.w ≤ −2 の頂点）
import Foundation
import simd
import SwiftUI

/// 出た目
struct DiceResult: Equatable {
    let cell: Int                         // 胞の番号（0〜7）
    let face: Int                         // 胞の中の面の番号（0〜5：自由な軸の順 × ＋−）
    let pip: Int                          // 48 の目の時の点の数（1〜6）
    let n24: Int                          // 24 の目の時の数（1〜24）
    let mode: Int                         // 振った時の目の数（24・48）
    var n48: Int { cell * 6 + pip }
}

/// 振っている途中
struct DiceRoll {
    var phase = 0, t = 0.0                // 0 4D のひと振り・1 3D のひと振り・2 目を見せる・3 胞にもどる
    let cell: Int, face: Int
    var oneShot = false                   // 一発（4D と 3D を同時に転がして、手前の面がそのまま目）
    let a0: [Double], a1: [Double]        // 角度（X-W・Y-W・Z-W・X-Y・X-Z・Y-Z）の出発と行き先（何回転かぶん足してある）
    var dirs: [SIMD3<Double>] = []        // 胞の 3 本の自由な軸の 3D の向き（①の終わりの形で）
    var p0 = SIMD3<Double>(0, 0, 0), s0 = 0.3
    var qf = simd_quatd(ix: 0, iy: 0, iz: 0, r: 1), spinAxis = SIMD3<Double>(0, 1, 0), spinAng = 0.0, wobAxis = SIMD3<Double>(1, 0, 0)
    static let P0 = 2.6, P1 = 2.3, P2 = 5.5, P3 = 0.7, P0one = 3.8
    var dur0: Double { oneShot ? Self.P0one : Self.P0 }
}

extension OrigamiState {
    // ---- 目の決まり ----
    /// 胞の中の面（自由な軸の k 番目 × 符号）
    static func diceFaces(_ cell: Int) -> [(b: Int, t: Double)] {
        let (a, _) = cellNormal(cell, 4)
        return (0..<4).filter { $0 != a }.flatMap { b in [(b, 1.0), (b, -1.0)] }
    }
    /// 48 の目：胞の中の面の点の数（向かい合う面の和が 7）
    static let dicePips = [1, 6, 2, 5, 3, 4]
    /// 24 の目：正方形 {(a, s), (b, t)} の数。軸の組 6 通り × 符号。向かい合う正方形（符号が両方逆）の和が 25
    static func diceSquare(_ a: Int, _ s: Double, _ b: Int, _ t: Double) -> Int {
        let (p, sp, q, sq) = a < b ? (a, s, b, t) : (b, t, a, s)
        let pairs = [(0, 1), (0, 2), (0, 3), (1, 2), (1, 3), (2, 3)]
        let i = pairs.firstIndex { $0.0 == p && $0.1 == q } ?? 0
        switch (sp > 0, sq > 0) {
        case (true, true): return 2 * i + 1
        case (true, false): return 2 * i + 2
        case (false, false): return 25 - (2 * i + 1)
        case (false, true): return 25 - (2 * i + 2)
        }
    }
    static func diceResult(_ cell: Int, _ face: Int, _ mode: Int) -> DiceResult {
        let (a, s) = cellNormal(cell, 4), f = diceFaces(cell)[face]
        return DiceResult(cell: cell, face: face, pip: dicePips[face], n24: diceSquare(a, s, f.b, f.t), mode: mode)
    }
    /// 胞ごとに、いちばん奥（4D の −w。near なら いちばん手前 ＋w）へ向ける X-W・Y-W・Z-W の角度（90° の倍数）
    static let diceTargets: [[SIMD3<Double>]] = diceTargetsFor(near: false)
    static let diceTargetsNear: [[SIMD3<Double>]] = diceTargetsFor(near: true)
    static func diceTargetsFor(near: Bool) -> [[SIMD3<Double>]] {
        var out = [[SIMD3<Double>]](repeating: [], count: 8)
        for i in 0..<4 { for j in 0..<4 { for k in 0..<4 {
            let ax = Double(i) * .pi / 2, ay = Double(j) * .pi / 2, zw = Double(k) * .pi / 2
            let r = R(2, 3, zw) * R(1, 3, ay) * R(0, 3, ax)
            for c in 0..<8 {
                let (a, s) = cellNormal(c, 4); var v = SIMD4<Double>(0, 0, 0, 0); v[a] = s
                if (r * v).w * (near ? -1 : 1) < -0.999 { out[c].append(SIMD3(ax, ay, zw)) }
            }
        } } }
        return out
    }

    // ---- 振る ----
    var diceRolling: Bool { diceRoll != nil }
    /// 振る（Shift+0・回転バーの 🎲）。組み上がっていなければ組み立てながら
    func rollDice(fixed: (cell: Int, face: Int)? = nil) {
        if progress < 1 { playFold() }
        if explodeE > 0.01 { startXp(0) }
        stopSpins(); stopPP(); cycling = false; tween = nil
        pend = [0, 0, 0, 0, 0]; stepRemain = [0, 0, 0]; stepVel = [0, 0, 0]; presetPar = nil; viewSel = -1
        let cell = fixed?.cell ?? Int.random(in: 0..<8), face = fixed?.face ?? Int.random(in: 0..<6)
        let tg = (diceOneShot ? Self.diceTargetsNear : Self.diceTargets)[cell].randomElement() ?? SIMD3(0, 0, 0)   // 一発は手前の胞・2 段階は奥の胞
        // 一発：3D の向きも決める（手前の胞の、出る面をまっすぐ手前に、その面の上を画面の上に。ほんの少しだけ傾けて立体らしく）
        var tg3: [Double]? = nil
        if diceOneShot {
            if view3 != matrix_identity_double4x4 { view3 = matrix_identity_double4x4; updateMats() }
            let r4 = Self.R(2, 3, tg.z) * Self.R(1, 3, tg.y) * Self.R(0, 3, tg.x), (a, _) = Self.cellNormal(cell, 4)
            let dirs = (0..<4).filter { $0 != a }.map { b -> SIMD3<Double> in var e = SIMD4<Double>(0, 0, 0, 0); e[b] = 1; let v = r4 * e; return SIMD3(v.x, v.y, v.z) }
            let (u, v, N) = Self.diceFaceFrame(dirs, face)
            let tilt = simd_double3x3(simd_quatd(angle: 0.20, axis: SIMD3(1, 0, 0)) * simd_quatd(angle: -0.26, axis: SIMD3(0, 1, 0)))
            let Rf = tilt * simd_double3x3(rows: [u, v, N])
            var M4 = matrix_identity_double4x4
            for i in 0..<3 { for j in 0..<3 { M4[j][i] = Rf[j][i] } }
            tg3 = Self.decompose(M4, [xy, xz, yz])
        }
        let cur = [ax, ay, zw, xy, xz, yz], tn = diceOneShot ? 2...3 : 1...2
        var a1 = cur
        for k in 0..<3 { a1[k] = cur[k] + Self.wrapPi(tg[k] - cur[k]) + 2 * .pi * Double(Int.random(in: tn)) * (Bool.random() ? 1 : -1) }
        for k in 3..<6 { a1[k] = cur[k] + (tg3.map { Self.wrapPi($0[k - 3] - cur[k]) } ?? 0) + 2 * .pi * Double(diceOneShot ? Int.random(in: 1...2) : 1) * (Bool.random() ? 1 : -1) }
        diceRoll = DiceRoll(cell: cell, face: face, oneShot: diceOneShot, a0: cur, a1: a1)
        diceHold = nil
        if diceFlash { diceFlash = false }
    }
    /// 振っている間（1 コマごと）
    func diceTick(_ dt: Double) {
        // 超立方体の面の目の濃さ（いつも描く、または振っている間）
        let want: Double = diceFaces || diceRoll != nil ? 1 : 0
        diceEyeK += (want - diceEyeK) * min(1, dt * 5)
        if abs(diceEyeK - want) < 1e-3 { diceEyeK = want }
        guard var r = diceRoll else { diceDim = 0; return }
        r.t += dt
        switch r.phase {
        case 0:
            // 一発：はじめ勢いよく、だんだん遅く（机の上のサイコロ）、最後に少しだけ行きすぎてコトンと止まる
            let u = min(1, r.t / r.dur0), e = r.oneShot ? Self.easeOutBack(u, 0.45) : Self.easeOutBack(u, 0.7)
            let a = (0..<6).map { r.a0[$0] + (r.a1[$0] - r.a0[$0]) * e }
            ax = Self.wrapPi(a[0]); ay = Self.wrapPi(a[1]); zw = Self.wrapPi(a[2]); xy = Self.wrapPi(a[3]); xz = Self.wrapPi(a[4]); yz = Self.wrapPi(a[5])
            updateMats()
            if u >= 1 && progress >= 1 && explodeE < 0.01 { if r.oneShot { diceReveal(&r) } else { diceStart3D(&r) } }
        case 1:
            if r.t >= DiceRoll.P1 { diceReveal(&r) }
        case 2:
            if r.t >= 2.8 && diceFlash { withAnimation(.easeOut(duration: 0.4)) { diceFlash = false } }
            if r.t >= DiceRoll.P2 { r.phase = 3; r.t = 0 }
        default:
            if r.t >= DiceRoll.P3 { diceRoll = nil; diceHold = SIMD3(ax, ay, zw); diceDim = 0; return }
        }
        diceDim = r.oneShot ? diceHiK : r.phase == 0 ? 0 : r.phase == 1 ? min(1, r.t / 0.4) : r.phase == 2 ? 1 : max(0, 1 - r.t / DiceRoll.P3)
        diceRoll = r
    }
    /// 目が出た（記録して、ドン！）
    private func diceReveal(_ r: inout DiceRoll) {
        r.phase = 2; r.t = 0
        let res = Self.diceResult(r.cell, r.face, diceMode)
        diceRes = res
        diceHist.insert(res, at: 0); if diceHist.count > 12 { diceHist.removeLast() }
        diceCount24[res.n24 - 1] += 1; diceCount48[res.n48 - 1] += 1
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) { diceFlash = true }
    }
    /// 一発の出た面の光り具合（0〜1。出た瞬間にふくらんで、終わりにすーっと消える）
    var diceHiK: Double {
        guard let r = diceRoll, r.oneShot, r.phase >= 2 else { return 0 }
        return r.phase == 2 ? min(1, r.t / 0.25) : max(0, 1 - r.t / DiceRoll.P3)
    }
    /// 超立方体の辺をうすくする度合い（一発で本物のサイコロになった時は、ほぼ消す。2 段階の②はうっすら残す）
    var diceLineDim: Double { diceRoll?.oneShot == true ? diceHiK : 0.8 * diceDim }
    /// ①の終わり：胞の向きと大きさを測って、②（3D のサイコロ）の出発と行き先を決める
    private func diceStart3D(_ r: inout DiceRoll) {
        let (a, s) = Self.cellNormal(r.cell, 4), H = Self.half
        var nc = [0.0, 0, 0, 0]; nc[a] = s * H
        let (p0, k0) = place(nc, 4)
        r.p0 = p0; r.s0 = H * k0
        r.dirs = (0..<4).filter { $0 != a }.map { b in let v = m4 * SIMD4<Double>(b == 0 ? 1 : 0, b == 1 ? 1 : 0, b == 2 ? 1 : 0, b == 3 ? 1 : 0); return simd_normalize(SIMD3(v.x, v.y, v.z)) }
        // 出る面を手前（+z）に、その面の上（v）を画面の上（+y）に。少し傾けて上と右の面も見せる
        let (u, v, N) = Self.diceFaceFrame(r.dirs, r.face)
        let M = simd_double3x3(rows: [u, v, N])
        let tilt = simd_double3x3(simd_quatd(angle: 0.34, axis: SIMD3(1, 0, 0)) * simd_quatd(angle: -0.40, axis: SIMD3(0, 1, 0)))
        r.qf = simd_quatd(tilt * M)
        let inv = r.qf.inverse
        r.spinAxis = inv.angle > 1e-6 ? inv.axis : SIMD3(0, 1, 0)
        r.spinAng = inv.angle + 4 * .pi                                    // 2 回転ぶん多く（同じ向きに着く）
        r.wobAxis = simd_normalize(simd_cross(r.spinAxis, SIMD3(0.3, 0.8, 0.5)))
        r.phase = 1; r.t = 0
    }
    /// サイコロの面 fi の向き（u 右・v 上・N 外向き、u × v ＝ N）
    static func diceFaceFrame(_ dirs: [SIMD3<Double>], _ fi: Int) -> (SIMD3<Double>, SIMD3<Double>, SIMD3<Double>) {
        let k = fi / 2, t: Double = fi % 2 == 0 ? 1 : -1, N = dirs[k] * t
        let o = (0..<3).filter { $0 != k }
        var u = dirs[o[0]], v = dirs[o[1]]
        if simd_dot(simd_cross(u, v), N) < 0 { swap(&u, &v) }
        return (u, v, N)
    }
    /// ②の今のサイコロ（真ん中・大きさの半分・向き）
    func diceDie() -> (c: SIMD3<Double>, s: Double, q: simd_quatd)? {
        guard let r = diceRoll, r.phase >= 1, r.dirs.count == 3 else { return nil }
        let H = Self.half, p1 = SIMD3<Double>(0, 0, 0.35 * H), s1 = 0.78 * H
        switch r.phase {
        case 1:
            let u = min(1, r.t / DiceRoll.P1), e = 1 - pow(1 - u, 3)
            let es = Self.easeOutBack(min(1, u / 0.3), 1.2)
            let bounce = 0.9 * H * abs(sin(2.6 * .pi * u)) * pow(1 - u, 2)
            let c = r.p0 + (p1 - r.p0) * Self.smoother(u / 0.35) + SIMD3(0, bounce, 0)
            let q = r.qf * simd_quatd(angle: 0.9 * sin(.pi * e) * (1 - e), axis: r.wobAxis) * simd_quatd(angle: r.spinAng * (1 - e), axis: r.spinAxis)
            return (c, r.s0 + (s1 - r.s0) * es, q)
        case 2: return (p1, s1, r.qf)
        default:
            let e = Self.smoother(min(1, r.t / DiceRoll.P3))
            return (p1 + (r.p0 - p1) * e, s1 * (1 - e) + r.s0 * 0.2 * e, r.qf)
        }
    }
    /// 振ったあと、W を動かすまで遠近のまま（平行投影にすると奥の胞がわからなくなる）
    var diceKeepsPersp: Bool {
        if diceRoll != nil { return true }
        guard let h = diceHold else { return false }
        return abs(Self.wrapPi(ax - h.x)) < 1e-3 && abs(Self.wrapPi(ay - h.y)) < 1e-3 && abs(Self.wrapPi(zw - h.z)) < 1e-3
    }
    func diceClearStats() { diceHist = []; diceCount24 = [Int](repeating: 0, count: 24); diceCount48 = [Int](repeating: 0, count: 48); diceRes = nil }
    static func diceCellName(_ c: Int) -> String { ["−W", "+Y", "−Y", "+X", "−X", "+Z", "−Z", "+W"][c] }
}

// ---- 描く（超立方体の窓）----
@inline(__always) private func gpuD(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }
/// 色を 1 つの数に（シェーダーで戻す。2^24 までは float で正確）
@inline(__always) private func packC(_ c: SIMD3<Float>) -> Float {
    let q = simd_clamp(c, .zero, SIMD3(repeating: 1)) * 255
    return Float((Int(q.x.rounded()) << 16) | (Int(q.y.rounded()) << 8) | Int(q.z.rounded()))
}

extension OrigamiRenderer {
    /// サイコロの三角形：超立方体の面の目（重ねる）と、②の立方体のサイコロ（奥行きあり）
    func diceGeometry(eye: SIMD3<Double>) -> [IntTriBatch] {
        guard n == 4 else { return [] }
        let H = OrigamiState.half
        let kA = max(0, min(1, (st.progress - 0.92) / 0.08)) * max(0, 1 - 4 * st.explodeE)
        var out: [IntTriBatch] = []
        let cols = st.cellColors(4).map { OrigamiState.rgb($0) }
        // 超立方体の面の目
        let eyeA = st.diceEyeK * kA * (1 - 0.8 * st.diceDim)
        if eyeA > 0.01 {
            var vs: [IntVert] = []
            let G = 6, m = Float(-(2 + (st.diceFaces ? 0.9 : 0.7) * eyeA))
            func square(_ fix: [(Int, Double)], _ fr: (Int, Int), _ inset: Double, _ code: Int, _ col: SIMD3<Float>) {
                var P = [[SIMD3<Double>]]()
                for i in 0...G {
                    var row: [SIMD3<Double>] = []
                    for j in 0...G {
                        var p = [0.0, 0, 0, 0]
                        for (ax, v) in fix { p[ax] = v * H }
                        p[fr.0] = (-1 + 2 * Double(i) / Double(G)) * H * inset; p[fr.1] = (-1 + 2 * Double(j) / Double(G)) * H * inset
                        row.append(st.place(p, 4).0)
                    }
                    P.append(row)
                }
                let pk = packC(col), cd = Float(code)
                for i in 0..<G { for j in 0..<G {
                    func V(_ a: Int, _ b: Int) -> IntVert { IntVert(p: SIMD4(gpuD(P[a][b]), m), c: SIMD4(Float(a) / Float(G), Float(b) / Float(G), cd, pk)) }
                    vs += [V(i, j), V(i + 1, j), V(i + 1, j + 1), V(i, j), V(i + 1, j + 1), V(i, j + 1)]
                } }
            }
            // 一発で出た面は、下で光る面として描く（ここでは描かない）
            let hiOn = st.diceHiK > 0.001, hr = st.diceRoll
            let hiSq: Int = hiOn && hr != nil ? OrigamiState.diceResult(hr!.cell, hr!.face, 24).n24 : -1
            if st.diceMode == 24 {
                for a in 0..<4 { for b in (a + 1)..<4 { for s in [1.0, -1.0] { for t in [1.0, -1.0] {
                    if OrigamiState.diceSquare(a, s, b, t) == hiSq { continue }
                    let fr = (0..<4).filter { $0 != a && $0 != b }
                    square([(a, s), (b, t)], (fr[0], fr[1]), 1, OrigamiState.diceSquare(a, s, b, t), SIMD3(1, 1, 1))
                } } } }
            } else {
                for c in 0..<8 {
                    let (a, s) = OrigamiState.cellNormal(c, 4), col = simd_mix(cols[c], SIMD3(repeating: 1), SIMD3(repeating: 0.45))
                    for (fi, f) in OrigamiState.diceFaces(c).enumerated() {
                        if hiOn && hr?.cell == c && hr?.face == fi { continue }
                        let fr = (0..<4).filter { $0 != a && $0 != f.b }
                        square([(a, s), (f.b, f.t * 0.84)], (fr[0], fr[1]), 0.84, 100 + OrigamiState.dicePips[fi], col)
                    }
                }
            }
            out.append(IntTriBatch(add: false, verts: vs))
        }
        // 一発で目が決まったら：手前の胞（外側の大きな立方体）を、すけない本物のサイコロに（胞の色・6 面に目）。
        //   手前の面が「あたり！」（金のふち・明るく脈打つ・少しせり出す）。手前の胞は 4 次元の奥行きが一定なので、写った形はふつうの立方体
        if let r = st.diceRoll, r.oneShot, st.diceHiK > 0.001 {
            let (a, s) = OrigamiState.cellNormal(r.cell, 4)
            func d3(_ ax: Int) -> SIMD3<Double> { var e = SIMD4<Double>(0, 0, 0, 0); e[ax] = 1; let v = st.m4 * e; return simd_normalize(SIMD3(v.x, v.y, v.z)) }
            var cp = [0.0, 0, 0, 0]; cp[a] = s * H
            let C = st.place(cp, 4).0
            let free = (0..<4).filter { $0 != a }, dirs = free.map(d3)
            var e1 = cp; e1[free[0]] = H
            let h = simd_distance(st.place(e1, 4).0, C)                    // 写った立方体の半分の大きさ
            let L = simd_normalize(SIMD3<Double>(-0.45, 0.6, 0.65))
            let al = st.diceHiK, t2 = r.phase == 2 ? r.t : DiceRoll.P2
            let glow = 1 + 0.3 * exp(-t2 * 1.4) * (0.5 + 0.5 * sin(t2 * 9))   // あたりの面の脈打ち（だんだん落ち着く）
            let pop = 0.07 * sin(.pi * min(1, t2 / 0.4))                      // あたりの面が一瞬せり出す
            var vs: [IntVert] = []
            for fi in 0..<6 {
                let (u, v, N) = OrigamiState.diceFaceFrame(dirs, fi)
                let win = fi == r.face, f = OrigamiState.diceFaces(r.cell)[fi]
                let res = OrigamiState.diceResult(r.cell, fi, st.diceMode)
                let num = st.diceMode == 24 ? OrigamiState.diceSquare(a, s, f.b, f.t) : 100 + res.pip
                let sh = 0.5 + 0.5 * max(0, simd_dot(N, L))
                let col = cols[r.cell] * Float(win ? min(1.35, (0.75 + 0.25 * sh) * glow) : sh)
                let cd = Float((win ? 2000 : 1000) + num), pk = packC(col), m = Float(-(2 + al))
                let O = C + N * h * (1 + (win ? pop : 0))
                func V(_ x: Double, _ y: Double) -> IntVert {
                    IntVert(p: SIMD4(gpuD(O + u * h * (2 * x - 1) + v * h * (2 * y - 1)), m), c: SIMD4(Float(x), Float(y), cd, pk))
                }
                vs += [V(0, 0), V(1, 0), V(1, 1), V(0, 0), V(1, 1), V(0, 1)]
            }
            out.append(IntTriBatch(add: false, verts: vs, depth: true))
        }
        // ②の立方体のサイコロ
        if let r = st.diceRoll, let d = st.diceDie() {
            let R = simd_double3x3(d.q), base = cols[r.cell]
            let L = simd_normalize(SIMD3<Double>(-0.45, 0.6, 0.65))
            var vs: [IntVert] = []
            for fi in 0..<6 {
                let (u, v, N) = OrigamiState.diceFaceFrame(r.dirs, fi)
                let ru = R * u, rv = R * v, rn = R * N
                let sh = Float(0.5 + 0.5 * max(0, simd_dot(rn, L)))
                let res = OrigamiState.diceResult(r.cell, fi, st.diceMode)
                let code = 1000 + (st.diceMode == 24 ? res.n24 : 100 + res.pip)
                let pk = packC(base * sh), cd = Float(code)
                func V(_ a: Double, _ b: Double) -> IntVert {
                    let p = d.c + (rn + ru * (2 * a - 1) + rv * (2 * b - 1)) * d.s
                    return IntVert(p: SIMD4(gpuD(p), -3), c: SIMD4(Float(a), Float(b), cd, pk))
                }
                vs += [V(0, 0), V(1, 0), V(1, 1), V(0, 0), V(1, 1), V(0, 1)]
            }
            out.append(IntTriBatch(add: false, verts: vs, depth: true))
        }
        return out
    }
}

// ---- 目の絵（ドン！の札・記録）：シェーダーと同じ点の並び ----
enum DiceArt {
    static let digits = [31599, 11415, 29671, 29647, 23497, 31183, 31215, 29257, 31727, 31695]   // 3×5 の点の数字（上の行から 3 ビットずつ）
    /// 点の真ん中（0〜1、y は下向き）と半径
    static func dots(_ num: Int, classic: Bool) -> [(CGPoint, Double)] {
        if classic {
            let L = 0.26, M = 0.5, Hh = 0.74, r = 0.092
            var p: [(Double, Double)] = []
            if num % 2 == 1 { p.append((M, M)) }
            if num >= 2 { p += [(L, Hh), (Hh, L)] }
            if num >= 4 { p += [(Hh, Hh), (L, L)] }
            if num == 6 { p += [(L, M), (Hh, M)] }
            return p.map { (CGPoint(x: $0.0, y: 1 - $0.1), r) }
        }
        let nd = num >= 10 ? 2 : 1, cols = nd == 2 ? 7 : 3, pp = nd == 2 ? 0.118 : 0.15
        let x0 = 0.5 - 0.5 * Double(cols - 1) * pp, y0 = 0.5 + 2 * pp
        var out: [(CGPoint, Double)] = []
        for ci in 0..<cols { for ri in 0..<5 {
            var dg = num, col = ci
            if nd == 2 { if ci == 3 { continue }; dg = ci < 3 ? num / 10 : num % 10; col = ci < 3 ? ci : ci - 4 }
            if (digits[dg] >> ((4 - ri) * 3 + (2 - col))) & 1 == 0 { continue }
            out.append((CGPoint(x: x0 + Double(ci) * pp, y: 1 - (y0 - Double(ri) * pp)), 0.38 * pp))
        } }
        return out
    }
}

/// サイコロの面 1 枚の絵
struct DiceFaceView: View {
    let num: Int, classic: Bool, color: Color
    var body: some View {
        Canvas { ctx, size in
            let S = min(size.width, size.height), R = CGRect(x: (size.width - S) / 2, y: (size.height - S) / 2, width: S, height: S)
            let shape = Path(roundedRect: R, cornerRadius: S * 0.16)
            ctx.fill(shape, with: .color(color))
            ctx.stroke(Path(roundedRect: R.insetBy(dx: S * 0.03, dy: S * 0.03), cornerRadius: S * 0.14), with: .color(.black.opacity(0.25)), lineWidth: S * 0.05)
            for (c, r) in DiceArt.dots(num, classic: classic) {
                let p = CGPoint(x: R.minX + c.x * S, y: R.minY + c.y * S), rr = r * S
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr * 1.3, y: p.y - rr * 1.3, width: rr * 2.6, height: rr * 2.6)), with: .color(.black.opacity(0.28)))
                ctx.fill(Path(ellipseIn: CGRect(x: p.x - rr, y: p.y - rr, width: rr * 2, height: rr * 2)), with: .color(.white))
            }
        }
    }
}

/// 出た目の「ドン！」（超立方体の窓の真ん中）
struct DiceHUD: View {
    let n: Int
    @ObservedObject var st: OrigamiState
    var body: some View {
        ZStack {
            if n == 4, st.diceFlash, let r = st.diceRes {
                let col = PaletteEditor.color(st.cellColors(4)[r.cell])
                let small = st.diceOneShot
                VStack(spacing: 6) {
                    if small { Text("出目").font(.system(size: 20, weight: .heavy, design: .rounded)).foregroundStyle(Color(red: 1, green: 0.83, blue: 0.35)) }
                    DiceFaceView(num: r.mode == 24 ? r.n24 : r.pip, classic: r.mode == 48, color: col).frame(width: small ? 76 : 120, height: small ? 76 : 120)
                    Text(r.mode == 24 ? "\(r.n24)" : "\(r.pip)").font(.system(size: small ? 32 : 46, weight: .heavy, design: .rounded)).foregroundStyle(.white)
                    Text(r.mode == 24 ? "\(OrigamiState.diceCellName(r.cell)) の胞のサイコロ・裏の面は \(OrigamiState.diceResult(r.cell, r.face ^ 1, 24).n24)・超立方体の反対側は \(25 - r.n24)"
                                      : "\(OrigamiState.diceCellName(r.cell)) の胞（この色）の \(r.pip)・48 のうち No.\(r.n48)")
                        .font(.system(size: 11, weight: .semibold)).foregroundStyle(UIC.sub)
                }
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(UIC.panel.opacity(0.88), in: RoundedRectangle(cornerRadius: 18))
                .overlay(RoundedRectangle(cornerRadius: 18).stroke(col.opacity(0.8), lineWidth: 2))
                .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
        }
        // 一発の時は、大きな光る面にかぶらないように右上へ小さく
        .padding(st.diceOneShot ? 14 : 0)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: st.diceOneShot ? .topTrailing : .center)
    }
}

/// 回転タブの「サイコロ」の欄
struct DiceSection: View {
    @ObservedObject var st: OrigamiState
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 6) {
                Btn("🎲 振る（⇧0）", on: st.diceRolling) { st.rollDice() }.help("超立方体サイコロを振る：①4D でころころ → 奥の胞が決まる ②その胞が飛び出して 3D でころころ → 手前の面が目")
                Btn("24 の目", on: st.diceMode == 24) { st.diceMode = 24 }.help("正方形の面ごとに 1〜24（表と裏は同じ目）。超立方体の中心をはさんで反対側の面との和が 25（サイコロ 1 個の裏の面ではない）。どの目も 1/24")
                Btn("48 の目", on: st.diceMode == 48) { st.diceMode = 48 }.help("胞ごとにふつうのサイコロの 1〜6。胞の色 × 点で 48 通り（同じ正方形の表と裏で目がちがう）")
            }
            HStack(spacing: 6) {
                Btn("一発", on: st.diceOneShot) { st.diceOneShot = true }.help("4D と 3D を同時にごろごろ転がして、だんだん遅くなって止まる。4 次元でいちばん手前の胞（外側の大きな立方体）の、まっすぐこちらを向いた面が目")
                Btn("2 段階", on: !st.diceOneShot) { st.diceOneShot = false }.help("①4D でころころ → 奥の胞が決まる ②その胞が飛び出して 3D でころころ → 手前の面が目")
            }
            HStack(spacing: 6) {
                Btn("超立方体にいつも目を描く", on: st.diceFaces) { st.diceFaces.toggle() }.help("振っていない時も、超立方体の面に目を描く")
                if !st.diceHist.isEmpty { Btn("記録を消す") { st.diceClearStats() } }
            }
            Text(st.diceMode == 24 ? "24 の目：超立方体の正方形は 8 胞 × 6 面 ÷ 2 ＝ 24 枚（1 枚を 2 つの胞が分け合う）。どの正方形も 2 つの胞から出られるので公平"
                                   : "48 の目：8 胞 × 6 面 ＝ 48。同じ正方形でも、どちらの胞から見るか（紙の表と裏）で別の目")
                .font(.caption2).foregroundStyle(UIC.sub).fixedSize(horizontal: false, vertical: true)
            if !st.diceHist.isEmpty {
                HStack(spacing: 4) {
                    Text("これまで").font(.caption2).foregroundStyle(UIC.sub)
                    ForEach(Array(st.diceHist.prefix(10).enumerated()), id: \.offset) { _, r in
                        DiceFaceView(num: r.mode == 24 ? r.n24 : r.pip, classic: r.mode == 48, color: PaletteEditor.color(st.cellColors(4)[r.cell])).frame(width: 22, height: 22)
                    }
                }
                // 出た回数（公平か見る）
                let cnt = st.diceMode == 24 ? st.diceCount24 : st.diceCount48, total = cnt.reduce(0, +)
                if total > 0 {
                    Canvas { ctx, size in
                        let mx = Double(max(1, cnt.max() ?? 1)), w = size.width / Double(cnt.count)
                        for (i, c) in cnt.enumerated() {
                            let h = (size.height - 2) * Double(c) / mx
                            ctx.fill(Path(CGRect(x: Double(i) * w + 0.5, y: size.height - h, width: max(1, w - 1), height: h)), with: .color(UIC.cyan.opacity(0.75)))
                        }
                    }.frame(height: 28)
                    Text("出た回数（\(st.diceMode) の目ごと・全部で \(total) 回）").font(.caption2).foregroundStyle(UIC.sub)
                }
            }
        }
    }
}
