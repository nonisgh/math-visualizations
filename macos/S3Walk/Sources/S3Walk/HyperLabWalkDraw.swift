// 超球の窓の歩いた跡と彗星：跡・カーソル・予定の道・矢印・羽
import SwiftUI
import MetalKit
import CoreVideo

extension HyperLabRenderer {
    func drawWalk(_ e: MTLRenderCommandEncoder, _ u0: HLUni) {
        guard st.walk, let src = wsrc else { return }
        let wk = src(), trail0 = wk.trail, pos = wk.pos
        var pts = trail0
        let ptsMax = side == .left || overview ? 500 : 3000                // 小さい画面は跡の点を減らす（毎コマ、メインの処理で帯を作るので）
        if pts.count > ptsMax { let k = Double(pts.count) / Double(ptsMax); pts = (0..<ptsMax).map { trail0[min(trail0.count - 1, Int(Double($0) * k))] } }   // 多い時は間引く
        pts.append(pos)
        let (eye, _, _, _) = camBasis()
        // 点を画面の 3 次元へ。face：見えている側なら 1、奥の側は 0（なめらかに）
        func place(_ p: SIMD4<Double>) -> (SIMD3<Double>, Double) {
            wPlace(p)                                                     // 目印・ダイブと同じ写し方（今いる R の世界の S³ の上）
        }
        let P = pts.map { place($0) }
        var tri: [HLVert] = []; tri.reserveCapacity(P.count * 12)
        var ctri: [HLCometVert] = []                                    // 光の彗星（足し合わせで、あとから描く）
        // カメラに近い所ほど小さく（ダイブで寄っても、画面の上の大きさがだいたい同じ。ふだんはほぼ 1）
        func near(_ p: SIMD3<Double>) -> Double { max(0.004, min(1, simd_length(eye - p) / 7.5)) }
        // 彗星の時：頭から道を戻った長さ。尾の届く所では跡を薄くして、尾が浮き出るように
        // 寄った割合（ダイブ）：ふつうは細くしぼむ尾、寄るほど写真のような 2 本の尾（広がるちりの尾・まっすぐな青いイオンの尾）へ
        let zm = [1, 3, 4].contains(cur) && side == .right && dvT > 0 ? Float(smoothstep(0.25, 0.75, Self.diveEase(dvT).1)) : 0
        // 引きの絵の光の彗星（印 4 大彗星・3 巨大彗星）：光の玉を大きくして、その中にふつうの大きさの彗星（全体像・引きの絵でも、どこにいるかひと目でわかる）。
        //   巨大彗星はさらに大きく。ダイブで寄るほど、ふつうの大きさへ戻す（印 1 彗星は、いつもふつうの大きさ）
        let gk = cur == 3 || cur == 4 ? (side == .right ? 1 - Self.diveEase(dvT).1 : 1) : 0
        let gHead = 1 + (cur == 3 ? 5.5 : 3.5) * gk, gTail = 1 + (cur == 3 ? 2.0 : 1.5) * gk
        // 彗星の明るさ：4D の奥の側（超球の殻の裏）は少し暗く。巨大彗星は殻をまたいでも同じ明るさ（大きな光が殻のふちで欠けて見えないように）
        func fz(_ f: Double) -> Double { 0.6 + 0.4 * (f + (1 - f) * gk) }
        // 尾の長さで速さを見せる：ダイブ中・大彗星・巨大彗星は、ゆっくりの時はほとんど尾を引かず、速さが乗ってくる（cometSpd 0.5 ほど）と今まで通りの尾に
        //   （ふだんの引きの彗星は、いつも今まで通り）
        let spW = max(side == .right ? Self.diveEase(dvT).1 : 0, gk > 0 ? 1 : 0), cs = st.cometSpd
        let spdK = (1 + 0.6 * cs) * (1 - spW * (1 - (0.15 + 0.85 * smoothstep(0.03, 0.5, cs))))
        let comet = cur >= 1, real = [1, 3, 4].contains(cur), tailL = 1.05 * spdK * near(P[P.count - 1].0) * (side == .right ? 1 + 3.5 * dvThird * Self.diveEase(dvT).1 : 1) * gTail * (side == .right ? 1 + 0.35 * max(0, st.showDist - 1) * dvThird : 1)   // ショーカメラが大きく引いた時は、尾を少し長く流す（遠くからでも流れがきれいに）
        var fromHead = [Double](repeating: .infinity, count: P.count)
        if comet {
            fromHead[P.count - 1] = 0
            var k = P.count - 2
            while k >= 0 { let d = simd_length(P[k].0 - P[k + 1].0); if d > 0.6 { break }; fromHead[k] = fromHead[k + 1] + d; if fromHead[k] > tailL * 3 { break }; k -= 1 }
        }
        // 前方の跡を消す：今いる所（S³ の上）の前の向き・すぐそばの古い跡を薄く（たった今歩いた分＝道に沿って 0.3 は残す）。通り過ぎるとまた見える
        let head4 = pts[pts.count - 1]
        var recentFrom = pts.count - 1
        if st.clearAhead {
            var a4 = 0.0, k = pts.count - 2
            while k >= 0 { a4 += simd_length(pts[k + 1] - pts[k]); if a4 > 0.3 { break }; recentFrom = k; k -= 1 }
        }
        let fw4: SIMD4<Double> = { let f = wk.fwd - head4 * simd_dot(wk.fwd, head4), l = simd_length(f); return l < 1e-9 ? .zero : f / l }()
        func aheadKeep(_ i: Int) -> Float {
            guard st.clearAhead, i < recentFrom else { return 1 }
            let q = pts[i], cs = max(-1, min(1, simd_dot(q, head4))), d = acos(cs)
            if d > 0.45 { return 1 }
            let dir = q - head4 * cs, l = simd_length(dir), a = l < 1e-9 ? 1 : simd_dot(dir / l, fw4)   // 前の向きとのなす角の cos
            let ahead = smoothstep(-0.2, 0.3, a), near = 1 - smoothstep(0.12, 0.45, d), close = 1 - smoothstep(0.03, 0.1, d)
            return Float(1 - max(near * ahead, close))
        }
        let railed = st.railOn && wk.rail.count >= 2
        let cometLine = railed || st.trailCol == 3                       // 青緑と白の線：先に道を描く時の通った所と、跡の色の「青緑」
        // 線の遠近：near は画面の太さをそろえる補正。そこから彗星よりカメラに遠い所ほど細くする（3 割より細くはしないので、遠くでも消えない）
        let eyeC = max(1e-6, simd_length(eye - P[P.count - 1].0))
        func depthK(_ p: SIMD3<Double>) -> Double { max(0.3, min(1, pow(eyeC / max(1e-6, simd_length(eye - p)), 1.1))) }
        func ribbon(_ width: Double, _ alpha: Float, _ bright: Float) {
            guard P.count >= 2 else { return }
            var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
            for i in 0..<P.count {
                let a = P[max(0, i - 1)].0, b = P[min(P.count - 1, i + 1)].0, p = P[i].0
                if i > 0 && simd_length(P[i].0 - P[i - 1].0) > 0.6 { prev = nil; continue }   // 飛んだ所（初めに戻した時など）はつながない
                var sd = simd_cross(b - a, eye - p); let l = simd_length(sd); sd = l < 1e-12 ? .zero : sd / l * width * near(p) * depthK(p)
                let t = Float(i) / Float(max(1, P.count - 1)), vis = Float(0.45 + 0.55 * P[i].1)
                let c: SIMD3<Float>
                switch st.trailCol {
                case 1: c = simd_mix(SIMD3<Float>(0.62, 0.74, 0.95), SIMD3<Float>(1.0, 1.0, 1.0), SIMD3(repeating: t * t)) * bright * 1.1   // 白い光（古い所はうすい青白）
                case 2:                                                     // 軸の色：その点がいちばん近い軸（x 赤・y 緑・z 青・w 紫）の色。間はなめらかに混ぜる
                    let q = pts[i], wq = SIMD4<Double>(pow(q.x, 4), pow(q.y, 4), pow(q.z, 4), pow(q.w, 4)), sw = max(1e-9, wq.x + wq.y + wq.z + wq.w)
                    var a = SIMD3<Float>(0, 0, 0); for k in 0..<4 { a += Self.axisCol[k] * Float(wq[k] / sw) }
                    c = simd_mix(a * 1.1, simd_mix(a, SIMD3(repeating: 1), SIMD3(repeating: 0.3)) * 1.25, SIMD3(repeating: t * t)) * bright   // 殻に埋もれないよう明るめに
                default: c = simd_mix(SIMD3<Float>(1.0, 0.30, 0.62), SIMD3<Float>(1.0, 0.97, 0.80), SIMD3(repeating: t * t)) * bright   // 殻の緑・青に映える暖かい色（古い所は桃色、新しい所は白）
                }
                // 彗星の尾の所は薄く（寄った時は、尾の届く先まで）
                let z0 = 0.35 + 0.65 * Double(zm), z1 = 1.1 + 1.4 * Double(zm)
                let fh = fromHead[i], keep = fh.isInfinite ? 1 : Float(max(0, min(1, (fh - z0 * tailL) / (z1 * tailL))))
                let c1 = cometLine ? (bright > 1.25 ? SIMD3<Float>(0.88, 1.0, 0.98) : bright > 1.1 ? SIMD3<Float>(0.42, 0.93, 0.90) : SIMD3<Float>(0.12, 0.85, 0.82)) : c   // 先に道を描く時：通った所は線の色によらず彗星の色（青緑のにじみと白っぽい芯）。古い所も薄くしない
                let col = SIMD4(c1, alpha * (cometLine ? 1 : 0.45 + 0.55 * t) * vis * keep * keep * aheadKeep(i))
                let l0 = p - sd, r0 = p + sd
                if let (pl, pr, pc) = prev {
                    func v(_ x: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(x), 1), n: .zero, c: c) }
                    tri.append(v(pl, pc)); tri.append(v(pr, pc)); tri.append(v(r0, col)); tri.append(v(pl, pc)); tri.append(v(r0, col)); tri.append(v(l0, col))
                }
                prev = (l0, r0, col)
            }
        }
        // 先に描く道（レール）：1 周ぶんの道を、跡と同じ太さの薄赤の線で。彗星はこの上を走り、予定の道の矢印もこの上をなぞる。
        //   歩いた跡は白っぽい青緑で上に重なるので、線が塗りかわっていくように見える（1 周で跡を消す時は、跡が消えて薄赤へ戻る）
        if st.railOn && wk.rail.count >= 2 {
            // 彗星より先の所だけ描く（通った所に赤が残ると、彗星の色の線に透けて混ざる）。道の順にたどるので、道が交わる所でも飛ばない。
            //   周の区切り（最後の場所を過ぎて跡が消えた時）：今の所から先の 1 周ぶんを、新しい線として彗星の前へ伸ばしていく。前の周の線はゆっくり消す。
            //   跡を消さない時は、1 周で全部が彗星の色のまま
            let cnt = wk.rail.count, now = nowT
            if cnt != railN || wk.railGen != railG { railN = cnt; railG = wk.railGen; railI = 0; railEnd = -1; railTail = false; railGhost = [] }
            else if trail0.count + 5 < railTrailN {
                if railI < cnt && simd_dot(wk.rail[railI], pos) >= cos(0.35) {
                    railGhost = railPrev; railT0 = now; railEnd = railI; railTail = true
                    if Self.glintLog { print(String(format: "周の区切り %.1f 秒", now)) }
                } else { railI = 0; railEnd = -1; railTail = false; railGhost = [] }   // 走り直し
            }
            railTrailN = trail0.count; railPrev = pts
            if railI >= wk.rail.count { railI = 0 }
            if simd_dot(wk.rail[railI], pos) < cos(0.35) {                // 場所が飛んだ（走り直し・アナ極へ など）：いちばん近い所から合わせ直す
                var bi = 0, bv = -2.0
                for k in wk.rail.indices { let d = simd_dot(wk.rail[k], pos); if d > bv { bv = d; bi = k } }
                railI = bi
            }
            var best = railI, bd = -2.0
            for k in railI..<min(railI + 80, wk.rail.count) { let d = simd_dot(wk.rail[k], pos); if d > bd { bd = d; best = k } }
            railI = best
            if railI >= wk.rail.count - 2 && Journey.lapClearsTrail {     // 1 周で跡を消す時は、また全部薄赤から（周回を数えない道でも）
                if !railTail { railT0 = now; railEnd = -1 }
                railI = 0; railTail = false
            }
            let end = railEnd >= 0 ? railEnd : cnt, grow = smoothstep(0, 2.6, now - railT0), tailN = railTail ? cnt - railI : 0
            let idx = railTail ? Array(railI..<cnt) + Array(0..<end) : railI < end ? Array(railI..<end) : []
            let R0 = idx.map { place(wk.rail[$0]) }
            // 新しい線：道のはじめから先へ、やわらかい先端で伸びていく
            let reveal: [Float] = idx.indices.map { i in i < tailN ? 1 : Float(max(0, min(1, (grow * (Double(end) + 60) - Double(idx[i])) / 60))) }
            func rail(_ R: [(SIMD3<Double>, Double)], _ vis: [Float]?, _ width: Double, _ alpha: Float, _ c: SIMD3<Float>) {
                var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
                for i in 0..<R.count {
                    if i > 0 && simd_length(R[i].0 - R[i - 1].0) > 3 { prev = nil; continue }   // ダイブで自分のそばは引き伸ばされて間があくので、跡より広くつなぐ（線が自分の所まで届く）
                    let a = R[max(0, i - 1)].0, b = R[min(R.count - 1, i + 1)].0, p = R[i].0
                    var sd = simd_cross(b - a, eye - p); let l = simd_length(sd); sd = l < 1e-12 ? .zero : sd / l * width * near(p) * depthK(p)
                    let col = SIMD4(c, alpha * Float(0.45 + 0.55 * R[i].1) * (vis?[i] ?? 1)), l0 = p - sd, r0 = p + sd
                    if let (pl, pr, pc) = prev {
                        func v(_ x: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(x), 1), n: .zero, c: c) }
                        tri.append(v(pl, pc)); tri.append(v(pr, pc)); tri.append(v(r0, col)); tri.append(v(pl, pc)); tri.append(v(r0, col)); tri.append(v(l0, col))
                    }
                    prev = (l0, r0, col)
                }
            }
            rail(R0, reveal, 0.05 * st.trailW, 0.16, SIMD3(1.0, 0.45, 0.5)); rail(R0, reveal, 0.016 * st.trailW, 0.85, SIMD3(1.0, 0.62, 0.66))
            // 前の周の線：彗星の色のまま、ゆっくり消えていく
            let gk = Float(1 - smoothstep(0, 1.6, now - railT0))
            if gk > 0.01 && railGhost.count >= 2 {
                let G = railGhost.map { place($0) }
                rail(G, nil, 0.05 * st.trailW, 0.22 * gk, SIMD3(0.12, 0.85, 0.82)); rail(G, nil, 0.016 * st.trailW, gk, SIMD3(0.42, 0.93, 0.90)); rail(G, nil, 0.005 * st.trailW, 0.9 * gk, SIMD3(0.88, 1.0, 0.98))
            } else if gk <= 0.01 && !railGhost.isEmpty { railGhost = [] }
        }
        ribbon(0.05 * st.trailW, 0.22, 1.0)                             // にじみ（太さは「跡の太さ」で）
        ribbon(0.016 * st.trailW, 1.0, 1.2)                             // 芯
        if cometLine { ribbon(0.005 * st.trailW, 0.9, 1.3) }               // 先に道を描く時：通った線の真ん中に細い白っぽい光（彗星の色）
        // 今いる所：さんぽ＝青緑と白の三重の輪、彗星＝小さな光の頭と、歩いた道に沿って細く消えていく尾
        let (c, f) = P[P.count - 1], fw = SIMD3<Double>(eye - c), up0 = abs(simd_normalize(fw).y) > 0.9 ? SIMD3<Double>(1, 0, 0) : SIMD3<Double>(0, 1, 0)
        if side == .right && !overview && !diveWipe {                   // 音：手前ほど大きく（3D の距離と、4D の手前・奥の側）
            let span = Self.R * Self.SCALE, dd = simd_length(SIMD3<Double>(eye - c))
            st.cometNear = max(0, min(1, 0.5 + (simd_length(eye) - dd) / (2 * span))) * (0.35 + 0.65 * f)
            let (_, Rv, Uv, Bv) = camBasis(), rel = c - eye, rl = simd_length(rel)
            if rl > 1e-6 { st.cometDir = SIMD3(simd_dot(rel, Rv) * mirrorX, simd_dot(rel, Uv), simd_dot(rel, Bv)) / rl }   // ダイブの鏡の間は左右を逆に（画面と合わせる）
            // カメラの向きを、さんぽの向き（前・右・上）で表す。全体像は写し方がちがうので、S³ の接線の向きで渡す
            func axis3(_ t: SIMD4<Double>) -> SIMD3<Double> { let d = place(simd_normalize(pos + t * 0.02)).0 - c, l = simd_length(d); return l < 1e-9 ? .zero : d / l }
            let tan4 = wk.fwd * simd_dot(rel, axis3(wk.fwd)) + wk.vR * simd_dot(rel, axis3(wk.vR)) + wk.vU * simd_dot(rel, axis3(wk.vU))
            if simd_length(tan4) > 1e-9 { st.camTan = -simd_normalize(tan4) }   // rel はカメラ → 彗星なので、裏返して「彗星から見たカメラの向き」に
            if Self.glintLog, nowT - camLogT >= 1 {
                camLogT = nowT
                let ct = st.camTan, nearP = acos(min(1, abs(pos.w)))
                print(String(format: "カメラ %.0f 秒 前 %+.2f 右 %+.2f 上 %+.2f 極まで %.2f", nowT, simd_dot(ct, wk.fwd), simd_dot(ct, wk.vR), simd_dot(ct, wk.vU), nearP))
            }
        }
        let gone = Float(1 - (1 - dvThird) * max(0, min(1, (dvT - 0.8) / 0.12)))   // 一人称はダイブの終わり（背中に追いつく所）で消える
        let ax = simd_normalize(simd_cross(up0, fw)), ay = simd_normalize(simd_cross(fw, ax)), vis = Float(fz(f)) * gone
        let sc = near(c) * (side == .right ? 1 + 3.5 * dvThird * Self.diveEase(dvT).1 : 1) * gHead   // 三人称：寄っても彗星が点にならないように（巨大彗星は引きの絵で大きく）
        if comet {
            // 尾：頭から道を後ろへ、長さ tailL ぶん（画面の 3 次元で）。先へ行くほど細く・青く・淡く
            var idx = [P.count - 1], acc = [0.0]
            var i = P.count - 2
            while i >= 0 && acc[acc.count - 1] < tailL {
                let d = simd_length(P[i].0 - P[i + 1].0); if d > 0.6 { break }
                idx.append(i); acc.append(acc[acc.count - 1] + d); i -= 1
            }
            // 尾の先：跡が尾の長さより短い時（歩き始め・跡の飛び）は、ある所までを尾の長さとして先へ消す（尾の先が四角く切れない）
            let tailEnd = max(1e-9, min(tailL, acc[acc.count - 1]))
            func tail(_ w0: Double, _ a0: Float, _ hot: SIMD3<Float>, _ cool: SIMD3<Float>) {
                guard idx.count >= 2 else { return }
                var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>)?
                for k in 0..<idx.count {
                    let j = idx[k], p = P[j].0
                    let a = P[idx[max(0, k - 1)]].0, b = P[idx[min(idx.count - 1, k + 1)]].0
                    let s = min(1, acc[k] / tailEnd)                                 // 0：頭、1：尾の先
                    var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                    sd = l < 1e-12 ? .zero : sd / l * w0 * sc * pow(1 - 0.92 * s, 1.4)                     // 頭の所が太く、後ろへしぼむ
                    let fv = Float(fz(P[j].1)) * gone, fs = Float(s)
                    let col = SIMD4(simd_mix(hot, cool, SIMD3(repeating: fs)), a0 * pow(1 - fs, 1.6) * fv)
                    let l0 = p - sd, r0 = p + sd
                    if let (pl, pr, pc) = prev {
                        func v(_ x: SIMD3<Double>, _ c: SIMD4<Float>) -> HLVert { HLVert(p: SIMD4(SIMD3<Float>(x), 1), n: .zero, c: c) }
                        tri.append(v(pl, pc)); tri.append(v(pr, pc)); tri.append(v(r0, col)); tri.append(v(pl, pc)); tri.append(v(r0, col)); tri.append(v(l0, col))
                    }
                    prev = (l0, r0, col)
                }
            }
            if real {
                func v(_ x: SIMD3<Double>, _ q: SIMD4<Float>) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(x), 1), q: q) }
                // 帯：点の列に沿って、横の半分の幅 wid(s) で。kind は cmf の種類
                func strip(_ pts: [SIMD3<Double>], _ ss: [Double], _ kind: Float, _ alpha: (Int) -> Float, _ wid: (Double) -> Double) {
                    guard pts.count >= 2 else { return }
                    var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>, SIMD4<Float>)?
                    for k in 0..<pts.count {
                        let p = pts[k], a = pts[max(0, k - 2)], b = pts[min(pts.count - 1, k + 2)]   // 横の向きは少し広く見て（つなぎ目で急に変わらない）
                        var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                        sd = l < 1e-12 ? .zero : sd / l * wid(ss[k])
                        let al = alpha(k), ql = SIMD4<Float>(Float(ss[k]), -1, kind, al), qr = SIMD4<Float>(Float(ss[k]), 1, kind, al), l0 = p - sd, r0 = p + sd
                        if let (pl, pr, pql, pqr) = prev { ctri += [v(pl, pql), v(pr, pqr), v(r0, qr), v(pl, pql), v(r0, qr), v(l0, ql)] }
                        prev = (l0, r0, ql, qr)
                    }
                }
                let tp0 = idx.map { P[$0].0 }, ts0 = acc.map { min(1, $0 / tailEnd) }, fc0 = idx.map { P[$0].1 }
                // 寄ると点の間が長く見えて折れ線の角が出るので、道すじをなめらかにして（少しならしてから）、点の間を曲線（Catmull-Rom）で 6 つずつ補う
                var tp: [SIMD3<Double>] = [], ts: [Double] = [], fc: [Double] = []
                if zm > 0.01 && tp0.count >= 2 {
                    var sm = tp0
                    for _ in 0..<2 where tp0.count >= 3 { var nx = sm; for i in 1..<(sm.count - 1) { nx[i] = sm[i] * 0.5 + (sm[i - 1] + sm[i + 1]) * 0.25 }; sm = nx }
                    let m = 6
                    for i in 0..<(sm.count - 1) {
                        let p0 = sm[max(0, i - 1)], p1 = sm[i], p2 = sm[i + 1], p3 = sm[min(sm.count - 1, i + 2)]
                        for j in 0..<m {
                            let u = Double(j) / Double(m), u2 = u * u, u3 = u2 * u
                            // Catmull-Rom の重み（4 点に掛ける数）
                            let w0 = -u3 + 2 * u2 - u, w1 = 3 * u3 - 5 * u2 + 2, w2 = -3 * u3 + 4 * u2 + u, w3 = u3 - u2
                            var q: SIMD3<Double> = p0 * w0
                            q += p1 * w1; q += p2 * w2; q += p3 * w3
                            tp.append(q * 0.5)
                            ts.append(ts0[i] + (ts0[i + 1] - ts0[i]) * u); fc.append(fc0[i] + (fc0[i + 1] - fc0[i]) * u)
                        }
                    }
                    tp.append(sm[sm.count - 1]); ts.append(ts0[ts0.count - 1]); fc.append(fc0[fc0.count - 1])
                }
                if zm > 0.01 && tp.count >= 2 {
                    // ちりの尾：道に沿って、先へ行くほど広がる
                    //   速さが乗るほど、傘（先の広がり）を大きく開く（疾走感）
                    let fan = 1 + 2.4 * smoothstep(0.25, 0.85, st.cometSpd)   // 速いと予定の道の矢印の幅くらいまで大きく開く
                    strip(tp, ts, 2, { k in Float(0.6 + 0.4 * fc[k]) * gone * zm }, { s in 0.09 * sc * (0.4 + 2.6 * s * fan) })
                    // イオンの尾：彗星の向き（今まっすぐ進もうとしている向き）の真後ろへ、まっすぐ長く（曲がっている最中も彗星の向きと平行。ちりの尾は道に沿ってなびく）
                    let hd = wk.head ?? wk.fwd                                      // 本当に進んでいく向き（さんぽは見ている方位へ進む）
                    let f4 = hd - wk.pos * simd_dot(hd, wk.pos), fl4 = simd_length(f4)
                    let jb = ts.firstIndex { $0 >= 0.3 } ?? (tp.count - 1)
                    let behind = fl4 > 1e-6 ? wPlace(simd_normalize(wk.pos - f4 / fl4 * 0.05)).0 : tp[max(1, jb)]
                    let back = simd_normalize(behind - c + SIMD3(1e-9, 0, 0)), kk = simd_normalize(fw), th = 0.0
                    let d1: SIMD3<Double> = back * cos(th), d2: SIMD3<Double> = simd_cross(kk, back) * sin(th), d3: SIMD3<Double> = kk * (simd_dot(kk, back) * (1 - cos(th)))
                    let dir: SIMD3<Double> = d1 + d2 + d3
                    let n = 24, L = tailL * 1.45                                  // 真ん中の細い尾は中くらいの長さに
                    var ip: [SIMD3<Double>] = [], iss: [Double] = []
                    for q in 0...n { let f = Double(q) / Double(n); ip.append(c + dir * (L * f)); iss.append(f) }
                    strip(ip, iss, 3, { _ in vis * zm * 0.8 }, { s in 0.05 * sc * (0.45 + 1.0 * s) })
                }
                // 光の尾：道に沿った帯（頭で太く、後ろへしぼむ）。色と明るさは cmf が横の位置・頭からの割合で決める
                var prev: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>, SIMD4<Float>)?
                for k in 0..<idx.count where idx.count >= 2 && zm < 0.99 {
                    let j = idx[k], p = P[j].0
                    let a = P[idx[max(0, k - 1)]].0, b = P[idx[min(idx.count - 1, k + 1)]].0
                    let s = min(1, acc[k] / tailEnd)
                    var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                    sd = l < 1e-12 ? .zero : sd / l * 0.085 * sc * pow(1 - 0.8 * s, 1.2)
                    let a0 = Float(fz(P[j].1) * (1 - 0.5 * gk)) * gone * (1 - zm)   // 巨大彗星の太い尾は控えめに（中の彗星の尾が見えるよう）
                    let ql = SIMD4<Float>(Float(s), -1, 1, a0), qr = SIMD4<Float>(Float(s), 1, 1, a0), l0 = p - sd, r0 = p + sd
                    if let (pl, pr, pql, pqr) = prev { ctri += [v(pl, pql), v(pr, pqr), v(r0, qr), v(pl, pql), v(r0, qr), v(l0, ql)] }
                    prev = (l0, r0, ql, qr)
                }
                // 光の頭：画面に向く板（コマはぼんやり広いので、板は大きめ）
                let hw = side == .right && dvT > 0 ? headWarp : SIMD3(), wv = SIMD2(simd_dot(hw, ax), simd_dot(hw, ay)), wm = min(1, simd_length(wv))
                let hs = 0.2 * sc * (1 + 0.45 * wm)                              // ゆがんで伸びる分、板を大きく（ふちで切れないように）
                let wc = SIMD4<Float>(Float(wv.x), Float(wv.y), Float(gk), 1)
                func hv(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs) + ay * (y * hs)), 1), q: SIMD4(Float(x), Float(y), 0, vis), c: wc) }
                ctri += [hv(-1, -1), hv(1, -1), hv(1, 1), hv(-1, -1), hv(1, 1), hv(-1, 1)]
                if gk > 0.01 {
                    // 巨大彗星の中に、ふつうの大きさの彗星（「ここだよ」の印）：細く明るい尾と、くっきりした頭
                    let sc0 = sc / gHead, tl0 = tailL / gTail
                    var pv: (SIMD3<Double>, SIMD3<Double>, SIMD4<Float>, SIMD4<Float>)?
                    for k in 0..<idx.count where idx.count >= 2 && acc[k] <= tl0 {
                        let j = idx[k], p = P[j].0
                        let a = P[idx[max(0, k - 1)]].0, b = P[idx[min(idx.count - 1, k + 1)]].0
                        let s = min(1, acc[k] / max(1e-9, tl0))
                        var sd = simd_cross(b - a, eye - p); let l = simd_length(sd)
                        sd = l < 1e-12 ? .zero : sd / l * 0.085 * sc0 * pow(1 - 0.8 * s, 1.2)
                        let a0 = Float(fz(P[j].1)) * gone * Float(gk)
                        let ql = SIMD4<Float>(Float(s), -1, 1, a0), qr = SIMD4<Float>(Float(s), 1, 1, a0), l0 = p - sd, r0 = p + sd
                        if let (pl, pr, pql, pqr) = pv { ctri += [v(pl, pql), v(pr, pqr), v(r0, qr), v(pl, pql), v(r0, qr), v(l0, ql)] }
                        pv = (l0, r0, ql, qr)
                    }
                    let hs0 = 0.26 * sc0, a0 = vis * Float(gk) * 1.6                // 頭は少し大きく明るく（「ここ」がわかるように）
                    func hv0(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(c + ax * (x * hs0) + ay * (y * hs0)), 1), q: SIMD4(Float(x), Float(y), 0, a0), c: SIMD4(0, 0, 0, 1)) }
                    ctri += [hv0(-1, -1), hv0(1, -1), hv0(1, 1), hv0(-1, -1), hv0(1, 1), hv0(-1, 1)]
                }
            } else {
                tail(0.075, 0.5, SIMD3(0.85, 0.95, 1.0), SIMD3(0.35, 0.45, 1.0))   // 尾のにじみ（青白く、しぼみながら消える）
                tail(0.024, 1.0, SIMD3(1.0, 1.0, 1.0), SIMD3(0.55, 0.85, 1.0))     // 尾の芯
            }
        }
        // 予定の道：これから進む道を、光の点線で（点はゆっくり進む向きへ流れる。先へ行くほど淡く、彗星のすぐ前は出さない）
        HyperLabState.planActive = !wk.plan.isEmpty
        if st.planOn && wk.plan.count >= 2 {
            // 予定の道の始まりは、彗星の少し先の道の点。頭に彗星の今の場所をつなぐ（矢印が彗星のすぐ前から並ぶ）
            var pl = wk.plan; if let f = pl.first, simd_length(f - wk.pos) > 1e-6 { pl.insert(wk.pos, at: 0) }
            let cb3 = camBasis(), Bv = cb3.3, Uv3 = cb3.2   // Uv3：画面の上の向き（矢印を寝かせる「水平」に使う）
            var cum = [0.0]; cum.reserveCapacity(pl.count)
            for i in 1..<pl.count { cum.append(cum[i - 1] + simd_length(pl[i] - pl[i - 1])) }
            // ダイブで寄るほど：自分のすぐ近くの空間が大きく引き伸ばされる（S³ の短い道のりが画面では長い）。そこで寄った時は、矢印を
            //   画面の 3D の距離で等間隔に並べ（すぐ前から）、大きさも 3D のまま（近いほど大きく、遠いほど小さく）にする
            let dz = side == .right ? Self.diveEase(dvT).1 : 0, ecd = max(0.05, simd_length(eye - c)), nearC = near(c)
            let total = cum[cum.count - 1], now = nowT
            let dive = side == .right ? 1 + 2.5 * dvThird * dz : 1
            let march = dz > 0.4, G = 0.47 * ecd * (1 - 0.55 * surgeK)   // 寄った時の矢印の間隔（3D）。迫る間はぐっと詰める
            // 曲がり具合（道の点ごと。となりの向きとの角度の、少し先までの大きい方）：カーブの所は工事の看板の矢印のように、光が手前から奥へ順に走る
            var bend = [Double](repeating: 0, count: pl.count)
            if pl.count >= 3 { for i in 1..<(pl.count - 1) {
                bend[i] = Self.geoTurn(pl[i - 1], pl[i], pl[i + 1])
            } }
            func seg(_ d: Double) -> (SIMD4<Double>, Int) {               // 道のり d の所の点（長さ 1 に直す前）と、その区間の番号
                var lo = 1, hi = cum.count - 1
                while lo < hi { let m = (lo + hi) / 2; if cum[m] < d { lo = m + 1 } else { hi = m } }
                let j = lo, a = cum[j - 1], b = cum[j], f = b > a ? max(0, min(1, (d - a) / (b - a))) : 0
                return (pl[j - 1] + (pl[j] - pl[j - 1]) * f, j)
            }
            // 寄った時（ダイブ）の矢印は「まぜる」やり方：場所は S³ の本当の点（殻や星と一緒に動き、彗星が近づくとちゃんと矢印の上を通る）、
            //   大きさと向きはふつうの 3D の空間で（大きさは 3D の距離だけ、向きは画面の上の道の向き）。4D の遠近で曲がりが強く出る遠くは出さない
            // 矢印を置く所：(道のり d、並びの番号 u（流れても連続）、手前の消え方)
            var marks: [(d: Double, u: Double, fade: Double, k: Double, sp: Double, dn: Double)] = []   // sp：となりの矢印との 3D の間隔（カメラ距離が 1。粗密で詰めたぶんは割り戻してある）、dn：粗密の詰め具合
            // 矢印は道の上に止まっている（歩いた道のり wk.dist からの決まった所に置く）。彗星が近づいて、矢印の間を通り抜けていく（導かれるように）
            if march {
                // 寄った時：間隔は彗星のそばで 3D の 0.37 × カメラの距離ほど（つながって見えて、カーブの曲がりもなめらかに見えるくらい）。左上の全体像と同じ間隔（S³ で 0.078）にすると、
                //   寄った画面では 1 つめの羽がもう遠すぎて出ないので、その間くらいに（1 つめの羽が彗星の 1 カメラ距離より少し手前）。寄ったあとは間隔を固定（鎖のように道の上に止まる）
                let m0 = simd_length(place(simd_normalize(wk.pos + wk.vL * 1e-3)).0 - c) / 1e-3
                let want = Self.arrowGap(ecd: ecd, showK: 1 + (st.showDist - 1) * dvThird * Self.diveEase(dvT).0, m0: m0)
                if marchGap <= 0 || want > marchGap * 2 || want < marchGap * 0.5 { marchGap = want }
                // 粗密：まっすぐな所は間隔を広く、カーブは密に。矢印が道の上に止まったままになるよう、「曲がり具合で重みをつけた道のり W」で等間隔に置く
                //   （重みは道の点ごとに決まるので、彗星が進んでも同じ所に矢印が残る。歩いたぶんの重みつきの道のりは planWAcc に足していく）
                let dense = st.planDense, gp = marchGap, w0 = wk.dist
                func dens(_ t: Double) -> Double { dense ? 1 + 1.5 * smoothstep(0.004, 0.03, bend[max(0, min(pl.count - 1, seg(t).1))]) : 1 }
                if let lw = planWLast, w0 >= lw, w0 - lw < 0.5 { planWAcc += (w0 - lw) * dens(0) } else { planWAcc = w0 }
                planWLast = w0
                // 矢印を通るたびに、線路のつなぎ目の音（動画を描く時は、画面の音を鳴らさない）
                let railN = Int((planWAcc / gp).rounded(.down))
                if clockOverride == nil && mainPane && railN > railLast && railN - railLast <= 4 { HyperSound.shared.railTick() }
                railLast = railN; Self.railGap = gp
                var W = planWAcc, u = (W / gp).rounded(.up), s3 = 0.0, prev = c, last: SIMD3<Double>? = nil
                let lim = 8 * ecd                                              // 3D の道のりでここまで（並びの位置 k もこれで決める。数が変わっても k がとばない）
                // 「予定の道を全部」：左上の地図と同じように、道の終わりまで出す（3D の道のりで切らない。詰まる所は飛ばすだけ。並びの位置 k は S³ の道のみ）
                let long = st.planLong, dMax = long ? total : min(total, 0.8)   // ふだんは S³ の上で 0.8 先まで（十分に長いが、急なカーブでは先端に矢印が生まれていくのが分かるくらい）
                var t = 0.0
                marchLoop: while marks.count < (long ? 500 : 90) && t < dMax {
                    let step = (t < 0.05 ? 0.0008 : t < 0.3 ? 0.004 : 0.015) / max(1, dens(t)), tn = min(dMax, t + step), dw = (tn - t) * dens(t)
                    if !long { let (q4, _) = seg(tn), l = simd_length(q4); if l > 1e-9 { let q = place(q4 / l).0; s3 += simd_length(q - prev); prev = q } }   // 3D の道のりはふつうの長さの時だけ使う
                    while W + dw >= u * gp {                                     // この 1 歩の中に矢印の所がある（複数あればみんな）
                        let d = t + (tn - t) * max(0, min(1, (u * gp - W) / max(1e-12, dw)))   // 1 歩の中で、ちょうど重みつきの道のりが u・gp になる所
                        if !long && s3 > lim { break marchLoop }                     // 遠く（4D の遠近で大きく曲がる所）は出さない
                        // 遠くで道が 3D の 1 点へ縮む所（4D の遠近）：となりの羽との間が詰まったら、なめらかに淡く消す（羽が団子に重ならない）
                        let qd4 = seg(d).0, ld = simd_length(qd4), qd = ld > 1e-9 ? place(qd4 / ld).0 : prev
                        //   粗密で詰めた所は、そのぶん間隔を割り戻す（カーブで密にしても、4D の縮みと区別して淡くしない）
                        let sp = (last.map { simd_length(qd - $0) / ecd } ?? 1) * dens(d); last = qd
                        if sp < (long ? 0.02 : 0.06) { if long { u += 1; continue }; break marchLoop }
                        marks.append((d, u, smoothstep(0, 0.006, d) * (long ? smoothstep(0.02, 0.08, sp) : smoothstep(0.08, 0.3, sp)), long ? d / max(1e-9, total) : s3 / lim, sp, dens(d))); u += 1   // 1 枚ずつ消さない（彗星の真下に来た時だけ、ふっと消える）
                    }
                    W += dw; t = tn
                }
            } else {
                marchGap = 0; planWLast = nil                                   // 寄っていない間は、次に寄った時に合わせ直す
                let gap = 0.078, w0 = wk.dist
                var u = (w0 / gap).rounded(.up)
                while true { let d = u * gap - w0; if d >= total { break }; marks.append((d, u, smoothstep(0.03, 0.09, d), d / total, 1, 1)); u += 1 }
            }
            let mark = st.planMark, col = Self.beadPalette[mark == 1 ? 1 : 3]   // 目印の色：楕円の光は暖かい白、矢印と金平糖は青白（ほんのり軸の色を混ぜる）
            var side4: SIMD4<Double>? = nil                               // 矢印の横の向き（前の矢印の向きを使う時の予備）
            // 先導（ダイブ）：彗星の今の進む向き（接線）を、画面の 3D で。手前の矢印はこの向きを指し、先へ行くほど道の向きへ回っていく
            //   （「今の向きから、ここでこう曲がる」を前もって示す。道が曲がり始めると、その曲がりが手前から先へ波のように伝わる）
            // 引っぱる所（ダイブ）：道の 0.22 先の点。そこまでの矢印は、その点へまっすぐ引っぱる向きを指す（変化は彗星のすぐ前で終わり、そこからは一直線）
            let dAim = min(total, 0.22), aimP: SIMD3<Double>? = { let (a4, _) = seg(dAim), al = simd_length(a4); return al > 1e-9 ? place(a4 / al).0 : nil }()
            let hd0 = wk.head ?? wk.vL, cX: SIMD3<Double>? = {
                let q1 = place(simd_normalize(wk.pos + hd0 * 1e-3)).0 - c; var v = q1 - Bv * simd_dot(q1, Bv)
                let l = simd_length(v); if l < 1e-12 { return nil }; v /= l; return v
            }()
            // いちばんきつく曲がる所（矢印を置く所の中で、その場の曲がり具合がいちばん大きい所）：回るのはそのあたりの矢印だけ
            // 立体の矢印の向き（ダイブ）：道の始まりで決めた横の向きを、S³ の上で道に沿って平行移動で運ぶ（となりの点の接する面へ写して長さ 1 に直す）。
            //   まっすぐな所では矢印がみんな同じ向きにそろい、道がねじれる所では、道に合わせて自然にねじれる。カメラが動いても向きは変わらない。
            //   始まりの向きも、前のコマの向きを今の始まりへ運んで続ける（急に切りかわらない）
            var nf: [SIMD4<Double>] = []
            if march && mark == 0 && pl.count >= 2 {
                func tang(_ i: Int) -> SIMD4<Double> {
                    let p = simd_normalize(pl[i]); var t = pl[min(pl.count - 1, i + 1)] - pl[max(0, i - 1)]; t -= p * simd_dot(t, p)
                    let l = simd_length(t); return l > 1e-12 ? t / l : t
                }
                func flat(_ n: SIMD4<Double>, _ i: Int) -> SIMD4<Double> {
                    let p = simd_normalize(pl[i]), t = tang(i); return n - p * simd_dot(n, p) - t * simd_dot(n, t)
                }
                var n0: SIMD4<Double>? = nil
                if let pf = planFrame { let v = flat(pf, 0), l = simd_length(v); if l > 0.2 { n0 = v / l } }
                if n0 == nil {
                    var best = SIMD4<Double>(), bl = 0.0
                    for a in [SIMD4<Double>(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)] { let v = flat(a, 0), l = simd_length(v); if l > bl { bl = l; best = v / l } }
                    n0 = best
                }
                nf = [n0!]
                for i in 1..<pl.count { let v = flat(nf[i - 1], i), l = simd_length(v); nf.append(l > 1e-9 ? v / l : nf[i - 1]) }
                planFrame = nf[0]
            }
            var rollRef: Double? = nil                                       // このコマの、鎖全体の回し（立体の矢印）
            var ksRun = Double.infinity                                      // 立体の矢印の大きさ：道の先へ行くほど必ず小さく（それまでの矢印のいちばん小さい大きさ）
            // 誘導灯の光とドミノのスピンの拍：彗星の流れる音（エンジンの低いうなり）のリズムに合わせる。うなり 6 つで 1 回（走っている時で 4 秒ほど）、光の粒がうなりの山で手前を出発し、ゆっくり先へ走る。
            //   疾走感の中をゆっくり光がうねっていく。音が鳴っていない時は 4 秒ごと
            let domC = domOverride ?? Self.domClock(now)
            var bendMax = 0.0
            for mk in marks { let j = seg(mk.d).1; bendMax = max(bendMax, bend[max(0, j - 1)], bend[min(pl.count - 1, j)]) }
            let dtA = min(0.1, max(0, now - arrowSmT)); arrowSmT = now
            var smNew: [Int: (dev: Double, bank: Double, dv: Double, bv: Double)] = [:], rollNew: [Int: (r: Double, v: Double)] = [:]
            // 針のばね：ω 4.5（約 1.4 秒で 1 回ゆれる）、減衰 0.6（少しだけ行き過ぎて、ふわっと止まる）
            //   手前の矢印ほど早く、先の矢印ほどゆっくり追う（変化が手前からドミノのように先へ伝わる。のんびりしたタコメーターのよう）
            func needle(_ x: inout Double, _ v: inout Double, _ to: Double, _ mi: Int) { let w = 6.0 / (1 + 0.22 * Double(mi)), z = 0.6, n = max(1, Int(ceil(dtA / 0.008))), h = dtA / Double(n); for _ in 0..<n { v += (w * w * (to - x) - 2 * z * w * v) * h; x += v * h } }
            var spinNew: [Int: (r: Double, v: Double)] = [:], curveNew: [Int: Double] = [:]
            defer { arrowSm = smNew; arrowRoll = rollNew; spinSm = spinNew; curveSpin = curveNew }
            let camFwd = simd_normalize(c - eye)                              // カメラの向き（彗星はいつも画面の中ほど）。視界の外の矢印は計算しない
            for (mi, mk) in marks.enumerated() {
                let d = mk.d, (q4, j) = seg(d), l = simd_length(q4)
                if l > 1e-9 {
                    let (q, face) = place(q4 / l)
                    // 視界に入らない矢印（カメラの向きから 75° より外・後ろ）は、向きや回りの計算をしない（ばねの状態だけ持ち越す）
                    if march && mark == 0 {
                        let vq = q - eye, lq = simd_length(vq)
                        if lq < 1e-9 || simd_dot(vq / lq, camFwd) < 0.25 {
                            let key = Int(mk.u.rounded())
                            if let v = arrowSm[key] { smNew[key] = v }; if let v = spinSm[key] { spinNew[key] = v }
                            if let v = curveSpin[key] { curveNew[key] = v }; if let v = arrowRoll[key] { rollNew[key] = v }
                            continue
                        }
                    }
                    let k = mk.k, kc = k   // kc：並びの中の位置（0 手前 〜 1 先頭）
                    var bk = 0.0                                              // この矢印のあたり（前後 4 点）の曲がり具合
                    for t in max(0, j - 3)...min(pl.count - 1, j + 4) { bk = max(bk, bend[t]) }
                    let curv = smoothstep(0.006, 0.03, bk)                    // 1 点（0.02）で 0.35°〜1.7° 曲がる所から
                    let wave = pow(0.5 + 0.5 * cos(2 * .pi * (mk.u / 4 - now * 2.0)), 6)   // 手前から奥へ走る光（並びの 4 つおきに、1 秒に 2 回）
                    // 寄った時は、まっすぐな所でも光が手前から奥へ走る（先導する感じ。カーブではもっと強く）
                    //   寄った時（鎖のように道の上に止まった羽）は、光を走らせない（光が走ると、羽が流れて見える）
                    //   寄った時は、羽はうっすら灯っていて、光の粒が手前から先へ走り抜ける（羽は止まったまま、光だけが進む）。
                    //   ふだんからほんのり光っている（光が来るとさらに明るく）
                    //   滑走路の誘導灯のように：光の粒が 1 つ、手前から先へなめらかに走り抜けて（1.1 秒）、少し休む（全部で 1.8 秒）。
                    //   光の前はすっと明るくなり、後ろは尾を引いてゆっくり消える（ぱっぱっと点く看板のようにしない）
                    // ドミノのスピン（寄った時）。光ってスピンする所は同じ：矢印の光の強さは、その矢印が回る速さで決める（回っている間だけ光る。ぴったり同期）
                    var spinAng = 0.0, spinVel = 0.0
                    if march {
                        // ドミノのスピン：誘導灯の光の粒がこの矢印に届くと、進む向きのまわりにくるっと半回り（約 0.4 秒）。
                        //   光と一緒に、手前の矢印から順に回っていく。「»」は半回りで元と同じ形なので、回り終わったらそのまま次の光を待つ
                        //   回り方は風に吹かれるように：矢印ごとのやわらかいばねで追う（少し行き過ぎて、ゆらっと戻る）。さらに小さくそよぐ
                        let cyc = domC.rounded(.down), head = (domC - cyc) * 1.8 / 1.1 * 1.15 - 0.05
                        let skey = Int(mk.u.rounded())
                        // カーブで自分から回る（自律スピン）：道が曲がっている所の矢印は、曲がる向きへ回り続ける（右へ曲がる所は右回り、左は左回り。
                        //   上下に曲がる時もその向きで）。速さは曲がりの強さで（ゆるいカーブはゆっくり、急カーブで約 1.1 秒に 1 回り）。まっすぐな所は止まる。
                        //   回り方の選び：0 拍（音のうなりのドミノ）・1 カーブ・2 両方
                        var ex = curveSpin[skey] ?? 0
                        if st.spinMode != 0 {
                            // 曲がる向き：少し手前と少し先の道の向き（画面の 3D）の回る軸が、画面の奥を向くか手前を向くか
                            let qa4 = seg(max(0, d - 0.03)).0, qb4 = seg(min(total, d + 0.03)).0
                            let qa = place(simd_normalize(qa4)).0, qb = place(simd_normalize(qb4)).0
                            let ax = simd_cross(q - qa, qb - q), sg = simd_dot(ax, Bv) >= 0 ? 1.0 : -1.0
                            let strength = smoothstep(0.004, 0.03, bk)
                            ex += sg * 2 * .pi * (0.25 + 0.65 * strength) * strength * dtA
                        }
                        curveNew[skey] = ex
                        let xs0 = head - kc
                        var target = (st.spinMode == 1 || st.spinMode >= 3 ? 0 : .pi * (cyc + smoothstep(-0.12, 0.3, xs0))) + ex
                        // 波：傾きがサインカーブの波になって、手前から先へ伝わる（拍 2 つで 1 波。振れ幅・波長はパラメーター）。
                        // らせん：1 枚ごとに少しずつねじれて並び（DNA のように）、鎖全体が拍に合わせて回り続ける
                        if st.spinMode == 3 { target = st.spinAmp * .pi / 180 * sin(2 * .pi * (domC - mk.u / max(1, st.spinLen))) }
                        if st.spinMode == 4 { target = mk.u * st.spinAmp * .pi / 180 + 2 * .pi * domC * st.spinLen * 0.1 }
                        // 進路：今走っている向きと、その矢印の所の道の向きの角度で寝かせ方を決める（平行なら垂直に立って薄い板に、直角なら水平に寝て面が見える。間はなめらかに）。
                        //   遠くのまっすぐ先の板ほど薄く見え、自分が進んで向きが変わると、矢印が次々に起き上がったり寝たりする。完全に垂直だと厚みゼロで消えるので、少し手前まで
                        //   進路 B（6）はその逆：平行なら寝て面が見え、直角なら立って線に見える（遠くでカーブしている板ほどひねったテープのように薄く）
                        if st.spinMode == 5 || st.spinMode == 6, let cx = cX {
                            let qa4 = seg(max(0, d - 0.004)).0, qb4 = seg(min(total, d + 0.004)).0
                            var tg = place(simd_normalize(qb4)).0 - place(simd_normalize(qa4)).0; tg -= Bv * simd_dot(tg, Bv)
                            if simd_length(tg) > 1e-9 { let th = acos(min(1, abs(simd_dot(simd_normalize(tg), cx)))); target = 0.72 * (st.spinMode == 5 ? .pi / 2 - th : th) }
                        }
                        var ss = spinSm[skey] ?? (target, 0)
                        if abs(target - ss.r) > 1.5 * .pi { ss.r += .pi * ((target - ss.r) / .pi).rounded() }   // 拍の数えが飛んだ時（音が鳴り始めた時など）は、半回り単位で追いつかせる（くるくる回らない）
                        let sw = 6.5, sz = 0.35, sn = max(1, Int(ceil(dtA / 0.008))), sh = dtA / Double(sn)
                        for _ in 0..<sn { ss.v += (sw * sw * (target - ss.r) - 2 * sz * sw * ss.v) * sh; ss.r += ss.v * sh }
                        spinNew[skey] = ss
                        let breeze = 0.1 * sin(2 * .pi * 0.6 * now + 1.9 * mk.u) + 0.05 * sin(2 * .pi * 1.3 * now + 0.7 * mk.u)
                        spinAng = ss.r + breeze; spinVel = ss.v
                    }
                    let neon: Double = {
                        let head = (domC - domC.rounded(.down)) * 1.8 / 1.1 * 1.15 - 0.05   // 光の先頭（並びの位置 k、0 手前〜1 先）
                        let x = head - kc                                                        // 光の先頭からの距離（＋：先頭より手前）
                        // 白い光は拍のドミノと同じ：先頭が来た板だけがぱっと光って、すぐ落ち着く（短いきらめきが 1 枚ずつ先へ伝わる。前後の板は暗いまま）
                        let byLight = x >= 0 ? exp(-x / 0.055) : exp(-x * x / 0.0009)
                        if march && mark == 0 { return max(byLight, smoothstep(0.8, 7, abs(spinVel))) }   // 立体の矢印：走る光に加えて、回っている板も光る（拍のドミノでは同じ時に）
                        return byLight
                    }()
                    let lit = march ? 0.55 + 2.3 * neon : (1 - 0.55 * curv) + 2.8 * curv * wave
                    // 先へ行くほど消える（フェードアウト）。カーブの所は、曲がる先まではっきり見せる（消え方を弱める）
                    let keep = 1 - 0.35 * curv                                         // 先の方はだんだん薄く消える（最初の形のように）。カーブの所だけ少しゆるく
                    // 「道を全部」の時は、先の方も淡くしない（左上の地図のように、道の終わりの先端まで描き切る）
                    let allWay = march && st.planLong
                    var al = Float(mk.fade * (1 - smoothstep(0.55, 1.0, k) * keep * (allWay ? 0 : 1)) * (0.4 + 0.6 * face) * lit)
                    if march { al *= Float(1 - (allWay ? 0 : 0.55) * smoothstep(0.3, 1.0, k) * keep) }
                    if march && mark == 0 { al *= Float((1 + 0.7 * smoothstep(0.1, 0.8, k) * smoothstep(0.03, 0.12, mk.sp)) * (0.6 + 0.4 * smoothstep(0, 0.3, k))) }   // 自分のすぐ手前の板は少し暗め（明るすぎない）   // 立体の矢印：先端の方（奥の小さい矢印）ほど濃く（遠くまで線がくっきり続く）   // 寄った時は、先へ行くほどしっかり淡く（遠近。先はほとんど消える）
                    else { al *= Float(min(1.3, max(0.35 + 0.4 * curv, pow(nearC / max(1e-4, near(q)), 1.2)))) }   // 外から見る時も、奥の矢印ほど淡く
                    // 急カーブ（曲率半径が小さい所）：矢印を朱色寄りに、二重の「≫」にして、遠くても小さくはっきり（消えにくく）
                    let tight = smoothstep(0.03, 0.09, bk)
                    if tight > 0 { al = max(al, Float(0.55 * tight * mk.fade * (0.4 + 0.6 * face))) }
                    var colW = curv * wave > 0.3 ? simd_mix(col, SIMD4<Float>(1, 0.95, 0.8, 1), SIMD4(repeating: Float(min(1, curv * wave)))) : col   // 光った矢印は白っぽく
                    if tight > 0 { colW = simd_mix(colW, SIMD4<Float>(1, 0.42, 0.22, 1), SIMD4(repeating: Float(0.65 * tight * (1 - 0.6 * wave)))) }
                    // ほんのり軸の色：粒のある所（4D の x・y・z・w のどの向きに近いか）に合わせて、軸の色を少し混ぜる（進むと色合いがゆっくり移る）
                    if mark == 2 {
                        let p4 = q4 / l, w2 = p4 * p4, ac = Self.axisCol
                        var t: SIMD3<Float> = ac[0] * Float(w2.x)
                        t += ac[1] * Float(w2.y); t += ac[2] * Float(w2.z); t += ac[3] * Float(w2.w)
                        colW = simd_mix(colW, SIMD4(t, 1), SIMD4(repeating: Self.beadAxisTint))
                    } else if mark == 0 && st.planShell {
                        // 矢印：その場所の球殻の色の蛍光色で光る（色をいちばん明るく・あざやかにして、白を少し混ぜた強めの光）
                        let t = Self.shellTint(q4 / l, st.shellModeNow), mx = max(t.x, max(t.y, t.z)), v = t / max(0.001, mx)
                        let gray = (v.x + v.y + v.z) / 3, vivid = simd_clamp(SIMD3(repeating: gray) + (v - SIMD3(repeating: gray)) * 1.6, SIMD3(repeating: 0), SIMD3(repeating: 1))
                        colW = SIMD4(simd_mix(vivid, SIMD3(repeating: 1), SIMD3(repeating: 0.1)), 1); al *= 1.25
                    } else if mark == 0 {
                        // 矢印：手前から奥へ、軸の 4 色（x 赤 → y 緑 → z 青 → w 紫）がほんのりグラデーションでつながる
                        let ac = Self.axisCol, g = min(2.999, max(0, kc * 3)), gi = Int(g), gf = Float(g - Double(gi))
                        let t = simd_mix(ac[gi], ac[gi + 1], SIMD3(repeating: gf))
                        colW = simd_mix(colW, SIMD4(t, 1), SIMD4(repeating: Self.beadAxisTint))
                    }
                    if march { colW = simd_mix(colW, SIMD4<Float>(1, 1, 1, 1), SIMD4(repeating: Float(0.06 + 0.9 * neon))) }   // 寄った時：ふだんから少し白く光り、光が来た所はしっかり白く
                    if al > 0.01 {
                        // 大きさの遠近：寄った時は 3D のまま。外から見る時も、彗星より手前の矢印ほど大きく、奥ほど小さく（少し強めに）
                        //   外から見る時（左上の地図など）：矢印は 3D でだいたい同じ大きさの物として（彗星のそばの大きさがもと）、カメラから遠いほど必ず小さく。
                        //   奥の矢印はさらに少し小さく（遠近の演出）。前は 4D の写り方の大きさを使っていて、奥の矢印の方が大きく見えることがあった
                        let deep = pow(min(1, ecd / max(1e-4, simd_length(eye - q))), 0.7)   // 寄った時：カメラから遠いほど、3D の遠近よりさらに小さく
                        var hs = (march ? 0.16 * ecd * max(0.4, deep) : 0.085 * nearC * dive * min(1.8, max(0.3, pow(nearC / max(1e-4, near(q)), 0.6))))   // 矢印は大きさを変えない（光だけが進む。矢印そのものが飛んでいくようには見せない）
                        // カメラのすぐ前に来た矢印（カメラと彗星の間。4D の写り方でカメラの近くへ来る所）：大きくなりすぎず、淡く消す
                        let de = simd_length(eye - q)
                        //   大きさは、道の先へ行くほど必ず小さく（4D の写り方でカメラの近くへ来ても、先の矢印が大きくならない）
                        if march { hs = min(hs, 0.1 * de, 0.16 * ecd / (1 + 1.2 * k)); al *= Float(smoothstep(0.35 * ecd, 0.75 * ecd, de)) }
                        // 矢印は S³ の上に寝かせる：進む向き t4 と横の向き n4（どちらも 4D の、その点の接する向き）で形を作って、画面の 3 次元へ写す。
                        //   写した形のゆがみ（見る角度で斜めにつぶれる・伸びる）はそのまま、大きさだけ hs にそろえる
                        let p4 = q4 / l
                        var t4 = pl[min(pl.count - 1, j)] - pl[j - 1]; t4 -= p4 * simd_dot(t4, p4)
                        let tl4 = simd_length(t4)
                        if tl4 > 1e-12 {
                            t4 /= tl4
                            // 横の向き n4：その点の接する向きのうち、進む向きに垂直な 2 つ（e1・e2）を組み合わせて、画面の上でいちばん広く見える向きに
                            //   （横から見て線のようにつぶれない。形のゆがみ・大きさの遠近はそのまま）
                            let e = march ? 0.0005 : 0.01
                            func at(_ v: SIMD4<Double>) -> SIMD3<Double> { place(simd_normalize(p4 + v * e)).0 - q }
                            let ax: [SIMD4<Double>] = [SIMD4(1, 0, 0, 0), SIMD4(0, 1, 0, 0), SIMD4(0, 0, 1, 0), SIMD4(0, 0, 0, 1)]
                            var basis: [SIMD4<Double>] = []
                            for a0 in ax where basis.count < 2 {
                                var v = a0 - p4 * simd_dot(a0, p4) - t4 * simd_dot(a0, t4)
                                for b0 in basis { v -= b0 * simd_dot(v, b0) }
                                let vl = simd_length(v); if vl > 0.3 { basis.append(v / vl) }
                            }
                            var n4 = side4 ?? SIMD4<Double>()
                            if basis.count == 2 && march && mark == 0 { n4 = basis[0] }   // 立体の矢印は横の向きを平行移動で決めるので、ここは何でもよい（計算を省く）
                            else if basis.count == 2 {
                                let xs = at(t4), want = simd_cross(Bv, xs)              // 画面の上で、進む向きに垂直な向き
                                let c1 = simd_dot(at(basis[0]), want), c2 = simd_dot(at(basis[1]), want)
                                if abs(c1) + abs(c2) > 1e-12 { n4 = basis[0] * c1 + basis[1] * c2 }
                            }
                            n4 -= p4 * simd_dot(n4, p4); n4 -= t4 * simd_dot(n4, t4)
                            let nl = simd_length(n4)
                            if nl > 1e-9 {
                                n4 /= nl; side4 = n4
                                var X3 = at(t4), Y3 = at(n4); var k = hs / max(1e-9, max(simd_length(X3), simd_length(Y3)))
                                if march && mark != 0 {                                  // 立体の矢印は道の接線と平行移動で向きを決めるので、前の羽の向きの計算は飛ばす
                                    // 寄った時（ダイブ）：S³ のゆがみは使わず、ふつうの 3D の空間で（向きは画面の上の道の向き、大きさは 3D の距離だけで決まる）
                                    var xs = simd_normalize(X3)
                                    // 先読み：矢印は、少し先（S³ の上で 0.05 先）の道の所を指す（曲がる手前から、曲がる側へ向いて導く）
                                    let (qa4, _) = seg(min(total, d + 0.08)), qal = simd_length(qa4)
                                    if qal > 1e-9 { var ch = place(qa4 / qal).0 - q; ch -= Bv * simd_dot(ch, Bv); if simd_length(ch) > 1e-9 { xs = simd_normalize(xs * 0.3 + simd_normalize(ch) * 0.7) } }
                                    // 強く導く：引っぱる所より手前の矢印は、その点へまっすぐ向く（一直線に引っぱられる）。その先は道の向き
                                    if let ap = aimP, d < dAim - 0.01 {
                                        var tv = ap - q; tv -= Bv * simd_dot(tv, Bv)
                                        if simd_length(tv) > 1e-9 { xs = simd_normalize(tv) }
                                    }
                                    if let cx = cX {
                                        // 先導の重み：彗星のすぐ前（S³ の上で 0.04 まで）で、今の向きから引っぱる向きへ切りかわる（変化はそこで終わる）
                                        let wgt = smoothstep(0, 0.04, d)
                                        let bl = cx * (1 - wgt) + xs * wgt; if simd_length(bl) > 1e-9 { xs = simd_normalize(bl) }
                                        // 先頭（奥）の矢印ほど、今の向きからの変わり方を大きく（変化率が高い。いちばん大きくて 83°）
                                        let cy = simd_cross(Bv, cx), th = atan2(simd_dot(xs, cy), simd_dot(xs, cx)), th2 = max(-1.45, min(1.45, th * (1 + 1.5 * kc)))
                                        xs = simd_normalize(cx * cos(th2) + cy * sin(th2))
                                    }
                                    // 向きの変わり方はアナログ（道の向きからのずれを、矢印ごとにスピードメーターの針のようなばねで追う。すっと動いて少し行き過ぎ、ふわっと止まる）
                                    var xp = X3 - Bv * simd_dot(X3, Bv)
                                    if simd_length(xp) > 1e-12 {
                                        xp = simd_normalize(xp)
                                        let yp = simd_cross(Bv, xp), dev = atan2(simd_dot(xs, yp), simd_dot(xs, xp)), key = Int(mk.u.rounded())
                                        var sm = arrowSm[key] ?? (dev, 0, 0, 0); needle(&sm.dev, &sm.dv, dev, mi)
                                        smNew[key] = sm
                                        xs = simd_normalize(xp * cos(sm.dev) + yp * sin(sm.dev))
                                    }
                                    // 横の向き：ふだんは水平（彗星の右の向き）。進む向きに直角にして、「＞」が飛ぶ向きに対して水平に寝る。
                                    //   水平の面がちょうど真横から見える時（線のように細くなる時）は、少しだけ画面の方へ起こす
                                    var ys = simd_cross(Bv, xs)
                                    // 水平の向き：画面から見ていちばん落ち着く水平（画面の上の向きに直角で、進む向きにも直角）。彗星やカメラが回っても、羽がふらつかない。
                                    //   進む向きが画面の上下に近い時（水平が決まらない時）は、画面に向く向きへなめらかに寄せる
                                    //   （進む向きは画面に写す前の 3D の向きで考える。画面に写した向きで考えると、水平が奥行きの向きになって羽が線のように細くなる）
                                    let F3 = simd_length(X3) > 1e-12 ? simd_normalize(X3) : xs
                                    let hz = simd_cross(F3, Uv3), hl = simd_length(hz)
                                    if hl > 1e-6 {
                                        var h = hz / hl; h -= xs * simd_dot(h, xs)
                                        if simd_length(h) > 1e-6 {
                                            h = simd_normalize(h)
                                            let f = simd_normalize(ys), face = abs(simd_dot(simd_cross(xs, h), Bv))   // 羽の面がどれだけ画面に向いているか
                                            let ok = smoothstep(0.04, 0.14, face) * smoothstep(0.1, 0.3, hl)   // ほとんど真横から見える時だけ起こす（ふだんは水平に寝かせる）
                                            let b = h * ok + f * (1 - ok) * (simd_dot(h, f) >= 0 ? 1 : -1)
                                            if simd_length(b) > 1e-9 { ys = simd_normalize(b) }
                                        }
                                    }
                                    // 水平の軸はゆっくり追いかける：羽の傾き（進む向きのまわりの回り）を、羽ごとにばねでなめらかに（急な切りかえで軸がふらつかない）。
                                    //   羽は左右対称なので、半回転（π）ちがいは同じ傾きとして扱う
                                    let r0 = simd_cross(Bv, xs)
                                    if simd_length(r0) > 1e-9 {
                                        let r0n = simd_normalize(r0), n0 = simd_cross(xs, r0n), rk = Int(mk.u.rounded())
                                        var phi = atan2(simd_dot(ys, n0), simd_dot(ys, r0n))
                                        var rs = arrowRoll[rk] ?? (phi, 0)
                                        while phi - rs.r > .pi / 2 { phi -= .pi }
                                        while phi - rs.r < -.pi / 2 { phi += .pi }
                                        let w = 3.5, nn = max(1, Int(ceil(dtA / 0.008))), hh = dtA / Double(nn)
                                        for _ in 0..<nn { rs.v += (w * w * (phi - rs.r) - 2 * w * rs.v) * hh; rs.r += rs.v * hh }
                                        rollNew[rk] = rs
                                        ys = r0n * cos(rs.r) + n0 * sin(rs.r)
                                    }
                                    let yl = simd_length(ys)
                                    if yl > 1e-9 { X3 = xs; Y3 = ys / yl; k = hs }
                                }
                                let bendHere = max(bend[max(0, j - 1)], bend[min(pl.count - 1, j)])
                                var ang = 0.0, bankOnly = 0.0
                                // くるっと回すのはやめた（速すぎて点滅に見える）。代わりに、いちばんきつく曲がる所の矢印は、車の方向指示器のように
                                //   ゆっくりやわらかく明るくなったり暗くなったりする（1 秒に 1 回ほど。「こっちへ曲がりますよ」）
                                if curv > 0.3 && bendMax > 0.006 && bendHere > 0.6 * bendMax {
                                    let blink = 0.5 + 0.5 * sin(now * 2 * .pi * 1.0)              // そろって明るくなる（ずらすと流れて見える）
                                    al *= Float(0.55 + 0.75 * blink * blink)
                                }
                                // 3D の傾き（ダイブ）：飛行機が曲がる時のように、矢印をその所の曲がりへ傾ける。曲がり具合は少し手前と少し先の道の向きの差
                                //   （その矢印の所の曲がりに合わせるので、軌道が少しずつちがう矢印が、なめらかにつながって傾く）
                                // 奥の小さな板（カメラ距離の 6 倍より遠い立体の矢印）は、曲がる所の傾きを求めない（見た目では分からない。計算を省く）
                                if march && !(mark == 0 && simd_length(eye - q) > 6 * ecd) {
                                    func dir(_ dd: Double) -> SIMD3<Double>? {
                                        let (a4, _) = seg(max(0, min(total, dd))), b4 = seg(max(0, min(total, dd + 0.01))).0, la = simd_length(a4), lb = simd_length(b4)
                                        guard la > 1e-9, lb > 1e-9 else { return nil }
                                        var v = place(b4 / lb).0 - place(a4 / la).0; v -= Bv * simd_dot(v, Bv); let l = simd_length(v); return l > 1e-12 ? v / l : nil
                                    }
                                    if let t0 = dir(d - 0.03), let t1 = dir(d + 0.03) {
                                        // 傾く大きさは S³ の上で本当に曲がる量で（まっすぐな道は、4D の写り方で曲がって見えても傾けない）。向き（左右）だけ画面の上で決める
                                        let turnS = atan2(simd_dot(simd_cross(t0, t1), Bv), simd_dot(t0, t1))
                                        var g = 0.0; for t in max(1, j - 2)...min(pl.count - 2, j + 2) { g = max(g, bend[t]) }
                                        let turnG = g * 3                                                  // 0.06 進む間に曲がる角度（1 点 0.02 ごとの角度 × 3）
                                        let bk = max(-1.1, min(1.1, -(turnS >= 0 ? 1 : -1) * turnG * 6))
                                        let key = Int(mk.u.rounded())                                     // 傾きも針のようなばねで
                                        var sm = smNew[key] ?? arrowSm[key] ?? (0, bk, 0, 0); needle(&sm.bank, &sm.bv, bk, mi); smNew[key] = sm
                                        ang += sm.bank * smoothstep(0.08, 0.45, kc)                        // 近くの羽ほど水平のまま（動きが少ない）
                                        bankOnly = 0.6 * ang                                               // 立体の矢印は、曲がる所でこの傾きだけ（少し控えめに）
                                        // 遠くの羽は、ときどきくるんとひっくり返って戻る（7 秒ごとに 2.6 秒かけて。サインカーブでやわらかく。遠いほど大きく）
                                        let ft = now.truncatingRemainder(dividingBy: 7.0)
                                        if ft < 2.6 { let fw = smoothstep(0.55, 0.9, kc); ang += fw * .pi * pow(sin(.pi * ft / 2.6), 2) }
                                        // メビウスの輪のように、先へ行くほど少しずつよじれる（手前は水平、見える所の先までで半回転）。
                                        //   よじれは彗星からの道のり（並びの位置 kc）で決まるので、羽が近づくにつれて、なめらかにほどけて水平になる
                                        ang += .pi * smoothstep(0.08, 0.95, kc)
                                    }
                                }
                                if ang != 0 {
                                    let lx = simd_length(X3), ly = simd_length(Y3)
                                    if lx > 1e-12 && ly > 1e-12 {
                                        let xh = X3 / lx, yh = Y3 / ly, zh = simd_normalize(simd_cross(xh, yh))
                                        Y3 = (yh * cos(ang) + zh * sin(ang)) * ly
                                    }
                                }
                                // 矢印は「»」の 1 つを前後に引きのばした形（形はシェーダーの kind 12。q.xy：板の上の位置）
                                func chevron(_ ox: Double, _ a: Float) {
                                    let x0 = -0.4 - 0.2, x1 = 0.58 + 0.2, y1 = 0.6
                                    func cv(_ x: Double, _ y: Double) -> HLCometVert {
                                        HLCometVert(p: SIMD4(SIMD3<Float>(q + X3 * ((x + ox) * k) + Y3 * (y * k)), 1), q: SIMD4(Float(x), Float(y), 12, a), c: colW)
                                    }
                                    ctri += [cv(x0, -y1), cv(x1, -y1), cv(x1, y1), cv(x0, -y1), cv(x1, y1), cv(x0, y1)]
                                }
                                if mark == 0 && march && j < nf.count {
                                    // 寄った時：厚みのある立体の「»」。前の向きは道の線の接線、横の向きは平行移動で運んだ向き。
                                    //   面ごとの明るさ（カメラの左上手前からの光、やわらかく）で立体に見せる。色は青白にほんのり軸の色。カメラから見えない裏の面は描かない
                                    // 前の向き：画面に描かれた道の線の接線（道の点を 3D へ写した曲線を微分した向き。すぐ前とすぐ後ろの点の差で）。
                                    //   矢印の中心の軸が道の線に乗り、線が曲がって見える所でも線に沿ってそろう（導く向きへ回すのは、立体の矢印ではしない）
                                    let qa4 = seg(max(0, d - 0.004)).0, qb4 = seg(min(total, d + 0.004)).0
                                    var Xf = place(simd_normalize(qb4)).0 - place(simd_normalize(qa4)).0
                                    if simd_length(Xf) < 1e-12 { Xf = at(t4) }
                                    Xf = simd_normalize(Xf)
                                    // 奥行きの成分だけ弱める（画面の上の向きは接線のまま、線に沿ってそろう）。道が奥へ向かう所でも、後ろから見た細い形にならない
                                    //   （奥行きは、カメラからこの点への見る線の向きで測る。遠近のある画面でも、写った向きが線の接線からずれない）
                                    let ray = simd_normalize(q - eye), dz = simd_dot(Xf, ray); Xf = simd_normalize(Xf - ray * dz * 0.65)
                                    let ca = cum[j - 1], cb = cum[j], fs = cb > ca ? max(0, min(1, (d - ca) / (cb - ca))) : 0
                                    var Yv = at(nf[j - 1] * (1 - fs) + nf[j] * fs); Yv -= Xf * simd_dot(Yv, Xf)
                                    if simd_length(Yv) > 1e-12 {
                                        var Yh = simd_normalize(Yv), Nh = simd_cross(Xf, Yh)
                                        let spin = spinAng
                                        // 鎖全体の回し：いちばん手前の矢印の面が画面に向くように、全部の矢印を同じ角だけ回す（矢印どうしの向きの関係は平行移動のまま）。
                                        //   その角はばねでゆっくり追う。「»」は半回りで同じ形なので、半回りちがいは同じとして扱う
                                        if rollRef == nil {
                                            let want = simd_normalize(simd_cross(simd_normalize(q - eye), Xf))
                                            var phi = atan2(simd_dot(simd_cross(Yh, want), Xf), simd_dot(Yh, want))
                                            var rs = planRoll ?? (phi, 0)
                                            while phi - rs.r > .pi / 2 { phi -= .pi }
                                            while phi - rs.r < -.pi / 2 { phi += .pi }
                                            let w = 2.5, nn = max(1, Int(ceil(dtA / 0.008))), hh = dtA / Double(nn)
                                            for _ in 0..<nn { rs.v += (w * w * (phi - rs.r) - 2 * w * rs.v) * hh; rs.r += rs.v * hh }
                                            if rs.r > 2 * .pi { rs.r -= 2 * .pi } else if rs.r < -2 * .pi { rs.r += 2 * .pi }
                                            planRoll = rs; rollRef = rs.r
                                        }
                                        let rollA = (rollRef ?? 0) + bankOnly + spin
                                        Yh = Yh * cos(rollA) + Nh * sin(rollA); Nh = simd_cross(Xf, Yh)
                                        let toEye = simd_normalize(eye - q), Lt = simd_normalize(Uv3 * 0.7 + toEye * 0.8 + simd_cross(Uv3, toEye) * 0.35)
                                        // 大きさは 3D の遠近だけ：どの矢印も 3D で同じ大きさ（カメラ距離の 0.07）の物として、カメラから遠いほど自然に小さく（手前から奥へ吸い込まれる）。
                                        //   カメラのすぐ前で大きくなりすぎないように。とても遠い所は点ほどに残す
                                        var ks = min(0.07 * ecd, 0.055 * simd_length(eye - q))
                                        ks = max(ks, 0.005 * simd_length(eye - q))
                                        //   道の先の方は 4D の写り方でカメラの方へ戻ってくることがある（3D では近くなって大きく見える）。
                                        //   道の先へ行くほど必ず小さくして、手前から奥へ遠ざかっていく 3D の遠近に見せる
                                        ks = min(ks, ksRun * 0.995); ksRun = ks
                                        //   となりの矢印との 3D の間隔でも抑える（道が 4D の写り方で縮む所では、矢印も一緒に小さく。重なって太い帯に見えない。
                                        //   先へ行くほど細く収束する 1 本の点線に）
                                        ks = min(ks, 0.6 * mk.sp / max(1, mk.dn) * ecd)   // 粗密で詰めた所も重ならない（重なると光が足し合わさって白く色が抜ける）
                                        func V(_ x: Double, _ y: Double, _ z: Double) -> SIMD3<Double> { q + Xf * (x * ks) + Yh * (y * ks) + Nh * (z * ks) }
                                        // ほとんど 2 次元の矢印：薄いカード 1 枚に「»」の形（シェーダーの kind 12、ふちはなめらかで角は丸い）。
                                        //   向き・大きさ・回りは 3D のまま。面の明るさは光の当たり方でやわらかく
                                        // 陰影：2 本の腕を、進む向きのまわりに ±12° だけ折った面と考えて、それぞれの光の当たり方で明るさを変える
                                        let nf2 = simd_dot(Nh, toEye) >= 0 ? Nh : -Nh, fa = 0.21
                                        let nUp = simd_normalize(nf2 * cos(fa) + Yh * sin(fa)), nDn = simd_normalize(nf2 * cos(fa) - Yh * sin(fa))
                                        let bUp = 0.55 + 0.45 * max(0, simd_dot(nUp, Lt)), bDn = 0.55 + 0.45 * max(0, simd_dot(nDn, Lt)), bM = max(bUp, bDn)
                                        let cb = Float(bM)
                                        // 上の腕（シェーダーの y＞0）が明るい方になるように、横の向きを合わせる
                                        let upIsBright = bUp >= bDn
                                        let cw = SIMD4<Float>(colW.x * cb, colW.y * cb, colW.z * cb, Float(min(bUp, bDn) / bM))
                                        func cv2(_ x: Double, _ y: Double) -> HLCometVert { HLCometVert(p: SIMD4(SIMD3<Float>(V(x, upIsBright ? y : -y, 0)), 1), q: SIMD4(Float(x), Float(y), 12, al), c: cw) }
                                        ctri += [cv2(-0.6, -0.6), cv2(0.78, -0.6), cv2(0.78, 0.6), cv2(-0.6, -0.6), cv2(0.78, 0.6), cv2(-0.6, 0.6)]
                                    }
                                } else if mark == 0 {
                                    chevron(0, al)
                                    if tight > 0.2 { chevron(-0.6, al * Float(tight) * 0.85) }   // 急カーブ：少し後ろにもう 1 つ（≫）
                                } else {
                                    // 矢印の代わりに、光のビーズ（画面に向いた光の玉）。進む向きに長い楕円（長い向きが進む向きを教える）。寄った時も外から見る時も。
                                    //   画面に向いているので、向きの軸がふらつかない。外から見る時の大きさは hs（矢印の時と同じくらい）
                                    //   まっすぐな所ほど進む向きに伸びた楕円（勢いよく進む感じ）、曲がる所はまるい玉に縮む
                                    var xv = simd_length(X3) > 1e-12 ? X3 : at(t4); xv -= Bv * simd_dot(xv, Bv)
                                    let xn = simd_length(xv) > 1e-12 ? simd_normalize(xv) : simd_normalize(at(t4))
                                    let sd0 = simd_cross(Bv, xn)
                                    if simd_length(sd0) > 1e-9 {
                                        let sdn = simd_normalize(sd0), kon = mark == 2, ext = 1.9
                                        let rB = kon ? (march ? 0.15 * k : 0.45 * hs) : (march ? 0.13 * k : 0.3 * hs), el = kon ? 1 : 1 + (Self.beadStretch - 1) * (1 - curv)
                                        // 金平糖：まるいまま、ゆっくりくるくる回る（粒ごとに回り始めをずらす）
                                        let spin = kon ? now * 0.7 + mk.u * 1.3 : 0, ax = xn * cos(spin) + sdn * sin(spin), ay = sdn * cos(spin) - xn * sin(spin)
                                        let kind: Float = kon ? 16 : 15
                                        func bv(_ x: Double, _ y: Double) -> HLCometVert {
                                            HLCometVert(p: SIMD4(SIMD3<Float>(q + ax * (x * rB * el) + ay * (y * rB)), 1), q: SIMD4(Float(x), Float(y), kind, al), c: colW)
                                        }
                                        ctri += [bv(-ext, -ext), bv(ext, -ext), bv(ext, ext), bv(-ext, -ext), bv(ext, ext), bv(-ext, ext)]
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
        let teal = SIMD3<Float>(0.06, 0.76, 0.94), ice = SIMD3<Float>(1.0, 0.93, 0.78)   // さんぽの印は青緑。彗星の頭は暖かい白（水色の殻に埋もれない）
        let discs: [(Double, SIMD4<Float>)] = real ? [] : comet
            ? [(0.085 * sc, SIMD4(ice, 0.28 * vis)), (0.045 * sc, SIMD4(ice, 0.8 * vis)), (0.022 * sc, SIMD4(1, 1, 1, vis))]   // 彗星の頭（玉より小さめ）
            : [(0.20 * sc, SIMD4(teal, 0.16 * vis)), (0.085 * sc, SIMD4(teal, vis)), (0.042 * sc, SIMD4(1, 1, 1, vis))]
        func rim(_ a: Double, _ rad: Double) -> SIMD3<Double> { let d: SIMD3<Double> = ax * cos(a) + ay * sin(a); return c + d * rad }
        for (rad, col) in discs {
            for k in 0..<24 {
                let a0 = Double(k) / 24 * 2 * .pi, a1 = Double(k + 1) / 24 * 2 * .pi
                for q in [c, rim(a0, rad), rim(a1, rad)] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
            }
        }
        // 地図で赤玉と紫玉が重なる時：2 つの色の円が近づいて、重なった所が白く光る（暗い背景なので、乗算ではなく光の足し算のように）
        if overview && st.overlapGlow {
            let pa = walkPlace(SIMD4(0, 0, 0, 1)).0, pk = walkPlace(SIMD4(0, 0, 0, -1)).0, r0 = 0.22 * Self.R * Self.SCALE
            let dd = simd_length(pa - pk), o = max(0, 1 - dd / (2 * r0)), ok = smoothstep(0, 0.25, o)
            if ok > 0.01 {
                func soft(_ ctr: SIMD3<Double>, _ rad: Double, _ col: SIMD3<Float>, _ am: Float) {
                    for (ra, aa) in [(1.0, 0.25), (0.8, 0.3), (0.6, 0.35)] as [(Double, Float)] {
                        for k in 0..<48 {
                            let a0 = Double(k) / 48 * 2 * .pi, a1 = Double(k + 1) / 48 * 2 * .pi
                            let e0: SIMD3<Double> = ax * cos(a0) + ay * sin(a0), e1: SIMD3<Double> = ax * cos(a1) + ay * sin(a1)
                            let q1: SIMD3<Double> = ctr + e0 * (rad * ra), q2: SIMD3<Double> = ctr + e1 * (rad * ra)
                            for q in [ctr, q1, q2] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: SIMD4(col, am * aa))) }
                        }
                    }
                }
                soft(pk, r0, SIMD3(0.72, 0.3, 1.0), Float(ok))
                soft(pa, r0, SIMD3(1.0, 0.22, 0.2), Float(ok))
                soft((pa + pk) / 2, r0 * (0.2 + 0.75 * o), SIMD3(1.0, 0.92, 0.95), Float(o * 1.6))
            }
        }
        if !comet && overview && st.autoCam && st.diveT > 0.3 && simd_length(st.camTan) > 0.5 {   // オートカメラの視点：カメラのいる方向の外に白い三角（中心を指す）。カメラが手前の側なら濃く、奥の側なら薄く
            let d3 = place(simd_normalize(pos + st.camTan * 0.03)).0 - c
            let dx = simd_dot(d3, ax), dy = simd_dot(d3, ay), dl = (dx * dx + dy * dy).squareRoot()
            if dl > 1e-9 {
                let ux: SIMD3<Double> = ax * (dx / dl) + ay * (dy / dl), px: SIMD3<Double> = ay * (dx / dl) - ax * (dy / dl)
                let col = SIMD4<Float>(1, 1, 1, (simd_dot(d3, fw) > 0 ? 0.95 : 0.5) * vis)
                let tip: SIMD3<Double> = c + ux * (0.215 * sc), base: SIMD3<Double> = c + ux * (0.35 * sc), half: SIMD3<Double> = px * (0.085 * sc)
                let tq: [SIMD3<Double>] = [tip, base + half, base - half]
                for q in tq { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
            }
        }
        if !comet {                                                     // さんぽの印の三重の輪：外は青緑、内は白
            for (r0, r1, col) in [(0.165 * sc, 0.19 * sc, SIMD4(teal, 0.95 * vis)), (0.112 * sc, 0.128 * sc, SIMD4<Float>(1, 1, 1, 0.9 * vis))] {
                for k in 0..<48 {
                    let a0 = Double(k) / 48 * 2 * .pi, a1 = Double(k + 1) / 48 * 2 * .pi
                    for q in [rim(a0, r0), rim(a0, r1), rim(a1, r1), rim(a0, r0), rim(a1, r1), rim(a1, r0)] { tri.append(HLVert(p: SIMD4(SIMD3<Float>(q), 1), n: .zero, c: col)) }
                }
            }
        }
        var u = u0; u.model = matrix_identity_float4x4; u.g.z = 0
        if !tri.isEmpty {
            e.setRenderPipelineState(alphaPipe); e.setDepthStencilState(depthAlways)
            tri.withUnsafeBytes { b in
                if b.count <= 4096 { e.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) }
            }
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: tri.count)
        }
        if !ctri.isEmpty {                                              // 光の彗星：足し合わせ（重なるほど明るく、白く飛ぶ）
            e.setRenderPipelineState(cometPipe); e.setDepthStencilState(depthAlways)
            ctri.withUnsafeBytes { b in
                if b.count <= 4096 { e.setVertexBytes(b.baseAddress!, length: b.count, index: 0) }
                else if let buf = device.makeBuffer(bytes: b.baseAddress!, length: b.count, options: .storageModeShared) { e.setVertexBuffer(buf, offset: 0, index: 0) }
            }
            var tm = SIMD4<Float>(Float(nowT.truncatingRemainder(dividingBy: 1000)), Float(st.cometSpd), 0, 0)   // y：彗星の速さ（派手さ）
            e.setVertexBytes(&u, length: MemoryLayout<HLUni>.stride, index: 1); e.setFragmentBytes(&tm, length: 16, index: 2)
            e.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: ctri.count)
        }
    }
    /// 寄った時の矢印の間隔（S³ の道のり）。ショーカメラが引いても広げない（直線で矢印がまばらになると、速さが見えなくなる）
    static func arrowGap(ecd: Double, showK: Double, m0: Double) -> Double { max(0.004, 0.37 * ecd / max(0.2, showK) / max(1e-6, m0)) }
    /// S³ の上で道が本当に曲がる角度（点 p で、a から来て b へ行く。大円＝S³ のまっすぐな道なら 0）。
    ///   となりの弦どうしの角度は、まっすぐな道でも歩幅ぶん（0.02 なら 0.02 rad）出てしまうので、p の接する向きにしてから比べる
    static func geoTurn(_ a: SIMD4<Double>, _ p: SIMD4<Double>, _ b: SIMD4<Double>) -> Double {
        let ta = a - p * simd_dot(a, p), tb = b - p * simd_dot(b, p), la = simd_length(ta), lb = simd_length(tb)
        guard la > 1e-12, lb > 1e-12 else { return 0 }
        return acos(max(-1, min(1, -simd_dot(ta, tb) / (la * lb))))
    }
}
