// 排水口と通気口：水で抜き方を「排水口」（か「交互」）にすると、湯船の底（−W の胞）の真ん中に排水口、上（+W の胞）に通気口がすっと現れる。
//   ふたは小さな胞（4D では立方体、左の窓では正方形）で、超立方体の胞と同じガラスの面（TLQuad）と辺で描く。
//   面（y ＝ +R）を蝶番に、ガチャッと 90° 開く（少し行き過ぎて戻る）。
//   排水口のふたが開くと、穴の向こう（w ＜ −H）へ続く 4 次元の排水管が見える：遠近で「内側ほど小さく」写るので、穴の立方体の内側に、奥へ縮んでいく管。
//   左の立方体の窓は 1 つ下の仲間：底（z ＝ −H）の真ん中に排水口、上（z ＝ +H）に通気口（正方形の穴）
import Foundation
import QuartzCore
import simd

/// 排水口・通気口の見た目と動きの数字（長さは湯船の半分の幅 H の何倍か）
enum DrainLook {
    static let ventSize = 0.1                                   // 通気口の半分の幅
    static let ventX = -0.5, ventY = 0.5, ventZ = -0.5           // 通気口の真ん中（左の窓は x・y だけ）
    static let showSec = 0.45                                   // 現れる・消える秒
    static let lidSpeed = 2.2                                   // ふたの開き具合の進む速さ（1 秒に）
    static let glowFade = 2.0                                   // 開け閉めの途中の明るさが、止まってから消える速さ（1 秒に）
    static let overshootA = 2.7, overshootB = 1.7               // ガチャッ：開き切る手前で少し行き過ぎて戻る曲線の強さ
    static let openFade = 0.12                                  // 開き始めのこの開き具合までに、ふち・ふたの面・管がすっと出る
    static let cutFrom = 0.003                                  // 左の窓で、面に穴をあけ始める開き具合（ふたもここから）
    static let lidFrom = 0.02                                   // 現れる途中で、ふたを描き始める大きさ（0〜1）
    static let assembledFrom = 0.92                             // 折り上がりがここを越えてから見せる
    static let pipeFrom = 0.03                                  // この開き具合から、奥の管を描く
    static let pipeLen = 1.3                                    // 奥の管の長さ
    static let pipeSegs = 4                                     // 管の壁を w の向きに分ける数（奥ほどうすく）
    static let cutAlpha = 0.6, wallAlpha = 0.5, endAlpha = 0.5  // 穴の内壁・管の壁・いちばん奥の濃さ（胞のガラスの何倍か）
    static let endShrink = 0.85                                 // いちばん奥の板の大きさ（穴の何倍か）
    static let edgeBase = SIMD3<Float>(0.92, 0.95, 1.0)         // 線の白っぽい色（超立方体の辺と同じ）
    static let edgeBright = 0.75                                // 胞の線が見つからない時の、ふつうの線の明るさ
    static let faint = 0.002                                    // これよりうすいものは描かない
}

extension OrigamiState {
    /// 穴の絵が動いている間（描き直しの合図に時刻を入れる）
    var holesAnimating: Bool {
        guard drainShown || holeShow > 1e-4 else { return false }
        return abs(holeShow - (drainShown ? 1 : 0)) > 1e-4 || holeDA > DrainLook.pipeFrom || holeDHL > 0 || holeVHL > 0 || abs(holeVA - (waterVent ? 1 : 0)) > 1e-4 || abs(holeDA - holeDTarget) > 1e-4
    }
    /// 左の窓（3D）で、口が開いていて面を穴あきで描く時の穴（真ん中と半分の幅）。底（排水口）・上（通気口）
    func holeCut(top: Bool) -> (cx: Double, cy: Double, R: Double)? {
        guard holeShow > 1e-3, (top ? holeVA : holeDA) > DrainLook.cutFrom else { return nil }
        let H = Self.half, sm = holeShow * holeShow * (3 - 2 * holeShow)
        return top ? (DrainLook.ventX * H, DrainLook.ventY * H, DrainLook.ventSize * H * sm) : (0, 0, drainSize * H * sm)
    }
    /// 排水口の格子のふたを開ける度合い（開けっぱなし＝いつも、水を排水口で抜く時＝栓を抜く間）
    var holeDTarget: Double { holesOpen ? 1 : (intOn && intMethod == 1 && waterHoleNow ? waterBLid : 0) }
}

@inline(__always) private func gpuH(_ v: SIMD3<Double>) -> SIMD3<Float> { SIMD3<Float>(Float(v.x), Float(-v.z), Float(v.y)) }

