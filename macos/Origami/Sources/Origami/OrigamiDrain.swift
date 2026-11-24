// 下水道（ウェブ版の drawHoles と同じ）：穴の工事で、湯船の底（−W の胞）の真ん中に排水口、上（+W の胞）に通気口を開ける。
//   工事をすると、ドリルで掘るように穴がだんだん大きくなる（回る刃と火花、1.6 秒）。穴はふだんの画面にもずっと付いている。
//   穴には透ける格子のふた（グレーチング）：ほかの胞のふたと同じく、辺（y ＝ +R）を蝶番にガチャッと 90° 開く（少し行き過ぎて戻る）。
//   排水口のふたが開くと、穴の向こう（w ＜ −H）へ続く 4 次元の排水管が見える：遠近で「内側ほど小さく」写るので、穴の立方体の内側に、奥へ縮んでいく管。
//   左の立方体の窓は 1 つ下の仲間：底（z ＝ −H）の真ん中に排水口、上（z ＝ +H）に通気口（正方形の穴）
import Foundation
import QuartzCore
import simd

extension OrigamiState {
    /// 穴の絵が動いている間（描き直しの合図に時刻を入れる）
    var holesAnimating: Bool {
        guard holesBuilt else { return false }
        let now = CACurrentMediaTime()
        return now - holesBuiltAt < 1.7 || holeDA > 0.03 || holeDHL > 0 || holeVHL > 0 || abs(holeVA - (waterVent ? 1 : 0)) > 1e-4 || abs(holeDA - holeDTarget) > 1e-4
    }
    /// 排水口の格子のふたを開ける度合い（開けっぱなし＝いつも、水を排水口で抜く時＝栓を抜く間）
    var holeDTarget: Double { holesOpen ? 1 : (intOn && intMethod == 1 && waterHoleNow ? waterBLid : 0) }
}

@inline(__always) private func gpuH(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    func holesGeometry(_ rods: inout [TLRod]) -> [IntTriBatch] {
        guard n <= 4, st.holesBuilt else { return [] }
        let k = max(0, min(1, (st.progress - 0.92) / 0.08)) * max(0, 1 - 4 * st.explodeE)
        guard k > 0.01 else { return [] }
        let now = CACurrentMediaTime(), gr = max(0, min(1, (now - st.holesBuiltAt) / 1.6)), smg = gr * gr * (3 - 2 * gr), drilling = gr < 1
        let H = OrigamiState.half, HR = OrigamiState.wHOLE * H * smg, VR = 0.1 * H * smg
        // 格子のふたの開き具合を、目標へ 1 秒に 2.2 の速さで（2 つの窓で 2 回進めないように、時刻で）
        let dtH = min(0.1, max(0, now - st.holeLastT)); st.holeLastT = now
        let dT = st.holeDTarget, vT = st.waterVent ? 1.0 : 0
        func step(_ x: Double, _ tg: Double) -> Double { x + (tg > x ? 1 : -1) * min(abs(tg - x), dtH * 2.2) }
        let dMoving = abs(st.holeDA - dT) > 1e-4, vMoving = abs(st.holeVA - vT) > 1e-4
        st.holeDA = step(st.holeDA, dT); st.holeVA = step(st.holeVA, vT)
        st.holeDHL = dMoving ? 1 : max(0, st.holeDHL - dtH * 2); st.holeVHL = vMoving ? 1 : max(0, st.holeVHL - dtH * 2)   // 開け閉めの途中は明るく（止まったら 0.5 秒で戻る）
        func back(_ x: Double) -> Double { let y = x - 1; return 1 + 2.7 * y * y * y + 1.7 * y * y }   // 行き過ぎて戻る（ガチャッ）
        // 穴の色：排水口は底の胞、通気口はふたの胞と同じ色にして、明るさだけ変える
        let pc = st.cellColors(n), cD = OrigamiState.rgb(pc[0]), cV = OrigamiState.rgb(pc[pc.count - 1])
        func lit(_ c: SIMD3<Float>, _ m: Float, _ a: Float) -> SIMD3<Float> { simd_min(SIMD3<Float>(repeating: 1), c * m + a) }
        struct Pal { let rim, line, pane, hl: SIMD3<Float> }
        func mk(_ c: SIMD3<Float>) -> Pal { Pal(rim: lit(c, 1.25, 0.15), line: lit(c, 1.4, 0.22), pane: lit(c, 0.9, 0.06), hl: lit(c, 1.5, 0.45)) }
        let PD = mk(cD), PV = mk(cV)
        var tris: [IntVert] = [], pipe: [IntVert] = []
        func L(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Float>, _ br: Double = 1) { rods.append(TLRod(a: SIMD4(gpuH(a), 0), b: SIMD4(gpuH(b), 0), col: SIMD4(c, Float(br * k / 1.4)))) }
        func F(_ list: inout [IntVert], _ q: [SIMD3<Double>], _ c: SIMD3<Float>, _ al: Double) {
            let a = Float(al * k); for i in [0, 1, 2, 0, 2, 3] { list.append(IntVert(p: SIMD4(gpuH(q[i]), 1), c: SIMD4(c * a, a))) }
        }
        let oa = min(1, st.holeDA), beyond = st.holeDA > 0.03, LEN = 1.3 * H, NR = 7, flow = (now * 0.35).truncatingRemainder(dividingBy: 1), pulse = 0.75 + 0.25 * sin(now * 1.7)
        if n == 4 {
            func S(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> SIMD3<Double> { st.place([x, y, z, w], 4).0 }
            let VP = SIMD3<Double>(-0.5 * H, 0.5 * H, -0.5 * H)
            let corners = (0..<8).map { v in SIMD3<Double>(v & 1 != 0 ? 1 : -1, v & 2 != 0 ? 1 : -1, v & 4 != 0 ? 1 : -1) }
            let edges = (0..<8).flatMap { a in (0..<3).compactMap { j in a & (1 << j) == 0 ? (a, a | 1 << j) : nil } }
            let quads: [[Int]] = (0..<3).flatMap { j in (0..<2).map { s in let o1 = (j + 1) % 3, o2 = (j + 2) % 3, b = s << j; return [b, b | 1 << o1, b | 1 << o1 | 1 << o2, b | 1 << o2] } }
            func cube(_ cx: SIMD3<Double>, _ R: Double, _ w: Double) -> [SIMD3<Double>] { corners.map { S(cx.x + $0.x * R, cx.y + $0.y * R, cx.z + $0.z * R, w) } }
            func cubeEdges(_ vs: [SIMD3<Double>], _ c: SIMD3<Float>, _ br: Double = 1) { for (a, b) in edges { L(vs[a], vs[b], c, br) } }
            cubeEdges(cube(.zero, HR, -H), PD.rim)                            // 排水口の穴のふち
            cubeEdges(cube(VP, VR, H), PV.rim)                                // 通気口の穴のふち
            // 透ける立体の格子のふた：x・y・z の 3 方向に細い棒（±1 と ±1/3 の所）＋ 6 面にうっすら透ける板。hl＝開け閉めの途中の明るさ
            func grate(_ cx: SIMD3<Double>, _ R: Double, _ w0: Double, _ sgn: Double, _ x: Double, _ hl: Double, _ pal: Pal) {
                let th = Double.pi / 2 * back(x), cs = cos(th), sn = sin(th), BAR = [-1.0, -1.0 / 3, 1.0 / 3, 1]
                func mix(_ c: SIMD3<Float>, _ k2: Float) -> SIMD3<Float> { (c + (pal.hl - c) * Float(hl)) * k2 }
                func hp(_ a: Double, _ b: Double, _ c: Double) -> SIMD3<Double> { let sd = R * (1 - b); return S(cx.x + a * R, cx.y + R - sd * cs, cx.z + c * R, w0 + sgn * sd * sn) }
                for dd in 0..<3 { for p in BAR { for q in BAR {
                    let o = [0, 1, 2].filter { $0 != dd }; var A = [0.0, 0, 0], B = [0.0, 0, 0]; A[dd] = -1; B[dd] = 1; A[o[0]] = p; B[o[0]] = p; A[o[1]] = q; B[o[1]] = q
                    let e: Float = abs(p) == 1 && abs(q) == 1 ? 1 : 0.6
                    L(hp(A[0], A[1], A[2]), hp(B[0], B[1], B[2]), mix(pal.line, e))
                } } }
                let cv = corners.map { hp($0.x, $0.y, $0.z) }
                for qd in quads { F(&tris, qd.map { cv[$0] }, mix(pal.pane, Float(1 + 2.5 * hl)), 0.22) }
                if hl > 0.01 {   // 蝶番の面（y ＝ +R の正方形。ここは動かない）を明るく
                    let hv = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { hp($0.0, 1, $0.1) }
                    F(&tris, hv, pal.hl * Float(3 * hl), 0.3); for i in 0..<4 { L(hv[i], hv[(i + 1) % 4], pal.hl * Float(hl)) }
                }
            }
            if !drilling { grate(.zero, HR, -H, -1, st.holeDA, st.holeDHL, PD); grate(VP, VR, H, 1, st.holeVA, st.holeVHL, PV) }
            if beyond {   // 穴の向こう：奥（−w）へ縮んでいく排水管。管の輪は奥ほど暗く、少しずつ奥へ流れていく。いちばん奥に向こう側の光
                let hv = cube(.zero, HR, -H)
                for qd in quads { F(&pipe, qd.map { hv[$0] }, SIMD3<Float>(0.18, 0.2, 0.26) * Float(oa), 0.3) }   // 切り口（穴の内壁）
                for i in 1...NR {
                    let f = pow((Double(i - 1) + flow) / Double(NR), 1.25), a = Float(1 - f * 0.85)
                    cubeEdges(cube(.zero, HR, -H - LEN * f), SIMD3<Float>(0.45, 0.62, 0.9) * a * Float(oa))
                }
                for (a, b) in edges { for m in 0..<4 {   // 管の壁：立方体の 12 本の辺 × w（奥ほど暗い）
                    let w0 = -H - LEN * Double(m) / 4, w1 = -H - LEN * Double(m + 1) / 4, c0 = Float(0.09 * (1 - Double(m) / 4))
                    let A = corners[a] * HR, B = corners[b] * HR
                    F(&pipe, [S(A.x, A.y, A.z, w0), S(B.x, B.y, B.z, w0), S(B.x, B.y, B.z, w1), S(A.x, A.y, A.z, w1)], SIMD3<Float>(0.6, 0.8, 1.3) * c0 * Float(oa), 0.5)
                } }
                let gv = cube(.zero, HR * 0.85, -H - LEN)
                for qd in quads { F(&pipe, qd.map { gv[$0] }, SIMD3<Float>(0.35, 0.5, 0.75) * Float(pulse * oa), 0.3) }
            }
            if drilling {   // 回る刃（x‐z の面）と火花
                for (cx, R, w) in [(SIMD3<Double>.zero, HR, -H), (VP, VR, H)] {
                    for q in 0..<6 { let th = now * 9 + Double(q) * .pi / 3; L(S(cx.x, cx.y, cx.z, w), S(cx.x + cos(th) * R * 1.3, cx.y, cx.z + sin(th) * R * 1.3, w), SIMD3(1, 0.75, 0.3), 1.4) }
                    for q in 0..<10 {
                        let a = (Double(q) * 2.39 + now * 3).truncatingRemainder(dividingBy: 2 * .pi), f = (now * 2 + Double(q) / 10).truncatingRemainder(dividingBy: 1), rr = R + f * 0.25 * H
                        L(S(cx.x + cos(a) * rr, cx.y + f * 0.1 * H, cx.z + sin(a) * rr, w + f * 0.15 * H), S(cx.x + cos(a) * (rr + 0.03 * H), cx.y + f * 0.1 * H, cx.z + sin(a) * (rr + 0.03 * H), w + f * 0.15 * H + 0.02 * H), SIMD3(1, 0.9, 0.5), 1.4)
                    }
                }
            }
        } else {
            func S(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> { st.place([x, y, z], 3).0 }
            func sq(_ cx: Double, _ cy: Double, _ R: Double, _ z: Double) -> [SIMD3<Double>] { [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { S(cx + $0.0 * R, cy + $0.1 * R, z) } }
            func sqEdges(_ v: [SIMD3<Double>], _ c: SIMD3<Float>) { for i in 0..<4 { L(v[i], v[(i + 1) % 4], c) } }
            sqEdges(sq(0, 0, HR, -H), PD.rim); sqEdges(sq(-0.5 * H, 0.5 * H, VR, H), PV.rim)
            // 透ける正方形の格子（細い棒＋うっすら透ける板。y ＝ +R の辺を蝶番に z の外へ）
            func grate2(_ cx: Double, _ cy: Double, _ R: Double, _ z0: Double, _ sgn: Double, _ x: Double, _ hl: Double, _ pal: Pal) {
                let th = Double.pi / 2 * back(x), cs = cos(th), sn = sin(th), BAR = [-1.0, -1.0 / 3, 1.0 / 3, 1]
                func mix(_ c: SIMD3<Float>, _ k2: Float) -> SIMD3<Float> { (c + (pal.hl - c) * Float(hl)) * k2 }
                func hp(_ a: Double, _ b: Double) -> SIMD3<Double> { let sd = R * (1 - b); return S(cx + a * R, cy + R - sd * cs, z0 + sgn * sd * sn) }
                for p in BAR { let c = mix(pal.line, abs(p) == 1 ? 1 : 0.6); L(hp(p, -1), hp(p, 1), c); L(hp(-1, p), hp(1, p), c) }
                F(&tris, [hp(-1, -1), hp(1, -1), hp(1, 1), hp(-1, 1)], mix(pal.pane, Float(1 + 2.5 * hl)), 0.22)
                if hl > 0.01 { L(S(cx - R, cy + R, z0), S(cx + R, cy + R, z0), pal.hl * Float(hl), 1.5) }   // 蝶番の辺
            }
            if !drilling { grate2(0, 0, HR, -H, -1, st.holeDA, st.holeDHL, PD); grate2(-0.5 * H, 0.5 * H, VR, H, 1, st.holeVA, st.holeVHL, PV) }
            if beyond {   // 床の正方形の穴の向こう（z ＜ −H）へ続く四角い管と、奥の光
                for i in 1...NR { let f = pow((Double(i - 1) + flow) / Double(NR), 1.25), a = Float(1 - f * 0.85); sqEdges(sq(0, 0, HR, -H - LEN * f), SIMD3<Float>(0.45, 0.62, 0.9) * a * Float(oa)) }
                let cs4 = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)]
                for i in 0..<4 { for m in 0..<4 {
                    let (a, b) = cs4[i], (c2, d2) = cs4[(i + 1) % 4], z0 = -H - LEN * Double(m) / 4, z1 = -H - LEN * Double(m + 1) / 4, c0 = Float(0.09 * (1 - Double(m) / 4))
                    F(&pipe, [S(a * HR, b * HR, z0), S(c2 * HR, d2 * HR, z0), S(c2 * HR, d2 * HR, z1), S(a * HR, b * HR, z1)], SIMD3<Float>(0.6, 0.8, 1.3) * c0 * Float(oa), 0.5)
                } }
                F(&pipe, sq(0, 0, HR * 0.85, -H - LEN), SIMD3<Float>(0.35, 0.5, 0.75) * Float(pulse * oa), 0.45)
            }
            if drilling {
                for (cx, cy, R, z) in [(0.0, 0.0, HR, -H), (-0.5 * H, 0.5 * H, VR, H)] {
                    for q in 0..<6 { let th = now * 9 + Double(q) * .pi / 3; L(S(cx, cy, z), S(cx + cos(th) * R * 1.3, cy + sin(th) * R * 1.3, z), SIMD3(1, 0.75, 0.3), 1.4) }
                }
            }
        }
        var out: [IntTriBatch] = []
        if !pipe.isEmpty { out.append(IntTriBatch(add: true, verts: pipe)) }      // 管は光として足す（暗い所は見えない）
        if !tris.isEmpty { out.append(IntTriBatch(add: false, verts: tris)) }
        return out
    }
}