extension OrigamiRenderer {
    func holesGeometry(_ rods: inout [TLRod], _ quads: inout [TLQuad]) -> [IntTriBatch] {
        guard n <= 4, st.drainShown || st.holeShow > 1e-4 else { return [] }
        let now = CACurrentMediaTime()
        typealias K = DrainLook
        // 現れる・消える（K.showSec 秒）と、ふたの開き具合（目標へ 1 秒に K.lidSpeed の速さ）。2 つの窓で 2 回進めないように、時刻で
        let dtH = min(0.1, max(0, now - st.holeLastT)); if st.holeLastT <= now { st.holeLastT = now }   // 確かめの止め絵は holeLastT を先の時刻にして止める
        let showT = st.drainShown ? 1.0 : 0; st.holeShow += (showT > st.holeShow ? 1 : -1) * min(abs(showT - st.holeShow), dtH / K.showSec)
        let k = max(0, min(1, (st.progress - K.assembledFrom) / (1 - K.assembledFrom))) * max(0, 1 - 4 * st.explodeE)
        guard k > 0.01, st.holeShow > 1e-4 else { return [] }
        let smg = st.holeShow * st.holeShow * (3 - 2 * st.holeShow)
        let H = OrigamiState.half, HR = st.drainSize * H * smg, VR = K.ventSize * H * smg
        let dT = st.holeDTarget, vT = st.waterVent ? 1.0 : 0
        func step(_ x: Double, _ tg: Double) -> Double { x + (tg > x ? 1 : -1) * min(abs(tg - x), dtH * K.lidSpeed) }
        let dMoving = abs(st.holeDA - dT) > 1e-4, vMoving = abs(st.holeVA - vT) > 1e-4
        st.holeDA = step(st.holeDA, dT); st.holeVA = step(st.holeVA, vT)
        st.holeDHL = dMoving ? 1 : max(0, st.holeDHL - dtH * K.glowFade); st.holeVHL = vMoving ? 1 : max(0, st.holeVHL - dtH * K.glowFade)   // 開け閉めの途中の合図（描き直しを続けるため）
        func back(_ x: Double) -> Double { let y = x - 1; return 1 + K.overshootA * y * y * y + K.overshootB * y * y }   // 行き過ぎて戻る（ガチャッ）
        // 穴の色：排水口は底の胞、通気口はふたの胞と同じ色にして、明るさだけ変える
        let pc = st.cellColors(n), cD = OrigamiState.rgb(pc[0]), cV = OrigamiState.rgb(pc[pc.count - 1])
        // ふたと穴のふちの線：超立方体の辺と同じ色の決め方（白っぽい色に、線の色づけ lineTint の分だけ胞の色を混ぜる）。光らせない
        func edgeC(_ c: SIMD3<Float>) -> SIMD3<Float> { let b = K.edgeBase; return b + ((c * 0.8 + 0.2) - b) * Float(st.lineTint) }
        let ED = edgeC(cD), EV = edgeC(cV), EBR = K.edgeBright
        func L(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ c: SIMD3<Float>, _ br: Double = 1) { rods.append(TLRod(a: SIMD4(gpuH(a), 0), b: SIMD4(gpuH(b), 0), col: SIMD4(c, Float(br * k / 1.4)))) }
        // ふたは、底（0）・上（1）の胞そのものの一部：その胞と同じガラス（面ごとの色と濃さ・重ねる順・包む強さ・4D の奥行き）で描く。
        //   閉じている時は何も描かない（ふつうの胞のまま）。開き始めると、その部分がパカッと開いて、穴のふちと奥の管が見える
        func glass(_ q: [SIMD3<Double>], _ lk: OrigamiRenderer.HoleLook, _ fi: Int, _ fade: Double) {
            let (c, al) = lk.sh[min(fi, lk.sh.count - 1)], a = al * Float(fade)
            guard a > Float(K.faint) else { return }
            let Q = q.map { gpuH($0) }
            var nn = simd_cross(Q[1] - Q[0], Q[3] - Q[0]); let l = simd_length(nn); guard l > 1e-9 else { return }; nn /= l
            quads.append(TLQuad(a: SIMD4(Q[0], lk.w), b: SIMD4(Q[1], lk.w), c: SIMD4(Q[2], lk.w), d: SIMD4(Q[3], lk.w), n: SIMD4(nn, simd_dot(nn, Q[0])), col: SIMD4(c, 0), m: SIMD4(a, lk.tag, lk.wrap, lk.squash)))
        }
        // 線：底（0）・上（1）の胞の辺と同じワイヤー（色・明るさ・太さ・なじませる印をそのまま）。無い時はふつうの線
        func wire(_ a: SIMD3<Double>, _ b: SIMD3<Double>, _ sl: Int, _ fade: Double) {
            guard fade > K.faint else { return }
            if let e = holeEdge[sl] { rods.append(TLRod(a: SIMD4(gpuH(a), e.a.w), b: SIMD4(gpuH(b), e.b.w), col: SIMD4(e.col.x, e.col.y, e.col.z, e.col.w * Float(fade * smg)))) }
            else { L(a, b, sl == 0 ? ED : EV, EBR * fade * smg) }
        }
        // 管（穴の向こう）も、光を足すのではなく底の胞と同じガラスで。4D の奥行きはいちばん奥（w ＝ 1）にして、内側の立方体と同じように乗算でなじませる
        func deep(_ q: [SIMD3<Double>], _ lk: OrigamiRenderer.HoleLook?, _ fi: Int, _ fade: Double) {
            guard let lk = lk else { return }
            var l2 = lk; l2.w = n == 4 ? 1 : lk.w; glass(q, l2, fi, fade)
        }
        func fadeOf(_ x: Double) -> Double { let c = max(0, min(1, x / K.openFade)); return c * c * (3 - 2 * c) }   // 開き始め（0〜K.openFade）で、ふち・ふたの線・管がすっと出る
        let oa = min(1, st.holeDA), beyond = st.holeDA > K.pipeFrom, LEN = K.pipeLen * H, NS = K.pipeSegs
        let fD = fadeOf(st.holeDA), fV = fadeOf(st.holeVA), lkD = holeLook[0], lkV = holeLook[1]
        if n == 4 {
            func S(_ x: Double, _ y: Double, _ z: Double, _ w: Double) -> SIMD3<Double> { st.place([x, y, z, w], 4).0 }
            let VP = SIMD3<Double>(K.ventX, K.ventY, K.ventZ) * H
            let corners = (0..<8).map { v in SIMD3<Double>(v & 1 != 0 ? 1 : -1, v & 2 != 0 ? 1 : -1, v & 4 != 0 ? 1 : -1) }
            let edges = (0..<8).flatMap { a in (0..<3).compactMap { j in a & (1 << j) == 0 ? (a, a | 1 << j) : nil } }
            // 面 j*2+s：軸 j に垂直で s の側（胞の面の番号と同じ並び）
            let quads6: [[Int]] = (0..<3).flatMap { j in (0..<2).map { s in let o1 = (j + 1) % 3, o2 = (j + 2) % 3, b = s << j; return [b, b | 1 << o1, b | 1 << o1 | 1 << o2, b | 1 << o2] } }
            func cube(_ cx: SIMD3<Double>, _ R: Double, _ w: Double) -> [SIMD3<Double>] { corners.map { S(cx.x + $0.x * R, cx.y + $0.y * R, cx.z + $0.z * R, w) } }
            func cubeWire(_ vs: [SIMD3<Double>], _ sl: Int, _ fade: Double) { for (a, b) in edges { wire(vs[a], vs[b], sl, fade) } }
            cubeWire(cube(.zero, HR, -H), 0, fD)                              // 排水口の穴のふち（開いている時だけ。閉じている時は、ふたの線と重なる）
            cubeWire(cube(VP, VR, H), 1, fV)                                  // 通気口の穴のふち
            // ふた：小さな立方体（胞の一部）。y ＝ +R の面を蝶番に、sgn の w の向きへ 90° 開く
            func lid(_ cx: SIMD3<Double>, _ R: Double, _ w0: Double, _ sgn: Double, _ x: Double, _ fade: Double, _ lk: OrigamiRenderer.HoleLook?, _ sl: Int) {
                guard let lk = lk else { return }
                let th = Double.pi / 2 * back(x), cs = cos(th), sn = sin(th)
                func hp(_ a: Double, _ b: Double, _ c: Double) -> SIMD3<Double> { let sd = R * (1 - b); return S(cx.x + a * R, cx.y + R - sd * cs, cx.z + c * R, w0 + sgn * sd * sn) }
                let cv = corners.map { hp($0.x, $0.y, $0.z) }
                for (i, qd) in quads6.enumerated() { glass(qd.map { cv[$0] }, lk, i, fade) }   // ガラスの面は開いている時だけ（閉じている時は胞の中身と同じなので描かない）
                for (a, b) in edges { wire(cv[a], cv[b], sl, 1) }                // ふたの線は、閉じていても胞のワイヤーと同じに見せる
            }
            if smg > K.lidFrom { lid(.zero, HR, -H, -1, st.holeDA, fD, lkD, 0); lid(VP, VR, H, 1, st.holeVA, fV, lkV, 1) }
            if beyond {   // 穴の向こう：奥（−w）へ縮んでいく排水管。内壁・管の壁（奥ほどうすく）・いちばん奥の板
                let hv = cube(.zero, HR, -H)
                for (i, qd) in quads6.enumerated() { deep(qd.map { hv[$0] }, lkD, i, K.cutAlpha * oa) }   // 切り口（穴の内壁）
                for (a, b) in edges { for m in 0..<NS {   // 管の壁：立方体の 12 本の辺 × w（奥ほどうすく）
                    let w0 = -H - LEN * Double(m) / Double(NS), w1 = -H - LEN * Double(m + 1) / Double(NS)
                    let A = corners[a] * HR, B = corners[b] * HR
                    deep([S(A.x, A.y, A.z, w0), S(B.x, B.y, B.z, w0), S(B.x, B.y, B.z, w1), S(A.x, A.y, A.z, w1)], lkD, 0, K.wallAlpha * (1 - Double(m) / Double(NS)) * oa)
                } }
                let gv = cube(.zero, HR * K.endShrink, -H - LEN)
                for (i, qd) in quads6.enumerated() { deep(qd.map { gv[$0] }, lkD, i, K.endAlpha * oa) }   // いちばん奥
            }
        } else {
            func S(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> { st.place([x, y, z], 3).0 }
            func sq(_ cx: Double, _ cy: Double, _ R: Double, _ z: Double) -> [SIMD3<Double>] { [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)].map { S(cx + $0.0 * R, cy + $0.1 * R, z) } }
            func rect(_ x0: Double, _ y0: Double, _ x1: Double, _ y1: Double, _ z: Double) -> [SIMD3<Double>] { [S(x0, y0, z), S(x1, y0, z), S(x1, y1, z), S(x0, y1, z)] }
            // 口が開いている面は、穴あきの面として描く（元の面は geometry で描かない）：穴のまわりの 4 枚
            for (top, lk) in [(false, lkD), (true, lkV)] {
                guard let lk = lk, let c = st.holeCut(top: top) else { continue }
                let z = top ? H : -H, x0 = c.cx - c.R, x1 = c.cx + c.R, y0 = c.cy - c.R, y1 = c.cy + c.R
                for q in [rect(-H, -H, x0, H, z), rect(x1, -H, H, H, z), rect(x0, -H, x1, y0, z), rect(x0, y1, x1, H, z)] { glass(q, lk, 0, 1) }
            }
            func sqWire(_ v: [SIMD3<Double>], _ sl: Int, _ fade: Double) { for i in 0..<4 { wire(v[i], v[(i + 1) % 4], sl, fade) } }
            sqWire(sq(0, 0, HR, -H), 0, 1)                                    // 排水口のふち：閉じていても、正方形のワイヤー（ふたの線と同じ所）
            sqWire(sq(K.ventX * H, K.ventY * H, VR, H), 1, 1)
            // ふた：面の一部（小さな正方形）。y ＝ +R の辺を蝶番に z の外へ 90° 開く
            func lid2(_ cx: Double, _ cy: Double, _ R: Double, _ z0: Double, _ sgn: Double, _ x: Double, _ fade: Double, _ lk: OrigamiRenderer.HoleLook?, _ sl: Int) {
                guard x > K.cutFrom, let lk = lk else { return }                   // 穴あきの面と同じ時から（holeCut と同じ境目）
                let th = Double.pi / 2 * back(x), cs = cos(th), sn = sin(th)
                func hp(_ a: Double, _ b: Double) -> SIMD3<Double> { let sd = R * (1 - b); return S(cx + a * R, cy + R - sd * cs, z0 + sgn * sd * sn) }
                let v = [hp(-1, -1), hp(1, -1), hp(1, 1), hp(-1, 1)]
                glass(v, lk, 0, 1)                                              // 面の一部なので、開き始めから同じ濃さ（穴あきの面と合わせて元の面と同じ）
                for i in 0..<4 { wire(v[i], v[(i + 1) % 4], sl, fade) }
            }
            if smg > K.lidFrom { lid2(0, 0, HR, -H, -1, st.holeDA, fD, lkD, 0); lid2(K.ventX * H, K.ventY * H, VR, H, 1, st.holeVA, fV, lkV, 1) }
            if beyond {   // 床の正方形の穴の向こう（z ＜ −H）へ続く四角い管と、いちばん奥の板
                let cs4 = [(-1.0, -1.0), (1, -1), (1, 1), (-1, 1)]
                for i in 0..<4 { for m in 0..<NS {
                    let (a, b) = cs4[i], (c2, d2) = cs4[(i + 1) % 4], z0 = -H - LEN * Double(m) / Double(NS), z1 = -H - LEN * Double(m + 1) / Double(NS)
                    deep([S(a * HR, b * HR, z0), S(c2 * HR, d2 * HR, z0), S(c2 * HR, d2 * HR, z1), S(a * HR, b * HR, z1)], lkD, 0, K.wallAlpha * (1 - Double(m) / Double(NS)) * oa)
                } }
                deep(sq(0, 0, HR * K.endShrink, -H - LEN), lkD, 0, K.endAlpha * oa)
            }
        }
        return []                                                       // 面はみな quads（胞のガラス）に入れたので、三角形の束は無し
    }
}
